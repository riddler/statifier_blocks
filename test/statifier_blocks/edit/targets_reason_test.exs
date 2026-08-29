defmodule StatifierBlocks.Edit.TargetsReasonTest do
  use ExUnit.Case, async: true

  @moduledoc """
  `Edit.Targets.slot_verdicts/3`: the accepting slots and the refusing ones
  from one enumeration, and the rule that decides what a refused slot has
  to say for itself.

  The reduction `Edit.Targets` documents is existential over a slot's gaps,
  so a slot-level reason exists only where the gaps agree. These tests pin
  both halves of that: the agreement that produces a reason, and the
  three ways a refusal legitimately has none.
  """

  alias StatifierBlocks.{AssignabilityFixtures, Block, Document}
  alias StatifierBlocks.Edit.Targets

  defp palette(relation \\ AssignabilityFixtures.Widens),
    do: AssignabilityFixtures.palette(relation)

  # authorize, then a group whose `body` and `interrupts` are both empty -
  # so the group's slots each have exactly one gap, whose inbound type is
  # `myapp.credit_card_txn` (the group's own inbound, ADR-0003 decision 4).
  defp document do
    authorize = Block.new("myapp.authorize", id: "blk_AUTH")

    group =
      Block.new("core.resumable_group", id: "blk_GRP", slots: %{"body" => [], "interrupts" => []})

    root = Block.new("core.sequence", id: "blk_ROOT", slots: %{"body" => [authorize, group]})
    Document.new(root, id: "bdoc_targets_reason")
  end

  defp verdict(verdicts, slot_ref) do
    case Enum.find(verdicts, fn {ref, _verdict} -> ref == slot_ref end) do
      {_ref, verdict} -> verdict
      nil -> :absent
    end
  end

  describe "the accepting half is unchanged" do
    # Sabotage: `droppable_slots_for/3` rewritten to keep the
    # `{:refused, _}` rows instead of the `:ok` ones - this goes red,
    # because the accepting set and this function's `:ok` rows stop being
    # the same list.
    test "droppable_slots_for/3 is exactly this function's :ok rows, in order" do
      document = document()
      palette = palette()
      candidate = Block.new("myapp.post_to_ledger", id: "blk_LDG")

      expected =
        for {slot_ref, :ok} <- Targets.slot_verdicts(document, palette, candidate), do: slot_ref

      assert Targets.droppable_slots_for(document, palette, candidate) == expected
      assert expected != []
    end

    # Sabotage: `slot_verdicts/3`'s `Enum.any?(verdicts, &(&1 == :ok))`
    # clause changed to `Enum.all?/2` - this goes red, because the
    # existential reduction `Edit.Targets` argues for becomes a universal
    # one and a slot with one good gap among bad ones goes dark.
    test "a slot with some accepting gaps and some refusing ones still accepts" do
      # `myapp.settle` into the root's body: gap 0 refuses (settle's output
      # reaching an authorize that wants a transaction) and gap 1 accepts
      # (identity, straight after the authorize). The slot is droppable.
      verdicts =
        Targets.slot_verdicts(document(), palette(), Block.new("myapp.settle", id: "blk_S2"))

      assert verdict(verdicts, {"blk_ROOT", "body"}) == :ok
    end

    # Sabotage: `group_by_slot/1` dropping its `Enum.reverse/1` on the order
    # accumulator - this goes red, because the slots come back in reverse
    # first-appearance order and the enumeration stops being deterministic
    # in the way `valid_targets/4` promises.
    test "every declared slot appears, accepted or refused, not only the accepted ones" do
      verdicts =
        Targets.slot_verdicts(document(), palette(), Block.new("myapp.authorize", id: "blk_A2"))

      refs = Enum.map(verdicts, &elem(&1, 0))

      assert refs == [{"blk_ROOT", "body"}, {"blk_GRP", "body"}, {"blk_GRP", "interrupts"}]
    end
  end

  describe "a refused slot's reason" do
    # Sabotage: `gap_reason/2`'s `{:error, [first | _rest]}` clause
    # returning `nil` - this goes red, because the slot darkens with
    # nothing to say about why.
    test "is the vocabulary's arm when every gap refused for the same reason" do
      # One gap in `blk_GRP`'s empty `body`, and the floor palette refuses
      # it: `myapp.credit_card_txn` reaching an authorize that consumes
      # `myapp.transaction`, with nothing to widen it.
      verdicts =
        Targets.slot_verdicts(
          document(),
          palette(nil),
          Block.new("myapp.authorize", id: "blk_A2")
        )

      assert verdict(verdicts, {"blk_GRP", "body"}) == {:refused, :not_assignable}
    end

    # Sabotage: `gap_reason/2` taking `Enum.find(findings, &match?(
    # {:type_mismatch, _, _, _, _}, &1))` instead of the first finding -
    # this goes red with `:not_assignable`, which is the data-flow
    # vocabulary answering over the structural gate that actually refused.
    test "is absent when the refusal was structural" do
      # An `:interrupt_handler` slot refusing a `:step`: ADR-0003 decision
      # 3's gate, whose `:kind_not_admitted` finding already names both kind
      # sets.
      verdicts =
        Targets.slot_verdicts(document(), palette(), Block.new("myapp.authorize", id: "blk_A2"))

      assert verdict(verdicts, {"blk_GRP", "interrupts"}) == {:refused, nil}
    end

    # Sabotage: `slot_verdicts/3`'s `full?/4` clause moved below the
    # `Enum.any?` clause - this goes red, because a full slot with an
    # accepting gap reports `:ok` and rule 3 stops being enforced.
    test "is absent for rule 3 and rule 4, which are not assignability questions" do
      spotlit = Block.new("myapp.settle", id: "blk_STL")

      group =
        Block.new("core.resumable_group",
          id: "blk_GRP",
          slots: %{"body" => [spotlit], "interrupts" => []}
        )

      root = Block.new("core.sequence", id: "blk_ROOT", slots: %{"body" => [group]})
      document = Document.new(root, id: "bdoc_room")

      # `core.resumable_group`'s `body` is `:zero_or_more`, so nothing here
      # is full; the subtree rule is the one that fires when the dragged
      # block is the group itself.
      verdicts = Targets.slot_verdicts(document, palette(), group)

      assert verdict(verdicts, {"blk_GRP", "body"}) == {:refused, nil}
      assert verdict(verdicts, {"blk_GRP", "interrupts"}) == {:refused, nil}
    end

    # Sabotage: `agreed_reason/2` returning `List.first/1` of the gap
    # reasons instead of requiring them to agree - this goes red, because
    # the slot starts showing one gap's reason as though it were the
    # slot's.
    test "is absent when different gaps refused for different reasons" do
      # Two gaps in the root's `body`, refusing with different producing
      # refs: gap 0 fails downstream against `blk_STL` (naming the
      # candidate), gap 1 fails upstream against `blk_STL`'s output (naming
      # `blk_STL`). No single sentence covers both.
      settle = Block.new("myapp.settle", id: "blk_STL")
      root = Block.new("core.sequence", id: "blk_ROOT", slots: %{"body" => [settle]})
      document = Document.new(root, id: "bdoc_disagree")

      verdicts =
        Targets.slot_verdicts(document, palette(nil), Block.new("myapp.settle", id: "blk_S2"))

      assert verdict(verdicts, {"blk_ROOT", "body"}) == {:refused, nil}
    end
  end
end
