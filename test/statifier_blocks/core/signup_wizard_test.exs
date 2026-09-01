defmodule StatifierBlocks.Core.SignupWizardTest do
  @moduledoc """
  The family's second worked example - a signup wizard with A/B testing -
  checked against the **real** core types, the way
  `StatifierBlocks.Core.WorkedExampleTest` checks the first one.

  Two examples exist rather than one because between them they reach every
  core container and the interrupt rail. The credit-card example uses
  `core.resumable_group` and a host interrupt handler; this one uses the
  plain `core.group` and the `core.on_event` this package ships, which is
  the half ADR-0003 decision 3's kind gate is easiest to get wrong on.

  Both are stored as canonical bytes as well as built in memory, so the
  encoder and decoder are each checked against the same document.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{Core, CoreFixtures, Document, DocumentFixtures}

  setup do
    %{document: DocumentFixtures.signup_wizard(), palette: CoreFixtures.palette()}
  end

  # Sabotage: made `Core.Group.slots/1` name its second slot "interrupt"
  # rather than "interrupts" - red with an undeclared-slot finding, which
  # is this check earning its keep.
  test "the signup wizard validates clean against the real core types", ctx do
    assert CoreFixtures.check(ctx.palette, ctx.document) == []
  end

  # Sabotage: dropped the `"core.group"` entry from `Palette.core_types/0`
  # - red on the resolution assert. Second sabotage, for the `uncovered`
  # set below: dropped `"core.assign"` from the registry - red, because the
  # union then names a type the registry no longer has (verified).
  test "it reaches the two core types the credit-card example does not", ctx do
    resolved = resolved_core_types(ctx)

    assert resolved == %{
             "core.sequence" => Core.Sequence,
             "core.group" => Core.Group,
             "core.branch" => Core.Branch,
             "core.on_event" => Core.OnEvent
           }

    other = resolved_core_types(%{ctx | document: DocumentFixtures.worked_example()})

    # `core.send` joins the same list on the same terms.
    # `core.invoke` is in neither document: both examples spell their host
    # call as a `myapp.*` type, which is what ADR-0002 decision 2 two-registry
    # seam looks like from the authoring side. `core.raise` and `core.assign`
    # are leaves neither example uses yet. All three are named here rather
    # than dropped from the comparison, so a core type falling out of the
    # worked examples has to be admitted deliberately, and the list shrinks
    # the day an example that uses one of them lands.
    # `core.drafts` and `core.placeholder` are uncovered on different terms
    # from the six above, and permanently rather than until an example lands.
    # Both are facts about a workflow *under construction* (ADR-0002's
    # amendment of 2026-08-31, section G13), and a worked example is a
    # finished workflow: an example carrying a parked fragment or a
    # deliberate gap would be demonstrating an unfinished document as though
    # it were the reference one.
    uncovered =
      MapSet.new([
        "core.assign",
        "core.drafts",
        "core.foreach",
        "core.invoke",
        "core.placeholder",
        "core.raise",
        "core.send",
        "core.subchart"
      ])

    assert MapSet.new(Map.keys(resolved))
           |> MapSet.union(MapSet.new(Map.keys(other)))
           |> MapSet.union(uncovered) ==
             MapSet.new(Map.keys(StatifierBlocks.Palette.core_types()))
  end

  # Sabotage: made `Core.Branch.slots/1` drop the `otherwise` slot - red,
  # because the wizard's `otherwise` becomes undeclared.
  test "the branch's arm set is exactly what its config declares", ctx do
    branch = block(ctx.document, "blk_WBR")

    assert Core.Branch.slots(branch.config) == [
             {"arm_variant_b", :at_least_one, ~s(When "variant_b")},
             {"otherwise", :any, "Otherwise"}
           ]

    assert Map.keys(branch.slots) |> Enum.sort() == ["arm_variant_b", "otherwise"]
  end

  # Sabotage: dropped `"abandon"` from `Core.OnEvent`'s accepted outcomes -
  # red on the handler's config finding.
  test "the wizard's core configs are accepted by the real validators", ctx do
    assert Core.OnEvent.validate_config(block(ctx.document, "blk_WINT").config) == :ok
    assert Core.Branch.validate_config(block(ctx.document, "blk_WBR").config) == :ok
    assert Core.Group.validate_config(block(ctx.document, "blk_WGRP").config) == :ok
  end

  # Sabotage: removed `kinds: [:interrupt_handler]` from `Core.OnEvent.io/1`
  # - red, because the shipped handler stops being admitted by the slot
  # written for it.
  test "the shipped handler is admitted in interrupts and refused in body", ctx do
    handler = block(ctx.document, "blk_WINT")
    group = block(ctx.document, "blk_WGRP")

    assert CoreFixtures.check(ctx.palette, ctx.document) == []

    misplaced = %{group | slots: %{group.slots | "body" => [handler]}}
    document = %{ctx.document | root: replace(ctx.document.root, misplaced)}

    assert [{:kind_not_admitted, id, "blk_WGRP", "body"}] =
             CoreFixtures.check(ctx.palette, document)

    assert id == handler.id
  end

  defp resolved_core_types(ctx) do
    ctx.document
    |> Document.blocks()
    |> Enum.filter(&String.starts_with?(&1.type, "core."))
    |> Map.new(fn block ->
      {:ok, module, _block} = StatifierBlocks.Palette.resolve(ctx.palette, block)
      {block.type, module}
    end)
  end

  defp block(document, id) do
    document |> Document.blocks() |> Enum.find(&(&1.id == id))
  end

  # Rebuilds the root with `replacement` swapped in for the block sharing
  # its id. The wizard nests the group one level under the root.
  defp replace(root, replacement) do
    body =
      Enum.map(root.slots["body"], fn b -> if b.id == replacement.id, do: replacement, else: b end)

    %{root | slots: %{root.slots | "body" => body}}
  end
end
