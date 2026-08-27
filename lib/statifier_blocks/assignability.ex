defmodule StatifierBlocks.Assignability do
  @moduledoc """
  May this block land in this slot? Answered by two independent gates -
  structural admission by kind tag, and data-flow compatibility by opaque
  string identity plus a host-supplied widening relation (ADR-0003).

  One implementation, consulted by both the editor (`sb-w50`) and the
  compiler (`sb-iwz`), because both are passed the same palette (ADR-0003
  decision 6).

  This module currently carries ADR-0003's seven types and four
  primitives: `io/2`, `kinds/2`, `slot_accepts/3` and `admits?/3`. These
  four are a deliberate widening of the record's own listed surface, not a
  second path around it - `check/5`, `valid_targets/4` and `validate/3`
  (later phases) are built out of them, not alongside them. They are public
  because the kind gate has to be testable in isolation, and because
  `StatifierBlocks.CoreFixtures`'s stand-in walk has to delegate to the
  shipped rule rather than keep a copy of it.

  Defaults, per ADR-0003 decision 5: an absent `io/1` callback, or a module
  that is not loadable, is `%{}`; an absent `:kinds` key is `[:step]`; an
  absent `:slot_accepts` entry for a given slot is `:any`.
  """

  alias StatifierBlocks.{Block, Document, Palette}

  @typedoc "Opaque to this package. Never parsed, split, or normalized."
  @type type_expr :: String.t()

  @typedoc ~S(Structural tag. `:step` and `:interrupt_handler` ship here; hosts may mint more.)
  @type kind :: atom()

  @typedoc "What a block produces to its next sibling. See ADR-0003 decision 4."
  @type produces :: type_expr() | :unknown | {:passthrough, Block.slot_name()}

  @typedoc "The return shape of `c:StatifierBlocks.BlockType.io/1`. Every key optional."
  @type io :: %{
          optional(:kinds) => [kind()],
          optional(:consumes) => type_expr() | :unknown,
          optional(:produces) => produces(),
          optional(:slot_accepts) => %{optional(Block.slot_name()) => [kind()] | :any}
        }

  @typedoc "Caller-supplied, not stored in the document (ADR-0003 decision 4)."
  @type context :: %{optional(:entry_type) => type_expr() | :unknown}

  @typedoc "A position, as ADR-0001 decision 5 defines one."
  @type target :: {Block.id(), Block.slot_name(), non_neg_integer()}

  @type finding ::
          {:kind_not_admitted, Block.id(), Block.id(), Block.slot_name(), [kind()],
           [kind()] | :any}
          | {:type_mismatch, Block.id(), Block.id() | :slot_entry, type_expr() | :unknown,
             type_expr() | :unknown}

  @doc """
  `module.io(config)`, or `%{}` when `io/1` is absent or `module` is not
  loadable (ADR-0003 decision 5). Checked with `Code.ensure_loaded?/1` plus
  `function_exported?/3`, the pattern `StatifierBlocks.Palette.resolve/2`
  already uses.
  """
  @spec io(module(), Block.config()) :: io()
  def io(module, config) do
    if Code.ensure_loaded?(module) and function_exported?(module, :io, 1) do
      module.io(config)
    else
      %{}
    end
  end

  @doc "The block's `kinds`, defaulting to `[:step]` (ADR-0003 decision 5)."
  @spec kinds(module(), Block.config()) :: [kind()]
  def kinds(module, config), do: Map.get(io(module, config), :kinds, [:step])

  @doc """
  The accepted kinds for `slot` on `module`, defaulting to `:any` when the
  slot has no entry in `io/1`'s `:slot_accepts` map (ADR-0003 decision 5).
  """
  @spec slot_accepts(module(), Block.config(), Block.slot_name()) :: [kind()] | :any
  def slot_accepts(module, config, slot) do
    module
    |> io(config)
    |> Map.get(:slot_accepts, %{})
    |> Map.get(slot, :any)
  end

  @doc """
  ADR-0003 decision 3's structural verdict for placing `child` in `slot` of
  `parent`: `:any` admits everything, otherwise the slot's accepted kinds
  and the child's own kinds must intersect.
  """
  @spec admits?({module(), Block.config()}, Block.slot_name(), {module(), Block.config()}) ::
          boolean()
  def admits?({parent, parent_config}, slot, {child, child_config}) do
    case slot_accepts(parent, parent_config, slot) do
      :any -> true
      accepted -> Enum.any?(kinds(child, child_config), &(&1 in accepted))
    end
  end

  @doc """
  ADR-0003 decision 6's ordered relation. Four steps, checked in this
  order, and the order is the contract:

    1. either side `:unknown` -> assignable (decision 5's permissive default);
    2. `produced == consumed` -> assignable (decision 1's identity relation);
    3. `palette.assignability` is `nil` -> not assignable (the floor a host
       cannot lower);
    4. otherwise `module.assignable?(produced, consumed)`.

  Reflexivity holds regardless of the host, because step 2 short-circuits
  before step 4 is ever reached - the host callback is consulted only after
  identity has already failed, so it can only widen the relation, never
  narrow it. Step 4 is guarded the same way every other optional seam in
  this package is: a `module` that is not loadable, or does not export
  `assignable?/2`, yields `false` rather than raising, so a misconfigured
  palette degrades to the floor instead of turning a validation pass into
  an exception.
  """
  @spec assignable?(Palette.t(), type_expr() | :unknown, type_expr() | :unknown) :: boolean()
  def assignable?(_palette, :unknown, _consumed), do: true
  def assignable?(_palette, _produced, :unknown), do: true
  def assignable?(_palette, same, same), do: true

  def assignable?(%Palette{assignability: nil}, _produced, _consumed), do: false

  def assignable?(%Palette{assignability: module}, produced, consumed) do
    if Code.ensure_loaded?(module) and function_exported?(module, :assignable?, 2) do
      module.assignable?(produced, consumed)
    else
      false
    end
  end

  @doc """
  `block`'s `produces`, resolved (ADR-0003 decision 4): a type expression
  resolves to itself; `:unknown` resolves to `:unknown`;
  `{:passthrough, slot}` resolves to the resolved `produces` of the last
  block in `slot`, or, when `slot` is empty (or is not a slot `block`
  declares - decision 4 is silent on that, and treating it as empty is the
  permissive, total reading decision 5 already establishes elsewhere),
  `block`'s own inbound type.

  A block that fails `Palette.resolve/2` contributes `:unknown` rather than
  a finding (ADR-0003 decision 5's degradation rule; unresolvability is
  ADR-0002 decision 3's finding, reported by the walk that owns it).

  ### Why this terminates

  Every recursive step lands at a strictly earlier position, in the
  document's pre-order, than the position that made the original call.
  Resolving `{:passthrough, slot}` on block `B` either descends to the last
  child of `B`'s own `slot` - later than `B`, but still strictly before
  whatever position asked for `B`'s `produces` in the first place, since
  that position comes after `B` and every descendant of `B` is ordered
  before `B`'s next sibling - or, when the slot is empty, falls back to
  `B`'s own inbound type, which is either `B`'s previous sibling or, at
  index 0, `B`'s parent - both strictly earlier than `B`. Pre-order rank
  over a finite tree is a well-founded measure with no infinite descending
  chain, so this cannot cycle even for a tree of nothing but empty
  passthrough sequences.
  """
  @spec produces(Palette.t(), Document.t(), Block.t(), context()) :: type_expr() | :unknown
  def produces(%Palette{} = palette, %Document{} = document, %Block{} = block, ctx) do
    case Palette.resolve(palette, block) do
      {:ok, module, resolved} ->
        module
        |> io(resolved.config)
        |> Map.get(:produces, :unknown)
        |> resolve_produces(palette, document, block, ctx)

      {:error, _reason} ->
        :unknown
    end
  end

  @spec resolve_produces(produces(), Palette.t(), Document.t(), Block.t(), context()) ::
          type_expr() | :unknown
  defp resolve_produces(:unknown, _palette, _document, _block, _ctx), do: :unknown

  defp resolve_produces({:passthrough, slot}, palette, document, block, ctx) do
    case block.slots |> Map.get(slot, []) |> List.last() do
      nil -> own_inbound_type(palette, document, block, ctx)
      last_child -> produces(palette, document, last_child, ctx)
    end
  end

  defp resolve_produces(type_expr, _palette, _document, _block, _ctx), do: type_expr

  # `block`'s own inbound type: `inbound_type/4` applied to the position
  # `block` itself occupies, or the entry type when `block` is the root.
  @spec own_inbound_type(Palette.t(), Document.t(), Block.t(), context()) ::
          type_expr() | :unknown
  defp own_inbound_type(palette, document, block, ctx) do
    case Document.fetch_path(document, block.id) do
      {:ok, []} -> Map.get(ctx, :entry_type, :unknown)
      {:ok, path} -> inbound_type(palette, document, List.last(path), ctx)
      :error -> :unknown
    end
  end

  @doc """
  The inbound type at `target` (ADR-0003 decision 4), computed by walking -
  never stored:

    * `index > 0` -> the resolved `produces` of the sibling at `index - 1`;
    * `index == 0` -> the parent block's own inbound type, found by
      `Document.fetch_path/2` on the parent's id and recursing on its last
      path step;
    * the root (`fetch_path` returns `{:ok, []}`) -> `ctx[:entry_type]`,
      defaulting to `:unknown`.

  Total: a `parent_id` no block in `document` carries, or an `index` past
  the end of the slot's children, resolves to `:unknown` rather than
  raising, consistent with decision 5's permissive default. See
  `produces/4` for the termination argument this function's own recursion
  (through `own_inbound_type/4` and back) relies on - every step here moves
  to a strictly earlier pre-order position too: a previous sibling or a
  parent, both earlier than `target` itself.
  """
  @spec inbound_type(Palette.t(), Document.t(), target(), context()) :: type_expr() | :unknown
  def inbound_type(%Palette{} = palette, %Document{} = document, {parent_id, slot, index}, ctx)
      when index > 0 do
    with parent when not is_nil(parent) <- find_block(document, parent_id),
         sibling when not is_nil(sibling) <- Enum.at(Map.get(parent.slots, slot, []), index - 1) do
      produces(palette, document, sibling, ctx)
    else
      nil -> :unknown
    end
  end

  def inbound_type(%Palette{} = palette, %Document{} = document, {parent_id, _slot, 0}, ctx) do
    case Document.fetch_path(document, parent_id) do
      {:ok, []} -> Map.get(ctx, :entry_type, :unknown)
      {:ok, path} -> inbound_type(palette, document, List.last(path), ctx)
      :error -> :unknown
    end
  end

  # O(n) per lookup over `Document.blocks/1` - the right first
  # implementation (ADR-0003's design notes): it needs no new function on
  # `Document`, whose contract belongs to another bead, and the hot path
  # (`valid_targets/4`) is free to build its own id-to-block map for a
  # single pass.
  @spec find_block(Document.t(), Block.id()) :: Block.t() | nil
  defp find_block(document, id), do: Enum.find(Document.blocks(document), &(&1.id == id))
end
