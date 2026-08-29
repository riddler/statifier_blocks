defmodule StatifierBlocks.Finding do
  @moduledoc """
  A finding as the editor renders it: normalized for presentation, and the
  anchor routes it (ADR-0005 decision 11).

  Findings arrive from sources with different shapes - `validate_config/1`
  returns `{key, message}` pairs, arity and undeclared-slot violations are
  about a slot, resolution failures are about a block - so this struct
  normalizes them to one shape with one routing mechanism: the `anchor`.
  `StatifierBlocks.ViewModel` is what actually does the routing; this
  module owns only the shape.

  ## Two `Finding` modules, on purpose

  `StatifierBlocks.Compiler.Finding` already exists, and it is a
  **different** struct for a **different** layer: it carries
  `stage`/`fault`/`code`/`reason` for the compile pipeline (ADR-0004
  decision 10), keyed to the stage that produced it and to whether the
  problem is the author's or the package's. This module,
  `StatifierBlocks.Finding`, is the **presentation** finding ADR-0005
  decision 11 specifies: `anchor`/`severity`/`source`/`message`, keyed to
  where in the rendered tree the finding shows up. Neither is a
  degenerate case of the other, neither wraps the other, and `from_compiler/2`
  is what adapts one into the other - deliberately in this module rather
  than in `StatifierBlocks.Compiler.Finding`, because the presentation
  layer may depend on the compiler layer, never the reverse. If you are
  about to import this module and get `stage`, `fault`, `code`, or
  `reason` back, you have the wrong one - reach for
  `StatifierBlocks.Compiler.Finding` instead.
  """

  alias StatifierBlocks.Block

  @typedoc """
  The whole routing mechanism (ADR-0005 decision 11). A `:config` finding
  renders inline beneath its field, a `:slot` finding on that slot's
  header, a `:block` finding on the block's chrome.
  """
  @type anchor ::
          {:config, Block.id(), key :: String.t()}
          | {:slot, Block.id(), Block.slot_name()}
          | {:block, Block.id()}

  @typedoc "Where this finding's rule lives. See `StatifierBlocks.ViewModel`'s moduledoc."
  @type source :: :config | :arity | :assignability | :resolution | :lint

  @type t :: %__MODULE__{
          severity: :error | :warning,
          anchor: anchor(),
          source: source(),
          message: String.t()
        }

  @enforce_keys [:anchor, :source, :message]
  defstruct [:anchor, :source, :message, severity: :error]

  @doc """
  Builds a finding, in the shape `StatifierBlocks.Compiler.Finding.new/4`
  already uses: the fixed positional arguments first, `message` last among
  them, and everything else in `opts`.

  `opts` carries `:severity`, defaulting to `:error` - the default every
  source but `:lint` uses (ADR-0005 decision 11).
  """
  @spec new(anchor(), source(), String.t(), keyword()) :: t()
  def new(anchor, source, message, opts \\ []) do
    %__MODULE__{
      anchor: anchor,
      source: source,
      message: message,
      severity: Keyword.get(opts, :severity, :error)
    }
  end

  @typedoc """
  Why `from_compiler/2` refused to adapt a
  `StatifierBlocks.Compiler.Finding`.

  `:unanchorable` - the finding names no block (`block_id` is `nil`). The
  anchor is the whole routing mechanism (ADR-0005 decision 11), so a
  finding that names no block cannot be routed. Only the `:document` stage
  produces these today (`Document.validate/1` failing).

  `:no_presentation_source` - the finding's stage names no source in
  decision 11's enum: `:document`, `:emit`, and `:chart` at `:error`
  severity all fall here. Decision 11's source enum has no bucket for an
  error raised against generated SCXML or against the document envelope,
  and the adapter refuses rather than lying about where the rule lives.
  This is a known gap in decision 11's source set, not a bug in this
  adapter.
  """
  @type from_compiler_error ::
          {:unanchorable, StatifierBlocks.Compiler.Finding.t()}
          | {:no_presentation_source, StatifierBlocks.Compiler.Finding.t()}

  @doc """
  Adapts one `StatifierBlocks.Compiler.Finding` (ADR-0004 decision 10) into
  this module's presentation shape (ADR-0005 decision 11).

  The presentation layer may depend on the compiler layer, never the
  reverse - a host that only compiles must not drag presentation concerns
  in - so this adapter lives here, in `StatifierBlocks.Finding`, and not in
  `StatifierBlocks.Compiler.Finding`. `Compiler.Finding` is one more
  differently-shaped source this module's moduledoc already promises to
  normalize.

  ## Anchor (mechanical)

    * `block_id` and `config_key` both present -> `{:config, block_id, config_key}`
    * `block_id` present, `config_key` `nil` -> `{:block, block_id}`
    * `block_id` `nil` (any `config_key`) -> refused, `{:unanchorable, finding}`

  `{:slot, id, name}` is never produced: `Compiler.Finding` carries no slot
  name, so there is nothing to build one from. This is a known gap:
  `sb-da9`'s slot-shaped structural findings (`:undeclared_slot`, slot
  arity) will need either a slot-bearing compiler finding or this seam
  widened (the `:source` override below is the closest existing hook) -
  that is future work, not built here.

  ## Source (by rule, never by `code`)

  New codes arrive continuously (`sb-da9` adds `:undeclared_slot` and
  slot-arity codes; other emitters land in this campaign), so the mapping
  must never switch on `code` - an unknown code has to map correctly by
  construction. In order:

    1. `opts[:source]`, when given, wins outright. See "the `:source`
       override" below.
    2. Severity that is not `:error` -> `:lint`. Decision 11 says every
       source but `:lint` produces `:error`, so a finding that is not an
       error cannot honestly be any other source. This is also what makes
       an `:info` severity representable end to end under the 2026-08-29
       amendment's `11b` (accepted; only `:lint` may produce one): a
       pass-through severity composed with this rule gets there for free.
    3. Otherwise by stage: `:config` -> `:config`, `:resolve` -> `:resolution`,
       `:structure` -> `:assignability`.
    4. Any other stage (`:document`, `:emit`, `:chart` at `:error`) ->
       refused, `{:no_presentation_source, finding}`.

  The anchor refusal takes priority over the source refusal: a block-less
  finding is `{:unanchorable, _}` even when its stage or severity would
  otherwise have mapped to a source, because there is nowhere to route it
  regardless of what it is about.

  ## Severity (pass-through, not a two-clause case)

  `severity` passes through unchanged. An `:error`/`:warning` case would go
  stale the moment `Compiler.Finding`'s severity set widens to admit
  `:info` for advisory findings - decision 11's 2026-08-29 amendment
  accepted that severity, and `11b` reserves it to `:lint`. Identity
  composed with source rule 2 above already gives the right answer for
  that day with no edit here, which is why the mapping does not enumerate
  the severities it knows about today.

  ## Lossy on purpose

  `stage`, `fault`, `code` and `reason` have no field in decision 11's
  four-field shape and are dropped by this adaptation. A caller that needs
  the fault split keeps the `Compiler.Finding` alongside the adapted one.

  ## The `:source` override

  `opts[:source]` lets a caller that knows better than the default rule
  say so explicitly - the seam `sb-da9`'s slot-shaped findings may
  eventually need. It is used exactly as given: it is already typed
  `source()` at the call site, so there is nothing left to validate.
  """
  @spec from_compiler(StatifierBlocks.Compiler.Finding.t(), keyword()) ::
          {:ok, t()} | {:error, from_compiler_error()}
  def from_compiler(%StatifierBlocks.Compiler.Finding{} = finding, opts \\ []) do
    with {:ok, anchor} <- anchor_from_compiler(finding),
         {:ok, source} <- source_from_compiler(finding, opts) do
      {:ok,
       %__MODULE__{
         anchor: anchor,
         source: source,
         message: finding.message,
         severity: finding.severity
       }}
    end
  end

  @doc """
  Adapts every finding in `findings`, partitioning into adapted findings
  (in input order) and every refusal paired with the `Compiler.Finding`
  that produced it (also in input order). Never silently drops a finding -
  `length(ok) + length(refused) == length(findings)` always holds - which
  is the same invariant `StatifierBlocks.ViewModel`'s routing table
  protects ("No route drops a finding").

  ## Wiring

  The real path this exists for: compile with `known_invoke_types:`, take
  the invoke-type lint off `Compiled.warnings`, adapt it, and hand the
  result to `ViewModel.build/3` as caller-supplied findings.

  ```elixir
  {:ok, compiled} =
    StatifierBlocks.Compiler.compile(document, palette, known_invoke_types: known)

  {lint_findings, _refused} = StatifierBlocks.Finding.from_compiler_all(compiled.warnings)

  view_model = StatifierBlocks.ViewModel.build(document, palette, lint_findings)
  ```

  `opts` is applied to every finding in `findings`; see `from_compiler/2`.
  """
  @spec from_compiler_all([StatifierBlocks.Compiler.Finding.t()], keyword()) ::
          {[t()], [{StatifierBlocks.Compiler.Finding.t(), from_compiler_error()}]}
  def from_compiler_all(findings, opts \\ []) when is_list(findings) do
    {ok_rev, refused_rev} =
      Enum.reduce(findings, {[], []}, fn finding, {ok_acc, refused_acc} ->
        case from_compiler(finding, opts) do
          {:ok, adapted} -> {[adapted | ok_acc], refused_acc}
          {:error, reason} -> {ok_acc, [{finding, reason} | refused_acc]}
        end
      end)

    {Enum.reverse(ok_rev), Enum.reverse(refused_rev)}
  end

  # `block_id` is the whole routing mechanism (ADR-0005 decision 11): a
  # finding that names no block cannot be anchored, and `:document` is the
  # only stage that produces one today (`Document.validate/1` failing).
  @spec anchor_from_compiler(StatifierBlocks.Compiler.Finding.t()) ::
          {:ok, anchor()} | {:error, {:unanchorable, StatifierBlocks.Compiler.Finding.t()}}
  defp anchor_from_compiler(%StatifierBlocks.Compiler.Finding{block_id: nil} = finding),
    do: {:error, {:unanchorable, finding}}

  defp anchor_from_compiler(%StatifierBlocks.Compiler.Finding{block_id: id, config_key: nil}),
    do: {:ok, {:block, id}}

  defp anchor_from_compiler(%StatifierBlocks.Compiler.Finding{block_id: id, config_key: key}),
    do: {:ok, {:config, id, key}}

  @spec source_from_compiler(StatifierBlocks.Compiler.Finding.t(), keyword()) ::
          {:ok, source()}
          | {:error, {:no_presentation_source, StatifierBlocks.Compiler.Finding.t()}}
  defp source_from_compiler(finding, opts) do
    case Keyword.fetch(opts, :source) do
      {:ok, source} -> {:ok, source}
      :error -> source_by_rule(finding)
    end
  end

  # Rule 2: a finding that is not an error cannot honestly be any source
  # but `:lint` (decision 11 - every other source produces `:error`).
  @spec source_by_rule(StatifierBlocks.Compiler.Finding.t()) ::
          {:ok, source()}
          | {:error, {:no_presentation_source, StatifierBlocks.Compiler.Finding.t()}}
  defp source_by_rule(%StatifierBlocks.Compiler.Finding{severity: severity})
       when severity != :error do
    {:ok, :lint}
  end

  # Rule 3/4: by stage, never by `code` - a `case` with a refusing
  # catch-all rather than a list of codes, so an unknown code maps
  # correctly by construction.
  defp source_by_rule(%StatifierBlocks.Compiler.Finding{stage: stage} = finding) do
    case stage do
      :config -> {:ok, :config}
      :resolve -> {:ok, :resolution}
      :structure -> {:ok, :assignability}
      _other_stage -> {:error, {:no_presentation_source, finding}}
    end
  end
end
