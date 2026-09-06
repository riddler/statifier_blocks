# ADR-0005 decision 1: with `phoenix_live_view` absent the editor does not
# compile, so neither can a test that drives it. The `:liveview` tag on
# `StatifierBlocks.EditorLiveCase` excludes these from a headless *run*; this
# guard is what keeps them out of a headless *compile*.
if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.SourceTabTest do
    @moduledoc """
    The Source drawer tab: the compiled chart, drawn.

    What is asserted here is what only a rendered drawer can show - that the
    tab is on the strip carrying the line count, that selecting a block
    highlights exactly the spans the provenance map attributes to it, that a
    span is a live route back to its block through the editor's own `select`
    event, and that a document that stops compiling keeps the last chart with
    a line saying so. The listing itself is
    `StatifierBlocks.SourceViewTest`'s claim, headless, where the projection
    lives.
    """

    use StatifierBlocks.EditorLiveCase

    alias StatifierBlocks.{Compiled, Compiler, Provenance, SourceView}

    defp open(view) do
      view |> element(".sb-drawer__strip") |> render_click()
      view |> element(~s(.sb-drawer__tab[phx-value-tab="source"])) |> render_click()
      view
    end

    defp compiled(document) do
      {:ok, %Compiled{} = compiled} = Compiler.compile(document, EditorFixtures.palette())
      compiled
    end

    # The `data-block` of every span the panel drew as selected, in order.
    defp highlighted(html) do
      ~r/<button[^>]*data-block="([^"]*)"[^>]*data-selected="true"/
      |> Regex.scan(html)
      |> Enum.map(&Enum.at(&1, 1))
    end

    # The `data-offset` of every span the panel drew as selected.
    defp highlighted_offsets(html) do
      ~r/<button[^>]*data-offset="(\d+)"[^>]*data-selected="true"/
      |> Regex.scan(html)
      |> Enum.map(&(&1 |> Enum.at(1) |> String.to_integer()))
    end

    defp line_numbers(html) do
      ~r/<li[^>]*data-line="(\d+)"/
      |> Regex.scan(html)
      |> Enum.map(&(&1 |> Enum.at(1) |> String.to_integer()))
    end

    describe "the tab" do
      # Sabotage: dropping `:source` from `Shell`'s `@drawer_tabs` - the tab
      # is not on the strip, `open/1` cannot reach the panel, and every test
      # in this file goes red at the second click.
      test "is on the strip and its count is the number of lines", %{conn: conn} do
        document = EditorFixtures.invoke_step()
        {:ok, view, _html} = mount_editor(conn, document: document)

        html = open(view) |> render()
        expected = SourceView.build(document, EditorFixtures.palette()).line_count

        assert has_element?(view, ~s(#sb-drawer-tab-source[aria-selected="true"]))
        assert view |> element("#sb-drawer-tab-source") |> render() =~ "Source"
        assert view |> element("#sb-drawer-tab-source") |> render() =~ "(#{expected})"
        assert length(line_numbers(html)) == expected
      end

      # Sabotage: rendering `data-line="1"` on every line - the listing still
      # draws every element and the numbers stop naming which one.
      test "lists the chart with line numbers, one element per line", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, document: EditorFixtures.invoke_step())

        html = open(view) |> render()
        numbers = line_numbers(html)

        assert numbers == Enum.to_list(1..length(numbers))
        assert html =~ "&lt;scxml"
        assert html =~ "&lt;/scxml&gt;"
      end
    end

    describe "the selection" do
      # Sabotage: rendering `data-selected="true"` unconditionally on every
      # span - the panel highlights the whole chart for any selection and the
      # byte-for-byte comparison below goes red.
      test "highlights exactly the bytes provenance gives the selected block", %{conn: conn} do
        document = EditorFixtures.invoke_step()
        {:ok, view, _html} = mount_editor(conn, document: document)

        view |> element(~s(.sb-node__label[phx-value-block-id="blk_authorize"])) |> render_click()
        html = open(view) |> render()

        %Compiled{scxml: scxml, provenance: provenance} = compiled(document)
        listing = SourceView.build(document, EditorFixtures.palette())

        resolved =
          for offset <- 0..(byte_size(scxml) - 1),
              {:ok, %{block_id: "blk_authorize"}} <- [Provenance.owner_at(provenance, offset)],
              into: MapSet.new(),
              do: offset

        drawn =
          for offset <- highlighted_offsets(html),
              %SourceView.Span{offset: ^offset, text: text} <-
                SourceView.spans_of(listing, "blk_authorize"),
              byte <- offset..(offset + byte_size(text) - 1),
              into: MapSet.new(),
              do: byte

        assert highlighted(html) != []
        assert Enum.uniq(highlighted(html)) == ["blk_authorize"]
        assert drawn == resolved
      end

      # Sabotage: dropping `phx-click="select"` from the span - the source is
      # still readable and stops being a way back to the block that produced
      # it, which is the whole of what makes it a debugger surface.
      test "selects the owning block when a span is clicked", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, document: EditorFixtures.invoke_step())

        open(view)
        _ = selections()

        # The config-emitted value's own span, which is the narrowest one the
        # listing draws and the one an author would click to ask "where did
        # this come from".
        view
        |> element(~s(.sb-source__span[data-config-key="invoke_type"]))
        |> render_click()

        assert [%{id: "blk_authorize"}] = selections()
        assert Enum.uniq(highlighted(render(view))) == ["blk_authorize"]

        # And back the other way, from a span the panel is drawing as the
        # other block's: the click follows the span rather than the
        # highlight, and the highlight follows the click.
        view
        |> element(~s(.sb-source__span[data-block="blk_flow"][data-offset="0"]))
        |> render_click()

        assert [%{id: "blk_flow"}] = selections()
        assert Enum.uniq(highlighted(render(view))) == ["blk_flow"]
      end

      # Sabotage: dropping the `title` attribute from the span - the value an
      # author typed is still highlighted and no longer says which field it
      # came from, which is the one thing the byte on its own cannot say.
      test "titles a config-emitted span with the field name", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, document: EditorFixtures.invoke_step())

        html = open(view) |> render()

        assert [config_span] =
                 Regex.scan(~r/<button[^>]*data-config-key="invoke_type"[^>]*>/, html)
                 |> Enum.map(&hd/1)

        assert config_span =~ ~s(title="invoke_type")
        assert html =~ "myapp:authorize"
      end
    end

    describe "a document that stops compiling" do
      # Sabotage: passing `previous: nil` from `refresh_source_view/1` - the
      # panel empties on the first edit that does not compile instead of
      # keeping the chart the author was reading.
      test "keeps the last chart and says it is stale", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, document: EditorFixtures.invoke_step())

        before = open(view) |> render()
        refute before =~ "Compiled from an earlier document"

        send(view.pid, {:swap_document, EditorFixtures.signup_wizard()})
        after_swap = open(view) |> render()

        assert after_swap =~ "Compiled from an earlier document"
        assert line_numbers(after_swap) == line_numbers(before)
      end
    end
  end
end
