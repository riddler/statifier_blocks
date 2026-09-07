defmodule StatifierBlocks.Compiler.ReservedRootOutcomeTest do
  @moduledoc """
  `sb-k0dy`, RQ-SF035-16: `failed` is reserved as an outcome name on a
  **root** block, and a document that declares it there is refused at
  compile with a `:config` finding.

  The collision the refusal exists for is asserted first and on the same
  document, because "these two would be one id" is the whole argument and
  a test that only asserted the refusal would be asserting a rule with no
  reason attached: ADR-0002's failure amendment of 2026-09-06 mints the
  one shared final an unhandled failure below the root reaches from the
  root block's id under `<prefix>failed`, and the root's own completion
  finals from the same id under `<prefix><outcome>`.

  What the document did before this bead is worth recording, because it
  is what the ruling is answering rather than a hypothetical: it was
  refused, by `Statifier` itself, as a `:chart` stage
  `{:duplicate_id, "s_blk_SUB__root_failed"}` whose fault is `:package`,
  which `StatifierBlocks.Compiler.Finding`'s moduledoc spells "a bug in
  this package or in a host's block type, and no edit to the document
  will help". The author could act on it and was told they could not,
  which is the class `ADR-0004` decision 9 reserves for a finding no
  document edit reaches. Nothing was
  miscompiled; what moves is which stage says so, in whose words, and
  against which field.

  The refusal is the root's alone. A block below the root naming an
  outcome `failed` mints its ids from its own id and is untouched, and
  every document that declares nothing of the sort compiles to the bytes
  it compiled to before - which
  `StatifierBlocks.Compiler.ByteCorpusTest` pins against goldens captured
  before this bead rather than against today's output.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{Block, Compiler, Document, Palette}
  alias StatifierBlocks.Compiler.Finding

  defmodule Constant do
    @moduledoc """
    A host type whose outcome list is a constant, one member of which is
    the reserved name. No config field answers for it, so the finding
    anchors on the block rather than on a field.
    """

    @behaviour StatifierBlocks.BlockType

    alias StatifierBlocks.Compiler.Context
    alias StatifierBlocks.Core.Emit

    @impl true
    def current_version, do: 1

    @impl true
    def slots(_config), do: []

    @impl true
    def config_schema(_config),
      do: [%{key: "label", type: :string, label: "Label", required?: false, default: ""}]

    @impl true
    def validate_config(_config), do: :ok

    @impl true
    def outcomes(_config), do: [{"done", "Done"}, {"failed", "Failed"}]

    @impl true
    def emit(%Block{}, context) do
      with {:ok, done} <- Context.outcome_id(context, "done"),
           {:ok, failed} <- Context.outcome_id(context, "failed") do
        {:ok, Emit.state(context.state_id, done, [Emit.final(done), Emit.final(failed)])}
      end
    end
  end

  setup do
    %{
      palette:
        Palette.new(Elixir.Map.merge(Palette.core_types(), %{"signup.constant" => Constant}))
    }
  end

  describe "the collision" do
    # The reason the name is reserved, on one document: the root's own
    # completion final and the shared unhandled-failure final are minted
    # from the same block id under the same prefix, so an outcome named
    # `failed` would ask for `s_blk_SUB__root_failed` twice.
    #
    # sabotage: minted the shared final under `<prefix>failure` instead of
    # `<prefix>failed` -> the two ids no longer collide and this goes red
    # (verified)
    test "the root's completion finals and the shared failure final share one namespace", ctx do
      assert {:ok, compiled} = compile(ctx, "approved", terminate: true)

      assert compiled.scxml =~ ~s(<final id="s_blk_SUB__root_approved")
      assert compiled.scxml =~ ~s(<final id="s_blk_SUB__root_failed")
    end
  end

  describe "the refusal" do
    # sabotage: dropped `reserved_outcome_findings/1` from `config_stage/2`
    # -> the document compiles and mints one id for two finals, and this
    # goes red (verified)
    test "a root outcome named failed is refused at compile", ctx do
      assert {:error, findings} = compile(ctx, "failed", terminate: true)

      assert [%Finding{} = finding] = findings
      assert finding.stage == :config
      assert finding.block_id == "blk_SUB"
      assert finding.fault == :author
      assert finding.severity == :error
      assert finding.message =~ ~s(declares the outcome "failed" on the root block)
      assert finding.message =~ "section 4 step 3"
    end

    # `core.subchart` reads its outcomes off `outcomes`, and the finding
    # says so: an editor underlines the field the author wrote the name in
    # rather than the whole card.
    # sabotage: returned the first sorted config key unconditionally ->
    # the finding anchors on `assign_to` and this goes red (verified)
    test "the finding names the config field the outcome came out of", ctx do
      assert {:error, [%Finding{} = finding]} = compile(ctx, "failed", terminate: true)

      assert finding.config_key == "outcomes"
    end

    # The other half of the ruling's anchor rule. A type whose outcome
    # list is a constant has no field to name, and `nil` is the block
    # anchor every finding that is about a block rather than one of its
    # fields already carries.
    # sabotage: anchored on the first config key when no key answers ->
    # the finding names `label`, which the author cannot fix, and this
    # goes red (verified)
    test "a constant outcome list anchors on the block, with no config key", ctx do
      root = Block.new("signup.constant", id: "blk_CONST", config: %{"label" => "Charge"})
      document = Document.new(root, id: "bdoc_CONST")

      assert {:error, [%Finding{} = finding]} =
               Compiler.compile(document, ctx.palette, terminate: true)

      assert finding.stage == :config
      assert finding.block_id == "blk_CONST"
      assert finding.config_key == nil
    end

    # The refusal does not depend on the compile option: both prefixes end
    # in the same role, so the collision is the same one under either.
    # sabotage: read the prefix and refused only under `:terminate` ->
    # a child-use compile mints the duplicate id and this goes red
    # (verified)
    test "it is refused under child_use as well as terminate", ctx do
      assert {:error, [%Finding{stage: :config}]} = compile(ctx, "failed", child_use: true)
    end
  end

  describe "what stays legal" do
    # Only the root's id mints `<prefix>failed`. A block below the root
    # mints its outcome ids from its own id, so the name says nothing
    # about the document's own ending and is the author's to use.
    #
    # sabotage: walked the whole tree instead of the root block ->
    # this document is refused and this goes red (verified)
    test "a block below the root may name an outcome failed", ctx do
      child =
        Block.new("core.subchart",
          id: "blk_SUB",
          config: %{"chart" => "bdoc_CHILD", "outcomes" => "failed"}
        )

      root = Block.new("core.sequence", id: "blk_SEQ", slots: %{"body" => [child]})

      assert {:ok, compiled} =
               Compiler.compile(Document.new(root, id: "bdoc_ROOT"), ctx.palette, terminate: true)

      assert compiled.scxml =~ "s_blk_SUB"
    end

    # A root outcome that merely resembles the reserved name is not it:
    # the reservation is one literal word, not a family.
    # sabotage: matched on `String.starts_with?/2` -> `failed_over` is
    # refused and this goes red (verified)
    test "a root outcome named failed_over compiles", ctx do
      assert {:ok, _compiled} = compile(ctx, "failed_over", terminate: true)
    end
  end

  # A `core.subchart` root whose declared outcome list is `outcomes`, with
  # an unhandled `core.invoke` failure below it so the shared final of
  # section 4 step 3 is actually emitted.
  defp compile(ctx, outcomes, opts) do
    invoke =
      Block.new("core.invoke", id: "blk_INV", config: %{"invoke_type" => "myapp:authorize"})

    root =
      Block.new("core.subchart",
        id: "blk_SUB",
        config: %{"chart" => "bdoc_CHILD", "outcomes" => outcomes, "assign_to" => ""},
        slots: %{("on_" <> outcomes) => [invoke]}
      )

    Compiler.compile(Document.new(root, id: "bdoc_ROOT"), ctx.palette, opts)
  end
end
