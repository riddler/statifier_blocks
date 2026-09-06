defmodule StatifierBlocks.SourceViewTest do
  @moduledoc """
  The listing itself, headless: the lines, the spans, and what each span is
  attributed to.

  No `Code.ensure_loaded?/1` wrapper, because there is nothing to wrap.
  `StatifierBlocks.SourceView` names no LiveView module and is a pure
  function of a document and a palette, so this file is one of the ones the
  headless job runs - which is the run that proves the projection holds with
  the editor entirely off the path. Drawing it is
  `StatifierBlocks.Editor.SourceTabTest`'s claim.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{Compiled, Compiler, EditorFixtures, Provenance, SourceView}

  defp compiled do
    {:ok, %Compiled{} = compiled} =
      Compiler.compile(EditorFixtures.invoke_step(), EditorFixtures.palette())

    compiled
  end

  defp built do
    SourceView.build(EditorFixtures.invoke_step(), EditorFixtures.palette())
  end

  defp text(%SourceView.Line{spans: spans}), do: Enum.map_join(spans, & &1.text)

  defp all_spans(%SourceView{lines: lines}), do: Enum.flat_map(lines, & &1.spans)

  describe "a document that compiles" do
    # Sabotage: matching `">"` instead of `"<"` in `line_starts/1` - the
    # lines break after each tag rather than before it, and no line begins
    # with the element it is supposed to be.
    test "numbers the lines from one, with one element on each" do
      %SourceView{status: :ready, lines: lines, line_count: count} = built()

      assert count == length(lines)
      assert Enum.map(lines, & &1.number) == Enum.to_list(1..count)

      assert Enum.all?(lines, &String.starts_with?(text(&1), "<"))
      assert lines |> hd() |> text() |> String.starts_with?(~s(<scxml ))
      assert lines |> List.last() |> text() == "</scxml>"
    end

    # Sabotage: returning `binary_part(scxml, from, to - from - 1)` from
    # `span/4` - one byte per span goes missing and this goes red while every
    # per-span assertion below still passes, which is why it is asserted
    # separately.
    test "reproduces the compiled chart byte for byte" do
      %Compiled{scxml: scxml} = compiled()

      assert built() |> all_spans() |> Enum.map_join(& &1.text) == scxml
    end

    # Sabotage: reading `Provenance.owner_at(provenance, to)` instead of
    # `from` in `span/4` - the owner of the byte after the run, which is a
    # different block at every element boundary.
    test "attributes each span to the owner its own first byte resolves to" do
      %Compiled{provenance: provenance} = compiled()

      for span <- all_spans(built()), span.block_id != nil do
        assert {:ok, owner} = Provenance.owner_at(provenance, span.offset)

        assert owner.block_id == span.block_id
        assert owner.role == span.role
        assert owner.config_key == span.config_key
      end
    end

    # Sabotage: anchoring a span at the end of its run rather than the start
    # (`offset: to` in `span/4`) - every run is attributed correctly and
    # placed one run late, so the bytes the panel would highlight stop being
    # the bytes the map resolves to that block.
    test "gives a block exactly the bytes that resolve to it" do
      %Compiled{scxml: scxml, provenance: provenance} = compiled()
      view = built()

      resolved =
        for offset <- 0..(byte_size(scxml) - 1),
            {:ok, %{block_id: "blk_authorize"}} <- [Provenance.owner_at(provenance, offset)],
            into: MapSet.new(),
            do: offset

      highlighted =
        for %SourceView.Span{offset: offset, text: text} <-
              SourceView.spans_of(view, "blk_authorize"),
            byte <- offset..(offset + byte_size(text) - 1),
            into: MapSet.new(),
            do: byte

      assert MapSet.size(resolved) > 0
      assert highlighted == resolved
    end

    # Sabotage: dropping `config_key` from the struct `span/4` builds - the
    # value still highlights as the block's, and the field it was typed into
    # is gone.
    test "carries the field name on a value emitted verbatim from config" do
      assert [%SourceView.Span{} = span] =
               built()
               |> all_spans()
               |> Enum.filter(&(&1.config_key != nil))

      assert span.config_key == "invoke_type"
      assert span.text == "myapp:authorize"
      assert span.block_id == "blk_authorize"
    end

    # Sabotage: returning `depth` rather than `max(depth - 1, 0)` for a
    # closing tag in `number/1` - every close is drawn one level deeper than
    # the element it closes and the indents stop being symmetric.
    test "indents by nesting depth and closes back to it" do
      lines = built().lines

      opening = Enum.find(lines, &String.starts_with?(text(&1), ~s(<state id="s_blk_flow")))
      closing = Enum.find(lines, &(&1.number == length(lines) - 1))

      assert opening.indent == 1
      assert text(closing) == "</state>"
      assert closing.indent == 1
      assert hd(lines).indent == 0
    end
  end

  describe "a document that does not compile" do
    # Sabotage: answering `{:error, findings}` with the empty struct instead
    # of one carrying `findings` - the panel loses the reason and says only
    # that something is wrong.
    test "reports the findings and no lines" do
      view = SourceView.build(EditorFixtures.signup_wizard(), EditorFixtures.palette())

      assert %SourceView{status: :compile_error, lines: [], line_count: 0, stale?: false} = view
      assert [finding] = view.findings
      assert finding.code == :unknown_block_type
    end

    # Sabotage: dropping the `:previous` clause of `stale/2` so every failed
    # compile answers `:compile_error` - the listing an author was reading
    # disappears the moment they type a half-finished block.
    test "keeps the last chart it produced and says it is stale" do
      previous = built()

      view =
        SourceView.build(EditorFixtures.signup_wizard(), EditorFixtures.palette(),
          previous: previous
        )

      assert %SourceView{status: :ready, stale?: true} = view
      assert view.lines == previous.lines
      assert view.line_count == previous.line_count
      assert [_finding] = view.findings
    end

    # Sabotage: making `stale/2` match any previous value rather than a
    # `:ready` one - a pending or failed previous comes back marked stale,
    # claiming a chart that was never compiled.
    test "does not call a previous failure stale" do
      previous = SourceView.build(EditorFixtures.signup_wizard(), EditorFixtures.palette())

      view =
        SourceView.build(EditorFixtures.signup_wizard(), EditorFixtures.palette(),
          previous: previous
        )

      assert %SourceView{status: :compile_error, stale?: false} = view
    end
  end
end
