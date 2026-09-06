defmodule StatifierBlocks.Compiler.DeclaredLabelTest do
  @moduledoc """
  ADR-0011 decision 9's first surface: a `:type_mismatch` finding names the
  declaration's **label**, so an author reads a human name instead of a
  nominal one they have to go and look up.

  The pair matters more than the sentence. A **declared** pair - two names
  the datamodel document's `types` key carries - reads as the two labels; an
  **opaque** pair, two spellings the document declares nothing about, reads
  exactly as it read before there were declarations at all. Both are asserted
  against the same stage, because "the labelled case works" and "the
  unlabelled case is unchanged" are two claims and a test that made only the
  first would let the second rot.

  A pure test. The message is built in `StatifierBlocks.Compiler`, which is
  where the datamodel the check ran against is in scope, so nothing here
  needs the editor.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{Block, Compiler, Document}
  alias StatifierBlocks.CardProcessingFixtures, as: Cards

  # ADR-0003's own worked example, whose types nothing declares: the opaque
  # half of the claim.
  alias StatifierBlocks.AssignabilityFixtures

  # The settle step reads `Settled`, which `cards.credit_txn` does not cover -
  # it declares no `settled_on` - so the walk refuses at the subject path and
  # the stage renders the refusal.
  defp mismatching_document do
    Cards.document([Cards.open(), Cards.settle("blk_STL", %{"expects" => "Settled"})])
  end

  defp message(document, palette, opts) do
    assert {:error, findings} = Compiler.compile(document, palette, opts)
    assert [finding] = Enum.filter(findings, &match?({:type_mismatch, _, _, _, _, _}, &1.reason))
    finding.message
  end

  describe "a declared pair" do
    # Sabotage: `Compiler.named/2` answering `inspect(spelling)` unconditionally
    # -> the message falls back to the nominal names and both assertions go red.
    test "reads as the two declarations' labels" do
      message =
        message(mismatching_document(), Cards.palette(), datamodel: Cards.datamodel())

      assert message =~ ~s(reads "Settled")
      assert message =~ ~s(left "Credit card transaction")

      refute message =~ "cards.credit_txn",
             "the nominal name is what the label replaces, not something it sits beside"
    end

    # Sabotage: `structure_stage/3` reading its declarations from `%{}` rather
    # than from the context the check ran against - the labels disappear and
    # this test is the one that says why.
    test "falls back to the nominal names when no datamodel reaches the stage" do
      message = message(mismatching_document(), Cards.palette(), [])

      assert message =~ ~s(reads "Settled")
      assert message =~ ~s(left "cards.credit_txn")
    end
  end

  describe "an opaque pair" do
    # ADR-0003's worked example: `myapp.settled_txn` into `myapp.transaction`
    # is a refusal between two spellings the datamodel declares nothing about.
    #
    # Sabotage: `Environment.type_label/2` answering `""` for an undeclared
    # spelling -> the message loses both types and this goes red.
    test "reads exactly as it did before declarations existed" do
      palette = AssignabilityFixtures.palette(nil)

      # `blk_STL` produces `myapp.settled_txn`; an authorize placed after it
      # consumes `myapp.transaction`, which nothing widens into.
      after_settle =
        Document.new(
          Block.new("core.sequence",
            id: "blk_ROOT",
            slots: %{
              "body" => [
                Block.new("myapp.authorize", id: "blk_AUT"),
                Block.new("myapp.settle", id: "blk_STL"),
                Block.new("myapp.authorize", id: "blk_AUT2")
              ]
            }
          ),
          id: "bdoc_opaque"
        )

      message = message(after_settle, palette, datamodel: Cards.datamodel())

      assert message =~ ~s(reads "myapp.transaction")
      assert message =~ ~s(left "myapp.settled_txn")
    end
  end
end
