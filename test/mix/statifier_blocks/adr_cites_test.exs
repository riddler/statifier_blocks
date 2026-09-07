defmodule Mix.StatifierBlocks.AdrCitesTest do
  use ExUnit.Case, async: true

  alias Mix.StatifierBlocks.AdrCites

  @fixture "test/fixtures/adr_cites"

  defp report, do: AdrCites.analyze(@fixture)

  defp checks(findings), do: Enum.map(findings, & &1.check)

  defp of_check(findings, check), do: Enum.filter(findings, &(&1.check == check))

  defp of_source(findings, file), do: Enum.filter(findings, &(&1.file == file))

  describe "resolving a citation" do
    # Sabotage: dropping the upper-bound clause from resolvable?/2 let a citation
    # past the end of the record pass, and this went red.
    test "a citation past the end of the record it names fails" do
      [finding] = of_check(report().findings, "adr-cite-unresolvable")

      assert finding.file == "docs/adr/0001-citing.md"
      assert finding.line == 12
      assert finding.severity == "error"
      assert finding.message =~ "0002-cited.md:999-999"
      assert finding.message =~ "the record has 12 lines"
    end

    # Sabotage: making the continuation pattern accept any intervening text
    # bound the `:97` of decision 7's later sentence to the citation before it,
    # and a second unresolvable finding appeared here.
    test "a bare line number in a later sentence is not a continuation" do
      refute Enum.any?(report().findings, &(&1.message =~ ":97"))
    end

    # Sabotage: dropping the continuation scan entirely lost the `:11` of
    # decision 6's citation list, and this key vanished from the entries.
    test "a line number in a citation list continues the citation before it" do
      assert Map.has_key?(report().entries, "0001-citing.md|0002-cited.md:11-11")
    end
  end

  describe "the recorded baseline" do
    # Sabotage: inverting the digest comparison passed the moved citation and
    # failed every unmoved one, and this went red.
    test "a citation whose recorded text no longer matches fails" do
      [finding] =
        report().findings
        |> of_check("adr-cite-moved")
        |> of_source("docs/adr/0001-citing.md")

      assert finding.line == 6
      assert finding.severity == "error"
      assert finding.message =~ "0002-cited.md:5-5"
      assert finding.message =~ "before a line was inserted above it"
      assert finding.message =~ "the baseline no longer matches"
    end

    # Sabotage: making an unrecorded citation an error rather than a warning put
    # this finding in :findings, and the assertion went red.
    test "a citation the baseline has not seen warns rather than fails" do
      %{findings: findings, warnings: warnings} = report()

      refute "adr-cite-new" in checks(findings)
      assert "adr-cite-new" in checks(warnings)
    end

    # Sabotage: dropping the "cites" wrapper from the reader made it return an
    # empty map, and rendering the entries in map order instead of sorted made
    # the recorded file's own key order unstable; both went red.
    test "rendering and reading a baseline round-trips every entry" do
      entries = report().entries
      path = Path.join(System.tmp_dir!(), "adr-cites-#{System.unique_integer([:positive])}")
      on_exit(fn -> File.rm_rf!(path) end)
      File.mkdir_p!(Path.join(path, "docs/adr"))
      File.write!(AdrCites.baseline_path(path), AdrCites.render_baseline(entries))

      read = AdrCites.read_baseline(path)
      key = "0001-citing.md|0002-cited.md:3-3"
      written = Regex.scan(~r/^    "([^"]+)":/m, File.read!(AdrCites.baseline_path(path)))

      assert Map.keys(read) == Enum.sort(Map.keys(entries))
      assert read[key]["sha256"] == entries[key].sha256
      assert Enum.map(written, &List.last/1) == Enum.sort(Map.keys(entries))
    end

    test "a root with no baseline reads as no recorded citations" do
      assert AdrCites.read_baseline(Path.join(System.tmp_dir!(), "nowhere-at-all")) == %{}
    end
  end

  describe "anchoring" do
    # Sabotage: removing the empty-phrases clause sent this paragraph down the
    # general path, where a group with nothing to match is silently anchored,
    # and the finding disappeared.
    test "a paragraph that quotes nothing is reported as unanchored" do
      [finding] = of_check(report().warnings, "adr-cite-unanchored")

      assert finding.line == 9
      assert finding.severity == "warning"
      assert finding.message =~ "0002-cited.md:7-7"
    end

    # Sabotage: matching a phrase against the whole record instead of the cited
    # range made every phrase resolve, and this finding disappeared.
    test "a paragraph whose quoted phrase is in no cited range is reported" do
      [finding] = of_check(report().warnings, "adr-cite-phrase-unmatched")

      assert finding.line == 15
      assert finding.severity == "warning"
      assert finding.message =~ "0002-cited.md:9-9"
    end

    # Sabotage: negating the containment test reported every anchored paragraph
    # instead of the unanchored ones, and both of these went red.
    test "a paragraph quoting text inside a cited range is not reported" do
      lines = Enum.map(report().warnings, & &1.line)

      refute 3 in lines
      refute 18 in lines
    end
  end

  describe "the documents scanned" do
    # Sabotage: narrowing the default sources back to `docs/adr/*.md` - the
    # shape this check had before they were widened - left the plan's citation
    # unprotected, and this went red.
    test "a plan's citation into a record is recorded and fails when the text moves" do
      %{findings: findings, entries: entries} = report()
      [finding] = of_source(findings, "docs/plans/260907-planning.md")

      assert Map.has_key?(entries, "260907-planning.md|0002-cited.md:5-5")
      assert finding.check == "adr-cite-moved"
      assert finding.line == 6
      assert finding.severity == "error"
      assert finding.message =~ "0002-cited.md:5-5"
    end

    # Sabotage: the same narrowing dropped the root instructions file, and its
    # entry disappeared here.
    test "an instructions file at the root is scanned too" do
      %{findings: findings, entries: entries} = report()

      assert Map.has_key?(entries, "CLAUDE.md|0002-cited.md:3-3")
      assert of_source(findings, "CLAUDE.md") == []
    end

    # Widening the sources did not widen the targets: a citation out of a source
    # into something that is no record stays out of scope, and the plan names a
    # module path and line to prove it.
    #
    # Sabotage: letting `target/2` answer `{:adr, base}` for a file no record
    # matches recorded that module path as a citation, and this went red.
    test "a citation into a file that is no record is not recorded" do
      refute Enum.any?(Map.keys(report().entries), &String.contains?(&1, "nothing.ex"))
    end

    # Sabotage: ignoring the option and always reading the defaults left the
    # plan's finding and its entry in place, and both this and the empty-glob
    # test below went red.
    test "the source globs are configurable" do
      records_only = AdrCites.analyze(@fixture, sources: ["docs/adr/*.md"])
      instructions_only = AdrCites.analyze(@fixture, sources: ["CLAUDE.md"])

      assert of_source(records_only.findings, "docs/plans/260907-planning.md") == []
      refute Map.has_key?(records_only.entries, "260907-planning.md|0002-cited.md:5-5")
      refute Map.has_key?(records_only.entries, "CLAUDE.md|0002-cited.md:3-3")
      assert Map.keys(instructions_only.entries) == ["CLAUDE.md|0002-cited.md:3-3"]
    end

    # Sabotage: the same disregard for the option read the defaults here too,
    # and the report came back full rather than empty.
    test "a source glob that matches nothing is not an error" do
      assert AdrCites.analyze(@fixture, sources: ["docs/nowhere/*.md"]) ==
               %{findings: [], warnings: [], entries: %{}}
    end
  end

  describe "this repository's own documents" do
    # Sabotage: inserting a line above a cited line in a record made this red,
    # which is the drift the stage exists to catch.
    test "every citation the default sources make resolves and is unmoved" do
      assert AdrCites.analyze(File.cwd!()).findings == []
    end
  end
end
