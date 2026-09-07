defmodule Mix.Tasks.Adr.Cites do
  @shortdoc "Resolve the line-number citations decision records make into each other"

  @moduledoc """
  Reports citations in `docs/adr/` that no longer point at the text they were
  written against.

  Records cite each other by path and line - `docs/adr/0002-...md:4108`, then
  `` `:4121-4122` `` for the same file. An insert or a re-wrap above a cited
  line moves it, and the citing record, untouched on `main`, silently points at
  different text. This task is the check for that; the reasoning and the three
  layers it runs are in `Mix.StatifierBlocks.AdrCites`.

  It runs as the `ADR cites` custom stage of `mix quality`, so the drift is a
  named gate failure rather than something review has to catch.

  ## Usage

      mix adr.cites
      mix adr.cites --format json
      mix adr.cites --update

  ## Options

    * `--format json` - print the ExQuality finding contract instead of prose
    * `--update` - rewrite `docs/adr/.cite-baseline.json` from the current tree

  `--update` is what a request that legitimately moves a cited line runs, in
  that same request, so the move is reviewed as a diff of the recorded text
  rather than discovered by the next record to be edited.

  Exit status is 0 when nothing failed and 1 when something did. Advisory
  findings - an unanchored paragraph, a citation the baseline has not yet seen
  - are reported and do not change the status.
  """

  use Mix.Task

  alias Mix.StatifierBlocks.AdrCites

  @switches [format: :string, update: :boolean]

  @impl Mix.Task
  def run(argv) do
    {parsed, _argv} = OptionParser.parse!(argv, strict: @switches)
    root = File.cwd!()
    report = AdrCites.analyze(root)

    if parsed[:update] do
      update(root, report)
    else
      report(report, parsed[:format] == "json")
    end
  end

  defp update(root, report) do
    path = AdrCites.baseline_path(root)
    File.write!(path, AdrCites.render_baseline(report.entries))
    Mix.shell().info("Recorded #{map_size(report.entries)} citations in #{path}")
  end

  # The gate reports what a person must act on: a failure, and a citation the
  # baseline has not recorded yet. The anchoring layer is advice about prose
  # rather than a defect - two dozen paragraphs paraphrase what they cite - so
  # it is counted in the summary and listed by a bare `mix adr.cites`, which
  # keeps a real finding from being lost among them on every gate run.
  defp report(report, true) do
    findings = report.findings ++ Enum.filter(report.warnings, &(&1.check == "adr-cite-new"))

    IO.puts(
      JSON.encode!(%{
        summary: summary(report),
        stats: %{finding_count: length(findings)},
        findings: findings
      })
    )

    exit_with(report)
  end

  defp report(report, false) do
    Enum.each(report.findings ++ report.warnings, fn finding ->
      Mix.shell().info("#{finding.file}:#{finding.line} [#{finding.check}] #{finding.message}")
    end)

    Mix.shell().info(summary(report))
    exit_with(report)
  end

  defp summary(%{findings: [], warnings: warnings}) do
    "Every record citation resolves and is unmoved (#{length(warnings)} advisory)"
  end

  defp summary(%{findings: findings, warnings: warnings}) do
    "#{count(length(findings), "record citation")} failed " <>
      "(#{length(warnings)} advisory)"
  end

  defp count(1, noun), do: "1 #{noun}"
  defp count(n, noun), do: "#{n} #{noun}s"

  defp exit_with(%{findings: []}), do: :ok
  defp exit_with(_report), do: exit({:shutdown, 1})
end
