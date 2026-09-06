defmodule StatifierBlocks.Assignability do
  @moduledoc """
  May this block land in this slot? Answered by two independent gates -
  structural admission by kind tag (ADR-0003 decision 3, untouched), and
  data flow by the environment at the position, checked with the datamodel
  document's own read check plus the palette's host relation last
  (ADR-0011).

  One implementation, consulted by both the editor and the compiler, because
  both are passed the same palette.

  ## What the data-flow gate is a gate on

  Nothing flows between adjacent blocks. ADR-0011 supersedes ADR-0003's seam:
  a block declares the datamodel paths it reads and writes, and
  `StatifierBlocks.Environment` carries a map from path to type through the
  document in pre-order. The question at a position is whether the
  environment there satisfies what the block reads, and the answer comes from
  `StatifierDatamodel.Types.satisfies/3` - the one read check, defined in the
  package that owns the document. This package defines no second one, and no
  `Compatibility` or `Coverage` module of its own.

  `consumes` and `produces` survive as sugar over the document's **subject
  path**, which the entry block's palette entry names (decision 6), so a
  palette that declared them against ADR-0003 keeps saying what it said.

  ## The contract

  The five functions ADR-0003's "The relation as typespecs" section named
  keep their arities, and two of them keep their arities while changing what
  they are computed from:

      @spec check(Palette.t(), Document.t(), target(), Block.t(), context()) ::
              :ok | {:error, [finding()]}

      @spec valid_targets(Palette.t(), Document.t(), Block.t(), context()) :: [target()]

      @spec validate(Palette.t(), Document.t(), context()) :: :ok | {:error, [finding()]}

      @spec inbound_type(Palette.t(), Document.t(), target(), context()) ::
              type_expr() | :unknown

      @spec assignable?(Palette.t(), type_expr() | :unknown, type_expr() | :unknown) ::
              boolean()

  `inbound_type/4` is now the environment's type **at the subject path**, and
  answers `:unknown` for a document with no subject. `assignable?/3` keeps
  ADR-0003 decision 6's ordering property - the host relation is consulted
  only after the check has already failed, so it can only widen - with the
  floor raised: the record-into-shape coverage step runs before the host is
  asked, per ADR-0011 decision 3's narrowing of decision 6.

  ## The deliberate widening

  This module ships more public functions than the records list, and none of
  them is a second implementation of the relation: `io/2`, `kinds/2`,
  `slot_accepts/3` and `admits?/3` are the structural gate's primitives,
  `produces/4` resolves a declared `produces` including `{:passthrough,
  slot}`, and `seam_reason/4`, `finding_reason/2`, `seam_reasons/3` and
  `target_verdicts/4` read verdicts the deciding functions have already
  reached and label or collect them.

  Defaults, per ADR-0003 decision 5 (restated by ADR-0011 decision 3 as
  `sd-ADR-0001`'s): an absent `io/1` callback, or a module that is not
  loadable, is `%{}`; an absent `:kinds` key is `[:step]`; an absent
  `:slot_accepts` entry for a given slot is `:any`; `:unknown` is permissive
  in both directions.
  """

  alias StatifierBlocks.{Block, Document, Environment, Palette, Shelf}
  alias StatifierDatamodel.Declarations

  @typedoc """
  A type as a declaration spells it. Opaque to this package - never parsed,
  split or normalized here; `StatifierDatamodel.Types.parse/2` reads it
  against the datamodel document, and a list carries its item type.
  """
  @type type_expr :: String.t() | {:list, type_expr()}

  @typedoc ~S(Structural tag. `:step` and `:interrupt_handler` ship here; hosts may mint more.)
  @type kind :: atom()

  @typedoc "What a block declares it produces. See ADR-0003 decision 4."
  @type produces :: type_expr() | :unknown | {:passthrough, Block.slot_name()}

  @typedoc "The return shape of `c:StatifierBlocks.BlockType.io/1`. Every key optional."
  @type io :: %{
          optional(:kinds) => [kind()],
          optional(:consumes) => type_expr() | :unknown,
          optional(:produces) => produces(),
          optional(:slot_accepts) => %{optional(Block.slot_name()) => [kind()] | :any}
        }

  @typedoc """
  Caller-supplied, not stored in the document. `StatifierBlocks.Environment`
  reads both keys: `:datamodel` is the datamodel document the type
  declarations come from, and `:entry_type` seeds the subject path.
  """
  @type context :: Environment.context()

  @typedoc "A position, as ADR-0001 decision 5 defines one."
  @type target :: {Block.id(), Block.slot_name(), non_neg_integer()}

  @typedoc """
  ADR-0003 decision 8's vocabulary, with the one member ADR-0011 decision 8
  adds: a `:type_mismatch` carries the **datamodel path** the read was
  checked at, last. It is added rather than left to be re-derived because a
  block may carry several read signatures on several paths, so a message
  saying which two types disagreed without saying where is one an author
  cannot act on. `:kind_not_admitted` gains none - a structural refusal is
  about a slot and has no path to name.
  """
  @type finding ::
          {:kind_not_admitted, Block.id(), Block.id(), Block.slot_name(), [kind()],
           [kind()] | :any}
          | {:type_mismatch, Block.id(), Block.id() | :slot_entry, type_expr() | :unknown,
             type_expr() | :unknown, String.t()}

  @typedoc """
  Why a read came out the way it did (the 2026-08-29 amendment to ADR-0003
  decision 8, with the arm ADR-0011 decision 8 adds). A reason **explains a
  verdict; it never changes one** - see `seam_reason/4`.

    * `:both_untyped` - neither side declared a type, so the read was
      admitted without checking anything.
    * `:source_untyped` - the environment holds `:unknown` there and the read
      declared a type. Admitted, unchecked.
    * `:target_untyped` - the read declared `:unknown` and the environment
      holds a type. Admitted, unchecked.
    * `{:shape_not_satisfied, missing}` - the environment holds a record at
      the path, the read expects a shape, and the record does not cover the
      shape's required set. `missing` names the required fields it does not
      cover, in the shape's own field order, so a message can say which are
      absent without re-deriving them.
    * `:not_assignable` - refused: both sides typed, identity failed,
      coverage did not apply or did not hold, and the palette's relation did
      not widen. Nothing names a block to go and look at.
    * `{:fixable_by, block_id}` - the same refusal, where a block's write
      signature is what put the offending type at the path: `block_id` is the
      declaration an author would change.
  """
  @type reason ::
          :source_untyped
          | :target_untyped
          | :both_untyped
          | {:shape_not_satisfied, [String.t()]}
          | :not_assignable
          | {:fixable_by, Block.id()}

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
  May a value the environment holds as `held` be read where `expected` is
  required?

  ADR-0003 decision 6's ordered relation as ADR-0011 decision 3 narrows it.
  The order is the contract:

    1. `StatifierDatamodel.Types.satisfies/3` - either side unknown, then
       identity, then a record covering a shape's required set;
    2. otherwise, and only otherwise, `palette.assignability`'s
       `assignable?/2`;
    3. a palette with no relation, or a module that is not loadable or does
       not export the callback, answers `false` - the floor a host cannot
       lower.

  Reflexivity holds regardless of the host, because step 1 decides identity
  before step 2 is reached, so the host callback can only widen the relation
  and never narrow it. The floor is **higher** than ADR-0003 left it: a
  record read as a shape it covers is admitted before the host is asked, so a
  host that was widening records into shapes by hand can delete that half of
  its module.

  `declarations` is `StatifierDatamodel.Declarations.from_document/1`'s index
  over the datamodel document's `types` key. With none - which is what every
  caller that has no datamodel to hand passes - the check reduces to unknown
  and identity, which is exactly what it decided before there were
  declarations to read.
  """
  @spec assignable?(Palette.t(), type_expr() | :unknown, type_expr() | :unknown, Declarations.t()) ::
          boolean()
  def assignable?(%Palette{} = palette, held, expected, declarations \\ %{}) do
    case Environment.satisfies(declarations, held, expected) do
      satisfied when satisfied in [:unknown, :identical, :covers] -> true
      _not_satisfied -> host_widens?(palette, held, expected)
    end
  end

  # Decision 6's steps 3 and 4, which ADR-0011 decision 3 moves to last. A
  # `module` that is not loadable, or does not export `assignable?/2`, yields
  # `false` rather than raising, so a misconfigured palette degrades to the
  # floor instead of turning a validation pass into an exception.
  @spec host_widens?(Palette.t(), term(), term()) :: boolean()
  defp host_widens?(%Palette{assignability: nil}, _held, _expected), do: false

  defp host_widens?(%Palette{assignability: module}, held, expected) do
    if Code.ensure_loaded?(module) and function_exported?(module, :assignable?, 2) do
      module.assignable?(held, expected)
    else
      false
    end
  end

  @doc """
  Why the read of `expected` against a `held` type came out the way it did.

  `producing_ref` is the block whose write signature put `held` at the path,
  exactly as ADR-0011 decision 8's `:type_mismatch` tuple names it, or
  `:slot_entry` when the seed - or a merge with no single writer to name - is
  what the read disagrees with.

  `nil` means **there is nothing to explain**: both sides are typed and the
  read passed, by identity, by coverage, or because the palette's relation
  widened it. Every other outcome names itself. The classification is total
  and follows the read check's own order:

    1. both sides `:unknown` -> `:both_untyped`;
    2. `held` `:unknown` -> `:source_untyped`;
    3. `expected` `:unknown` -> `:target_untyped`;
    4. satisfied, or widened by the host -> `nil`;
    5. a record that does not cover the shape -> `{:shape_not_satisfied,
       missing}`;
    6. `producing_ref` is a block id -> `{:fixable_by, producing_ref}`;
    7. otherwise -> `:not_assignable`.

  **This function decides nothing.** It reads a verdict `assignable?/4` has
  already reached and labels it; nothing in this package branches a verdict
  on what it returns, so the reason vocabulary stays strictly explanatory.
  The first three arms sit on reads the permissive default *admitted*, and
  adding them cannot refuse anything.

  The two ADR-0003 refusing arms still differ only in whether the author has
  somewhere to go, and under ADR-0011 that block is found by name rather than
  by adjacency: it is the block whose write signature put the type at the
  path, which is a more useful answer than the sibling ADR-0003 could name.

  Structural refusals carry no reason from this vocabulary.
  `{:kind_not_admitted, ...}` already names both kind sets in the finding
  itself, so `finding_reason/2` answers `nil` for it rather than duplicating
  it here.
  """
  @spec seam_reason(
          Palette.t(),
          type_expr() | :unknown,
          type_expr() | :unknown,
          Block.id() | :slot_entry,
          Declarations.t()
        ) :: reason() | nil
  def seam_reason(%Palette{} = palette, held, expected, producing_ref, declarations \\ %{}) do
    case {Environment.type_of(declarations, held), Environment.type_of(declarations, expected)} do
      {:unknown, :unknown} -> :both_untyped
      {:unknown, _typed} -> :source_untyped
      {_typed, :unknown} -> :target_untyped
      _both_typed -> refusal_reason(palette, held, expected, producing_ref, declarations)
    end
  end

  @spec refusal_reason(
          Palette.t(),
          term(),
          term(),
          Block.id() | :slot_entry,
          Declarations.t()
        ) :: reason() | nil
  defp refusal_reason(palette, held, expected, producing_ref, declarations) do
    case Environment.satisfies(declarations, held, expected) do
      satisfied when satisfied in [:unknown, :identical, :covers] ->
        nil

      outcome ->
        if host_widens?(palette, held, expected) do
          nil
        else
          refused(outcome, producing_ref)
        end
    end
  end

  @spec refused({:missing, [String.t()]} | :not_assignable, Block.id() | :slot_entry) :: reason()
  defp refused({:missing, names}, _producing_ref), do: {:shape_not_satisfied, names}
  defp refused(:not_assignable, :slot_entry), do: :not_assignable
  defp refused(:not_assignable, producing_ref), do: {:fixable_by, producing_ref}

  @doc """
  The reason for one finding, derived rather than stored.

  A `:type_mismatch` carries its producing ref, the held type, the expected
  type and the path already, so its reason is `seam_reason/5` applied to what
  the tuple holds. A reason kept *in* the finding would be a second copy of a
  verdict the tuple plus the palette already determine, free to disagree with
  it; derived, it cannot.

  `:kind_not_admitted` answers `nil`: the structural gate's reason is its own
  finding code, and this vocabulary is the data-flow gate's.

  A caller with no datamodel document to hand gets the classification the
  declarations-free check reaches, which is the one this package reached
  before there were declarations at all.
  """
  @spec finding_reason(Palette.t(), finding(), Declarations.t()) :: reason() | nil
  def finding_reason(palette, finding, declarations \\ %{})

  def finding_reason(
        %Palette{},
        {:kind_not_admitted, _id, _parent, _slot, _kinds, _accepts},
        _declarations
      ),
      do: nil

  def finding_reason(
        %Palette{} = palette,
        {:type_mismatch, _id, ref, held, expected, _path},
        declarations
      ),
      do: seam_reason(palette, held, expected, ref, declarations)

  @doc """
  Every read in `document` that has something to say about itself, in
  `Document.blocks/1`'s pre-order: `{reading_block_id, producing_ref,
  reason}`.

  This is the queryable form of the cost ADR-0003's consequences state in
  prose - "a partially typed palette permits what a fully typed one would
  catch". The three untyped arms name exactly those reads, and they are the
  reason this vocabulary is not merely a refusal vocabulary: a host auditing
  its own palette's coverage asks here, gets back the reads that passed
  without being checked, and declares the signatures that produced them.

  A block declaring no read at all still contributes a row, against the
  environment's type at the subject path - the block was reached without
  saying anything about what it needs, which is precisely the coverage gap
  this function exists to surface.

  It changes no verdict and is not part of validation. Reads with nothing to
  explain (typed on both sides and passing) are omitted rather than listed
  with a `nil`.
  """
  @spec seam_reasons(Palette.t(), Document.t(), context()) ::
          [{Block.id(), Block.id() | :slot_entry, reason()}]
  def seam_reasons(%Palette{} = palette, %Document{} = document, ctx) do
    declarations = Environment.declarations(ctx)

    for block <- Document.blocks(document),
        {:ok, [_first | _rest] = path} <- [Document.fetch_path(document, block.id)],
        env = Environment.annotated(palette, document, List.last(path), ctx),
        {_key, read_path, expected} <- reads_or_silence(palette, document, block),
        {held, ref} = held_at(env, read_path),
        reason = seam_reason(palette, held, expected, ref, declarations),
        reason != nil do
      {block.id, ref, reason}
    end
  end

  @doc """
  `block`'s declared `produces`, resolved: a type expression resolves to
  itself; `:unknown` resolves to `:unknown`; `{:passthrough, slot}` resolves
  to the resolved `produces` of the last block in `slot`, or, when `slot` is
  empty (or is not a slot `block` declares), `block`'s own inbound type.

  A block that fails `Palette.resolve/2` contributes `:unknown` rather than a
  finding (ADR-0003 decision 5's degradation rule).

  Under ADR-0011 nothing in the data-flow gate consults this: a passthrough
  container passes types through by carrying its slot's own writes out
  through the merge, which is the environment doing it rather than a
  declaration claiming it. It is kept because it reads a declaration a
  palette may still carry, and reading a declaration is not the same as
  deciding with it.

  ### Why this terminates

  Every recursive step lands at a strictly earlier position in the document's
  pre-order than the position that made the original call. Resolving
  `{:passthrough, slot}` on block `B` either descends to the last child of
  `B`'s own `slot` - later than `B`, but still strictly before whatever
  position asked for `B`'s `produces`, since that position comes after `B`
  and every descendant of `B` is ordered before `B`'s next sibling - or,
  when the slot is empty, falls back to `B`'s own inbound type, which is
  `B`'s previous sibling or, at index 0, `B`'s parent. Pre-order rank over a
  finite tree is a well-founded measure with no infinite descending chain, so
  this cannot cycle even for a tree of nothing but empty passthrough
  sequences.
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
  # `block` itself occupies, or the seed's subject type when `block` is the
  # root.
  @spec own_inbound_type(Palette.t(), Document.t(), Block.t(), context()) ::
          type_expr() | :unknown
  defp own_inbound_type(palette, document, block, ctx) do
    case Document.fetch_path(document, block.id) do
      {:ok, []} -> subject_seed(palette, document, ctx)
      {:ok, path} -> inbound_type(palette, document, List.last(path), ctx)
      :error -> :unknown
    end
  end

  @spec subject_seed(Palette.t(), Document.t(), context()) :: type_expr() | :unknown
  defp subject_seed(palette, document, ctx) do
    case Environment.subject_path(palette, document) do
      nil -> :unknown
      path -> palette |> Environment.seed(document, ctx) |> Map.get(path, :unknown)
    end
  end

  @doc """
  The type flowing into `target`: the environment's type at the document's
  **subject path**, at that position (ADR-0011 decisions 1 and 6).

  ADR-0003 decision 4 computed this by walking to the previous sibling's
  resolved `produces`, and ADR-0011 replaces the seam rather than the
  question. A document with no subject path - no entry block, or an entry
  block whose palette entry declares no `subject:` - has nothing flowing into
  any position and answers `:unknown` everywhere, which is the permissive
  default an untyped palette has always got.

  Total: a `parent_id` no block in `document` carries, or an `index` past the
  end of the slot's children, resolves to `:unknown` rather than raising.

  Inside a `core.drafts` shelf the answer is `:unknown` at every index.
  ADR-0003's amendment of 2026-08-31, section A2, is why, and ADR-0011
  decision 1 carries it forward in its own vocabulary: the walk does not
  enter the shelf, and each parked fragment is walked from an **empty**
  environment, so a fragment reads nothing as known because nothing put it
  there. The walk *inside* each fragment is untouched - a parked fragment is
  a subtree whose own writes and reads are real, and they are checked exactly
  as they would be anywhere else.
  """
  @spec inbound_type(Palette.t(), Document.t(), target(), context()) :: type_expr() | :unknown
  def inbound_type(%Palette{} = palette, %Document{} = document, target, ctx) do
    case Environment.subject_path(palette, document) do
      nil -> :unknown
      path -> palette |> Environment.at(document, target, ctx) |> Map.get(path, :unknown)
    end
  end

  @doc """
  ADR-0003 decision 7's one decision function: kind admission for
  `candidate` at `target`, plus the reads whose verdict a placement at
  `target` can change.

  `candidate` not yet in `document` (`Document.fetch_path/2` returns
  `:error`) is an **insert**: `candidate`'s own reads against the environment
  at `target`, and the reads of whatever block currently sits at `target`'s
  index against that environment with `candidate`'s writes applied (nothing
  to check when the slot ends there).

  `candidate` already in `document` is a **move**: the same two, plus what it
  vacates - at its current position `{p, s, i}`, removing it makes `i - 1`
  and `i + 1` adjacent, so the block at `i + 1` is checked against the
  environment as it stood at `i`, which is the environment without
  `candidate`'s writes (nothing to check when the slot has no `i + 1`).

  Findings are decision 8's vocabulary verbatim, in this order when more than
  one applies: kind admission first, then the reads at the insertion point,
  then the vacated ones. A block carrying several read signatures contributes
  one finding per unsatisfied read, each naming its own path, because the
  signatures are independent (ADR-0011 decision 2). `:ok` when the list is
  empty.

  Degradation, per decision 5: a block that fails `Palette.resolve/2` - the
  candidate, the parent, or any block involved - contributes the permissive
  default rather than a finding.
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
    declarations = Environment.declarations(ctx)
    env = Environment.annotated(palette, document, target, ctx)

    kind_findings =
      case kind_admission_finding(palette, document, parent_id, slot, candidate) do
        nil -> []
        finding -> [finding]
      end

    findings =
      kind_findings ++
        read_findings(palette, document, env, candidate, declarations) ++
        downstream_findings(palette, document, target, candidate, env, declarations) ++
        vacated_findings(palette, document, candidate, ctx, declarations)

    case findings do
      [] -> :ok
      findings -> {:error, findings}
    end
  end

  # One finding per unsatisfied read `block` declares, checked against `env`.
  # A path the environment does not hold is `:unknown` and so satisfied: that
  # is not a contradiction anybody stated, and it stays ADR-0005 clause 11e's
  # `:info` advisory, produced by the pass that owns the declared-path
  # question rather than here (ADR-0011 decision 5).
  @spec read_findings(
          Palette.t(),
          Document.t(),
          Environment.annotated(),
          Block.t(),
          Declarations.t()
        ) :: [finding()]
  defp read_findings(palette, document, env, %Block{} = block, declarations) do
    for {_key, path, expected} <- Environment.read_signatures(palette, document, block),
        {held, ref} = held_at(env, path),
        not assignable?(palette, held, expected, declarations) do
      {:type_mismatch, block.id, ref, held, expected, path}
    end
  end

  @spec held_at(Environment.annotated(), String.t() | nil) ::
          {type_expr() | :unknown, Block.id() | :slot_entry}
  defp held_at(env, path), do: Map.get(env, path, {:unknown, :slot_entry})

  # A block's declared reads, or - when it declares none - the one silent row
  # `seam_reasons/3` reports a coverage gap with.
  @spec reads_or_silence(Palette.t(), Document.t(), Block.t()) :: [Environment.signature()]
  defp reads_or_silence(palette, document, block) do
    case Environment.read_signatures(palette, document, block) do
      [] -> [{:consumes, Environment.subject_path(palette, document), :unknown}]
      signatures -> signatures
    end
  end

  @spec downstream_findings(
          Palette.t(),
          Document.t(),
          target(),
          Block.t(),
          Environment.annotated(),
          Declarations.t()
        ) :: [finding()]
  defp downstream_findings(
         palette,
         document,
         {parent_id, slot, index},
         candidate,
         env,
         declarations
       ) do
    with parent when not is_nil(parent) <- find_block(document, parent_id),
         downstream when not is_nil(downstream) <-
           Enum.at(Map.get(parent.slots, slot, []), index) do
      after_candidate = with_writes(palette, document, candidate, env)
      read_findings(palette, document, after_candidate, downstream, declarations)
    else
      nil -> []
    end
  end

  # `env` with `block`'s own write signatures applied, which is what the
  # block after it would see. The candidate's slots are not walked: a
  # placement question is about the block being placed, and what its subtree
  # writes is `validate/3`'s business once the document holds it.
  @spec with_writes(Palette.t(), Document.t(), Block.t(), Environment.annotated()) ::
          Environment.annotated()
  defp with_writes(palette, document, %Block{} = block, env) do
    palette
    |> Environment.write_signatures(document, block)
    |> Enum.reduce(env, fn {_key, path, type}, acc -> Map.put(acc, path, {type, block.id}) end)
  end

  # The reads a move vacates: nothing when `candidate` is not already in
  # `document` (an insert has nothing to vacate), nothing when `candidate` is
  # the root (it occupies no slot), and nothing when the slot has no block
  # after `candidate`'s current position. Otherwise the block after it, read
  # against the environment as it stood at `candidate`'s own position -
  # which is the environment without `candidate`'s writes, since the walk
  # applies a block's writes only on the way out of it.
  @spec vacated_findings(Palette.t(), Document.t(), Block.t(), context(), Declarations.t()) ::
          [finding()]
  defp vacated_findings(palette, document, %Block{} = candidate, ctx, declarations) do
    with {:ok, [_first | _rest] = path} <- Document.fetch_path(document, candidate.id),
         {parent_id, slot, index} = target <- List.last(path),
         parent when not is_nil(parent) <- find_block(document, parent_id),
         after_block when not is_nil(after_block) <-
           Enum.at(Map.get(parent.slots, slot, []), index + 1) do
      env = Environment.annotated(palette, document, target, ctx)
      read_findings(palette, document, env, after_block, declarations)
    else
      _nothing_vacated -> []
    end
  end

  # `{module, config}` for `block` through `palette`, or `{nil, %{}}` when
  # `Palette.resolve/2` fails - the same permissive shape `io/2` already
  # gives a module that is not loadable.
  @spec resolve_module_config(Palette.t(), Block.t()) :: {module() | nil, Block.config()}
  defp resolve_module_config(palette, block) do
    case Palette.resolve(palette, block) do
      {:ok, module, resolved} -> {module, resolved.config}
      {:error, _reason} -> {nil, %{}}
    end
  end

  # `parent_id`'s `{module, config}`, or `{nil, %{}}` when no block in
  # `document` carries it (a permissive default: `admits?/3` then sees
  # `:any`).
  @spec resolve_parent(Palette.t(), Document.t(), Block.id()) :: {module() | nil, Block.config()}
  defp resolve_parent(palette, document, parent_id) do
    case find_block(document, parent_id) do
      nil -> {nil, %{}}
      parent -> resolve_module_config(palette, parent)
    end
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

    if shelf_at_root_body?(document, parent_id, slot, candidate) or
         admits?(parent_mc, slot, candidate_mc) do
      nil
    else
      {parent_module, parent_config} = parent_mc
      {candidate_module, candidate_config} = candidate_mc
      accepts = slot_accepts(parent_module, parent_config, slot)
      candidate_kinds = kinds(candidate_module, candidate_config)
      {:kind_not_admitted, candidate.id, parent_id, slot, candidate_kinds, accepts}
    end
  end

  # The one position kinds cannot decide (ADR-0002's amendment of
  # 2026-08-31, section G12a, as ADR-0003's amendment of the same date,
  # section A1, hands it over). The root block declares `slot_accepts`
  # `[:step]` for its `body` like every other container, so decision 3's
  # intersection refuses a `:draft_shelf` there along with everywhere else.
  # G12a says the root's `body` admits one anyway - a constraint on depth,
  # which is a property of the document rather than of either block.
  # `StatifierBlocks.Shelf` owns the rule; this is the one place that
  # consults it, so `check/5`, `valid_targets/4` and `validate/3` all get the
  # same answer.
  @spec shelf_at_root_body?(Document.t(), Block.id(), Block.slot_name(), Block.t()) :: boolean()
  defp shelf_at_root_body?(document, parent_id, slot, candidate),
    do: Shelf.shelf?(candidate) and Shelf.root_body?(document, parent_id, slot)

  # O(n) per lookup over `Document.blocks/1` - the right first
  # implementation (ADR-0003's design notes): it needs no new function on
  # `Document`, whose contract belongs to another bead.
  @spec find_block(Document.t(), Block.id()) :: Block.t() | nil
  defp find_block(document, id), do: Enum.find(Document.blocks(document), &(&1.id == id))

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
  of positions rather than a refusal.
  """
  @spec valid_targets(Palette.t(), Document.t(), Block.t(), context()) :: [target()]
  def valid_targets(%Palette{} = palette, %Document{} = document, %Block{} = candidate, ctx) do
    for {target, :ok} <- target_verdicts(palette, document, candidate, ctx), do: target
  end

  @doc """
  Every position `valid_targets/4` enumerates, each paired with `check/5`'s
  full verdict rather than filtered down to the accepting ones.

  `valid_targets/4` is defined as this function keeping the `:ok` rows, so
  there is one enumeration and one decision, not two. It is exposed for the
  same reason the moduledoc's other widenings are: a caller that has to say
  *why* a position was refused - `StatifierBlocks.Edit.Targets`, which
  projects positions to slots and needs a reason for a slot it darkens -
  must not re-derive the position set, because a second enumeration is a
  second answer waiting to drift from this one.

  Same order and the same determinism guarantee `valid_targets/4`
  documents.
  """
  @spec target_verdicts(Palette.t(), Document.t(), Block.t(), context()) ::
          [{target(), :ok | {:error, [finding()]}}]
  def target_verdicts(%Palette{} = palette, %Document{} = document, %Block{} = candidate, ctx) do
    for block <- Document.blocks(document),
        {module, config} = resolve_module_config(palette, block),
        module != nil,
        {slot, _arity, _label} <- module.slots(config),
        index <- 0..length(Map.get(block.slots, slot, [])) do
      target = {block.id, slot, index}
      {target, check(palette, document, target, candidate, ctx)}
    end
  end

  @doc """
  Every finding in `document`, per ADR-0003's `validate/3`: every read
  already present in the document, checked with the same rules `check/5`
  checks one with - the whole-document counterpart to `check/5`'s
  single-position query.

  Walking every block in `Document.blocks/1` other than the root (which
  occupies no slot) and checking its own reads against the environment at its
  position visits every read in the document exactly once.

  This is deliberately **not** `check/5` called with a block already sitting
  at its own current position as the candidate: `check/5`'s downstream and
  vacated reads are defined relative to a `target` the candidate is being
  placed at or removed from, and a block that already occupies `target`
  makes both of those check the document as though the block were somewhere
  it is not. `validate/3` reaches the same two checks `check/5` runs for kind
  admission and the block's own reads directly.

  `:ok` when the document has no findings; otherwise `{:error, findings}`
  with every block's findings concatenated, in `Document.blocks/1`'s
  pre-order.
  """
  @spec validate(Palette.t(), Document.t(), context()) :: :ok | {:error, [finding()]}
  def validate(%Palette{} = palette, %Document{} = document, ctx) do
    declarations = Environment.declarations(ctx)

    findings =
      Enum.flat_map(Document.blocks(document), fn block ->
        block_findings(palette, document, block, ctx, declarations)
      end)

    case findings do
      [] -> :ok
      findings -> {:error, findings}
    end
  end

  @spec block_findings(Palette.t(), Document.t(), Block.t(), context(), Declarations.t()) ::
          [finding()]
  defp block_findings(palette, document, %Block{} = block, ctx, declarations) do
    case Document.fetch_path(document, block.id) do
      {:ok, [_first | _rest] = path} ->
        {parent_id, slot, _index} = target = List.last(path)
        env = Environment.annotated(palette, document, target, ctx)

        kind =
          case kind_admission_finding(palette, document, parent_id, slot, block) do
            nil -> []
            finding -> [finding]
          end

        kind ++ read_findings(palette, document, env, block, declarations)

      _root_or_missing ->
        []
    end
  end
end
