defmodule StatifierBlocks.Compiler.DraftsTest do
  @moduledoc """
  What the shelf and the gap marker mean to the compiler: ADR-0004's
  amendment of 2026-08-31, sections D1 through D6, and ADR-0003's section
  A2.

  D1's byte identity is the acceptance property and is asserted first,
  because everything else in that record is a consequence of it: if a
  parked fragment reached the chart, nothing else here would matter.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{Assignability, Block, Compiler, CoreFixtures, Document, Palette}

  defp step(id, duration \\ "PT1H"),
    do: Block.new("core.wait", id: id, config: %{"duration" => duration})

  defp marker(id, note \\ ""),
    do: Block.new("core.placeholder", id: id, config: %{"note" => note})

  defp shelf(id, children),
    do: Block.new("core.drafts", id: id, slots: %{"body" => children})

  defp document(body, id \\ "bdoc_D") do
    Document.new(Block.new("core.sequence", id: "blk_ROOT", slots: %{"body" => body}), id: id)
  end

  defp compiled!(document) do
    assert {:ok, compiled} = Compiler.compile(document, Palette.core())
    compiled
  end

  # Four fragments, deliberately noisy: a container, a leaf that writes
  # data, a marker, and a nested group. If any of them reached the chart,
  # the byte comparison below would move.
  defp fragments do
    [
      Block.new("core.sequence", id: "blk_F1", slots: %{"body" => [step("blk_F1A", "PT9H")]}),
      Block.new("core.assign", id: "blk_F2", config: %{"path" => "parked", "value" => "true"}),
      marker("blk_F3", "the refund arm"),
      Block.new("core.group", id: "blk_F4", slots: %{"body" => [step("blk_F4A", "PT7H")]})
    ]
  end

  defp occupied, do: document([step("blk_A"), shelf("blk_SHELF", fragments()), step("blk_B")])
  defp empty_shelf, do: document([step("blk_A"), shelf("blk_SHELF", []), step("blk_B")])
  defp no_shelf, do: document([step("blk_A"), step("blk_B")])

  describe "D1: the shelf contributes nothing, and that is the acceptance property" do
    # Sabotage: dropped the `Enum.split_with/2` from `elide_shelf/1` so the
    # shelf stayed in the tree - red on all three comparisons, which is the
    # entire failure the type exists to prevent.
    test "an occupied shelf, an empty one, and no shelf compile to identical bytes" do
      occupied = compiled!(occupied())
      empty = compiled!(empty_shelf())
      none = compiled!(no_shelf())

      assert occupied.scxml == empty.scxml
      assert occupied.scxml == none.scxml
    end

    # Sabotage: made `elide_shelf/1` prune the shelf but keep emitting its
    # children into the root - red here on the ids, and the parked
    # fragments would be addressable at runtime.
    test "the provenance map has no entry for a shelved block, and no id is minted" do
      occupied = compiled!(occupied())
      shelved = ["blk_SHELF", "blk_F1", "blk_F1A", "blk_F2", "blk_F3", "blk_F4", "blk_F4A"]

      owners =
        occupied.provenance.spans
        |> Enum.map(fn {_span, %{block_id: block_id}} -> block_id end)
        |> MapSet.new()

      for id <- shelved do
        refute MapSet.member?(owners, id), "#{id} reached the provenance map"
        refute occupied.scxml =~ id, "#{id} reached the chart"
      end

      assert occupied.scxml =~ "blk_A"
    end

    # The self-reference refusal walks the assembled emission, so it is the
    # stage that proves the shelf's contents never got there: a parked
    # subchart naming this very document would refuse the compile if any of
    # it had been emitted, and does not.
    #
    # Sabotage: dropped the `Enum.split_with/2` from `elide_shelf/1` - red
    # here on the refusal, and a fragment an author had not placed would be
    # deciding whether their document compiles at all.
    test "a parked subchart naming this document is not a self-reference" do
      parked_subchart =
        shelf("blk_SHELF", [
          Block.new("core.subchart",
            id: "blk_SUB",
            config: %{"chart" => "bdoc_SELF", "outcomes" => "done"}
          )
        ])

      in_the_flow =
        Block.new("core.subchart",
          id: "blk_SUB2",
          config: %{"chart" => "bdoc_SELF", "outcomes" => "done"}
        )

      assert {:ok, _compiled} =
               Compiler.compile(
                 document([step("blk_A"), parked_subchart], "bdoc_SELF"),
                 Palette.core()
               )

      # The same block in the flow is refused, which is what says the arm
      # above is the shelf and not a hole in the check.
      assert {:error, _findings} =
               Compiler.compile(
                 document([step("blk_A"), in_the_flow], "bdoc_SELF"),
                 Palette.core()
               )
    end
  end

  describe "D6: two hashes, and only one of them moves" do
    # Sabotage: made `record/3` read the pruned tree for `document_hash` -
    # red here, since shelf activity has to move the document hash or an
    # editor could not tell that the document changed.
    test "differing shelves have different document hashes and the same chart identity" do
      occupied = compiled!(occupied())
      empty = compiled!(empty_shelf())

      refute occupied.record.document_hash == empty.record.document_hash
      assert occupied.record.chart_identity == empty.record.chart_identity
    end
  end

  describe "D4: two warnings, on a compile that succeeds" do
    # Sabotage: made `drafts_warning/1` mint one finding per fragment - red
    # here on the count, which is D4's argument that the warning's loudness
    # must not track how much the author parked.
    test ":draft_blocks_present is one per document, on the shelf" do
      warnings = compiled!(occupied()).warnings
      present = Enum.filter(warnings, &(&1.code == :draft_blocks_present))

      assert [finding] = present
      assert finding.stage == :emit
      assert finding.severity == :warning
      assert finding.fault == :author
      assert finding.block_id == "blk_SHELF"
    end

    # Sabotage: dropped the emptiness guard from `drafts_warning/1` - red
    # here. An empty shelf has nothing to say, and with D1's byte identity
    # that makes it invisible to every consumer of a compile.
    test "an empty shelf mints nothing at all" do
      empty = compiled!(empty_shelf())

      assert Enum.filter(empty.warnings, &(&1.code == :draft_blocks_present)) == []
      assert empty.warnings == compiled!(no_shelf()).warnings
    end

    # Sabotage: made `marker_warnings/1` stop at the root - red here on the
    # nested marker, since each gap is at a distinct place in the flow.
    test ":placeholder_block is one per marker, and carries the note" do
      in_flow =
        document([
          marker("blk_G1", "the refund arm"),
          Block.new("core.group", id: "blk_G", slots: %{"body" => [marker("blk_G2")]})
        ])

      markers =
        in_flow
        |> compiled!()
        |> Map.fetch!(:warnings)
        |> Enum.filter(&(&1.code == :placeholder_block))

      assert [first, second] = markers
      assert first.block_id == "blk_G1"
      assert first.message =~ "the refund arm"
      assert second.block_id == "blk_G2"
      refute second.message =~ ~s(")

      for finding <- markers do
        assert finding.stage == :emit
        assert finding.severity == :warning
        assert finding.fault == :author
      end
    end

    # Sabotage: dropped the `Enum.split_with/2` from `elide_shelf/1`, so
    # the shelf stayed in the tree - red here, because the parked marker is
    # then walked like any other. A marker on the shelf is not a gap in the
    # flow; it is a fragment that is not in the flow at all.
    test "a marker parked on the shelf warns about nothing" do
      parked = document([step("blk_A"), shelf("blk_SHELF", [marker("blk_PARKED", "later")])])

      assert Enum.filter(compiled!(parked).warnings, &(&1.code == :placeholder_block)) == []
    end
  end

  describe "D5: the marker compiles to a step that does nothing" do
    # Sabotage: made `Placeholder.emit/2` return an empty emission - red
    # here, because the flow would break around the gap rather than walking
    # through it.
    test "the chart runs and the macrostep walks straight through the gap" do
      compiled = compiled!(document([marker("blk_GAP", "the refund arm"), step("blk_AFTER")]))

      assert compiled.scxml =~ ~s(<state id="s_blk_GAP")
      refute compiled.scxml =~ "the refund arm"
      refute compiled.scxml =~ "<log"

      assert {:ok, machine} = Statifier.compile(compiled.scxml)
      {machine_state, _effects} = Statifier.initialize(machine)
      leaves = Statifier.active_leaf_states(machine_state)

      # The gap completes on entry, so the session has already walked
      # through it and is waiting at the step after it.
      assert MapSet.member?(leaves, "s_blk_AFTER__waiting")
      refute MapSet.member?(leaves, "s_blk_GAP")
    end
  end

  describe "A2: the shelf is at entry, and the walk still runs inside a fragment" do
    # The fragments have to declare real type expressions or the assertion
    # is vacuous: every core type answers `:unknown` anyway, so a shelf of
    # core blocks would read as "at entry" whether the rule existed or not.
    # `myapp.authorize` produces `myapp.credit_card_txn` and `myapp.capture`
    # consumes it, so on the shelf there is a seam to get wrong.
    defp typed_palette,
      do: Palette.new(Map.merge(Palette.core_types(), CoreFixtures.host_types()))

    defp typed_shelf do
      document([
        step("blk_A"),
        shelf("blk_SHELF", [
          Block.new("myapp.authorize", id: "blk_P1", type_version: 2, config: %{}),
          Block.new("myapp.capture", id: "blk_P2"),
          Block.new("myapp.notify", id: "blk_P3")
        ])
      ])
    end

    # Sabotage: dropped the `on_the_shelf?/2` arm from `inbound_type/4` -
    # red at index 1 and 2, where the previous fragment's `produces` would
    # answer. Rearranging a shelf would then produce and clear findings,
    # which is exactly the sequencing meaning the shelf is defined not to
    # have.
    test "every direct child of the shelf is at entry, whatever its index" do
      doc = typed_shelf()

      for index <- 0..3 do
        assert Assignability.inbound_type(typed_palette(), doc, {"blk_SHELF", "body", index}, %{}) ==
                 :unknown,
               "index #{index} read the shelf as a flow"
      end

      # The same two blocks adjacent in the *flow* do carry the seam, which
      # is what says the rule above is about the shelf and not about the
      # two types.
      in_flow =
        document([
          Block.new("myapp.authorize", id: "blk_P1", type_version: 2, config: %{}),
          Block.new("myapp.capture", id: "blk_P2")
        ])

      assert Assignability.inbound_type(typed_palette(), in_flow, {"blk_ROOT", "body", 1}, %{}) ==
               "myapp.credit_card_txn"
    end

    # Sabotage: dropped the `on_the_shelf?/2` arm from `inbound_type/4` -
    # red here too, and in the form an author would actually meet it: a
    # fragment parked out of order would refuse the whole document.
    test "a fragment parked before the one it consumes from refuses nothing" do
      out_of_order =
        document([
          step("blk_A"),
          shelf("blk_SHELF", [
            Block.new("myapp.capture", id: "blk_P2"),
            Block.new("myapp.authorize", id: "blk_P1", type_version: 2, config: %{})
          ])
        ])

      assert {:ok, _compiled} = Compiler.compile(out_of_order, typed_palette())
    end

    # A2's own example, asserted rather than paraphrased: structural
    # checking is not suspended on the shelf, because `slot_accepts: :any`
    # is a claim about what the shelf's own body admits and says nothing
    # about what a fragment's own slots admit.
    #
    # Sabotage: made `structure_stage/3` walk a shelf-pruned copy of the
    # document instead of the document - red here, and every rule the
    # Structure stage owns would stop reaching a parked fragment. That
    # ordering is the load-bearing half of where the elision sits, and it
    # is why the elision prunes the resolved tree and never the document.
    test "a parked group still refuses an ordinary step in its interrupts slot" do
      parked_broken =
        shelf("blk_SHELF", [
          Block.new("core.group",
            id: "blk_F",
            slots: %{"body" => [], "interrupts" => [step("blk_WRONG")]}
          )
        ])

      assert {:error, findings} =
               Compiler.compile(document([step("blk_A"), parked_broken]), Palette.core())

      assert [%{code: :kind_not_admitted, block_id: "blk_WRONG", stage: :structure}] = findings
    end

    # Sabotage: made `on_the_shelf?/2` true for every descendant of the
    # shelf rather than for a direct child of it - red here, and an author
    # who parks a three-block fragment would stop being told about a broken
    # seam inside it, which is exactly what A2 says makes the shelf worth
    # having rather than a hole in the checker.
    test "inside a fragment the walk is the ordinary one" do
      doc = occupied()

      # `blk_F1`'s body is a fragment's own slot, not the shelf's, so the
      # position resolves through the ordinary rule - the same answer the
      # same container gives when it is not parked at all.
      assert Assignability.inbound_type(Palette.core(), doc, {"blk_F1", "body", 0}, %{}) ==
               Assignability.inbound_type(
                 Palette.core(),
                 document([Block.new("core.sequence", id: "blk_F1", slots: %{"body" => []})]),
                 {"blk_F1", "body", 0},
                 %{}
               )
    end
  end
end
