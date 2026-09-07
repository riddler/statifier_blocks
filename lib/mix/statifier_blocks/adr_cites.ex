defmodule Mix.StatifierBlocks.AdrCites do
  @moduledoc """
  Resolves the line-number citations this repository's documents make into the
  decision records, and reports the ones that no longer point at the text they
  were written against.

  A document cites a record in `docs/adr/` by path and line - for example
  `docs/adr/0002-block-type-behaviour.md:4108` - often followed by more line
  numbers for the same file (`` `:4121-4122` ``, `` `:4126` ``). Nothing about
  a line number survives an edit above it: an insert or a re-wrap in the cited
  record silently moves every line below it, and the citing document, on `main`
  and untouched, now points at different text. That failure is invisible to
  every other stage of the gate, which is why this one exists.

  ## What it reads

  Two roles, and they are not the same set of files. The **targets** are the
  records under `docs/adr/`, and only a citation into one of them is checked -
  a citation into `lib/` or `test/` is left to the compiler and the suite. The
  **sources** are the documents scanned for citations, and they are wider than
  the records, because a plan or `CLAUDE.md` cites a record by line exactly as
  a record does and drifts in exactly the same way. The default globs are
  `docs/adr/*.md`, `docs/plans/*.md` and `CLAUDE.md`; `analyze/2` takes a
  `:sources` option that replaces them, which is how a test scans a fixture
  tree and how another document root would join the check.

  ## What it checks

  Three layers, two of which fail the gate:

  1. **Resolvable** (fails). The cited file exists under `docs/adr/` and the
     cited range is non-empty and inside it.
  2. **Unmoved** (fails). The cited range's text still hashes to what the
     recorded baseline says it did. This is the layer that catches the drift:
     a line inserted above a cited range changes the text at that range, and
     the digest changes with it.
  3. **Anchored** (warns). The citing paragraph quotes something - a phrase in
     quotation marks, or a multi-word backticked span - that is still found
     inside one of the ranges the paragraph cites. A paragraph that quotes
     nothing is reported as unanchored rather than failed: most of the corpus
     cites a section heading and paraphrases it, and treating a paraphrase as
     drift would falsify history rather than protect it.

  ## The baseline

  Layer 2 reads `docs/adr/.cite-baseline.json`, which records one entry per
  citation: the normalized text at the cited range and its SHA-256. An entry is
  keyed by the citing document's **base name** and the range it cites, not by
  the citing document's path. Two sources sharing a base name therefore share a
  key - harmlessly, because an entry's value is the text at the cited range and
  says nothing about the source, so the colliding entries are identical. Keying
  by path instead would rewrite every recorded key the moment the sources
  widened, and every citation would fall back to the warning layer for a cycle:
  the protection would lapse exactly when it was being extended. It is
  regenerated with `mix adr.cites --update`, and the regenerated file belongs
  in the same request as the record edit that moved the line.

  A citation the baseline has never seen **warns** rather than fails. Records
  land serially and a new citation arrives with the request that writes it;
  failing on an unrecorded citation would red the gate of a request that had
  done nothing wrong. Protection therefore accrues at the next `--update`
  rather than at the moment the citation is written, which is the deliberate
  trade this layer makes.

  Nothing here rewrites a record. Merged records keep the line-number citations
  they were written with.
  """

  # A path-and-line citation: `docs/adr/0002-....md:4108`, with an optional end
  # line. The path alternatives keep a bare prose colon from matching.
  @cite ~r{`?(?<file>[A-Za-z0-9_./-]+\.(?:md|ex|exs|json|heex)):(?<a>\d+)(?:-(?<b>\d+))?`?}

  # A continuation of the citation before it: `` , `:4121-4122` `` and
  # `` and `:4133` ``. Only a list separator may sit between the two, so the
  # `` `:4120` `` in "). Wrapping `:4120` would move..." - a self-citation a
  # sentence later - is correctly left unbound.
  @continuation ~r{\A[\s,]*(?:and|or)?[\s,]*`:(?<a>\d+)(?:-(?<b>\d+))?`}

  @quoted ~r/"([^"]+)"/
  @backticked ~r/`([^`]+)`/

  # A record or bead name is what a paragraph is *about*, never a quotation of
  # the text it points at, so it is not an anchor.
  @namey ~r/\A(?:[a-z]{2,3}-)?(?:ADR-\d{4}|RQ-[A-Za-z0-9-]+)/

  # A shorter run of words matches by accident often enough to be worthless as
  # an anchor.
  @min_phrase 12

  @adr_dir "docs/adr"
  @baseline_file ".cite-baseline.json"

  # The documents scanned for citations, as globs relative to the project root.
  # The records cite each other, and the plans and `CLAUDE.md` cite the records;
  # all three drift the same way, so all three are read. Nothing here decides
  # what may be *cited* - that stays `docs/adr/`, in `target/2`.
  @default_sources ["docs/adr/*.md", "docs/plans/*.md", "CLAUDE.md"]
  @text_excerpt 160

  @type finding :: %{
          file: String.t(),
          line: pos_integer(),
          severity: String.t(),
          check: String.t(),
          message: String.t()
        }

  @type report :: %{
          findings: [finding()],
          warnings: [finding()],
          entries: %{optional(String.t()) => map()}
        }

  @doc "Path of the baseline file for a project root."
  @spec baseline_path(String.t()) :: String.t()
  def baseline_path(root), do: Path.join([root, @adr_dir, @baseline_file])

  @doc """
  Runs every layer over the documents under `root` that the source globs name,
  resolving what they cite into `root`'s `docs/adr/`.

  Returns the failing findings, the advisory ones, and the baseline entries the
  current tree would record.

  ## Options

    * `:sources` - globs, relative to `root`, of the documents to scan for
      citations. Replaces the default `docs/adr/*.md`, `docs/plans/*.md` and
      `CLAUDE.md` rather than adding to them.
  """
  @spec analyze(String.t(), keyword()) :: report()
  def analyze(root, opts \\ []) do
    sources = read_sources(root, Keyword.get(opts, :sources, @default_sources))
    records = read_records(root)
    baseline = read_baseline(root)

    sources
    |> groups(records)
    |> Enum.reduce(%{findings: [], warnings: [], entries: %{}}, fn group, acc ->
      merge(acc, judge(group, records, baseline))
    end)
    |> Map.update!(:findings, &Enum.reverse/1)
    |> Map.update!(:warnings, &Enum.reverse/1)
  end

  @doc "Serializes baseline entries as the JSON document the tree checks in."
  @spec render_baseline(%{optional(String.t()) => map()}) :: String.t()
  def render_baseline(entries) do
    body =
      entries
      |> Enum.sort_by(fn {key, _} -> key end)
      |> Enum.map_join(",\n", fn {key, entry} ->
        ~s(    #{JSON.encode!(key)}: ) <>
          ~s({"sha256": #{JSON.encode!(entry.sha256)}, "text": #{JSON.encode!(entry.text)}})
      end)

    ~s({\n  "version": 1,\n  "cites": {\n) <> body <> ~s(\n  }\n}\n)
  end

  @doc "Reads the checked-in baseline, or an empty map when there is none yet."
  @spec read_baseline(String.t()) :: %{optional(String.t()) => map()}
  def read_baseline(root) do
    with {:ok, raw} <- File.read(baseline_path(root)),
         {:ok, %{"cites" => cites}} <- JSON.decode(raw) do
      cites
    else
      _ -> %{}
    end
  end

  # -- sources, records and paragraphs ----------------------------------------

  # A source is read once and carries its path relative to the root, which is
  # what a finding reports, and its base name, which is what the baseline keys.
  defp read_sources(root, globs) do
    globs
    |> Enum.flat_map(fn glob -> root |> Path.join(glob) |> Path.wildcard() end)
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.map(fn path ->
      %{
        path: Path.relative_to(path, root),
        name: Path.basename(path),
        lines: String.split(File.read!(path), "\n")
      }
    end)
  end

  defp read_records(root) do
    [root, @adr_dir, "*.md"]
    |> Path.join()
    |> Path.wildcard()
    |> Map.new(fn path -> {Path.basename(path), String.split(File.read!(path), "\n")} end)
  end

  defp groups(sources, records) do
    Enum.flat_map(sources, fn source ->
      source.lines
      |> paragraphs()
      |> Enum.map(&group(source, records, &1))
      |> Enum.reject(&(&1.cites == []))
    end)
  end

  defp group(source, records, {first, last}) do
    text = source.lines |> Enum.slice((first - 1)..(last - 1)) |> Enum.join(" ")
    {cites, mixed?} = citations(text, records)

    %{
      source: source.path,
      source_name: source.name,
      line: first,
      cites: cites,
      mixed?: mixed?,
      phrases: phrases(text)
    }
  end

  # Paragraphs are blank-line separated. A citation and the phrase it quotes sit
  # in the same paragraph and rarely on the same line, because the prose is
  # hard-wrapped.
  defp paragraphs(lines) do
    lines
    |> Enum.with_index(1)
    |> Enum.chunk_by(fn {line, _} -> String.trim(line) == "" end)
    |> Enum.reject(fn chunk -> chunk |> hd() |> elem(0) |> String.trim() == "" end)
    |> Enum.map(fn chunk -> {chunk |> hd() |> elem(1), chunk |> List.last() |> elem(1)} end)
  end

  # -- citation scanning ------------------------------------------------------

  defp citations(text, records), do: citations(text, records, [], false)

  defp citations(text, records, acc, mixed?) do
    case Regex.run(@cite, text, return: :index, capture: :first) do
      nil ->
        {Enum.reverse(acc), mixed?}

      [{start, len}] ->
        whole = binary_part(text, start, len)
        rest = binary_part(text, start + len, byte_size(text) - start - len)
        %{"file" => file, "a" => a, "b" => b} = Regex.named_captures(@cite, whole)
        {tail, rest} = continuations(rest, [])
        target = target(file, records)
        ranges = [range(a, b) | tail]
        {acc, mixed?} = collect(target, ranges, acc, mixed?)
        citations(rest, records, acc, mixed?)
    end
  end

  defp continuations(text, acc) do
    case Regex.named_captures(@continuation, text) do
      nil ->
        {Enum.reverse(acc), text}

      %{"a" => a, "b" => b} ->
        [{_, len}] = Regex.run(@continuation, text, return: :index, capture: :first)
        rest = binary_part(text, len, byte_size(text) - len)
        continuations(rest, [range(a, b) | acc])
    end
  end

  defp range(a, ""), do: {String.to_integer(a), String.to_integer(a)}
  defp range(a, b), do: {String.to_integer(a), String.to_integer(b)}

  # Only a citation into `docs/adr/` is in scope. A citation into `lib/` or
  # `test/` is left to the compiler and the suite, but it is remembered, because
  # a paragraph carrying one may be quoting the code rather than the record.
  defp target(file, records) do
    base = Path.basename(file)

    if String.starts_with?(file, @adr_dir <> "/") and Map.has_key?(records, base) do
      {:adr, base}
    else
      :other
    end
  end

  defp collect(:other, _ranges, acc, _mixed?), do: {acc, true}

  defp collect({:adr, base}, ranges, acc, mixed?) do
    {Enum.reduce(ranges, acc, fn {a, b}, inner -> [{base, a, b} | inner] end), mixed?}
  end

  # -- phrases ----------------------------------------------------------------

  defp phrases(text) do
    normalized = normalize(text)

    quoted = captures(@quoted, normalized)
    ticked = @backticked |> captures(normalized) |> Enum.filter(&String.contains?(&1, " "))

    (quoted ++ ticked)
    |> Enum.map(&normalize/1)
    |> Enum.reject(&noise?/1)
    |> Enum.uniq()
  end

  defp captures(regex, text) do
    regex |> Regex.scan(text, capture: :all_but_first) |> List.flatten()
  end

  defp noise?(phrase) do
    String.length(phrase) < @min_phrase or
      Regex.match?(@namey, phrase) or
      Regex.match?(~r/\.\w+:\d/, phrase)
  end

  defp normalize(text) do
    text
    |> String.replace(~r/[*_]/, "")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  # -- judging ----------------------------------------------------------------

  defp judge(group, records, baseline) do
    {valid, broken} = Enum.split_with(group.cites, &resolvable?(&1, records))

    unresolvable = Enum.map(broken, &unresolvable_finding(group, &1, records))
    {moved, entries} = compare(group, valid, records, baseline)

    %{
      findings: unresolvable ++ moved.failures,
      warnings: moved.warnings ++ anchoring(group, valid, records),
      entries: entries
    }
  end

  defp resolvable?({base, a, b}, records) do
    case Map.fetch(records, base) do
      {:ok, lines} -> a >= 1 and b >= a and b <= length(lines)
      :error -> false
    end
  end

  defp unresolvable_finding(group, {base, a, b}, records) do
    detail =
      case Map.fetch(records, base) do
        {:ok, lines} -> "the record has #{length(lines)} lines"
        :error -> "no such record under #{@adr_dir}/"
      end

    finding(
      group,
      "error",
      "adr-cite-unresolvable",
      "cites #{base}:#{a}-#{b}, which does not resolve - #{detail}"
    )
  end

  defp compare(group, valid, records, baseline) do
    Enum.reduce(valid, {%{failures: [], warnings: []}, %{}}, fn cite, {acc, entries} ->
      {key, entry} = entry(group, cite, records)
      {add_comparison(acc, group, cite, key, entry, baseline), Map.put(entries, key, entry)}
    end)
  end

  defp add_comparison(acc, group, {base, a, b}, key, entry, baseline) do
    case Map.fetch(baseline, key) do
      {:ok, %{"sha256" => sha}} when sha == entry.sha256 ->
        acc

      {:ok, %{"text" => was}} ->
        message =
          "cites #{base}:#{a}-#{b}, which has moved - the baseline recorded " <>
            "#{inspect(was)} there and the record now reads #{inspect(entry.text)}"

        %{acc | failures: [finding(group, "error", "adr-cite-moved", message) | acc.failures]}

      :error ->
        message =
          "cites #{base}:#{a}-#{b}, which the baseline has never seen - " <>
            "run `mix adr.cites --update` and commit the result"

        %{acc | warnings: [finding(group, "warning", "adr-cite-new", message) | acc.warnings]}
    end
  end

  defp entry(group, {base, a, b}, records) do
    text = region(records, base, a, b)

    {"#{group.source_name}|#{base}:#{a}-#{b}",
     %{sha256: sha256(text), text: String.slice(text, 0, @text_excerpt)}}
  end

  defp region(records, base, a, b) do
    records
    |> Map.fetch!(base)
    |> Enum.slice((a - 1)..(b - 1))
    |> Enum.join(" ")
    |> normalize()
  end

  defp sha256(text), do: :crypto.hash(:sha256, text) |> Base.encode16(case: :lower)

  defp anchoring(_group, [], _records), do: []

  defp anchoring(%{phrases: []} = group, cites, _records) do
    [
      finding(
        group,
        "warning",
        "adr-cite-unanchored",
        "cites #{render(cites)} and quotes nothing, so only the range is checked"
      )
    ]
  end

  defp anchoring(group, cites, records) do
    regions = Enum.map(cites, fn {base, a, b} -> region(records, base, a, b) end)

    if Enum.any?(group.phrases, fn phrase -> Enum.any?(regions, &String.contains?(&1, phrase)) end) do
      []
    else
      [unmatched_finding(group, cites)]
    end
  end

  defp unmatched_finding(group, cites) do
    finding(
      group,
      "warning",
      "adr-cite-phrase-unmatched",
      "cites #{render(cites)}, and none of the phrases the paragraph quotes is " <>
        "inside any of those ranges - either the paragraph paraphrases, or a cite has drifted"
    )
  end

  defp render(cites) do
    Enum.map_join(cites, ", ", fn {base, a, b} -> "#{base}:#{a}-#{b}" end)
  end

  defp finding(group, severity, check, message) do
    %{
      file: group.source,
      line: group.line,
      severity: severity,
      check: check,
      message: message
    }
  end

  defp merge(acc, part) do
    %{
      findings: Enum.reverse(part.findings) ++ acc.findings,
      warnings: Enum.reverse(part.warnings) ++ acc.warnings,
      entries: Map.merge(acc.entries, part.entries)
    }
  end
end
