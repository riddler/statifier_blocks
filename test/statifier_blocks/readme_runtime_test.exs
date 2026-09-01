defmodule StatifierBlocks.ReadmeRuntimeTest do
  @moduledoc """
  The README's runtime-handler example is executed, not trusted.

  `readme_registration_test.exs` makes this argument for the registration
  section; the same applies here. The section under "## The handlers this
  package does ship" defines a host resolver module with `use
  StatifierBlocks.Runtime.Subchart`, calls `handlers/1` on it, and then
  wires the same module into the durable variant with
  `StatifierBlocks.Runtime.DurableSubchart.dispatch_fun/1`, so a callback
  that gains an argument or a builder that changes shape breaks the
  snippet a host copies first. The section is evaluated once - it
  defines a module, and evaluating it twice would redefine it - and every
  value it claims in a `#=>` comment is asserted against what the
  evaluation produced.
  """

  use ExUnit.Case, async: false

  alias Statifier.Invoke.Handler

  @readme Path.join([__DIR__, "..", "..", "README.md"]) |> Path.expand()
  @external_resource @readme
  @heading "The handlers this package does ship"

  setup_all do
    readme = File.read!(@readme)
    blocks = elixir_blocks_under(readme, @heading)

    refute blocks == [], ~s(no elixir code blocks found under "## #{@heading}" in README.md)

    {_result, binding} = blocks |> Enum.join("\n\n") |> Code.eval_string([], file: @readme)

    %{readme: readme, binding: binding}
  end

  # Sabotage: changed `handlers/1` in lib/statifier_blocks/runtime/subchart.ex
  # to build `%{"wrong:type" => module}` - red here
  # (`left: %{"wrong:type" => MyApp.Charts}, right: %{"statifier_blocks:subchart" => MyApp.Charts}`),
  # restored, re-ran green (verified).
  test "handlers/1 builds the map the README claims", _ctx do
    host = Module.concat([:MyApp, :Charts])

    assert StatifierBlocks.Runtime.Subchart.handlers(host) == %{
             "statifier_blocks:subchart" => host
           }
  end

  # Sabotage: deleted the `use StatifierBlocks.Runtime.Subchart` line from
  # the README's fence (leaving `resolve_chart/2` and `palette/0` in
  # place) - red here (`function_exported?(MyApp.Charts, :start, 2)` came
  # back `false`), restored, re-ran green (verified).
  #
  # `module_info(:attributes)[:behaviour]` only ever reports the first
  # `@behaviour` a module declares, not every one, so the callbacks each
  # behaviour requires are checked directly instead.
  test "the defined module implements both behaviours", _ctx do
    host = Module.concat([:MyApp, :Charts])
    optional = Handler.behaviour_info(:optional_callbacks)

    for {callback, arity} <- Handler.behaviour_info(:callbacks),
        {callback, arity} not in optional do
      assert function_exported?(host, callback, arity)
    end

    for {callback, arity} <- StatifierBlocks.Runtime.Subchart.behaviour_info(:callbacks) do
      assert function_exported?(host, callback, arity)
    end
  end

  # Sabotage: changed `handlers/1` in lib/statifier_blocks/runtime/subchart.ex
  # to key its map on a literal `"wrong:type"` instead of `invoke_type()` -
  # red here too (`left: ["wrong:type"], right: ["statifier_blocks:subchart"]`),
  # restored, re-ran green (verified) - this is what keeps the README from
  # drifting off the one definition site.
  test "the handled invoke type is the one definition site names", _ctx do
    host = Module.concat([:MyApp, :Charts])
    handlers = StatifierBlocks.Runtime.Subchart.handlers(host)

    assert Map.keys(handlers) == [StatifierBlocks.Core.Subchart.invoke_type()]
  end

  # Sabotage: had `dispatch_fun/1` in
  # lib/statifier_blocks/runtime/durable_subchart.ex return a two-arity fun
  # - red here (`is_function(dispatch, 3)` came back `false`), restored,
  # re-ran green (verified). The README tells a host to hand this value
  # straight to `StatifierPersistence.Driver`'s `:dispatch` option, and
  # that option takes a three-arity fun.
  test "the durable snippet builds the fun the driver's :dispatch option takes", ctx do
    dispatch = Keyword.fetch!(ctx.binding, :dispatch)

    assert is_function(dispatch, 3)
  end

  # Sabotage: edited the README's `#=>` line to claim `MyApp.Charts.Wrong`
  # instead of `MyApp.Charts` - red here (`left` carried `.Wrong`, `right`
  # did not), restored, re-ran green (verified) - this is the half that
  # catches prose drift a still-passing snippet would hide.
  test "every output the section claims is the one it produces", ctx do
    claimed =
      ctx.readme
      |> elixir_blocks_under(@heading)
      |> Enum.join("\n")
      |> then(&Regex.scan(~r/^\s*#=> (.+)$/m, &1))
      |> Enum.map(fn [_whole, claim] -> claim end)

    assert claimed == [~s(%{"statifier_blocks:subchart" => MyApp.Charts})]
  end

  # Every ```elixir block between `## <heading>` and the next `## ` heading.
  @spec elixir_blocks_under(binary(), binary()) :: [binary()]
  defp elixir_blocks_under(readme, heading) do
    readme
    |> String.split("\n## ")
    |> Enum.find("", &String.starts_with?(&1, heading <> "\n"))
    |> then(&Regex.scan(~r/^```elixir\n(.*?)^```$/ms, &1))
    |> Enum.map(fn [_whole, code] -> code end)
  end
end
