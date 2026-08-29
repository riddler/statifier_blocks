defmodule StatifierBlocks.SlotValidation do
  @moduledoc """
  ADR-0002 decision 6's two properties, checked over a whole document
  against a palette: declared slots are the complete set a block may carry
  (`:undeclared_slot`), and a slot's child count must satisfy the arity
  its type declares for it (`:slot_arity_violated`).

  One implementation, consulted by both the editor and the compiler
  (`sb-iwz`), the same way `StatifierBlocks.Assignability` is - both are
  passed the same palette and the same document, and neither owns a
  private copy of either rule.

  ## Ordering

  `validate/2` walks `Document.blocks/1` (pre-order, root first) and
  concatenates each block's findings, so the result is already in the
  order a caller wants to report them. Within one block, arity findings
  come first, in `slots/1`'s own declaration order; undeclared-slot
  findings come after, in UTF-8-sorted slot-name order (matching
  `Document.blocks/1`'s own sorted slot traversal).

  ## Degradation

  A block whose type fails `Palette.resolve/2` contributes no findings of
  either kind - the same permissive default `Assignability.produces/4`
  uses, because unresolvability is ADR-0002 decision 3's own finding,
  reported by the walk that owns it, not this one.

  ## Totality, and where the `slots/1` precondition holds

  `module.slots(resolved.config)` is called with no rescue, exactly as
  `Assignability.valid_targets/4` calls `module.slots/1`: this package's
  rule is that nothing is rescued to a default. ADR-0002 decision 6
  guarantees `slots/1` returns without raising only for a config
  `validate_config/1` accepts, so `validate/2` is total over any document
  and palette whose block types honour that guarantee for the configs
  they are handed. In the compiler this precondition holds by
  construction - the Config stage runs `validate_config/1` over every
  block and stops the pipeline before Structure runs - but a caller
  outside the compiler (an editor, mid-edit) wanting the same guarantee
  runs `validate_config/1` first.
  """

  alias StatifierBlocks.{Block, BlockType, Document, Palette}

  @type finding ::
          {:slot_arity_violated, Block.id(), Block.slot_name(), BlockType.slot_arity(),
           non_neg_integer()}
          | {:undeclared_slot, Block.id(), Block.slot_name(), non_neg_integer()}

  @doc """
  Every slot-arity and undeclared-slot finding in `document` against
  `palette`, in `Document.blocks/1` pre-order. `:ok` when the list is
  empty.

  Per block: `Palette.resolve(palette, block)`. On `{:error, _}` the
  block contributes nothing. On `{:ok, module, resolved}`,
  `module.slots(resolved.config)` is the declaration list checked -
  `resolved.config`, not `block.config`, because the migrated config is
  what the type's own declarations are read against (ADR-0002 decision
  8), and it is what the compiler's Resolve stage already uses.
  """
  @spec validate(Palette.t(), Document.t()) :: :ok | {:error, [finding()]}
  def validate(%Palette{} = palette, %Document{} = document) do
    findings =
      document
      |> Document.blocks()
      |> Enum.flat_map(&block_findings(palette, &1))

    case findings do
      [] -> :ok
      findings -> {:error, findings}
    end
  end

  @spec block_findings(Palette.t(), Block.t()) :: [finding()]
  defp block_findings(palette, %Block{} = block) do
    case Palette.resolve(palette, block) do
      {:ok, module, resolved} ->
        declared = module.slots(resolved.config)
        arity_findings(declared, block) ++ undeclared_findings(declared, block)

      {:error, _reason} ->
        []
    end
  end

  # Arity findings, in `slots/1`'s own declaration order: one per declared
  # slot whose child count violates its arity. An absent slot key counts
  # as zero children (ADR-0001 decision 5's uniform shape, read literally).
  @spec arity_findings([BlockType.slot_decl()], Block.t()) :: [finding()]
  defp arity_findings(declared, %Block{} = block) do
    for {name, arity, _label} <- declared,
        count = length(Map.get(block.slots, name, [])),
        not arity_satisfied?(arity, count) do
      {:slot_arity_violated, block.id, name, arity, count}
    end
  end

  # Undeclared-slot findings, in UTF-8-sorted slot-name order: one per key
  # of `block.slots` that appears in no declaration. The count is how many
  # blocks the compile would drop.
  @spec undeclared_findings([BlockType.slot_decl()], Block.t()) :: [finding()]
  defp undeclared_findings(declared, %Block{} = block) do
    declared_names = MapSet.new(declared, fn {name, _arity, _label} -> name end)

    block.slots
    |> Map.keys()
    |> Enum.sort()
    |> Enum.reject(&MapSet.member?(declared_names, &1))
    |> Enum.map(fn name ->
      {:undeclared_slot, block.id, name, length(Map.get(block.slots, name))}
    end)
  end

  @doc """
  Whether `count` children satisfies `arity`, per ADR-0002 decision 6's
  four-row table: `:any` admits any count; `:at_least_one` needs `count >=
  1`; `:exactly_one` needs `count == 1`; `:zero_or_one` needs `count <= 1`.
  """
  @spec arity_satisfied?(BlockType.slot_arity(), non_neg_integer()) :: boolean()
  def arity_satisfied?(:any, _count), do: true
  def arity_satisfied?(:at_least_one, count), do: count >= 1
  def arity_satisfied?(:exactly_one, count), do: count == 1
  def arity_satisfied?(:zero_or_one, count), do: count <= 1
end
