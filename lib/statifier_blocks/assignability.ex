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

  @doc """
  ADR-0003 decision 7's one decision function: kind admission for
  `candidate` at `target`, plus the seams whose verdict a placement at
  `target` can change.

  `candidate` not yet in `document` (`Document.fetch_path/2` returns
  `:error`) is an **insert**: two seams, `inbound_type(target)` against
  `candidate`'s `consumes`, and `candidate`'s resolved `produces` against
  the `consumes` of whatever block currently sits at `target`'s index
  (nothing to check when the slot ends there).

  `candidate` already in `document` is a **move**: the same two seams, plus
  the seam it vacates - at its current position `{p, s, i}`, removing it
  makes `i - 1` and `i + 1` adjacent, so the resolved `produces` of the
  block at `i - 1` (or the slot's own inbound type when `i == 0`) is
  checked against the `consumes` of the block at `i + 1` (nothing to check
  when the slot has no `i + 1`).

  Findings are decision 8's vocabulary verbatim, in this order when more
  than one applies: kind admission first, then the insertion seams, then
  the vacated seam. `:ok` when the list is empty.

  Degradation, per decision 5: a block that fails `Palette.resolve/2` - the
  candidate, the parent, or any block on a seam - contributes the
  permissive default rather than a finding, the same way `io/2` already
  degrades a module that is not loadable.
  """
  @spec check(Palette.t(), Document.t(), target(), Block.t(), context()) ::
          :ok | {:error, [finding()]}
  def check(
        %Palette{} = palette,
        %Document{} = document,
        {parent_id, slot, _index} = target,
        %Block{} = candidate,
        ctx
      ) do
    kind_finding = kind_admission_finding(palette, document, parent_id, slot, candidate)
    upstream_finding = upstream_seam_finding(palette, document, target, candidate, ctx)
    downstream_finding = downstream_seam_finding(palette, document, target, candidate, ctx)
    vacated_finding = vacated_seam_finding(palette, document, candidate, ctx)

    case Enum.reject(
           [kind_finding, upstream_finding, downstream_finding, vacated_finding],
           &is_nil/1
         ) do
      [] -> :ok
      findings -> {:error, findings}
    end
  end

  # `{module, config}` for `block` through `palette`, or `{nil, %{}}` when
  # `Palette.resolve/2` fails - the same permissive shape `io/2` already
  # gives a module that is not loadable, so every primitive below degrades
  # through the one path.
  @spec resolve_module_config(Palette.t(), Block.t()) :: {module() | nil, Block.config()}
  defp resolve_module_config(palette, block) do
    case Palette.resolve(palette, block) do
      {:ok, module, resolved} -> {module, resolved.config}
      {:error, _reason} -> {nil, %{}}
    end
  end

  # `parent_id`'s `{module, config}`, or `{nil, %{}}` when no block in
  # `document` carries it (a permissive default: `admits?/3` then sees
  # `:any`, which is the total, never-raising reading decision 5 already
  # establishes for every other absent declaration).
  @spec resolve_parent(Palette.t(), Document.t(), Block.id()) :: {module() | nil, Block.config()}
  defp resolve_parent(palette, document, parent_id) do
    case find_block(document, parent_id) do
      nil -> {nil, %{}}
      parent -> resolve_module_config(palette, parent)
    end
  end

  # `block`'s declared `consumes`, defaulting to `:unknown` (decision 5)
  # through the same degradation `resolve_module_config/2` gives.
  @spec consumes_of(Palette.t(), Block.t()) :: type_expr() | :unknown
  defp consumes_of(palette, block) do
    {module, config} = resolve_module_config(palette, block)
    module |> io(config) |> Map.get(:consumes, :unknown)
  end

  @spec kind_admission_finding(
          Palette.t(),
          Document.t(),
          Block.id(),
          Block.slot_name(),
          Block.t()
        ) ::
          finding() | nil
  defp kind_admission_finding(palette, document, parent_id, slot, candidate) do
    parent_mc = resolve_parent(palette, document, parent_id)
    candidate_mc = resolve_module_config(palette, candidate)

    if admits?(parent_mc, slot, candidate_mc) do
      nil
    else
      {parent_module, parent_config} = parent_mc
      {candidate_module, candidate_config} = candidate_mc
      accepts = slot_accepts(parent_module, parent_config, slot)
      candidate_kinds = kinds(candidate_module, candidate_config)
      {:kind_not_admitted, candidate.id, parent_id, slot, candidate_kinds, accepts}
    end
  end

  # The block, or `:slot_entry` when there is none, at the seam upstream of
  # `target` - the sibling at `index - 1`, or the slot's own inbound
  # (nothing produced by a specific block) at `index == 0`.
  @spec upstream_ref(Document.t(), target()) :: Block.id() | :slot_entry
  defp upstream_ref(_document, {_parent_id, _slot, 0}), do: :slot_entry

  defp upstream_ref(document, {parent_id, slot, index}) do
    case find_block(document, parent_id) do
      nil ->
        :slot_entry

      parent ->
        case Enum.at(Map.get(parent.slots, slot, []), index - 1) do
          nil -> :slot_entry
          sibling -> sibling.id
        end
    end
  end

  @spec upstream_seam_finding(Palette.t(), Document.t(), target(), Block.t(), context()) ::
          finding() | nil
  defp upstream_seam_finding(palette, document, target, candidate, ctx) do
    inbound = inbound_type(palette, document, target, ctx)
    candidate_consumes = consumes_of(palette, candidate)

    if assignable?(palette, inbound, candidate_consumes) do
      nil
    else
      {:type_mismatch, candidate.id, upstream_ref(document, target), inbound, candidate_consumes}
    end
  end

  @spec downstream_seam_finding(Palette.t(), Document.t(), target(), Block.t(), context()) ::
          finding() | nil
  defp downstream_seam_finding(palette, document, {parent_id, slot, index}, candidate, ctx) do
    with parent when not is_nil(parent) <- find_block(document, parent_id),
         downstream when not is_nil(downstream) <-
           Enum.at(Map.get(parent.slots, slot, []), index) do
      candidate_produces = produces(palette, document, candidate, ctx)
      downstream_consumes = consumes_of(palette, downstream)

      if assignable?(palette, candidate_produces, downstream_consumes) do
        nil
      else
        {:type_mismatch, downstream.id, candidate.id, candidate_produces, downstream_consumes}
      end
    else
      nil -> nil
    end
  end

  # The seam a move vacates: nil when `candidate` is not already in
  # `document` (an insert has nothing to vacate), and nil when the slot has
  # no block after `candidate`'s current position (nothing becomes adjacent
  # to nothing).
  @spec vacated_seam_finding(Palette.t(), Document.t(), Block.t(), context()) :: finding() | nil
  defp vacated_seam_finding(palette, document, candidate, ctx) do
    case Document.fetch_path(document, candidate.id) do
      :error ->
        nil

      {:ok, path} ->
        {parent_id, slot, index} = List.last(path)

        case find_block(document, parent_id) do
          nil -> nil
          parent -> vacated_seam_finding(palette, document, parent, slot, index, ctx)
        end
    end
  end

  @spec vacated_seam_finding(
          Palette.t(),
          Document.t(),
          Block.t(),
          Block.slot_name(),
          non_neg_integer(),
          context()
        ) :: finding() | nil
  defp vacated_seam_finding(palette, document, parent, slot, index, ctx) do
    children = Map.get(parent.slots, slot, [])

    case Enum.at(children, index + 1) do
      nil ->
        nil

      after_block ->
        vacated_seam_finding(palette, document, parent, slot, index, children, after_block, ctx)
    end
  end

  @spec vacated_seam_finding(
          Palette.t(),
          Document.t(),
          Block.t(),
          Block.slot_name(),
          non_neg_integer(),
          [Block.t()],
          Block.t(),
          context()
        ) :: finding() | nil
  defp vacated_seam_finding(palette, document, parent, slot, index, children, after_block, ctx) do
    {before_produces, before_ref} =
      seam_before(palette, document, parent, slot, index, children, ctx)

    after_consumes = consumes_of(palette, after_block)

    if assignable?(palette, before_produces, after_consumes) do
      nil
    else
      {:type_mismatch, after_block.id, before_ref, before_produces, after_consumes}
    end
  end

  # The producing side of a vacated seam: the slot's own inbound type at
  # `index == 0` (there is no block before it to name), or the resolved
  # `produces` of the sibling at `index - 1` otherwise.
  @spec seam_before(
          Palette.t(),
          Document.t(),
          Block.t(),
          Block.slot_name(),
          non_neg_integer(),
          [Block.t()],
          context()
        ) :: {type_expr() | :unknown, Block.id() | :slot_entry}
  defp seam_before(palette, document, parent, slot, 0, _children, ctx) do
    {inbound_type(palette, document, {parent.id, slot, 0}, ctx), :slot_entry}
  end

  defp seam_before(palette, document, _parent, _slot, index, children, ctx) do
    case Enum.at(children, index - 1) do
      nil -> {:unknown, :slot_entry}
      before_block -> {produces(palette, document, before_block, ctx), before_block.id}
    end
  end

  @doc """
  Every position in `document` where `candidate` may be dropped, per
  ADR-0003's `valid_targets/4`: for every block in `Document.blocks/1`, for
  every slot that block's module **declares** (`module.slots(config)`, not
  the slot keys the stored document happens to carry), for every index from
  `0` to that slot's current child count inclusive, the position is kept
  when `check/5` returns `:ok` for it.

  Deterministic: `Document.blocks/1` is already pre-order, `slots/1` is
  visited in the order it declares slots, and indices ascend within each
  slot - so the same call always returns the same list, in the same order.

  A block whose type fails `Palette.resolve/2` contributes no positions:
  there is no module to ask for a declared slot set, so this is an absence
  of positions rather than a refusal. Offering a target inside a slot that
  is not even declared would be offering a position the document walk that
  owns undeclared-slot findings (ADR-0002 decision 6) then rejects.
  """
  @spec valid_targets(Palette.t(), Document.t(), Block.t(), context()) :: [target()]
  def valid_targets(%Palette{} = palette, %Document{} = document, %Block{} = candidate, ctx) do
    for block <- Document.blocks(document),
        {module, config} = resolve_module_config(palette, block),
        module != nil,
        {slot, _arity, _label} <- module.slots(config),
        index <- 0..length(Map.get(block.slots, slot, [])),
        check(palette, document, {block.id, slot, index}, candidate, ctx) == :ok do
      {block.id, slot, index}
    end
  end

  @doc """
  Every finding in `document`, per ADR-0003's `validate/3`: every seam
  already present in the document, checked with the same rules `check/5`
  checks a seam with - the whole-document counterpart to `check/5`'s
  single-position query.

  A document's seams are exactly its blocks' own upstream seams: the slot's
  own inbound (or the previous sibling's resolved `produces`, when there is
  one) against the block's `consumes`, plus the same kind-admission check
  `check/5` runs for a candidate at a target. Walking every block in
  `Document.blocks/1` other than the root (which occupies no slot and has
  no seam of its own) and checking each one this way visits every seam in
  the document exactly once - a block never shares its upstream seam with
  any other block, and nothing in a slot has a seam after its last child
  that some other block's own upstream check does not already cover.

  This is deliberately **not** `check/5` called with a block already
  sitting at its own current position as the candidate: `check/5`'s
  downstream and vacated seams are defined relative to a `target` the
  candidate is being placed at or removed from, and a block that already
  occupies `target` makes both of those seams check the block against
  itself, or against neighbors as though the block were not there at all -
  neither is a seam that exists in `document` as given. `validate/3`
  reaches the same two checks `check/5` runs for kind admission and the
  upstream seam - `kind_admission_finding/5` and `upstream_seam_finding/5`
  - directly, so the decision stays the one `check/5` is built from without
  running its candidate-already-there degenerate case.

  `:ok` when the document has no findings; otherwise `{:error, findings}`
  with every block's findings concatenated, in `Document.blocks/1`'s
  pre-order.
  """
  @spec validate(Palette.t(), Document.t(), context()) :: :ok | {:error, [finding()]}
  def validate(%Palette{} = palette, %Document{} = document, ctx) do
    findings =
      for block <- Document.blocks(document),
          {:ok, [_ | _] = path} <- [Document.fetch_path(document, block.id)],
          {parent_id, slot, index} = List.last(path),
          finding <- [
            kind_admission_finding(palette, document, parent_id, slot, block),
            upstream_seam_finding(palette, document, {parent_id, slot, index}, block, ctx)
          ],
          finding != nil do
        finding
      end

    case findings do
      [] -> :ok
      findings -> {:error, findings}
    end
  end
end
