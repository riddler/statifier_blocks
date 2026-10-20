defmodule StatifierBlocks.ReadmeBasicUsageTest do
  @moduledoc """
  The README's one basic-usage block is executed, not trusted.

  This module takes the single `elixir` block under the README's
  `## Basic usage` heading, evaluates it, and asserts every value it claims
  in a `#=>` comment - once as a value and once as the literal text of the
  `#=>` line, so an output that drifted while the code kept working fails
  too. Renaming the heading, or leaving the section with no block or more
  than one, fails here rather than silently checking nothing.

  The block runs no LiveView code, so this test runs in the headless tree
  too.
  """

  use ExUnit.Case, async: false

  @readme Path.join([__DIR__, "..", "..", "README.md"]) |> Path.expand()
  @external_resource @readme

  setup_all do
    readme = File.read!(@readme)
    block = basic_usage_block(readme)
    {_result, binding} = Code.eval_string(block, [], file: "README.md")
    %{block: block, binding: binding}
  end

  # Sabotage: changed the README's invoke type to "myapp:send_welcomes" in
  # the step's declaration only - red on the `invoke_types` assert.
  test "the basic usage compiles the patron-registration document it claims to", ctx do
    compiled = Keyword.fetch!(ctx.binding, :compiled)

    assert compiled.invoke_types == ["myapp:check_details", "myapp:send_welcome"]
    assert compiled.scxml =~ ~s(<invoke type="myapp:send_welcome"/>)
    assert compiled.record.document_id == "bdoc_patron_registration"
    assert {:ok, _machine} = Statifier.compile(compiled.scxml)
  end

  test "the claimed outputs are the README's literal text", ctx do
    assert ctx.block =~
             ~s{compiled.invoke_types\n#=> ["myapp:check_details", "myapp:send_welcome"]}

    assert ctx.block =~ ~s{compiled.scxml =~ ~s(<invoke type="myapp:send_welcome"/>)\n#=> true}
  end

  defp basic_usage_block(readme) do
    section =
      readme
      |> String.split("\n## ")
      |> Enum.find(&String.starts_with?(&1, "Basic usage\n"))

    assert section, "the README has no `## Basic usage` section"

    case Regex.scan(~r/```elixir\n(.*?)```/s, section, capture: :all_but_first) do
      [[block]] -> block
      other -> flunk("expected one elixir block under Basic usage, found #{length(other)}")
    end
  end
end
