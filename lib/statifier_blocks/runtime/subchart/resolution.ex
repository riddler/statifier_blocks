defmodule StatifierBlocks.Runtime.Subchart.Resolution do
  @moduledoc """
  The half of the `statifier_blocks:subchart` handler that is pure in both
  variants: turning the document id on `src` into a compiled child chart,
  or into one of the three shared refusal reasons.

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

  @typedoc "The reason a start refused, always one of the closed campaign-023 R-b set."
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
  # The non-binary-`src` totality rule: `core.subchart` only ever emits a
  # literal document id, so a chart arriving with anything else (nil, or a
  # `srcexpr` result) did not come from this package. Refused directly,
  # without ever calling the resolver.
  def resolve(%Invoke{src: src}, _ctx, _host) when not is_binary(src) do
    {:refuse, "unknown_document", %{"chart" => inspect(src)}}
  end

  def resolve(%Invoke{src: src}, ctx, host) do
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

  @spec compile_child(Document.t(), map(), module(), String.t()) :: t()
  defp compile_child(document, ctx, host, src) do
    opts = [child_use: true] ++ lint_opts(ctx)

    case Compiler.compile(document, host.palette(), opts) do
      {:ok, %Compiled{scxml: scxml}} ->
        {:ok, scxml}

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
