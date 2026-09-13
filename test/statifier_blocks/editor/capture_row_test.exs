# ADR-0005 decision 1: with `phoenix_live_view` absent the editor does not
# compile, so neither can a test that drives it. The pure halves of decision
# 10 - that a capture's targets are write signatures, and that they reach the
# declared-path advisory - live in `StatifierBlocks.EnvironmentTest` and
# `StatifierBlocks.DatamodelTest`, deliberately outside this guard.
if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.CaptureRowTest do
    @moduledoc """
    `core.on_event`'s capture, authored (ADR-0011 decision 10): a repeated
    two-control row, one row per pair, a datamodel path written beside a path
    inside the firing event's payload.

    It is a repeated row and not a field, because ADR-0002 decision 7's
    closed field-type set has no member describing a map and declined to add
    one - so there is no `config_schema/1` declaration to render from, and
    what is asserted here is that the pairs are drawn from the config, that
    the source control is offered the type's own fixture payload, and that
    filling the trailing blank row writes a pair while clearing a row
    removes one.
    """

    use StatifierBlocks.EditorLiveCase

    defp document(capture) do
      Document.new(
        Block.new("core.group",
          id: "blk_order",
          slots: %{
            "body" => [
              Block.new("core.await", id: "blk_wait", config: %{"event" => "order.paid"})
            ],
            "interrupts" => [
              Block.new("core.on_event",
                id: "blk_cancel",
                config:
                  Map.merge(
                    %{"event" => "order.cancelled", "outcome" => "abandon"},
                    if(capture == nil, do: %{}, else: %{"capture" => capture})
                  )
              )
            ]
          }
        ),
        id: "doc_order"
      )
    end

    defp view(conn, opts \\ []) do
      {:ok, view, _html} = mount_editor(conn, document: document(Keyword.get(opts, :capture)))

      view
      |> element(
        ~s([data-block-id="#{Keyword.get(opts, :select, "blk_cancel")}"] ) <>
          ~s(> .sb-node__chrome > .sb-node__label)
      )
      |> render_click()

      view
    end

    defp change(view, params) do
      view
      |> element(~s(form[data-block-id="blk_cancel"]))
      |> render_change(Map.put(params, "block-id", "blk_cancel"))

      view
    end

    describe "the row" do
      # Sabotage: made `capture_pairs/1` answer `nil` for every selection ->
      # the section is absent and every assertion here goes red (verified).
      # Before this bead there was no control at all: the key was authored
      # through the document and not through the editor.
      test "a stored pair draws its two controls", %{conn: conn} do
        view = view(conn, capture: %{"order.cancel_reason" => "reason"})

        assert has_element?(view, ~s(.sb-capture[data-capture-rows="1"]))

        assert has_element?(
                 view,
                 ~s(.sb-capture__row[data-capture-row="0"] input[value="order.cancel_reason"])
               )

        assert has_element?(
                 view,
                 ~s(.sb-capture__row[data-capture-row="0"] input[value="reason"])
               )
      end

      # The trailing blank row is what adds a pair, so it is there whether
      # or not anything is stored.
      #
      # Sabotage: dropped the `++ [{"", ""}]` from the row list -> a handler
      # that captures nothing offers no way to start, and this goes red on
      # both halves (verified).
      test "there is always one blank row at the end", %{conn: conn} do
        assert has_element?(view(conn), ~s(.sb-capture[data-capture-rows="0"]))
        assert has_element?(view(conn), ~s(.sb-capture__row[data-capture-row="0"]))

        stored = view(conn, capture: %{"order.cancel_reason" => "reason"})
        assert has_element?(stored, ~s(.sb-capture__row[data-capture-row="1"]))
      end

      # Sabotage: replaced the `@on_event_type` guard on `capture_pairs/1`
      # with a match on any node -> every selected block grows a capture
      # section and this goes red (verified).
      test "a block that takes no capture map draws no row", %{conn: conn} do
        refute has_element?(view(conn, select: "blk_wait"), ".sb-capture")
      end
    end

    describe "a literal pair (ADR-0005's Note of 2026-09-13)" do
      # The two controls a capture row offers are a datamodel path and a
      # path in the payload, and a literal is neither - so the pair is
      # rendered rather than offered. Before this bead it drew nothing at
      # all: `capture_pairs/1` filtered the source position for a binary.
      #
      # Sabotage: dropped `capture_row/1`'s const clause, so a literal pair
      # drew nothing again -> the literal row is absent and this test and
      # the carry-over one below both go red (verified).
      test "draws a read-only row spelling the value the document holds", %{conn: conn} do
        view = view(conn, capture: %{"answer.choice" => ["const", "yes"]})

        assert has_element?(
                 view,
                 ~s(.sb-capture__row--literal[data-capture-literal="answer.choice"])
               )

        assert render(view) =~ "the literal &quot;yes&quot;"
      end

      # It is a rendering and not a control, so it posts nothing: the two
      # inputs a path row draws are not there for it, and the trailing
      # blank row is still index 0 because the literal takes no index.
      #
      # Sabotage: routed the literal through the same two-control row a
      # path pair draws -> its target appears in an input and the blank row
      # no longer sits at index 0, taking this test and the two beside it
      # red (verified).
      test "offers no control for the literal, and takes no row index", %{conn: conn} do
        view = view(conn, capture: %{"answer.choice" => ["const", "yes"]})

        refute has_element?(view, ~s(input[value="answer.choice"]))
        assert has_element?(view, ~s(.sb-capture__row[data-capture-row="0"] input[value=""]))
      end

      # The defect this row is half of: the posted rows ARE the map, so a
      # form that drew no control for a pair replaced it away on the next
      # change the author made anywhere in the block.
      #
      # Sabotage: dropped `carried_literals/1` from `decode_capture/2`'s
      # merge -> the literal pair is gone after one keystroke and this goes
      # red (verified).
      test "survives an edit to the rest of the block", %{conn: conn} do
        view =
          conn
          |> view(capture: %{"answer.choice" => ["const", "yes"], "order.why" => "reason"})
          |> change(%{
            "config" => %{"event" => "order.cancelled", "outcome" => "resume"},
            "capture" => %{"0" => %{"target" => "order.why", "source" => "reason"}}
          })

        assert has_element?(
                 view,
                 ~s(.sb-capture__row--literal[data-capture-literal="answer.choice"])
               )

        assert has_element?(
                 view,
                 ~s(.sb-capture__row[data-capture-row="0"] input[value="order.why"])
               )
      end

      # A source in neither form is malformed, which `validate_config/1`
      # refuses and no control here could repair - so it draws no row, and
      # it is not carried over either: carrying it would make a refusal the
      # author cannot see permanent.
      #
      # Sabotage: widened `capture_row/1`'s tagged clause to `[_tag, value]`
      # -> the wrong-tag source drew a literal row and the first assertion
      # went red (verified).
      test "a malformed source draws no row", %{conn: conn} do
        view = view(conn, capture: %{"answer.choice" => ["konst", "yes"]})

        refute has_element?(view, ".sb-capture__row--literal")
        assert has_element?(view, ~s(.sb-capture[data-capture-rows="0"]))
      end
    end

    describe "the source control's candidates" do
      # ADR-0011 decision 10: a handler's fixture payload is the only place
      # in the package that knows what an event of that name carries.
      #
      # Sabotage: made `fixture_events/1` answer `%{}` -> no datalist is
      # drawn and this goes red (verified).
      test "the payload keys of the configured event are offered", %{conn: conn} do
        view = view(conn)

        assert has_element?(
                 view,
                 ~s(datalist#sb-capture-sources-blk_cancel[data-capture-sources="2"])
               )

        assert has_element?(
                 view,
                 ~s(datalist#sb-capture-sources-blk_cancel option[value="reason"])
               )

        assert has_element?(view, ~s(datalist#sb-capture-sources-blk_cancel option[value="at"]))

        assert has_element?(
                 view,
                 ~s(.sb-capture__source[list="sb-capture-sources-blk_cancel"])
               )
      end
    end

    describe "editing" do
      # Sabotage: made `decode_capture/2` ignore the posted rows -> the pair
      # never reaches the config and this goes red (verified).
      test "filling the blank row writes a pair", %{conn: conn} do
        view =
          conn
          |> view()
          |> change(%{
            "config" => %{"event" => "order.cancelled", "outcome" => "abandon"},
            "capture" => %{"0" => %{"target" => "order.cancel_reason", "source" => "reason"}}
          })

        assert has_element?(view, ~s(.sb-capture[data-capture-rows="1"]))

        assert has_element?(
                 view,
                 ~s(.sb-capture__row[data-capture-row="0"] input[value="order.cancel_reason"])
               )
      end

      # Sabotage: dropped the `Enum.reject/2` that discards an empty row ->
      # a cleared row is stored as `%{"" => ""}`, the pair never goes away,
      # and this goes red (verified).
      test "clearing both controls of a row removes its pair", %{conn: conn} do
        view =
          conn
          |> view(capture: %{"order.cancel_reason" => "reason"})
          |> change(%{
            "config" => %{"event" => "order.cancelled", "outcome" => "abandon"},
            "capture" => %{
              "0" => %{"target" => "", "source" => ""},
              "1" => %{"target" => "", "source" => ""}
            }
          })

        assert has_element?(view, ~s(.sb-capture[data-capture-rows="0"]))
      end

      # A half-typed row is a draft the document refuses, not bytes to throw
      # away between keystrokes.
      #
      # Sabotage: rejected a row with a blank target as well -> the source
      # the author just typed disappears on the next change and this goes
      # red (verified).
      test "a row with only a source is kept, and refused", %{conn: conn} do
        view =
          conn
          |> view()
          |> change(%{
            "config" => %{"event" => "order.cancelled", "outcome" => "abandon"},
            "capture" => %{"0" => %{"target" => "", "source" => "reason"}}
          })

        assert has_element?(
                 view,
                 ~s(.sb-capture__row[data-capture-row="0"] input[value="reason"])
               )

        assert has_element?(view, ".sb-form .sb-finding")
      end
    end
  end
end
