defmodule StatifierBlocks.Assignability.RefusalReasonTest do
  use ExUnit.Case, async: true

  @moduledoc """
  The 2026-08-29 amendment to ADR-0003 decision 8: the reason vocabulary,
  and the property that makes it safe - a reason explains a verdict and
  never changes one.

  The host relation itself is exercised end to end in
  `StatifierBlocks.Assignability.HostRelationTest`, which asserts decision
  7's one-function rule directly; this file is the vocabulary.
  """

  alias StatifierBlocks.{Assignability, AssignabilityFixtures, Block, Document}

  defp widening_palette, do: AssignabilityFixtures.palette()
  defp floor_palette, do: AssignabilityFixtures.palette(nil)

  # `myapp.settle` first and `myapp.authorize` after it: a seam that is
  # typed on both sides, that no widening in the fixture relation rescues,
  # and whose producing side is a named block - which is the shape
  # `{:fixable_by, _}` exists for.
  defp reversed_document do
    settle = Block.new("myapp.settle", id: "blk_STL")
    authorize = Block.new("myapp.authorize", id: "blk_AUTH")
    root = Block.new("core.sequence", id: "blk_ROOT", slots: %{"body" => [settle, authorize]})
    Document.new(root, id: "bdoc_reversed")
  end

  describe "seam_reason/4, the five arms" do
    # Sabotage: reordered the `cond` in `seam_reason/4` so the
    # `assignable?/3` clause runs before the `:unknown` clauses - the three
    # untyped assertions go red together, because a passing seam answers
    # `nil` instead of naming why it was never checked.
    test "the three untyped arms name a seam decision 5 admitted without checking" do
      palette = widening_palette()

      assert Assignability.seam_reason(palette, :unknown, :unknown, :slot_entry) == :both_untyped

      assert Assignability.seam_reason(palette, :unknown, "myapp.card_txn", :slot_entry) ==
               :source_untyped

      assert Assignability.seam_reason(palette, "myapp.card_txn", :unknown, :slot_entry) ==
               :target_untyped
    end

    # Sabotage: `seam_reason/4`'s `assignable?/3` clause returning
    # `:not_assignable` instead of `nil` - both assertions go red, which is
    # the vocabulary claiming a checked, passing seam has something wrong
    # with it.
    test "a seam that really passes has nothing to explain, by identity or by the host" do
      palette = widening_palette()

      assert Assignability.seam_reason(palette, "myapp.card_txn", "myapp.card_txn", "blk_A") ==
               nil

      assert Assignability.seam_reason(
               palette,
               "myapp.credit_card_txn",
               "myapp.card_txn",
               "blk_A"
             ) == nil
    end

    # Sabotage: `seam_reason/4`'s `producing_ref == :slot_entry` clause
    # dropped, so every refusal becomes `{:fixable_by, _}` - the
    # `:not_assignable` assertion goes red with `{:fixable_by, :slot_entry}`,
    # which is the arm naming a thing that is not a block.
    test "the two refusing arms split on decision 8's own producing ref" do
      palette = widening_palette()

      assert Assignability.seam_reason(
               palette,
               "myapp.settled_txn",
               "myapp.transaction",
               :slot_entry
             ) == :not_assignable

      assert Assignability.seam_reason(
               palette,
               "myapp.settled_txn",
               "myapp.transaction",
               "blk_STL"
             ) == {:fixable_by, "blk_STL"}
    end

    # Sabotage: `assignable?/3`'s `%Palette{assignability: nil}` clause
    # returning `true` - the second assertion goes red, because the floor
    # palette stops refusing and the reason disappears with the refusal.
    test "the host relation is what decides which of the two a seam gets, not the vocabulary" do
      assert Assignability.seam_reason(
               widening_palette(),
               "myapp.credit_card_txn",
               "myapp.card_txn",
               "blk_AUTH"
             ) == nil

      assert Assignability.seam_reason(
               floor_palette(),
               "myapp.credit_card_txn",
               "myapp.card_txn",
               "blk_AUTH"
             ) == {:fixable_by, "blk_AUTH"}
    end
  end

  describe "finding_reason/2" do
    # Sabotage: `finding_reason/2`'s `:type_mismatch` clause passing the
    # finding's *second* element (the consuming block) as the producing ref
    # - the assertion goes red naming `blk_AUTH`, the block that consumes,
    # instead of `blk_STL`, the block that declared the type.
    test "a type mismatch explains itself from what its own tuple already carries" do
      palette = widening_palette()
      document = reversed_document()

      assert {:error, [finding]} = Assignability.validate(palette, document, %{})

      assert finding ==
               {:type_mismatch, "blk_AUTH", "blk_STL", "myapp.settled_txn", "myapp.transaction"}

      assert Assignability.finding_reason(palette, finding) == {:fixable_by, "blk_STL"}
    end

    # Sabotage: `finding_reason/2`'s `:kind_not_admitted` clause returning
    # `:not_assignable` - the assertion goes red, which is the data-flow
    # vocabulary answering for the structural gate it does not speak for.
    test "a structural refusal is its own reason and gets none from this vocabulary" do
      palette = widening_palette()

      finding =
        {:kind_not_admitted, "blk_LDG", "blk_GRP", "interrupts", [:step], [:interrupt_handler]}

      assert Assignability.finding_reason(palette, finding) == nil
    end
  end

  describe "seam_reasons/3, the producer of the untyped arms" do
    # Sabotage: `seam_reasons/3`'s `reason != nil` filter removed - the
    # `length/1` assertion goes red, because every fully-checked seam in the
    # document starts reporting itself with a `nil` reason.
    test "names the seams a partially typed palette let through unchecked" do
      palette = widening_palette()
      document = AssignabilityFixtures.worked_example_document()
      ctx = AssignabilityFixtures.worked_example_context()

      reasons = Assignability.seam_reasons(palette, document, ctx)

      # blk_AUTH consumes "myapp.transaction" from the entry type - identity,
      # nothing to explain. blk_STL consumes what blk_AUTH produces -
      # identity again. blk_GRP declares no `consumes`, so its seam passed
      # only because the target side is untyped, and that is the one seam
      # with something to say.
      assert reasons == [{"blk_GRP", "blk_STL", :target_untyped}]
    end

    # Sabotage: `validate/3` rewritten to append `seam_reasons/3`'s rows to
    # its findings - the `:ok` assertion goes red, which is precisely the
    # vocabulary refusing more than it explains.
    test "and changes no verdict: the same document still validates clean" do
      palette = widening_palette()
      document = AssignabilityFixtures.worked_example_document()
      ctx = AssignabilityFixtures.worked_example_context()

      assert Assignability.seam_reasons(palette, document, ctx) != []
      assert Assignability.validate(palette, document, ctx) == :ok
    end

    # Sabotage: `seam_reasons/3` walking `Document.blocks/1` without the
    # `{:ok, [_ | _]}` path guard - the assertion goes red with an extra row
    # for the root, which occupies no slot and therefore has no seam.
    test "a refusing seam appears here too, with the same reason its finding gives" do
      palette = widening_palette()
      document = reversed_document()

      assert Assignability.seam_reasons(palette, document, %{}) == [
               {"blk_STL", :slot_entry, :source_untyped},
               {"blk_AUTH", "blk_STL", {:fixable_by, "blk_STL"}}
             ]
    end
  end
end
