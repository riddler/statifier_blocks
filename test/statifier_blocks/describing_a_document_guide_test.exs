defmodule StatifierBlocks.DescribingADocumentGuideTest do
  @moduledoc """
  `docs/describing-a-document.md` and the README's `## Validating and
  describing a document` section are executed, not trusted.

  Each document's `elixir` code blocks are concatenated in reading order -
  they are one program, and later blocks use names earlier ones bound - and
  evaluated once. Every `#=>` claim sits under a statement that binds a
  name, so each claim is asserted twice: the name's value in the program's
  binding against the expected value below, and the literal `#=>` text
  against that value's `inspect/2`. The second half is what catches an
  output that drifted in the prose while the code kept working.

  The guide's module is namespaced `MyApp.Describing.*` and the README's is
  `MyApp.LoanPhrasing`, so neither evaluation redefines what the other
  bound. The README's schema example runs `ex_json_schema`, a test-only
  dependency of this package; nothing here needs LiveView, so the module
  runs in the headless tree too.
  """

  use ExUnit.Case, async: false

  @guide Path.join([__DIR__, "..", "..", "docs", "describing-a-document.md"]) |> Path.expand()
  @readme Path.join([__DIR__, "..", "..", "README.md"]) |> Path.expand()
  @external_resource @guide
  @external_resource @readme

  @readme_heading "Validating and describing a document"

  @loan_default_lines [
    "Run its steps in order",
    "Send loan.checked_out",
    "Wait for loan.returned, giving up after 21d",
    "The steps start with Send loan.checked_out",
    "After Send loan.checked_out (done), Wait for loan.returned, giving up after 21d",
    "Wait for loan.returned, giving up after 21d (received, timed_out) ends the steps"
  ]

  # In claim order: every `#=>` line of the README section, the name the
  # statement above it binds, and the value it claims.
  @readme_claims [
    same_file: true,
    draft: "http://json-schema.org/draft-07/schema#",
    checked: :ok,
    refused: true,
    typed: :ok,
    root_admits: :ok,
    palette_refuses: true,
    lines: @loan_default_lines,
    edge_kinds: [:entry, :sequence, :exit],
    reworded: List.replace_at(@loan_default_lines, 4, "Once the book is out, wait for its return")
  ]

  # The same for the guide.
  @guide_claims [
    identity: {"bdoc_library_loan", 1},
    nodes: [
      {"loan", nil, :step},
      {"fines", "loan", :step},
      {"notice", "fines", :arm},
      {"paid", "fines", :arm},
      {"checkout", "loan", :step},
      {"lending", "loan", :step},
      {"returned", "lending", :step},
      {"renewed", "lending", :rail},
      {"lost", "lending", :rail},
      {"close", "loan", :step}
    ],
    await_outcomes: ["received", "timed_out"],
    interrupts: [
      {"loan.renewed", {:body, "lending"}, :shallow},
      {"loan.reported_lost", {:exit, "lending"}, nil}
    ],
    arms: [
      {"patron.fines_owed > 0", {:block, "notice"}},
      {:otherwise, {:exit, "fines"}}
    ],
    node_lines: [
      "Run its steps in order",
      ~s(Decide: When "owes", otherwise \(one of\)),
      "Send loan.fines_notice",
      "Wait for fines.paid",
      "Send loan.checked_out",
      "Resumable group",
      "Wait for loan.returned, giving up after 21d",
      "When loan.renewed, resume",
      "When loan.reported_lost, abandon",
      "Send loan.closed"
    ],
    interrupt_lines: [
      "On loan.renewed, When loan.renewed, resume resumes the group at shallow history",
      "On loan.reported_lost, When loan.reported_lost, abandon abandons the group"
    ],
    reworded_lines: [
      "A renewal",
      "A report that the book is lost",
      "A renewal restarts the wait for the return"
    ],
    lost_line: "On loan.reported_lost, When loan.reported_lost, abandon abandons the group",
    same_count?: true
  ]

  setup_all do
    guide = File.read!(@guide)
    readme_section = section(File.read!(@readme), @readme_heading)

    guide_blocks = elixir_blocks(guide)
    readme_blocks = elixir_blocks(readme_section)

    refute guide_blocks == [], "no elixir code blocks found in docs/describing-a-document.md"

    refute readme_blocks == [],
           ~s(no elixir code blocks under "## #{@readme_heading}" in README.md)

    # Evaluated once for the whole module: both documents define a module,
    # and evaluating either per test would redefine it.
    {_result, guide_binding} =
      guide_blocks |> Enum.join("\n\n") |> Code.eval_string([], file: @guide)

    {_result, readme_binding} =
      readme_blocks |> Enum.join("\n\n") |> Code.eval_string([], file: @readme)

    %{
      guide: guide,
      readme_section: readme_section,
      guide_binding: guide_binding,
      readme_binding: readme_binding
    }
  end

  # Sabotage: changed the README's stored document's `"type_version": 1` to
  # `"type_version": "1"` - red here (`checked` was an error list, not
  # `:ok`), restored from a copy, re-ran green (verified).
  test "the README section's program binds the values it claims", ctx do
    for {name, expected} <- @readme_claims do
      assert Keyword.fetch!(ctx.readme_binding, name) == expected, "README binding #{name}"
    end
  end

  # Sabotage: edited the README's `edge_kinds` claim to `[:entry, :exit]` -
  # red (the claim lists differed on that row), restored from a copy, re-ran
  # green (verified).
  test "every output the README section claims is the one it produces", ctx do
    assert claims(ctx.readme_section) == Enum.map(@readme_claims, &inspect_claim/1)
  end

  # Sabotage: in the guide's phrasing module, answered the renewal interrupt
  # with a line carrying a tab - red (`reworded_lines` lost its third row
  # to the default line), restored from a copy, re-ran green (verified).
  test "the guide's program binds the values it claims", ctx do
    for {name, expected} <- @guide_claims do
      assert Keyword.fetch!(ctx.guide_binding, name) == expected, "guide binding #{name}"
    end
  end

  # Sabotage: edited the guide's `await_outcomes` claim to `["received"]` -
  # red (the claim lists differed on that row), restored from a copy, re-ran
  # green (verified).
  test "every output the guide claims is the one it produces", ctx do
    assert claims(ctx.guide) == Enum.map(@guide_claims, &inspect_claim/1)
  end

  # Sabotage: renamed the guide's `## Read the edges the containers draw`
  # heading to `## Edges` - red (the heading lists differed on that row),
  # restored from a copy, re-ran green (verified). Each heading names a goal
  # a reader has, which is what keeps the page a how-to.
  test "the guide keeps its goal-shaped headings", ctx do
    headings = Regex.scan(~r/^## (.+)$/m, ctx.guide) |> Enum.map(fn [_all, h] -> h end)

    assert headings == [
             "Before you start",
             "Outline a document",
             "Read the edges the containers draw",
             "Write the outline as lines",
             "Reword lines with a phrasing module",
             "Know what a phrasing module cannot change"
           ]
  end

  @spec inspect_claim({atom(), term()}) :: binary()
  defp inspect_claim({_name, value}),
    do: inspect(value, limit: :infinity, printable_limit: :infinity)

  @spec claims(binary()) :: [binary()]
  defp claims(markdown) do
    markdown
    |> then(&Regex.scan(~r/^\s*#=> (.+)$/m, &1))
    |> Enum.map(fn [_whole, claim] -> claim end)
  end

  # The text between `## <heading>` and the next `## ` heading.
  @spec section(binary(), binary()) :: binary()
  defp section(markdown, heading) do
    markdown
    |> String.split("\n## ")
    |> Enum.find("", &String.starts_with?(&1, heading <> "\n"))
  end

  # Every ```elixir block in the text, in reading order.
  @spec elixir_blocks(binary()) :: [binary()]
  defp elixir_blocks(markdown) do
    markdown
    |> then(&Regex.scan(~r/^```elixir\n(.*?)^```$/ms, &1))
    |> Enum.map(fn [_whole, code] -> code end)
  end
end
