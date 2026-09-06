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
      * **Acceptance** is the slot's, and it is two sets because the palette
        has two kinds of row. `allowed` carries the type names that slot will
        take, computed by `StatifierBlocks.Editor` with the *same* predicate a
        drag uses - `Edit.Targets.droppable_slots_for/3` against a probe block
        of each candidate type, whose config since sb-1c7g is the entry's
        `default_config`, so a type refused for a READ rather than for its
        kind is filtered here too. `allowed_recipes` carries the recipe names
        whose arrangement lands at the armed position, which is the recipe's
        own question and not a set of type names (ADR-0005 clause 1C):
        `insert/2` at that position, and `Recipe.within_reach?/2` over what it
        answers with. Decision 8 is explicit that the filter uses the same
        predicate as decision 5, not a parallel implementation, and this
        component deliberately computes neither of them: it is handed the sets.

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

    Wherever that line says "block type" or "fit" it is counting **types
    only**, with the recipes named in a clause of their own. A recipe is not a
    block type (ADR-0005 clause 1C) and no acceptance set can answer for its
    fit, so a single number over both kinds said two untrue things at once: it
    called a recipe a type, and it counted a recipe among the entries the slot
    had accepted.

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

    ## The entry is also a drag source (sb-4nep)

    A row carries `draggable="true"` and `data-sb-drag-type`, which is the
    whole of this component's part in palette drag-to-insert. Dragging a type
    onto a gap and picking it at an armed gap produce the *same* `:insert` at
    the same position, so this is a second gesture onto decision 8's one path
    rather than a second path - the record's command set is untouched, and the
    keyboard route above is unchanged and still the one the tests drive.

    The type name rather than a payload: the server owns what a new block of
    that type is (`Editor.new_block/2` mints the id and the default config at
    gesture time, decision 2), so what crosses the wire is the name the author
    reached for and nothing that would have to be trusted.
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

    attr(:allowed_recipes, :any,
      default: nil,
      doc: """
      MapSet of the recipe names whose arrangement lands at the armed
      position, or nil for unfiltered. Independent of `allowed`: a recipe is
      not a block type, so the two sets are two namespaces (ADR-0005 clause
      1C) and neither answers for the other's kind.
      """
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
      visible = filter(assigns.groups, assigns.query, assigns.allowed, assigns.allowed_recipes)

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
              <li
                :for={entry <- group.entries}
                data-type={entry[:type_name]}
                data-recipe={if entry.kind == :recipe, do: entry.name}
              >
                <button
                  type="button"
                  class="sb-palette__pick"
                  draggable={to_string(entry.kind == :type)}
                  data-sb-drag-type={entry[:type_name]}
                  data-sb-block-accent={ViewModel.accent_token(entry.entry)}
                  style={accent_style(entry.entry)}
                  phx-click="palette-pick"
                  phx-target={@target}
                  phx-value-type={entry[:type_name]}
                  phx-value-recipe={if entry.kind == :recipe, do: entry.name}
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
    #
    # Types and recipes are counted apart wherever the line says "block type"
    # or "fit", because a recipe is not a block type (ADR-0005 clause 1C) and
    # its fit is not the slot's question but its own. A single number over both
    # therefore made two false claims at once - it called a recipe a type, and
    # it counted a recipe among the entries the slot had accepted. The recipes
    # get their own clause rather than disappearing from the line: they are on
    # screen, so a line that did not mention them would be arithmetic an author
    # cannot reconcile with what they are looking at.
    #
    # The fit numbers count what the ARMED SLOT will take, which is the whole
    # of the verdict and not the structural half of it: `allowed` is
    # `Edit.Targets.droppable_slots_for/3` against the insert probe, and since
    # sb-1c7g that probe carries the entry's `default_config`, so a type
    # refused for a read it declares on a config field is outside the
    # numerator exactly as one refused for its kind is. The alternative was to
    # split the line into a structural count and a typed one, and it is the
    # wrong trade for this audience: "fit here" is a promise about what will
    # land when the row is clicked, and one number that keeps that promise
    # beats two numbers that make the author work out which of them did.
    #
    # The query arm keeps one number over both kinds, and that one is true as
    # it stands: matching a search is something a recipe row does exactly as a
    # type row does, and "match" claims nothing about either kind.
    @spec count_line([ViewModel.PaletteGroup.t()], [ViewModel.PaletteGroup.t()], String.t()) ::
            String.t()
    defp count_line(groups, visible, query) do
      total = entry_count(groups)
      shown = entry_count(visible)
      total_types = kind_count(groups, :type)
      shown_types = kind_count(visible, :type)
      recipes = recipe_clause(kind_count(visible, :recipe))
      needle = query |> to_string() |> String.trim()

      cond do
        needle != "" -> ~s(#{shown} of #{total} match "#{needle}")
        shown_types < total_types -> fit_line(shown_types, total_types, recipes)
        total_types == 1 -> "1 block type" <> comma(recipes)
        true -> "#{total_types} block types" <> comma(recipes)
      end
    end

    # The slot-narrowed line. It names "block types" even where the palette
    # registers no recipe at all, because the two numbers are a count of types
    # either way and a line whose subject changed with the host's registry is
    # one an author cannot learn to read. The recipes hang off it behind a
    # semicolon and the word "listed" rather than a comma, so that the sentence
    # about what fits ends before the recipes are named: "N of M block types
    # fit here, and 1 recipe" would read as the recipe fitting too, and at the
    # time it was written a listed recipe had not been asked. It has been since
    # (sb-ym2w): a recipe on screen at an armed slot is one whose arrangement
    # lands there. The wording stays as it is, because "also listed" is still
    # true of such a row and understating what has been checked costs an author
    # nothing, where the old comma overstated it. N and M stand for the two
    # counts this clause computes; no literal total is written here, because
    # the palette's type count moves as the host registers types.
    @spec fit_line(non_neg_integer(), non_neg_integer(), String.t()) :: String.t()
    defp fit_line(shown_types, total_types, ""),
      do: "#{shown_types} of #{total_types} block types fit here"

    defp fit_line(shown_types, total_types, recipes),
      do: "#{shown_types} of #{total_types} block types fit here; #{recipes} also listed"

    @spec comma(String.t()) :: String.t()
    defp comma(""), do: ""
    defp comma(recipes), do: ", " <> recipes

    @spec recipe_clause(non_neg_integer()) :: String.t()
    defp recipe_clause(0), do: ""
    defp recipe_clause(1), do: "1 recipe"
    defp recipe_clause(count), do: "#{count} recipes"

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

    # The same arithmetic over one of the two kinds an entry can be. The kind
    # is on the entry already (`ViewModel.PaletteGroup`), so nothing here has
    # to know which of the palette's two maps a row came out of.
    @spec kind_count([ViewModel.PaletteGroup.t()], ViewModel.PaletteGroup.kind()) ::
            non_neg_integer()
    defp kind_count(groups, kind) do
      Enum.reduce(groups, 0, fn group, count ->
        count + Enum.count(group.entries, &(&1.kind == kind))
      end)
    end

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
    The groups a query and the two acceptance sets leave visible, with empty
    groups dropped. Pure, so the palette's filtering is asserted directly
    rather than through markup.

    `allowed_recipes` defaults to `nil` - unfiltered - so a caller that has
    only the type set, and every existing one did, is unchanged.
    """
    @spec filter(
            [ViewModel.PaletteGroup.t()],
            String.t(),
            MapSet.t(String.t()) | nil,
            MapSet.t(String.t()) | nil
          ) :: [ViewModel.PaletteGroup.t()]
    def filter(groups, query, allowed, allowed_recipes \\ nil) do
      needle = query |> to_string() |> String.trim() |> String.downcase()

      groups
      |> Enum.map(fn %ViewModel.PaletteGroup{} = group ->
        %{
          group
          | entries: Enum.filter(group.entries, &visible?(&1, needle, allowed, allowed_recipes))
        }
      end)
      |> Enum.reject(&(&1.entries == []))
    end

    @spec visible?(
            ViewModel.PaletteGroup.entry(),
            String.t(),
            MapSet.t(String.t()) | nil,
            MapSet.t(String.t()) | nil
          ) :: boolean()
    defp visible?(entry, needle, allowed, allowed_recipes) do
      accepted?(entry, allowed, allowed_recipes) and matches?(entry, needle)
    end

    # Acceptance is the SLOT's, and the two kinds are asked apart because
    # they are asked different questions. A block type is asked of the set of
    # type names the slot takes. A recipe has no type name for such a set to
    # hold (ADR-0005 clause 1C), and whether a "deadline" lands where the
    # author armed is the recipe's own question - `insert/2` answers it, and
    # clause 3C bounds what it may answer with - so `Editor` asks each recipe
    # that question at the position the author armed and hands the answers
    # down as a second set.
    #
    # A recipe used to stay visible everywhere and be refused at the pick,
    # which read as honest and was not: the refusal wrote nothing and said
    # nothing, so a row that could never land looked exactly like one that
    # could until it was clicked, and then still did (sb-ym2w). The same
    # answer given before the click is the one an author can act on.
    #
    # Either set may be `nil`, and `nil` is "nothing is armed" rather than
    # "nothing is accepted" - the unarmed palette shows everything of both
    # kinds.
    @spec accepted?(
            ViewModel.PaletteGroup.entry(),
            MapSet.t(String.t()) | nil,
            MapSet.t(String.t()) | nil
          ) :: boolean()
    defp accepted?(%{kind: :recipe}, _allowed, nil), do: true

    defp accepted?(%{kind: :recipe, name: name}, _allowed, allowed_recipes),
      do: MapSet.member?(allowed_recipes, name)

    defp accepted?(_entry, nil, _allowed_recipes), do: true

    defp accepted?(%{type_name: type_name}, allowed, _allowed_recipes),
      do: MapSet.member?(allowed, type_name)

    @spec matches?(ViewModel.PaletteGroup.entry(), String.t()) :: boolean()
    defp matches?(_entry, ""), do: true

    defp matches?(%{name: name, entry: entry}, needle) do
      haystack = [name, entry.label, entry.description | entry.keywords]
      Enum.any?(haystack, &String.contains?(String.downcase(&1), needle))
    end
  end
end
