defmodule StatifierBlocks.Edit.TargetsContextTest do
  @moduledoc """
  The drop check asks the data-flow question with the datamodel document the
  caller holds, rather than with an empty context.

  ADR-0002 decision 6 and ADR-0003 decision 6 make the editor's check and the
  compiler's check one implementation. Until `sb-sy0q` the editor's half
  called `Assignability.target_verdicts/4` with a hard-coded `%{}`, so
  `sd-ADR-0001` decision 8's coverage step - a record satisfying a shape by
  covering its required set - could not run there: the compiled document
  accepted a placement the editor drew as refused. The claim asserted here is
  that one drop, with and without the context, and it is asserted at the seam
  rather than through a rendered page because the rule is pure.

  The default is unchanged and is asserted too. A caller with nothing to say
  still gets ADR-0003 decision 5's permissive answer, which is what every
  existing caller of the three-argument form relies on.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{Block, Document}
  alias StatifierBlocks.CardProcessingFixtures, as: Cards
  alias StatifierBlocks.Edit.Targets

  # `blk_INNER`'s body has exactly one gap, and the environment reaching it
  # holds `cards.credit_txn` at the subject - so unlike a slot with several
  # gaps, every gap in it agrees and the slot's own verdict is the read's.
  defp document do
    Cards.document([
      Cards.open(),
      Block.new("core.sequence", id: "blk_INNER", slots: %{"body" => []})
    ])
  end

  defp verdict(ctx) do
    document()
    |> Targets.slot_verdicts(Cards.palette(), Cards.settle("blk_NEW"), ctx)
    |> Enum.into(%{})
    |> Map.fetch!({"blk_INNER", "body"})
  end

  defp verdict_without_context do
    document()
    |> Targets.slot_verdicts(Cards.palette(), Cards.settle("blk_NEW"))
    |> Enum.into(%{})
    |> Map.fetch!({"blk_INNER", "body"})
  end

  describe "the datamodel the caller holds" do
    # Sabotage: `slot_verdicts/4` passing `%{}` to `target_verdicts/4` instead
    # of `ctx` - the coverage step stops running and this goes red, which is
    # exactly the defect the bead names.
    test "lets the coverage step run, so a record covering a shape is droppable" do
      assert verdict(Cards.ctx()) == :ok

      assert {"blk_INNER", "body"} in Targets.droppable_slots_for(
               document(),
               Cards.palette(),
               Cards.settle("blk_NEW"),
               Cards.ctx()
             )
    end

    # The compiler's answer for the same placement, so the two are asserted
    # against each other rather than each against its own expectation.
    # Sabotage: as above - the editor starts refusing what the check admits
    # and these two lines disagree.
    test "makes the editor's answer the compiler's answer" do
      placed =
        Cards.document([
          Cards.open(),
          Block.new("core.sequence",
            id: "blk_INNER",
            slots: %{"body" => [Cards.settle("blk_NEW")]}
          )
        ])

      assert StatifierBlocks.Assignability.validate(Cards.palette(), placed, Cards.ctx()) == :ok
      assert verdict(Cards.ctx()) == :ok
    end
  end

  describe "no context" do
    # Sabotage: defaulting `ctx` to `Cards.ctx()` rather than `%{}` - the
    # permissive default stops being the default and this goes red.
    test "is the permissive default, and refuses the read it cannot check" do
      assert verdict_without_context() == {:refused, {:fixable_by, "blk_OPEN"}}
      assert verdict_without_context() == verdict(%{})
    end
  end

  # A document is a document however it was built; this only guards the helper
  # above from silently building something else.
  test "the fixture document holds the inner sequence" do
    assert %Document{} = document()
    assert Enum.any?(Document.blocks(document()), &(&1.id == "blk_INNER"))
  end
end
