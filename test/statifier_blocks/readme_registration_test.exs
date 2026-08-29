defmodule StatifierBlocks.ReadmeRegistrationTest do
  @moduledoc """
  The README's registration example is executed, not trusted.

  `readme_test.exs` makes the same argument for the two example sections
  it covers, and the reason applies with more force here: this section
  defines a host block type from scratch, so a callback that gains an
  argument or a builder that changes shape breaks the very snippet a host
  copies first. The section is evaluated once - it defines a module, and
  evaluating it twice would redefine it - and every value it claims in a
  `#=>` comment is asserted against what the evaluation produced.

  The example runs no LiveView code, so this test runs in the headless
  tree too.
  """

  use ExUnit.Case, async: false

  @readme Path.join([__DIR__, "..", "..", "README.md"]) |> Path.expand()
  @external_resource @readme
  @heading "Registering your own block types"

  setup_all do
    readme = File.read!(@readme)
    blocks = elixir_blocks_under(readme, @heading)

    refute blocks == [], ~s(no elixir code blocks found under "## #{@heading}" in README.md)

    {_result, binding} = blocks |> Enum.join("\n\n") |> Code.eval_string([], file: @readme)

    %{readme: readme, binding: binding}
  end

  # Sabotage: pointed the README's registration at `StatifierBlocks.Core.Wait`
  # instead of the module the snippet defines - red on the fetch assert,
  # which is the check that the palette really holds what the snippet says
  # (verified).
  test "the example registers the host type beside the core vocabulary", ctx do
    palette = Keyword.fetch!(ctx.binding, :palette)
    risk_hold = Keyword.fetch!(ctx.binding, :risk_hold)

    assert risk_hold == Module.concat([:MyApp, :Blocks, :RiskHold])
    assert StatifierBlocks.Palette.fetch(palette, "myapp.risk_hold") == {:ok, risk_hold}

    assert {:ok, StatifierBlocks.Core.Sequence} =
             StatifierBlocks.Palette.fetch(palette, "core.sequence")

    assert map_size(palette.types) == map_size(StatifierBlocks.Palette.core_types()) + 1
  end

  # Sabotage: dropped `@behaviour StatifierBlocks.BlockType` from the
  # README's module - red here, since a host example that does not declare
  # the behaviour is teaching the wrong thing (verified).
  test "the host type is a conforming block type", ctx do
    risk_hold = Keyword.fetch!(ctx.binding, :risk_hold)

    assert StatifierBlocks.BlockType in (risk_hold.module_info(:attributes)[:behaviour] || [])
    assert risk_hold.current_version() == 1
    assert risk_hold.slots(%{}) == []
    assert risk_hold.validate_config(%{"queue" => "fraud"}) == :ok
    assert {:error, [{"queue", _message}]} = risk_hold.validate_config(%{})
  end

  # Sabotage: changed the README entry's badge to a 30-character chip -
  # red here, because the normalizer refuses it and the claimed `#=>` line
  # no longer holds (verified).
  test "the declared badge and accent token normalize to what the README claims", ctx do
    entry = Keyword.fetch!(ctx.binding, :risk_hold).palette_entry()

    assert StatifierBlocks.BlockType.badge(entry) == "manual review"
    assert StatifierBlocks.ViewModel.accent_token(entry) == "--sb-accent-risk"
  end

  # Sabotage: edited one `#=>` line in the section to claim a different
  # value - red here, which is the half that catches prose drift a
  # still-passing snippet would hide (verified).
  test "every output the section claims is the one it produces", ctx do
    claimed =
      ctx.readme
      |> elixir_blocks_under(@heading)
      |> Enum.join("\n")
      |> then(&Regex.scan(~r/^\s*#=> (.+)$/m, &1))
      |> Enum.map(fn [_whole, claim] -> claim end)

    assert claimed == ["true", ~s("manual review"), ~s("--sb-accent-risk")]
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
