defmodule StatifierBlocks.CompileRatchet do
  @moduledoc """
  The documents `StatifierBlocks.Compiler.CompileRatchetTest` holds to the
  bytes and chart identity they compiled to at the `v0.45.0` release, the
  last release before returnable steps, Back and `core.checkpoint` existed
  (ADR-0004's Amendment of 2026-11-20, `L8`: a document with no returnable
  step compiles byte-identically).

  ## What the enumeration covers

    * **Every stored block document under `test/fixtures/`** that decodes
      with `StatifierBlocks.Document.from_json/1` and compiles under the
      shared fixture palette, `StatifierBlocks.CoreFixtures.palette/0` (the
      core vocabulary plus the worked examples' host types), named by its
      path under `test/fixtures/`.
    * **The migration guide's composite pair**, the three document and
      declaration combinations `docs/guides/migrating-documents-0.27-to-0.34.md`
      compiles, under the core palette plus the declared composite.
    * **The byte corpus**, `StatifierBlocks.ByteCorpus.entries/0`, each under
      its own palette.
    * **The documents the shared fixture modules build**: the editor's
      documents and the map fixtures' deeper library loans, each under the
      palette its module pairs it with.

  Every entry is compiled under each of `StatifierBlocks.ByteCorpus.modes/0`
  (plain, `terminate: true`, `child_use: true`). A compile that is refused
  is pinned too, by its findings' codes, so a refusal that turns into a
  compile, or the other way, is a move.

  ## What it leaves out, and why

    * A stored document whose host types are defined inside one test file
      rather than under `test/support/` (the graph fixtures' email
      verification children, the migration guide's documents read without
      their composite declaration, and one expressibility document): no
      shared palette resolves them, and the tests that define those types
      exercise them.
    * The insert probe and the assignability worked example: their host
      types are stubs whose `emit/2` refuses, so they compile to no bytes.
    * A JSON file that is not a block document (the map graphs, the
      measurement captures, the pin files).
    * A document added after `v0.45.0` (`documents/sub_path_at_run_time/`):
      it is not an existing document, and its own tests cover it.
    * `StatifierBlocks.DocumentGenerator`: it mints fresh block ids on every
      call, so its documents have no stable bytes to pin.
    * The card and live run fixtures: they compile only when statifier-ui is
      present, and the ratchet runs in the headless job too.
    * The `core.subchart` fixtures: `StatifierBlocks.SubchartByteFixtures`
      enumerates them and `test/fixtures/subchart_bytes/literal_chart.json`
      pins them. `capture/1` recomputes every one of those pins under the
      tree it runs on and refuses when one differs, so a capture at
      `v0.45.0` proves those pins are `v0.45.0`'s too, without a second copy.

  ## Trusting or regenerating the pins

  The pins in `golden_path/0` were written by `capture/1` run in a checkout
  of the `v0.45.0` tag with this file and `subchart_byte_fixtures.ex` copied
  into its `test/support/` (neither existed there; every fixture module
  they call did, unchanged since). To re-derive them, from a clean checkout:

      git worktree add --detach ../ratchet-base v0.45.0
      cp test/support/compile_ratchet.ex test/support/subchart_byte_fixtures.ex \\
        ../ratchet-base/test/support/
      mkdir -p ../ratchet-base/test/fixtures/subchart_bytes
      cp test/fixtures/subchart_bytes/literal_chart.json \\
        ../ratchet-base/test/fixtures/subchart_bytes/
      cd ../ratchet-base && mix deps.get && MIX_ENV=test mix run \\
        -e 'StatifierBlocks.CompileRatchet.capture("ratchet.json")'

  and compare `ratchet.json` with the pinned file; they are byte-equal. A
  pin is replaced only deliberately, by a change that says in its own
  commit why that document's bytes moved.
  """

  alias StatifierBlocks.{
    Block,
    ByteCorpus,
    Compiler,
    CoreFixtures,
    Document,
    EditorFixtures,
    MapFixtures,
    Palette,
    SubchartByteFixtures
  }

  alias StatifierBlocks.Composite.Data

  @fixtures "test/fixtures"
  @migrating "documents/migrating_0_27_to_0_34"

  @doc "The release the pins were captured at."
  @spec base() :: String.t()
  def base, do: "v0.45.0"

  @doc "Where the pinned digests live."
  @spec golden_path() :: String.t()
  def golden_path, do: Path.join([@fixtures, "compile_ratchet", base() <> ".json"])

  @doc "The compile option sets every entry is pinned under."
  @spec modes() :: [{String.t(), keyword()}]
  def modes, do: ByteCorpus.modes()

  @doc "The enumeration, as `{name, document, palette}` triples, sorted by name."
  @spec entries() :: [{String.t(), Document.t(), Palette.t()}]
  def entries do
    Enum.sort_by(stored() ++ migrating() ++ corpus() ++ built(), &elem(&1, 0))
  end

  @doc """
  One entry's pin under one mode: the SHA-256 of the compiled bytes and the
  chart identity, or the sorted codes of the findings that refused it, and
  the content hash of the document compiled, so a fixture whose input
  changed is told apart from a compiler whose output did.
  """
  @spec pin(Document.t(), Palette.t(), keyword()) :: map()
  def pin(document, palette, opts) do
    input = %{"document" => Document.content_hash(document)}

    case Compiler.compile(document, palette, opts) do
      {:ok, compiled} ->
        Map.merge(input, %{
          "sha256" => digest(compiled.scxml),
          "chart_identity" => compiled.record.chart_identity.content_hash
        })

      {:error, findings} ->
        Map.put(input, "refused", findings |> Enum.map(&to_string(&1.code)) |> Enum.sort())
    end
  end

  @doc "Every pin, keyed `name-mode`."
  @spec pins() :: %{String.t() => map()}
  def pins do
    for {name, document, palette} <- entries(),
        {mode, opts} <- modes(),
        into: %{},
        do: {name <> "-" <> mode, pin(document, palette, opts)}
  end

  @doc """
  Writes `pins/0` to `path`, one key per line in key order, after checking
  that every pin in `SubchartByteFixtures.golden_path/0` matches the tree
  this runs on; raises naming the first that does not.
  """
  @spec capture(Path.t()) :: :ok
  def capture(path) do
    check_subchart_pins!()

    lines =
      pins()
      |> Enum.sort()
      |> Enum.map(fn {key, pin} -> "  " <> JSON.encode!(key) <> ": " <> encode(pin) end)

    File.write!(path, "{\n" <> Enum.join(lines, ",\n") <> "\n}\n")
  end

  @doc "The SHA-256 of `bytes`, lower-case hex."
  @spec digest(iodata()) :: String.t()
  def digest(bytes), do: :sha256 |> :crypto.hash(bytes) |> Base.encode16(case: :lower)

  # -- The enumeration -------------------------------------------------------

  defp stored do
    palette = CoreFixtures.palette()

    for path <- @fixtures |> Path.join("**/*.json") |> Path.wildcard() |> Enum.sort(),
        name = Path.relative_to(path, @fixtures),
        not String.starts_with?(name, "documents/sub_path_at_run_time/"),
        {:ok, document} <- [path |> File.read!() |> Document.from_json()],
        resolves?(document, palette) do
      {name, document, palette}
    end
  end

  defp migrating do
    for {document, declaration} <- [
          {"before", "screen_before"},
          {"before", "screen_after"},
          {"after", "screen_after"}
        ] do
      {:ok, state} = Data.declaration(read_json!(declaration))
      palette = Palette.new(Map.put(Palette.core_types(), "library.verify_email", {Data, state}))
      {:ok, decoded} = Document.from_json(File.read!(migrating_path(document)))

      {"#{@migrating}/#{document}+#{declaration}", decoded, palette}
    end
  end

  defp corpus do
    for {name, document, palette} <- ByteCorpus.entries(),
        do: {"byte_corpus/" <> name, document, palette}
  end

  defp built do
    editor = EditorFixtures.palette()

    [
      {"editor/invoke_step", EditorFixtures.invoke_step(), editor},
      {"editor/credit_card", EditorFixtures.credit_card(), editor},
      {"editor/variant_branch", Document.new(EditorFixtures.variant_branch(), id: "bdoc_VARIANT"),
       editor}
    ] ++
      for {key, document, _last, _abandoning} <- MapFixtures.deep_abandons(),
          do: {"map/" <> key, document, Palette.core()}
  end

  # A document is in the stored set when every block's type is in the
  # palette: one that names a type defined only inside a test file is not.
  defp resolves?(document, palette) do
    document
    |> Document.blocks()
    |> Enum.all?(fn %Block{type: type} -> match?({:ok, _ref}, Palette.fetch(palette, type)) end)
  end

  defp migrating_path(name), do: Path.join([@fixtures, @migrating, name <> ".json"])

  defp read_json!(name), do: name |> migrating_path() |> File.read!() |> JSON.decode!()

  # -- Capture ---------------------------------------------------------------

  defp check_subchart_pins! do
    pins = SubchartByteFixtures.golden_path() |> File.read!() |> JSON.decode!()

    for {name, document, palette} <- SubchartByteFixtures.entries(),
        {mode, opts} <- SubchartByteFixtures.modes() do
      key = name <> "-" <> mode
      {:ok, compiled} = Compiler.compile(document, palette, opts)

      unless Map.fetch!(pins, key) == %{
               "sha256" => digest(compiled.scxml),
               "chart_identity" => compiled.record.chart_identity.content_hash
             } do
        raise "the subchart pin #{key} does not match this tree"
      end
    end

    :ok
  end

  defp encode(pin) do
    fields =
      pin |> Enum.sort() |> Enum.map(fn {k, v} -> JSON.encode!(k) <> ": " <> JSON.encode!(v) end)

    "{" <> Enum.join(fields, ", ") <> "}"
  end
end
