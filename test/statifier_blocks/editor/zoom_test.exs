# ADR-0005 decision 1: with `phoenix_live_view` absent the editor does not
# compile, so neither can a test that drives it. The `:liveview` tag on
# `StatifierBlocks.EditorLiveCase` excludes these from a headless *run*; this
# guard is what keeps them out of a headless *compile*, which is the earlier
# of the two problems.
if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.ZoomTest do
    @moduledoc """
    Zoom and the two fits in the DOM (`sb-6ai`, the 2026-08-30 ruling).

    The arithmetic is asserted with LiveView absent, in
    `StatifierBlocks.ZoomLadderTest`, and so is the stylesheet's half of it.
    What is left here is the part that could not be: that the measurement the
    hook sends reaches the fits, that the stage is wrapped in something the
    scroller can size itself from, and that `Fit active` states an intent the
    client can carry out exactly once per press.

    The editor is fully usable with no hook imported, which is why every test
    below that needs a measurement pushes one explicitly: nothing here is
    reachable by mounting alone, and that is the point.
    """

    use StatifierBlocks.EditorLiveCase

    @card_id "blk_email_step"

    # What the browser would have measured: a tree wider than the scroller it
    # sits in, and one card in it narrow enough to fit at any step.
    @payload %{
      "stage" => %{"w" => 1000, "h" => 600},
      "viewport" => %{"w" => 800, "h" => 600},
      "anchors" => [%{"k" => "card:blk_email_step", "x" => 0, "y" => 0, "w" => 300, "h" => 40}]
    }

    defp measure(view, payload \\ @payload),
      do: view |> element("#sb-measure") |> render_hook("measure", payload)

    defp select(view),
      do:
        view
        |> element(~s([data-block-id="#{@card_id}"] > .sb-node__chrome > .sb-node__label))
        |> render_click()

    describe "the scroller is an anchor of its own" do
      # Sabotage: dropping `data-sb-anchor` from `.sb-canvas-panel` - the hook
      # finds no viewport, pushes none, and both fits go back to being modes
      # with no number behind them. Nothing else in the editor notices.
      test "the canvas panel carries the viewport anchor key", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        assert has_element?(view, ~s(.sb-canvas-panel[data-sb-anchor="viewport"]))
      end
    end

    describe "the wrapper the scroller sizes itself from" do
      # Sabotage: putting the inline size on `.sb-canvas` instead of on the
      # wrapper - the stage is then laid out at the scaled size AND scaled
      # again by the transform, so every step compounds and the connectors,
      # which are measured in the stage's own space, keep the size the stage
      # was laid out at rather than the one it is drawn at.
      test "an unzoomed canvas carries no inline geometry at all", %{conn: conn} do
        {:ok, view, html} = mount_editor(conn)

        assert html =~ ~s(class="sb-canvas-zoom")
        refute html =~ ~s(class="sb-canvas-zoom" style="width)

        measure(view)
        refute render(view) =~ ~s(class="sb-canvas-zoom" style="width)
      end

      # Sabotage: leaving the wrapper unsized - the transform still draws the
      # tree at the new size and the panel still scrolls the old one, so at
      # 200% the bottom right of the chart cannot be reached and at 50% half
      # the scroll range is empty. The screenshot at 100% looks identical.
      test "a zoomed canvas is wrapped in the scaled extent", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)
        measure(view)

        view |> element(~s(button[phx-click="zoom-out"])) |> render_click()

        assert has_element?(view, ~s(.sb-editor[data-zoom="90"]))
        assert render(view) =~ ~s(class="sb-canvas-zoom" style="width:900px;height:540px")
      end

      # Sabotage: leaving the stage to take its width from the wrapper - the
      # wrapper is sized from the stage's scroll extent and the stage is then
      # laid out into the wrapper, so above 100% each measurement makes the
      # next one bigger. The live check at 150% ran it to 33,554,428 pixels.
      test "a zoomed stage is laid out at the scroller's width", %{conn: conn} do
        {:ok, view, html} = mount_editor(conn)
        measure(view)

        refute html =~ "width:800px"
        refute render(view) =~ "width:800px"

        view |> element(~s(button[phx-click="zoom-in"])) |> render_click()

        assert render(view) =~ ~s(style="width:800px")
      end

      # Sabotage: sizing the wrapper from the zoom alone with a hard-coded
      # base - the wrapper stops following the tree, so a document with one
      # block scrolls as far as one with two hundred.
      test "the extent follows the measurement, not just the step", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)
        measure(view, %{@payload | "stage" => %{"w" => 200, "h" => 100}})

        view |> element(~s(button[phx-click="zoom-in"])) |> render_click()

        assert render(view) =~ ~s(class="sb-canvas-zoom" style="width:220px;height:110px")
      end
    end

    describe "Fit width" do
      # Sabotage: leaving the handler as `assign(socket, :fit, :width)` - which
      # is what it was, and is the whole of what this bead found: the button
      # lights up, `data-fit` changes, and the canvas is the size it was.
      test "lands on the largest step at which the tree fits the panel", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)
        measure(view)

        view |> element(~s(button[phx-value-fit="width"])) |> render_click()

        # 1000 wide into 800: 80% fits exactly, 90% would not.
        assert has_element?(view, ~s(.sb-editor[data-fit="width"][data-zoom="80"]))
        assert render(view) =~ "80%"
      end

      # Sabotage: dropping the unmeasured clause from `Shell.fit_zoom/3` - a
      # host that never imported the measurement hook gets a fit that raises
      # rather than a fit that declines, which takes the editor down.
      test "with nothing measured it is still a mode and nothing else", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        view |> element(~s(button[phx-value-fit="width"])) |> render_click()

        assert has_element?(view, ~s(.sb-editor[data-fit="width"][data-zoom="100"]))
      end
    end

    describe "Fit active" do
      # Sabotage: fitting the stage rather than the selected card - `Fit
      # active` becomes a second `Fit width` and the control that says it
      # fills the panel with one block instead fills it with the document.
      test "fits the selected card, not the whole tree", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)
        measure(view)
        select(view)

        view |> element(~s(button[phx-value-fit="active"])) |> render_click()

        # The card is 300 wide into 800: the top of the ladder still fits it,
        # where the 1000-wide tree only fitted at 80%.
        assert has_element?(view, ~s(.sb-editor[data-fit="active"][data-zoom="200"]))
      end

      # Sabotage: stamping the block id alone - the value stops changing on a
      # second press, the client sees a stamp it has already acted on, and an
      # author who scrolled away cannot get back to their own selection.
      test "stamps a reveal that changes on every press", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)
        measure(view)
        select(view)

        view |> element(~s(button[phx-value-fit="active"])) |> render_click()
        assert has_element?(view, ~s(#sb-canvas[data-sb-reveal="1:#{@card_id}"]))

        view |> element(~s(button[phx-value-fit="active"])) |> render_click()
        assert has_element?(view, ~s(#sb-canvas[data-sb-reveal="2:#{@card_id}"]))
      end

      # Sabotage: stamping the reveal before the `selected_id` check - an
      # editor with nothing selected asks the client to scroll to nothing,
      # which is a lookup that silently fails on every re-render.
      test "with nothing selected it stamps nothing and changes nothing", %{conn: conn} do
        {:ok, view, html} = mount_editor(conn)
        measure(view)

        refute html =~ "data-sb-reveal"

        view |> with_target("#editor") |> render_click("fit", %{"fit" => "active"})

        assert has_element?(view, ~s(.sb-editor[data-fit="manual"][data-zoom="100"]))
        refute render(view) =~ "data-sb-reveal"
      end
    end

    describe "the client half of the reveal" do
      # Sabotage: dropping the `stamp === this.revealed` guard from the hook -
      # every re-render re-centres the selection, so an author cannot scroll
      # away from a card they selected. No Elixir test can see that, which is
      # why the guard is asserted as a string here.
      test "the hook acts on a stamp once" do
        source = File.read!("assets/js/statifier_blocks.js")

        assert source =~ "data-sb-reveal"
        assert source =~ "stamp !== this.revealed"
        assert source =~ "panel.scrollLeft +="
        assert source =~ "panel.scrollTop +="
      end
    end
  end
end
