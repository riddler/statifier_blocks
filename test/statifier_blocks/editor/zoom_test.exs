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

    alias StatifierBlocks.Shell

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

    describe "the fit a host opens at (sb-ehqn)" do
      # Sabotage: dropping the `open_at_fit/1` call from the measure handler -
      # the attr sets the mode, the button lights up, and the canvas stays at
      # 100%, which is `Fit width` never pressed and the defect 017's capture
      # finding 2 recorded.
      test "fit: :width lands on the step the ladder computes for those numbers", %{conn: conn} do
        {:ok, view, html} = mount_editor(conn, fit: :width)

        # Before the first measurement it is a mode and nothing else, which is
        # also what a host that never imported the hook has forever.
        assert html =~ ~s(data-fit="width")
        assert has_element?(view, ~s(.sb-editor[data-fit="width"][data-zoom="100"]))

        measure(view)

        # The same number the button computes: the 1000-wide stage into the
        # 800-wide scroller the payload carries.
        assert Shell.fit_zoom(1000, 800, 100) == 80
        assert has_element?(view, ~s(.sb-editor[data-fit="width"][data-zoom="80"]))
      end

      # Sabotage: leaving the armed fit armed - dropping `assign(:fit_pending,
      # nil)` from `open_at_fit/1` - so every later measurement spends it
      # again and an author who zooms in is thrown back to the fit by the next
      # resize or font swap. A measurement is not a gesture, and this is the
      # difference between opening at a fit and being held in one.
      test "the fit happens once: a later measurement leaves the author's zoom alone", %{
        conn: conn
      } do
        {:ok, view, _html} = mount_editor(conn, fit: :width)
        measure(view)

        view |> element(~s(button[phx-click="zoom-in"])) |> render_click()
        assert has_element?(view, ~s(.sb-editor[data-fit="manual"][data-zoom="90"]))

        measure(view)

        assert has_element?(view, ~s(.sb-editor[data-fit="manual"][data-zoom="90"]))
      end

      # The host re-renders here with the document it already has open at a
      # later revision - a changed struct, the same `Document.id` - which is
      # what a host does after it persists an edit, and it stands for every
      # re-render a host makes for a reason of its own. None of them is an
      # opening, so none of them may re-fit; the swap that *is* an opening is
      # the test below it. The revision has to move for the re-render to
      # happen at all: `assign/3` drops a value equal to the one it holds, so
      # a host handing back an identical struct never reaches `update/2` and
      # would prove nothing either way.
      # Sabotage: re-arming whenever the host re-renders with the attr - a
      # host that re-renders for any reason of its own resets the author's
      # zoom, and the attr stops being an *opening* state.
      test "a host re-render carrying the same attr does not re-fit", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, fit: :width)
        measure(view)

        view |> element(~s(button[phx-click="zoom-out"])) |> render_click()
        assert has_element?(view, ~s(.sb-editor[data-fit="manual"][data-zoom="67"]))

        same = EditorFixtures.signup_wizard()
        send(view.pid, {:swap_document, %{same | revision: same.revision + 1}})

        assert has_element?(view, ~s(.sb-editor[data-revision="1"]))
        refute render(view) =~ "data-fit-pending"

        measure(view)

        assert has_element?(view, ~s(.sb-editor[data-fit="manual"][data-zoom="67"]))
      end

      # Sabotage: defaulting the pending fit to `:width` instead of to nothing
      # - every editor in the family opens fitted, which is a change of
      # behaviour for every host that never asked for one.
      test "the default is manual, and a measurement moves nothing", %{conn: conn} do
        for opts <- [[], [fit: :manual]] do
          {:ok, view, _html} = mount_editor(conn, opts)
          measure(view)

          assert has_element?(view, ~s(.sb-editor[data-fit="manual"][data-zoom="100"]))
        end
      end

      # Sabotage: assigning the raw attr instead of `Shell.fit_mode/1` - the
      # canvas is stamped `data-fit="cover"`, no stylesheet rule matches it,
      # and a typo in a host template is a mode the editor cannot leave.
      test "an unknown fit is refused into manual, not carried into the DOM", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, fit: :cover)
        measure(view)

        assert has_element?(view, ~s(.sb-editor[data-fit="manual"][data-zoom="100"]))
        refute render(view) =~ "cover"
      end

      # Sabotage: resolving `:active` against the stage - opening at `:active`
      # with nothing selected silently becomes `Fit width`, which is a mode
      # the host did not ask for.
      test "fit: :active with nothing selected is a mode and nothing else", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, fit: :active)
        measure(view)

        assert has_element?(view, ~s(.sb-editor[data-fit="active"][data-zoom="100"]))
        refute render(view) =~ "data-sb-reveal"
      end
    end

    describe "the pre-fit gate (sb-oje0)" do
      # The frame between the mount and the first payload is the whole defect:
      # it is laid out at 100% and the frame after it is at the fit. The attr
      # is what the stylesheet holds that frame back by, so it has to be on
      # the DEAD render too - the dead render is the first thing painted.
      # Sabotage: rendering `data-fit-pending` only when `measured?` is true -
      # the attr appears one frame after the flash it exists to cover, which
      # is every frame except the one that matters.
      test "an armed fit is stamped on the root, dead render included", %{conn: conn} do
        dead =
          render_component(StatifierBlocks.Editor,
            id: "editor",
            document: EditorFixtures.signup_wizard(),
            palette: EditorFixtures.palette(),
            fit: :width
          )

        assert dead =~ ~s(data-fit-pending="width")

        {:ok, view, html} = mount_editor(conn, fit: :width)

        assert html =~ ~s(data-fit-pending="width")
        assert has_element?(view, ~s(.sb-editor[data-fit-pending="width"][data-zoom="100"]))
      end

      # The gate is the armed fit's shadow and nothing else: it has to lift on
      # the same payload that spends the fit, in the same render, or the stage
      # stays hidden past the frame it was hidden for.
      # Sabotage: stamping the attr off `@fit` instead of `@fit_pending` - it
      # never drops for a host that opened at `:width`, and the canvas is
      # revealed only by the 500ms fallback, on every mount, forever.
      test "the stamp drops on the measurement that spends the fit", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, fit: :width)

        measure(view)

        assert has_element?(view, ~s(.sb-editor[data-fit="width"][data-zoom="80"]))
        refute has_element?(view, ~s(.sb-editor[data-fit-pending]))
        refute render(view) =~ "data-fit-pending"
      end

      # A host that did not opt into a fit has no frame to hide, and hiding
      # one would be this bead inventing a blank first paint for every editor
      # in the family.
      # Sabotage: stamping the attr unconditionally - every editor opens
      # hidden, and a hook-less host with `fit: :manual` waits 500ms for a
      # canvas that was correct from the first frame.
      test "a manual editor is never stamped, before or after measuring", %{conn: conn} do
        for opts <- [[], [fit: :manual]] do
          {:ok, view, html} = mount_editor(conn, opts)

          refute html =~ "data-fit-pending"

          measure(view)

          refute render(view) =~ "data-fit-pending"
        end
      end

      # `:active` arms a fit that resolves against a selection a mount does
      # not have, so it moves no canvas - but it is still armed, and it is
      # still spent by the first payload. The gate follows the arming, not the
      # outcome, or `fit: :active` flashes exactly as `:width` used to.
      # Sabotage: arming the gate only for `:width` - the mode a host uses to
      # open on the selected card is the one mode left unguarded.
      test "an armed :active fit is gated and released the same way", %{conn: conn} do
        {:ok, view, html} = mount_editor(conn, fit: :active)

        assert html =~ ~s(data-fit-pending="active")

        measure(view)

        refute render(view) =~ "data-fit-pending"
      end

      # A document the host swaps in is an opening of its own, so it takes the
      # whole of the mount path: armed from the attr in that same update,
      # gated while the browser has not measured the new tree, and spent by
      # the payload that arrives after the patch. The second payload is a
      # wider stage than the first, so the zoom it lands on could only have
      # come from re-computing the fit - the first document's 80% would still
      # be on the canvas if nothing re-armed.
      # Sabotage: dropping the swapped-document clause from `arm_fit/4` - the
      # canvas keeps the zoom the *previous* document was fitted at, which is
      # the defect a host that swaps documents sees on every switch.
      test "a swapped document is armed, gated, and fitted again", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, fit: :width)
        measure(view)

        assert has_element?(view, ~s(.sb-editor[data-fit="width"][data-zoom="80"]))
        refute render(view) =~ "data-fit-pending"

        send(view.pid, {:swap_document, EditorFixtures.credit_card()})

        assert has_element?(view, ~s(.sb-editor[data-fit-pending="width"][data-zoom="80"]))

        measure(view, %{
          @payload
          | "stage" => %{"w" => 1600, "h" => 600}
        })

        assert has_element?(view, ~s(.sb-editor[data-fit="width"][data-zoom="50"]))
        refute render(view) =~ "data-fit-pending"
      end

      # The re-arm is the attr's, not the swap's: a host that never asked for
      # a fit does not start getting one because it changed document, and a
      # swap under `:manual` stamps no gate to hide a canvas that was correct.
      # Sabotage: arming the swapped clause unconditionally instead of from
      # `mode` - every host that swaps documents gets a fit it never opted
      # into, and the manual editor blanks for a frame on every switch.
      test "a swap under :manual arms nothing and gates nothing", %{conn: conn} do
        for opts <- [[], [fit: :manual]] do
          {:ok, view, _html} = mount_editor(conn, opts)
          measure(view)

          send(view.pid, {:swap_document, EditorFixtures.credit_card()})

          refute render(view) =~ "data-fit-pending"

          measure(view, %{@payload | "stage" => %{"w" => 1600, "h" => 600}})

          assert has_element?(view, ~s(.sb-editor[data-fit="manual"][data-zoom="100"]))
        end
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
