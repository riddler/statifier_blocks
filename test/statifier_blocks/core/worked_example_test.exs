defmodule StatifierBlocks.Core.WorkedExampleTest do
  @moduledoc """
  The bead's second acceptance criterion: the ADR-0001 worked example
  validates against the **real** core types.

  The example is the one `StatifierBlocks.DocumentFixtures` already builds
  and the one `test/fixtures/documents/worked_example.json` stores, so this
  is the same document the encoder and decoder are checked against - not a
  restatement of it that could drift. Only its four `myapp.*` types are
  stubbed (`StatifierBlocks.CoreFixtures`); every `core.*` block in it
  resolves to the module this bead ships.

  `CoreFixtures.check/2` is the walk: resolve, `validate_config/1`, no
  undeclared slots, arity, kind admission. It is test-only - the shipped
  palette-aware validation is `sb-da9`'s - but the callbacks it calls are
  the real ones, which is what the criterion is about.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{Core, CoreFixtures, Document, DocumentFixtures}

  setup do
    %{document: DocumentFixtures.worked_example(), palette: CoreFixtures.palette()}
  end

  # Sabotage: made `Core.Parallel.slots/1` prefix lanes with `"lane-"`
  # instead of `"lane_"` - red with two undeclared-slot findings, which is
  # the check earning its keep.
  test "the worked example validates clean against the real core types", ctx do
    assert CoreFixtures.check(ctx.palette, ctx.document) == []
  end

  # Sabotage: dropped the `"core.branch"` entry from `Palette.core_types/0`
  # - red on the resolution assert.
  test "every core block in it resolves to the module this bead ships", ctx do
    resolved =
      ctx.document
      |> Document.blocks()
      |> Enum.filter(&String.starts_with?(&1.type, "core."))
      |> Map.new(fn block ->
        {:ok, module, _block} = StatifierBlocks.Palette.resolve(ctx.palette, block)
        {block.type, module}
      end)

    assert resolved == %{
             "core.sequence" => Core.Sequence,
             "core.resumable_group" => Core.ResumableGroup,
             "core.branch" => Core.Branch,
             "core.parallel" => Core.Parallel,
             "core.wait" => Core.Wait
           }
  end

  # Sabotage: made `Core.Branch.slots/1` drop the `otherwise` slot - red,
  # because the example's `otherwise` becomes undeclared.
  test "the example's config-parameterized slot sets are exactly what its types declare", ctx do
    branch = block(ctx.document, "blk_BR")
    parallel = block(ctx.document, "blk_PAR")

    assert Core.Branch.slots(branch.config) == [
             {"arm_approved", :at_least_one, ~s(When "approved")},
             {"otherwise", :any, "Otherwise"}
           ]

    assert Core.Parallel.slots(parallel.config) == [
             {"lane_capture", :any, "capture"},
             {"lane_receipt", :any, "receipt"}
           ]

    assert Map.keys(branch.slots) |> Enum.sort() == ["arm_approved", "otherwise"]
    assert Map.keys(parallel.slots) |> Enum.sort() == ["lane_capture", "lane_receipt"]
  end

  # Sabotage: had `Core.Wait`'s `validate_config/1` reject `48h` - red on
  # the wait block's config finding.
  test "the example's core configs are accepted by the real validators", ctx do
    assert Core.Wait.validate_config(block(ctx.document, "blk_WAI").config) == :ok
    assert Core.ResumableGroup.validate_config(block(ctx.document, "blk_GRP").config) == :ok
    assert Core.Branch.validate_config(block(ctx.document, "blk_BR").config) == :ok
    assert Core.Parallel.validate_config(block(ctx.document, "blk_PAR").config) == :ok
  end

  # Sabotage: pointed the example's interrupt at `myapp.notify` (a step)
  # instead of `myapp.on_event` - red with a `:kind_not_admitted` finding,
  # from declarations alone.
  test "a step dropped into the example's interrupts slot is refused", ctx do
    interrupt = block(ctx.document, "blk_INT")
    step = block(ctx.document, "blk_NOT")

    group = block(ctx.document, "blk_GRP")
    broken = put_in(group.slots["interrupts"], [step])
    document = %{ctx.document | root: replace(ctx.document.root, broken)}

    assert CoreFixtures.check(ctx.palette, ctx.document) == []

    assert [{:kind_not_admitted, id, "blk_GRP", "interrupts"}] =
             CoreFixtures.check(ctx.palette, document)

    assert id == step.id
    assert interrupt.type == "myapp.on_event"
  end

  defp block(document, id) do
    document |> Document.blocks() |> Enum.find(&(&1.id == id))
  end

  # Rebuilds the root with `replacement` swapped in for the block sharing
  # its id. The worked example nests the group one level under the root.
  defp replace(root, replacement) do
    body =
      Enum.map(root.slots["body"], fn b -> if b.id == replacement.id, do: replacement, else: b end)

    %{root | slots: %{root.slots | "body" => body}}
  end
end
