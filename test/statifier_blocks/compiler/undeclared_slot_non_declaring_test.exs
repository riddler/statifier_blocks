defmodule StatifierBlocks.Compiler.UndeclaredSlotNonDeclaringTest do
  @moduledoc """
  What a NON-declaring composite's own slots are never asked.

  `ADR-0002`'s `C3` replaces a composite that declares no `outcomes` by its
  expansion outright, so the spliced document the Structure stage walks no
  longer contains that block. Both of that stage's slot findings then have
  nothing to fire against, and the document compiles green with zero findings
  for the author to read:

    * `:undeclared_slot` - a child placed in a slot the type does not
      declare, which emitted nothing; and
    * `:slot_arity_violated` - a slot the type DOES declare whose child count
      violates the arity it declared it at. Those children do reach the bytes
      through the member the declaration names; what was lost is the
      declaration's own refusal.

  That is the same class of silently lost authoring work
  `StatifierBlocks.Compiler.ReservedExpansionSlotTest` pins for the DECLARING
  half, one step wider - there the block survives Resolve and only one
  reserved key was swallowed, here the whole block is gone.

  Resolve reports both now, against the composite block, carrying
  `StatifierBlocks.SlotValidation`'s own reason tuples unchanged - the same
  reasons the declaring half draws from Structure, because they are the same
  authoring mistakes. Since `C9b` the same path carries a non-declaring
  INSTANCE of a per-instance declarer, and that is pinned here too.

  The negative halves matter as much: a child in a declared slot whose count
  satisfies its arity is spliced into a member by
  `StatifierBlocks.Composite.expand!/2` and must draw nothing.

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

  defmodule ConfirmStepPerInstance do
    @moduledoc """
    `C9`'s shape over the same subtree: no `:outcomes` option, and a
    `declared_outcomes/1` that reads the instance's own `buttons` param. The
    same type is a declaring instance for one config and a NON-declaring one
    for another (`C9b`), and the non-declaring one arrives on exactly the
    path this file is about.
    """

    use StatifierBlocks.Composite,
      name: "signup.confirm_step_per_instance",
      params: [
        %{key: "event", type: :string, label: "Confirmed by", required?: true, default: ""},
        %{key: "buttons", type: :string, label: "Buttons", required?: true, default: ""}
      ],
      slots: [%{name: "then", to: {"tail", "body"}, arity: :exactly_one, label: "Then"}],
      palette_entry: %{label: "Confirm the contact, per instance"},
      version: 1

    alias StatifierBlocks.Compiler.UndeclaredSlotNonDeclaringTest.ConfirmSubtree

    @impl StatifierBlocks.Composite
    def subtree(params), do: ConfirmSubtree.build(params)

    @impl StatifierBlocks.Composite
    def declared_outcomes(config), do: String.split(config["buttons"] || "", ",", trim: true)
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

  describe "an arity violation on a declared pass-through slot of a non-declaring composite" do
    # The blind spot this file's undeclared-slot half found, one slot kind
    # wider: `C3` takes the block out of the spliced document, so the
    # Structure stage never counts the children of a slot the type DOES
    # declare either, and an author who emptied an `:exactly_one` slot
    # compiled green. Sabotage: restored the reason-tag filter
    # `Enum.filter(&match?({:undeclared_slot, ^id, _slot, _count}, &1))` on
    # `non_declaring_slot_findings/2` - red, because the arity tuple is then
    # dropped again and the document compiles `{:ok, _}`.
    test "draws a :slot_arity_violated finding at Resolve against the composite block" do
      assert {:error, findings} =
               Compiler.compile(document(strict_block(%{"then" => []})), palette())

      assert [%Finding{} = finding] =
               Enum.filter(findings, &(&1.code == :slot_arity_violated))

      assert finding.stage == :resolve
      assert finding.block_id == "blk_CS"
      assert finding.reason == {:slot_arity_violated, "blk_CS", "then", :exactly_one, 0}
    end

    # The same argument the undeclared half makes: `:package` renders as
    # "this cannot be fixed here", and a document edit fixes this one.
    # Sabotage: passed no `:fault` to `Finding.new/4` in
    # `non_declaring_slot_finding/1`'s arity clause - red, because the
    # `:resolve` stage's own default is `:package`.
    test "is the author's fault, not the palette's" do
      assert {:error, findings} =
               Compiler.compile(document(strict_block(%{"then" => []})), palette())

      assert [%Finding{fault: :author}] =
               Enum.filter(findings, &(&1.code == :slot_arity_violated))
    end

    # The two stages report one authoring mistake, so they say the same
    # sentence: `non_declaring_slot_finding/1`'s arity clause is
    # `slot_finding/1`'s word for word. Sabotage: dropped `arity_phrase(arity)`
    # from the Resolve clause - red, because the message then stops before
    # naming what the type declared.
    test "reads as the Structure stage's own sentence for the same reason tuple" do
      assert {:error, findings} =
               Compiler.compile(document(strict_block(%{"then" => []})), palette())

      assert [%Finding{message: message}] =
               Enum.filter(findings, &(&1.code == :slot_arity_violated))

      assert message ==
               ~s(the "then" slot holds 0 blocks, and this block type declares it as holding exactly one)
    end

    # `C9b`: "non-declaring" is a question about the BLOCK. An instance of a
    # per-instance declarer whose `declared_outcomes/1` answers `[]` for its
    # own config takes `C3`'s path, so it is blind in exactly the same way
    # and draws exactly the same finding. Sabotage: made
    # `ConfirmStepPerInstance.declared_outcomes/1` answer `["confirmed"]`
    # whatever the config - red, because the block is then a DECLARING
    # instance, leaves this path entirely, and the filter below answers `[]`.
    test "draws there for a non-declaring INSTANCE of a per-instance declarer too" do
      block =
        Block.new("signup.confirm_step_per_instance",
          id: "blk_CS",
          config: %{"event" => "contact.confirmed", "buttons" => ""},
          slots: %{"then" => []}
        )

      assert {:error, findings} = Compiler.compile(document(block), palette())

      assert [%Finding{stage: :resolve, block_id: "blk_CS"} = finding] =
               Enum.filter(findings, &(&1.code == :slot_arity_violated))

      assert finding.reason == {:slot_arity_violated, "blk_CS", "then", :exactly_one, 0}
    end

    # The negative half: a slot whose count SATISFIES the declared arity
    # draws nothing, and its child still reaches the bytes through the
    # member the declaration names. Sabotage: made
    # `StatifierBlocks.SlotValidation.arity_satisfied?/2`'s `:exactly_one`
    # clause read `count == 0` - red here, because the one child this
    # document places then reads as a violation and the compile errors.
    test "a declared pass-through slot whose count satisfies its arity draws nothing" do
      block = strict_block(%{"then" => [dropped_child("blk_W")]})

      assert {:ok, compiled} = Compiler.compile(document(block), palette())

      assert compiled.scxml =~ "s_blk_W"
    end
  end

  describe "the finding messages count in English" do
    # `holds 1 blocks` is what this message read before. Sabotage: made the
    # compiler's `block_count/1` a single clause `"#{count} blocks"` - red
    # here, on the singular half; the plural half is what keeps the fix from
    # being a swap of one wrong number-word for another.
    test "the undeclared-slot message says one block for one and two blocks for two" do
      assert {:error, [%Finding{message: singular}]} =
               Compiler.compile(document_with("mystery"), palette())

      assert singular =~ ~s(the "mystery" slot holds 1 block but this block type)
      refute singular =~ "1 blocks"

      two =
        block()
        |> Map.put(:slots, %{"mystery" => [dropped_child("blk_W"), dropped_child("blk_X")]})
        |> document()

      assert {:error, [%Finding{message: plural}]} = Compiler.compile(two, palette())

      assert plural =~ ~s(the "mystery" slot holds 2 blocks but this block type)
    end

    # The whole sentence, at one child and at two. It used to say "they are
    # dropped" and "move them into a slot it declares" - a plural pronoun
    # whatever the count, and an `it` that could be the slot or the block
    # type. It now names the slot's contents and the block type outright,
    # so only the noun phrase `block_count/1` writes changes with the count.
    #
    # Sabotage (run): put the old "so they are dropped ... move them into a
    # slot it declares" wording back - red on the singular assertion, the
    # first it reaches. Made the compiler's `block_count/1` a single clause
    # `"#{count} blocks"` - red on the singular assertion. Made its second
    # clause `"#{count} block"` - red on the plural assertion.
    test "the undeclared-slot message reads whole at one block and at two" do
      assert {:error, [%Finding{message: singular}]} =
               Compiler.compile(document_with("mystery"), palette())

      assert singular ==
               ~s(the "mystery" slot holds 1 block but this block type declares no such ) <>
                 "slot, so the slot's contents are dropped where this composite is replaced " <>
                 "by its expansion; move the contents into a slot this block type declares, " <>
                 "or rename the slot"

      two =
        block()
        |> Map.put(:slots, %{"mystery" => [dropped_child("blk_W"), dropped_child("blk_X")]})
        |> document()

      assert {:error, [%Finding{message: plural}]} = Compiler.compile(two, palette())

      assert plural ==
               ~s(the "mystery" slot holds 2 blocks but this block type declares no such ) <>
                 "slot, so the slot's contents are dropped where this composite is replaced " <>
                 "by its expansion; move the contents into a slot this block type declares, " <>
                 "or rename the slot"
    end

    # The arity message counts through the same helper, and its own two
    # reachable counts are zero and two-or-more: ADR-0002 decision 6's four
    # arities are `:any`, `:at_least_one`, `:exactly_one` and `:zero_or_one`,
    # and a count of one satisfies every one of them, so no arity finding can
    # carry a count of 1. That is why the helper is shared rather than
    # inlined at each site - the singular branch is reachable only from the
    # undeclared-slot message above, and an inlined fix would have left this
    # site free to drift. Sabotage: made the compiler's `block_count/1` a
    # single clause `"#{count} block"` - red here.
    test "the arity message counts in blocks at the counts an arity can carry" do
      assert {:error, [%Finding{message: none}]} =
               Compiler.compile(document(strict_block(%{"then" => []})), palette())

      assert none =~ ~s(the "then" slot holds 0 blocks, and this block type)

      two = strict_block(%{"then" => [dropped_child("blk_W"), dropped_child("blk_X")]})

      assert {:error, [%Finding{message: plural}]} = Compiler.compile(document(two), palette())

      assert plural =~ ~s(the "then" slot holds 2 blocks, and this block type)
    end
  end

  # -- fixtures ------------------------------------------------------------

  defp palette do
    Palette.new(
      Palette.core_types()
      |> Map.put("signup.confirm_step_plain", ConfirmStepPlain)
      |> Map.put("signup.confirm_step_strict", ConfirmStepStrict)
      |> Map.put("signup.confirm_step_per_instance", ConfirmStepPerInstance)
    )
  end

  defp strict_block(slots),
    do:
      Block.new("signup.confirm_step_strict",
        id: "blk_CS",
        config: %{"event" => "contact.confirmed"},
        slots: slots
      )

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
