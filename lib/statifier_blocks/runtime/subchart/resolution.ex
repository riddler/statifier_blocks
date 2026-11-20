defmodule StatifierBlocks.Runtime.Subchart.Resolution do
  @moduledoc """
  The half of the `statifier_blocks:subchart` handler that is pure in both
  variants: turning the document id on `src` into a compiled child chart,
  or into one of the four shared refusal reasons.

  `src` is the literal id a `chart` block emits, or the value a
  `chart_from` block's `srcexpr` evaluated to when the invocation started;
  both reach `resolve/3` the same way, and only a string is handed to the
  host's resolver.

  ADR-0008 decision 2 says the resolver contract is the durable module's
  too, "in full and without additions", and that resolution is therefore
  "shared code, not a second copy". This module is that shared code.
  `StatifierBlocks.Runtime.Subchart` (in-memory, `Statifier.Session`) and
  `StatifierBlocks.Runtime.DurableSubchart` (durable,
  `StatifierPersistence.Driver`'s dispatch fun) both call `resolve/3` and
  differ only in what they do with its two answers - which is exactly the
  "what differs between the variants begins after resolution has produced
  a chart" line the record draws.

  The resolver contract itself, the behaviour, and every word of
  documentation about it stay on `StatifierBlocks.Runtime.Subchart`: this
  module mints nothing and is not part of the package's public surface.

  ## A `chart_from` child must fit the block's declared outcomes

  A `chart_from` block's `<invoke>` carries the block's declared outcomes
  on the reserved `statifier_blocks:outcomes` param (ADR-0004's Amendment
  of 2026-11-19, J2). When the payload carries it, the child that resolved
  and compiled is judged last: each outcome its root declares - the
  `declared_outcomes` of the compiled artifact's `interface`, whether this
  module compiled it or the host's resolver handed it back compiled - must
  be among the block's, or the start is refused
  `"child_outcome_undeclared"` (J3), with `detail` naming the document id,
  the child's outcomes outside the set in the child's order, and the
  block's set in its own order. A child that declares fewer outcomes fits,
  and so does an artifact whose `interface` declares none.

  A literal `chart` block emits no carrier, so its child is not judged here
  and starts exactly as it always has. A carrier whose value is not a
  string is not one this package's emission produces, and it is read as no
  carrier.

  ## `:known_invoke_types` is passed only when the ctx can supply it

  The in-memory ctx is a `t:Statifier.Invoke.Handler.ctx/0` and carries
  `:invoke_handlers`, the set the runtime will classify against, so a
  child compile gets ADR-0004 decision 8's opt-in lint. A durable
  dispatch context carries no such key - the durable seam's registry is
  the host's dispatch fun, not a handler map - so the option is
  **omitted** rather than passed as an empty set. Omitted, the compiler
  does not run the lint at all (`StatifierBlocks.Compiler`'s
  `Keyword.fetch/2`). Passed empty, it would run and report every invoke
  type in the child as unregistered - starting with
  `statifier_blocks:subchart` itself in a nested durable subchart
  (ADR-0008 decision 6) - which is a false claim about the host's
  registration rather than a true one. The lint is warning-only
  (`StatifierBlocks.Compiler.InvokeTypes`), so neither choice can change
  a refusal; the choice is between silence and noise, and silence is the
  honest one where there is nothing to compare against.
  """

  alias Statifier.Effect.Invoke
  alias StatifierBlocks.{Compiled, Compiler, Document}
  alias StatifierBlocks.Compiler.Finding
  alias StatifierBlocks.Core.Subchart

  @typedoc "The reason a start refused, always one of the closed refusal set."
  @type reason :: String.t()

  @typedoc "A resolved child chart's SCXML, or a refusal carrying its reason and JSON-shaped detail."
  @type t :: {:ok, String.t()} | {:refuse, reason(), map()}

  @doc """
  Resolves `invoke`'s `src` through `host.resolve_chart/2` and compiles
  the result for child use, or refuses.

  `ctx` is handed to `resolve_chart/2` unchanged - a
  `t:Statifier.Invoke.Handler.ctx/0` in the in-memory case, a
  `StatifierPersistence.Driver` dispatch context in the durable one.
  """
  @spec resolve(Invoke.t(), map(), module()) :: t()
  # The non-binary-`src` totality rule: a `chart` block's `src` is always a
  # string, and a `chart_from` block's is whatever its path evaluated to
  # (ADR-0004's Amendment of 2026-11-19, J5 and J6). A string, from either,
  # goes to the host's resolver, which alone decides which ids resolve; any
  # other value (nil, `:undefined`, a number, a map) names no document and
  # is refused directly, its value inspected, without the resolver called.
  def resolve(%Invoke{src: src}, _ctx, _host) when not is_binary(src) do
    {:refuse, "unknown_document", %{"chart" => inspect(src)}}
  end

  def resolve(%Invoke{src: src} = invoke, ctx, host) do
    case host.resolve_chart(src, ctx) do
      {:ok, %Document{} = document} ->
        document |> compile_child(ctx, host, src) |> fit(invoke)

      {:ok, %Compiled{} = compiled} ->
        fit({:ok, compiled}, invoke)

      {:cycle, path} when is_list(path) ->
        {:refuse, "cycle_refused", %{"chart" => src, "cycle" => path}}

      :error ->
        {:refuse, "unknown_document", %{"chart" => src}}

      other ->
        raise_non_conforming(host, other)
    end
  end

  @doc false
  # The payload a handler hands on in `{:start_child, ...}`: the resolved
  # chart as its content, and its params without the reserved outcomes
  # param a `chart_from` block carries (ADR-0004's Amendment of 2026-11-19,
  # J2), so the carrier never reaches the child's datamodel. A literal
  # `chart` block carries no such param, so its params pass unchanged.
  @spec child_invoke(Invoke.t(), String.t()) :: Invoke.t()
  def child_invoke(%Invoke{params: params} = invoke, scxml) do
    %{invoke | content: scxml, params: without_carrier(params)}
  end

  # The engine hands `<param>` values on as a map keyed by name, and as
  # `:undefined` when the element had none (`Statifier.EventData`'s params
  # rung). A map the carrier was the only entry of is answered as
  # `:undefined`, the shape a block with no params at all produces, so the
  # child sees exactly what it would have seen had no carrier been emitted.
  @spec without_carrier(term()) :: term()
  defp without_carrier(params) when is_map(params) do
    case Map.delete(params, Subchart.outcomes_param()) do
      remaining when remaining == %{} and map_size(params) > 0 -> :undefined
      remaining -> remaining
    end
  end

  defp without_carrier(params), do: params

  # The last check, after resolution and the child compile have both
  # answered (J3's order): a payload carrying the block's declared outcomes
  # is a `chart_from` block's, and its child's root outcomes must all be
  # among them. Without the carrier - a literal `chart` block - the child
  # is not judged and its chart is answered as it stands.
  @spec fit({:ok, Compiled.t()} | {:refuse, reason(), map()}, Invoke.t()) :: t()
  defp fit({:refuse, _reason, _detail} = refusal, _invoke), do: refusal

  defp fit({:ok, %Compiled{scxml: scxml, interface: interface}}, %Invoke{} = invoke) do
    with {:ok, declared} <- carried_outcomes(invoke),
         [_ | _] = undeclared <- undeclared(interface, declared) do
      {:refuse, "child_outcome_undeclared",
       %{"chart" => invoke.src, "outcomes" => undeclared, "declared" => declared}}
    else
      _fits -> {:ok, scxml}
    end
  end

  # The child's root outcomes outside the block's set, in the child's own
  # order. An `interface` with no `declared_outcomes` declares nothing to
  # judge, so it fits.
  @spec undeclared(map(), [String.t()]) :: [String.t()]
  defp undeclared(interface, declared) do
    interface |> Map.get(:declared_outcomes, []) |> Enum.reject(&(&1 in declared))
  end

  # The block's declared outcomes off the reserved carrier: a single-quoted
  # string literal of `outcome_names/1` joined by single spaces, which the
  # engine hands on evaluated, so the param's value is the joined string.
  @spec carried_outcomes(Invoke.t()) :: {:ok, [String.t()]} | :no_carrier
  defp carried_outcomes(%Invoke{params: params}) when is_map(params) do
    case Map.get(params, Subchart.outcomes_param()) do
      carrier when is_binary(carrier) -> {:ok, String.split(carrier, " ", trim: true)}
      _absent -> :no_carrier
    end
  end

  defp carried_outcomes(%Invoke{}), do: :no_carrier

  @spec compile_child(Document.t(), map(), module(), String.t()) ::
          {:ok, Compiled.t()} | {:refuse, reason(), map()}
  defp compile_child(document, ctx, host, src) do
    opts = [child_use: true] ++ lint_opts(ctx)

    case Compiler.compile(document, host.palette(), opts) do
      {:ok, %Compiled{} = compiled} ->
        {:ok, compiled}

      {:error, findings} ->
        {:refuse, "child_compile_findings",
         %{"chart" => src, "findings" => Enum.map(findings, &finding_detail/1)}}
    end
  end

  @spec lint_opts(map()) :: keyword()
  defp lint_opts(%{invoke_handlers: handlers}) when is_map(handlers),
    do: [known_invoke_types: Map.keys(handlers)]

  defp lint_opts(_ctx), do: []

  @spec finding_detail(Finding.t()) :: %{String.t() => term()}
  defp finding_detail(%Finding{code: code, message: message, block_id: block_id}) do
    %{"code" => Atom.to_string(code), "message" => message, "block_id" => block_id}
  end

  @spec raise_non_conforming(module(), term()) :: no_return()
  defp raise_non_conforming(host, other) do
    raise ArgumentError,
          "#{inspect(host)}.resolve_chart/2 returned #{inspect(other)}, which is not " <>
            "one of {:ok, %StatifierBlocks.Document{}}, {:ok, %StatifierBlocks.Compiled{}}, " <>
            "{:cycle, path} or :error"
  end
end
