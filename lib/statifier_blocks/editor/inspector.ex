if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.Inspector do
    @moduledoc """
    The tabbed inspector: Config, Findings, Condition, Fixtures (ADR-0005, the
    2026-08-29 shell amendment, ruling 3A, and its 2026-09-05 amendment).

    3A is one rule and a list, and the rule is the part that matters: **the
    inspector is about the selected block, and anything about the document goes
    to the drawer.** The list of tabs follows from it rather than the other way
    round, which is why the Datamodel - an inspector tab in the spike - is a
    drawer tab here. It was never about the selected block.

    One thing a reader will look for and not find:

      * There is no tab here that is about the document. A pane that is about
        the document has one place to go, and 3A exists so that "which
        inspector tab does this become" stops being asked. The Fixtures tab
        below is admitted by that rule, not in spite of it: a fixture row is
        attached to exactly one block.
      * The Findings tab is **not** the document-level findings panel decision
        13 names. That panel still exists, still lists every finding in the
        document, and still lives beside the canvas. This tab is the selected
        block's own findings, which is the distinction the campaign-014 polish
        pass filed as `sb-3l1` item a.

    ## The Findings tab with nothing selected (sb-dbqq)

    3A's rule decides what a tab is **about**; it does not say what a tab
    does when its subject is missing. With no selection the Findings tab has
    no block to be about, and what it did was render the same "select a
    block" line the Condition tab does - a chip-less tab beside a document
    with four things wrong with it.

    So with `node: nil` the tab reads the **document**: the chip carries
    `StatifierBlocks.Shell.findings_count/1` over the findings the editor
    passes in - the one number this package means by "the document's
    findings", the same one the drawer's strip and
    `StatifierBlocks.Editor.findings_count/3` report - and the panel lists
    them grouped by block, each row selecting its block through the same
    `select` event the canvas and the drawer's list push.

    This is the tab's empty state and not a fourth surface. The moment
    anything is selected the tab is that block's findings again, unchanged,
    and the document-level list an author *navigates* is still the drawer's
    (R4). What the inspector adds is an answer where there was a dead end:
    the count is not recomputed here, the list is not filtered here, and
    selecting a row hands the author back to the pane's real subject.

    ## The Condition tab reads; it does not evaluate

    It renders the per-arm predicator source the block carries, one entry per
    `:expression` field, and it evaluates nothing. Evaluation is
    `StatifierBlocks.Predicates`, it is server-side, and what it produces - a
    truth table - is tabular and document-level, so 1A puts it in the drawer.
    The tab that shows an author what a branch asks and the drawer that shows
    what it answers are different surfaces on purpose.

    Editing a condition stays on the Config tab, where every other field is
    edited, so there is exactly one form in the editor and one place a draft
    can live (decision 9).

    ## The Fixtures tab is the selected block's rows (sb-0l36)

    ADR-0005's 2026-09-05 amendment, "3A admits a Fixtures tab in the
    inspector". A fixture row attaches to one block - the `fixtures` assign is
    `%{block_id => [TruthTable.t()]}`, with no document-level bucket and no row
    belonging to two blocks - so the selected block's rows are about the
    selected block, which is the whole of what 3A asks of an inspector tab.

    **The drawer's own Fixtures tab is unchanged in every particular.** The two
    coexist by pane, exactly as Findings already does: the drawer's tab is
    every row in the document with the block named in a column, and this one is
    one block's rows with the block named by the pane. Nothing here filters a
    different list or derives a second number - both read the runs the editor
    already holds.

    **It adds no execution path.** The rows come from the same
    `StatifierBlocks.Runtime.FixtureRuns` result the drawer's tab renders,
    which the editor recomputes in `refresh_fixture_runs/1`; this tab selects
    the runs whose `block_id` is the pane's subject and renders them. What that
    costs is one comparison per run, on a struct the editor computed for the
    drawer's sake anyway.

    **Its count is the selected block's row count**, in the Findings tab's chip
    and style. It counts rows and not failures for the reason the drawer's
    strip does: the number beside a tab says how much is in it, and a count
    that vanished when everything passed would read as "no fixtures" on the
    document an author most wants to see the number for.

    Its empty states are three, and they are different questions: no selection
    (the pane has no subject), no fixtures source at all, and a source that
    holds nothing for this block. The mid-edit compile failure is a fourth, and
    it reads as mid-edit rather than as a failure of the fixtures - the same
    words the drawer's panel uses, for the same reason.

    ## The pane header, and what its status says (parity item 1.1)

    Above the tabs sits the pane's own header row: the name of the pane, and a
    right-aligned status. The status is the inspector's subject stated in
    words - the selected block's type label, or `no selection` - and it is
    there because 3A's rule ("the inspector is about the selected block") is
    invisible in an empty pane otherwise: three tabs with nothing under them
    do not say whether the author has selected nothing or selected something
    that has nothing to show.

    It reads the **type's label**, not the block's id. A label is what the
    author picked the block by in the palette and what its card reads on the
    canvas, so the header names the block in the vocabulary the rest of the
    editor already uses. An unresolvable block reaches the placeholder entry
    by the ordinary route and falls back to its raw type name, which is the
    only thing about it that is still known.

    ## The inspector folds too (ADR-0005, the 2026-08-30 shell amendment)

    This pane used to say it had no collapse - that the palette's fold was the
    wide arrangement's answer to a cramped canvas, that one pane was enough of
    an answer, and that a second one would be a separate ruling. It is that
    separate ruling that has now been made: the 2026-08-30 amendment to the
    shell arrangement grants the inspector its own fold, and the paragraph
    above is superseded rather than merely out of date.

    What it is, is the palette's fold on the other side of the canvas:
    `collapsed` in, `"inspector-collapse"` out, `data-collapsed` on the pane
    and `data-inspector` on the layout, and the width given back by one
    stylesheet rule. No hook, no client state, no fourth tab, and nothing
    about 3A changes - a folded pane is still about the selected block, it is
    just not on screen. The chevron points the way the press will MOVE the
    pane, which on this side is the mirror of the palette's.

    ## The Config tab's two sections (parity item 1.9)

    Under the tabs the Config tab is two labelled sections rather than a form
    dropped into a pane. **Block** states what the pane's subject IS - its
    type, its id, and the slot it sits in - and **Configuration** holds the
    form.

    The Block section is the one that has to be there when nothing is
    selected, which is why its three rows render either way and read as a
    dash when they have no value. A section that appears and disappears with
    the selection teaches an author nothing about what the pane will show
    them; three rows that are always in the same place, sometimes empty, say
    what the inspector is about before they have selected anything.

    The three rows are deliberately the three an author can act on. `Type` is
    the type's label, the same string the header status reads, so the pane
    names the block the way the palette and the canvas do. `Id` is the block
    id verbatim and set in mono, because it is the string that appears in a
    finding, in a provenance map and in a URL, and an author reading one of
    those needs to match it character for character. `Slot` is the slot's
    label - `StatifierBlocks.Shell.slot_label/2`'s answer - because a card
    seen on its own does not say which arm of a branch it is in.

    Under the three rows, and only for a block whose type did not resolve,
    the Block section holds that block's **stored config as canonical JSON**
    (campaign-017 ruling D4). It used to sit on the card, where it made the
    one broken block the widest thing in its lane; it is the same bytes in
    the same order, moved to the surface an author reaches by asking about
    that block in particular. It is read-only here for the reason the Config
    tab is empty there: nothing declares which of those values are editable,
    and a form over them would be invented rather than derived.

    It is the only thing in this pane that wraps mid-token. A block id
    ellipsises and a condition source scrolls, because both are strings an
    author matches character by character and neither is long by design; a
    stored config carries whatever the host that wrote it carried, so the
    only two honest choices are wrapping anywhere and clipping bytes the
    author is here to read.

    The Configuration section's empty state is a **box**, not the one-line
    sentence the other tabs use. It is the only empty state in the editor
    standing where a control would be, and an unboxed sentence in that
    position reads as a caption for the form below it rather than as the
    reason there is no form.
    """

    use Phoenix.Component

    alias StatifierBlocks.Editor.{ConfigForm, Findings}
    alias StatifierBlocks.{Finding, Shell, ViewModel}

    attr(:tab, :atom, required: true)

    attr(:collapsed, :boolean,
      default: false,
      doc: "folded to a rail - the 2026-08-30 shell amendment's inspector fold"
    )

    attr(:node, :any, default: nil, doc: "the selected `ViewModel.Node`, or nil")

    attr(:slot_label, :any,
      default: nil,
      doc: "`Shell.slot_label/2` for the selection - the slot it sits in, or nil"
    )

    attr(:pending, :list, default: [])
    attr(:expression_component, :any, default: nil)

    attr(:invoke_types, :list,
      default: [],
      doc: "Passed through to `StatifierBlocks.Editor.Field`; see its moduledoc."
    )

    attr(:path_candidates, :list,
      default: [],
      doc: "Passed through to `StatifierBlocks.Editor.Field`; see its moduledoc."
    )

    attr(:value_candidates, :map,
      default: %{},
      doc: "Passed through to `StatifierBlocks.Editor.Field`; see its moduledoc."
    )

    attr(:path_types, :map,
      default: %{},
      doc: "Passed through to `StatifierBlocks.Editor.Field`; see its moduledoc."
    )

    attr(:event_candidates, :list,
      default: [],
      doc: "Passed through to `StatifierBlocks.Editor.Field`; see its moduledoc."
    )

    attr(:outcome_candidates, :list,
      default: [],
      doc: "Passed through to `StatifierBlocks.Editor.Field`; see its moduledoc."
    )

    attr(:field_candidates, :map,
      default: %{},
      doc: "Passed through to `StatifierBlocks.Editor.ConfigForm`; see its moduledoc."
    )

    attr(:capture_pairs, :any,
      default: nil,
      doc: "Passed through to `StatifierBlocks.Editor.ConfigForm`; see its moduledoc."
    )

    attr(:capture_sources, :list,
      default: [],
      doc: "Passed through to `StatifierBlocks.Editor.ConfigForm`; see its moduledoc."
    )

    attr(:fixtures, :any,
      default: nil,
      doc: "Passed through to `StatifierBlocks.Editor.ConfigForm`; see its moduledoc."
    )

    attr(:field_focus, :any,
      default: nil,
      doc: "Passed through to `StatifierBlocks.Editor.ConfigForm`; see its moduledoc."
    )

    attr(:fixture_runs, :any,
      default: nil,
      doc:
        "`StatifierBlocks.Runtime.FixtureRuns.t()` for the Fixtures tab, or `nil` - " <>
          "the same struct the drawer's Fixtures tab reads, filtered here to the " <>
          "selected block's runs"
    )

    attr(:target, :any, required: true)
    attr(:class, :string, default: nil)

    attr(:document_findings, :list,
      default: [],
      doc: "`ViewModel.findings` - what the Findings tab reads with no selection"
    )

    attr(:orphan_findings, :list,
      default: [],
      doc: "`ViewModel.orphan_findings` - the subset with no block to select"
    )

    attr(:root, :any,
      default: nil,
      doc: "the view model's root `ViewModel.Node`, read only for group labels"
    )

    @doc "The four tabs and the panel of whichever one is showing."
    def inspector(assigns) do
      findings = Shell.block_findings(assigns.node)
      block_runs = block_runs(assigns.fixture_runs, assigns.node)

      assigns =
        assigns
        |> assign(:findings, findings)
        |> assign(:block_runs, block_runs)
        |> assign(:fixture_count, length(block_runs))
        |> assign(:tab_count, tab_count(assigns.node, findings, assigns.document_findings))
        |> assign(:groups, document_groups(assigns))
        |> assign(:counts, Shell.severity_counts(document_counted(assigns)))
        |> assign(:conditions, Shell.condition_fields(assigns.node && assigns.node.form))

      ~H"""
      <section
        class={["sb-inspector", @class]}
        data-tab={@tab}
        data-collapsed={to_string(@collapsed)}
        data-block-id={@node && @node.block_id}
      >
        <div class="sb-inspector__header">
          <h2 class="sb-inspector__title">Inspector</h2>
          <span class="sb-inspector__status" data-selected={to_string(@node != nil)}>
            {selection_status(@node)}
          </span>
          <button
            type="button"
            class="sb-inspector__toggle"
            phx-click="inspector-collapse"
            phx-target={@target}
            aria-expanded={to_string(not @collapsed)}
            aria-label={if @collapsed, do: "Expand the inspector", else: "Collapse the inspector"}
            title={if @collapsed, do: "Expand the inspector", else: "Collapse the inspector"}
          ></button>
        </div>

        <div class="sb-inspector__tabs" role="tablist" aria-label="Inspector">
          <button
            :for={tab <- Shell.inspector_tabs()}
            type="button"
            role="tab"
            id={"sb-inspector-tab-#{tab}"}
            class={["sb-inspector__tab", @tab == tab && "sb-inspector__tab--selected"]}
            aria-selected={to_string(@tab == tab)}
            aria-controls={"sb-inspector-panel-#{tab}"}
            tabindex={if @tab == tab, do: "0", else: "-1"}
            phx-click="inspector-tab"
            phx-value-tab={tab}
            phx-target={@target}
          >
            {label(tab)}
            <span :if={tab == :findings and @tab_count > 0} class="sb-inspector__tab-count">
              {@tab_count}
            </span>
            <span :if={tab == :fixtures and @fixture_count > 0} class="sb-inspector__tab-count">
              {@fixture_count}
            </span>
          </button>
        </div>

        <div
          class="sb-inspector__panel"
          role="tabpanel"
          id={"sb-inspector-panel-#{@tab}"}
          aria-labelledby={"sb-inspector-tab-#{@tab}"}
        >
          <p :if={@node == nil and @tab == :condition} class="sb-inspector__empty">
            Select a block on the canvas to inspect it.
          </p>

          <.block_section :if={@tab == :config} node={@node} slot_label={@slot_label} />

          <section :if={@tab == :config} class="sb-inspector__section">
            <h3 class="sb-inspector__section-title">Configuration</h3>
            <p :if={@node == nil} class="sb-inspector__empty sb-inspector__empty--boxed">
              Select a block on the canvas to edit its configuration.
            </p>
            <.config_panel
              :if={@node != nil}
              node={@node}
              pending={@pending}
              expression_component={@expression_component}
              invoke_types={@invoke_types}
              path_candidates={@path_candidates}
              value_candidates={@value_candidates}
              path_types={@path_types}
              event_candidates={@event_candidates}
              outcome_candidates={@outcome_candidates}
              field_candidates={@field_candidates}
              capture_pairs={@capture_pairs}
              capture_sources={@capture_sources}
              fixtures={@fixtures}
              field_focus={@field_focus}
              target={@target}
            />
          </section>

          <.findings_panel :if={@node != nil and @tab == :findings} findings={@findings} />
          <.document_findings_panel
            :if={@node == nil and @tab == :findings}
            groups={@groups}
            counts={@counts}
            target={@target}
          />
          <.condition_panel
            :if={@node != nil and @tab == :condition}
            node={@node}
            conditions={@conditions}
          />
          <.fixtures_panel
            :if={@tab == :fixtures}
            node={@node}
            runs={@fixture_runs}
            block_runs={@block_runs}
          />
        </div>
      </section>
      """
    end

    attr(:node, :any, required: true)
    attr(:slot_label, :any, required: true)

    # Rendered with `node: nil` too - see the moduledoc. The rows read a dash
    # then, and they are the same three rows in the same order, so the pane's
    # shape does not change under the author when they click a card.
    defp block_section(assigns) do
      ~H"""
      <section class="sb-inspector__section">
        <h3 class="sb-inspector__section-title">Block</h3>
        <dl class="sb-inspector__meta">
          <.meta_row label="Type" value={@node && selection_status(@node)} />
          <.meta_row label="Id" value={@node && @node.block_id} mono />
          <.meta_row label="Slot" value={@node && @slot_label} />
        </dl>
        <pre :if={@node && @node.raw_config_json} class="sb-inspector__raw-config">{@node.raw_config_json}</pre>
      </section>
      """
    end

    attr(:label, :string, required: true)
    attr(:value, :any, required: true)
    attr(:mono, :boolean, default: false)

    # The dash is markup rather than a `::before`, so what an author reads is
    # what a test reads; `data-empty` is what the CSS and a host style against,
    # for the same reason the condition source stamps one.
    defp meta_row(assigns) do
      ~H"""
      <div class="sb-inspector__meta-row">
        <dt class="sb-inspector__meta-key">{@label}</dt>
        <dd
          class={["sb-inspector__meta-value", @mono && "sb-inspector__meta-value--mono"]}
          data-empty={to_string(@value in [nil, ""])}
        >
          <span :if={@value in [nil, ""]} class="sb-inspector__meta-dash">&mdash;</span>{@value}
        </dd>
      </div>
      """
    end

    attr(:node, ViewModel.Node, required: true)
    attr(:pending, :list, required: true)
    attr(:expression_component, :any, required: true)
    attr(:invoke_types, :list, required: true)
    attr(:path_candidates, :list, required: true)
    attr(:value_candidates, :map, required: true)
    attr(:path_types, :map, required: true)
    attr(:event_candidates, :list, required: true)
    attr(:outcome_candidates, :list, required: true)
    attr(:field_candidates, :map, required: true)
    attr(:capture_pairs, :any, required: true)
    attr(:capture_sources, :list, required: true)
    attr(:fixtures, :any, required: true)
    attr(:field_focus, :any, required: true)
    attr(:target, :any, required: true)

    # Decision 12's read-only case reaches here as `form: nil`, and it is the
    # ConfigForm's own message rather than a second one written here: the tab
    # says why there is nothing to edit, and points at the Block section
    # above, which is where D4 moved the bytes themselves.
    defp config_panel(assigns) do
      ~H"""
      <ConfigForm.config_form
        :if={@node.form}
        node={@node}
        target={@target}
        pending={@pending}
        expression_component={@expression_component}
        invoke_types={@invoke_types}
        path_candidates={@path_candidates}
        value_candidates={@value_candidates}
        path_types={@path_types}
        event_candidates={@event_candidates}
        outcome_candidates={@outcome_candidates}
        field_candidates={@field_candidates}
        capture_pairs={@capture_pairs}
        capture_sources={@capture_sources}
        fixtures={@fixtures}
        field_focus={@field_focus}
      />
      <p :if={@node.form == nil} class="sb-inspector__empty">
        This block's type is not registered here, so nothing declares which of its
        stored values are editable. Its config is preserved, and shown as stored
        under Block above.
      </p>
      """
    end

    attr(:findings, :list, required: true)

    # The selected block's findings. A row is `Findings.row/1`'s anatomy with
    # no subject: the block is the pane's own subject, named in the header
    # above, so a subject column here would repeat it on every line.
    defp findings_panel(assigns) do
      ~H"""
      <p :if={@findings == []} class="sb-inspector__empty">No findings on this block.</p>
      <ul :if={@findings != []} class="sb-inspector__findings">
        <li
          :for={finding <- @findings}
          class={["sb-finding", "sb-findings__cells", Finding.severity_class(finding)]}
          data-source={finding.source}
          data-severity={finding.severity}
          data-anchor={Findings.anchor_tag(finding)}
        >
          <Findings.row finding={finding} />
        </li>
      </ul>
      """
    end

    attr(:groups, :list, required: true)
    attr(:counts, :list, required: true)
    attr(:target, :any, required: true)

    # The unselected tab's panel. A pill row says how much is wrong, a group
    # heading names the block, a row is `Findings.row/1` without its subject
    # (the heading is the subject), and a row is a button because the way out
    # of a document-level list is selecting the thing the row is about - the
    # same `select` event the canvas and the drawer's list push, so there is
    # one way a block gets selected however an author arrives at it.
    #
    # The unanchored group's rows are spans: its findings name block ids the
    # document does not hold, so there is nothing to select and a button that
    # did nothing would be worse than no button. They are listed rather than
    # filtered because they are inside the count on the tab beside them.
    defp document_findings_panel(assigns) do
      ~H"""
      <p :if={@groups == []} class="sb-inspector__empty">No findings in this document.</p>
      <Findings.severity_pills counts={@counts} />
      <div :if={@groups != []} class="sb-inspector__groups">
        <section
          :for={group <- @groups}
          class="sb-inspector__group"
          data-block-id={group.block_id}
          data-unanchored={to_string(group.block_id == nil)}
        >
          <h3 class="sb-inspector__group-title">{group.label}</h3>
          <ul class="sb-inspector__findings">
            <li
              :for={finding <- group.findings}
              class={["sb-finding", Finding.severity_class(finding)]}
              data-source={finding.source}
              data-severity={finding.severity}
              data-anchor={Findings.anchor_tag(finding)}
            >
              <button
                :if={group.block_id != nil}
                type="button"
                class="sb-inspector__group-row sb-findings__cells"
                phx-click="select"
                phx-target={@target}
                phx-value-block-id={group.block_id}
              >
                <Findings.row finding={finding} />
              </button>
              <span
                :if={group.block_id == nil}
                class="sb-inspector__group-row sb-findings__cells"
              >
                <Findings.row finding={finding} />
              </span>
            </li>
          </ul>
        </section>
      </div>
      """
    end

    attr(:node, ViewModel.Node, required: true)
    attr(:conditions, :list, required: true)

    # One entry per `:expression` field, which for `core.branch` is one per arm
    # and in the arms' stored order - the order the branch tries them in, so
    # reading down the list is reading the branch.
    defp condition_panel(assigns) do
      ~H"""
      <ol :if={@conditions != []} class="sb-conditions">
        <li :for={field <- @conditions} class="sb-condition" data-field-key={field.key}>
          <span class="sb-condition__label">{field.label}</span>
          <code class="sb-condition__source" data-empty={to_string(field.value in [nil, ""])}>{Shell.condition_source(
            field
          )}</code>
        </li>
      </ol>

      <div :if={@conditions == []} class="sb-inspector__empty">
        <p>This block carries no condition.</p>
        <p class="sb-condition__where">
          Conditions live on a branch's arms - one per arm, deciding which way the
          chart goes - and on the guarded rules attached to a container's rail.
          Select one of those to read its condition here.
        </p>
      </div>
      """
    end

    attr(:node, :any, required: true)
    attr(:runs, :any, required: true)
    attr(:block_runs, :list, required: true)

    # The selected block's fixture rows. One state at a time, resolved in
    # `fixtures_state/3` rather than by four `:if`s that could all be true at
    # once: a pane that renders "no fixtures source" above a table of runs is
    # exactly the defect a computed state cannot have.
    #
    # A row carries the same three facts per row the drawer's tab does -
    # expected slot, taken slot, verdict - minus the block column, because the
    # block is the pane's own subject and a column repeating it on every line
    # is the column the inspector has room for least.
    #
    # `data-verdict` is what the stylesheet tints and what a test reads, and it
    # is the `.sb-fixtures__scroll` rules the drawer's table already declares:
    # the same verdicts in the same words should not be two colours in two
    # panes.
    defp fixtures_panel(assigns) do
      assigns =
        assign(assigns, :state, fixtures_state(assigns.node, assigns.runs, assigns.block_runs))

      ~H"""
      <p :if={@state == :no_selection} class="sb-inspector__empty">
        Select a block on the canvas to see its fixtures.
      </p>

      <p :if={@state == :no_fixtures} class="sb-inspector__empty">
        No fixtures source is attached to this editor, so this block has no
        recorded cases to run. A host supplies them alongside the document.
      </p>

      <div :if={@state == :compile_error}>
        <p class="sb-inspector__empty">
          This document does not currently compile, so no case can be run.
        </p>
        <ul class="sb-fixtures__findings">
          <li :for={finding <- @runs.findings}>{finding.message}</li>
        </ul>
      </div>

      <p :if={@state == :none_for_block} class="sb-inspector__empty">
        No fixture rows are recorded for this block.
      </p>

      <div :if={@state == :ready} class="sb-fixtures__scroll sb-inspector__fixtures">
        <table>
          <thead>
            <tr>
              <th scope="col">Table</th>
              <th scope="col">Case</th>
              <th scope="col">Expected</th>
              <th scope="col">Taken</th>
              <th scope="col">Verdict</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={run <- @block_runs} data-block={run.block_id} data-row={run.row_name}>
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

    # The runs whose subject is the pane's, in the order the run list holds
    # them - which is the fixture source's own order, so reading down this
    # table is reading the block's cases as they were written.
    #
    # `nil` runs are the editor before it has ever computed any, and they read
    # as "none": there is nothing to filter and nothing to say beyond what the
    # panel's own state says.
    @spec block_runs(term(), ViewModel.Node.t() | nil) :: list()
    defp block_runs(nil, _node), do: []
    defp block_runs(_runs, nil), do: []

    defp block_runs(runs, %ViewModel.Node{block_id: block_id}),
      do: Enum.filter(runs.runs, &(&1.block_id == block_id))

    # Four states, and the order they are resolved in is the order the
    # questions are asked: has the pane a subject, is there a source at all,
    # does the document compile, and does this block have rows.
    @spec fixtures_state(ViewModel.Node.t() | nil, term(), list()) :: atom()
    defp fixtures_state(nil, _runs, _block_runs), do: :no_selection
    defp fixtures_state(_node, nil, _block_runs), do: :no_fixtures

    defp fixtures_state(_node, runs, block_runs) do
      case runs.status do
        :no_fixtures -> :no_fixtures
        :compile_error -> :compile_error
        :ready when block_runs == [] -> :none_for_block
        :ready -> :ready
      end
    end

    # The chip's number, and the whole of what the selection changes about it.
    # With a block selected it is that block's findings, as it always was; with
    # none it is `Shell.findings_count/1` over the document's, which is the one
    # definition of that number - counting `@document_findings` here instead
    # would be the second one, and two of them is the defect that seam closed.
    @spec tab_count(ViewModel.Node.t() | nil, [Finding.t()], [Finding.t()]) :: non_neg_integer()
    defp tab_count(nil, _block_findings, document_findings),
      do: Shell.findings_count(document_findings)

    defp tab_count(%ViewModel.Node{}, block_findings, _document_findings),
      do: length(block_findings)

    # Grouped only when they will be rendered: with something selected the tab
    # is that block's findings and the document's grouping is not asked for.
    @spec document_groups(map()) :: [Shell.findings_group()]
    defp document_groups(%{node: nil} = assigns),
      do: Shell.findings_groups(assigns.root, assigns.document_findings, assigns.orphan_findings)

    defp document_groups(_selected), do: []

    # The pills are the document's, on the same rule the chip above them
    # follows: with a block selected this panel is not rendered, so there is
    # nothing to count. It reads the same list `findings_groups/3` cuts up,
    # which is what keeps the pills summing to the groups beneath them.
    @spec document_counted(map()) :: [Finding.t()]
    defp document_counted(%{node: nil} = assigns), do: assigns.document_findings
    defp document_counted(_selected), do: []

    # The header's subject, in the vocabulary the palette and the canvas use.
    # `entry.label` is decision 10's default-applied label, so it is a string
    # for every resolvable block; the fall through to `type` is the
    # unresolvable case, whose entry is the placeholder's.
    @spec selection_status(ViewModel.Node.t() | nil) :: String.t()
    defp selection_status(nil), do: "no selection"

    defp selection_status(%ViewModel.Node{} = node) do
      case Map.get(node.entry, :label) do
        label when is_binary(label) and label != "" -> label
        _none -> node.type
      end
    end

    @spec label(Shell.inspector_tab()) :: String.t()
    defp label(:config), do: "Config"
    defp label(:findings), do: "Findings"
    defp label(:condition), do: "Condition"
    defp label(:fixtures), do: "Fixtures"
  end
end
