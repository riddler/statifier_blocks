defmodule StatifierBlocks.Core.SubchartBytesTest do
  @moduledoc """
  A `core.subchart` that names its child by `chart` keeps its bytes when
  `chart_from` is added (ADR-0004's Amendment of 2026-11-19, J1 and J2):
  every fixture `StatifierBlocks.SubchartByteFixtures` enumerates compiles,
  under every mode, to the SHA-256 of the bytes and to the chart identity
  pinned in `test/fixtures/subchart_bytes/literal_chart.json`.

  The pins were captured from `origin/main` at `51cb2bc`, before any code
  of the change that added `chart_from` was written, so the assertion is a
  claim about the tree before it and not a restatement of today's output.
  A pin is replaced only deliberately, by a change that says in its own
  commit why the literal form's bytes moved.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{Compiler, SubchartByteFixtures}

  @pins SubchartByteFixtures.golden_path() |> File.read!() |> JSON.decode!()

  # sabotage: emitted the reserved outcomes param on every subchart, the
  # literal form included -> every fixture's digest moves and this goes red
  # on each of them (verified)
  for {name, _document, _palette} <- SubchartByteFixtures.entries(),
      {mode, _opts} <- SubchartByteFixtures.modes() do
    test "#{name} keeps its bytes and chart identity under #{mode}" do
      {_name, document, palette} =
        Enum.find(SubchartByteFixtures.entries(), &(elem(&1, 0) == unquote(name)))

      {_mode, opts} = Enum.find(SubchartByteFixtures.modes(), &(elem(&1, 0) == unquote(mode)))

      assert {:ok, compiled} = Compiler.compile(document, palette, opts)

      assert %{"sha256" => sha256, "chart_identity" => identity} =
               Map.fetch!(@pins, unquote(name <> "-" <> mode))

      assert digest(compiled.scxml) == sha256
      assert compiled.record.chart_identity.content_hash == identity
    end
  end

  # A pin nobody reaches proves nothing: the pinned names are exactly the
  # ones the enumeration compiles, in both directions.
  test "the pins and the enumeration name the same fixtures" do
    expected =
      for {name, _document, _palette} <- SubchartByteFixtures.entries(),
          {mode, _opts} <- SubchartByteFixtures.modes(),
          do: name <> "-" <> mode

    assert Enum.sort(Map.keys(@pins)) == Enum.sort(expected)
  end

  defp digest(bytes), do: :sha256 |> :crypto.hash(bytes) |> Base.encode16(case: :lower)
end
