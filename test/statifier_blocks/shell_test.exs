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
    # Sabotage: adding a fourth tab to `@inspector_tabs` - 3A says exactly
    # three and that the list will grow only through the record, so this goes
    # red on the addition rather than after it has shipped.
    test "there are exactly three, in the order the ruling lists them" do
      assert Shell.inspector_tabs() == [:config, :findings, :condition]
    end

    # Sabotage: making `inspector_tab/1` return the raw value - a crafted
    # `phx-value-tab` reaches the template as an unknown panel id.
    test "an unknown tab resolves to the first one" do
      assert Shell.inspector_tab("condition") == :condition
      assert Shell.inspector_tab(:findings) == :findings
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

  defp find(%ViewModel.Node{block_id: id} = node, id), do: node

  defp find(%ViewModel.Node{slots: slots}, id) do
    slots |> Enum.flat_map(& &1.children) |> Enum.find_value(&find(&1, id))
  end
end
