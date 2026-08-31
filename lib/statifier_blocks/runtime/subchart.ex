defmodule StatifierBlocks.Runtime.Subchart do
  @moduledoc """
  The canonical `statifier_blocks:subchart` invoke handler - the runtime
  half of `StatifierBlocks.Core.Subchart`'s specification (sb-6edf).

  `core.subchart` compiles an `<invoke>` and fully specifies its contract
  (ADR-0004's 2026-08-29 amendment, C1-C3): a child compiled with
  `:child_use`, the outcome carried on `<donedata>`, one slot per outcome.
  What it does not do, because a block type never runs anything (ADR-0002
  decision 2), is resolve the document id on `src` to an actual chart and
  start it. Every host embedding this package would write the same
  handler to close that gap - "start the child chart this document names"
  is the same code everywhere - so this module is that handler, written
  once. It adds no new contract of its own; it implements the other half
  of one `StatifierBlocks.Core.Subchart` already states.

  ## Namespace: `StatifierBlocks.Runtime.*`, not `StatifierBlocks.Invoke.*`

  This is the package's first runtime module - the first module under
  `lib/` that does anything at session time rather than at compile time -
  and the choice here sets the precedent for every later one.
  `StatifierBlocks.Runtime.*` reads as "the half that runs", set against
  the authoring half that is everything else in `lib/`.
  `StatifierBlocks.Invoke.*` was deliberately not used: it would collide
  in a reader's head with `StatifierBlocks.Core.Invoke` (a block type that
  names an invoke type) and with `StatifierBlocks.InvokeStep` (a base
  block types build out of), and both of those name invoke types without
  running any. A namespace that reads the same as those two but does the
  opposite thing is a worse name than a new one.

  ## The two-registry seam this module does not cross

  ADR-0002 decision 2 draws two registries: a palette names block types,
  and a **separate** registry (statifier-ex st-ADR-0051) maps invoke type
  strings to the handler modules that run them. A block type names an
  invoke type; a handler runs one. This module is a handler - it crosses
  nothing back the other way. `handlers/1` reads the invoke type string
  off `StatifierBlocks.Core.Subchart.invoke_type/0` in one direction only,
  and no block type here resolves a handler for itself.

  ## The resolver contract

  A host `use`s this module and implements two callbacks:

      @callback resolve_chart(document_id :: String.t(), ctx :: Statifier.Invoke.Handler.ctx()) ::
                  {:ok, StatifierBlocks.Document.t()}
                  | {:ok, StatifierBlocks.Compiled.t()}
                  | {:cycle, [String.t()]}
                  | :error

      @callback palette() :: StatifierBlocks.Palette.t()

  Four answers, matching the closed three-reason refusal set below plus
  the pre-compiled convenience:

    * `{:ok, %StatifierBlocks.Document{}}` - compiled here with
      `child_use: true` against `palette/0` and `known_invoke_types:
      Map.keys(ctx.invoke_handlers)` (the same set the runtime will
      classify against, ADR-0004 decision 8).
    * `{:ok, %StatifierBlocks.Compiled{}}` - already compiled; its
      `.scxml` is used exactly as it stands. This handler does **not**
      re-check that it was compiled with `:child_use` - a host handing
      back a chart with no outcome donedata gets the documented default
      arm, not a new refusal.
    * `{:cycle, path}` - the cross-document cycle
      `StatifierBlocks.Compiler.SelfReference` hands to the resolver,
      because a compile of one document cannot see the document graph a
      cycle needs. `path` is the document ids forming the cycle (`[]` is
      allowed).
    * `:error` - the document id names nothing the host can resolve.

  ## Two things outside the four answers, decided here

    1. A **non-binary `src`** (`nil`, or whatever a `srcexpr` resolves to)
       never reaches `resolve_chart/2` at all: it refuses `unknown_document`
       directly, with `detail` carrying the offending value inspected.
       `core.subchart` only ever emits a literal document id, so a chart
       arriving with anything else did not come from this package.
    2. A **return outside the four answers raises `ArgumentError`**, naming
       the offending module and the value returned. That is a host program
       defect, not an author-facing chart problem, and folding it into one
       of the three reasons below would report a bug in the host's own code
       as a refusal of the author's chart - the same posture
       `docs/extending.md` states for the engine itself ("the library never
       rescues them"), pinned downstream by `Statifier.Testing.HandlerCase`
       check 5.

  ## The closed refusal set (campaign-023 ruling R-b)

  Exactly three reasons, never a fourth: `"unknown_document"`,
  `"child_compile_findings"`, `"cycle_refused"`. Every refusal is planned
  as one `{:raise, :platform, ...}` instruction carrying the reason and a
  JSON-shaped `detail` map - never an `{:error, _}` from `start/2`, which
  the engine turns into a data-less `error.execution`
  (`Statifier.Session.Effects.plan_invoke/3`) and would lose the reason
  entirely.

  The raised event is `"error.communication.invoke." <> invoke.invoke_id`.
  `core.subchart` emits its `<invoke>` with `id=<block id>` (C3), so this
  is `error.communication.invoke.<block id>`, and the block's own compiled
  `error.communication.invoke` transition - emitted only when `on_error`
  is occupied - catches it by SCXML's descriptor prefix rule. `attempts`
  is deliberately omitted from `detail`'s shape: a refusal made no
  attempt, and the engine's own default (`Statifier.Session.build_failure_event/3`)
  already reads an absent one as `:undefined`.

  ## Why `perform/2` is absent

  Every instruction this handler plans - `{:start_child, _, _}`,
  `{:stop_child, _}`, `{:forward, _, _}`, `{:raise, _, _, _, _}` - already
  has a dedicated executor clause in `Statifier.Session`. An
  implementation would be dead code carrying `perform/2`'s idempotency
  obligation for nothing.

  ## Why this is the in-memory case, and what is deliberately not here

  `start/2` staying a pure planning callback (`Statifier.Invoke.Handler`'s
  own contract) is exactly what scopes this handler to
  `Statifier.Session`'s in-memory case: an in-memory resolver reading a
  document out of the host's own process is pure, but a durable variant -
  the child as its own persisted run, with parent linkage carried in run
  metadata, composing with `statifier_persistence`/`statifier_oban` - would
  need to durably record that linkage as part of starting, which is not a
  planning-time operation. That variant is the deliberate follow-up
  (campaign-023 ruling R-e); nothing for it is implemented here.

  ## Why the palette arrives as a callback

  `Statifier.Session`'s `:invoke_handlers` maps a type string to a
  **module and nothing else** - there is no per-handler configuration
  anywhere in statifier 2.2.0, so a palette cannot be closed over at
  registration and cannot ride in on `ctx`. A callback on the host's own
  module is the only shape left, and it keeps ADR-0002 decision 2's
  substance: the palette stays a caller-supplied value reaching the
  compile through the call signature, never global state. `palette/0`
  must be a pure function of nothing (ADR-0002 decision 4's rule, which
  reaches anything it calls); a host needing per-tenant palettes declares
  one handler module per palette and registers the right one for the
  session, which is exactly the cadence ADR-0002 names - a palette fixed
  for an operation, a handler set fixed for a session's lifetime.
  """

  alias Statifier.Effect.Invoke
  alias Statifier.Event
  alias Statifier.Invoke.Handler
  alias StatifierBlocks.{Compiled, Compiler, Document, Palette}
  alias StatifierBlocks.Compiler.Finding
  alias StatifierBlocks.Core.Subchart

  @callback resolve_chart(document_id :: String.t(), ctx :: Handler.ctx()) ::
              {:ok, Document.t()} | {:ok, Compiled.t()} | {:cycle, [String.t()]} | :error
  @callback palette() :: Palette.t()

  @typedoc "The reason a start refused, always one of the closed R-b set."
  @type reason :: String.t()

  defmacro __using__(_opts) do
    quote do
      @behaviour StatifierBlocks.Runtime.Subchart
      @behaviour Statifier.Invoke.Handler

      @impl Statifier.Invoke.Handler
      def start(invoke, ctx),
        do: StatifierBlocks.Runtime.Subchart.start(invoke, ctx, __MODULE__)

      @impl Statifier.Invoke.Handler
      def cancel(invoke_id, ctx),
        do: StatifierBlocks.Runtime.Subchart.cancel(invoke_id, ctx)

      @impl Statifier.Invoke.Handler
      def forward(invoke_id, event, ctx),
        do: StatifierBlocks.Runtime.Subchart.forward(invoke_id, event, ctx)

      defoverridable start: 2, cancel: 2, forward: 3
    end
  end

  @doc "The invoke type every handler built through this module serves - `StatifierBlocks.Core.Subchart.invoke_type/0`, the one definition site."
  @spec invoke_type() :: String.t()
  def invoke_type, do: Subchart.invoke_type()

  @doc "Builds the `:invoke_handlers` map `Statifier.Session.start_link/2` expects, from one host module."
  @spec handlers(module()) :: %{String.t() => module()}
  def handlers(module) when is_atom(module), do: %{invoke_type() => module}

  @doc false
  @spec start(Invoke.t(), Handler.ctx(), module()) :: {:ok, [Handler.instruction()]}
  def start(%Invoke{} = invoke, ctx, host) do
    case resolve(invoke, ctx, host) do
      {:ok, scxml} -> {:ok, [{:start_child, %{invoke | content: scxml}, {:invoke, invoke}}]}
      {:refuse, reason, detail} -> {:ok, [refusal(invoke, reason, detail)]}
    end
  end

  @doc false
  @spec cancel(String.t(), Handler.ctx()) :: {:ok, [Handler.instruction()]}
  def cancel(invoke_id, _ctx) when is_binary(invoke_id), do: {:ok, [{:stop_child, invoke_id}]}

  @doc false
  @spec forward(String.t(), Event.t(), Handler.ctx()) :: {:ok, [Handler.instruction()]}
  def forward(invoke_id, %Event{} = event, _ctx) when is_binary(invoke_id),
    do: {:ok, [{:forward, invoke_id, event}]}

  # The non-binary-`src` totality rule: `core.subchart` only ever emits a
  # literal document id, so a chart arriving with anything else (nil, or a
  # `srcexpr` result) did not come from this package. Refused directly,
  # without ever calling the resolver.
  @spec resolve(Invoke.t(), Handler.ctx(), module()) ::
          {:ok, String.t()} | {:refuse, reason(), map()}
  defp resolve(%Invoke{src: src}, _ctx, _host) when not is_binary(src) do
    {:refuse, "unknown_document", %{"chart" => inspect(src)}}
  end

  defp resolve(%Invoke{src: src}, ctx, host) do
    case host.resolve_chart(src, ctx) do
      {:ok, %Document{} = document} ->
        compile_child(document, ctx, host, src)

      {:ok, %Compiled{scxml: scxml}} ->
        {:ok, scxml}

      {:cycle, path} when is_list(path) ->
        {:refuse, "cycle_refused", %{"chart" => src, "cycle" => path}}

      :error ->
        {:refuse, "unknown_document", %{"chart" => src}}

      other ->
        raise_non_conforming(host, other)
    end
  end

  @spec compile_child(Document.t(), Handler.ctx(), module(), String.t()) ::
          {:ok, String.t()} | {:refuse, reason(), map()}
  defp compile_child(document, ctx, host, src) do
    opts = [child_use: true, known_invoke_types: Map.keys(ctx.invoke_handlers)]

    case Compiler.compile(document, host.palette(), opts) do
      {:ok, %Compiled{scxml: scxml}} ->
        {:ok, scxml}

      {:error, findings} ->
        {:refuse, "child_compile_findings",
         %{"chart" => src, "findings" => Enum.map(findings, &finding_detail/1)}}
    end
  end

  @spec finding_detail(Finding.t()) :: %{String.t() => term()}
  defp finding_detail(%Finding{code: code, message: message, block_id: block_id}) do
    %{"code" => Atom.to_string(code), "message" => message, "block_id" => block_id}
  end

  @spec refusal(Invoke.t(), reason(), map()) :: Handler.instruction()
  defp refusal(
         %Invoke{invoke_id: invoke_id, state_index: state_index, invoke_index: invoke_index},
         reason,
         detail
       ) do
    {:raise, :platform, "error.communication.invoke." <> invoke_id,
     {:invoke, state_index, invoke_index}, [data: %{"reason" => reason, "detail" => detail}]}
  end

  @spec raise_non_conforming(module(), term()) :: no_return()
  defp raise_non_conforming(host, other) do
    raise ArgumentError,
          "#{inspect(host)}.resolve_chart/2 returned #{inspect(other)}, which is not " <>
            "one of {:ok, %StatifierBlocks.Document{}}, {:ok, %StatifierBlocks.Compiled{}}, " <>
            "{:cycle, path} or :error"
  end
end
