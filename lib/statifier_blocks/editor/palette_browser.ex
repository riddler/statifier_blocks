if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.PaletteBrowser do
    @moduledoc """
    The grouped, searchable, filterable palette (ADR-0005 decisions 8, 10, 13).

    ## The entry's icon

    An entry renders the tile the card it produces will carry, resolved by the
    same seam and through the same `icon` assign - `Editor` hands this
    component and `Editor.BlockNode` the identical value. The tile was declared
    here and rendered nowhere for the whole of the graduated editor's life
    (`sb-jja`), so a host could not put an icon on a palette row at all; a
    palette that showed no icons above a canvas that did was the visible half
    of that.

    Everything it renders comes from `palette_entry/0` through
    `StatifierBlocks.ViewModel`, which already applied decision 10's defaults -
    `label` to the type name, `group` to `"Other"`, `description` to `""`,
    `icon` to `nil`, `keywords` to `[]`, `order` to `0`. A block type that
    implements none of the callback still renders here, and ADR-0002 decision
    5 promised it would.

    Two filters compose, and they are different in kind:

      * **Search** is the author's, over label, description, type name and
        `keywords`. Purely presentational.
      * **Acceptance** is the slot's. When the palette was opened from a
        specific gap, `allowed` carries the type names that slot will take,
        computed by `StatifierBlocks.Editor` with the *same* predicate a drag
        uses - `Edit.Targets.droppable_slots_for/3` against a probe block of
        each candidate type. Decision 8 is explicit that the filter uses the
        same predicate as decision 5, not a parallel implementation, and this
        component deliberately computes none of it: it is handed a set.

    ## What a row says, and what the count line says (parity item 1.3)

    A row is the tile, the label, and the one-line description the type
    declared - three things, not one, because the label alone answers "what is
    this called" and never "what would it do". The tile is a slot rather than
    an icon: a type that named none still renders the box, so the column of
    names lines up whether or not every type in a host's registry got around
    to declaring a glyph.

    Above the groups sits one line of arithmetic. Unfiltered it is the size of
    the palette; filtered it is how much of the palette is left and why. The
    "why" matters more than it looks: two different filters can be narrowing
    this list - the author's query and the slot's acceptance set - and an
    author who opened the palette from a gap never typed anything, so a line
    that only ever explained queries would leave the more confusing of the two
    cases unexplained.

    The per-group count is the same idea one level down, and it is the count
    of what is *under that header now*, not of the group in the registry.

    ## The strip, below 780 (7A)

    The 2026-08-29 shell amendment gives the palette a second shape: below a
    container width of 780 it collapses to a strip - a label and a "+" - that
    opens as a sheet over the canvas, so the inspector gets the full row. Both
    shapes are always in the markup and the **stylesheet** decides which one is
    on screen, because the breakpoint is a container query and the server does
    not know how wide the host gave the editor. What the server owns is whether
    the sheet is open, which is one boolean and one event; selecting a block or
    picking an entry closes it, since a sheet left open covers the thing the
    author just chose.

    ## The pane header, and the collapse (parity item 1.1)

    Above the strip and the body sits the pane's own header row: the name of
    the pane, and a chevron that folds it. It is the palette's half of the
    frame the spike gives both side panes, and 8A puts it on the package's
    side of the split - it operates on the document that is open rather than
    deciding which one is.

    The collapse is a server-side command in the same shape everything else in
    the shell amendment uses: one boolean on the editor, one event, no hook.
    Collapsed, the body goes with `display: none` rather than a zero width, so
    a folded pane is out of the tab order and out of the accessibility tree -
    a pane an author can still Tab into is a pane that reads as broken to
    everyone not using a mouse. The chevron stays, because it is the way back.

    The header belongs to the **wide** arrangement. Below 780 the strip (7A)
    is the palette's whole chrome and the stylesheet puts the header away:
    two stacked headers is one more than a one-column arrangement has room
    for, and the collapse has nothing to fold there - the body is already a
    sheet.

    Picking an entry emits an `:insert` at exactly the position the "+" named,
    which is the identical command a successful drop would produce. That is
    what makes the whole insertion path exercisable in `LiveViewTest` without
    simulating a drag, and it is why decision 8 is not only an accessibility
    affordance - though it is that, drag-and-drop being unusable by keyboard
    and hostile on touch.
    """

    use Phoenix.Component

    alias StatifierBlocks.Editor.Icons
    alias StatifierBlocks.ViewModel

    attr(:groups, :list, required: true)
    attr(:query, :string, default: "")

    attr(:allowed, :any,
      default: nil,
      doc: "MapSet of accepted type names, or nil for unfiltered."
    )

    attr(:target, :any, required: true)

    attr(:icon, :any,
      default: nil,
      doc: """
      The host's icon component, or nil for `StatifierBlocks.Editor.Icons`.
      The same value the canvas cards get, so a type looks the same before and
      after the pick that puts it in the document.
      """
    )

    attr(:class, :string, default: nil)

    attr(:sheet_open, :boolean,
      default: false,
      doc: "Whether the narrow-layout sheet is open (7A). Ignored above 780."
    )

    attr(:collapsed, :boolean,
      default: false,
      doc: """
      Whether the pane is folded to its header. The wide arrangement's
      affordance; below 780 the strip is the palette's chrome and this is
      ignored.
      """
    )

    attr(:insert_target, :any,
      default: nil,
      doc: """
      Where an armed pick would land, as `%{slot: label, parent: title}`, or
      nil when nothing is armed. `StatifierBlocks.Shell.insert_target/2`
      computes it; this component only prints it.
      """
    )

    attr(:unarmed_pick, :boolean,
      default: false,
      doc: """
      Whether the last pick was made with nothing armed, and so did nothing.
      The visible half of that no-op.
      """
    )

    @doc """
    The palette: a header row, a search box, a count line, then a section per
    `entry.group`.
    """
    def palette_browser(assigns) do
      visible = filter(assigns.groups, assigns.query, assigns.allowed)

      assigns =
        assigns
        |> assign(:visible, visible)
        |> assign(:count, count_line(assigns.groups, visible, assigns.query))
        |> assign(:filtering, narrowed?(assigns.groups, visible, assigns.query))

      ~H"""
      <section
        class={["sb-palette", @class]}
        data-filtered={to_string(@allowed != nil)}
        data-sheet={if @sheet_open, do: "open", else: "closed"}
        data-collapsed={to_string(@collapsed)}
        data-inserting={to_string(@insert_target != nil)}
      >
        <div class="sb-palette__header">
          <h2 class="sb-palette__title">Palette</h2>
          <button
            type="button"
            class="sb-palette__toggle"
            phx-click="palette-collapse"
            phx-target={@target}
            aria-expanded={to_string(not @collapsed)}
            aria-label={if @collapsed, do: "Expand the palette", else: "Collapse the palette"}
            title={if @collapsed, do: "Expand the palette", else: "Collapse the palette"}
          ></button>
        </div>

        <button
          type="button"
          class="sb-palette__strip"
          phx-click="palette-sheet"
          phx-target={@target}
          aria-expanded={to_string(@sheet_open)}
        >
          <span class="sb-palette__strip-label">Blocks</span>
          <span class="sb-palette__strip-plus" aria-hidden="true">+</span>
        </button>

        <div class="sb-palette__body">
          <p :if={@insert_target} class="sb-palette__mode" role="status">
            <span class="sb-palette__mode-text">
              Pick a block to insert into
              <strong class="sb-palette__mode-slot">{@insert_target.slot}</strong>
              of <strong class="sb-palette__mode-parent">{@insert_target.parent}</strong>
            </span>
            <button
              type="button"
              class="sb-button sb-palette__cancel"
              phx-click="palette-close"
              phx-target={@target}
            >
              Cancel
            </button>
          </p>

          <p
            :if={@insert_target == nil and @unarmed_pick}
            class="sb-palette__mode sb-palette__mode--unarmed"
            role="status"
          >
            <span class="sb-palette__mode-text">
              Nothing is armed, so that pick had nowhere to go. Choose a "+" on the canvas first.
            </span>
          </p>

          <form
            id="sb-palette-search"
            phx-change="palette-search"
            phx-submit="palette-search"
            phx-target={@target}
          >
            <input
              class="sb-palette__search"
              type="text"
              name="q"
              value={@query}
              placeholder="Search blocks"
              autocomplete="off"
            />
          </form>

          <p class="sb-palette__count" role="status" data-filtering={to_string(@filtering)}>
            {@count}
          </p>

          <p :if={@visible == []} class="sb-palette__empty">No block types match.</p>

          <div :for={group <- @visible} class="sb-palette__group" data-group={group.name}>
            <h3 class="sb-palette__group-name">
              <span>{group.name}</span>
              <span class="sb-palette__group-count">{length(group.entries)}</span>
            </h3>
            <ul class="sb-palette__entries">
              <li :for={entry <- group.entries} data-type={entry.type_name}>
                <button
                  type="button"
                  class="sb-palette__pick"
                  data-sb-block-accent={ViewModel.accent_token(entry.entry)}
                  style={accent_style(entry.entry)}
                  phx-click="palette-pick"
                  phx-target={@target}
                  phx-value-type={entry.type_name}
                >
                  <span class="sb-palette__icon">
                    <Icons.glyph icon={@icon} name={entry.entry.icon} class="sb-palette__glyph" />
                  </span>
                  <span class="sb-palette__text">
                    <span class="sb-palette__name">{entry.entry.label}</span>
                    <span :if={entry.entry.description != ""} class="sb-palette__description">
                      {entry.entry.description}
                    </span>
                  </span>
                </button>
              </li>
            </ul>
          </div>
        </div>
      </section>
      """
    end

    # The count line, under the search box. Two numbers, and which one is on
    # screen is the whole design: an author who has filtered wants to know how
    # much of the palette they are still looking at, and one who has not wants
    # to know how big it is. The first two arms are the spike's wording. The
    # third is the case the spike does not have, because it has no acceptance
    # filter: the palette opened from a gap is narrowed by the slot rather than
    # by anything the author typed, and a bare total there would claim the
    # author can reach types this gap will not take.
    @spec count_line([ViewModel.PaletteGroup.t()], [ViewModel.PaletteGroup.t()], String.t()) ::
            String.t()
    defp count_line(groups, visible, query) do
      total = entry_count(groups)
      shown = entry_count(visible)
      needle = query |> to_string() |> String.trim()

      cond do
        needle != "" -> ~s(#{shown} of #{total} match "#{needle}")
        shown < total -> "#{shown} of #{total} fit here"
        total == 1 -> "1 block type"
        true -> "#{total} block types"
      end
    end

    # Whether anything is narrowing the list, by either of the two filters.
    # The attribute is what lets the stylesheet lift the line out of the
    # subtle step when it is reporting a filter rather than a size.
    @spec narrowed?([ViewModel.PaletteGroup.t()], [ViewModel.PaletteGroup.t()], String.t()) ::
            boolean()
    defp narrowed?(groups, visible, query) do
      String.trim(to_string(query)) != "" or entry_count(visible) < entry_count(groups)
    end

    @spec entry_count([ViewModel.PaletteGroup.t()]) :: non_neg_integer()
    defp entry_count(groups), do: Enum.reduce(groups, 0, &(length(&1.entries) + &2))

    # The palette row carries the same accent as the card the pick produces,
    # so a block type's identity is the same before and after it is in the
    # document. See `StatifierBlocks.Editor.BlockNode` for the seam.
    @spec accent_style(map()) :: String.t() | nil
    defp accent_style(entry) do
      case ViewModel.accent_token(entry) do
        nil -> nil
        name -> "--sb-block-accent: var(#{name}, var(--sb-accent))"
      end
    end

    @doc """
    The groups a query and an acceptance set leave visible, with empty groups
    dropped. Pure, so the palette's filtering is asserted directly rather than
    through markup.
    """
    @spec filter([ViewModel.PaletteGroup.t()], String.t(), MapSet.t(String.t()) | nil) ::
            [ViewModel.PaletteGroup.t()]
    def filter(groups, query, allowed) do
      needle = query |> to_string() |> String.trim() |> String.downcase()

      groups
      |> Enum.map(fn %ViewModel.PaletteGroup{} = group ->
        %{group | entries: Enum.filter(group.entries, &visible?(&1, needle, allowed))}
      end)
      |> Enum.reject(&(&1.entries == []))
    end

    @spec visible?(ViewModel.PaletteGroup.entry(), String.t(), MapSet.t(String.t()) | nil) ::
            boolean()
    defp visible?(entry, needle, allowed) do
      accepted?(entry, allowed) and matches?(entry, needle)
    end

    @spec accepted?(ViewModel.PaletteGroup.entry(), MapSet.t(String.t()) | nil) :: boolean()
    defp accepted?(_entry, nil), do: true
    defp accepted?(%{type_name: type_name}, allowed), do: MapSet.member?(allowed, type_name)

    @spec matches?(ViewModel.PaletteGroup.entry(), String.t()) :: boolean()
    defp matches?(_entry, ""), do: true

    defp matches?(%{type_name: type_name, entry: entry}, needle) do
      haystack = [type_name, entry.label, entry.description | entry.keywords]
      Enum.any?(haystack, &String.contains?(String.downcase(&1), needle))
    end
  end
end
