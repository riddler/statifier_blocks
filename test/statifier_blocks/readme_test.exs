defmodule StatifierBlocks.ReadmeTest do
  @moduledoc """
  The worked example and the README's config-field example are executed,
  not trusted.

  The worked example is the how-to page `docs/guides/build-and-compile.md`;
  the config-field example is a section of `README.md`, the package's front
  door and the page hexdocs shows. A snippet in either that no longer
  compiles against the real API is a defect a reader hits before anything
  else. This module extracts the `elixir` code blocks from the page and from
  the README section, concatenates each in reading order, evaluates it, and
  asserts the values each claims in its `#=>` comments.

  Two consequences worth naming, because both are deliberate:

    * **The README section heading is load-bearing.** `elixir_blocks_under/2`
      finds a section by its `## ` heading; renaming the heading fails this
      test rather than silently checking nothing. The page is read whole,
      every `elixir` block on it, and an empty read fails the same way.
    * **The claimed outputs are asserted twice** - once as a value, once as
      the literal text of the `#=>` line. The second half is what catches an
      output that drifted while the code kept working.

  The examples run no LiveView code, so this test runs in the headless tree
  too - a worked example that needed Phoenix would be lying about the
  optional dependency.
  """

  use ExUnit.Case, async: false

  @readme Path.join([__DIR__, "..", "..", "README.md"]) |> Path.expand()
  @external_resource @readme

  @page Path.join([__DIR__, "..", "..", "docs", "guides", "build-and-compile.md"])
        |> Path.expand()
  @external_resource @page

  setup_all do
    readme = File.read!(@readme)
    page = File.read!(@page)

    # Evaluated once for the whole module: the page defines modules, and
    # evaluating it per test would redefine them.
    {_result, worked} = eval_blocks(elixir_blocks_in(page), "docs/guides/build-and-compile.md")

    %{readme: readme, page: page, worked: worked}
  end

  # Sabotage: changed the page's document id - red on the `document_id`
  # assert. Dropping `Palette.core_types()` from the page's palette turns
  # every test in this module red instead, through `setup_all`: the compile
  # then fails to resolve `core.sequence` before any assertion runs.
  test "the worked example compiles the patron-registration document it claims to", ctx do
    compiled = Keyword.fetch!(ctx.worked, :compiled)

    assert compiled.invoke_types == ["myapp:check_details", "myapp:issue_card"]
    assert compiled.warnings == []
    assert compiled.record.document_id == "bdoc_patron_registration"
    assert compiled.record.compiler_version == StatifierBlocks.Compiler.compiler_version()

    assert compiled.scxml =~
             ~s(<invoke id="s_blk_check_details__invocation" type="myapp:check_details"/>)

    assert compiled.scxml =~
             ~s(<invoke id="s_blk_issue_card__invocation" type="myapp:issue_card"/>)

    assert compiled.scxml =~
             ~s(<transition event="done.state.s_blk_check_details" target="s_blk_old_enough" type="internal"/>)

    assert compiled.scxml =~
             ~s(<transition event="done.state.s_blk_old_enough" target="s_blk_root__o_done" type="internal"/>)

    assert Keyword.fetch!(ctx.worked, :blocks_in_play) ==
             ["blk_check_details", "blk_issue_card", "blk_old_enough", "blk_root"]
  end

  # Sabotage: emptied the `datamodel:` list in the page's `Document.new/2`
  # call - red on the candidates assert and the SCXML match; deleting only
  # the `minimum_age` entry is red on the findings assert too. The example's
  # branch condition reads two roots, and an example that reads what nothing
  # declares is the one this test exists to keep the page out of.
  test "the worked example declares the roots its branch condition reads", ctx do
    document = Keyword.fetch!(ctx.worked, :document)
    palette = Keyword.fetch!(ctx.worked, :palette)
    compiled = Keyword.fetch!(ctx.worked, :compiled)

    assert StatifierBlocks.Datamodel.candidates(document, nil) ==
             ["minimum_age", "visitor_age"]

    assert StatifierBlocks.Datamodel.findings(document, palette, nil) == []

    assert compiled.scxml =~
             ~s(<datamodel><data id="visitor_age"/><data id="minimum_age"/></datamodel>)
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

  # Sabotage: edited one `#=>` line on the page to claim a different value
  # - red here, which is the half of this file that catches prose drift a
  # still-passing snippet would hide.
  test "every output the two examples claim is the one they produce", ctx do
    claimed =
      (elixir_blocks_in(ctx.page) ++
         elixir_blocks_under(ctx.readme, "Config fields and where their values live"))
      |> Enum.join("\n")
      |> then(&Regex.scan(~r/^\s*#=> (.+)$/m, &1))
      |> Enum.map(fn [_whole, claim] -> claim end)

    assert claimed == [
             ~s(["myapp:check_details", "myapp:issue_card"]),
             ~s(["blk_check_details", "blk_issue_card", "blk_old_enough", "blk_root"]),
             ~s("arm_approved"),
             ~s(["arms", 0, "cond"]),
             ~s({:ok, "budget_remaining > amount"}),
             ~s(%{"arms" => [%{"cond" => "amount <= 5000", "slot" => "arm_approved"}]})
           ]
  end

  # Sabotage: renamed the "## Config fields and where their values live"
  # heading in the README - red on the non-empty assert in `eval_blocks/2`,
  # which is the guard against this whole file quietly checking an empty
  # string.
  defp eval_section(readme, heading) do
    eval_blocks(elixir_blocks_under(readme, heading), ~s("## #{heading}" in README.md))
  end

  # Sabotage: changed every ```elixir fence on the page to ```text - every
  # test red through `setup_all`, on the non-empty assert here.
  defp eval_blocks(blocks, where) do
    refute blocks == [], "no elixir code blocks found under #{where}"

    blocks |> Enum.join("\n\n") |> Code.eval_string([], __ENV__)
  end

  # Every ```elixir block on a page, in reading order.
  @spec elixir_blocks_in(binary()) :: [binary()]
  defp elixir_blocks_in(page) do
    ~r/^```elixir\n(.*?)^```$/ms
    |> Regex.scan(page)
    |> Enum.map(fn [_whole, code] -> code end)
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
