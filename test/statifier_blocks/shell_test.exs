defmodule StatifierBlocks.ShellTest do
  @moduledoc """
  The shell's arrangement, asserted with LiveView absent.

  ADR-0005's 2026-08-29 shell amendment is mostly a claim about where things
  go, and the parts of it that are decisions rather than pixels all live in
  `StatifierBlocks.Shell`: which zoom step a control reaches, how deep the
  document is, which of five states the drawer is in, which blocks its index
  page offers, and which of a block's fields are conditions.

  Deliberately **not** tagged `:liveview`. Everything here runs in the headless
  tree, which is decision 1's promise and the reason `Shell` is not under the
  `Editor` namespace.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{EditorFixtures, Finding, Shell, ViewModel}
  alias StatifierBlocks.Predicates.TruthTable

  setup_all do
    document = EditorFixtures.credit_card()
    view_model = ViewModel.build(document, EditorFixtures.palette(), [])

    %{
      document: document,
      view_model: view_model,
      root: view_model.root,
      fixtures: EditorFixtures.credit_card_tables()
    }
  end

  describe "zoom (8A's toolbar)" do
    # Sabotage: making `zoom_in/1` add 10 rather than step the ladder - 100
    # goes to 110 by coincidence and 90 goes to 100 instead of 100, so this
    # goes red on the step that is not a multiple of ten.
    test "steps along the ladder rather than by a multiplier" do
      assert Shell.zoom_in(100) == 110
      assert Shell.zoom_in(67) == 80
      assert Shell.zoom_out(100) == 90
      assert Shell.zoom_out(67) == 50
    end

    # Sabotage: dropping the `List.last/1` fallback from `zoom_in/1` - the top
    # of the ladder returns nil and every later read of the zoom breaks.
    test "the ends of the ladder are stable" do
      assert Shell.zoom_in(200) == 200
      assert Shell.zoom_out(50) == 50
    end

    # Sabotage: removing the binary clause from `clamp_zoom/1` - a value from a
    # `phx-value-` attribute stops being read at all and every zoom resets to
    # 100, which looks like the control not working rather than like a bug.
    test "an untrusted value resolves to a step, never to a crash" do
      assert Shell.clamp_zoom("125") == 125
      assert Shell.clamp_zoom(123) == 125
      assert Shell.clamp_zoom("banana") == 100
      assert Shell.clamp_zoom(nil) == 100
      assert Shell.clamp_zoom(10_000) == 200
    end
  end

  describe "the document metrics (8A)" do
    # Sabotage: seeding `block_count/1`'s reduce at 0 rather than 1 - every
    # subtree loses its own node and the toolbar under-counts by the depth.
    test "counts every block, the root included", %{root: root} do
      assert Shell.block_count(root) == 6
    end

    # Sabotage: dropping the `+ 1` from `depth/1` - a leaf reports 0 and the
    # whole document reports one less than it has.
    test "depth counts the root as 1", %{root: root} do
      assert Shell.depth(root) == 3
    end
  end

  describe "the drawer's height (2A)" do
    # Sabotage: removing the clamp's `max/2` - a host that stored a height from
    # a build with a different band opens the drawer at a size no control can
    # undo, which is the failure mode of remembering state off-box.
    test "a host's remembered height is bounded on the way in" do
      {min, max, default} = Shell.height_band()

      assert Shell.clamp_height(2.0) == min
      assert Shell.clamp_height(400.0) == max
      assert Shell.clamp_height(12.5) == 12.5
      assert Shell.clamp_height("18.0") == 18.0
      assert Shell.clamp_height(nil) == default
      assert Shell.clamp_height(%{}) == default
    end
  end

  describe "the inspector's tabs (3A)" do
    # Sabotage: adding a fifth tab to `@inspector_tabs` - 3A says the list
    # grows only through the record, so this goes red on the addition rather
    # than after it has shipped. It is four as of ADR-0005's 2026-09-05
    # amendment, "3A admits a Fixtures tab in the inspector", which puts the
    # new tab last and leaves the rule it grew under untouched.
    test "there are exactly four, in the order the ruling lists them" do
      assert Shell.inspector_tabs() == [:config, :findings, :condition, :fixtures]
    end

    # Sabotage: making `inspector_tab/1` return the raw value - a crafted
    # `phx-value-tab` reaches the template as an unknown panel id.
    test "an unknown tab resolves to the first one" do
      assert Shell.inspector_tab("condition") == :condition
      assert Shell.inspector_tab(:findings) == :findings
      assert Shell.inspector_tab("fixtures") == :fixtures
      assert Shell.inspector_tab("datamodel") == :config
      assert Shell.inspector_tab(nil) == :config
    end
  end

  describe "conditions (3A's Condition tab)" do
    # Sabotage: filtering on the field's key rather than its type - the editor
    # starts knowing that `core.branch` names its arms `arm_*`, which is the
    # type-branching decision 2 forbids.
    test "a condition is an :expression field, whatever the type calls it", %{root: root} do
      node = find(root, "blk_cc_decision")

      assert Shell.condition_fields(node.form) |> Enum.map(& &1.key) ==
               ["arm_review", "arm_declined"]

      assert Shell.condition_fields(node.form) |> Enum.map(&Shell.condition_source/1) ==
               ["amount > 500", "risk_band == 'high'"]
    end

    # Sabotage: dropping the `nil` clause - a block with no form (decision
    # 12's unresolvable case) raises instead of showing the empty state.
    test "a block with no form and a block with no conditions both answer []", %{root: root} do
      assert Shell.condition_fields(nil) == []
      assert Shell.condition_fields(find(root, "blk_cc_settle_pause").form) == []
    end
  end

  describe "the drawer's five states (2A)" do
    # Sabotage: returning `jumps` on the closed state - the strip starts
    # carrying an index it never renders, which is work per render for nothing.
    test "collapsed is a strip with the document's count", %{fixtures: fixtures} do
      view = Shell.drawer_view(%{open?: false, fixtures: fixtures, selected_id: nil})

      assert view.status == :closed
      assert view.open? == false
      assert view.title == "Truth tables"
      assert view.count == 1
      assert view.tables == []
    end

    # Sabotage: folding `nil` fixtures into the empty map - the drawer stops
    # being able to say "no source is attached" and says "no block here has a
    # table", which is a false statement about the document.
    test "no fixtures source is its own state, and the drawer still exists" do
      view = Shell.drawer_view(%{open?: true, fixtures: nil, selected_id: "blk_cc_decision"})

      assert view.status == :no_fixtures
      assert view.count == 0
      assert view.jumps == []
    end

    # Sabotage: making the miss state return `status: :ready` with no tables -
    # the drawer opens empty and the index page, which is 2A's answer to the
    # cold-start gap, is never reached.
    test "open with nothing selected is the index page", %{fixtures: fixtures} do
      view = Shell.drawer_view(%{open?: true, fixtures: fixtures, selected_id: nil})

      assert view.status == :no_selection
      assert view.jumps == ["blk_cc_decision"]
      assert view.subject_id == nil
    end

    # Sabotage: answering `:no_selection` for a selected block with no table -
    # the drawer stops being able to say WHICH miss it is in, and the sentence
    # above the index page starts lying about the selection.
    test "open on a block with no table is the index page too", %{fixtures: fixtures} do
      view =
        Shell.drawer_view(%{open?: true, fixtures: fixtures, selected_id: "blk_cc_settle_pause"})

      assert view.status == :none_for_block
      assert view.subject_id == "blk_cc_settle_pause"
      assert view.jumps == ["blk_cc_decision"]
    end

    # Sabotage: keying `tables_for/2` on the table's name rather than the block
    # id - the drawer shows a table for whichever block sorts first and follows
    # nothing.
    test "open on a block that owns one shows it", %{fixtures: fixtures} do
      view = Shell.drawer_view(%{open?: true, fixtures: fixtures, selected_id: "blk_cc_decision"})

      assert view.status == :ready
      assert [%TruthTable{name: "Authorization routing"}] = view.tables
    end

    # Sabotage: counting the selection's tables rather than the document's -
    # the strip reads (0) whenever nothing is selected, which teaches an author
    # the document has no recorded cases.
    test "the count is the document's, not the selection's", %{fixtures: fixtures} do
      for selected <- [nil, "blk_cc_settle_pause", "blk_cc_decision"] do
        view = Shell.drawer_view(%{open?: false, fixtures: fixtures, selected_id: selected})
        assert view.count == 1
      end

      assert Shell.table_count(nil) == 0
      assert Shell.table_count(%{"a" => [], "b" => []}) == 0
    end
  end

  # `sb-4yze`: the fourth drawer tab. `Shell.fixture_row_count/1` is the
  # number the strip carries, and `drawer_tabs/0`'s new last entry is what
  # makes the strip reach it at all.
  describe "the fixtures tab (sb-4yze)" do
    # Sabotage: dropped `:fixtures` from `@drawer_tabs`, leaving the
    # three-tab list. This went red.
    test "drawer_tabs/0 lists fixtures fourth" do
      assert Enum.take(Shell.drawer_tabs(), 4) == [:tables, :findings, :declarations, :fixtures]
    end

    # Sabotage: changed `@drawer_titles`' `fixtures:` entry to
    # `"Fixture Runs"`. This went red.
    test "drawer_title/1 names it Fixtures" do
      assert Shell.drawer_title(:fixtures) == "Fixtures"
    end

    # Sabotage: made `fixture_row_count/1` count TABLES instead of ROWS
    # (`Enum.reduce(fixtures, 0, fn {_id, tables}, acc -> acc + length(tables) end)`,
    # `table_count/1`'s own body) - this went red, reading 1 instead of 4,
    # because `credit_card_tables/0` is one table holding four rows.
    test "fixture_row_count/1 counts rows, not tables", %{fixtures: fixtures} do
      assert Shell.fixture_row_count(fixtures) == 4
      assert Shell.fixture_row_count(nil) == 0
      assert Shell.fixture_row_count(%{"a" => []}) == 0
    end

    # Sabotage: put `:fixtures` ahead of `:tables` in `@drawer_tabs` - a
    # document holding both truth tables and fixture rows opened on the
    # Fixtures tab instead of Truth tables, which is the arrival-order defect
    # the tab's placement exists to avoid. This went red.
    test "an unchosen tab still resolves to :tables first when both tables and fixtures hold rows",
         %{fixtures: fixtures} do
      view = Shell.drawer_view(%{open?: true, fixtures: fixtures})

      assert view.tab == :tables
    end

    # Sabotage: dropped `fixtures` from the `own` list built in `drawer_view/1`
    # - the strip never grew a fourth entry and this went red reading 0 for a
    # document with four fixture rows.
    test "drawer_view/1's own list carries the fixtures tab with the row count", %{
      fixtures: fixtures
    } do
      view = Shell.drawer_view(%{open?: true, fixtures: fixtures})

      assert %{id: :fixtures, title: "Fixtures", count: 4} =
               Enum.find(view.tabs, &(&1.id == :fixtures))
    end

    # Sabotage: dropped `"fixtures"` from `host_tabs/1`'s reserved-names list
    # (left only the four names `@drawer_tabs` produced before this bead) -
    # a host tab named "fixtures" survived the filter and this went red.
    test "host_tabs/1 drops a host tab whose id is \"fixtures\"" do
      shadow = %{id: "fixtures", title: "Mine", count: 3}
      assert Shell.host_tabs([shadow]) == []
    end
  end

  # The fifth drawer tab: the read-only view over every declared datamodel
  # path. The rows are `StatifierBlocks.Datamodel.declared_view/3`'s and are
  # asserted there; what belongs here is where the tab lands, what the strip
  # counts, and the two cell words.
  describe "the datamodel tab" do
    # Sabotage: dropped `:datamodel` from `@drawer_tabs`, leaving the four-tab
    # list. This went red, and so did every other test in this describe.
    test "drawer_tabs/0 lists it last, after fixtures" do
      assert Shell.drawer_tabs() == [:tables, :findings, :declarations, :fixtures, :datamodel]
      assert Shell.drawer_title(:datamodel) == "Datamodel"
    end

    # Sabotage: dropped `datamodel` from the `own` list built in
    # `drawer_view/1` - the strip never grew a fifth entry and this went red
    # with `nil` where the entry should be.
    test "drawer_view/1's own list carries it with the row count" do
      view = Shell.drawer_view(%{open?: true, declared_view: [row("a"), row("b")]})

      assert %{id: :datamodel, title: "Datamodel", count: 2} =
               Enum.find(view.tabs, &(&1.id == :datamodel))
    end

    # Sabotage: `Map.get(state, :declared_view) || []` replaced by
    # `Map.fetch!(state, :declared_view)` - every existing caller that does
    # not pass the key raised, which is what the fallback is for.
    test "counts zero when no rows were supplied" do
      view = Shell.drawer_view(%{open?: true})

      assert %{id: :datamodel, count: 0} = Enum.find(view.tabs, &(&1.id == :datamodel))
    end

    # 2A's resolution rule, reaching the newest tab: an unchosen drawer over a
    # document with nothing else in it opens where the content actually is.
    # Sabotage: put `:datamodel` ahead of `:tables` in `@drawer_tabs` - the
    # second assertion went red, opening on Datamodel for a document that has
    # truth tables in it, which is the arrival-order defect the placement
    # exists to avoid.
    test "an unchosen tab resolves to it only when nothing before it holds anything", %{
      fixtures: fixtures
    } do
      assert Shell.drawer_view(%{open?: true, declared_view: [row("a")]}).tab == :datamodel

      assert Shell.drawer_view(%{
               open?: true,
               fixtures: fixtures,
               declared_view: [row("a")]
             }).tab == :tables
    end

    # Sabotage: dropped `"datamodel"` from `host_tabs/1`'s reserved names by
    # reverting `@drawer_tabs` - a host tab named "datamodel" survived the
    # filter and this went red.
    test "host_tabs/1 drops a host tab whose id is \"datamodel\"" do
      assert Shell.host_tabs([%{id: "datamodel", title: "Mine", count: 3}]) == []
    end

    # Sabotage: `declared_by/1` returning only the first source - the
    # two-surface row read "Datamodel" and this went red.
    test "declared_by/1 names every surface in order" do
      assert Shell.declared_by(row("a", sources: [:datamodel])) == "Datamodel"
      assert Shell.declared_by(row("a", sources: [:declare])) == "Host"
      assert Shell.declared_by(row("a", sources: [:document])) == "Document"

      assert Shell.declared_by(row("a", sources: [:datamodel, :declare, :document])) ==
               "Datamodel, Host, Document"
    end

    # Sabotage: `declared_shape/1`'s `%{type: nil}` clause returning `""` -
    # the shapeless row rendered a blank cell, which reads as a rendering gap
    # rather than as a fact about the declaration.
    test "declared_shape/1 spells the type, the element type, and the absence" do
      assert Shell.declared_shape(row("a", type: :integer)) == "integer"
      assert Shell.declared_shape(row("a", type: :list, item_type: :string)) == "list of string"
      assert Shell.declared_shape(row("a", type: :list)) == "list"
      assert Shell.declared_shape(row("a")) == "unspecified"
    end
  end

  # The descriptor half of the drawer's host-tab seam (8A: slots for markup,
  # events for actions). What a host tab's body renders is
  # `StatifierBlocks.Editor.HostTabTest`'s claim, because it needs a host
  # LiveView to have a render pass at all; what belongs here is where a host
  # tab lands on the strip, which picks of it stand, and which of them never
  # become a tab.
  describe "a host's own drawer tabs" do
    # Sabotage: putting the host tabs before `own` in `drawer_view/1` - the
    # first assertion reads ["runs", :tables, :findings] and goes red, and so
    # does the unchosen-tab resolution below, which is the order's real reader.
    test "join the strip after the package's, in the order they were given" do
      view =
        Shell.drawer_view(%{
          open?: true,
          host_tabs: [host_tab("runs", "Runs", 3), host_tab("jobs", "Jobs", 0)]
        })

      assert Enum.map(view.tabs, & &1.id) == [
               :tables,
               :findings,
               :declarations,
               :fixtures,
               :datamodel,
               "runs",
               "jobs"
             ]

      assert Enum.map(view.tabs, & &1.title) == [
               "Truth tables",
               "Findings",
               "Declarations",
               "Fixtures",
               "Datamodel",
               "Runs",
               "Jobs"
             ]

      assert Enum.map(view.tabs, & &1.count) == [0, 0, 0, 0, 0, 3, 0]
    end

    # Sabotage: keeping `resolve_tab/2`'s old `when tab in @drawer_tabs` guard
    # - a host tab can be listed but never selected, which is the whole seam.
    test "can be picked, and the pick stands" do
      view =
        Shell.drawer_view(%{open?: true, tab: "runs", host_tabs: [host_tab("runs", "Runs", 0)]})

      assert view.tab == "runs"
      assert view.title == "Runs"
      assert view.count == 0
    end

    # Sabotage: resolving against `@drawer_tabs` rather than against the strip
    # - a withdrawn tab stays selected and the drawer names a panel that is not
    # in the DOM.
    test "a pick the host has since withdrawn resolves again" do
      view = Shell.drawer_view(%{open?: true, tab: "runs", host_tabs: []})

      assert view.tab == :tables
    end

    # 2A's rule about the strip, reaching a host tab: a strip is worth having
    # because it says what the drawer holds.
    # Sabotage: `resolve_tab/2` searching `own` instead of `tabs` for a
    # non-zero count - the drawer opens on `Truth tables 0` beside a running
    # feed, which is the state 2A says the strip exists to prevent.
    test "an unchosen tab resolves through them when nothing else holds anything" do
      view = Shell.drawer_view(%{open?: true, host_tabs: [host_tab("runs", "Runs", 4)]})

      assert view.tab == "runs"
      assert view.count == 4
    end

    # Sabotage: dropping the `reject` in `host_tabs/1` - two tabs called
    # "Findings" render, both stamped `sb-drawer-tab-findings`, and the strip
    # has an id collision an author cannot see and a screen reader cannot
    # resolve.
    test "one named for a package tab never becomes a tab" do
      view =
        Shell.drawer_view(%{
          open?: true,
          host_tabs: [host_tab("findings", "Mine", 9), host_tab("tables", "Also mine", 9)]
        })

      assert Enum.map(view.tabs, & &1.id) == [
               :tables,
               :findings,
               :declarations,
               :fixtures,
               :datamodel
             ]

      assert Shell.host_tabs([host_tab("findings", "Mine", 9)]) == []
    end

    # Sabotage: `Enum.uniq/1` instead of `Enum.uniq_by/2` on the id - two
    # entries differing only in title both survive and collide.
    test "a repeated id is kept once" do
      kept = Shell.host_tabs([host_tab("runs", "Runs", 1), host_tab("runs", "Runs again", 2)])

      assert kept == [host_tab("runs", "Runs", 1)]
    end

    # The payload half. A tab name arrives as a string off a `phx-value-tab`
    # attribute, so this is the function a crafted one reaches.
    # Sabotage: `String.to_atom(value)` for an unmatched name - the assertion
    # on the crafted payload reads `:not_a_tab` and goes red, and the atom
    # table grows once per distinct payload.
    test "are resolved by name without any of them becoming an atom" do
      assert Shell.drawer_tab("runs", ["runs"]) == "runs"
      assert Shell.drawer_tab("runs", []) == :tables
      assert Shell.drawer_tab("findings", ["findings"]) == :findings
      assert Shell.drawer_tab("not_a_tab", ["runs"]) == :tables
      assert Shell.drawer_tab("runs") == :tables
    end
  end

  # sb-ukgu: one number, defined once. The claim that the *host's* number is
  # this one is `StatifierBlocks.Editor.FindingsCountTest`'s, because it needs
  # a rendered drawer to compare against; what belongs here is that the tab a
  # host is being pointed at counts what `findings_count/1` counts and not a
  # list of its own.
  describe "the findings number (R4, sb-ukgu)" do
    # Sabotage: `findings_count/1` returning `length(findings) + 1` - the tab
    # follows it, which is the coupling this asserts, so the literal 2 goes
    # red; inlining a count of its own at the tab's call site instead makes
    # the first assertion the one that goes red. Both verified.
    test "the Findings tab's count is findings_count/1 over the document's findings" do
      findings = [
        Finding.new({:block, "blk_cc_decision"}, :lint, "unreachable arm"),
        Finding.new({:block, "blk_gone"}, :resolution, "no such block")
      ]

      view = Shell.drawer_view(%{open?: false, findings: findings, orphan_findings: []})

      tab = Enum.find(view.tabs, &(&1.id == :findings))

      assert tab.count == Shell.findings_count(findings)
      assert tab.count == 2
      assert Shell.findings_count([]) == 0
    end
  end

  # sb-1g4q / campaign-019 D2: the pill row above both document-level findings
  # lists. The markup is the components' tests; what belongs here is that the
  # pills are the same list the count counts, cut a second way.
  describe "the findings number, cut by severity (D2)" do
    defp mixed_findings do
      [
        Finding.new({:block, "blk_cc_decision"}, :lint, "worth a look", severity: :info),
        Finding.new({:config, "blk_cc_capture_pause", "duration"}, :config, "not a number"),
        Finding.new({:block, "blk_variant"}, :lint, "no handler", severity: :warning),
        Finding.new({:block, "blk_gone"}, :resolution, "no such block"),
        Finding.new({:slot, "blk_cc_decision", "then"}, :lint, "thin", severity: :warning)
      ]
    end

    # Most urgent first, whatever order the findings arrived in - the fixture
    # leads with the `:info` on purpose, so an implementation that reported
    # first-appearance order (which is what `findings_groups/3` does, two
    # functions away) would put the advisory at the front of the triage row.
    # Sabotage: reordering `@severity_order` to `[:error, :info, :warning]` -
    # the advisory lands ahead of the two warnings and this goes red.
    test "reads error, warning, info, whatever order they arrived in" do
      assert Shell.severity_counts(mixed_findings()) == [
               %{severity: :error, count: 2},
               %{severity: :warning, count: 2},
               %{severity: :info, count: 1}
             ]
    end

    # The pills and the chip are one list read twice, which is the same
    # property `findings_groups/3` holds and for the same reason: a summary
    # line that disagrees with the list beneath it is the two-numbers defect
    # `findings_count/1` exists to close.
    # Sabotage: counting with `Enum.uniq_by(findings, & &1.severity)` before
    # the tally - every count collapses to 1, the sum reads 3 against a count
    # of 5, and this goes red.
    test "sums to findings_count/1" do
      findings = mixed_findings()
      total = findings |> Shell.severity_counts() |> Enum.map(& &1.count) |> Enum.sum()

      assert total == Shell.findings_count(findings)
      assert total == 5
    end

    # A severity with nothing at it has no pill, on the rule the inspector's
    # tab chip already follows: a row where two of three readings say zero is
    # a row an author learns to stop reading.
    # Sabotage: emitting every severity in `@severity_order` unconditionally -
    # the clean document grows three zero pills and both assertions go red.
    test "omits a severity with nothing at it, and a clean document has no pills" do
      only_errors = [Finding.new({:block, "blk_gone"}, :resolution, "no such block")]

      assert Shell.severity_counts(only_errors) == [%{severity: :error, count: 1}]
      assert Shell.severity_counts([]) == []
    end
  end

  # sb-dbqq: the inspector's Findings tab with nothing selected. The markup is
  # `StatifierBlocks.Editor.InspectorBodyTest`'s; what belongs here is that the
  # grouping keeps every finding the count counts, and that the ones with no
  # block to select still get a group.
  describe "the document's findings, grouped (sb-dbqq)" do
    setup do
      %{
        findings: [
          Finding.new({:block, "blk_cc_decision"}, :lint, "unreachable arm"),
          Finding.new({:config, "blk_cc_capture_pause", "duration"}, :config, "not a number"),
          Finding.new({:slot, "blk_cc_decision", "then"}, :assignability, "wants a step"),
          Finding.new({:block, "blk_gone"}, :resolution, "no such block")
        ]
      }
    end

    # One group per block in first-appearance order, and a block's findings
    # together however their anchors were shaped - the `:slot` finding on
    # `blk_cc_decision` belongs with that block's `:block` finding, and an
    # implementation that grouped by the anchor's tag would split them.
    # Sabotage: grouping on the whole anchor rather than on its block id - the
    # decision block gets two groups and the first assertion goes red.
    test "groups by block, in first appearance order", %{root: root, findings: findings} do
      groups = Shell.findings_groups(root, findings, [Enum.at(findings, 3)])

      assert Enum.map(groups, & &1.block_id) == ["blk_cc_decision", "blk_cc_capture_pause", nil]
      assert Enum.map(groups, & &1.label) == ["Branch", "Wait", "Unanchored"]

      [decision | _rest] = groups
      assert Enum.map(decision.findings, & &1.source) == [:lint, :assignability]
    end

    # The count and the panel are one list read twice, so the panel cannot show
    # fewer than the chip beside it counts. Orphans are the case that breaks:
    # they are inside `findings_count/1` and they have no block to file under.
    # Sabotage: dropping `append_unanchored/2`'s non-empty clause - the orphan
    # vanishes from the panel while the chip still counts it, and both the
    # total and the last-group assertion go red.
    test "keeps every finding the count counts, orphans last", %{root: root, findings: findings} do
      orphan = Enum.at(findings, 3)
      groups = Shell.findings_groups(root, findings, [orphan])

      total = groups |> Enum.flat_map(& &1.findings) |> length()
      assert total == Shell.findings_count(findings)

      last = List.last(groups)
      assert last.block_id == nil
      assert last.findings == [orphan]
    end

    # A document with nothing wrong with it has no groups, not one empty group.
    # Sabotage: making `append_unanchored/2` append unconditionally - the clean
    # document grows an "Unanchored" heading over nothing and this goes red.
    test "a clean document groups into nothing", %{root: root} do
      assert Shell.findings_groups(root, [], []) == []
    end

    # `root` is read for labels and nothing else, so a caller that has none
    # still gets the grouping - with the id standing in, which is what
    # `label_for/2` answers for a block the tree does not hold anyway.
    # Sabotage: `group_label/2` raising on a nil root - this goes red rather
    # than the component quietly requiring an assign it does not need.
    test "labels fall back to the block id with no root", %{findings: findings} do
      assert [%{label: "blk_cc_decision"} | _rest] = Shell.findings_groups(nil, findings, [])
    end
  end

  describe "the index page's labels" do
    # Sabotage: returning the block id from `label_for/2` unconditionally - the
    # jump list becomes a column of opaque ids and the reason the index page
    # exists (finding the block you meant) goes with it.
    test "a jump is labelled by its type's palette label", %{root: root} do
      assert Shell.label_for(root, "blk_cc_decision") == "Branch"
      assert Shell.label_for(root, "blk_nope") == "blk_nope"
    end
  end

  describe "where a block sits (the inspector's BLOCK section)" do
    # The signup fixture is the subject here rather than `credit_card`, because
    # its branch has two differently labelled arms and an unresolvable block
    # with a raw slot - the three answers this function has to tell apart.
    setup do
      view_model = ViewModel.build(EditorFixtures.signup_wizard(), EditorFixtures.palette(), [])
      %{signup_root: view_model.root}
    end

    # The load-bearing pair is `blk_email_step`: it sits in the slot NAMED
    # `body` and LABELLED `Steps`, so an implementation that reached for the
    # slot name renders a word the canvas never shows.
    # Sabotage: returning `slot.name` instead of `slot.label` - the first
    # assertion goes red on "body", which is the defect this row exists to
    # avoid stating to an author.
    test "is the slot's label, not its name", %{signup_root: root} do
      assert Shell.slot_label(root, "blk_email_step") == "Steps"
      assert Shell.slot_label(root, "blk_control_pause") == "Otherwise"
    end

    # A raw slot has no label to read, and `ViewModel` already answers with the
    # name itself - the same string the canvas draws over that stranded slot.
    # Sabotage: making the recursion skip a node whose own status is
    # unresolvable - the child of the tracking block stops being locatable and
    # this goes red with nil.
    test "reaches a child of an unresolvable block, under its raw slot name", %{
      signup_root: root
    } do
      assert Shell.slot_label(root, "blk_settle_pause") == "after"
    end

    # Sabotage: dropping the `block_id: id` clause - the root walks its own
    # slots looking for itself, finds nothing, and the row reads as a dash on
    # the one block that is always in the document.
    test "the root sits in no slot, and says so", %{signup_root: root} do
      assert Shell.slot_label(root, "blk_wizard") == "root"
    end

    # Both nil cases are the same answer on purpose: a selection that went away
    # between two builds is no selection, and the row has one empty state.
    # Sabotage: letting the walk raise on an unknown id rather than answering
    # nil - a stale selection takes the whole pane down instead of blanking one
    # row.
    test "an id no node carries, and no id at all, are both nil", %{signup_root: root} do
      assert Shell.slot_label(root, "blk_deleted_long_ago") == nil
      assert Shell.slot_label(root, nil) == nil
    end
  end

  describe "where an armed insertion would land (sb-dfyk)" do
    setup do
      view_model = ViewModel.build(EditorFixtures.signup_wizard(), EditorFixtures.palette(), [])
      %{signup_root: view_model.root}
    end

    # The same load-bearing pair `slot_label/2` has, one level out: the slot is
    # NAMED `body` and LABELLED `Steps`, and the whole point of the sentence the
    # palette prints is to name the place in the words already on the canvas.
    # Sabotage: returning `slot.name` rather than `slot.label` - the instruction
    # reads "into Steps" nowhere and "into body" instead, and this goes red.
    test "names the slot by its label and the holder by its title", %{signup_root: root} do
      assert Shell.insert_target(root, {"blk_wizard", "body", 0}) ==
               %{slot: "Steps", parent: "Sequence"}

      assert Shell.insert_target(root, {"blk_variant", "otherwise", 0}) ==
               %{slot: "Otherwise", parent: "Branch"}
    end

    # The index is not part of the answer. Three gaps in one slot are three
    # different positions and one destination, and an instruction that changed
    # between them would be reporting an implementation detail.
    # Sabotage: folding the index into the map - the two calls stop being equal
    # and this goes red.
    test "does not vary with the index within the slot", %{signup_root: root} do
      assert Shell.insert_target(root, {"blk_wizard", "body", 0}) ==
               Shell.insert_target(root, {"blk_wizard", "body", 3})
    end

    # Three nil cases, one answer: nothing armed, a holder that is gone, and a
    # slot the holder does not declare all mean there is no destination to name.
    # Sabotage: dropping the `with` and matching the slot directly - the second
    # and third raise instead of answering nil, which takes the pane down on the
    # render after an edit removed the block a gap was armed in.
    test "nothing armed, a vanished holder, and an unknown slot are all nil", %{
      signup_root: root
    } do
      assert Shell.insert_target(root, nil) == nil
      assert Shell.insert_target(root, {"blk_deleted_long_ago", "body", 0}) == nil
      assert Shell.insert_target(root, {"blk_wizard", "no_such_slot", 0}) == nil
    end
  end

  describe "the selected block's findings (3A)" do
    # Sabotage: using `view_model.findings` instead - the inspector's tab
    # becomes the document-level panel, which is exactly the conflation 3A
    # exists to end.
    test "is the block's own, not the document's", %{document: document} do
      view_model =
        ViewModel.build(document, EditorFixtures.palette(), [
          Finding.new({:block, "blk_cc_decision"}, :lint, "watch this one"),
          Finding.new({:block, "blk_cc_capture_pause"}, :lint, "and this one")
        ])

      node = find(view_model.root, "blk_cc_decision")

      assert Enum.map(Shell.block_findings(node), & &1.message) == ["watch this one"]
      assert Shell.block_findings(nil) == []
    end
  end

  describe "a cell's status reads as a word" do
    # Sabotage: mapping two statuses to one word - `:undecidable` and
    # `:mismatch` stop being distinguishable, and they are different findings
    # rather than two points on one ramp. Asserted against the five statuses
    # directly, because a fixture that happens not to reach one of them would
    # let the collision through.
    test "each of the five gets its own" do
      words =
        for status <- [:match, :mismatch, :unchecked, :error, :undecidable],
            do: Shell.cell_word(%TruthTable.Cell{status: status})

      assert words == ~w(match mismatch unchecked error undecidable)
    end

    # The corroborator: the words the drawer actually renders come off a real
    # table rather than off the five-way map above.
    # Sabotage: returning the status atom's `inspect/1` instead - the cells
    # render as `:match` and this goes red.
    test "and a built table renders through it", %{fixtures: fixtures} do
      [table] = Map.fetch!(fixtures, "blk_cc_decision")
      words = table.rows |> Enum.flat_map(& &1.cells) |> Enum.map(&Shell.cell_word/1)

      assert "match" in words
      assert Enum.all?(words, &(&1 in ~w(match mismatch unchecked error undecidable)))
    end
  end

  describe "the fixture hint (ADR-0005's 2026-09-05 note)" do
    # A table built here rather than reused, so row order is this test's own
    # subject: `paths` declares `band` after `amount`, and the rows bind
    # values that are neither alphabetical nor unique.
    defp hint_tables(rows) do
      {:ok, table} =
        TruthTable.build(
          %{
            name: "Routing",
            paths: ["amount", "band"],
            columns: [%{key: "yes", label: "Yes", source: "amount > 500"}]
          },
          rows
        )

      %{"blk" => [table]}
    end

    @rows [
      %{name: "first", bindings: %{"amount" => "120", "band" => "'low'"}},
      %{name: "second", bindings: %{"amount" => "900", "band" => "'high'"}},
      %{name: "third", bindings: %{"amount" => "120", "band" => "'mid'"}}
    ]

    # Sabotage: took `List.last/1` of the distinct values as the exemplar
    # rather than the first - this read 900, and the reordered call read it
    # too. Worth knowing what this test alone does NOT catch: reversing the
    # ROW list leaves it green, because `amount` happens to be 120 at both
    # ends. The test below is the discriminating one, and the two are drawn
    # together for that reason.
    test "the exemplar is the first row's value in declaration order" do
      assert %{value: "120"} = Shell.fixture_hint(hint_tables(@rows), "blk", "amount > 500")

      reordered = Enum.reverse(@rows)
      assert %{value: "120"} = Shell.fixture_hint(hint_tables(reordered), "blk", "amount > 500")
    end

    # The reordering above is the real assertion of "declaration order": the
    # same three rows in the opposite order answer the OTHER end, which no
    # alphabetical or most-common rule would do.
    #
    # Sabotage: `Enum.reverse/1` in front of `hint_values/2`'s pipeline, which
    # is the "most recent" rule the record rules out - this test went red, and
    # it is the only one of the three that could not be satisfied by a
    # coincidence of the values chosen.
    test "reordering the rows moves the exemplar with them" do
      reordered = Enum.reverse(@rows)

      assert %{value: "'mid'"} = Shell.fixture_hint(hint_tables(reordered), "blk", "band == 'x'")
      assert %{value: "'low'"} = Shell.fixture_hint(hint_tables(@rows), "blk", "band == 'x'")
    end

    # Sabotage: dropped `Enum.uniq/1` from `hint_values/2` - the list came
    # back as ["120", "900", "120"], which is the duplicate the `title` is
    # there to summarise away. This went red.
    test "the whole set is distinct, in first-appearance order" do
      assert %{values: ["120", "900"]} =
               Shell.fixture_hint(hint_tables(@rows), "blk", "amount > 500")

      assert %{values: ["'low'", "'high'", "'mid'"]} =
               Shell.fixture_hint(hint_tables(@rows), "blk", "band == 'x'")
    end

    # A row that binds nothing for the path contributes nothing rather than
    # an empty entry - `credit_card_tables/0`'s fourth row leaves `risk_band`
    # unbound on purpose, which is why it is the subject here.
    #
    # Sabotage: `Map.get/3` in place of the `Map.fetch/2` case, so an unbound
    # path yields `to_hint_text(nil)` - the title grew a third value reading
    # "nil", which is a value no fixture row declares. This went red.
    test "a row that does not bind the path contributes no value", %{fixtures: fixtures} do
      assert %{values: values} =
               Shell.fixture_hint(fixtures, "blk_cc_decision", "risk_band == 'high'")

      assert values == ["'low'", "'high'"]
    end

    # Sabotage: made `hint_path/2` take the first match in declared order
    # rather than longest-first - "user.age" answered for "user.age_group",
    # and the hint named a path the source does not read. This went red.
    test "a path that is a prefix of another does not answer for it" do
      {:ok, table} =
        TruthTable.build(
          %{
            name: "Ages",
            paths: ["user.age", "user.age_group"],
            columns: [%{key: "yes", label: "Yes", source: "user.age > 18"}]
          },
          [%{name: "one", bindings: %{"user.age" => "21", "user.age_group" => "'adult'"}}]
        )

      fixtures = %{"blk" => [table]}

      assert %{path: "user.age_group", value: "'adult'"} =
               Shell.fixture_hint(fixtures, "blk", "user.age_group == 'adult'")

      assert %{path: "user.age", value: "21"} =
               Shell.fixture_hint(fixtures, "blk", "user.age > 18")
    end

    # A condition still empty is the common case on a block just dropped, and
    # the record's hint is worth having exactly then. The first declared path
    # is what it falls back to.
    #
    # Sabotage: dropped the `|| first` fallback from `hint_path/2` - a block
    # whose condition names nothing yet got no hint at all, which is the case
    # the hint is most useful in. This went red.
    test "a source naming no path falls back to the first declared path" do
      assert %{path: "amount", value: "120"} =
               Shell.fixture_hint(hint_tables(@rows), "blk", "")

      assert %{path: "amount"} = Shell.fixture_hint(hint_tables(@rows), "blk", nil)
    end

    # Sabotage: answered `%{path: nil, value: "", values: []}` instead of nil
    # for a block with no rows - `Field.field/1` then drew an empty element
    # with an empty `title`, which is precisely the empty affordance the
    # record calls silence instead. This went red on the `nil` assertions.
    test "no rows, no source and no such block all answer nil", %{fixtures: fixtures} do
      assert Shell.fixture_hint(nil, "blk_cc_decision", "amount > 500") == nil
      assert Shell.fixture_hint(fixtures, nil, "amount > 500") == nil
      assert Shell.fixture_hint(fixtures, "blk_cc_capture_pause", "amount > 500") == nil
      assert Shell.fixture_hint(%{"blk" => []}, "blk", "amount > 500") == nil
      assert Shell.fixture_hint(hint_tables([]), "blk", "amount > 500") == nil
    end
  end

  # One host tab descriptor, in the shape the editor derives from a
  # `:drawer_tab` slot entry.
  defp host_tab(id, title, count), do: %{id: id, title: title, count: count}

  # One row of `StatifierBlocks.Datamodel.declared_view/3`'s shape, built by
  # hand so the strip's arithmetic is asserted without a document behind it.
  defp row(path, opts \\ []) do
    %{
      path: path,
      sources: Keyword.get(opts, :sources, [:datamodel]),
      type: Keyword.get(opts, :type),
      item_type: Keyword.get(opts, :item_type),
      scope: Keyword.get(opts, :scope),
      label: Keyword.get(opts, :label),
      sensitive?: false
    }
  end

  defp find(%ViewModel.Node{block_id: id} = node, id), do: node

  defp find(%ViewModel.Node{slots: slots}, id) do
    slots |> Enum.flat_map(& &1.children) |> Enum.find_value(&find(&1, id))
  end
end
