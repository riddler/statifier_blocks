if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.Drawer do
    @moduledoc """
    The full-width drawer row (ADR-0005, the 2026-08-29 shell amendment,
    rulings 1A and 2A).

    1A says what belongs here and the test is two words: **tabular** and
    **document-level**. Content that is a grid of rows about the whole document
    goes in the drawer; content about one block does not, whatever its shape.
    Truth tables ship first; fixture runs and the datamodel view have reserved
    places and are not drafted here.

    The measurable reason the drawer exists at all: a truth table for a branch
    in a credit-card processing document is one row per case and one column per
    bound input plus the verdicts, and at the inspector's width it either
    scrolls sideways or inverts its column order to keep the answers on screen.
    The spike did the second and filed the inversion as a readability defect.
    A drawer is as wide as the editor is, which is the axis the table needs.

    ## Never open-or-gone

    2A: collapsed, the drawer is a **strip** carrying a title and a count -
    "Truth tables (3)" - and that is what makes the content discoverable from
    any state rather than only from the affordance that opens it. Opening it
    with no table on the selected block shows the **index page**: the blocks
    that do own one, each of them a jump. That is the whole of the spike's
    cold-start gap, closed.

    The count is the document's, not the selection's. A strip reading `(0)`
    because nothing happens to be selected would tell an author something false
    about their document.

    ## The resize is a command, not a hook

    Decision 7 ships exactly one JavaScript hook and this section adds none.
    The resize is a native range control inside a `phx-change` form: the new
    height crosses as an ordinary event, `StatifierBlocks.Shell.clamp_height/1`
    bounds it, and the host stores it - one round trip, and the state that
    matters lives where state already lives. 2A is explicit that the height is
    remembered **per viewer** and that the package has no viewer, so nothing
    here persists anything.
    """

    use Phoenix.Component

    alias StatifierBlocks.Predicates.TruthTable
    alias StatifierBlocks.{Shell, ViewModel}

    attr(:view, :map, required: true, doc: "`StatifierBlocks.Shell.drawer_view/1`'s value")
    attr(:height, :float, required: true)
    attr(:root, ViewModel.Node, required: true)
    attr(:target, :any, required: true)
    attr(:class, :string, default: nil)

    @doc "The drawer row: a strip when collapsed, tabs and a table when open."
    def drawer(assigns) do
      {min, max, _default} = Shell.height_band()
      assigns = assigns |> assign(:min, min) |> assign(:max, max)

      ~H"""
      <section
        class={["sb-drawer", @class]}
        data-open={to_string(@view.open?)}
        data-status={@view.status}
        data-count={@view.count}
        style={"--sb-drawer-height: #{@height}rem"}
      >
        <button
          :if={not @view.open?}
          type="button"
          class="sb-drawer__strip"
          phx-click="drawer-open"
          phx-target={@target}
          aria-expanded="false"
        >
          <span class="sb-drawer__title">{@view.title}</span>
          <span class="sb-drawer__count">({@view.count})</span>
        </button>

        <div :if={@view.open?} class="sb-drawer__frame">
          <div class="sb-drawer__bar">
            <div class="sb-drawer__tabs" role="tablist" aria-label="Drawer">
              <button
                type="button"
                role="tab"
                id="sb-drawer-tab-tables"
                class="sb-drawer__tab sb-drawer__tab--selected"
                aria-selected="true"
                aria-controls="sb-drawer-panel-tables"
                phx-click="drawer-tab"
                phx-value-tab="tables"
                phx-target={@target}
              >
                {@view.title}
                <span class="sb-drawer__count">({@view.count})</span>
              </button>
            </div>

            <form
              id="sb-drawer-resize"
              class="sb-drawer__resize"
              phx-change="drawer-resize"
              phx-submit="drawer-resize"
              phx-target={@target}
            >
              <label class="sb-drawer__resize-label" for="sb-drawer-height">Height</label>
              <input
                id="sb-drawer-height"
                type="range"
                name="height"
                min={@min}
                max={@max}
                step="0.5"
                value={@height}
              />
            </form>

            <button
              type="button"
              class="sb-drawer__close"
              phx-click="drawer-close"
              phx-target={@target}
              aria-expanded="true"
            >
              Collapse
            </button>
          </div>

          <div
            class="sb-drawer__panel"
            role="tabpanel"
            id="sb-drawer-panel-tables"
            aria-labelledby="sb-drawer-tab-tables"
          >
            <p :if={@view.status == :no_fixtures} class="sb-drawer__empty">
              No fixtures source is attached to this editor, so there are no recorded
              cases to show. A host supplies them alongside the document.
            </p>

            <.index_page
              :if={@view.status in [:no_selection, :none_for_block]}
              view={@view}
              root={@root}
              target={@target}
            />

            <.table :for={table <- @view.tables} table={table} />
          </div>
        </div>
      </section>
      """
    end

    attr(:view, :map, required: true)
    attr(:root, ViewModel.Node, required: true)
    attr(:target, :any, required: true)

    # The miss state, as an index rather than as an apology. An open drawer
    # saying only "nothing here" is the affordance that teaches an author to
    # stop opening it; the list of blocks that DO own a table is the thing they
    # were looking for one keystroke ago.
    defp index_page(assigns) do
      ~H"""
      <div class="sb-drawer__index">
        <p class="sb-drawer__empty">
          <span :if={@view.status == :no_selection}>Nothing is selected.</span>
          <span :if={@view.status == :none_for_block}>
            The selected block has no recorded cases.
          </span>
          <span :if={@view.jumps != []}>These blocks do:</span>
          <span :if={@view.jumps == []}>No block in this document has any.</span>
        </p>
        <ul :if={@view.jumps != []} class="sb-drawer__jumps">
          <li :for={id <- @view.jumps}>
            <button
              type="button"
              class="sb-drawer__jump"
              phx-click="select"
              phx-value-block-id={id}
              phx-target={@target}
            >
              {Shell.label_for(@root, id)}
              <span class="sb-drawer__jump-id">{id}</span>
            </button>
          </li>
        </ul>
      </div>
      """
    end

    attr(:table, TruthTable, required: true)

    # One row per case, one column per bound path and then one per arm - the
    # conventional order, which is the order the drawer's width buys back.
    defp table(assigns) do
      ~H"""
      <figure class="sb-table" data-table={@table.name}>
        <figcaption class="sb-table__caption">
          <span class="sb-table__name">{@table.name}</span>
          <span :if={@table.description} class="sb-table__description">{@table.description}</span>
        </figcaption>

        <div class="sb-table__scroll">
          <table>
            <thead>
              <tr>
                <th scope="col">Case</th>
                <th :for={path <- @table.paths} scope="col" data-path={path}>{path}</th>
                <th :for={column <- @table.columns} scope="col" data-column={column.key}>
                  {column.label}
                </th>
              </tr>
            </thead>
            <tbody>
              <tr :for={row <- @table.rows} data-row={row.name}>
                <th scope="row">{row.name}</th>
                <td :for={path <- @table.paths} data-path={path}>
                  {Map.get(row.bindings || %{}, path, "")}
                </td>
                <td
                  :if={row.error}
                  class="sb-table__row-error"
                  colspan={length(@table.columns)}
                  data-status="error"
                >
                  {inspect(row.error)}
                </td>
                <td
                  :for={cell <- if(row.error, do: [], else: row.cells)}
                  data-column={cell.column_key}
                  data-status={cell.status}
                  data-selected={to_string(cell.selected?)}
                >
                  {Shell.cell_word(cell)}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </figure>
      """
    end
  end
end
