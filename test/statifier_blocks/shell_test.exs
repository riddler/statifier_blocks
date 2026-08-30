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

  alias StatifierBlocks.{EditorFixtures, Shell, ViewModel}
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

  describe "the selected block's findings (3A)" do
    # Sabotage: using `view_model.findings` instead - the inspector's tab
    # becomes the document-level panel, which is exactly the conflation 3A
    # exists to end.
    test "is the block's own, not the document's", %{document: document} do
      view_model =
        ViewModel.build(document, EditorFixtures.palette(), [
          StatifierBlocks.Finding.new({:block, "blk_cc_decision"}, :lint, "watch this one"),
          StatifierBlocks.Finding.new({:block, "blk_cc_capture_pause"}, :lint, "and this one")
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
