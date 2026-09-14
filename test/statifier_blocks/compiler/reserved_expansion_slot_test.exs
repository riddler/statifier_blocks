defmodule StatifierBlocks.Compiler.ReservedExpansionSlotTest do
  @moduledoc """
  The slot key a declaring composite's expansion members are kept under, as
  written by an AUTHOR on that composite's own block.

  `ADR-0002`'s `C6` gives a composite that declares outcomes a resolved node
  of its own and hangs the expansion members off it under a reserved slot
  name. `:undeclared_slot` is exempt on exactly that key on exactly those
  blocks, because there the key is the compiler's own bytes - and the
  exemption is keyed by BLOCK ID, so it also covered a slot of that name an
  author typed on the same block. The resolved node is built with the
  compiler's list, so those children were dropped with the compile green and
  nothing for the author to read.

  Resolve reports it now, and the narrowing is exactly that key on exactly a
  declaring node. Both sides are pinned below: the author's key on a
  declaring block draws the finding, while the compiler's own key on the same
  block still draws none and the same name on any other block keeps its
  ordinary `:undeclared_slot`.

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

  # The compiler's own spelling for the slot, repeated here rather than read
  # from the module attribute it is private to: a test that read the constant
  # would still pass if the constant changed, and what an author types is a
  # literal string either way.
  @reserved ":expansion"

  defmodule ConfirmSubtree do
    @moduledoc """
    The expansion the reserved slot holds, kept in its own module so the
    declaration below differs from the one
    `StatifierBlocks.Composite.DeclaredOutcomesTest` uses in nothing but its
    name.
    """

    alias StatifierBlocks.Block

    @doc "A sequence over an await on the confirmation event."
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
              )
            ]
          }
        )
      ]
    end
  end

  defmodule ConfirmStepDeclaring do
    @moduledoc "Declares outcomes, so it survives Resolve as its own node."

    use StatifierBlocks.Composite,
      name: "signup.confirm_step_declaring",
      params: [
        %{key: "event", type: :string, label: "Confirmed by", required?: true, default: ""}
      ],
      outcomes: ["timed_out", "received"],
      palette_entry: %{label: "Confirm the contact"},
      version: 1

    alias StatifierBlocks.Compiler.ReservedExpansionSlotTest.ConfirmSubtree

    @impl StatifierBlocks.Composite
    def subtree(params), do: ConfirmSubtree.build(params)
  end

  describe "an author's slot of the reserved name on a declaring composite" do
    # Sabotage: dropped `reserved_slot_findings(block) ++` from
    # `declaring_node/7`'s case subject - green compile, no finding, and the
    # child below vanishes exactly as it did before this bead.
    test "draws a Resolve finding against the composite block" do
      assert {:error, findings} = Compiler.compile(document_with_reserved_slot(), palette())

      assert [%Finding{} = finding] =
               Enum.filter(findings, &(&1.code == :reserved_slot_name))

      assert finding.stage == :resolve
      assert finding.block_id == "blk_CS"
      assert finding.reason == {:reserved_slot_name, "blk_CS", @reserved}
      assert finding.message =~ "rename it"
    end

    # Sabotage: passed no `:fault` to `Finding.new/4` - red, because the
    # stage's own default is `:package` and an editor renders that as
    # "this cannot be fixed here", which is false of a slot an author typed.
    test "is the author's fault, not the palette's" do
      assert {:error, findings} = Compiler.compile(document_with_reserved_slot(), palette())

      assert [%Finding{fault: :author}] =
               Enum.filter(findings, &(&1.code == :reserved_slot_name))
    end

    # Sabotage: reported on `slots != %{}` rather than on the key - red here,
    # because the declared `on_received` slot below is an author slot too and
    # the finding would name a document that did nothing wrong.
    test "is not drawn by a declared outcome slot on the same block" do
      block = Map.put(block(), :slots, %{"on_received" => []})

      assert {:ok, _compiled} = Compiler.compile(document(block), palette())
    end
  end

  describe "the narrowing: what the exemption still covers" do
    # The negative test. Sabotage: made `compiler_slot?/2`'s reserved-key
    # clause answer `false` - red, because the exemption is what keeps the
    # compiler's own key off the structure stage's report and the untouched
    # document below would stop compiling.
    test "the compiler's own key on the same block draws nothing" do
      assert {:ok, compiled} = Compiler.compile(document(block()), palette())

      assert compiled.scxml =~ "s_blk_CS"
    end

    # The other half of the negative test. Sabotage: made `compiler_slot?/2`
    # answer `true` on the slot name alone, ignoring the declaring set - red,
    # because this block is an ordinary core block whose answer to a slot its
    # type does not declare is the ordinary structural one, whatever the slot
    # is called.
    test "the same name on a block that is not a declaring composite keeps :undeclared_slot" do
      block =
        Block.new("core.sequence", id: "blk_PLAIN", slots: %{@reserved => [dropped_child()]})

      assert {:error, findings} = Compiler.compile(document(block), palette())

      assert Enum.any?(
               findings,
               &(&1.code == :undeclared_slot and &1.stage == :structure)
             )

      refute Enum.any?(findings, &(&1.code == :reserved_slot_name))
    end
  end

  # -- fixtures ------------------------------------------------------------

  defp palette do
    Palette.new(
      Map.put(Palette.core_types(), "signup.confirm_step_declaring", ConfirmStepDeclaring)
    )
  end

  defp block,
    do:
      Block.new("signup.confirm_step_declaring",
        id: "blk_CS",
        config: %{"event" => "contact.confirmed"}
      )

  defp dropped_child,
    do: Block.new("core.wait", id: "blk_W", config: %{"duration" => "5m"})

  defp document_with_reserved_slot do
    block()
    |> Map.put(:slots, %{@reserved => [dropped_child()]})
    |> document()
  end

  defp document(block),
    do:
      Document.new(
        Block.new("core.sequence", id: "blk_ROOT", slots: %{"body" => [block]}),
        id: "bdoc_reservedexpansionslot"
      )
end
