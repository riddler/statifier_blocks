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
  4. **Structure** - `StatifierBlocks.Assignability.validate/3`: may this
     block land in this slot, by kind tag and by data-flow type
     (ADR-0003)?
  5. **Emit** - bottom-up. Each block's `emit/2` is called with its
     children already compiled and summarized, its emission is attributed
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

  ### The Structure stage is not yet whole

  Decision 10's table names three things in this stage: slot **arity**,
  `:undeclared_slot`, and assignability. Only the third runs here.
  Palette-aware arity and undeclared-slot validation is **`sb-da9`'s**,
  filed and unworked; this module draws the seam and leaves it empty
  rather than growing a second implementation of ADR-0002 decision 6's
  rules beside the one that bead will ship. Until it lands the pipeline
  simply never visits a slot `slots/1` did not declare, so an undeclared
  slot's blocks are absent from the emission rather than misplaced in it -
  which is a silent drop, and exactly what `sb-da9` exists to make loud.

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
  """

  alias Statifier.Machine.Identity

  alias StatifierBlocks.{
    Assignability,
    Block,
    CompilationRecord,
    Compiled,
    Document,
    Emission,
    Palette,
    Provenance
  }

  alias StatifierBlocks.Compiler.{
    Attribution,
    Chart,
    Context,
    Finding,
    InvokeTypes,
    Serializer,
    StateId
  }

  @scxml_ns "http://www.w3.org/2005/07/scxml"

  # Decision 6's third determinism input. It is the package version, and it
  # moves whenever a change to this package moves generated bytes - which,
  # since a Hex release is the only way a host's bytes change, is every
  # release. `compiler_version_test.exs` asserts it against `mix.exs` so the
  # two cannot drift silently.
  @compiler_version "0.1.0"

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
  `:entry_type` is ADR-0003 decision 4's caller-supplied context. See the
  moduledoc.
  """
  @type option ::
          {:known_invoke_types, Enumerable.t()}
          | {:entry_type, Assignability.type_expr() | :unknown}

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
         {:ok, emission} <- emit_stage(node, document.id) do
      chart_stage(document, node, emission, opts)
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

  # Assignability only. Slot arity and `:undeclared_slot` are `sb-da9`'s -
  # see the moduledoc's seam note. This stage runs over the *document*
  # rather than the resolved tree because `Assignability.validate/3` is
  # the one implementation both the editor and the compiler consult
  # (ADR-0003 decision 6), and the editor has no resolved tree.
  @spec structure_stage(Document.t(), Palette.t(), keyword()) :: :ok | {:error, [Finding.t()]}
  defp structure_stage(document, palette, opts) do
    case Assignability.validate(palette, document, assignability_context(opts)) do
      :ok -> :ok
      {:error, findings} -> {:error, Enum.map(findings, &structure_finding/1)}
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

  # -- Stage 5: emit ---------------------------------------------------------

  @spec emit_stage(Resolved.t(), Document.id()) :: {:ok, Emission.t()} | {:error, [Finding.t()]}
  defp emit_stage(node, document_id) do
    with {:ok, emission} <- emit(node, document_id) do
      {:ok, scxml_element(node, document_id, emission)}
    end
  end

  @spec emit(Resolved.t(), Document.id()) :: {:ok, Emission.t()} | {:error, [Finding.t()]}
  defp emit(%Resolved{block: block, module: module, slots: slots}, document_id) do
    with {:ok, compiled_slots} <- emit_slots(slots, document_id) do
      context = Context.new(block.id, document_id, summaries(compiled_slots))

      case module.emit(block, context) do
        {:ok, %Emission{} = emission} -> attribute(emission, block, compiled_slots)
        {:error, reason} -> {:error, emit_findings(block, reason)}
      end
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

  @spec summaries([{Block.slot_name(), [{Block.id(), Emission.t()}]}]) ::
          %{optional(Block.slot_name()) => [Context.child_summary()]}
  defp summaries(compiled_slots) do
    Map.new(compiled_slots, fn {name, children} ->
      {name, Enum.map(children, fn {block_id, _emission} -> Context.summary(block_id) end)}
    end)
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
  @spec scxml_element(Resolved.t(), Document.id(), Emission.t()) :: Emission.t()
  defp scxml_element(%Resolved{block: %Block{id: root_id}}, document_id, root_emission) do
    element =
      Emission.element(
        "scxml",
        [
          {"initial", StateId.state_id(root_id)},
          {"name", document_id},
          {"version", "1.0"},
          {"xmlns", @scxml_ns}
        ],
        [root_emission]
      )

    %{element | owner: Provenance.owner(root_id)}
  end

  # -- Stage 6: chart --------------------------------------------------------

  @spec chart_stage(Document.t(), Resolved.t(), Emission.t(), keyword()) ::
          {:ok, Compiled.t()} | {:error, [Finding.t()]}
  defp chart_stage(%Document{} = document, node, emission, opts) do
    {scxml, provenance} = Serializer.serialize(emission)
    emitted = InvokeTypes.collect(emission)

    with {:ok, warnings} <- Chart.validate(scxml, provenance, document) do
      {:ok,
       %Compiled{
         scxml: scxml,
         provenance: provenance,
         record: record(document, node, scxml),
         invoke_types: InvokeTypes.types(emitted),
         warnings: warnings ++ lint(emitted, opts)
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
