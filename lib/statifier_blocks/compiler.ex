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
     config migration (ADR-0002 decision 8). Nothing is written back. A
     resolved node whose module is a composite is **replaced, in place, by
     the subtree `StatifierBlocks.Composite.expand!/2` returns** (ADR-0004's
     amendment of 2026-09-07, E1), so stages 3-6 read a tree with no
     composite in it and need no knowledge that one was ever there. The
     param map the expansion returns is kept beside the tree, and a finding
     raised against a block inside an expansion is re-anchored to the
     composite block and the param that produced it before it is reported
     (E3). The provenance map is never rewritten: every span keeps the
     expanded block that emitted it.
  3. **Config** - every block's `validate_config/1`, the checks beside it
     that read something a block type cannot see from its own config, and
     the one name a **root** block may not declare as an outcome (ADR-0002's
     failure amendment of 2026-09-06, section 4 step 3, and the Note that
     closes it).
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

  ### Config and Structure are reported together

  Every other stage in decision 10's table stops the pipeline the moment it
  fails, and the errors a caller gets back come from that one stage. Config
  and Structure are the one pair that does not: when Config finds something,
  Structure still runs, and the refusal carries the **union** of what both
  found (RQ-SF035-2, and the dated Notes of 2026-09-06 on ADR-0004
  decision 10 and on ADR-0011 decision 1).

  The reason is that they are not in a consequence relation the way the
  later stages are. Emit reads the tree Structure has already agreed is
  well-formed, so its findings on a document Structure refused would be
  artefacts. Structure reads the *document*, not the config values Config
  checks, so a mis-typed field on one card and an unsatisfied read on
  another are two independent statements about the same document - and an
  author who can only see the first has to fix it, recompile, and discover
  the second, one round trip per stage. Decision 10's "every finding within
  a stage is reported, because they are siblings" is the same argument; this
  extends it across exactly the one stage boundary where it holds.

  What a block whose config Config refused contributes to Structure is
  nothing at all - it is skipped by id, and every other block is checked
  exactly as it would have been. That is what the old sequencing bought and
  what has to be bought again some other way: *every* source in the
  Structure stage reads the refused config. A write signature comes off a
  config, so an entry derived from one would make the next block's read
  disagree with a type nobody declared; `slots/1` takes a config too, so
  slot arity and `:undeclared_slot` on a refused block would be counted
  against a slot set that config does not really declare; and
  `StatifierBlocks.Shelf` places a block the config named. So the refused
  ids reach the environment walk as `:skip_blocks` - the block declares no
  read and writes no entry - and the two document-shape sources drop the
  findings they anchored on those same ids.

  The walk itself continues past a skipped block: its siblings and its
  children are checked as they always were, and a child's config is its own.
  This is an absence of one block's answers, not a shortened stage.

  Refusal semantics are unchanged. A document with a Config finding still
  does not compile; it now says more about why.

  ### The Structure stage is whole

  Decision 10's table names three things in this stage: slot **arity**,
  `:undeclared_slot`, and assignability. ADR-0004's amendment of
  2026-08-31, section D3, adds two more to the same row under campaign-024
  ruling R-b - `:drafts_block_misplaced` and `:duplicate_drafts_block`,
  the two placement facts a block type's `io/1` cannot carry, owned by
  `StatifierBlocks.Shelf`. All of them run here, and their
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
    * `:field_candidates` - the values a host offers per field, keyed
      `{type_name, field_key}`, the same map the editor's own
      `field_candidates` assign takes. A **closed** list - `[{value,
      label}]` - turns a value it does not offer into a **warning**, never
      an error; an open list - `{:open, choices}` - reports nothing, and a
      field the map does not name is not looked at. Absent, the lint does
      not run.
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

      The same document is read by two other checks, and it is read once:
      the structure stage's typed-environment read check (ADR-0011
      decisions 2 and 3), and the config stage's declared-payload refusal,
      where a `core.on_event` that declares its `payload` refuses a
      `capture` pair reading a member that payload does not carry
      (ADR-0002's amendment of 2026-09-06). A compile with no `:datamodel`
      runs neither, and refuses nothing.
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

      Beside those per-outcome finals, one **shared** top-level `<final>`
      is emitted when a block below the root declares a failure-classed
      outcome - one `StatifierBlocks.BlockType.failure_outcomes/2` names -
      that the document did not handle (ADR-0002's failure amendment of
      2026-09-06, section 4). It is minted from the root block's id under
      the role `child_failed`, one transition per unhandled pair reaches
      it from the root block's own state, and it carries
      `<param name="outcome" expr="'error'"/>` beside the reserved
      `<param name="statifier_persistence:run_status" expr="'failed'"/>`.
      The outcome it reports is `error` rather than the failing block's
      own outcome name, because `StatifierBlocks.Core.Subchart` appends
      `error` to its outcomes whether or not the author listed it, so it
      is the one word a parent is guaranteed to have a route for. A
      document with no unhandled failure below its root gains nothing
      here, and a root block may not declare an outcome named `failed`:
      that would ask for this final's state id a second time, and it is
      refused as a Config-stage finding.
    * `:terminate` - compile this document **as a root document that
      finishes** (ADR-0004's 2026-08-29 root-termination note). The
      emission gains one top-level `<final>` per outcome the root block
      declares, reached from `done.outcome.<root state id>.<outcome>` and
      carrying **no** `<donedata>` - except that a final for a
      failure-classed outcome carries the one reserved run-status `<param>`
      described below - so the session reaches `:done` when the
      root block completes. Without it a compiled root document never
      terminates: the root block's own outcome finals are children of the
      root compound state, so completing the root block raises
      `done.outcome` internally and the session stays active forever, which
      is what leaves a durable run uncompleted. Defaults to `false`, and a
      document compiled without it is byte-identical to what it was before
      the option existed.

      Beside those per-outcome finals, one **shared** top-level `<final>`
      is emitted when a block below the root declares a failure-classed
      outcome the document did not handle, exactly as under `:child_use`
      (ADR-0002's failure amendment of 2026-09-06, section 4). Here it is
      minted from the root block's id under the role `root_failed`, one
      transition per unhandled pair reaches it from the root block's own
      state, and its `<donedata>` holds only the reserved
      `<param name="statifier_persistence:run_status" expr="'failed'"/>` -
      the key `statifier_persistence`'s ADR-0008 amendment of 2026-09-06
      fixes, which a durable stepper reads to decide that the run failed.
      So a root document whose nested step fails still reaches `:done`,
      and says that it failed when it gets there. A document with no
      unhandled failure below its root gains nothing here, and a root
      block may not declare an outcome named `failed`: that would ask for
      this final's state id a second time, and it is refused as a
      Config-stage finding.

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
    Composite,
    Document,
    Emission,
    Environment,
    Palette,
    Provenance,
    Shelf,
    SlotValidation
  }

  alias StatifierBlocks.Core.{Config, OnEvent, ResumableGroup, Send}

  alias StatifierBlocks.Compiler.{
    Attribution,
    Cancels,
    Chart,
    Context,
    DeclaredRoots,
    Finding,
    Interrupts,
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

  # ADR-0008's 2026-09-06 amendment in `statifier_persistence`: the
  # reserved `<donedata>` key a failure-classed final carries, and the one
  # value its set is closed at.
  # C1's own `<param>` name, and one of the two a `donedata_type/1` entry
  # may not mint.
  @outcome_param_name "outcome"

  @run_status_key "statifier_persistence:run_status"
  @run_status_failed "failed"

  # ADR-0002's amendment of 2026-09-06, section 4: the role the one shared
  # top-level final for an unhandled failure below the root is minted
  # under, appended to whichever of the two prefixes above the compile
  # option chose - `child_failed` or `root_failed`, so a reader can tell
  # which option produced it.
  @failed_role "failed"

  # The outcome name that final reports under `:child_use`. It is `error`
  # rather than the nested block's own outcome name because a parent reads
  # a child chart through `core.subchart`, which appends `error` to its
  # outcomes whether or not the author listed it - so `error` is the one
  # word a parent is guaranteed to have a route for, and a name from
  # inside the child chart would not be.
  @propagated_outcome "error"

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
  @compiler_version "0.26.0"

  # A resolved block and its resolved children, in `slots/1` declaration
  # order. Built once by the Resolve stage and threaded through the rest, so
  # no later stage re-resolves or re-migrates anything.
  defmodule Resolved do
    @moduledoc false

    @type t :: %__MODULE__{
            block: StatifierBlocks.Block.t(),
            module: StatifierBlocks.Palette.type_ref(),
            slots: [{StatifierBlocks.Block.slot_name(), [t()]}]
          }

    @enforce_keys [:block, :module, :slots]
    defstruct [:block, :module, :slots]
  end

  @typedoc """
  `:known_invoke_types` enables decision 8's optional two-registry lint;
  `:field_candidates` enables the opt-in warning for a value outside a
  host's own closed candidate list;
  `:entry_type` is ADR-0003 decision 4's caller-supplied context;
  `:datamodel` is the host's declared datamodel, read by the sensitive-path
  refusal, the typed-environment read check and the declared-payload
  refusal; `:declare` is the `<data>` roots the host declares for this
  document. See the moduledoc.
  """
  @type option ::
          {:known_invoke_types, Enumerable.t()}
          | {:field_candidates, %{optional({String.t(), String.t()}) => term()}}
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
  (decision 10), with one exception the moduledoc's "Config and Structure
  are reported together" section states: those two stages run as a pair, and
  a refusal carries the union of their findings. Warnings ride on the
  artifact when the compile succeeds.
  """
  @spec compile(Document.t(), Palette.t(), [option()]) ::
          {:ok, Compiled.t()} | {:error, [Finding.t()]}
  def compile(%Document{} = document, %Palette{} = palette, opts \\ []) when is_list(opts) do
    document
    |> stages(palette, opts)
    |> in_document_order(document)
  end

  # Resolve is pulled out of the `with` because it answers a third thing the
  # stages after it do not: the expansion index, which every finding - its
  # own included - is re-anchored through before it is reported.
  @spec stages(Document.t(), Palette.t(), [option()]) ::
          {:ok, Compiled.t()} | {:error, [Finding.t()]}
  defp stages(%Document{} = document, %Palette{} = palette, opts) do
    with :ok <- document_stage(document) do
      case resolve_stage(document, palette) do
        {:ok, node, expansion} ->
          document
          |> after_resolve(palette, node, expansion, opts)
          |> reanchor(expansion)

        {:error, findings, expansion} ->
          reanchor({:error, findings}, expansion)
      end
    end
  end

  @spec after_resolve(Document.t(), Palette.t(), Resolved.t(), expansion(), [option()]) ::
          {:ok, Compiled.t()} | {:error, [Finding.t()]}
  defp after_resolve(document, palette, node, expansion, opts) do
    with :ok <- config_and_structure_stages(document, palette, node, expansion, opts),
         {node, shelf_warnings} = elide_shelf(node),
         :ok <- chart_use_stage(node, opts),
         :ok <- donedata_stage(node, opts),
         {:ok, {emission, emit_warnings}} <- emit_stage(node, document, opts),
         :ok <- self_reference_stage(emission, document.id),
         :ok <- sensitive_stage(emission, opts) do
      chart_stage(
        document,
        node,
        emission,
        shelf_warnings ++ marker_warnings(node) ++ deadline_warnings(node) ++ emit_warnings,
        opts
      )
    end
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

  # Every block inside an expansion, to the composite block it came from and
  # the param key to blame for what it was given - or `nil` when no single
  # param is (ADR-0004's amendment of 2026-09-07, E3).
  #
  # Built by this stage and read once, when findings are reported. A composite
  # nested inside another composite's subtree puts its own members here
  # pointing at it, and itself here pointing at the outer composite, so the
  # walk to the block an author can hold is `anchor/2`'s.
  @typep expansion :: %{optional(Block.id()) => {Block.id(), String.t() | nil}}

  @spec resolve_stage(Document.t(), Palette.t()) ::
          {:ok, Resolved.t(), expansion()} | {:error, [Finding.t()], expansion()}
  defp resolve_stage(%Document{root: root}, palette) do
    case resolve(palette, root) do
      {:ok, [node], expansion} ->
        {:ok, node, expansion}

      {:ok, [_ | _] = nodes, expansion} ->
        {:error, [root_expansion_finding(root, length(nodes))], expansion}

      {:error, findings, expansion} ->
        {:error, findings, expansion}
    end
  end

  # A block resolves to a *list* of nodes because a composite resolves to its
  # expansion, which E1 splices in place of it. Every other block resolves to
  # the one node it always did.
  @spec resolve(Palette.t(), Block.t()) ::
          {:ok, [Resolved.t()], expansion()} | {:error, [Finding.t()], expansion()}
  defp resolve(palette, %Block{} = block) do
    case Palette.resolve(palette, block) do
      {:ok, module, resolved} ->
        if Composite.composite?(module) do
          expand_node(palette, resolved, module)
        else
          resolve_children(palette, module, resolved)
        end

      {:error, reason} ->
        {orphans, expansion} = orphan_findings(palette, block)
        {:error, [resolve_finding(block, reason) | orphans], expansion}
    end
  end

  # E1: the replacement is complete before the stage ends, so a member that is
  # itself a composite expands here too. `Composite.expand!/2` raises on a
  # broken declaration and decision 1 forbids this pipeline to raise, so the
  # raise becomes a `:resolve` finding against the composite block - the one
  # block in the neighbourhood an author can see.
  @spec expand_node(Palette.t(), Block.t(), module()) ::
          {:ok, [Resolved.t()], expansion()} | {:error, [Finding.t()], expansion()}
  defp expand_node(palette, %Block{} = block, module) do
    case expand(block, module) do
      {:ok, members, param_map} ->
        # `ADR-0004`'s T3: the index maps expansion MEMBERS only. The param
        # map is keyed by exactly those - `Composite.expand!/2` takes it over
        # the minted members, before the author's pass-through children are
        # spliced in - so a child the author placed has no entry here, and
        # `anchor/2` finds nothing for it and leaves its finding on it.
        own = Map.new(param_map, fn {id, key} -> {id, {block.id, key}} end)

        members
        |> Enum.reduce({[], [], own}, &resolve_member(palette, &1, &2))
        |> then(fn
          {nodes, [], expansion} -> {:ok, nodes, expansion}
          {_nodes, findings, expansion} -> {:error, findings, expansion}
        end)

      {:error, finding} ->
        {:error, [finding], %{}}
    end
  end

  # The composite's own entries win the merge: a member that is itself a
  # composite reports its members against *it*, and `anchor/2` climbs from
  # there to the outermost composite the author can hold.
  @spec resolve_member(
          Palette.t(),
          Block.t(),
          {[Resolved.t()], [Finding.t()], expansion()}
        ) :: {[Resolved.t()], [Finding.t()], expansion()}
  defp resolve_member(palette, member, {nodes, findings, expansion}) do
    case resolve(palette, member) do
      {:ok, member_nodes, member_expansion} ->
        {nodes ++ member_nodes, findings, Map.merge(member_expansion, expansion)}

      {:error, member_findings, member_expansion} ->
        {nodes, findings ++ member_findings, Map.merge(member_expansion, expansion)}
    end
  end

  @spec expand(Block.t(), module()) ::
          {:ok, [Block.t()], Composite.param_map()} | {:error, Finding.t()}
  defp expand(%Block{} = block, module) do
    {members, param_map} = Composite.expand!(block, module)
    {:ok, members, param_map}
  rescue
    error ->
      why = Exception.message(error)

      {:error,
       Finding.new(
         :resolve,
         {:composite_expansion_failed, block.id, why},
         "the composite could not be expanded: #{why}",
         block_id: block.id
       )}
  end

  # ADR-0001 decision 1 gives a document exactly one root, so a composite at
  # the root whose subtree answers more than one top-level block has nowhere
  # to splice the rest. Refusing is the only honest answer: silently keeping
  # the expansion root would drop blocks the declaration wrote.
  @spec root_expansion_finding(Block.t(), pos_integer()) :: Finding.t()
  defp root_expansion_finding(%Block{id: id}, count) do
    Finding.new(
      :resolve,
      {:composite_expansion_failed, id, {:root_expansion_not_single, count}},
      "the document root is a composite whose subtree answers #{count} top-level " <>
        "blocks, and a document has exactly one root: there is nowhere to splice the rest",
      block_id: id
    )
  end

  @spec resolve_children(Palette.t(), Palette.type_ref(), Block.t()) ::
          {:ok, [Resolved.t()], expansion()} | {:error, [Finding.t()], expansion()}
  defp resolve_children(palette, ref, %Block{} = block) do
    {slots, findings, expansion} =
      ref
      |> Palette.call(:slots, [block.config], [])
      |> Enum.reduce({[], [], %{}}, fn {name, _arity, _label}, {slots, findings, expansion} ->
        {children, child_findings, child_expansion} = resolve_slot(palette, block, name)

        {[{name, children} | slots], findings ++ child_findings,
         Map.merge(expansion, child_expansion)}
      end)

    case findings do
      [] ->
        {:ok, [%Resolved{block: block, module: ref, slots: Enum.reverse(slots)}], expansion}

      findings ->
        {:error, findings, expansion}
    end
  end

  @spec resolve_slot(Palette.t(), Block.t(), Block.slot_name()) ::
          {[Resolved.t()], [Finding.t()], expansion()}
  defp resolve_slot(palette, %Block{slots: slots}, name) do
    slots
    |> Map.get(name, [])
    |> Enum.reduce({[], [], %{}}, fn child, {nodes, findings, expansion} ->
      case resolve(palette, child) do
        {:ok, child_nodes, child_expansion} ->
          {Enum.reverse(child_nodes) ++ nodes, findings, Map.merge(expansion, child_expansion)}

        {:error, child_findings, child_expansion} ->
          {nodes, findings ++ child_findings, Map.merge(expansion, child_expansion)}
      end
    end)
    |> then(fn {nodes, findings, expansion} -> {Enum.reverse(nodes), findings, expansion} end)
  end

  # A block whose own type did not resolve has no `slots/1` to walk, so its
  # children are visited in sorted slot-name order instead. Reporting them
  # too is decision 10's "within a stage every finding is reported": the
  # children's types are siblings of this failure, not consequences of it.
  @spec orphan_findings(Palette.t(), Block.t()) :: {[Finding.t()], expansion()}
  defp orphan_findings(palette, %Block{slots: slots}) do
    slots
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.flat_map(fn {_name, children} -> children end)
    |> Enum.reduce({[], %{}}, fn child, {findings, expansion} ->
      {child_findings, child_expansion} = orphan_child_findings(palette, child)
      {findings ++ child_findings, Map.merge(expansion, child_expansion)}
    end)
  end

  @spec orphan_child_findings(Palette.t(), Block.t()) :: {[Finding.t()], expansion()}
  defp orphan_child_findings(palette, child) do
    case resolve(palette, child) do
      {:ok, _nodes, expansion} -> {[], expansion}
      {:error, findings, expansion} -> {findings, expansion}
    end
  end

  # E3: a finding raised inside an expansion names a block the author cannot
  # see, cannot select and cannot edit, so it is re-anchored one level up
  # before it is reported - onto the composite block, carrying the key the
  # param map names or `nil` when it names none. It runs before
  # `in_document_order/2`, because the stored document is where a reported
  # finding's path comes from and an expanded id has no path in it.
  #
  # Nothing else moves. Decision 5's map still owns every span by the member
  # that emitted it, so the Source tab still highlights the member's own span
  # and a fixture run still names the member: the author's surface says which
  # param is wrong, the engineer's says which state carries the bytes.
  @spec reanchor({:ok, Compiled.t()} | {:error, [Finding.t()]}, expansion()) ::
          {:ok, Compiled.t()} | {:error, [Finding.t()]}
  defp reanchor(result, expansion) when map_size(expansion) == 0, do: result

  defp reanchor({:ok, %Compiled{} = compiled}, expansion) do
    {:ok, %{compiled | warnings: Enum.map(compiled.warnings, &reanchor_finding(&1, expansion))}}
  end

  defp reanchor({:error, findings}, expansion) do
    {:error, Enum.map(findings, &reanchor_finding(&1, expansion))}
  end

  @spec reanchor_finding(Finding.t(), expansion()) :: Finding.t()
  defp reanchor_finding(%Finding{block_id: nil} = finding, _expansion), do: finding

  defp reanchor_finding(%Finding{block_id: block_id} = finding, expansion) do
    case anchor(expansion, block_id) do
      nil -> finding
      {composite_id, config_key} -> %{finding | block_id: composite_id, config_key: config_key}
    end
  end

  # A composite whose subtree holds another composite expands twice, and the
  # inner expansion's blocks are as invisible to the author as the outer's.
  # The walk therefore does not stop at the inner composite: it climbs to the
  # outermost one, carrying that composite's own param key rather than the
  # inner one's, because the inner key names no field on the form the author
  # is looking at.
  @spec anchor(expansion(), Block.id()) :: {Block.id(), String.t() | nil} | nil
  defp anchor(expansion, block_id) do
    case Map.fetch(expansion, block_id) do
      :error ->
        nil

      {:ok, {composite_id, config_key}} ->
        anchor(expansion, composite_id) || {composite_id, config_key}
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

  # The declarations are indexed once for the whole document, from the same
  # `:datamodel` option every other stage reads, and threaded down the tree:
  # a check that needs the datamodel is still a config check (ADR-0002's
  # amendment of 2026-09-06, P5 - the anchor is a config key and the fault is
  # the author's), and `validate_config/1` is the callback that cannot be
  # given one.
  @spec config_stage(Resolved.t(), keyword()) :: [Finding.t()]
  defp config_stage(node, opts) do
    declarations = opts |> assignability_context() |> Environment.declarations()
    reserved_outcome_findings(node) ++ config_findings(node, declarations)
  end

  # The one outcome name a **root** block may not declare (RQ-SF035-16;
  # `sb-ju4d` left the question open on ADR-0002's failure amendment,
  # section 4 step 3, and the Note of this bead's date closes it there).
  #
  # Section 4 step 3 mints the one shared final an unhandled failure below
  # the root reaches from the root block's id under the role
  # `<prefix>failed`, and `completion_outcome/6` mints the root's own
  # completion finals from the same id under `<prefix><outcome>`. A root
  # block declaring an outcome literally named `failed` therefore asks for
  # one state id twice.
  #
  # Refused unconditionally, not only where the collision would actually
  # fire. Whether the shared final is emitted at all depends on an
  # unhandled failure-classed outcome somewhere below the root (step 2), so
  # a conditional refusal would let a document compile and then stop
  # compiling after an edit three blocks down that says nothing about the
  # root's outcome names - and would say so in a sentence about a block the
  # author was not editing. The name is reserved on the root instead, in
  # one sentence the author can act on where they wrote it.
  #
  # Only on the root, because only the root's id mints `<prefix>failed`: a
  # block below the root may name an outcome `failed` exactly as it always
  # could, since its own outcome ids are minted from its own id.
  #
  # It is a `:config` finding rather than an `:emit` one because it is the
  # author's to fix and it is about a value they wrote, which is the split
  # `StatifierBlocks.Compiler.Finding`'s moduledoc draws; `:emit`'s
  # `:invalid_outcome` beside it is about a name no author could have
  # written, minted by a type.
  @spec reserved_outcome_findings(Resolved.t()) :: [Finding.t()]
  defp reserved_outcome_findings(%Resolved{block: block, module: module}) do
    if @failed_role in BlockType.outcome_names(module, block.config) do
      key = outcome_source_key(block, module)

      [
        Finding.new(
          :config,
          {:invalid_config, key},
          ~s(declares the outcome "#{@failed_role}" on the root block, whose top-level ) <>
            "final would take the state id already minted for the one shared final an " <>
            "unhandled failure below the root reaches (ADR-0002's failure amendment of " <>
            "2026-09-06, section 4 step 3). The name is reserved on a root block; rename " <>
            "the outcome",
          block_id: block.id,
          config_key: key
        )
      ]
    else
      []
    end
  end

  # Which config field the reserved name came out of, so an editor
  # underlines that field rather than the whole card: the field whose
  # removal removes the outcome. No new callback and no per-type knowledge
  # - `core.subchart` reads its outcomes off `outcomes`, and a host type
  # reads its own off whatever it likes.
  #
  # Keys in sorted order, so a config where more than one field could
  # answer for the name anchors on the same one every time.
  #
  # `nil` when no single field answers for it - a type whose outcome list
  # is a constant, or one that reads two fields together - and `nil` is
  # exactly the block anchor every finding that is about a block rather
  # than one of its fields already carries.
  @spec outcome_source_key(Block.t(), module()) :: String.t() | nil
  defp outcome_source_key(%Block{config: config}, module) do
    config
    |> Map.keys()
    |> Enum.sort()
    |> Enum.find(&(@failed_role not in outcome_names_without(module, config, &1)))
  end

  # The probe hands a block type a config it did not write, which is the
  # one place in this stage a well-behaved type could raise where the real
  # compile would not - a type that fetches a key it declared required. A
  # type that raises here has answered the question the probe asked with
  # "not this key", which is what decision 1's "never raises" costs and all
  # it costs: the finding is produced either way, with the block anchor.
  @spec outcome_names_without(module(), Block.config(), String.t()) :: [String.t()]
  defp outcome_names_without(module, config, key) do
    BlockType.outcome_names(module, Map.delete(config, key))
  rescue
    _any -> [@failed_role]
  end

  # Decision 10's two stages that run as a pair rather than in sequence. See
  # the moduledoc's "Config and Structure are reported together": Structure
  # reads the document while Config reads config values, so neither stage's
  # findings are artefacts of the other's, and an author gets both in one
  # refusal instead of one per round trip.
  #
  # The coupling between them runs one way and is exactly the skip set: a
  # block Config refused declares nothing Structure will believe, so its id
  # is passed down and `StatifierBlocks.Environment` leaves its writes out
  # while `StatifierBlocks.Assignability.validate/3` passes over the block
  # itself. A block with no `block_id` on its finding - there is no such
  # config finding today, since every one of them anchors on a card, but the
  # struct allows it - skips nothing, which is the permissive answer.
  @spec config_and_structure_stages(
          Document.t(),
          Palette.t(),
          Resolved.t(),
          expansion(),
          keyword()
        ) :: :ok | {:error, [Finding.t()]}
  defp config_and_structure_stages(document, palette, node, expansion, opts) do
    config = config_stage(node, opts)

    structure =
      structure_stage(
        structure_document(document, node, expansion),
        palette,
        opts,
        refused_block_ids(config)
      )

    case config ++ structure do
      [] -> :ok
      findings -> {:error, findings}
    end
  end

  # E1's third consequence: "Config and Structure see the members". Config
  # already walks the resolved tree, so it does. Structure walks a
  # `t:StatifierBlocks.Document.t/0` - `SlotValidation.validate/2`,
  # `Assignability.validate/3`, `Shelf.validate/1` and the environment all
  # take one - so for a document holding a composite it is handed the tree
  # the Resolve stage built instead, with the expansion spliced in. An
  # expanded member's slot arity and its assignability are then checked
  # exactly as they would be had an author placed those blocks by hand.
  #
  # A document holding no composite is passed through untouched, rather than
  # rebuilt from the resolved tree: rebuilding would hand Structure each
  # block's *migrated* config, which is a different question from the one
  # this bead is answering.
  @spec structure_document(Document.t(), Resolved.t(), expansion()) :: Document.t()
  defp structure_document(document, _node, expansion) when map_size(expansion) == 0, do: document

  defp structure_document(document, node, _expansion),
    do: %{document | root: resolved_block(node)}

  # The resolved tree carries only the slots the block's type *declares*, so
  # the stored map is merged under it rather than replaced: a slot no type
  # declares is what `:undeclared_slot` is about, and rebuilding without it
  # would silence that refusal for every document holding a composite.
  @spec resolved_block(Resolved.t()) :: Block.t()
  defp resolved_block(%Resolved{block: block, slots: slots}) do
    declared =
      Map.new(slots, fn {name, children} -> {name, Enum.map(children, &resolved_block/1)} end)

    %{block | slots: Map.merge(block.slots, declared)}
  end

  @spec refused_block_ids([Finding.t()]) :: MapSet.t(Block.id())
  defp refused_block_ids(findings) do
    for %Finding{block_id: id} <- findings, id != nil, into: MapSet.new(), do: id
  end

  @spec config_findings(Resolved.t(), StatifierDatamodel.Declarations.t()) :: [Finding.t()]
  defp config_findings(
         %Resolved{block: block, module: ref, slots: slots} = node,
         declarations
       ) do
    own =
      case Palette.call(ref, :validate_config, [block.config], :ok) do
        :ok -> []
        {:error, findings} -> findings
      end

    declared = declaration_findings(block, ref)
    expressions = BlockType.type_expr_findings(ref, block.config)
    typed = declared_payload_findings(node, declarations)

    Enum.map(declared ++ expressions ++ own ++ typed, fn {key, message} ->
      Finding.new(:config, {:invalid_config, key}, message,
        block_id: block.id,
        config_key: key
      )
    end) ++
      Enum.flat_map(slots, fn {_name, children} ->
        Enum.flat_map(children, &config_findings(&1, declarations))
      end)
  end

  # The config checks that are about the *declaration* rather than the value
  # under it: a field written without a `default:` key, and a `hidden?: true`
  # field whose `default:` is its type's empty value. Both are refused here,
  # at compile, naming the field.
  #
  # `t:StatifierBlocks.BlockType.field_decl/0` has required `:default` from
  # the start, so a declaration missing it was never well-formed. What it did
  # instead of failing was reach the view model, where every field's default
  # is destructured out of the declaration, and raise a `FunctionClauseError`
  # from inside the build - a stack trace naming neither the block type nor
  # the field, produced by whichever screen happened to render the block. The
  # earliest place the defect is visible with the field's name still attached
  # is the stage that already asks a block type what it declares, so that is
  # where it is refused.
  #
  # Every arm is checked. Until 2026-09-07 only the `{:path, opts}` arm was,
  # on the reasoning that a path field's `default:` is what the editor puts
  # in an unset control and what a read of the path falls back to, while for
  # every other field type the view model reads the key permissively and
  # renders `nil`; widening the refusal was a change to what a block type may
  # declare, which is the record's call and not this stage's. ADR-0002
  # decision 7's amendment of 2026-09-07 (section F3) takes that call: the
  # reasoning generalises, because `nil` is a value no block type ever said
  # was legal and `validate_config/1` cannot see a defect in a declaration.
  #
  # The second check is that amendment's F4. `hidden?: true` puts a field
  # beyond every form, so its `default:` is the only value it will ever have
  # unless a host writes the key itself; a `default:` that is the type's
  # *empty* value declares a key that carries nothing and can never be given
  # anything. The empty value is stated per type by the record rather than
  # derived here, and `:boolean` is the one type with none - `false` is a
  # decided value rather than an absence. A `readonly?: true` field takes no
  # such refusal: it is rendered, so an empty value is visible.
  #
  # The finding is per *block*, not per type. `config_schema/1` takes the
  # block's config, so what a type declares is not a property of the type
  # alone - two blocks of one type can differ - and nothing in the compile
  # de-duplicates by type. Anchoring on each block also sends an author to a
  # card they can see, which is what decision 11's routing is for; a
  # document with two offending blocks reports two findings, one apiece.
  @spec declaration_findings(Block.t(), Palette.type_ref()) :: [BlockType.finding()]
  defp declaration_findings(%Block{config: config}, ref) do
    ref
    |> Palette.call(:config_schema, [config], [])
    |> Enum.flat_map(&declaration_finding/1)
  end

  @spec declaration_finding(BlockType.field_decl()) :: [BlockType.finding()]
  defp declaration_finding(%{key: key} = decl) do
    cond do
      not Map.has_key?(decl, :default) ->
        [
          {key,
           ~s(the #{key} field is declared with no default: key, ) <>
             ~s(so it has no value to read when a config leaves it unset)}
        ]

      hidden_with_empty_default?(decl) ->
        [
          {key,
           ~s(the #{key} field is declared hidden?: true with an empty default:, ) <>
             ~s(so it carries no value and no form can ever give it one)}
        ]

      true ->
        []
    end
  end

  # ADR-0002 decision 7's amendment of 2026-09-07, section F4: the empty
  # value refused under `hidden?: true`, one row per member of the closed
  # nine-value `field_type/0` set. `:boolean` has no *type-specific* row and
  # falls through to the catch-all, which is the record's own reading of it.
  @spec hidden_with_empty_default?(BlockType.field_decl()) :: boolean()
  defp hidden_with_empty_default?(%{hidden?: true, type: type, default: default}),
    do: empty_default?(type, default)

  defp hidden_with_empty_default?(_decl), do: false

  # `nil` is an empty hidden default for EVERY row, not only the
  # `{:type_expr, opts}` one whose prose happened to enumerate its arms
  # (ADR-0002's Composite amendment of 2026-09-07, folding sb-3ejc). F4's own
  # reason applies unchanged to every row - a hidden field's `default:` is the
  # only value it will ever have, and `nil` carries nothing in exactly the
  # sense an empty string does - so the literal reading, under which a hidden
  # `:string` declaring `default: nil` was accepted while a hidden
  # `{:type_expr, opts}` declaring the same was refused, was an accident of
  # which row's prose enumerated its arms.
  #
  # `:boolean` is refused with every other row here, and its own clause below
  # still stands: `false` is a decided value, so a hidden `false` is a hidden
  # fact. `nil` is not `false`.
  @spec empty_default?(BlockType.field_type(), Block.json()) :: boolean()
  defp empty_default?(_type, nil), do: true
  defp empty_default?(:string, default), do: default == ""
  defp empty_default?(:integer, default), do: default == ""
  defp empty_default?(:boolean, _default), do: false
  defp empty_default?({:select, _choices}, default), do: default == ""
  defp empty_default?(:expression, default), do: default == ""
  defp empty_default?(:duration, default), do: default == ""
  defp empty_default?({:list, _inner}, default), do: default == []
  defp empty_default?({:path, _opts}, default), do: default == ""
  defp empty_default?({:type_expr, _opts}, default), do: default in ["", nil]
  defp empty_default?(_type, _default), do: false

  # The one config check in this package that reads the datamodel document.
  # `core.on_event` owns both halves of it - what a `payload` declares and
  # what a `capture` pair reads out of it - so the rule lives in that module
  # and this stage only hands it the declarations, in the same shape
  # `validate_config/1` returns.
  @spec declared_payload_findings(Resolved.t(), StatifierDatamodel.Declarations.t()) ::
          [{String.t(), String.t()}]
  defp declared_payload_findings(%Resolved{module: OnEvent, block: block}, declarations),
    do: OnEvent.payload_capture_findings(block.config, declarations)

  defp declared_payload_findings(%Resolved{}, _declarations), do: []

  # -- Stage 4: structure ----------------------------------------------------

  # Slot arity, `:undeclared_slot`, assignability, and the shelf's two
  # placement facts - decision 10's full table for this stage, plus the two
  # codes ADR-0004's amendment of 2026-08-31, section D3, adds to its
  # Structure row under campaign-024 ruling R-b. Every source is collected
  # and concatenated rather than any of them short-circuiting the others:
  # decision 10 says every finding within a stage is reported, because those
  # findings are siblings rather than consequences, and none of these three
  # is a consequence of another (see the moduledoc). This stage runs over
  # the *document* rather than the resolved tree because both
  # `SlotValidation.validate/2` and `Assignability.validate/3` are the one
  # implementation the editor and the compiler consult (ADR-0002 decision
  # 6, ADR-0003 decision 6), and the editor has no resolved tree.
  #
  # `skip` is the ids Config already refused (see the moduledoc's "Config and
  # Structure are reported together"). Every source here reads the config
  # that was refused, so every source has to pass over those blocks, and each
  # does it the way that suits what it computes: assignability takes the set
  # through the context, because the *environment* must not carry a write
  # derived from a refused config even for the blocks that are checked, while
  # `SlotValidation` and `Shelf` compute per block and are filtered on the way
  # out. Both are the same rule - a refused block contributes nothing to this
  # stage - and neither shortens the walk for anybody else.
  @spec structure_stage(Document.t(), Palette.t(), keyword(), MapSet.t(Block.id())) ::
          [Finding.t()]
  defp structure_stage(document, palette, opts, skip) do
    slot_findings =
      case SlotValidation.validate(palette, document) do
        :ok -> []
        {:error, findings} -> Enum.map(findings, &slot_finding/1)
      end

    ctx = opts |> assignability_context() |> Map.put(:skip_blocks, skip)
    declarations = Environment.declarations(ctx)

    assignability_findings =
      case Assignability.validate(palette, document, ctx) do
        :ok ->
          []

        {:error, findings} ->
          read_keys = read_keys(palette, document)
          Enum.map(findings, &structure_finding(&1, declarations, read_keys))
      end

    shelf_findings =
      case Shelf.validate(document) do
        :ok -> []
        {:error, findings} -> Enum.map(findings, &shelf_finding/1)
      end

    Enum.reject(slot_findings, &refused?(&1, skip)) ++
      assignability_findings ++ Enum.reject(shelf_findings, &refused?(&1, skip))
  end

  @spec refused?(Finding.t(), MapSet.t(Block.id())) :: boolean()
  defp refused?(%Finding{block_id: nil}, _skip), do: false
  defp refused?(%Finding{block_id: id}, skip), do: MapSet.member?(skip, id)

  # Both carry `severity: :error` and `fault: :author` by `Finding.new/4`'s
  # own defaults for this stage, and neither carries a `config_key`, because
  # neither is about a value in a form (ADR-0004's amendment of
  # 2026-08-31, section D3). Their anchor is the block, which is decision
  # 5's totality doing its ordinary work: an unplaceable block is still a
  # block and still names itself.
  @spec shelf_finding(Shelf.finding()) :: Finding.t()
  defp shelf_finding({:drafts_block_misplaced, id} = reason) do
    Finding.new(
      :structure,
      reason,
      ~s(a drafts block goes directly in the root block's "body" slot and nowhere else),
      block_id: id
    )
  end

  defp shelf_finding({:duplicate_drafts_block, id} = reason) do
    Finding.new(
      :structure,
      reason,
      "the document already carries a drafts block, and it carries at most one; " <>
        "the first one in document order is the one kept",
      block_id: id
    )
  end

  # Both keys are optional and both are read by the environment the
  # data-flow gate runs over: `:entry_type` seeds the document's subject
  # path, and `:datamodel` is the document the type declarations the read
  # check consults come from (ADR-0011 decisions 2 and 3). The `:datamodel`
  # option is the same one the sensitive-path refusal reads, passed through
  # untouched - a caller supplies one datamodel, not two.
  @spec assignability_context(keyword()) :: Assignability.context()
  defp assignability_context(opts) do
    Enum.reduce([:entry_type, :datamodel], %{}, fn key, acc ->
      case Keyword.fetch(opts, key) do
        {:ok, value} -> Map.put(acc, key, value)
        :error -> acc
      end
    end)
  end

  # `declarations` is what turns a nominal type name into the label ADR-0011
  # decision 9 asks a finding to carry. It is read from the same `:datamodel`
  # the check itself ran against - one document, read once in
  # `structure_stage/4` - so the sentence an author reads and the verdict it
  # explains cannot come from two different documents. With no datamodel to
  # hand the declarations are empty, every spelling renders as itself, and the
  # message is word for word the one this stage produced before the labels
  # existed.
  #
  # `read_keys` is the other half of decision 2's promise. A read signature is
  # declared ON A FIELD, and the reason it is - the finding anchors on the
  # key the author has a control for, rather than on the card - only holds if
  # the key survives the trip. `Assignability.finding()` names the datamodel
  # path and not the field (decision 8's tuple is six wide and stays six
  # wide), so the key is looked back up here, where the palette and the
  # document are both in hand, instead of being re-derived by every consumer
  # that wants to underline something.
  @spec structure_finding(
          Assignability.finding(),
          StatifierDatamodel.Declarations.t(),
          read_keys()
        ) :: Finding.t()
  defp structure_finding(
         {:kind_not_admitted, id, parent_id, slot, kinds, accepts} = reason,
         _declarations,
         _read_keys
       ) do
    Finding.new(
      :structure,
      reason,
      ~s(a #{inspect(kinds)} block cannot go in #{parent_id}'s "#{slot}" slot, ) <>
        "which admits #{inspect(accepts)}",
      block_id: id
    )
  end

  defp structure_finding(
         {:type_mismatch, id, source, held, expected, path} = reason,
         declarations,
         read_keys
       ) do
    Finding.new(
      :structure,
      reason,
      "this block reads #{named(declarations, expected)} at #{path}, " <>
        "where #{source_phrase(source)} #{named(declarations, held)}",
      block_id: id,
      config_key: Map.get(read_keys, {id, path, expected})
    )
  end

  # Which of the two sources typed the path, which is the difference between
  # "your block writes the wrong type here" and "the host declares this path
  # as something else" - and what the environment marks a seeded entry for.
  # A block and the slot entry read exactly as they always did.
  @spec source_phrase(Assignability.upstream_ref()) :: String.t()
  defp source_phrase(:declaration), do: "the datamodel document declares"
  defp source_phrase(source), do: "#{inspect(source)} left"

  @typedoc false
  @type read_keys :: %{{Block.id(), String.t(), term()} => String.t()}

  # Every read signature in the document that a form field declared, keyed by
  # what a `:type_mismatch` carries about it. The two together are what tells
  # two path fields reading the same path apart: they disagree on the type
  # they expect, or they are the same declaration twice and no consumer could
  # tell them apart anyway. `Environment.read_signatures/3` also yields the
  # `:consumes` sugar and capture pairs, whose key is an atom naming a
  # declaration form rather than a control an author can be sent to - those
  # are dropped here, and their findings keep the `nil` config key they have
  # always carried.
  @spec read_keys(Palette.t(), Document.t()) :: read_keys()
  defp read_keys(palette, document) do
    for %Block{id: id} = block <- Document.blocks(document),
        {key, path, expected} <- Environment.read_signatures(palette, document, block),
        is_binary(key),
        reduce: %{} do
      acc -> Map.put_new(acc, {id, path, expected}, key)
    end
  end

  # A declared type reads as its label and everything else reads as it always
  # did, quoted the way `inspect/1` quoted it - so an opaque string a host
  # carries and `:unknown` are unchanged, and only a name the datamodel
  # document actually declares is rewritten.
  @spec named(StatifierDatamodel.Declarations.t(), Environment.type_expr() | :unknown) ::
          String.t()
  defp named(_declarations, :unknown), do: inspect(:unknown)

  defp named(declarations, spelling),
    do: inspect(Environment.type_label(declarations, spelling))

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

  # -- Between Structure and Chart-use: the shelf leaves the tree ------------

  # ADR-0002's amendment of 2026-08-31, section G9a: the shelf is removed
  # from the root's child list before anything reads sequencing. ADR-0004's
  # amendment of the same date, section D1, is what that buys - the Emit
  # stage does not call `emit/2` on the shelf or on anything under it, so a
  # shelved block type is never asked rather than emitting-and-discarded,
  # `StateId` mints no id for any of them and the provenance map carries no
  # entry (D2).
  #
  # It runs after Structure and before everything downstream of it. Order
  # against Structure is the load-bearing half: that stage walks the
  # *document* rather than this tree, so a parked fragment's own internal
  # seams, arity and kind admission are all still checked while it is
  # parked (ADR-0003's amendment of this date, A2). Order against Chart-use
  # is not load-bearing today - that stage reads only the compile options -
  # and it sits before it anyway, because D1's claim is about the contents
  # contributing nothing to anything, not to the emitter specifically.
  #
  # Structure has already run and stopped the pipeline on a misplaced or
  # duplicated shelf, so any shelf still standing here is a direct child of
  # the root's `body` and there is at most one.
  #
  # The Config stage has already run over the whole document, including
  # every block on the shelf, which is G9c: an author who parks a
  # half-configured fragment is still told so.
  @spec elide_shelf(Resolved.t()) :: {Resolved.t(), [Finding.t()]}
  defp elide_shelf(%Resolved{slots: slots} = node) do
    {kept, shelves} =
      Enum.map_reduce(slots, [], fn {name, children}, found ->
        {shelved, flow} = Enum.split_with(children, &shelf_node?/1)
        {{name, flow}, found ++ shelved}
      end)

    {%{node | slots: kept}, Enum.flat_map(shelves, &drafts_warning/1)}
  end

  @spec shelf_node?(Resolved.t()) :: boolean()
  defp shelf_node?(%Resolved{block: block}), do: Shelf.shelf?(block)

  # D4: one finding per document, on the shelf, when the shelf's `body` is
  # non-empty. One per fragment would make the warning's loudness a function
  # of how much the author had parked, which is backwards - a well-used
  # shelf is not a worse document than a lightly-used one. An empty shelf
  # mints nothing, which with D1's byte identity makes it completely
  # invisible to every consumer of a compile.
  #
  # `fault: :author` is passed rather than left to the stage default, and
  # both new warnings do the same. Decision 9's split reads an `:emit`
  # finding with no `config_key` as `:package`, which is right for
  # `shadowed_finding/2` - no document edit fixes a compile call. It is
  # wrong for these two: emptying the shelf and filling the gap are both
  # document edits, and D4's table says `:author` for exactly that reason.
  @spec drafts_warning(Resolved.t()) :: [Finding.t()]
  defp drafts_warning(%Resolved{block: %Block{id: id}, slots: slots}) do
    if Enum.any?(slots, fn {_name, children} -> children != [] end) do
      [
        Finding.new(
          :emit,
          {:draft_blocks_present, id},
          "this document has parked work in it: the drafts shelf holds fragments that " <>
            "are not in the flow, and nothing in it is compiled",
          block_id: id,
          severity: :warning,
          fault: :author
        )
      ]
    else
      []
    end
  end

  # D4's mirror image: one per marker, because each one is a distinct gap at
  # a distinct place in the flow and an author fixing them needs to be told
  # about each. Walked over the *pruned* tree, so a `core.placeholder`
  # parked on the shelf warns about nothing - it is not a gap in the flow,
  # it is a fragment that is not in the flow at all.
  @spec marker_warnings(Resolved.t()) :: [Finding.t()]
  defp marker_warnings(%Resolved{block: block, slots: slots}) do
    own = if Shelf.marker?(block), do: [marker_warning(block)], else: []

    own ++
      Enum.flat_map(slots, fn {_name, children} -> Enum.flat_map(children, &marker_warnings/1) end)
  end

  # G10b fixes that this package never otherwise reads `note`; carrying it
  # here is the one thing it is for, so the panel says what the author said
  # the gap was for.
  @spec marker_warning(Block.t()) :: Finding.t()
  defp marker_warning(%Block{id: id, config: config}) do
    Finding.new(
      :emit,
      {:placeholder_block, id},
      "a placeholder marks a step left unwritten here" <> note_phrase(Map.get(config, "note")),
      block_id: id,
      severity: :warning,
      fault: :author
    )
  end

  @spec note_phrase(term()) :: String.t()
  defp note_phrase(note) when is_binary(note) and note != "", do: ~s(: "#{note}")
  defp note_phrase(_note), do: ""

  # ADR-0010's Note of 2026-09-02, the operator's RQ-026-6 ruling, option
  # (c): the one advisory this record asks for, and the whole of what the
  # ruling changes. The compiled bytes are untouched - decision 1's "first
  # block of the group's `body` slot" convention stands for both group
  # types and no block type gains a key - so this pass is a read of the
  # resolved tree and nothing else.
  #
  # ## The shape, and why exactly this one
  #
  # A delayed `core.send` at the **head** of a `core.resumable_group`'s
  # `body`, and a `core.on_event` on that same group's `interrupts` rail
  # whose `outcome` is `resume`. Decision 3's behaviour 2 is the
  # consequence: the resume handler's transition exits the body region,
  # which fires the `<cancel>` `StatifierBlocks.Compiler.Cancels` emitted
  # in that region's `<onexit>`, and the history re-entry restores the
  # step the group was interrupted in rather than the head that armed the
  # deadline. Nothing re-arms, so the group runs on with no deadline at
  # all.
  #
  # A plain `core.group` is silent because it has no history to re-enter
  # through - decision 3's behaviour 1, where the deadline survives the
  # resume because an internal resume exits neither the group nor its
  # body region. A rail with no `resume` handler is silent because the
  # abandon path's lifetime is correct for free (decision 3 again). Both
  # silences are the ruling's own words, not an optimization.
  #
  # ## One warning per group
  #
  # D4's reasoning for the shelf applies unchanged: a group with two
  # resume handlers is not a worse document than one with a single
  # handler, and a finding whose loudness tracks the rail's length is
  # noise. The anchor is the **group**, not the send: the group is the
  # block that owns both halves of the shape, and it is the block one of
  # the two escapes asks the author to change.
  #
  # `severity: :warning` with no `config_key` maps to the `:lint` source
  # under ADR-0005 decision 11's rule 2 (see
  # `StatifierBlocks.Finding.from_compiler/2`), which is where an advisory
  # belongs and what renders it in the neutral chrome rather than the
  # error family. `fault: :author` for `drafts_warning/1`'s reason: both
  # escapes are document edits.
  #
  # It is deliberately **not** added to `StatifierBlocks.Compiler.Finding`'s
  # stage table, whose column is "Errors it produces" - the three warning
  # codes the `:emit` stage already raises are absent from that row for the
  # same reason. `sb-1m2`'s complaint about that row is about a missing
  # *error* code and is not touched here.
  @spec deadline_warnings(Resolved.t()) :: [Finding.t()]
  defp deadline_warnings(%Resolved{module: module, block: block, slots: slots}) do
    own =
      if module == ResumableGroup and deadline_lost_on_resume?(slots),
        do: [deadline_warning(block)],
        else: []

    own ++
      Enum.flat_map(slots, fn {_name, children} ->
        Enum.flat_map(children, &deadline_warnings/1)
      end)
  end

  @spec deadline_lost_on_resume?([{Block.slot_name(), [Resolved.t()]}]) :: boolean()
  defp deadline_lost_on_resume?(slots) do
    armed_head?(slot_children(slots, "body")) and
      resumes?(slot_children(slots, "interrupts"))
  end

  @spec slot_children([{Block.slot_name(), [Resolved.t()]}], Block.slot_name()) :: [Resolved.t()]
  defp slot_children(slots, name) do
    case List.keyfind(slots, name, 0) do
      {^name, children} -> children
      nil -> []
    end
  end

  # "Delayed" is "the key holds a non-empty string", not "the string parses
  # as a duration": the Config stage has already run over the whole
  # document and stops the pipeline on a `delay` that is neither empty nor
  # a duration (`StatifierBlocks.Core.Send.validate_config/1`), so any
  # delay still standing here is one the compile accepted. Re-parsing it
  # would be a second opinion on a question already answered.
  @spec armed_head?([Resolved.t()]) :: boolean()
  defp armed_head?([%Resolved{module: Send, block: %Block{config: config}} | _rest]),
    do: delayed?(Map.get(config, "delay"))

  defp armed_head?(_children), do: false

  @spec delayed?(term()) :: boolean()
  defp delayed?(delay) when is_binary(delay), do: String.trim(delay) != ""
  defp delayed?(_delay), do: false

  @spec resumes?([Resolved.t()]) :: boolean()
  defp resumes?(children) do
    Enum.any?(children, fn
      %Resolved{module: OnEvent, block: %Block{config: config}} ->
        Map.get(config, "outcome") == "resume"

      %Resolved{} ->
        false
    end)
  end

  @spec deadline_warning(Block.t()) :: Finding.t()
  defp deadline_warning(%Block{id: id}) do
    Finding.new(
      :emit,
      {:deadline_lost_on_resume, id},
      "the deadline at the head of this group's body is armed once only: a resume " <>
        "interrupt exits the body region, which cancels the delayed send, and the " <>
        "history re-entry restores the interrupted step rather than the head that " <>
        "armed it, so after the first resume the group runs on with no deadline. Arm " <>
        "the deadline outside the group, or use a core.group.",
      block_id: id,
      severity: :warning,
      fault: :author
    )
  end

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
  defp emit(%Resolved{block: block, module: ref, slots: slots}, document_id) do
    with {:ok, compiled_slots} <- emit_slots(slots, document_id),
         :ok <- validate_outcomes(block, ref) do
      context = Context.new(block.id, document_id, summaries(slots))

      case Palette.call(ref, :emit, [block, context], :never) do
        {:ok, %Emission{} = emission} ->
          # ADR-0010 decision 8: the rail scopes the interrupt pair. This is
          # the first point in the pipeline holding both the parent's own
          # emission - which says where each child sits - and the children's
          # compiled subtrees, so it is where the raises inside a rail are
          # salted with the group's state id.
          compiled = Interrupts.scope(emission, children(compiled_slots))

          emission
          |> Cancels.arm(compiled)
          |> attribute(block, compiled)

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
  @spec attribute(Emission.t(), Block.t(), [{Block.id(), Emission.t()}]) ::
          {:ok, Emission.t()} | {:error, [Finding.t()]}
  defp attribute(emission, block, compiled_children) do
    known = MapSet.new([block.id | Enum.map(compiled_children, &elem(&1, 0))])

    case Attribution.stamp(emission, block.id, known) do
      {:ok, stamped} ->
        splice(stamped, compiled_children, block)

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
  @spec splice(Emission.t(), [{Block.id(), Emission.t()}], Block.t()) ::
          {:ok, Emission.t()} | {:error, [Finding.t()]}
  defp splice(emission, compiled_children, block) do
    available = Map.new(compiled_children)

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
  # One exception, added 2026-09-06 with the campaign-033 failure seam and
  # noted on both records: a final for a **failure-classed** outcome - one
  # `BlockType.failure_outcomes/2` names - carries a reserved `<donedata>`
  # `<param>` under **both** options. The key is
  # `statifier_persistence:run_status` and its value is `'failed'`, spelled
  # here exactly as `statifier_persistence`'s ADR-0008 amendment of
  # 2026-09-06 fixes it, and a durable stepper reads it to decide that the
  # run failed. Under `:terminate` it is the only `<param>` the final
  # carries, because the root shape still says nothing about which outcome
  # was reached; under `:child_use` it rides beside the `outcome` param
  # that shape already emits. The colon separator is the record's: a dotted
  # key would be indistinguishable from a nested map in a predicator path
  # expression, and a colon is not a predicator identifier character.
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
  defp completion_finals(
         %Resolved{block: block, module: module} = node,
         emission,
         prefix,
         donedata?
       ) do
    failures = BlockType.failure_outcomes(module, block.config)
    declared = if donedata?, do: declared_params(module, block.config), else: []

    pairs =
      module
      |> BlockType.outcome_names(block.config)
      |> Enum.flat_map(
        &completion_outcome(block.id, &1, prefix, donedata?, &1 in failures, declared)
      )

    transitions = Enum.map(pairs, &elem(&1, 0))
    finals = Enum.map(pairs, &elem(&1, 1))

    {catches, failed} = propagation(node, prefix, donedata?, declared)

    {%{emission | children: emission.children ++ transitions ++ catches}, finals ++ failed}
  end

  @spec completion_outcome(
          Block.id(),
          String.t(),
          String.t(),
          boolean(),
          boolean(),
          [Emission.t()]
        ) :: [{Emission.t(), Emission.t()}]
  defp completion_outcome(root_id, outcome, prefix, donedata?, failure?, declared) do
    with {:ok, final_id} <- StateId.state_id(root_id, prefix <> outcome),
         {:ok, transition} <-
           stamp_completion(completion_transition(root_id, outcome, final_id), root_id),
         {:ok, final} <-
           stamp_completion(
             completion_final(final_id, outcome, donedata?, failure?, declared),
             root_id
           ) do
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

  @spec completion_final(StateId.t(), String.t(), boolean(), boolean(), [Emission.t()]) ::
          Emission.t()
  defp completion_final(final_id, outcome, donedata?, failure?, declared) do
    params =
      if(donedata?, do: [outcome_param(outcome)], else: []) ++
        if(failure?, do: [run_status_param()], else: []) ++
        declared

    case params do
      [] -> Emission.element("final", [{"id", final_id}])
      params -> Emission.element("final", [{"id", final_id}], [donedata(params)])
    end
  end

  @spec donedata([Emission.t()]) :: Emission.t()
  defp donedata(params), do: Emission.element("donedata", [], params)

  @spec outcome_param(String.t()) :: Emission.t()
  defp outcome_param(outcome) do
    Emission.element("param", [{"expr", "'" <> outcome <> "'"}, {"name", @outcome_param_name}])
  end

  # ADR-0004's C1 as widened on 2026-09-06, from ADR-0013 decision 3: the
  # root block type's optional `donedata_type/1` declares fields, and each
  # one is a `<param>` reading the datamodel path the declaration names.
  #
  # They come **after** both compiler-minted params - the `outcome` param
  # and, on a failure-classed outcome, the reserved run-status one - so a
  # root type declaring nothing compiles to the bytes it compiled to
  # before the callback existed, and a failure-classed final does not have
  # its two existing params reordered by a declaration that arrives later.
  # Declaration order is preserved for decision 6's reason: sorting the
  # list would move a host's compiled bytes.
  #
  # They are emitted on **every** top-level final, failure-classed
  # included, because `donedata_type/1` is a pure function of the root
  # block's config and the compiler classes outcomes rather than runs. On
  # the failure arm they do not thereby reach a parent: ADR-0009's Note of
  # 2026-09-06 has the driver answer the invocation with the run's failure
  # rather than with done data, so the collected element carries no
  # `"donedata"` key at all. The bytes are minted and unread there, which
  # is a cost in the compiled document and nothing else - and a document
  # compiled for use as a child is also one a host may run directly, where
  # its `<donedata>` is read by whoever invoked it.
  #
  # Only under `:child_use`. The `:terminate` finals carry no `<donedata>`
  # at all, so there is no boundary for a declared field to cross;
  # `completion_finals/4`'s caller is where that is decided.
  @spec declared_params(module(), Block.config()) :: [Emission.t()]
  defp declared_params(module, config) do
    module
    |> BlockType.donedata_type(config)
    |> Enum.map(fn %{name: name, path: path} ->
      Emission.element("param", [{"expr", path}, {"name", name}])
    end)
  end

  # The failure seam's reserved key, spelled as `statifier_persistence`'
  # ADR-0008 amendment of 2026-09-06 fixes it: one key, one closed value.
  @spec run_status_param() :: Emission.t()
  defp run_status_param do
    Emission.element(
      "param",
      [{"expr", "'" <> @run_status_failed <> "'"}, {"name", @run_status_key}]
    )
  end

  @spec stamp_completion(Emission.t(), Block.id()) ::
          {:ok, Emission.t()} | {:error, {:unknown_attribution, Block.id()}}
  defp stamp_completion(emission, root_id) do
    Attribution.stamp(emission, root_id, MapSet.new([root_id]))
  end

  # -- Stage 5a-bis: the nested-to-root failure catch --------------------------

  # ADR-0002's amendment of 2026-09-06, section 4. Under the same two
  # options the completion finals sit behind, and nothing at all outside
  # them: an outcome a block below the root declares, that the block's own
  # type classes as a failure, and that the document did not handle,
  # reaches the document's own ending instead of being selected by
  # nothing.
  #
  # **Handled** is a property of the failing block, not of the container
  # above it: the block's type declares an `on_<outcome>` slot for that
  # outcome and the document put a child in it. Nothing else in this
  # package counts, because nothing else looks at a child's outcome -
  # `Emit.chain/2` wires a container's children on `done.state.<child>`,
  # which fires for every final a child can reach, and no core container
  # emits a transition selected by `done.outcome.<child>.<outcome>`. A
  # container that runs a step and then runs the next one has decided
  # nothing about how the step ended; the author who filled in "if it
  # fails" has.
  #
  # One shared final rather than one per pair: what a durable stepper
  # reads is that the run failed, and *which* block failed is in the trace
  # and in the provenance map at higher fidelity than a final id could
  # carry. It also keeps the added bytes proportional to "does this
  # document have any unhandled failure at all" rather than to the number
  # of blocks in it.
  #
  # Attribution splits, following decision 5 and `Emit.chain/2`'s rule
  # rather than the completion finals': each transition is stamped to
  # **the failing block**, because what happens after the authorize step
  # fails is a fact about the authorize step, and the shared final is
  # stamped to the root block, the only block the document's own ending is
  # a fact about. The provenance map stays total over the added bytes.
  #
  # The transitions reach the root before the container advances, and
  # nothing here arranges that: entering a `<final>` runs its `onentry` -
  # where `Emit.final/1` puts the raise of
  # `done.outcome.<state id>.<outcome>` - and only then is
  # `done.state.<parent>` generated. The internal queue is FIFO, so the
  # outcome event is selected first, the root's transition exits the root
  # state, and the container's pending `done.state` is selected by
  # nothing.
  @spec propagation(Resolved.t(), String.t(), boolean(), [Emission.t()]) ::
          {[Emission.t()], [Emission.t()]}
  defp propagation(%Resolved{block: %Block{id: root_id}} = node, prefix, donedata?, declared) do
    case unhandled_failures(node) do
      [] ->
        {[], []}

      pairs ->
        with {:ok, final_id} <- StateId.state_id(root_id, prefix <> @failed_role),
             {:ok, final} <-
               stamp_completion(
                 completion_final(final_id, @propagated_outcome, donedata?, true, declared),
                 root_id
               ),
             {:ok, transitions} <- propagation_transitions(pairs, final_id) do
          {transitions, [final]}
        else
          _refused -> {[], []}
        end
    end
  end

  # The walk starts **below** the root: the root block's own outcomes are
  # the document's answer and its completion finals already report them,
  # including when its own `on_<outcome>` slot is occupied.
  @spec unhandled_failures(Resolved.t()) :: [{Block.id(), StateId.t(), String.t()}]
  defp unhandled_failures(%Resolved{slots: slots}), do: child_failures(slots)

  @spec child_failures([{Block.slot_name(), [Resolved.t()]}]) ::
          [{Block.id(), StateId.t(), String.t()}]
  defp child_failures(slots) do
    Enum.flat_map(slots, fn {_name, children} -> Enum.flat_map(children, &node_failures/1) end)
  end

  # Document pre-order: the block itself, then its slots in `slots/1`
  # declaration order. An outcome the class names that `outcomes/1` does
  # not declare contributes nothing, which is the resolver's own posture
  # toward a malformed return.
  @spec node_failures(Resolved.t()) :: [{Block.id(), StateId.t(), String.t()}]
  defp node_failures(%Resolved{block: block, module: module, slots: slots} = node) do
    failures = BlockType.failure_outcomes(module, block.config)

    own =
      module
      |> BlockType.outcome_names(block.config)
      |> Enum.filter(&(&1 in failures and unhandled?(node, &1)))
      |> Enum.map(&{block.id, StateId.state_id(block.id), &1})

    own ++ child_failures(slots)
  end

  @spec unhandled?(Resolved.t(), String.t()) :: boolean()
  defp unhandled?(%Resolved{slots: slots}, outcome) do
    case List.keyfind(slots, "on_" <> outcome, 0) do
      {_name, [_child | _rest]} -> false
      _undeclared_or_empty -> true
    end
  end

  # External, like the completion transitions beside them and for the same
  # reason: the point is to leave the root state for a sibling final.
  # `<transition>` with no `type` attribute is external in SCXML, so the
  # attribute is absent rather than spelled out.
  @spec propagation_transitions([{Block.id(), StateId.t(), String.t()}], StateId.t()) ::
          {:ok, [Emission.t()]} | {:error, {:unknown_attribution, Block.id()}}
  defp propagation_transitions(pairs, final_id) do
    pairs
    |> Enum.reduce_while({:ok, []}, fn {block_id, state_id, outcome}, {:ok, acc} ->
      "transition"
      |> Emission.element([
        {"event", StateId.outcome_event(state_id, outcome)},
        {"target", final_id}
      ])
      |> Attribution.stamp(block_id, MapSet.new([block_id]))
      |> case do
        {:ok, stamped} -> {:cont, {:ok, [stamped | acc]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      {:error, _reason} = error -> error
    end
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

  # -- Stage 5a'-bis: the declared-summary refusal ----------------------------

  # ADR-0013 decision 2 and ADR-0002's Note of 2026-09-06: two `<param>`
  # names are the compiler's - `outcome`, C1's, and the failure seam's
  # reserved run-status key - and a `donedata_type/1` entry colliding with
  # either is an `:invalid_donedata_field` Emit finding against the root
  # block rather than a silently shadowed param. A name outside the bare
  # lowercase identifier shape the record fixes is the same finding: the
  # `<param>` it would mint is not a name this package mints anywhere else.
  #
  # It runs only under `:child_use`, because that is the only compile that
  # emits the declared params at all - a `:terminate` final carries no
  # `<donedata>`, so there is no param there to shadow (ADR-0004's
  # 2026-09-06 amendment). Like the refusal above it, it is not a new
  # pipeline stage: decision 10's table is unchanged, and it runs before
  # Emit only because there is nothing worth emitting once it fires.
  @spec donedata_stage(Resolved.t(), [option()]) :: :ok | {:error, [Finding.t()]}
  defp donedata_stage(%Resolved{block: block, module: module}, opts) do
    if Keyword.get(opts, :child_use, false) do
      module
      |> BlockType.donedata_type(block.config)
      |> Enum.reject(&declarable_param?/1)
      |> Enum.map(&donedata_finding(&1, block.id))
      |> case do
        [] -> :ok
        findings -> {:error, findings}
      end
    else
      :ok
    end
  end

  @spec declarable_param?(BlockType.donedata_field()) :: boolean()
  defp declarable_param?(%{name: name}) do
    Config.identifier?(name) and name not in [@outcome_param_name, @run_status_key]
  end

  @spec donedata_finding(BlockType.donedata_field(), Block.id()) :: Finding.t()
  defp donedata_finding(%{name: name}, root_id) do
    Finding.new(
      :emit,
      {:invalid_donedata_field, name},
      ~s(declares the done-data field "#{name}", which is either one of the two names the ) <>
        ~s(compiler mints - "#{@outcome_param_name}" and "#{@run_status_key}" - or not a ) <>
        "bare lowercase identifier",
      block_id: root_id
    )
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
         warnings: emit_warnings ++ warnings ++ lint(emitted, opts) ++ candidate_lint(node, opts)
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

  # The `:field_candidates` lint, on exactly `:known_invoke_types`' terms:
  # opt-in, and a **warning** for every value a host's own closed list does
  # not offer. Never an error, for the reason that one is never an error -
  # which values exist is a property of the deployment the document runs in,
  # so any list handed to a compile is one deployment's belief rather than a
  # rule about the document, and `validate_config/1` is the only authority on
  # a value (ADR-0002 decision 7).
  #
  # An open list - `{:open, choices}` - reports nothing at all. Its whole
  # claim is that these are values and not the values, so a value outside it
  # is not even a remark.
  @spec candidate_lint(Resolved.t(), keyword()) :: [Finding.t()]
  defp candidate_lint(node, opts) do
    case Keyword.fetch(opts, :field_candidates) do
      {:ok, offered} when is_map(offered) and offered != %{} -> candidate_findings(node, offered)
      _no_lists_supplied -> []
    end
  end

  @spec candidate_findings(Resolved.t(), map()) :: [Finding.t()]
  defp candidate_findings(%Resolved{block: block, module: ref, slots: slots}, offered) do
    own =
      ref
      |> Palette.call(:config_schema, [block.config], [])
      |> Enum.flat_map(&candidate_finding(block, &1, offered))

    children =
      Enum.flat_map(slots, fn {_slot, nodes} ->
        Enum.flat_map(nodes, &candidate_findings(&1, offered))
      end)

    own ++ children
  end

  @spec candidate_finding(Block.t(), BlockType.field_decl(), map()) :: [Finding.t()]
  defp candidate_finding(%Block{} = block, decl, offered) do
    with choices when is_list(choices) <- Map.get(offered, {block.type, decl.key}),
         {:ok, value} when is_binary(value) and value != "" <-
           BlockType.fetch_value(block.config, BlockType.value_path(decl)),
         false <- Enum.any?(choices, fn {choice, _label} -> choice == value end) do
      [
        Finding.new(
          :config,
          {:value_not_offered, decl.key, value},
          ~s(#{value} is not one of the values offered for #{decl.label}),
          block_id: block.id,
          config_key: decl.key,
          severity: :warning
        )
      ]
    else
      _offered_or_open_or_unset -> []
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

  # The hash's triples carry the entry's MODULE, never the entry: a data
  # composite's `state` is its declaration, and inspecting it here would
  # make `palette_hash/1` a commitment to a declaration's text, which
  # `StatifierBlocks.CompilationRecord` is explicit it is not. Two data
  # composites therefore differ here by type name and version, and two
  # revisions of one declaration registered under one name at one version
  # do not - the palette-hygiene obligation that record already names, with
  # a different author.
  @spec entries(Resolved.t()) :: [{Block.type_name(), module(), pos_integer()}]
  defp entries(%Resolved{block: block, module: ref, slots: slots}) do
    [
      {block.type, module_of(ref), Palette.call(ref, :current_version, [], nil)}
      | Enum.flat_map(slots, fn {_name, children} -> Enum.flat_map(children, &entries/1) end)
    ]
  end

  @spec module_of(Palette.type_ref()) :: module()
  defp module_of({module, _state}), do: module
  defp module_of(module), do: module
end
