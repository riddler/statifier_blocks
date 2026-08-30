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

  @typedoc """
  Where this finding's rule lives. See `StatifierBlocks.ViewModel`'s
  moduledoc.

  The enum as ADR-0005 decision 11's 2026-08-30 amendments leave it:

    * `:arity` is gone (`11j`). Slot arity and undeclared-slot violations
      come through the compiler's `:structure` stage and have always
      adapted to `:assignability`; nothing ever produced `:arity`, and an
      enum value with no producer invites a presentation rule that can
      never fire. What those findings are *anchored* to is unchanged -
      still `{:slot, block_id, slot_name}` - which is what decision 11's
      prose about slots was ever describing.
    * `:compile` is new (`11h`), and it is deliberately stage-agnostic. It
      says "the compiler said so" and nothing more, so this enum does not
      grow a value every time the compiler grows a stage. The anchor still
      decides where the finding renders; the source only says where it
      came from.
  """
  @type source :: :config | :assignability | :resolution | :lint | :compile

  @typedoc """
  Three-valued since the 2026-08-29 amendment to ADR-0005 decision 11.

  `:error` says the document does not compile. `:warning` says it compiles
  and something may not behave as intended - the record's own example, an
  invoke type with no registered handler, is correct the moment the host
  registers one. `:info` says **this is worth the author's attention and
  nothing is wrong**, which is the line decision 11 could not draw before.

  Amendment `11b` reserves `:info` to the `:lint` source, and states
  honestly that no lint produces one today: it is accepted as the place a
  real advisory will land. It changes no verdict - a document whose only
  findings are `:info` is exactly as compilable as one with none, and any
  consumer gating on findings gates on `:error`, as it did before.
  """
  @type severity :: :error | :warning | :info

  @type t :: %__MODULE__{
          severity: severity(),
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
  decision 11's enum. **No input to `from_compiler/2` produces this
  today.** It was the answer for `:document`, `:emit` and `:chart` at
  `:error` severity until ADR-0005 amendment `11h` gave those a source
  (`:compile`); the amendment retains the refusal's meaning for inputs
  that are not compiler findings at all, so it stays in this union rather
  than being dropped the way `11j` dropped `:arity` from `source/0`.
  `from_compiler/2` pattern-matches a `StatifierBlocks.Compiler.Finding`,
  so there is no such input through this door yet.
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
       `:compile`, under ADR-0005 amendment `11h`. Rule 4 used to refuse
       with `{:no_presentation_source, finding}`; a compile error against
       generated SCXML or against the document envelope had no bucket in
       decision 11's enum, so the adapter refused rather than lie about
       where the rule lived. `:compile` is that bucket, and it is why an
       error the compiler raises at a stage this mapping does not name can
       now render in the editor at all - which is the half of `11h` that
       makes the document-level panel's promise ("no finding can hide")
       true for compile errors too.

  Because rule 4 no longer refuses, the anchor is the only thing that can:
  a block-less finding is `{:unanchorable, _}` even when its stage or
  severity would otherwise have mapped to a source, because there is
  nowhere to route it regardless of what it is about.

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

  `config_value_span` is dropped for the same reason and is the one drop
  that costs a consumer something visible: it is decision 9's
  sub-expression span, and an editor rendering only the adapted finding
  underlines the whole field rather than the offending sub-expression. The
  anchor has nowhere to put it - `{:config, id, key}` names a field, not a
  range inside one - so widening decision 11's shape is what it would take,
  and that is an ADR-0005 change rather than an adapter change. Until then
  the same rule applies as for the fault split: keep the
  `Compiler.Finding` alongside.

  ## The `:source` override

  `opts[:source]` lets a caller that knows better than the default rule
  say so explicitly - the seam `sb-da9`'s slot-shaped findings may
  eventually need. It is used exactly as given: it is already typed
  `source()` at the call site, so there is nothing left to validate.
  """
  @spec from_compiler(StatifierBlocks.Compiler.Finding.t(), keyword()) ::
          {:ok, t()} | {:error, from_compiler_error()}
  def from_compiler(%StatifierBlocks.Compiler.Finding{} = finding, opts \\ []) do
    with {:ok, anchor} <- anchor_from_compiler(finding) do
      {:ok,
       %__MODULE__{
         anchor: anchor,
         source: source_from_compiler(finding, opts),
         message: finding.message,
         severity: finding.severity
       }}
    end
  end

  @doc """
  The modifier class a finding's severity renders under (ADR-0005 decision
  11, amended 2026-08-29 for `:info`).

  It lives here rather than in each of the five components that render a
  finding, because it was five copies of the same two clauses and the
  amendment would have made it five copies of three. Decision 14's `sb-`
  prefix is a contract, so the one place that spells these names is worth
  having; and this module is outside `StatifierBlocks.Editor.*`, so a class
  name here costs a headless host nothing and is asserted with LiveView
  absent.

  `:info` renders in a neutral advisory chrome, distinct from the warning
  family and never in the error family (amendment `11c`).

      iex> StatifierBlocks.Finding.severity_class(%StatifierBlocks.Finding{
      ...>   anchor: {:block, "blk_1"}, source: :lint, message: "x", severity: :info})
      "sb-finding--info"
  """
  @spec severity_class(t()) :: String.t()
  def severity_class(%__MODULE__{severity: :warning}), do: "sb-finding--warning"
  def severity_class(%__MODULE__{severity: :info}), do: "sb-finding--info"
  def severity_class(%__MODULE__{}), do: "sb-finding--error"

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

  @spec source_from_compiler(StatifierBlocks.Compiler.Finding.t(), keyword()) :: source()
  defp source_from_compiler(finding, opts) do
    case Keyword.fetch(opts, :source) do
      {:ok, source} -> source
      :error -> source_by_rule(finding)
    end
  end

  # Rule 2: a finding that is not an error cannot honestly be any source
  # but `:lint` (decision 11 - every other source produces `:error`).
  # Amendment `11i` made the converse false - `:lint` may carry `:error` -
  # which is why this rule reads the severity in one direction only.
  @spec source_by_rule(StatifierBlocks.Compiler.Finding.t()) :: source()
  defp source_by_rule(%StatifierBlocks.Compiler.Finding{severity: severity})
       when severity != :error do
    :lint
  end

  # Rule 3/4: by stage, never by `code` - a `case` with a catch-all rather
  # than a list of codes, so an unknown code maps correctly by
  # construction. The catch-all is `:compile` under amendment `11h`: one
  # stage-agnostic value, so this mapping never has to grow a clause when
  # the compiler grows a stage.
  defp source_by_rule(%StatifierBlocks.Compiler.Finding{stage: stage}) do
    case stage do
      :config -> :config
      :resolve -> :resolution
      :structure -> :assignability
      _other_stage -> :compile
    end
  end
end
