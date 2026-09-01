defmodule StatifierBlocks.Runtime.DurableSubchart do
  @moduledoc """
  The durable `statifier_blocks:subchart` handler (sb-2i04, ADR-0008): the
  child runs as its own persisted `statifier_persistence` run, and the
  answer is given at **dispatch time** rather than from a pure
  `Statifier.Invoke.Handler.start/2`.

  `StatifierBlocks.Runtime.Subchart` is untouched and stays the in-memory
  canonical handler. This is the second module beside it (ADR-0008
  decision 1): the two serve the same invoke type string
  (`StatifierBlocks.Core.Subchart.invoke_type/0`, the one definition
  site), compile the same documents to the same bytes, and share the whole
  of resolution and refusal through
  `StatifierBlocks.Runtime.Subchart.Resolution`. Which one answers is the
  host's session wiring, never the document - so a host that wires the
  in-memory module into a durable run gets a child that does not survive
  the restart the parent was made durable to survive.

  ## The seam this plugs into

  The durable path has no `Statifier.Session`. Its invocations are
  answered by `StatifierPersistence.Driver`'s `:dispatch` fun, called as
  `dispatch.(type, params, context)` inside the durable step that emitted
  the `<invoke>`. `dispatch_fun/1` builds exactly that fun from a host
  module:

      dispatch = StatifierBlocks.Runtime.DurableSubchart.dispatch_fun(MyApp.Charts)
      driver = StatifierPersistence.Driver.new(machine, store, dispatch: dispatch)

  A host serving more invoke types than this one writes its own fun and
  delegates the subchart clause here:

      fn
        "statifier_blocks:subchart", params, context ->
          StatifierBlocks.Runtime.DurableSubchart.dispatch(
            "statifier_blocks:subchart", params, context, MyApp.Charts
          )

        "myapp:authorize", params, _context ->
          {:ok, MyApp.authorize(params)}
      end

  `use StatifierBlocks.Runtime.DurableSubchart` is the same thing on the
  host module itself: it declares the resolver behaviour and defines an
  overridable `dispatch/3` delegating here.

  ## No dependency on `statifier_persistence`

  This module names no module from that package and calls nothing in it.
  Everything it needs arrives in the dispatch context map, and everything
  it answers is a plain tuple the driver already understands. That keeps
  `statifier_blocks` free of a dependency edge on a package that depends,
  transitively, on the same engine this one compiles for.

  ## `src` reaches this module through `context.invoke`

  `core.subchart` carries the document id on the `<invoke>`'s `src` and
  nowhere else (ADR-0004's amendment, R1), and `src` is not one of the two
  arguments a dispatch fun is handed. `statifier_persistence`'s
  `t:StatifierPersistence.Driver.dispatch_context/0` therefore carries
  `:invoke`, the whole `t:Statifier.Effect.Invoke.t/0` being dispatched;
  `context.invoke.src` is the document id this module resolves, and the
  payload it hands back is the one it was given rather than a synthesised
  stand-in.

  A context with no `:invoke` key raises `ArgumentError` rather than
  refusing the author's chart: it means the host is on a
  `statifier_persistence` older than the one that widened the seam, which
  is a wiring defect and not a chart problem - the same posture the
  resolver contract's own totality rule takes.

  ## What it answers

  `{:start_child, %{invoke | content: scxml}, {:invoke, invoke}}` on a
  successful resolve - the same instruction shape the in-memory module
  plans, unrenamed and unwrapped, because the effect vocabulary is
  `statifier`'s and only the executor differs (ADR-0008 decision 3). The
  driver creates the child run inside the parent's own exclusion, records
  the linkage with its mandatory chart-identity pin, and answers
  `:pending`: the parent reaches quiescence and the completion arrives
  later through the seam's public `done.invoke` door.

  `{:error, reason: reason, detail: detail}` on a refusal - `st-ADR-0068`'s
  failure keyword list, which the driver turns into
  `error.communication.invoke.<invoke id>` carrying the same
  `reason`/`detail` payload the in-memory `{:raise, :platform, ...}`
  instruction carries. `:attempts` is deliberately absent: a refusal made
  no attempt.

  ## The refusal set, and which half raises which reason

  ADR-0008 decision 5 closes the set at four, and the two packages satisfy
  it jointly:

  | Reason | Raised by |
  |---|---|
  | `unknown_document` | this module |
  | `child_compile_findings` | this module |
  | `cycle_refused` | this module |
  | `child_run_creation_failed` | `StatifierPersistence.Driver`, from its own `start_child` refusals |

  The fourth is the durable-only reason, and it belongs where it is
  raised: creating the child run happens after this module has answered,
  inside the parent's serialized step, so this module has no way to
  observe it and does not pretend to. Nothing here can emit a fifth.

  ## What is deliberately absent

  No `cancel`, no `forward`, no completion path. A durable cancel happens
  because the parent left the invoking state and `active_invocations` lost
  the entry; the cascade through the child's own children, the retained
  records under a distinct terminal status, and the idempotent dropping of
  late completions are all `sp-ADR-0008`'s (ADR-0008 decision 4, "no
  bespoke parent-child channel"). This package contributes nothing to them
  and offers no callback that looks like it does.

  Nesting needs no code: the driver drives a child with the same dispatch
  fun, so a grandchild's `<invoke>` arrives here exactly as its parent's
  did, and the protection against a looping document graph is the cycle
  refusal already in the set (ADR-0008 decision 6). Fan-out - one
  invocation mapping to N children - is named by that decision and is not
  built here.
  """

  alias Statifier.Effect.Invoke
  alias StatifierBlocks.Core.Subchart, as: SubchartBlock
  alias StatifierBlocks.Runtime.Subchart.Resolution

  @typedoc """
  What `dispatch/4` answers: the start instruction
  `StatifierPersistence.Driver` executes, or `st-ADR-0068`'s failure
  keyword list under `:error`.
  """
  @type answer ::
          {:start_child, Invoke.t(), {:invoke, Invoke.t()}}
          | {:error, [reason: Resolution.reason(), detail: map()]}

  @doc """
  Declares the resolver behaviour and defines an overridable `dispatch/3`
  on the host module, delegating to `dispatch/4`.

  The behaviour is `StatifierBlocks.Runtime.Subchart`'s own - the same
  `c:StatifierBlocks.Runtime.Subchart.resolve_chart/2` and
  `c:StatifierBlocks.Runtime.Subchart.palette/0`, in full and without
  additions (ADR-0008 decision 2).
  """
  defmacro __using__(_opts) do
    durable = __MODULE__

    quote do
      @behaviour StatifierBlocks.Runtime.Subchart

      def dispatch(type, params, context),
        do: unquote(durable).dispatch(type, params, context, __MODULE__)

      defoverridable dispatch: 3
    end
  end

  @doc "The invoke type this module serves - `StatifierBlocks.Core.Subchart.invoke_type/0`, the one definition site."
  @spec invoke_type() :: String.t()
  def invoke_type, do: SubchartBlock.invoke_type()

  @doc """
  Builds the three-arity fun `StatifierPersistence.Driver`'s `:dispatch`
  option expects, from one host module.

  The fun serves this module's invoke type and nothing else; a host with
  further invoke types writes its own fun and delegates to `dispatch/4`,
  as the moduledoc shows.
  """
  @spec dispatch_fun(module()) :: (String.t(), term(), map() -> answer())
  def dispatch_fun(host) when is_atom(host) do
    fn type, params, context -> dispatch(type, params, context, host) end
  end

  @doc """
  Answers one durable `statifier_blocks:subchart` invocation.

  `context` is a `StatifierPersistence.Driver` dispatch context; its
  `:invoke` key carries the payload whose `src` names the document to
  resolve, and it is handed to
  `c:StatifierBlocks.Runtime.Subchart.resolve_chart/2` as the ctx.

  The resolved `params` argument is deliberately unread: the element's own
  params seed the child run's datamodel on the driver's side, out of the
  payload handed back, so reading them here would only risk disagreeing
  with it.
  """
  @spec dispatch(String.t(), term(), map(), module()) :: answer()
  def dispatch(type, _params, context, host) when is_atom(host) do
    ensure_type!(type)
    invoke = payload!(context)

    case Resolution.resolve(invoke, context, host) do
      {:ok, scxml} -> {:start_child, %{invoke | content: scxml}, {:invoke, invoke}}
      {:refuse, reason, detail} -> {:error, reason: reason, detail: detail}
    end
  end

  @spec payload!(map()) :: Invoke.t()
  defp payload!(%{invoke: %Invoke{} = invoke}), do: invoke

  defp payload!(context) do
    raise ArgumentError,
          "#{inspect(__MODULE__)} needs the dispatched %Statifier.Effect.Invoke{} on the " <>
            "dispatch context's :invoke key, and got #{inspect(context)}. The document id a " <>
            "subchart resolves is that payload's :src, and nothing else carries it; a context " <>
            "without the key means statifier_persistence predates the widened dispatch seam."
  end

  @spec ensure_type!(String.t()) :: :ok
  defp ensure_type!(type) do
    if type == invoke_type() do
      :ok
    else
      raise ArgumentError,
            "#{inspect(__MODULE__)} serves #{inspect(invoke_type())} and was dispatched " <>
              "#{inspect(type)}. Wire a dispatch fun that routes each invoke type to its own " <>
              "handler; this one is not a catch-all."
    end
  end
end
