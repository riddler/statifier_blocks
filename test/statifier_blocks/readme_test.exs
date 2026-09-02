defmodule StatifierBlocks.ReadmeTest do
  @moduledoc """
  The README's worked example is executed, not trusted.

  `README.md` is the package's front door and the page hexdocs shows, so a
  snippet there that no longer compiles against the real API is a defect a
  reader hits before anything else. This module extracts the `elixir` code
  blocks from the README's two example sections, concatenates each section
  in reading order, evaluates it, and asserts the values the README claims
  in its `#=>` comments.

  Two consequences worth naming, because both are deliberate:

    * **The section headings are load-bearing.** `elixir_blocks_under/2`
      finds a section by its `## ` heading; renaming a heading fails this
      test rather than silently checking nothing.
    * **The claimed outputs are asserted twice** - once as a value, once as
      the literal text of the README's `#=>` line. The second half is what
      catches an output that drifted while the code kept working.

  The example runs no LiveView code, so this test runs in the headless tree
  too - a README whose first snippet needed Phoenix would be lying about
  the optional dependency.
  """

  use ExUnit.Case, async: false

  @readme Path.join([__DIR__, "..", "..", "README.md"]) |> Path.expand()
  @external_resource @readme

  setup_all do
    readme = File.read!(@readme)

    # Evaluated once for the whole module: the section defines modules, and
    # evaluating it per test would redefine them.
    {_result, worked} = eval_section(readme, "A worked example")

    %{readme: readme, worked: worked}
  end

  # Sabotage: changed the README's `Palette.core_types()` merge to
  # `Palette.new(%{...})` (dropping the core vocabulary) - red, because the
  # compile then fails to resolve `core.sequence`.
  test "the worked example compiles the card-processing document it claims to", ctx do
    compiled = Keyword.fetch!(ctx.worked, :compiled)

    assert compiled.invoke_types == ["myapp:authorize", "myapp:capture"]
    assert compiled.warnings == []
    assert compiled.record.document_id == "bdoc_card_capture"
    assert compiled.record.compiler_version == StatifierBlocks.Compiler.compiler_version()

    assert compiled.scxml =~ ~s(<invoke id="s_blk_authorize__invocation" type="myapp:authorize"/>)
    assert compiled.scxml =~ ~s(<invoke id="s_blk_capture__invocation" type="myapp:capture"/>)

    assert Keyword.fetch!(ctx.worked, :blocks_in_play) ==
             ["blk_approved", "blk_authorize", "blk_capture", "blk_root"]
  end

  # Sabotage: emptied the `datamodel:` list in the README's `Document.new/2`
  # call - red on all three asserts, which is the point: the example's branch
  # condition reads two roots, and an example that reads what nothing declares
  # is the one this test exists to keep the README out of.
  test "the worked example declares the roots its branch condition reads", ctx do
    document = Keyword.fetch!(ctx.worked, :document)
    palette = Keyword.fetch!(ctx.worked, :palette)
    compiled = Keyword.fetch!(ctx.worked, :compiled)

    assert StatifierBlocks.Datamodel.candidates(document, nil) ==
             ["amount", "budget_remaining"]

    assert StatifierBlocks.Datamodel.findings(document, palette, nil) == []

    assert compiled.scxml =~
             ~s(<datamodel><data id="budget_remaining"/><data id="amount"/></datamodel>)
  end

  # Sabotage: dropped the `value_path:` key from `Core.Branch.config_schema/1`
  # - red, because `value_path/1` then answers `["arm_approved"]` and the
  # README's `#=>` line no longer matches.
  test "the config-field example resolves a branch arm's condition through its path", ctx do
    {_result, binding} = eval_section(ctx.readme, "Config fields and where their values live")

    config = Keyword.fetch!(binding, :config)
    field = Keyword.fetch!(binding, :field)

    assert field.key == "arm_approved"
    assert StatifierBlocks.BlockType.value_path(field) == ["arms", 0, "cond"]

    assert StatifierBlocks.BlockType.fetch_value(config, ["arms", 0, "cond"]) ==
             {:ok, "budget_remaining > amount"}

    assert StatifierBlocks.BlockType.put_value(config, ["arms", 0, "cond"], "amount <= 5000") ==
             %{"arms" => [%{"cond" => "amount <= 5000", "slot" => "arm_approved"}]}
  end

  # Sabotage: edited one `#=>` line in the README to claim a different value
  # - red here, which is the half of this file that catches prose drift a
  # still-passing snippet would hide.
  test "every output the two example sections claim is the one they produce", ctx do
    claimed =
      ["A worked example", "Config fields and where their values live"]
      |> Enum.flat_map(&elixir_blocks_under(ctx.readme, &1))
      |> Enum.join("\n")
      |> then(&Regex.scan(~r/^\s*#=> (.+)$/m, &1))
      |> Enum.map(fn [_whole, claim] -> claim end)

    assert claimed == [
             ~s(["myapp:authorize", "myapp:capture"]),
             ~s(["blk_approved", "blk_authorize", "blk_capture", "blk_root"]),
             ~s("arm_approved"),
             ~s(["arms", 0, "cond"]),
             ~s({:ok, "budget_remaining > amount"}),
             ~s(%{"arms" => [%{"cond" => "amount <= 5000", "slot" => "arm_approved"}]})
           ]
  end

  # Sabotage: renamed the "## A worked example" heading in the README - red
  # on the non-empty assert, which is the guard against this whole file
  # quietly checking an empty string.
  defp eval_section(readme, heading) do
    blocks = elixir_blocks_under(readme, heading)

    refute blocks == [], ~s(no elixir code blocks found under "## #{heading}" in README.md)

    blocks |> Enum.join("\n\n") |> Code.eval_string([], __ENV__)
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
