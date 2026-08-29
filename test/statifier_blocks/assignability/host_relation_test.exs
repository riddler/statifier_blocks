defmodule StatifierBlocks.Assignability.HostRelationTest do
  use ExUnit.Case, async: true

  @moduledoc """
  ADR-0003 decision 7's acceptance property, asserted rather than argued:
  *"there is no arrangement of code in which the editor lights up a slot
  the compiler would reject."*

  The way to test that is not to check the two agree on a fixed document -
  they would agree by accident if both were wrong. It is to change the one
  thing decision 6 says is the only channel the host's relation can arrive
  through - `palette.assignability` - and assert that **the same seam**
  moves in **both** consumers, in the same direction, at the same time.

  So each test here runs one document through both paths under two
  palettes that differ in nothing but the relation module:

    * the authority, `Assignability.validate/3` (decision 7's whole-document
      walk, what the compiler runs before emitting);
    * the editor's pre-hover drop set, `Edit.Targets.droppable_slots_for/3`,
      which reaches the same relation through
      `Assignability.valid_targets/4` -> `check/5` -> `assignable?/3`.

  The seam is `myapp.credit_card_txn -> myapp.card_txn`: not identity, so it
  reaches decision 6 step 4 and nothing else, which is the only step a host
  can influence.

  A third describe block follows that same refusal out through
  `Compiler.compile/2` and `Finding.from_compiler/2`, so the path from the
  host's module to a finding the editor's panel can route is asserted whole
  rather than in two halves that meet by assumption.
  """

  alias StatifierBlocks.{Assignability, AssignabilityFixtures, Block, Compiler, Document, Finding}
  alias StatifierBlocks.Edit.Targets

  # A group whose empty `body` sits after the authorize, so the group's own
  # inbound type - and therefore the inbound type at `{blk_GRP, "body", 0}`
  # - is `myapp.credit_card_txn` (ADR-0003 decision 4's slot inbound).
  defp document_with_empty_group do
    authorize = Block.new("myapp.authorize", id: "blk_AUTH")

    group =
      Block.new("core.resumable_group",
        id: "blk_GRP",
        config: %{"history" => "shallow"},
        slots: %{"body" => [], "interrupts" => []}
      )

    root = Block.new("core.sequence", id: "blk_ROOT", slots: %{"body" => [authorize, group]})
    Document.new(root, id: "bdoc_host_relation")
  end

  # The same document with the ledger step already placed in that slot -
  # so `validate/3` is looking at exactly the seam the drag was asking
  # about.
  defp document_with_ledger_placed do
    authorize = Block.new("myapp.authorize", id: "blk_AUTH")
    ledger = Block.new("myapp.post_to_ledger", id: "blk_LDG")

    group =
      Block.new("core.resumable_group",
        id: "blk_GRP",
        config: %{"history" => "shallow"},
        slots: %{"body" => [ledger], "interrupts" => []}
      )

    root = Block.new("core.sequence", id: "blk_ROOT", slots: %{"body" => [authorize, group]})
    Document.new(root, id: "bdoc_host_relation")
  end

  defp ledger_candidate, do: Block.new("myapp.post_to_ledger", id: "blk_LDG")

  describe "one relation, reached through one palette, moving both consumers" do
    # Sabotage: `assignable?/3`'s step-4 clause returning `false` instead of
    # calling `module.assignable?/2` - every "with the host relation"
    # assertion in this file goes red together, which is the point: there is
    # one place a host answer can enter, and losing it loses the drop set
    # and the validation verdict in the same breath.
    test "the host's widening admits the drop and clears the finding" do
      palette = AssignabilityFixtures.palette()

      assert {"blk_GRP", "body"} in Targets.droppable_slots_for(
               document_with_empty_group(),
               palette,
               ledger_candidate()
             )

      assert Assignability.validate(palette, document_with_ledger_placed(), %{}) == :ok
    end

    # Sabotage: `assignable?/3`'s `%Palette{assignability: nil}` clause
    # returning `true` - both assertions go red, because the floor a host
    # cannot lower stops being a floor and the two consumers agree on the
    # wrong answer instead of the right one.
    test "taking the relation off the palette refuses the drop and raises the finding" do
      palette = AssignabilityFixtures.palette(nil)

      refute {"blk_GRP", "body"} in Targets.droppable_slots_for(
               document_with_empty_group(),
               palette,
               ledger_candidate()
             )

      assert {:error, [finding]} =
               Assignability.validate(palette, document_with_ledger_placed(), %{})

      assert finding ==
               {:type_mismatch, "blk_LDG", :slot_entry, "myapp.credit_card_txn", "myapp.card_txn"}
    end

    # Sabotage: `Edit.Targets.slot_verdicts/3` calling
    # `Assignability.valid_targets/4` on a freshly built palette with no
    # `:assignability` instead of the one it was passed - this goes red,
    # because the drop set stops moving with the relation while validation
    # keeps moving with it, which is exactly the divergence decision 7
    # forbids.
    test "a relation that answers false to everything is the floor, not below it" do
      # `Deny` widens nothing, so it must give the identical answer to no
      # relation at all - a host callback can never narrow the identity
      # relation (decision 6).
      deny = AssignabilityFixtures.palette(AssignabilityFixtures.Deny)
      none = AssignabilityFixtures.palette(nil)
      document = document_with_empty_group()

      assert Targets.droppable_slots_for(document, deny, ledger_candidate()) ==
               Targets.droppable_slots_for(document, none, ledger_candidate())

      assert Assignability.validate(deny, document_with_ledger_placed(), %{}) ==
               Assignability.validate(none, document_with_ledger_placed(), %{})
    end

    # Sabotage: `Assignability.assignable?/3`'s `def assignable?(_palette,
    # same, same)` identity clause deleted - this goes red with a second
    # finding, because `blk_AUTH`'s identity seam falls through to a host
    # relation that does not widen it, which is an absent relation
    # narrowing the floor it is supposed to sit above.
    test "identity never reaches the host, so removing the relation moves only the widened seam" do
      widening = AssignabilityFixtures.palette()
      floor = AssignabilityFixtures.palette(nil)
      document = document_with_ledger_placed()

      # The entry type is supplied here on purpose: it makes `blk_AUTH`'s
      # own seam an *identity* match (`myapp.transaction` reaching an
      # authorize that consumes `myapp.transaction`), which decision 6 step
      # 2 settles before step 4 is reachable. So under the floor palette
      # that seam must still pass, and the single finding must still be the
      # widened one - a relation's absence can only ever un-widen, never
      # narrow.
      ctx = AssignabilityFixtures.worked_example_context()

      assert Assignability.validate(widening, document, ctx) == :ok

      assert {:error, [{:type_mismatch, "blk_LDG", _ref, _produced, _consumed}]} =
               Assignability.validate(floor, document, ctx)
    end
  end

  describe "the refusal the drop set shows carries the same reason validation would" do
    # Sabotage: `Edit.Targets.gap_reason/2` answering `nil` for a refusing
    # gap instead of explaining its first finding - this goes red, so the
    # slot darkens with nothing to say about why while the finding beside
    # it still knows.
    test "the slot's reason and the finding's reason are one function's answer" do
      palette = AssignabilityFixtures.palette(nil)

      verdicts = Targets.slot_verdicts(document_with_empty_group(), palette, ledger_candidate())

      assert {{"blk_GRP", "body"}, {:refused, :not_assignable}} =
               Enum.find(verdicts, &match?({{"blk_GRP", "body"}, _verdict}, &1))

      assert {:error, [finding]} =
               Assignability.validate(palette, document_with_ledger_placed(), %{})

      assert Assignability.finding_reason(palette, finding) == :not_assignable
    end
  end

  describe "the compiler's half of the wire carries the reason too" do
    # Sabotage: `Compiler.structure_finding/1`'s `:type_mismatch` clause
    # building its `Finding.new/4` with a literal atom instead of the
    # matched `reason` tuple - this goes red, because the raw finding stops
    # riding through the compile pipeline and there is nothing left to
    # derive an explanation from on the far side.
    test "a refusal survives compile as a :structure finding whose reason is derivable" do
      palette = AssignabilityFixtures.palette(nil)

      assert {:error, findings} = Compiler.compile(document_with_ledger_placed(), palette)

      assert [%Compiler.Finding{stage: :structure, block_id: "blk_LDG"} = finding] = findings

      # ADR-0003's 2026-08-29 amendment, 8c: the reason is not a field on
      # the finding, it is a projection of what the finding already carries.
      # So the compile pipeline needs no new plumbing to convey it.
      assert Assignability.finding_reason(palette, finding.reason) == :not_assignable
    end

    # Sabotage: `Finding.from_compiler/2`'s stage table mapping
    # `:structure` to `:config` instead of `:assignability` - this goes red,
    # because the presentation finding stops claiming the rule it came from.
    test "and adapts into a presentation finding the editor's panel can route" do
      palette = AssignabilityFixtures.palette(nil)

      assert {:error, findings} = Compiler.compile(document_with_ledger_placed(), palette)

      assert {:ok, presented} = Finding.from_compiler(hd(findings))

      assert %Finding{source: :assignability, anchor: {:block, "blk_LDG"}, severity: :error} =
               presented
    end
  end
end
