if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.Drawer do
    @moduledoc """
    The full-width drawer row (ADR-0005, the 2026-08-29 shell amendment,
    rulings 1A and 2A).

    1A says what belongs here and the test is two words: **tabular** and
    **document-level**. Content that is a grid of rows about the whole document
    goes in the drawer; content about one block does not, whatever its shape.

    Six tabs ship. Truth tables were first. The document-level findings list
    joined them under operator ruling R4 (2026-08-29), which retired the text
    block that used to sit under the canvas: a list of findings is a grid of
    rows about the whole document, so 1A's test admits it and the canvas gets
    its height back. Declarations joined them under the 2026-09-01 amendment
    (clause 2i), which took ADR-0001 11i's named door: the document's own
    `datamodel` roots are a grid of rows about the envelope, which is 1A's
    test again. Fixture runs joined under `sb-4yze`: one row per fixture row
    in the document, each carrying the outcome slot it expected against the
    one the compiled chart actually took (`StatifierBlocks.Runtime.FixtureRuns`
    does the driving; this module only draws the table). The read-only
    declared-path view took the last reserved place: one row per path the
    three declaring surfaces name, with the surfaces that named it and the
    shape the ADR-0006 projection carries, which is a grid of rows about the
    whole document and admitted by 1A for the same reason the four before it
    were. It is read-only on purpose - the editable half is the Declarations
    tab beside it, over the document's own roots - and no reserved place
    remains behind it.

    The measurable reason the drawer exists at all: a truth table for a branch
    in a credit-card processing document is one row per case and one column per
    bound input plus the verdicts, and at the inspector's width it either
    scrolls sideways or inverts its column order to keep the answers on screen.
    The spike did the second and filed the inversion as a readability defect.
    A drawer is as wide as the editor is, which is the axis the table needs.

    ## Never open-or-gone

    2A: collapsed, the drawer is a **strip** carrying a title and a count - a
    small-caps label beside a chip, "Truth tables 3" - and that is what makes
    the content discoverable from any state rather than only from the
    affordance that opens it. Opening it with no table on the selected block
    shows the **index page**: the blocks that do own one, each of them a jump.
    That is the whole of the spike's cold-start gap, closed.

    The strip reports the **active tab**, and an author who has not picked one
    gets the first tab that actually holds something
    (`StatifierBlocks.Shell.drawer_view/1` resolves it). That is 2A's own
    reasoning applied to a second tab: a strip is worth having because it says
    what is in the drawer, and one that names an empty tab while the other has
    four rows in it says the opposite.

    The count is the document's, not the selection's. A strip reading `0`
    because nothing happens to be selected would tell an author something false
    about their document.

    ## A host's own tab

    8A's split is that the package ships the editing surface and the host
    ships what surrounds it. A host tab is that reaching the drawer: the
    editor's `drawer_tabs` assign carries a label, a count and a **function
    component**, the function is called here when its tab is the active one,
    and the package learns nothing about what it draws.

    This admits no new *package* tab. 1A's test - tabular, and about the whole
    document - governs the tabs shipped here, unchanged and unweakened; for a
    tab the host contributes, that test transfers to the host as its own
    obligation. The 2026-08-30 amendment recording the drawer's tab strip as a
    host seam is where that split is written down.

    It is called the way HEEx calls `<.tab />` rather than by applying it to a
    bare map, which is `StatifierBlocks.Editor.Icons`' rule (sb-b8g) and the
    same one for the same reason: a host component that derives a value with
    `assign/3`, which is what an ordinary component does, raises on an assigns
    map with no change-tracking key in it.

    A function rather than a slot, for the reason `StatifierBlocks.Editor`'s
    own moduledoc gives: the first thing a host wants a tab for is a feed of
    something happening now, and a slot body reading a host assign does not
    redraw when that assign moves, because the editor is a `LiveComponent` and
    a slot body is not one of the assigns it was passed. A pushed descriptor
    is.

    ## Host data enters the panel through `assign/2`

    The content function is called with the two assigns this seam has -
    `%{id: ..., count: ...}` - and everything else the panel draws comes from
    the host, out of the closure the descriptor was built with. Getting it
    from the closure into the markup is one line, and which line it is
    matters:

        content: fn assigns -> MyApp.run_feed(assign(assigns, :events, events)) end

    `Map.merge/2` and `Map.put/3` write the same key and are the trap. The
    assigns map that arrives carries a `__changed__` naming the two keys
    *this* call passed, `id` and `count`, because the call is change-tracked
    like any other component call. A merged key is absent from that map, so
    every part of the template that reads it is treated as unchanged and never
    reaches the diff: the panel draws once, holding whatever the closure held
    when the tab was opened, and then stands still while the count on the tab
    beside it keeps climbing. Nothing raises and nothing warns, because
    nothing is missing - the value is in the assigns, and change tracking was
    only never told about it.

    `Phoenix.Component.assign/2` is what tells it. It writes the key *and*
    records the key in `__changed__`, and that record is the whole of the
    difference between the two lines.

    ## The resize is a command, not a hook

    Decision 7 ships exactly one JavaScript hook and this section adds none.
    The resize is a native range control inside a `phx-change` form: the new
    height crosses as an ordinary event, `StatifierBlocks.Shell.clamp_height/1`
    bounds it, and the host stores it - one round trip, and the state that
    matters lives where state already lives. 2A is explicit that the height is
    remembered **per viewer** and that the package has no viewer, so nothing
    here persists anything.

    ## The arrow keys are the server's

    The strip is a `role="tablist"` with a roving `tabindex`, so the tabs
    are one stop on the Tab sequence and all but the active one are reached
    with the arrow keys or not at all - and once `sb-mtak` made the strip scroll at the
    narrow breakpoint with its scrollbar hidden, "not at all" also meant not
    visible. WAI-ARIA's pattern closes that: Left and Right move one tab and
    wrap, Home and End go to the ends.

    **The server owns the movement, and nothing here is a JavaScript hook.**
    Decision 7 caps the package at two hooks and says in as many words that
    adding another requires amending that record, which is a deliberately high
    bar and the wrong bar to clear for a keystroke that already has a
    server-side route: `phx-keydown` on the tablist carries the key, the
    editor's `"drawer-tab-key"` handler picks the neighbour out of the same
    ordered tab list the strip draws from, and the pick is stored in the same
    assign a click stores. So the tab order lives in one place, the arrow keys
    and the pointer reach it the same way, and `ExUnit` can drive the whole
    behaviour.

    Activation is **automatic** - moving focus picks the tab - which is what
    lets the server know which tab is focused without being told: under a
    roving `tabindex` the focused tab is the active one, so `phx-value-tab`
    on the tablist is enough and no per-tab binding is needed. WAI-ARIA
    recommends automatic activation when showing a panel is cheap, and these
    panels are already re-rendered on every document change.

    Moving DOM focus is the one part a re-render cannot do by itself, and it
    is done without a hook either. The `@focus_tab` span carries the newly
    active tab in its **id**, so a pick that moves the tab replaces the
    element rather than patching it, and the `phx-mounted` on the replacement
    runs `JS.focus/1` at the new tab. `focus()` scrolls its element into view,
    which is what makes a tab past the clipped edge reachable at the narrow
    breakpoint. The editor clears `focus_tab` on every other route into the
    drawer - a click, an open, a close, a document switch - so the span is
    absent unless a key press just asked for the focus to move, and opening
    the drawer never steals it.
    """

    use Phoenix.Component

    alias Phoenix.LiveView.JS
    alias StatifierBlocks.Editor.{Declarations, Findings}
    alias StatifierBlocks.Predicates.TruthTable
    alias StatifierBlocks.{Shell, SourceView, ViewModel}

    attr(:view, :map, required: true, doc: "`StatifierBlocks.Shell.drawer_view/1`'s value")
    attr(:height, :float, required: true)
    attr(:root, ViewModel.Node, required: true)
    attr(:target, :any, required: true)
    attr(:class, :string, default: nil)

    attr(:focus_tab, :any,
      default: nil,
      doc: """
      The tab the strip must put DOM focus on, or `nil` for "leave focus
      alone". The editor sets it when an arrow key moved the active tab and
      clears it on every other route into the drawer - see the moduledoc's
      "The arrow keys are the server's".
      """
    )

    attr(:declarations, :list,
      default: [],
      doc: "the entries the Declarations tab draws - the document's, or an author's draft"
    )

    attr(:declaration_refusal, :string,
      default: nil,
      doc: "the sentence for a refused declaration edit, or `nil`"
    )

    attr(:fixture_runs, :any,
      default: nil,
      doc: "`StatifierBlocks.Runtime.FixtureRuns.t()` for the Fixtures tab, or `nil`"
    )

    attr(:declared_view, :list,
      default: [],
      doc: "`StatifierBlocks.Datamodel.declared_view/3`'s rows for the Datamodel tab"
    )

    attr(:declared_types, :list,
      default: [],
      doc: "`StatifierBlocks.Datamodel.declared_types/1`'s rows for the Datamodel tab"
    )

    attr(:environment_view, :any,
      default: nil,
      doc: """
      What the environment holds at the selected block's position, as
      `%{path:, type:}` rows, or `nil` when nothing is selected - ADR-0011
      decision 9's "what is known here". `nil` and `[]` say different things:
      nothing selected, and nothing known there.
      """
    )

    attr(:run?, :boolean,
      default: false,
      doc: """
      Whether a run is seated in the editor. The Datamodel tab's
      "what is known here" table draws its held-value column only while one
      is - see `StatifierBlocks.Runtime.RunValues`.
      """
    )

    attr(:source_view, :any,
      default: nil,
      doc: """
      `StatifierBlocks.SourceView.t()` for the Source tab, or `nil` before
      the editor has compiled anything. The editor refreshes it only while
      the drawer is open on that tab.
      """
    )

    attr(:selected_id, :any,
      default: nil,
      doc: "the selected block's id, which is what the Source tab highlights by"
    )

    attr(:host_tabs, :list,
      default: [],
      doc: """
      The host's tab descriptors, already through
      `StatifierBlocks.Shell.host_tabs/1`. The active one's `content` is
      called for the panel; the strip draws them all from `@view.tabs`, where
      their labels and counts already are.

      `content` is called with `%{id: ..., count: ...}` and with change
      tracking on those two keys only, so a host value the function adds for
      its own markup is added with `Phoenix.Component.assign/2` and never
      merged in - see the moduledoc.
      """
    )

    @doc "The drawer row: a strip when collapsed, tabs and a table when open."
    def drawer(assigns) do
      {min, max, _default} = Shell.height_band()

      assigns =
        assigns
        |> assign(:min, min)
        |> assign(:max, max)
        |> assign(:host_tab, Enum.find(assigns.host_tabs, &(&1.id == assigns.view.tab)))

      ~H"""
      <section
        class={["sb-drawer", @class]}
        data-open={to_string(@view.open?)}
        data-tab={@view.tab}
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
          <span class="sb-drawer__count">{@view.count}</span>
        </button>

        <div :if={@view.open?} class="sb-drawer__frame">
          <div class="sb-drawer__bar">
            <div
              class="sb-drawer__tabs"
              role="tablist"
              aria-label="Drawer"
              phx-keydown="drawer-tab-key"
              phx-value-tab={@view.tab}
              phx-target={@target}
            >
              <button
                :for={entry <- @view.tabs}
                type="button"
                role="tab"
                id={"sb-drawer-tab-#{entry.id}"}
                class={[
                  "sb-drawer__tab",
                  entry.id == @view.tab && "sb-drawer__tab--selected"
                ]}
                aria-selected={to_string(entry.id == @view.tab)}
                aria-controls={"sb-drawer-panel-#{entry.id}"}
                tabindex={if entry.id == @view.tab, do: "0", else: "-1"}
                phx-click="drawer-tab"
                phx-value-tab={entry.id}
                phx-target={@target}
              >
                {entry.title}
                <span class="sb-drawer__count">({entry.count})</span>
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

          <span
            :if={@focus_tab}
            id={"sb-drawer-tab-focus-#{@focus_tab}"}
            class="sb-drawer__tab-focus"
            hidden
            phx-mounted={JS.focus(to: "#sb-drawer-tab-#{@focus_tab}")}
          ></span>

          <div
            class="sb-drawer__panel"
            role="tabpanel"
            id={"sb-drawer-panel-#{@view.tab}"}
            aria-labelledby={"sb-drawer-tab-#{@view.tab}"}
          >
            <%= cond do %>
              <% @host_tab -> %>
                {Phoenix.LiveView.TagEngine.component(
                  @host_tab.content,
                  %{id: @host_tab.id, count: @view.count},
                  {__MODULE__, {:drawer, 1}, __ENV__.file, __ENV__.line}
                )}
              <% @view.tab == :findings -> %>
                <Findings.findings
                  findings={@view.findings}
                  orphans={@view.orphans}
                  root={@root}
                  target={@target}
                />
              <% @view.tab == :declarations -> %>
                <Declarations.declarations
                  entries={@declarations}
                  refusal={@declaration_refusal}
                  target={@target}
                />
              <% @view.tab == :fixtures -> %>
                <.fixture_runs runs={@fixture_runs} />
              <% @view.tab == :source -> %>
                <.source view={@source_view} selected_id={@selected_id} target={@target} />
              <% @view.tab == :datamodel -> %>
                <.known_here rows={@environment_view} run?={@run?} />
                <.declared_paths rows={@declared_view} />
                <.declared_types rows={@declared_types} />
              <% true -> %>
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
            <% end %>
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
    #
    # The scroller is a labelled region and a Tab stop. A table with more arms
    # than the drawer is wide scrolls horizontally, and nothing inside it is
    # focusable - every cell is text - so without a `tabindex` here the
    # columns past the right edge are reachable by pointer and by nothing
    # else. Making the scroller itself focusable is what hands a keyboard the
    # arrow keys, Home and End over the table; `role="region"` with the
    # table's own name is what stops that stop from announcing as an unnamed
    # group, since a focusable scroll container with no accessible name is a
    # stop a screen reader cannot tell its user the purpose of.
    defp table(assigns) do
      ~H"""
      <figure class="sb-table" data-table={@table.name}>
        <figcaption class="sb-table__caption">
          <span class="sb-table__name">{@table.name}</span>
          <span :if={@table.description} class="sb-table__description">{@table.description}</span>
        </figcaption>

        <div class="sb-table__scroll" tabindex="0" role="region" aria-label={@table.name}>
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
                <th scope="row">
                  {row.name}
                  <span :if={row.note} class="sb-table__row-note">{row.note}</span>
                </th>
                <td :for={path <- @table.paths} data-path={path}>
                  {Map.get(row.bindings || %{}, path, "")}
                </td>
                <td
                  :if={row.error}
                  class="sb-table__row-error"
                  colspan={length(@table.columns)}
                  data-status="error"
                >
                  {row_error_sentence(row.error)}
                </td>
                <td
                  :for={{cell, detail} <- annotated_cells(row)}
                  data-column={cell.column_key}
                  data-status={cell.status}
                  data-selected={to_string(cell.selected?)}
                  title={detail}
                >
                  {Shell.cell_word(cell)}<span :if={detail} class="sb-table__cell-detail">{detail}</span>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </figure>
      """
    end

    # A row that never built a context has no cells to draw: the row-error
    # cell above spans the columns in their place.
    #
    # The status word alone says a cell disagreed with its row, not what the
    # disagreement was, and the two mismatches read identically - an author
    # cannot tell "this arm was expected to win and did not" from "this arm
    # was expected to lose and won". Both readings are already on the cell:
    # `expected` is what the row declared, `selected?` is what one ordered
    # first-match-wins pass actually chose. So the detail is paired with its
    # cell here and drawn beside the word, rather than staying in the struct
    # where only the code can see it.
    defp annotated_cells(%TruthTable.Row{error: error}) when not is_nil(error), do: []

    defp annotated_cells(%TruthTable.Row{cells: cells}),
      do: Enum.map(cells, &{&1, mismatch_detail(&1)})

    # Only `:mismatch` carries a detail. `:match` would say the same thing
    # twice, `:unchecked` has no `expected` to report, and `:error` and
    # `:undecidable` have no boolean `selected?` a sentence could name.
    defp mismatch_detail(%TruthTable.Cell{
           status: :mismatch,
           expected: expected,
           selected?: selected
         }),
         do: "expected #{yes_no(expected)}, selected #{yes_no(selected)}"

    defp mismatch_detail(%TruthTable.Cell{}), do: nil

    # "yes" and "no" rather than "true" and "false": the column is an arm and
    # the question the cell answers is whether that arm was taken, which is
    # not a value the author wrote anywhere.
    defp yes_no(true), do: "yes"
    defp yes_no(false), do: "no"

    # A row whose bindings never built a context carries a
    # `StatifierBlocks.Predicates.reason()` - a tagged tuple from this
    # package's error vocabulary, and a term rather than a sentence. An author
    # reading the drawer wrote the fixture, not the vocabulary, so each tag
    # `Predicates.context/1` can hand a row is read out here instead. The
    # inspected term stays the fallback for anything unrecognised: a reason
    # the seam adds later reads oddly, which is a bug someone can see, rather
    # than vanishing into an empty cell, which is one nobody can.
    defp row_error_sentence({:binding, path, reason}),
      do: ~s(The binding for "#{path}" failed: #{clause(reason) || inspect(reason)}.)

    defp row_error_sentence({:binding_conflict, path}),
      do:
        ~s(The binding for "#{path}" conflicts with another bound path: ) <>
          "two paths cannot both nest."

    defp row_error_sentence(reason) do
      case clause(reason) do
        nil -> inspect(reason)
        clause -> "This case's bindings failed: #{clause}."
      end
    end

    # The five `evaluate/2`-level tags, as lowercase fragments, so they read
    # the same nested inside a `{:binding, path, reason}` and standing alone.
    # The predicator struct's own message is deliberately not quoted into
    # them: it is parser vocabulary rather than anything the author wrote, and
    # a single one of them runs past 130 characters, which a `nowrap` table
    # cell turns into a horizontal scroll on a table that otherwise fits. The
    # source that failed is already in the row's own binding column.
    defp clause({:undefined_result, source}),
      do: "the source #{inspect(source)} evaluated to undefined"

    defp clause({:non_boolean, value}),
      do: "the source produced #{inspect(value)}, which is not true or false"

    defp clause({:parse_error, _error}), do: "the source could not be parsed"

    defp clause({:undefined_variable, variable, _error}),
      do: ~s(nothing binds the variable "#{variable}")

    defp clause({:evaluation_error, _error}), do: "the source could not be evaluated"

    defp clause(_other), do: nil

    attr(:runs, :any, default: nil)

    # `@runs` is `StatifierBlocks.Runtime.FixtureRuns.t()` or `nil` (before the
    # first `refresh_fixture_runs/1` call the editor ever makes, which is
    # before the drawer has been opened once). `nil` and `:no_fixtures` read
    # alike: neither has a run to show, and the copy says why.
    #
    # `:compile_error` reads as a normal mid-edit state on purpose - an editor
    # mid-edit reaches it constantly, and it is not a failure of the
    # fixtures - followed by the findings that say what does not compile.
    defp fixture_runs(assigns) do
      ~H"""
      <p :if={@runs == nil or @runs.status == :no_fixtures} class="sb-drawer__empty">
        No fixtures source is attached to this editor, so there are no recorded
        cases to run. A host supplies them alongside the document.
      </p>

      <div :if={@runs != nil and @runs.status == :compile_error}>
        <p class="sb-drawer__empty">
          This document does not currently compile, so no case can be run.
        </p>
        <ul class="sb-fixtures__findings">
          <li :for={finding <- @runs.findings}>{finding.message}</li>
        </ul>
      </div>

      <div :if={@runs != nil and @runs.status == :ready} class="sb-fixtures__scroll">
        <table>
          <thead>
            <tr>
              <th scope="col">Block</th>
              <th scope="col">Table</th>
              <th scope="col">Case</th>
              <th scope="col">Expected</th>
              <th scope="col">Taken</th>
              <th scope="col">Verdict</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={run <- @runs.runs} data-block={run.block_id} data-row={run.row_name}>
              <td>{run.block_id}</td>
              <td>{run.table_name}</td>
              <td>{run.row_name}</td>
              <td>{run.expected_slot}</td>
              <td>{run.taken_slot}</td>
              <td data-verdict={run.verdict}>{run.verdict}</td>
            </tr>
          </tbody>
        </table>
      </div>
      """
    end

    attr(:view, :any, default: nil)
    attr(:selected_id, :any, default: nil)
    attr(:target, :any, required: true)

    # The compiled chart, one numbered row per element, each run of bytes
    # carrying the block that emitted it.
    #
    # The three states are the three `StatifierBlocks.SourceView` reports,
    # and they say different things on purpose. `:pending` is *nothing has
    # been compiled*, which is only ever seen by a caller that drew this
    # panel without asking for a listing first. `:compile_error` is a normal
    # mid-edit document with no earlier chart to fall back on. `:ready` with
    # `stale?` is the last chart the document produced, still readable, with
    # a line saying it is not the current one - which is what the editor
    # shows instead of recompiling on every keystroke.
    defp source(assigns) do
      assigns = assign(assigns, :view, assigns.view || %SourceView{})

      ~H"""
      <div class="sb-source" data-status={@view.status} data-stale={to_string(@view.stale?)}>
        <p :if={@view.status == :pending} class="sb-drawer__empty">
          Nothing has been compiled yet.
        </p>

        <p :if={@view.status == :compile_error} class="sb-drawer__empty">
          This document does not currently compile, so there is no chart to show.
        </p>

        <p :if={@view.stale?} class="sb-source__stale">
          Compiled from an earlier document. This document does not currently
          compile, so what follows is the last chart it produced.
        </p>

        <ul :if={@view.findings != []} class="sb-source__findings">
          <li :for={finding <- @view.findings}>{finding.message}</li>
        </ul>

        <ol :if={@view.status == :ready} class="sb-source__lines">
          <li
            :for={line <- @view.lines}
            class="sb-source__line"
            value={line.number}
            data-line={line.number}
            data-indent={line.indent}
          >
            <span class="sb-source__number" aria-hidden="true">{line.number}</span>
            <code
              class="sb-source__text"
              style={"padding-left: calc(var(--sb-space) * #{line.indent})"}
              phx-no-format
            ><.source_span :for={span <- line.spans} span={span} selected_id={@selected_id} target={@target} /></code>
          </li>
        </ol>
      </div>
      """
    end

    attr(:span, SourceView.Span, required: true)
    attr(:selected_id, :any, default: nil)
    attr(:target, :any, required: true)

    # One run of bytes. A run with an owner is a button carrying that block's
    # id straight to the editor's existing `select` event: the byte offset was
    # already resolved through `StatifierBlocks.Provenance.owner_at/2` when
    # the listing was built, so the click needs no second resolution and the
    # panel adds no handler of its own.
    #
    # `config_key` is the field an author typed the value into, and it is the
    # title because that is the whole of what the span is: not "somewhere in
    # this block" but "this field of it".
    #
    # A run with no owner is plain text. It is drawn rather than dropped
    # because the listing is the generated bytes and a listing that omitted
    # some of them would not be.
    #
    # The markup is deliberately unbroken - `phx-no-format` on the `<code>`
    # above, and no whitespace between the two elements here - because every
    # space inside the listing is a byte of the chart.
    defp source_span(assigns) do
      ~H"""
      <button
        :if={@span.block_id}
        type="button"
        class="sb-source__span"
        data-block={@span.block_id}
        data-role={@span.role}
        data-config-key={@span.config_key}
        data-offset={@span.offset}
        data-selected={to_string(@span.block_id == @selected_id)}
        title={@span.config_key}
        phx-click="select"
        phx-value-block-id={@span.block_id}
        phx-target={@target}
      >{@span.text}</button><span :if={is_nil(@span.block_id)} class="sb-source__plain">{@span.text}</span>
      """
    end

    attr(:rows, :list, default: [])

    # One row per declared path, and nothing an author can change: the
    # editable surface is the Declarations tab, over the document's own roots,
    # and this one is the whole vocabulary an advisory is decided against -
    # including the two surfaces the author does not own. A grid that offered
    # to edit a host's datamodel would be offering an edit the package cannot
    # make.
    #
    # The empty state distinguishes nothing at all from a surface that
    # declared nothing, in the same words `StatifierBlocks.Datamodel`'s
    # "absence is not unknown-ness" section uses: with nothing declared
    # anywhere, no advisory is produced either, and the panel says that rather
    # than leaving an author to infer it from an empty table.
    defp declared_paths(assigns) do
      ~H"""
      <section class="sb-datamodel__section" data-section="declared-paths">
        <h3 class="sb-datamodel__heading">Declared paths</h3>

        <p :if={@rows == []} class="sb-drawer__empty">
          Nothing declares a datamodel path for this document - not the host, not
          the compile call's roots, and not the document's own envelope. No
          undeclared-path advisory is produced while that is true.
        </p>

        <div :if={@rows != []} class="sb-datamodel__scroll">
          <table>
            <thead>
              <tr>
                <th scope="col">Path</th>
                <th scope="col">Declared by</th>
                <th scope="col">Type</th>
                <th scope="col">Scope</th>
                <th scope="col">Label</th>
              </tr>
            </thead>
            <tbody>
              <tr
                :for={row <- @rows}
                data-path={row.path}
                data-sensitive={to_string(row.sensitive?)}
              >
                <th scope="row">{row.path}</th>
                <td>{Shell.declared_by(row)}</td>
                <td>{Shell.declared_shape(row)}</td>
                <td>{row.scope}</td>
                <td>{row.label}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>
      """
    end

    attr(:rows, :any, default: nil)
    attr(:run?, :boolean, default: false)

    # ADR-0011 decision 9's second surface: the paths the environment holds at
    # the SELECTED block's position, with their types. It sits above the
    # declared-path table rather than beside it because the two answer
    # different questions and the order is the order an author asks them in -
    # "what can I read right here" first, "what exists anywhere in this
    # document" second.
    #
    # Three states, and they are three because collapsing any two of them
    # lies. `nil` is *nothing selected*, and there is no position to answer
    # for. `[]` is *a block is selected and nothing is known there*, which is
    # the honest answer for a document whose entry block declares no subject
    # (decision 2) and is not the same as not having asked. Rows are the
    # answer.
    #
    # Nothing here is clickable and nothing here is a finding. The record is
    # explicit that neither of decision 9's surfaces changes a verdict or
    # produces a finding of its own, so this is a read-only statement of what
    # the walk computed on the way to the block the author is looking at.
    #
    # With a run seated the table grows one column: what that run was actually
    # holding at each of these paths, at the point the scrubber is on. The
    # pairing is the whole value of it - a path this position declares one
    # type and the run held something else is a read that should not have
    # worked, and it is visible by looking at the two cells rather than by
    # this package ruling on them. Still no verdict, still no finding, still
    # no colour: an author reads the row.
    #
    # The column appears only while a run is there. An empty third column
    # under a document nobody is running would read as "held nothing", which
    # is a claim, where the truth is that nobody asked.
    defp known_here(assigns) do
      ~H"""
      <section class="sb-datamodel__section" data-section="known-here">
        <h3 class="sb-datamodel__heading">What is known here</h3>

        <p :if={@rows == nil} class="sb-drawer__empty">
          Select a block to see what the datamodel holds at its position.
        </p>

        <p :if={@rows == []} class="sb-drawer__empty">
          Nothing is known at this block's position. The document opens with its
          entry block's subject, and this one is reached before anything has
          been written.
        </p>

        <div :if={@rows not in [nil, []]} class="sb-datamodel__scroll">
          <table>
            <thead>
              <tr>
                <th scope="col">Path</th>
                <th scope="col">Type</th>
                <th :if={@run?} scope="col">Held here</th>
              </tr>
            </thead>
            <tbody>
              <tr
                :for={row <- @rows}
                data-path={row.path}
                data-type={row.type}
                data-held={@run? && held_text(row)}
              >
                <th scope="row">{row.path}</th>
                <td>{row.type}</td>
                <td :if={@run?} class="sb-datamodel__held">{held_text(row)}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>
      """
    end

    # "declared T, held V" is what the row says across its cells, and the two
    # halves are not the same kind of thing: the type is what the document
    # promised, the value is what the run had. A path the run never wrote is
    # not `nil` and not an empty string either - both of those are values a
    # run could genuinely hold - so it says so in words.
    @spec held_text(map()) :: String.t()
    defp held_text(%{held: held}) when is_binary(held), do: held
    defp held_text(_unwritten), do: "not written"

    attr(:rows, :list, default: [])

    # The declared `record` and `shape` vocabulary, with each declaration's
    # fields and its required marks. It is what a `:type_mismatch` naming a
    # shape is about: an author told that a record does not cover `Settleable`
    # needs to be able to read what `Settleable` requires, and until this
    # section the editor never said.
    #
    # The fields are an inner list inside the row rather than a second table
    # keyed by declaration name, because a field has no meaning away from the
    # declaration that declares it - `amount_minor` is a row of `Settleable`,
    # not a row of the document. A required field is marked with a word and
    # not only with a symbol, for `Shell.cell_word/1`'s reason.
    defp declared_types(assigns) do
      ~H"""
      <section class="sb-datamodel__section" data-section="declared-types">
        <h3 class="sb-datamodel__heading">Declared types</h3>

        <p :if={@rows == []} class="sb-drawer__empty">
          The datamodel document declares no records or shapes, so every type a
          block reads or writes is read by identity on its own spelling.
        </p>

        <div :if={@rows != []} class="sb-datamodel__scroll">
          <table>
            <thead>
              <tr>
                <th scope="col">Type</th>
                <th scope="col">Kind</th>
                <th scope="col">Fields</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={row <- @rows} data-type={row.name} data-kind={row.kind}>
                <th scope="row">
                  <span class="sb-datamodel__type-label">{row.label || row.name}</span>
                  <span :if={row.label not in [nil, row.name]} class="sb-datamodel__type-name">
                    {row.name}
                  </span>
                </th>
                <td>{row.kind}</td>
                <td>
                  <p :if={row.fields == []} class="sb-datamodel__no-fields">no fields</p>
                  <ul :if={row.fields != []} class="sb-datamodel__fields">
                    <li
                      :for={field <- row.fields}
                      data-field={field.name}
                      data-required={to_string(field.required?)}
                    >
                      <span class="sb-datamodel__field-name">{field.name}</span>
                      <span class="sb-datamodel__field-type">{field.type}</span>
                      <span :if={field.required?} class="sb-datamodel__field-required">
                        required
                      </span>
                    </li>
                  </ul>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>
      """
    end
  end
end
