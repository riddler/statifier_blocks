defmodule StatifierBlocks.Compiler.UndeclaredSlotNonDeclaringTest do
  @moduledoc """
  A child an author placed in a slot a NON-declaring composite's type does
  not declare.

  `ADR-0002`'s `C3` replaces a composite that declares no `outcomes` by its
  expansion outright, so the spliced document the Structure stage walks no
  longer contains that block. `:undeclared_slot` is a Structure finding, so
  it had nothing to fire against: the child compiled green, emitted nothing,
  and the author got zero findings back. That is the same class of silently
  lost authoring work `StatifierBlocks.Compiler.ReservedExpansionSlotTest`
  pins for the DECLARING half, one step wider - there the block survives
  Resolve and only one reserved key was swallowed, here the whole block is
  gone and every undeclared key goes with it.

  Resolve reports it now, against the composite block, carrying
  `StatifierBlocks.SlotValidation`'s own `{:undeclared_slot, id, slot,
  count}` reason unchanged - the same reason the declaring half draws from
  Structure, because it is the same authoring mistake.

  The negative half matters as much: a child in a slot the type DOES declare
  is spliced into a member by `StatifierBlocks.Composite.expand!/2` and must
  draw nothing.

  The fixtures are the signup wizard's confirmation step, the same shape
  `StatifierBlocks.Composite.DeclaredOutcomesTest` uses.

  A pure test. Nothing here names LiveView, so it compiles and runs headless.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.Compiler.Finding

  alias StatifierBlocks.{
    Block,
    Compiler,
    Document,
    Palette
  }

  # The compiler's own spelling for the slot a DECLARING composite's expansion
  # members hang under, repeated as a literal for the reason
  # `StatifierBlocks.Compiler.ReservedExpansionSlotTest` gives: what an author
  # types is a literal string whatever the constant says.
  @reserved ":expansion"

  defmodule ConfirmSubtree do
    @moduledoc """
    A sequence over an await on the confirmation event, then an empty
    sequence the pass-through slot below maps into. The mapped inner slot
    has to be one the subtree writes EMPTY - it holds the author's children
    and only them - so `tail` exists, and writes its `body` slot explicitly,
    for the declaration to point at.
    """

    alias StatifierBlocks.Block

    @doc "The expansion members."
    @spec build(map()) :: [Block.t()]
    def build(params) do
      [
        Block.new("core.sequence",
          id: "body",
          slots: %{
            "body" => [
              Block.new("core.await",
                id: "wait",
                config: %{"event" => params["event"], "timeout" => "10m"}
              ),
              Block.new("core.sequence", id: "tail", slots: %{"body" => []})
            ]
          }
        )
      ]
    end
  end

  defmodule ConfirmStepPlain do
    @moduledoc "Declares no outcomes, so `C3` replaces it by its expansion."

    use StatifierBlocks.Composite,
      name: "signup.confirm_step_plain",
      params: [
        %{key: "event", type: :string, label: "Confirmed by", required?: true, default: ""}
      ],
      slots: [%{name: "then", to: {"tail", "body"}, label: "Then"}],
      palette_entry: %{label: "Confirm the contact"},
      version: 1

    alias StatifierBlocks.Compiler.UndeclaredSlotNonDeclaringTest.ConfirmSubtree

    @impl StatifierBlocks.Composite
    def subtree(params), do: ConfirmSubtree.build(params)
  end

  defmodule ConfirmStepStrict do
    @moduledoc """
    The same, declaring its pass-through slot at `:exactly_one`, so a
    document can violate that arity without carrying an undeclared key.
    """

    use StatifierBlocks.Composite,
      name: "signup.confirm_step_strict",
      params: [
        %{key: "event", type: :string, label: "Confirmed by", required?: true, default: ""}
      ],
      slots: [%{name: "then", to: {"tail", "body"}, arity: :exactly_one, label: "Then"}],
      palette_entry: %{label: "Confirm the contact, strictly"},
      version: 1

    alias StatifierBlocks.Compiler.UndeclaredSlotNonDeclaringTest.ConfirmSubtree

    @impl StatifierBlocks.Composite
    def subtree(params), do: ConfirmSubtree.build(params)
  end

  describe "a child in an undeclared slot on a composite that declares no outcomes" do
    # Sabotage: restored `declaring_node/7`'s `[] -> {:ok, nodes, expansion}`
    # branch, which is what this bead found - green compile, zero findings,
    # and `blk_W` nowhere in the emitted bytes.
    test "draws an :undeclared_slot finding at Resolve against the composite block" do
      assert {:error, findings} = Compiler.compile(document_with("mystery"), palette())

      assert [%Finding{} = finding] = Enum.filter(findings, &(&1.code == :undeclared_slot))

      assert finding.stage == :resolve
      assert finding.block_id == "blk_CS"
      assert finding.reason == {:undeclared_slot, "blk_CS", "mystery", 1}
      assert finding.message =~ "dropped"
    end

    # Sabotage: passed no `:fault` to `Finding.new/4` - red, because the
    # `:resolve` stage's own default is `:package`, which an editor renders
    # as "this cannot be fixed here". A document edit fixes this one.
    test "is the author's fault, not the palette's" do
      assert {:error, findings} = Compiler.compile(document_with("mystery"), palette())

      assert [%Finding{fault: :author}] = Enum.filter(findings, &(&1.code == :undeclared_slot))
    end

    # Sabotage: used `map_size(block.slots)` as the count instead of the
    # slot's own - red, because the two slots below hold a different number
    # of children each.
    test "reports every undeclared key, in sorted order, each with its own child count" do
      block =
        Map.put(block(), :slots, %{
          "zeta" => [dropped_child("blk_Z")],
          "alpha" => [dropped_child("blk_A"), dropped_child("blk_B")]
        })

      assert {:error, findings} = Compiler.compile(document(block), palette())

      assert [
               {:undeclared_slot, "blk_CS", "alpha", 2},
               {:undeclared_slot, "blk_CS", "zeta", 1}
             ] ==
               findings |> Enum.filter(&(&1.code == :undeclared_slot)) |> Enum.map(& &1.reason)
    end

    # The reserved name is reserved on a DECLARING composite's own block and
    # nowhere else (`StatifierBlocks.Compiler.ReservedExpansionSlotTest`'s
    # narrowing). On this one the compiler puts no such key, so the author's
    # key is an ordinary undeclared slot. Sabotage: drew
    # `:reserved_slot_name` here too - red, because that finding tells an
    # author their key collided with the compiler's, and on this block it
    # did not.
    test "the reserved expansion-slot name here is an ordinary undeclared slot" do
      assert {:error, findings} = Compiler.compile(document_with(@reserved), palette())

      assert [{:undeclared_slot, "blk_CS", @reserved, 1}] ==
               findings |> Enum.filter(&(&1.code == :undeclared_slot)) |> Enum.map(& &1.reason)

      refute Enum.any?(findings, &(&1.code == :reserved_slot_name))
    end
  end

  describe "what still compiles" do
    # The negative test. Sabotage: built the findings from `block.slots`'
    # keys directly instead of asking
    # `StatifierBlocks.SlotValidation.validate/2` - red, because this slot IS
    # declared and `StatifierBlocks.Composite.expand!/2` splices its children
    # into the member the declaration names.
    test "a child in a declared pass-through slot draws nothing and reaches the bytes" do
      assert {:ok, compiled} = Compiler.compile(document_with("then"), palette())

      assert compiled.scxml =~ "s_blk_W"
    end

    # The baseline the bead's own probe compiled green, kept green: a
    # composite an author wrote no slots on at all. Sabotage: dropped
    # `StatifierBlocks.SlotValidation`'s `Enum.reject/2` of the declared
    # names, so every slot key draws - red, and red through the Structure
    # stage's call as well as this one, which is that module's
    # one-rule-two-callers guarantee doing its work.
    test "a composite an author wrote no slots on compiles exactly as before" do
      assert {:ok, compiled} = Compiler.compile(document(block()), palette())

      assert compiled.scxml =~ "s_blk_CS_wait"
    end
  end

  describe "what this stage does not answer" do
    # Moved in from the unit tests the first review's cure removed. Resolve
    # asks about undeclared KEYS; arity on a non-declaring composite is the
    # same blind spot but a separate question, and answering it here would
    # decide it. Sabotage: dropped the reason-tag filter from
    # `undeclared_slot_findings/2`, leaving only the block-id one - red with
    # a FunctionClauseError, because the arity tuple reaches the clause that
    # only matches `{:undeclared_slot, _, _, _}`.
    test "an arity violation on a declared pass-through slot draws nothing here" do
      block =
        Block.new("signup.confirm_step_strict",
          id: "blk_CS",
          config: %{"event" => "contact.confirmed"},
          slots: %{"then" => []}
        )

      assert {:ok, _compiled} = Compiler.compile(document(block), palette())
    end
  end

  # -- fixtures ------------------------------------------------------------

  defp palette do
    Palette.new(
      Palette.core_types()
      |> Map.put("signup.confirm_step_plain", ConfirmStepPlain)
      |> Map.put("signup.confirm_step_strict", ConfirmStepStrict)
    )
  end

  defp block,
    do:
      Block.new("signup.confirm_step_plain",
        id: "blk_CS",
        config: %{"event" => "contact.confirmed"}
      )

  defp dropped_child(id), do: Block.new("core.wait", id: id, config: %{"duration" => "5m"})

  defp document_with(slot_name) do
    block()
    |> Map.put(:slots, %{slot_name => [dropped_child("blk_W")]})
    |> document()
  end

  defp document(block),
    do:
      Document.new(
        Block.new("core.sequence", id: "blk_ROOT", slots: %{"body" => [block]}),
        id: "bdoc_undeclaredslotnondeclaring"
      )
end
