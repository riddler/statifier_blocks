defmodule StatifierBlocks.TypingAPaletteTest do
  @moduledoc """
  `docs/typing-a-palette.md` and the README's typing section are executed,
  not trusted.

  The how-to is the page a host reads when it types its first palette, so a
  snippet there that no longer compiles against the real API is a defect the
  reader hits before anything else. This module extracts every `elixir` code
  block from the how-to, concatenates them in reading order - they are one
  program, and later blocks use names earlier ones bound - evaluates the
  result, and asserts every value the page claims in a `#=>` comment. The
  README's `## Typing a palette` section is evaluated the same way.

  Three consequences worth naming, because all three are deliberate:

    * **Every fence is checked, and all but one of them runs.**
      `elixir_blocks/1` takes them all rather than a named section's, so a
      snippet added to the how-to without a claim beside it still has to
      compile. The single exception is the `# mix.exs` fence, which is a
      dependency entry rather than a step in the program: running it inside
      the guide's binding would prove nothing, so it is checked against the
      requirement this package's own `mix.exs` declares instead.
    * **The claimed outputs are asserted twice** - once as a value, once as
      the literal text of the `#=>` line - which is what catches an output
      that drifted while the code kept working.
    * **The two documents are evaluated in separate `setup_all` calls but
      define no module in common.** The how-to's modules are namespaced
      `MyApp.Typing.*`; the README's section defines none at all, so
      neither redefines what the other bound.

  Nothing here needs LiveView, so it runs in the headless tree too - a
  typing guide whose first snippet needed Phoenix would be lying about the
  optional dependency.
  """

  use ExUnit.Case, async: false

  @how_to Path.join([__DIR__, "..", "..", "docs", "typing-a-palette.md"]) |> Path.expand()
  @readme Path.join([__DIR__, "..", "..", "README.md"]) |> Path.expand()
  @external_resource @how_to
  @external_resource @readme

  setup_all do
    how_to = File.read!(@how_to)
    readme = File.read!(@readme)

    how_to_blocks = elixir_blocks(how_to)
    readme_blocks = elixir_blocks_under(readme, "Typing a palette")

    refute how_to_blocks == [], "no elixir code blocks found in docs/typing-a-palette.md"
    refute readme_blocks == [], ~s(no elixir code blocks under "## Typing a palette" in README.md)

    # Evaluated once for the whole module: the how-to defines modules, and
    # evaluating it per test would redefine them.
    {_result, how_to_binding} =
      how_to_blocks
      |> Enum.reject(&dependency_fence?/1)
      |> Enum.join("\n\n")
      |> Code.eval_string([], file: @how_to)

    {_readme_result, readme_binding} =
      readme_blocks |> Enum.join("\n\n") |> Code.eval_string([], file: @readme)

    %{
      how_to: how_to,
      readme: readme,
      how_to_binding: how_to_binding,
      readme_binding: readme_binding
    }
  end

  # Sabotage: deleted the `"label" => "Credit card transaction"` line from
  # the how-to's `cards.credit_txn` declaration - red here
  # (`left: {:ok, %{label: "Credit card transaction"}}` against a
  # declaration carrying none), restored, re-ran green (verified).
  test "the how-to's datamodel document declares the types it claims", ctx do
    declarations = Keyword.fetch!(ctx.how_to_binding, :declarations)

    assert {:ok, %{label: "Credit card transaction"}} =
             StatifierDatamodel.Declarations.fetch(declarations, "cards.credit_txn")

    assert {:ok, %{kind: :shape}} =
             StatifierDatamodel.Declarations.fetch(declarations, "Settleable")

    assert Keyword.fetch!(ctx.how_to_binding, :txn_label) == "Credit card transaction"
  end

  # Sabotage: removed `subject: "cards.current_txn"` from the how-to's
  # `palette_entry/0` - red (`left: nil, right: "cards.current_txn"`),
  # restored, re-ran green (verified). This is the assert that keeps the
  # guide's central claim - the sugar is a read and a write at the subject
  # path - from going stale.
  test "the how-to's palette seeds the subject path the entry block names", ctx do
    palette = Keyword.fetch!(ctx.how_to_binding, :palette)
    document = Keyword.fetch!(ctx.how_to_binding, :document)

    assert StatifierBlocks.Environment.subject_path(palette, document) == "cards.current_txn"

    assert Keyword.fetch!(ctx.how_to_binding, :known_at_settle) ==
             %{"cards.current_txn" => "cards.credit_txn"}
  end

  # Sabotage: changed the how-to's `expects:` from `"Settleable"` to
  # `"cards.settlement"` - red here (`left: {:error, ...}, right: :ok`),
  # restored, re-ran green (verified): a guide that teaches a signature the
  # walk then refuses is the failure this test exists to prevent.
  test "the how-to's typed document validates", ctx do
    assert Keyword.fetch!(ctx.how_to_binding, :verdict) == :ok

    assert Keyword.fetch!(ctx.how_to_binding, :by_coverage) == :covers
    assert Keyword.fetch!(ctx.how_to_binding, :refused) == :not_assignable
    assert Keyword.fetch!(ctx.how_to_binding, :permissive) == :unknown
  end

  # Sabotage: edited the how-to's first `#=> :covers` line to claim
  # `:identical` - red (the claim lists differed on that one row), restored,
  # re-ran green (verified) - the half that catches prose drift a passing
  # snippet hides.
  test "every output the how-to claims is the one it produces", ctx do
    assert claims(ctx.how_to) == [
             ~s("Credit card transaction"),
             ~s(%{"cards.current_txn" => "cards.credit_txn"}),
             ~s(:ok),
             ~s(:covers),
             ~s(:not_assignable),
             ~s(:unknown)
           ]
  end

  # Sabotage: pointed the README section's `Environment.satisfies/3` at
  # `"cards.settlement"` as the held type - red
  # (`left: :not_assignable, right: :covers`), restored, re-ran green
  # (verified). Every value below is read out of the snippet's own binding
  # rather than recomputed here, which is what makes that sabotage bite: an
  # earlier draft recomputed the call and stayed green through it.
  test "the README section produces the values it claims", ctx do
    assert Keyword.fetch!(ctx.readme_binding, :read_path) == ["subject"]
    assert Keyword.fetch!(ctx.readme_binding, :satisfied) == :covers
    assert Keyword.fetch!(ctx.readme_binding, :label) == "Credit card transaction"

    assert Keyword.fetch!(ctx.readme_binding, :write_signature) ==
             %{"assign_to" => {:path, %{writes: "cards.settlement"}}}

    assert claims(readme_section(ctx.readme)) == [
             ~s(["subject"]),
             ~s(:covers),
             ~s("Credit card transaction"),
             ~s(%{"assign_to" => {:path, %{writes: "cards.settlement"}}})
           ]
  end

  # Sabotage: renamed the how-to's `## Read the result in the editor`
  # heading to `## Editor` - red (the heading lists differed on the last
  # row), restored, re-ran green (verified). The headings are the guide's
  # shape: each one names a goal a reader has, which is what keeps the page
  # a how-to rather than a tour of the machinery.
  test "the how-to keeps the goal-shaped headings the guide is organized by", ctx do
    headings = Regex.scan(~r/^## (.+)$/m, ctx.how_to) |> Enum.map(fn [_all, h] -> h end)

    assert headings == [
             "Before you start",
             "Declare the records and shapes your paths hold",
             "Type an entry by a declaration",
             "Name the document's subject",
             "Declare what each field reads and writes",
             "Check what the walk knows at a position",
             "Project a host schema into the document",
             "Re-resolve a host relation at publish",
             "Read the result in the editor"
           ]
  end

  # Sabotage: changed the how-to's fence to `{:statifier_datamodel, "~> 0.2"}`
  # - red here (`left: "~> 0.1", right: "~> 0.2"`), restored from a copy taken
  # first, re-ran green (verified). This is the assert that closes the one
  # hole the rest of the module leaves: the fence the program excludes was
  # hand-evaluated until now, so a floor raised in `mix.exs` and not in the
  # guide - or the reverse - shipped a reader an install line that does not
  # resolve the version the package actually requires.
  test "the how-to's mix.exs fence names the requirement this package declares", ctx do
    fences = elixir_blocks(ctx.how_to)
    {excluded, executed} = Enum.split_with(fences, &dependency_fence?/1)

    # Named rather than derived: the counts are the module's contract with the
    # guide, so a fence added on either side of the split is a red test and a
    # deliberate decision rather than a silent change of what runs.
    assert length(executed) == 7
    assert [fence] = excluded

    {{name, requirement}, []} = Code.eval_string(fence, [], file: @how_to)

    declared =
      Mix.Project.config()
      |> Keyword.fetch!(:deps)
      |> Enum.find(&(elem(&1, 0) == name))

    refute declared == nil, "#{inspect(name)} is not a dependency of this package"
    assert elem(declared, 1) == requirement
  end

  # The `# mix.exs` marker is what makes a fence non-executable: it is an
  # entry for the reader's own project file, not a step in the guide's
  # program. One predicate serves both the exclusion and the assert above, so
  # the two can never disagree about which fence that is.
  @spec dependency_fence?(binary()) :: boolean()
  defp dependency_fence?(fence), do: String.contains?(fence, "# mix.exs")

  @spec claims(binary()) :: [binary()]
  defp claims(markdown) do
    markdown
    |> then(&Regex.scan(~r/^\s*#=> (.+)$/m, &1))
    |> Enum.map(fn [_whole, claim] -> claim end)
  end

  @spec readme_section(binary()) :: binary()
  defp readme_section(readme) do
    readme
    |> String.split("\n## ")
    |> Enum.find("", &String.starts_with?(&1, "Typing a palette\n"))
  end

  # Every ```elixir block in the document, in reading order.
  @spec elixir_blocks(binary()) :: [binary()]
  defp elixir_blocks(markdown) do
    markdown
    |> then(&Regex.scan(~r/^```elixir\n(.*?)^```$/ms, &1))
    |> Enum.map(fn [_whole, code] -> code end)
  end

  # Every ```elixir block between `## <heading>` and the next `## ` heading.
  @spec elixir_blocks_under(binary(), binary()) :: [binary()]
  defp elixir_blocks_under(markdown, heading) do
    markdown
    |> String.split("\n## ")
    |> Enum.find("", &String.starts_with?(&1, heading <> "\n"))
    |> elixir_blocks()
  end
end
