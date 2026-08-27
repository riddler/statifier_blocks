if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.PaletteBrowser do
    @moduledoc """
    The grouped, searchable, filterable palette (ADR-0005 decisions 8, 10, 13).

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

    Picking an entry emits an `:insert` at exactly the position the "+" named,
    which is the identical command a successful drop would produce. That is
    what makes the whole insertion path exercisable in `LiveViewTest` without
    simulating a drag, and it is why decision 8 is not only an accessibility
    affordance - though it is that, drag-and-drop being unusable by keyboard
    and hostile on touch.
    """

    use Phoenix.Component

    alias StatifierBlocks.ViewModel

    attr(:groups, :list, required: true)
    attr(:query, :string, default: "")

    attr(:allowed, :any,
      default: nil,
      doc: "MapSet of accepted type names, or nil for unfiltered."
    )

    attr(:target, :any, required: true)
    attr(:icon, :any, default: nil)
    attr(:class, :string, default: nil)

    @doc "The palette: a search box, then a section per `entry.group`."
    def palette_browser(assigns) do
      assigns = assign(assigns, :visible, filter(assigns.groups, assigns.query, assigns.allowed))

      ~H"""
      <section class={["sb-palette", @class]} data-filtered={to_string(@allowed != nil)}>
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

        <p :if={@visible == []} class="sb-palette__empty">No block types match.</p>

        <div :for={group <- @visible} class="sb-palette__group" data-group={group.name}>
          <h3 class="sb-palette__group-name">{group.name}</h3>
          <ul class="sb-palette__entries">
            <li :for={entry <- group.entries} data-type={entry.type_name}>
              <button
                type="button"
                class="sb-palette__pick"
                phx-click="palette-pick"
                phx-target={@target}
                phx-value-type={entry.type_name}
              >
                {entry.entry.label}
                <span :if={entry.entry.description != ""} class="sb-palette__description">
                  {entry.entry.description}
                </span>
              </button>
            </li>
          </ul>
        </div>
      </section>
      """
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
