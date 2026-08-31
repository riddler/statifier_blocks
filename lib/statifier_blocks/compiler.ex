defmodule StatifierBlocks.Compiler do
  @moduledoc """
  The one-way compile: a block document plus a palette in, one artifact out
  (ADR-0004 decisions 1-4, 6-7).

  `compile/3` is a **total function of `{document, palette}`**. No process
  state, no global registry, no IO, no clock - the same purity ADR-0002
  decision 4 imposes on the callbacks, imposed on the pipeline that calls
  them. It returns `{:ok, %StatifierBlocks.Compiled{}}` or
  `{:error, [%StatifierBlocks.Compiler.Finding{}]}`, never raises, and never
  partially succeeds.

  ## The pipeline

  Each stage runs over the whole document; the first stage that produces
  errors stops the compile and reports every error it found. Stopping
  rather than accumulating across stages is deliberate - see
  `StatifierBlocks.Compiler.Finding`.

  1. **Document** - `StatifierBlocks.Document.validate/1`. Structural only;
     no palette is consulted.
  2. **Resolve** - every block through
     `StatifierBlocks.Palette.resolve/2`, which also applies an in-memory
     config migration (ADR-0002 decision 8). Nothing is written back.
  3. **Config** - every block's `validate_config/1`.
  4. **Structure** - `StatifierBlocks.SlotValidation.validate/2` (slot
     arity, `:undeclared_slot`) and `StatifierBlocks.Assignability.validate/3`
     (may this block land in this slot, by kind tag and by data-flow type -
     ADR-0003), reported together.
  5. **Emit** - bottom-up. Each block's `emit/2` is called with its
     children already compiled and summarized, the scope-shaped cancel for
     any delayed send a direct child armed is added to its own state
     (`StatifierBlocks.Compiler.Cancels`), its emission is attributed
     (`StatifierBlocks.Compiler.Attribution`), and its child placeholders
     are spliced with those children's own emissions.
  6. **Chart** - serialize once through
     `StatifierBlocks.Compiler.Serializer`, which writes the bytes and the
     provenance map together, then run those bytes through
     `Statifier.compile/2` and map every finding back through provenance
     (`StatifierBlocks.Compiler.Chart`).

  Findings from every stage are reported in document order over blocks -
  `StatifierBlocks.Document.blocks/1`'s pre-order - which is how upstream's
  own document-order sort survives the trip.

  ### The Structure stage is whole

  Decision 10's table names three things in this stage: slot **arity**,
  `:undeclared_slot`, and assignability. All three run here, and their
  findings are reported together rather than either short-circuiting the
  other: an undeclared slot key does not induce an assignability finding
  (a slot with no declaration gets `slot_accepts` `:any`, which admits
  everything), and an arity violation is a count, which no assignability
  rule reads. Neither is a consequence of the other - they are siblings,
  which is decision 10's own rule for what one stage reports - so
  `StatifierBlocks.SlotValidation.validate/2` and
  `StatifierBlocks.Assignability.validate/3` are both always run and their
  findings concatenated. Before this, the pipeline never visited a slot
  `slots/1` did not declare, so an undeclared slot's blocks were absent
  from the emission rather than misplaced in it - a silent drop.

  ## Options

    * `:known_invoke_types` - decision 8's opt-in lint. A set (or list) of
      invoke types the caller believes will be registered; every emitted
      type absent from it becomes a **warning**, never an error. See
      `StatifierBlocks.Compiler.InvokeTypes`.
    * `:entry_type` - ADR-0003 decision 4's caller-supplied context: the
      type flowing into the document's root. Defaults to absent, which
      `StatifierBlocks.Assignability` reads as `:unknown`. ADR-0004's own
      typespec lists only the first option, because it delegated
      assignability wholesale to ADR-0003 (decision 11) without noticing
      that ADR-0003's context is caller-supplied and therefore has to
      arrive through this function. This is that arrival, not a second
      decision about what assignability means.
    * `:datamodel` - the host's declared datamodel, which
      `StatifierBlocks.Compiler.SensitivePaths` reads to refuse a document
      that carries a declared-sensitive path into a position the chart
      evaluates against the datamodel (ADR-0002 decision 7's `sensitive?`
      key and the secrets rule behind it). Absent, or declaring nothing
      sensitive, the check does not run and produces nothing - absence is
      not unknown-ness (ADR-0005 `11f`). See
      `StatifierBlocks.Compiler.SensitivePaths.datamodel/1` for the shapes
      it accepts, and that module for the criterion the refusal applies.
    * `:child_use` - compile this document **for use as a child** of
      another chart (ADR-0004's 2026-08-29 amendment, C1). The emission
      gains one top-level `<final>` per outcome the root block declares,
      reached from `done.outcome.<root state id>.<outcome>` and carrying
      `<donedata><param name="outcome" expr="'<outcome>'"/></donedata>`,
      which is how a child's outcome crosses the invoke boundary: raised
      events are internal to the session that raises them, so the only
      thing a parent observes is the completion event and the data the
      child sent with it (SCXML 3.7 and 5.5). Defaults to `false`, and a
      document compiled without it is byte-identical to what it was before
      the option existed. The parent half is
      `StatifierBlocks.Core.Subchart`.
    * `:terminate` - compile this document **as a root document that
      finishes** (ADR-0004's 2026-08-29 root-termination note). The
      emission gains one top-level `<final>` per outcome the root block
      declares, reached from `done.outcome.<root state id>.<outcome>` and
      carrying **no** `<donedata>`, so the session reaches `:done` when the
      root block completes. Without it a compiled root document never
      terminates: the root block's own outcome finals are children of the
      root compound state, so completing the root block raises
      `done.outcome` internally and the session stays active forever, which
      is what leaves a durable run uncompleted. Defaults to `false`, and a
      document compiled without it is byte-identical to what it was before
      the option existed.

      `:terminate` and `:child_use` are the same emission shaped for two
      different uses, and a document is compiled for one or the other:
      passing both is refused with an `:emit` finding rather than resolved
      silently, because both would put a transition on the same
      `done.outcome` event on the root block's own state and document order
      would quietly decide which top-level `<final>` a run reaches.
    * `:declare` - the **`<data>` roots the host declares for this
      document** (ADR-0004's 2026-08-29 host-declared-roots note): a list
      of `{id, expr}` pairs, in declaration order, where `expr` is either
      an expression written verbatim into the attribute or `nil` for a
      root that reads as `undefined` until something assigns it.

          Compiler.compile(document, palette, declare: [{"targets", nil}, {"parked", "false"}])

      Each pair becomes one `StatifierBlocks.Compiler.DeclaredRoots`
      declaration, prepended to the root block's own children before the
      hoist, so the host's roots lead the single `<datamodel>` in the
      order given and block-declared roots follow in document order. An
      id must be a bare lowercase identifier - `core.invoke`'s
      `assign_to` rule - and an id the option repeats, or an entry that
      is not a well-formed pair, is refused as an Emit-stage finding
      against the root block. An id a *block* also declares is F6's
      `:duplicate_binding` against that block, through the same walk a
      nested loop's collision goes through.

      This is the compile call's declaration surface, and it **leads**:
      the document has a second one, ADR-0001 decision 11's top-level
      `datamodel` key (added 2026-08-31), whose roots follow the host's
      in the single `<datamodel>` - `:declare` roots, then the document's
      own, then block-declared roots, all in document order. A root both
      declare is host-wins: the compile call's declaration is the one
      emitted, the document's is dropped, and the artifact carries a
      **warning** (`:shadowed_document_root`) rather than a refusal, since
      the compile call is what a host controls and the document edit that
      would silence the warning is not the one that fixes anything. No
      block type declares a root of its own - that surface is still
      untaken, ADR-0002's to take. Absent or `[]` emits no `<datamodel>`
      unless the document or a block declares a root, so a document
      compiled without the option is byte-identical to what it was before
      the option existed. Run creation still wins over `expr` (SCXML
      5.3.2) - a run seeded with a value for the id starts from that
      value, which is the engine's behaviour and not this package's.

      See `StatifierBlocks.Compiler.DeclaredRoots`'s "Document-declared
      roots" section for the full precedence rule and for why a document
      root colliding with a *block*-declared root stays F6's
      `:duplicate_binding` error rather than becoming a second kind of
      warning.

  ## Determinism (decision 6)

  > For a fixed `{document canonical bytes, palette, compiler version}`, the
  > generated SCXML is **byte-identical** on every machine and every run,
  > forever.

  All three inputs are real, and `StatifierBlocks.CompilationRecord`
  records all three. What this module contributes to the guarantee is that
  it never iterates a bare map: slots are visited in `slots/1` declaration
  order (ADR-0002 decision 6 made that order meaningful), children in
  document order, and attributes are sorted at construction by
  `StatifierBlocks.Emission.element/3`.

  The guarantee is **not** reversible and must not be read as one. Equal
  output does not imply equal input: a `metadata`-only edit changes the
  document hash and produces identical SCXML, because `metadata` is not
  compiled. A host may use "same triple" to skip a recompile, and may
  **not** use "same SCXML" to conclude the document is unchanged.

  The document's `datamodel` key (ADR-0001 decision 11) is part of the
  document's canonical bytes and therefore of the triple's first input,
  so the guarantee is unweakened by its existence - moving an entry's
  `id` or `expr` moves the document hash and, because those are compiled,
  moves the generated SCXML too. But it is a second instance of the same
  non-reversibility clause above: an entry's `description` is prose, not
  compiled, so two documents differing only in a `description` hash
  differently and still produce byte-identical SCXML.
  """

  alias Statifier.Machine.Identity

  alias StatifierBlocks.{
    Assignability,
    Block,
    BlockType,
    CompilationRecord,
    Compiled,
    Document,
    Emission,
    Palette,
    Provenance,
    SlotValidation
  }

  alias StatifierBlocks.Compiler.{
    Attribution,
    Cancels,
    Chart,
    Context,
    DeclaredRoots,
    Finding,
    InvokeTypes,
    SelfReference,
    SensitivePaths,
    Serializer,
    StateId
  }

  @scxml_ns "http://www.w3.org/2005/07/scxml"

  # The role every child-use final is minted under. It is a role like any
  # other (decision 3), so `unstate_id/1` inverts it and the reserved `o_`
  # namespace stays the outcome finals' alone.
  @child_role_prefix "child_"

  # The role every root-termination final is minted under. Like
  # `@child_role_prefix` it is an ordinary role (decision 3), so
  # `unstate_id/1` inverts it.
  #
  # It is `root_` and not `done_`: `core.parallel` already mints the
  # `done_lane_<name>` role family (this record's `complete: first`
  # amendment, P1), so a `done_<outcome>` root final would share a
  # namespace with it and, for a parallel root declaring an outcome named
  # `lane_<something>`, would mint the same id twice. `root_` collides with
  # no role any block type mints, nor with the reserved `o_` outcome
  # namespace or the child-use family, and it says what it is.
  @root_role_prefix "root_"

  # The provenance role a host-declared `<data>` root carries. Not a role
  # in `StateId`'s sense and deliberately not spellable as one: the
  # leading colon fails `StateId.role?/1`, so this name cannot collide
  # with a role any block mints. See `host_roots/2`.
  @host_role ":declare"

  # The provenance role a document-declared `<data>` root carries
  # (ADR-0001 decision 11). Same reason, same shape as `@host_role`: a
  # leading colon fails `StateId.role?/1`, so this name cannot collide
  # with a role any block mints either. See `document_roots/3`.
  @document_role ":datamodel"

  # Decision 6's third determinism input. It is the package version, and it
  # moves whenever a change to this package moves generated bytes - which,
  # since a Hex release is the only way a host's bytes change, is every
  # release. `compiler_test.exs` asserts it against `mix.exs` so the
  # two cannot drift silently.
  @compiler_version "0.11.0"

  # A resolved block and its resolved children, in `slots/1` declaration
  # order. Built once by the Resolve stage and threaded through the rest, so
  # no later stage re-resolves or re-migrates anything.
  defmodule Resolved do
    @moduledoc false

    @type t :: %__MODULE__{
            block: StatifierBlocks.Block.t(),
            module: module(),
            slots: [{StatifierBlocks.Block.slot_name(), [t()]}]
          }

    @enforce_keys [:block, :module, :slots]
    defstruct [:block, :module, :slots]
  end

  @typedoc """
  `:known_invoke_types` enables decision 8's optional two-registry lint;
  `:entry_type` is ADR-0003 decision 4's caller-supplied context;
  `:datamodel` is the host's declared datamodel, read only by the
  sensitive-path refusal; `:declare` is the `<data>` roots the host
  declares for this document. See the moduledoc.
  """
  @type option ::
          {:known_invoke_types, Enumerable.t()}
          | {:entry_type, Assignability.type_expr() | :unknown}
          | {:datamodel, term()}
          | {:child_use, boolean()}
          | {:terminate, boolean()}
          | {:declare, [DeclaredRoots.declaration()]}

  @doc """
  Compiles `document` against `palette`.

  Total: `{:ok, %StatifierBlocks.Compiled{}}` or
  `{:error, [%StatifierBlocks.Compiler.Finding{}]}`, never a raise and
  never a partial success. Errors come from the first failing stage only
  (decision 10); warnings ride on the artifact when the compile succeeds.
  """
  @spec compile(Document.t(), Palette.t(), [option()]) ::
          {:ok, Compiled.t()} | {:error, [Finding.t()]}
  def compile(%Document{} = document, %Palette{} = palette, opts \\ []) when is_list(opts) do
    with :ok <- document_stage(document),
         {:ok, node} <- resolve_stage(document, palette),
         :ok <- config_stage(node),
         :ok <- structure_stage(document, palette, opts),
         :ok <- chart_use_stage(node, opts),
         {:ok, {emission, emit_warnings}} <- emit_stage(node, document, opts),
         :ok <- self_reference_stage(emission, document.id),
         :ok <- sensitive_stage(emission, opts) do
      chart_stage(document, node, emission, emit_warnings, opts)
    end
    |> in_document_order(document)
  end

  @doc "Decision 6's third determinism input: this package's version."
  @spec compiler_version() :: String.t()
  def compiler_version, do: @compiler_version

  # -- Stage 1: document -----------------------------------------------------

  @spec document_stage(Document.t()) :: :ok | {:error, [Finding.t()]}
  defp document_stage(document) do
    case Document.validate(document) do
      :ok ->
        :ok

      {:error, reason} ->
        {:error,
         [
           Finding.new(
             :document,
             {:invalid_document, reason},
             "the document is not structurally valid: #{inspect(reason)}"
           )
         ]}
    end
  end

  # -- Stage 2: resolve ------------------------------------------------------

  @spec resolve_stage(Document.t(), Palette.t()) :: {:ok, Resolved.t()} | {:error, [Finding.t()]}
  defp resolve_stage(%Document{root: root}, palette) do
    case resolve(palette, root) do
      {:ok, node} -> {:ok, node}
      {:error, findings} -> {:error, findings}
    end
  end

  @spec resolve(Palette.t(), Block.t()) :: {:ok, Resolved.t()} | {:error, [Finding.t()]}
  defp resolve(palette, %Block{} = block) do
    case Palette.resolve(palette, block) do
      {:ok, module, resolved} ->
        resolve_children(palette, module, resolved)

      {:error, reason} ->
        {:error, [resolve_finding(block, reason) | orphan_findings(palette, block)]}
    end
  end

  @spec resolve_children(Palette.t(), module(), Block.t()) ::
          {:ok, Resolved.t()} | {:error, [Finding.t()]}
  defp resolve_children(palette, module, %Block{} = block) do
    {slots, findings} =
      block.config
      |> module.slots()
      |> Enum.reduce({[], []}, fn {name, _arity, _label}, {slots, findings} ->
        {children, child_findings} = resolve_slot(palette, block, name)
        {[{name, children} | slots], findings ++ child_findings}
      end)

    case findings do
      [] -> {:ok, %Resolved{block: block, module: module, slots: Enum.reverse(slots)}}
      findings -> {:error, findings}
    end
  end

  @spec resolve_slot(Palette.t(), Block.t(), Block.slot_name()) :: {[Resolved.t()], [Finding.t()]}
  defp resolve_slot(palette, %Block{slots: slots}, name) do
    slots
    |> Map.get(name, [])
    |> Enum.reduce({[], []}, fn child, {nodes, findings} ->
      case resolve(palette, child) do
        {:ok, node} -> {[node | nodes], findings}
        {:error, child_findings} -> {nodes, findings ++ child_findings}
      end
    end)
    |> then(fn {nodes, findings} -> {Enum.reverse(nodes), findings} end)
  end

  # A block whose own type did not resolve has no `slots/1` to walk, so its
  # children are visited in sorted slot-name order instead. Reporting them
  # too is decision 10's "within a stage every finding is reported": the
  # children's types are siblings of this failure, not consequences of it.
  @spec orphan_findings(Palette.t(), Block.t()) :: [Finding.t()]
  defp orphan_findings(palette, %Block{slots: slots}) do
    slots
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.flat_map(fn {_name, children} -> children end)
    |> Enum.flat_map(&orphan_child_findings(palette, &1))
  end

  @spec orphan_child_findings(Palette.t(), Block.t()) :: [Finding.t()]
  defp orphan_child_findings(palette, child) do
    case resolve(palette, child) do
      {:ok, _node} -> []
      {:error, findings} -> findings
    end
  end

  @spec resolve_finding(Block.t(), term()) :: Finding.t()
  defp resolve_finding(%Block{id: id, type: type}, {:unknown_block_type, _type} = reason) do
    Finding.new(:resolve, reason, ~s(no palette entry for block type "#{type}"), block_id: id)
  end

  defp resolve_finding(%Block{id: id}, {:block_type_too_new, _id, stored} = reason) do
    Finding.new(
      :resolve,
      reason,
      "the block is stored at type version #{stored}, which is newer than this palette entry",
      block_id: id
    )
  end

  defp resolve_finding(%Block{id: id}, {:migration_failed, _id, why} = reason) do
    Finding.new(:resolve, reason, "config migration failed: #{inspect(why)}", block_id: id)
  end

  # -- Stage 3: config -------------------------------------------------------

  @spec config_stage(Resolved.t()) :: :ok | {:error, [Finding.t()]}
  defp config_stage(node) do
    case config_findings(node) do
      [] -> :ok
      findings -> {:error, findings}
    end
  end

  @spec config_findings(Resolved.t()) :: [Finding.t()]
  defp config_findings(%Resolved{block: block, module: module, slots: slots}) do
    own =
      case module.validate_config(block.config) do
        :ok ->
          []

        {:error, findings} ->
          Enum.map(findings, fn {key, message} ->
            Finding.new(:config, {:invalid_config, key}, message,
              block_id: block.id,
              config_key: key
            )
          end)
      end

    own ++
      Enum.flat_map(slots, fn {_name, children} -> Enum.flat_map(children, &config_findings/1) end)
  end

  # -- Stage 4: structure ----------------------------------------------------

  # Slot arity, `:undeclared_slot`, and assignability - decision 10's full
  # table for this stage. Both sources are collected and concatenated
  # rather than either short-circuiting the other: decision 10 says every
  # finding within a stage is reported, because those findings are
  # siblings rather than consequences, and neither of these two is a
  # consequence of the other (see the moduledoc). This stage runs over
  # the *document* rather than the resolved tree because both
  # `SlotValidation.validate/2` and `Assignability.validate/3` are the one
  # implementation the editor and the compiler consult (ADR-0002 decision
  # 6, ADR-0003 decision 6), and the editor has no resolved tree.
  @spec structure_stage(Document.t(), Palette.t(), keyword()) :: :ok | {:error, [Finding.t()]}
  defp structure_stage(document, palette, opts) do
    slot_findings =
      case SlotValidation.validate(palette, document) do
        :ok -> []
        {:error, findings} -> Enum.map(findings, &slot_finding/1)
      end

    assignability_findings =
      case Assignability.validate(palette, document, assignability_context(opts)) do
        :ok -> []
        {:error, findings} -> Enum.map(findings, &structure_finding/1)
      end

    case slot_findings ++ assignability_findings do
      [] -> :ok
      findings -> {:error, findings}
    end
  end

  @spec assignability_context(keyword()) :: Assignability.context()
  defp assignability_context(opts) do
    case Keyword.fetch(opts, :entry_type) do
      {:ok, entry_type} -> %{entry_type: entry_type}
      :error -> %{}
    end
  end

  @spec structure_finding(Assignability.finding()) :: Finding.t()
  defp structure_finding({:kind_not_admitted, id, parent_id, slot, kinds, accepts} = reason) do
    Finding.new(
      :structure,
      reason,
      ~s(a #{inspect(kinds)} block cannot go in #{parent_id}'s "#{slot}" slot, ) <>
        "which admits #{inspect(accepts)}",
      block_id: id
    )
  end

  defp structure_finding({:type_mismatch, id, source, produced, consumed} = reason) do
    Finding.new(
      :structure,
      reason,
      "this block consumes #{inspect(consumed)} but #{inspect(source)} produces " <>
        "#{inspect(produced)}",
      block_id: id
    )
  end

  @spec slot_finding(SlotValidation.finding()) :: Finding.t()
  defp slot_finding({:slot_arity_violated, id, slot, arity, count} = reason) do
    Finding.new(
      :structure,
      reason,
      ~s(the "#{slot}" slot holds #{count} blocks, and this block type declares it ) <>
        arity_phrase(arity),
      block_id: id
    )
  end

  defp slot_finding({:undeclared_slot, id, slot, count} = reason) do
    Finding.new(
      :structure,
      reason,
      ~s(the "#{slot}" slot holds #{count} blocks but this block type declares no such slot, ) <>
        "so they would be dropped",
      block_id: id
    )
  end

  @spec arity_phrase(StatifierBlocks.BlockType.slot_arity()) :: String.t()
  defp arity_phrase(:any), do: "as holding any number"
  defp arity_phrase(:at_least_one), do: "as holding at least one"
  defp arity_phrase(:exactly_one), do: "as holding exactly one"
  defp arity_phrase(:zero_or_one), do: "as optional"

  # -- Stage 5: emit ---------------------------------------------------------

  @spec emit_stage(Resolved.t(), Document.t(), [option()]) ::
          {:ok, {Emission.t(), [Finding.t()]}} | {:error, [Finding.t()]}
  defp emit_stage(node, %Document{id: document_id} = document, opts) do
    with {:ok, host} <- host_roots(node, opts),
         {kept_document, warnings} <- document_roots(node, document, host),
         {:ok, emission} <- emit(node, document_id),
         {:ok, {stripped, roots}} <- hoist(node, prepend(emission, host ++ kept_document)) do
      {:ok, {scxml_element(node, document_id, stripped, roots, opts), warnings}}
    end
  end

  # ADR-0004's 2026-08-29 host-declared-roots note: the `:declare` compile
  # option is the only surface a host has for declaring a `<data>` root of
  # a root document, and it arrives here as `<data>` elements prepended to
  # the root block's own children - so the hoist that already orders,
  # de-duplicates and refuses block-declared roots does all three for the
  # host's without a second mechanism.
  #
  # Attribution: these bytes belong to no block, so decision 5's rule for
  # `<scxml>` and the `<datamodel>` wrapper applies - the **root block**
  # owns them. The role records *which* surface produced them, spelled
  # with the option's own leading colon so `StateId.role?/1` rejects it
  # and no role a block mints from a state id can ever equal it. No
  # `config_key`, because no config field holds the name: decision 9's
  # split then reads a finding against one of these as `:package` rather
  # than as the author's, which is right - no document edit fixes a
  # compile call.
  @spec host_roots(Resolved.t(), [option()]) ::
          {:ok, [Emission.t()]} | {:error, [Finding.t()]}
  defp host_roots(%Resolved{block: %Block{id: root_id}}, opts) do
    case DeclaredRoots.declarations(Keyword.get(opts, :declare)) do
      {:ok, roots} ->
        {:ok, Enum.map(roots, &%{&1 | owner: Provenance.owner(root_id, role: @host_role)})}

      {:error, refusals} ->
        {:error, Enum.map(refusals, &declaration_finding(&1, root_id))}
    end
  end

  @spec declaration_finding(DeclaredRoots.declaration_finding(), Block.id()) :: Finding.t()
  defp declaration_finding({:invalid_declaration, entry}, root_id) do
    Finding.new(
      :emit,
      {:invalid_declaration, entry},
      ~s(the :declare compile option holds #{inspect(entry)}, which is not a {id, expr} pair ) <>
        "whose id is a bare lowercase identifier and whose expr is a non-empty expression " <>
        "or nil",
      block_id: root_id
    )
  end

  defp declaration_finding({:duplicate_declaration, id}, root_id) do
    Finding.new(
      :emit,
      {:duplicate_declaration, id},
      ~s(the :declare compile option declares the root "#{id}" twice; early binding makes a ) <>
        "declared root global, so the second declaration would be the only one that survives",
      block_id: root_id
    )
  end

  # ADR-0001 decision 11: the document's own `datamodel` key is a second
  # declaration surface, and it follows the `:declare` compile option's
  # roots (`host`) rather than leading them - see the moduledoc's
  # `:declare` bullet. A document root the host already declares by the
  # same id is dropped here, before the hoist ever sees it, and turned
  # into one **warning** rather than an F6 refusal: the compile call
  # leads by contract, so a host/document collision is expected and
  # survivable, unlike a block-declared collision the author has no way
  # to see coming.
  #
  # Attribution follows `host_roots/2`'s own reasoning exactly, with its
  # own role: these bytes belong to no block, so the root block owns
  # them, and `@document_role`'s leading colon keeps this surface's
  # provenance distinguishable from both a block-minted role and the
  # host's own `@host_role`.
  @spec document_roots(Resolved.t(), Document.t(), [Emission.t()]) ::
          {[Emission.t()], [Finding.t()]}
  defp document_roots(%Resolved{block: %Block{id: root_id}}, %Document{datamodel: entries}, host) do
    document =
      entries
      |> DeclaredRoots.document_declarations()
      |> Enum.map(&%{&1 | owner: Provenance.owner(root_id, role: @document_role)})

    {kept, shadowed_ids} = DeclaredRoots.shadowed(host, document)

    {kept, Enum.map(shadowed_ids, &shadowed_finding(&1, root_id))}
  end

  @spec shadowed_finding(String.t(), Block.id()) :: Finding.t()
  defp shadowed_finding(id, root_id) do
    Finding.new(
      :emit,
      {:shadowed_document_root, id},
      ~s(the document declares the datamodel root "#{id}", which the :declare compile ) <>
        "option also declares; the compile call leads, so the host's declaration is the " <>
        "one emitted and the document's is dropped",
      block_id: root_id,
      severity: :warning
    )
  end

  # The host's roots lead the root block's own children, which is what
  # puts them first in the hoisted `<datamodel>` and what puts every
  # block-declared root inside their scope for F6.
  @spec prepend(Emission.t(), [Emission.t()]) :: Emission.t()
  defp prepend(emission, []), do: emission

  defp prepend(%Emission{children: children} = emission, roots),
    do: %{emission | children: roots ++ children}

  # ADR-0004's foreach amendment, F2/F3: a block type declares a `<data>`
  # root among its own state's children and the compiler lifts every one
  # of them to the top of the document, because early binding means a root
  # has to be declared before any state is entered. The refusal F6 records
  # is the same walk's other product; see
  # `StatifierBlocks.Compiler.DeclaredRoots`.
  @spec hoist(Resolved.t(), Emission.t()) ::
          {:ok, {Emission.t(), [Emission.t()]}} | {:error, [Finding.t()]}
  defp hoist(%Resolved{block: %Block{id: root_id}}, emission) do
    case DeclaredRoots.hoist(emission) do
      {:ok, _stripped_and_roots} = ok -> ok
      {:error, collisions} -> {:error, Enum.map(collisions, &duplicate_binding(&1, root_id))}
    end
  end

  @spec duplicate_binding(DeclaredRoots.finding(), Block.id()) :: Finding.t()
  defp duplicate_binding({:duplicate_binding, block_id, config_key, name}, root_id) do
    owner = block_id || root_id

    Finding.new(
      :emit,
      {:duplicate_binding, owner, name},
      ~s(binds the name "#{name}", which a block it sits inside already declares as a ) <>
        "datamodel root; early binding makes both of them global, so this binding would " <>
        "overwrite the enclosing one",
      block_id: owner,
      config_key: config_key
    )
  end

  @spec emit(Resolved.t(), Document.id()) :: {:ok, Emission.t()} | {:error, [Finding.t()]}
  defp emit(%Resolved{block: block, module: module, slots: slots}, document_id) do
    with {:ok, compiled_slots} <- emit_slots(slots, document_id),
         :ok <- validate_outcomes(block, module) do
      context = Context.new(block.id, document_id, summaries(slots))

      case module.emit(block, context) do
        {:ok, %Emission{} = emission} ->
          emission
          |> Cancels.arm(children(compiled_slots))
          |> attribute(block, compiled_slots)

        {:error, reason} ->
          {:error, emit_findings(block, reason)}
      end
    end
  end

  # A block type's own outcome declarations, checked on **this** node's
  # pass and reported against **this** block - the one whose type
  # misbehaved, never its parent (ADR-0004's outcome amendment, 2f). It
  # runs before `emit/2` so a type that cannot mint its own outcome ids
  # never gets asked to emit with them, and it is why `summaries/1` below
  # can build a child's outcome entries without re-checking them: by the
  # time a parent sees a child in a summary, the child's own pass has
  # already refused a malformed or duplicated name.
  @spec validate_outcomes(Block.t(), module()) :: :ok | {:error, [Finding.t()]}
  defp validate_outcomes(block, module) do
    module
    |> BlockType.outcome_names(block.config)
    |> Enum.reduce_while({:ok, MapSet.new()}, fn name, {:ok, seen} ->
      cond do
        not StateId.role?(name) -> {:halt, {:invalid, name}}
        MapSet.member?(seen, name) -> {:halt, {:invalid, name}}
        true -> {:cont, {:ok, MapSet.put(seen, name)}}
      end
    end)
    |> case do
      {:ok, _seen} -> :ok
      {:invalid, name} -> {:error, emit_findings(block, {:invalid_outcome, block.id, name})}
    end
  end

  # Attribution runs on the block's own emission, before its children are
  # spliced in: each block stamps only what it wrote, and a child's
  # subtree arrives already stamped from its own pass. That is what makes
  # the provenance map total by construction (ADR-0004 decision 5) rather
  # than by a later sweep that would have to guess who emitted what.
  @spec attribute(Emission.t(), Block.t(), [{Block.slot_name(), [{Block.id(), Emission.t()}]}]) ::
          {:ok, Emission.t()} | {:error, [Finding.t()]}
  defp attribute(emission, block, compiled_slots) do
    known = MapSet.new([block.id | Enum.map(children(compiled_slots), &elem(&1, 0))])

    case Attribution.stamp(emission, block.id, known) do
      {:ok, stamped} ->
        splice(stamped, compiled_slots, block)

      {:error, {:unknown_attribution, other} = reason} ->
        {:error,
         [
           Finding.new(
             :emit,
             reason,
             "attributed an element to #{other}, which is not this block or one of its children",
             block_id: block.id
           )
         ]}
    end
  end

  @spec emit_slots([{Block.slot_name(), [Resolved.t()]}], Document.id()) ::
          {:ok, [{Block.slot_name(), [{Block.id(), Emission.t()}]}]} | {:error, [Finding.t()]}
  defp emit_slots(slots, document_id) do
    Enum.reduce_while(slots, {:ok, []}, fn {name, children}, {:ok, acc} ->
      case emit_children(children, document_id) do
        {:ok, compiled} -> {:cont, {:ok, [{name, compiled} | acc]}}
        {:error, findings} -> {:halt, {:error, findings}}
      end
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      {:error, findings} -> {:error, findings}
    end
  end

  @spec emit_children([Resolved.t()], Document.id()) ::
          {:ok, [{Block.id(), Emission.t()}]} | {:error, [Finding.t()]}
  defp emit_children(children, document_id) do
    Enum.reduce_while(children, {:ok, []}, fn %Resolved{block: block} = child, {:ok, acc} ->
      case emit(child, document_id) do
        {:ok, emission} -> {:cont, {:ok, [{block.id, emission} | acc]}}
        {:error, findings} -> {:halt, {:error, findings}}
      end
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      {:error, findings} -> {:error, findings}
    end
  end

  # Built from the **resolved** slots rather than the compiled ones: a
  # summary now carries the child's declared outcomes (ADR-0004's outcome
  # amendment, 2e), and a compiled slot holds only `{block_id, emission}`
  # pairs, which cannot say which module declared what. The resolved slots
  # are the same slots in the same order carrying the same children, so
  # the walk is unchanged; what is added is the module and config each
  # child was already resolved with.
  @spec summaries([{Block.slot_name(), [Resolved.t()]}]) ::
          %{optional(Block.slot_name()) => [Context.child_summary()]}
  defp summaries(slots) do
    Map.new(slots, fn {name, children} -> {name, Enum.map(children, &summary/1)} end)
  end

  @spec summary(Resolved.t()) :: Context.child_summary()
  defp summary(%Resolved{block: block, module: module}) do
    Context.summary(block.id, BlockType.outcome_names(module, block.config))
  end

  # Replaces every `{:child, block_id}` placeholder with that child's own
  # emission. A placeholder naming a block that is not a child of this one in
  # a declared slot is a bug in the block type, reported against the parent
  # rather than written into identity-bearing bytes as a hole.
  @spec splice(Emission.t(), [{Block.slot_name(), [{Block.id(), Emission.t()}]}], Block.t()) ::
          {:ok, Emission.t()} | {:error, [Finding.t()]}
  defp splice(emission, compiled_slots, block) do
    available = Map.new(children(compiled_slots))

    case substitute(emission, available) do
      {:ok, spliced} ->
        {:ok, spliced}

      {:error, block_id} ->
        {:error,
         [
           Finding.new(
             :emit,
             {:unspliced_child, block_id},
             "emitted a child placeholder for #{block_id}, which is not a child of this block",
             block_id: block.id
           )
         ]}
    end
  end

  @spec children([{Block.slot_name(), [{Block.id(), Emission.t()}]}]) ::
          [{Block.id(), Emission.t()}]
  defp children(compiled_slots) do
    Enum.flat_map(compiled_slots, fn {_name, children} -> children end)
  end

  @spec substitute(Emission.node_t(), %{optional(Block.id()) => Emission.t()}) ::
          {:ok, Emission.t()} | {:error, Block.id()}
  defp substitute(%Emission{children: children} = emission, available) do
    children
    |> Enum.reduce_while({:ok, []}, fn child, {:ok, acc} ->
      case substitute(child, available) do
        {:ok, substituted} -> {:cont, {:ok, [substituted | acc]}}
        {:error, block_id} -> {:halt, {:error, block_id}}
      end
    end)
    |> case do
      {:ok, acc} -> {:ok, %{emission | children: Enum.reverse(acc)}}
      {:error, block_id} -> {:error, block_id}
    end
  end

  defp substitute({:child, block_id}, available) do
    case Map.fetch(available, block_id) do
      {:ok, emission} -> {:ok, emission}
      :error -> {:error, block_id}
    end
  end

  @spec emit_findings(Block.t(), term()) :: [Finding.t()]
  defp emit_findings(%Block{id: id}, {:invalid_role, _block_id, role} = reason) do
    [
      Finding.new(
        :emit,
        reason,
        ~s(minted the state role "#{role}", which is not a lowercase identifier free of "__"),
        block_id: id
      )
    ]
  end

  defp emit_findings(%Block{id: id}, {:reserved_role, _block_id, role} = reason) do
    [
      Finding.new(
        :emit,
        reason,
        ~s(minted the state role "#{role}", which is in the reserved outcome namespace),
        block_id: id
      )
    ]
  end

  defp emit_findings(%Block{id: id}, {:invalid_outcome, _block_id, outcome} = reason) do
    [
      Finding.new(
        :emit,
        reason,
        ~s(declared or minted the outcome "#{outcome}", which is either declared twice ) <>
          ~s(or not a lowercase identifier free of "__"),
        block_id: id
      )
    ]
  end

  defp emit_findings(%Block{id: id}, findings) when is_list(findings) do
    Enum.map(findings, fn
      {key, message} when is_binary(key) and is_binary(message) ->
        Finding.new(:emit, {:emit_refused, key}, message, block_id: id, config_key: key)

      other ->
        Finding.new(:emit, {:emit_refused, other}, inspect(other), block_id: id)
    end)
  end

  defp emit_findings(%Block{id: id}, reason) do
    [Finding.new(:emit, {:emit_refused, reason}, inspect(reason), block_id: id)]
  end

  # The `<scxml>` element belongs to no particular block, so ADR-0004
  # decision 5 attributes it to the **root block**, which ADR-0001 decision
  # 1 guarantees exists. That is what makes the provenance map total over
  # the bytes: the root element's span covers all of them, so no offset in
  # the generated chart is unowned.
  @spec scxml_element(Resolved.t(), Document.id(), Emission.t(), [Emission.t()], [option()]) ::
          Emission.t()
  defp scxml_element(
         %Resolved{block: %Block{id: root_id}} = node,
         document_id,
         root_emission,
         roots,
         opts
       ) do
    {root, finals} = completion_finals(node, root_emission, opts)

    # The `<datamodel>` wrapper belongs to no block either, so it takes
    # the root block for `<scxml>`'s reason; the `<data>` elements inside
    # it keep the owners their own blocks stamped on them. A document that
    # declares no roots gets no element at all, which is what keeps every
    # chart compiled before F2 existed byte-identical.
    datamodel =
      roots
      |> DeclaredRoots.datamodel()
      |> Enum.map(&%{&1 | owner: Provenance.owner(root_id)})

    element =
      Emission.element(
        "scxml",
        [
          {"initial", StateId.state_id(root_id)},
          {"name", document_id},
          {"version", "1.0"},
          {"xmlns", @scxml_ns}
        ],
        datamodel ++ [root | finals]
      )

    %{element | owner: Provenance.owner(root_id)}
  end

  # -- Stage 5a: the top-level completion finals ------------------------------

  # Two options ask for the same shape, for two different uses:
  #
  #   * `:child_use` - ADR-0004's 2026-08-29 amendment, C1: a document
  #     compiled for use as a child emits one top-level `<final>` per
  #     outcome its root block declares, carrying the outcome name as done
  #     data, because that is the only way an outcome crosses an `<invoke>`
  #     boundary.
  #   * `:terminate` - ADR-0004's 2026-08-29 root-termination note: a root
  #     document emits the same finals with **no** `<donedata>`, because
  #     nothing is listening across a boundary and what the option buys is
  #     the session reaching `:done` at all.
  #
  # In both cases the root block's own outcome finals and the raises inside
  # them are untouched - what is added here is what turns that internal
  # signal into a top-level `<final>` the session can actually enter.
  #
  # The transitions sit on the root block's own state, because that is the
  # only place an event a descendant raised can be selected from; the
  # finals are its siblings under `<scxml>`. Both are attributed to the
  # root block, in the `child_<outcome>` or `root_<outcome>` role, through
  # the same `Attribution.stamp/3` every block's own emission goes through
  # - so the provenance map stays total over the added bytes rather than
  # growing a hole nobody owns (decision 5).
  #
  # The two are mutually exclusive and `chart_use_stage/2` has already
  # refused the pair, so the order of the clauses below decides nothing.
  @spec completion_finals(Resolved.t(), Emission.t(), [option()]) ::
          {Emission.t(), [Emission.t()]}
  defp completion_finals(node, emission, opts) do
    cond do
      Keyword.get(opts, :child_use, false) ->
        completion_finals(node, emission, @child_role_prefix, true)

      Keyword.get(opts, :terminate, false) ->
        completion_finals(node, emission, @root_role_prefix, false)

      true ->
        {emission, []}
    end
  end

  @spec completion_finals(Resolved.t(), Emission.t(), String.t(), boolean()) ::
          {Emission.t(), [Emission.t()]}
  defp completion_finals(%Resolved{block: block, module: module}, emission, prefix, donedata?) do
    pairs =
      module
      |> BlockType.outcome_names(block.config)
      |> Enum.flat_map(&completion_outcome(block.id, &1, prefix, donedata?))

    transitions = Enum.map(pairs, &elem(&1, 0))
    finals = Enum.map(pairs, &elem(&1, 1))

    {%{emission | children: emission.children ++ transitions}, finals}
  end

  @spec completion_outcome(Block.id(), String.t(), String.t(), boolean()) ::
          [{Emission.t(), Emission.t()}]
  defp completion_outcome(root_id, outcome, prefix, donedata?) do
    with {:ok, final_id} <- StateId.state_id(root_id, prefix <> outcome),
         {:ok, transition} <-
           stamp_completion(completion_transition(root_id, outcome, final_id), root_id),
         {:ok, final} <-
           stamp_completion(completion_final(final_id, outcome, donedata?), root_id) do
      [{transition, final}]
    else
      _refused -> []
    end
  end

  @spec completion_transition(Block.id(), String.t(), StateId.t()) :: Emission.t()
  defp completion_transition(root_id, outcome, final_id) do
    Emission.element("transition", [
      {"event", StateId.outcome_event(StateId.state_id(root_id), outcome)},
      {"target", final_id}
    ])
  end

  @spec completion_final(StateId.t(), String.t(), boolean()) :: Emission.t()
  defp completion_final(final_id, outcome, true) do
    Emission.element("final", [{"id", final_id}], [
      Emission.element("donedata", [], [
        Emission.element("param", [{"expr", "'" <> outcome <> "'"}, {"name", "outcome"}])
      ])
    ])
  end

  defp completion_final(final_id, _outcome, false) do
    Emission.element("final", [{"id", final_id}])
  end

  @spec stamp_completion(Emission.t(), Block.id()) ::
          {:ok, Emission.t()} | {:error, {:unknown_attribution, Block.id()}}
  defp stamp_completion(emission, root_id) do
    Attribution.stamp(emission, root_id, MapSet.new([root_id]))
  end

  # -- Stage 5a': the chart-use refusal ---------------------------------------

  # `:child_use` and `:terminate` are the same emission shaped for two
  # different uses, and a document is compiled for one or the other. Both
  # together would put two transitions on the same
  # `done.outcome.<root state id>.<outcome>` event on the root block's own
  # state, and document order - not the caller - would decide which
  # top-level `<final>` a run reaches, silently. Refusing is the honest
  # answer, and it is an `:emit` finding because the thing refused is an
  # emission shape. It is not a new pipeline stage (decision 10's table is
  # unchanged); it runs before Emit only because there is nothing worth
  # emitting once it fires.
  @spec chart_use_stage(Resolved.t(), [option()]) :: :ok | {:error, [Finding.t()]}
  defp chart_use_stage(%Resolved{block: %Block{id: root_id}}, opts) do
    if Keyword.get(opts, :child_use, false) and Keyword.get(opts, :terminate, false) do
      {:error,
       [
         Finding.new(
           :emit,
           {:conflicting_chart_use, :child_use, :terminate},
           "a document is compiled either for use as a child (child_use: true) or as a " <>
             "root document that finishes (terminate: true), and this compile asked for " <>
             "both",
           block_id: root_id
         )
       ]}
    else
      :ok
    end
  end

  # -- Stage 5a'': the self-reference refusal ---------------------------------

  # Runs on the assembled emission, between Emit and Chart, for the reason
  # the sensitive-path refusal below runs there: the criterion is about
  # the emission - which `<invoke>` names which document - rather than
  # about one block's config, and it is the first point where the
  # document's own id and every emitted `src` are both in hand. Its
  # findings carry the `:emit` stage they were produced in, and it is not
  # a new pipeline stage: decision 10's table is unchanged. See
  # `StatifierBlocks.Compiler.SelfReference` for the criterion and for why
  # cross-document cycles are the host resolver's.
  @spec self_reference_stage(Emission.t(), Document.id()) :: :ok | {:error, [Finding.t()]}
  defp self_reference_stage(emission, document_id) do
    case SelfReference.check(emission, document_id) do
      [] -> :ok
      findings -> {:error, findings}
    end
  end

  # -- Stage 5b: the sensitive-path refusal -----------------------------------

  # Runs on the assembled emission, between Emit and Chart, because the
  # criterion it applies is about the emission: which attributes the chart
  # will evaluate against the datamodel (see
  # `StatifierBlocks.Compiler.SensitivePaths`). Its findings carry the
  # `:emit` stage they were produced in and, because every one of them
  # anchors on a config field, the author's side of decision 9's fault
  # split. It is not a new pipeline stage - decision 10's table is
  # unchanged - and it stops the compile before Chart for the same reason
  # every other error does: there is nothing worth serializing.
  @spec sensitive_stage(Emission.t(), [option()]) :: :ok | {:error, [Finding.t()]}
  defp sensitive_stage(emission, opts) do
    case SensitivePaths.check(emission, Keyword.get(opts, :datamodel)) do
      [] -> :ok
      findings -> {:error, findings}
    end
  end

  # -- Stage 6: chart --------------------------------------------------------

  @spec chart_stage(Document.t(), Resolved.t(), Emission.t(), [Finding.t()], keyword()) ::
          {:ok, Compiled.t()} | {:error, [Finding.t()]}
  defp chart_stage(%Document{} = document, node, emission, emit_warnings, opts) do
    {scxml, provenance} = Serializer.serialize(emission)
    emitted = InvokeTypes.collect(emission)

    with {:ok, warnings} <- Chart.validate(scxml, provenance, document) do
      {:ok,
       %Compiled{
         scxml: scxml,
         provenance: provenance,
         record: record(document, node, scxml),
         invoke_types: InvokeTypes.types(emitted),
         warnings: emit_warnings ++ warnings ++ lint(emitted, opts)
       }}
    end
  end

  @spec lint([InvokeTypes.emitted()], keyword()) :: [Finding.t()]
  defp lint(emitted, opts) do
    case Keyword.fetch(opts, :known_invoke_types) do
      {:ok, known} -> InvokeTypes.lint(emitted, known)
      :error -> []
    end
  end

  @spec record(Document.t(), Resolved.t(), binary()) :: CompilationRecord.t()
  defp record(%Document{} = document, node, scxml) do
    %CompilationRecord{
      document_id: document.id,
      revision: document.revision,
      document_hash: Document.content_hash(document),
      palette_hash: palette_hash(node),
      compiler_version: @compiler_version,
      chart_identity: Identity.of_source(scxml, chart_name: document.id, chart_version: nil)
    }
  end

  # -- Findings: paths, and document order ----------------------------------

  # Decision 10 requires every finding to name a block; ADR-0001 decision 5
  # gives the editor the path to reveal it in the tree without walking the
  # document. Both are filled in once, here, so no stage has to remember
  # to - and every stage's findings come out in the same order, which is
  # `Document.blocks/1`'s pre-order and is how upstream's own
  # document-order sort survives the trip.
  @spec in_document_order({:ok, Compiled.t()} | {:error, [Finding.t()]}, Document.t()) ::
          {:ok, Compiled.t()} | {:error, [Finding.t()]}
  defp in_document_order({:ok, %Compiled{} = compiled}, document) do
    {:ok, %{compiled | warnings: order(compiled.warnings, document)}}
  end

  defp in_document_order({:error, findings}, document) do
    {:error, order(findings, document)}
  end

  @spec order([Finding.t()], Document.t()) :: [Finding.t()]
  defp order(findings, document) do
    ranks =
      document
      |> Document.blocks()
      |> Enum.with_index()
      |> Map.new(fn {block, index} -> {block.id, index} end)

    findings
    |> Enum.map(&locate(&1, document))
    |> Enum.sort_by(&Map.get(ranks, &1.block_id, -1))
  end

  @spec locate(Finding.t(), Document.t()) :: Finding.t()
  defp locate(%Finding{block_id: nil} = finding, _document), do: finding
  defp locate(%Finding{path: path} = finding, _document) when is_list(path), do: finding

  defp locate(%Finding{block_id: block_id} = finding, document) do
    case Document.fetch_path(document, block_id) do
      {:ok, path} -> %{finding | path: path}
      :error -> finding
    end
  end

  # A digest over the sorted `{type_name, module, current_version}` triples
  # of the entries this compile actually resolved. See
  # `StatifierBlocks.CompilationRecord` for what it does and does not claim.
  @spec palette_hash(Resolved.t()) :: binary()
  defp palette_hash(node) do
    digest =
      node
      |> entries()
      |> Enum.uniq()
      |> Enum.sort()
      |> Enum.map_join("\n", fn {type, module, version} ->
        "#{type}\t#{inspect(module)}\t#{version}"
      end)

    "sha256:" <> Base.encode16(:crypto.hash(:sha256, digest), case: :lower)
  end

  @spec entries(Resolved.t()) :: [{Block.type_name(), module(), pos_integer()}]
  defp entries(%Resolved{block: block, module: module, slots: slots}) do
    [
      {block.type, module, module.current_version()}
      | Enum.flat_map(slots, fn {_name, children} -> Enum.flat_map(children, &entries/1) end)
    ]
  end
end
