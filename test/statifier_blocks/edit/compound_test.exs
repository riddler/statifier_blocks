defmodule StatifierBlocks.Edit.CompoundTest do
  use ExUnit.Case, async: true

  alias StatifierBlocks.{Block, Document, Edit, Palette}
  alias StatifierBlocks.Edit.History

  # A group with one step in its body and nothing on its rail - the smallest
  # tree the deadline arrangement is written against.
  #
  #   blk_ROOT (core.group)
  #     body: [blk_STEP]
  defp document do
    step = Block.new("core.wait", id: "blk_STEP", config: %{"duration" => "1s"})

    Document.new(
      Block.new("core.group", id: "blk_ROOT", slots: %{"body" => [step]}),
      id: "bdoc_COMPOUND"
    )
  end

  defp send_block(id), do: Block.new("core.send", id: id, config: %{"event" => "a.b"})

  describe "apply/2 over a composition (clause 2n)" do
    # Sabotage: `apply_compound/3` folding right to left - the second insert
    # is applied first, its index 1 is out of range against a one-child slot,
    # and this goes red on `:index_out_of_range` rather than on the order.
    test "applies its members left to right against the intermediate documents" do
      commands = [
        {:insert, {"blk_ROOT", "body", 1}, send_block("blk_ONE")},
        {:insert, {"blk_ROOT", "body", 2}, send_block("blk_TWO")}
      ]

      assert {:ok, %Document{} = after_doc, _inverse} =
               Edit.apply(document(), {:compound, commands})

      assert ["blk_STEP", "blk_ONE", "blk_TWO"] ==
               Enum.map(after_doc.root.slots["body"], & &1.id)
    end

    # The round-trip law of ADR-0005 decision 3, for the composition: the
    # inverse is the compound of each member's inverse IN REVERSE ORDER, and
    # applying it returns the document as a struct, not merely as equal bytes.
    #
    # Sabotage: returning `{:compound, Enum.reverse(inverses)}` - the
    # accumulator is already head-first, so reversing it puts the inverses
    # back in forward order and this goes red with `blk_ONE` still in the
    # tree.
    test "its inverse is the members' inverses, reversed" do
      before = document()

      commands = [
        {:insert, {"blk_ROOT", "body", 0}, send_block("blk_ONE")},
        {:insert, {"blk_ROOT", "body", 0}, send_block("blk_TWO")}
      ]

      assert {:ok, changed, inverse} = Edit.apply(before, {:compound, commands})
      assert {:compound, [{:remove, "blk_TWO"}, {:remove, "blk_ONE"}]} = inverse
      assert {:ok, ^before, _re_inverse} = Edit.apply(changed, inverse)
    end

    # A member that refuses refuses the whole compound, with its OWN error
    # term and no document at all - so there is no partially applied document
    # for a caller to mistake for a result.
    #
    # Sabotage: `apply_compound/3` skipping a refusing member instead of
    # propagating - the call answers `{:ok, ...}` and both assertions go red.
    test "a member's refusal is the compound's refusal, verbatim" do
      commands = [
        {:insert, {"blk_ROOT", "body", 0}, send_block("blk_ONE")},
        {:remove, "blk_NOWHERE"}
      ]

      assert {:error, {:no_such_block, "blk_NOWHERE"}} =
               Edit.apply(document(), {:compound, commands})
    end

    # Clause 2n: the leaves are drawn from the five and nothing else. Both
    # malformed shapes are refused rather than flattened.
    #
    # Sabotage: dropping `check_compound/1` from the `:compound` clause - the
    # empty list applies to `{:ok, doc, {:compound, []}}` and the nested one
    # flattens silently, so both assertions go red.
    test "an empty list and a nested compound are refused" do
      assert {:error, {:malformed_envelope, {:compound, :empty}}} =
               Edit.apply(document(), {:compound, []})

      nested = {:compound, [{:compound, [{:remove, "blk_STEP"}]}]}

      assert {:error, {:malformed_envelope, {:compound, :nested}}} =
               Edit.apply(document(), nested)
    end
  end

  describe "the gate and the history (clause 2n)" do
    # `check_config/3` runs on the LEAVES, each against the document the
    # leaves before it produced. Here the config that must be refused belongs
    # to a block the compound itself inserts, so a gate that asked the
    # ORIGINAL document would find no such block and let it through.
    #
    # Sabotage: `check_leaf/3` passing `document` rather than the advanced
    # one - the `:update_config` names a block the original document does not
    # hold, `check_config/3` answers `:ok`, and this goes red with the invalid
    # config in the tree.
    test "the config gate reaches a leaf that edits a block an earlier leaf inserted" do
      commands = [
        {:insert, {"blk_ROOT", "body", 0}, send_block("blk_ONE")},
        {:update_config, "blk_ONE", %{"event" => "not a valid event name"}}
      ]

      assert {:error, {:invalid_config, "blk_ONE", _findings}} =
               Edit.check_config(Palette.core(), document(), {:compound, commands})
    end

    # The property the constructor exists for: one commit, one entry, so one
    # undo takes the whole arrangement back out.
    #
    # Sabotage: `History.commit/4` pushing one inverse per leaf - the first
    # undo leaves `blk_ONE` behind and the "both halves gone" assertion goes
    # red.
    test "a compound is one undo entry, and redo puts the whole thing back" do
      before = document()
      palette = Palette.core()

      commands = [
        {:insert, {"blk_ROOT", "body", 0}, send_block("blk_ONE")},
        {:insert, {"blk_ROOT", "interrupts", 0},
         Block.new("core.on_event",
           id: "blk_TWO",
           config: %{"event" => "a.b", "outcome" => "abandon"}
         )}
      ]

      assert {:ok, history, changed} =
               History.commit(History.new(), palette, before, {:compound, commands})

      assert length(history.undo) == 1

      assert {:ok, undone_history, ^before} = History.undo(history, palette, changed)
      assert {:ok, _redone_history, ^changed} = History.redo(undone_history, palette, before)
    end
  end
end
