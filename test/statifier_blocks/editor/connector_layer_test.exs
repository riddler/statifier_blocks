# ADR-0005 decision 1: with `phoenix_live_view` absent the editor does not
# compile, so neither can a test that drives it. The `:liveview` tag on
# `StatifierBlocks.EditorLiveCase` excludes these from a headless *run*; this
# guard is what keeps them out of a headless *compile*, which is the earlier
# of the two problems.
if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.ConnectorLayerTest do
    @moduledoc """
    Decision 7's 2026-08-29 amendment, in the DOM.

    The geometry is asserted with LiveView absent, in
    `StatifierBlocks.ConnectorsTest` - that separation is clause 7b.2's whole
    point. What is left here is the part that could not be: that the
    components stamp the anchors the hook is supposed to read, that a
    measurement arriving on the wire becomes drawn paths, and above all that
    the editor is **fully usable with the hook absent**, which clause 7b.3
    makes the standing test of the amendment rather than a graceful
    degradation nicety.
    """

    use StatifierBlocks.EditorLiveCase

    alias StatifierBlocks.Connectors

    @document_id "blk_cc_flow"
    @branch_id "blk_cc_decision"

    defp measure(view, payload),
      do: view |> element("#sb-measure") |> render_hook("measure", payload)

    # What the browser would have measured, derived from the tree rather than
    # written out: every anchor the markup stamps gets a plausible box, so the
    # payload is the shape the hook sends and the test never has to be updated
    # when the fixture grows a block.
    defp measurement_of(html) do
      anchors =
        ~r/data-sb-anchor="([^"]+)"/
        |> Regex.scan(html)
        |> Enum.map(fn [_all, key] -> key end)
        |> Enum.uniq()
        |> Enum.reject(&(&1 == "stage"))
        |> Enum.with_index()
        |> Enum.map(fn {key, index} ->
          %{"k" => key, "x" => 0, "y" => index * 40, "w" => 300, "h" => 30}
        end)

      %{"stage" => %{"w" => 400, "h" => 40 * (length(anchors) + 1)}, "anchors" => anchors}
    end

    describe "the standing test of the amendment: the hook absent (7b.3)" do
      # Sabotage: rendering the `<svg>` unconditionally rather than behind
      # `drawable?/2` - a host that never imports the hook gets an empty
      # overlay with a stacking context in its editor, which is not the editor
      # it had before.
      test "nothing is measured, so no overlay is rendered at all", %{conn: conn} do
        {:ok, _view, html} = mount_editor(conn, document: EditorFixtures.credit_card())

        refute html =~ "sb-connectors"
        refute html =~ "sb-edge"
      end

      # The other half, and the one that makes the check above mean something:
      # everything else is still there.
      # Sabotage: making `Canvas` render the tree only when a stage has been
      # measured - the editor stops working without the hook, which is the
      # violation 7b.3 exists to catch.
      test "and the editor is otherwise exactly the editor it was", %{conn: conn} do
        {:ok, view, html} = mount_editor(conn, document: EditorFixtures.credit_card())

        assert html =~ ~s(data-block-id="#{@branch_id}")
        assert html =~ "sb-node__chrome"

        # A command still round-trips, which is the affordance the amendment
        # promises is untouched: measurement is not part of the drag.
        dragging =
          view
          |> element("#sb-canvas")
          |> render_hook("dragstart", %{"block-id" => @branch_id})

        assert dragging =~ ~s(data-dragging="true")
      end

      # 7a's last clause, from the server's side: an unreadable push leaves
      # the editor in the state it already had rather than crashing it.
      # Sabotage: pattern matching the payload in `handle_event("measure", ...)`
      # - a malformed push from the DOM takes the LiveView down with it.
      test "an unreadable push leaves the editor where it was", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, document: EditorFixtures.credit_card())

        html = measure(view, %{"anchors" => "not a list"})

        refute html =~ "sb-connectors"
        assert html =~ ~s(data-block-id="#{@branch_id}")
      end
    end

    describe "the anchors the components stamp (7c, and the 7d attribute name)" do
      # Sabotage: dropping `data-sb-anchor` from `BlockNode`'s card - the hook
      # measures nothing to arrive at, every edge is skipped, and the layer
      # silently draws nothing.
      test "one attribute, and the five kinds of anchor the record names", %{conn: conn} do
        {:ok, _view, html} = mount_editor(conn, document: EditorFixtures.credit_card())

        assert html =~ ~s(data-sb-anchor="#{Connectors.stage_anchor()}")
        assert html =~ ~s(data-sb-anchor="#{Connectors.node_anchor(@branch_id)}")
        assert html =~ ~s(data-sb-anchor="#{Connectors.card_anchor(@branch_id)}")
        assert html =~ ~s(data-sb-anchor="#{Connectors.outlet_anchor(@branch_id)}")
        assert html =~ ~s(data-sb-anchor="#{Connectors.slot_anchor(@branch_id, "arm_review")}")
      end

      # The body anchor, which is a container's real extent rather than the
      # narrower node box its contents overflow. It is what an interrupt
      # channel is offset from, and it is a server-side stamp: the hook's read
      # is `querySelectorAll("[data-sb-anchor]")`, so a new kind of anchor is
      # a new attribute on an element and nothing else.
      # Sabotage: dropping `data-sb-anchor` from `BlockNode`'s slots element -
      # `channel_box/2` finds no body, falls silently back to the node box,
      # and every interrupt edge on the canvas goes back to turning down
      # inside the container it is escaping.
      test "a container's body carries its own anchor", %{conn: conn} do
        {:ok, _view, html} = mount_editor(conn, document: EditorFixtures.credit_card())

        assert html =~ ~s(data-sb-anchor="#{Connectors.slots_anchor(@branch_id)}")
      end

      # Decision 7's element rule: one element carries one `phx-hook`, and the
      # canvas root is the drag hook's by decision.
      # Sabotage: moving the measure hook onto the canvas root - the drag hook
      # is displaced, every drag stops working, and this goes red first.
      test "the measure hook rides its own element, and the canvas is still the drag hook's",
           %{conn: conn} do
        {:ok, _view, html} = mount_editor(conn, document: EditorFixtures.credit_card())

        assert html =~ ~s(id="sb-canvas")
        assert html =~ ~s(phx-hook="StatifierBlocksDrag")
        assert html =~ ~s(phx-hook="StatifierBlocksMeasure")

        # The measure element exists whether or not a host imported the hook:
        # it is markup, and an unimported hook name is inert.
        assert html =~ ~s(class="sb-measure")
      end
    end

    describe "a measurement becomes drawn paths (7b.2)" do
      # Sabotage: having `handle_event("measure", ...)` store the raw params
      # instead of `Connectors.measurement/1`'s decode - `edges/2` looks up
      # `%Rect{}` structs, finds maps, and draws nothing.
      test "the overlay appears, sized from the stage, with one path per edge", %{conn: conn} do
        {:ok, view, html} = mount_editor(conn, document: EditorFixtures.credit_card())

        drawn = measure(view, measurement_of(html))

        assert drawn =~ "sb-connectors"
        assert drawn =~ ~s(viewBox="0 0 400.0)

        paths = Regex.scan(~r{class="sb-edge sb-edge--(\w+)"}, drawn)
        refute paths == []
      end

      # Clause 7b: measurement is an INPUT, never a decision. Feed it a
      # different measurement and the same document comes back.
      # Sabotage: letting `handle_event("measure", ...)` touch the document,
      # the history or the selection - the hook has started changing what the
      # editor holds, which is the thing 7a exists to forbid.
      test "a measurement changes no document, no selection and no history", %{conn: conn} do
        {:ok, view, html} = mount_editor(conn, document: EditorFixtures.credit_card())

        # Drained first: what is asserted is that the MEASUREMENT notified
        # nothing, not that the mount did not.
        _mount_noise = latest_document()

        _drawn = measure(view, measurement_of(html))

        refute latest_document(), "a measurement notified the host of a document change"
      end

      # The overlay is absent again the moment the measurement is, which is
      # what makes 7b.3 a property rather than a first-render special case.
      # Sabotage: keeping the last measurement when an empty one arrives - a
      # host that removed the hook after a render keeps stale connectors over
      # a tree that has since moved.
      test "and it goes away again when the measurement does", %{conn: conn} do
        {:ok, view, html} = mount_editor(conn, document: EditorFixtures.credit_card())

        assert measure(view, measurement_of(html)) =~ "sb-connectors"
        refute measure(view, %{}) =~ "sb-connectors"
      end
    end

    describe "the two rail vocabularies, drawn (sb-67s)" do
      # One document carrying both rail styles, so each assertion below has
      # its own control in the same render - which is the shape
      # `StatifierBlocks.Editor.FailureRailTest` uses for the same reason.
      defp rails_document do
        Document.new(
          Block.new("core.resumable_group",
            id: "blk_checkout",
            slots: %{
              "body" => [
                Block.new("core.invoke",
                  id: "blk_authorize",
                  config: %{"invoke_type" => "myapp:authorize"},
                  slots: %{"on_error" => [Block.new("core.raise", id: "blk_declined")]}
                )
              ],
              "interrupts" => [Block.new("core.on_event", id: "blk_cancelled")]
            }
          ),
          id: "doc_checkout"
        )
      end

      # `sb-67s`, in the markup this time: a failure exit shares one stylesheet
      # rule with the edge between two adjacent steps, so it can never pick up
      # the dashes or the hue that mark a way out of band.
      # Sabotage: giving the failure rail its own `:failure` kind in
      # `Connectors.rail_edge/6` - it renders as `sb-edge--failure`, the
      # distinction the ruling removed comes back one layer down, and this
      # goes red.
      test "a failure exit takes no class of its own", %{conn: conn} do
        {:ok, view, html} = mount_editor(conn, document: rails_document())

        drawn = measure(view, measurement_of(html))

        refute drawn =~ "sb-edge--failure"
        assert drawn =~ "sb-edge sb-edge--flow"
      end

      # The control that keeps the check above from passing on a render that
      # draws no rail exits at all: the OTHER vocabulary must still be there.
      # Sabotage: routing an interrupt exit as flow too - the two vocabularies
      # collapse into one, which is the bug `sb-67s` ruled in the other
      # direction, and this goes red where the check above stays green.
      test "and a secondary rail still exits out of band", %{conn: conn} do
        {:ok, view, html} = mount_editor(conn, document: rails_document())

        drawn = measure(view, measurement_of(html))

        assert drawn =~ "sb-edge sb-edge--interrupt"
        assert drawn =~ "url(#sb-arrow-interrupt)"
      end

      # The arrowhead's own geometry, which is the difference between a head
      # that lands on the endpoint at every stroke width and one that does
      # neither. Asserted in the markup because that is where it lives: an
      # SVG marker is declarative, so there is no function to hold to it.
      # Sabotage: dropping `markerUnits="userSpaceOnUse"` - the default unit
      # is `strokeWidth`, so the same head renders at a different size on a
      # hairline rejoin than on a hovered edge, and this goes red.
      test "an arrowhead is sized in user space, boxed by a viewBox, and referenced at its tip",
           %{conn: conn} do
        {:ok, view, html} = mount_editor(conn, document: EditorFixtures.credit_card())

        drawn = measure(view, measurement_of(html))

        assert drawn =~ ~s(markerUnits="userSpaceOnUse")
        assert drawn =~ ~s(viewBox="0 0 8 8")

        # The path draws to 7 and the reference point is 6.5, so the tip - not
        # the tail - is what lands on the point the geometry computed.
        assert drawn =~ ~s(refX="6.5")
        assert drawn =~ ~s(d="M0 0.5 L7 4 L0 7.5 z")
      end
    end

    describe "the whole document, at the fixture's depth" do
      # The credit-card document is a branch with three arms inside a
      # sequence, so it exercises every derivation the walk has: adjacency,
      # a container's entry, a fan and a rejoin per arm.
      # Sabotage: dropping the fan clause from `entry_edges/2` - a branch's
      # arms stop being connected to it at all and this goes red on the count.
      test "every derivation the walk has is exercised, and drawn", %{conn: conn} do
        {:ok, view, html} = mount_editor(conn, document: EditorFixtures.credit_card())

        drawn = measure(view, measurement_of(html))

        kinds =
          ~r/class="sb-edge sb-edge--(\w+)"/
          |> Regex.scan(drawn)
          |> Enum.map(fn [_all, kind] -> kind end)
          |> Enum.uniq()
          |> Enum.sort()

        assert kinds == ["fan", "flow", "join"]
      end

      # Sabotage: rendering the document root's own node without an outlet -
      # flow leaves the sequence from its header rather than from below its
      # children, and every edge out of a nested container starts in the wrong
      # place.
      test "a container's outlet is stamped below everything it contains", %{conn: conn} do
        {:ok, _view, html} = mount_editor(conn, document: EditorFixtures.credit_card())

        outlet = ~s(data-sb-anchor="#{Connectors.outlet_anchor(@document_id)}")
        card = ~s(data-sb-anchor="#{Connectors.card_anchor(@document_id)}")

        assert html =~ outlet
        assert :binary.match(html, outlet) > :binary.match(html, card)
      end
    end
  end
end
