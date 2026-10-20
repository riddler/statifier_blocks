defmodule StatifierBlocks.DescribingADocumentGuideTest do
  @moduledoc """
  `docs/describing-a-document.md` and
  `docs/guides/validate-a-document-against-the-schema.md` are executed, not
  trusted.

  Each page's `elixir` code blocks are concatenated in reading order -
  they are one program, and later blocks use names earlier ones bound - and
  evaluated once. Every `#=>` claim sits under a statement that binds a
  name, so each claim is asserted twice: the name's value in the program's
  binding against the expected value below, and the literal `#=>` text
  against that value's `inspect/2`. The second half is what catches an
  output that drifted in the prose while the code kept working.

  The describing page's modules are namespaced `MyApp.Describing.*`, and the
  validation page defines none, so neither evaluation redefines what the
  other bound. The validation page runs `ex_json_schema`, a test-only
  dependency of this package; nothing here needs LiveView, so the module
  runs in the headless tree too.
  """

  use ExUnit.Case, async: false

  @guide Path.join([__DIR__, "..", "..", "docs", "describing-a-document.md"]) |> Path.expand()
  @schema_guide Path.join([
                  __DIR__,
                  "..",
                  "..",
                  "docs",
                  "guides",
                  "validate-a-document-against-the-schema.md"
                ])
                |> Path.expand()
  @external_resource @guide
  @external_resource @schema_guide

  # In claim order: every `#=>` line of the validation page, the name the
  # statement above it binds, and the value it claims.
  @schema_claims [
    same_file: true,
    draft: "http://json-schema.org/draft-07/schema#",
    checked: :ok,
    refused: true,
    typed: :ok,
    root_admits: :ok,
    palette_refuses: true
  ]

  # The same for the describing page.
  @guide_claims [
    identity: {"bdoc_patron_registration", 1},
    nodes: [
      {"registration", nil, :step},
      {"verify", "registration", :step},
      {"reminder", "verify", :arm},
      {"verified", "verify", :arm},
      {"submit", "registration", :step},
      {"review", "registration", :step},
      {"approved", "review", :step},
      {"corrected", "review", :rail},
      {"withdrawn", "review", :rail},
      {"close", "registration", :step}
    ],
    await_outcomes: ["received", "timed_out"],
    interrupts: [
      {"registration.corrected", {:body, "review"}, :shallow},
      {"registration.withdrawn", {:exit, "review"}, nil}
    ],
    arms: [
      {"email_verified == false", {:block, "reminder"}},
      {:otherwise, {:exit, "verify"}}
    ],
    node_lines: [
      "Run its steps in order",
      ~s(Decide: When "unverified", otherwise \(one of\)),
      "Send registration.verify_reminder",
      "Wait for registration.email_verified",
      "Send registration.submitted",
      "Resumable group",
      "Wait for registration.approved, giving up after 14d",
      "When registration.corrected, resume",
      "When registration.withdrawn, abandon",
      "Send registration.closed"
    ],
    interrupt_lines: [
      "On registration.corrected, When registration.corrected, resume resumes the group at shallow history",
      "On registration.withdrawn, When registration.withdrawn, abandon abandons the group"
    ],
    reworded_lines: [
      "A correction",
      "A withdrawal",
      "A correction restarts the wait for the approval"
    ],
    withdrawn_line:
      "On registration.withdrawn, When registration.withdrawn, abandon abandons the group",
    submit_line: "Once the application is in, wait for the librarian",
    same_count?: true
  ]

  setup_all do
    guide = File.read!(@guide)
    schema_guide = File.read!(@schema_guide)

    guide_blocks = elixir_blocks(guide)
    schema_blocks = elixir_blocks(schema_guide)

    refute guide_blocks == [], "no elixir code blocks found in docs/describing-a-document.md"

    refute schema_blocks == [],
           "no elixir code blocks found in docs/guides/validate-a-document-against-the-schema.md"

    # Evaluated once for the whole module: the describing page defines
    # modules, and evaluating it per test would redefine them.
    {_result, guide_binding} =
      guide_blocks |> Enum.join("\n\n") |> Code.eval_string([], file: @guide)

    {_result, schema_binding} =
      schema_blocks |> Enum.join("\n\n") |> Code.eval_string([], file: @schema_guide)

    %{
      guide: guide,
      schema_guide: schema_guide,
      guide_binding: guide_binding,
      schema_binding: schema_binding
    }
  end

  # Sabotage: changed the page's stored document's `"type_version": 1` to
  # `"type_version": "1"` - red here (`checked` was an error list, not
  # `:ok`), restored from a copy, re-ran green (verified).
  test "the validation page's program binds the values it claims", ctx do
    for {name, expected} <- @schema_claims do
      assert Keyword.fetch!(ctx.schema_binding, name) == expected, "validation binding #{name}"
    end
  end

  # Sabotage: edited the validation page's `refused` claim to `false` - red
  # (the claim lists differed on that row), restored from a copy, re-ran
  # green (verified).
  test "every output the validation page claims is the one it produces", ctx do
    assert claims(ctx.schema_guide) == Enum.map(@schema_claims, &inspect_claim/1)
  end

  # Each heading names a goal a reader has, which is what keeps the page a
  # how-to.
  test "the validation page keeps its goal-shaped headings", ctx do
    assert headings(ctx.schema_guide) == [
             "Hand the schema file to your service",
             "Check a stored document",
             "Know what the schema admits that the decoder refuses",
             "Ask for a stricter schema for your palette",
             "Check your palette before taking a stricter package version"
           ]

    assert ctx.schema_guide =~ "# How to validate a document against the schema from any language"
  end

  # Sabotage: in the describing page's phrasing module, answered the
  # correction interrupt with a line carrying a tab - red (`reworded_lines`
  # lost its third row to the default line), restored from a copy, re-ran
  # green (verified).
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
    assert headings(ctx.guide) == [
             "Before you start",
             "Outline a document",
             "Read the edges the containers draw",
             "Write the outline as lines",
             "Reword lines with a phrasing module",
             "Know what a phrasing module cannot change"
           ]
  end

  @spec headings(binary()) :: [binary()]
  defp headings(markdown) do
    Regex.scan(~r/^## (.+)$/m, markdown) |> Enum.map(fn [_all, h] -> h end)
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

  # Every ```elixir block in the text, in reading order.
  @spec elixir_blocks(binary()) :: [binary()]
  defp elixir_blocks(markdown) do
    markdown
    |> then(&Regex.scan(~r/^```elixir\n(.*?)^```$/ms, &1))
    |> Enum.map(fn [_whole, code] -> code end)
  end
end
