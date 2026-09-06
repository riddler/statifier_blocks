# ADR-0005 decision 1: with `phoenix_live_view` absent the editor does not
# compile, so neither can a test that drives it. The `:liveview` tag on
# `StatifierBlocks.EditorLiveCase` excludes these from a headless *run*; this
# guard is what keeps them out of a headless *compile*.
if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.RunPaneSendTest do
    @moduledoc """
    The Run pane's send control (`sb-djj5`): a palette drawn from the
    selected block's type's `fixtures/0` events, sending through a live
    `Statifier.Session` and never through the document.

    A separate file from `run_pane_test.exs` (which must keep passing
    untouched) because this needs a live session rather than a stopped one -
    `LiveRunFixtures.live/0` rather than `CardRunFixtures.run/0`.

    `async: false` for the same reason `run_pane_test.exs` is: the sibling
    runtime tests install stand-ins under the same application-config keys
    this file needs the real package at.
    """

    use StatifierBlocks.EditorLiveCase, async: false

    alias StatifierBlocks.{Editor, LiveRunFixtures}

    setup do
      Application.delete_env(:statifier_blocks, :run_pane_module)
      Application.delete_env(:statifier_blocks, :event_injection_module)
      Application.delete_env(:statifier_blocks, :fixtures_module)

      on_exit(fn ->
        Application.delete_env(:statifier_blocks, :run_pane_module)
        Application.delete_env(:statifier_blocks, :event_injection_module)
        Application.delete_env(:statifier_blocks, :fixtures_module)
      end)

      :ok
    end

    defp seat(view, opts) do
      Phoenix.LiveView.send_update(
        view.pid,
        Editor,
        Keyword.merge(
          [
            id: "editor",
            document: LiveRunFixtures.document(),
            palette: LiveRunFixtures.palette(),
            declare: LiveRunFixtures.declare()
          ],
          opts
        )
      )

      render(view)
      view
    end

    defp mount_run(conn, opts) do
      {:ok, view, _html} =
        mount_editor(conn,
          document: LiveRunFixtures.document(),
          palette: LiveRunFixtures.palette(),
          declare: LiveRunFixtures.declare()
        )

      {:ok, seat(view, opts)}
    end

    # The card-processing document, for the two tests that need a
    # persisted-shaped state (`CardRunFixtures.run/0`'s session is already
    # stopped) rather than the live-run document above.
    defp mount_card_run(conn, opts) do
      {:ok, view, _html} =
        mount_editor(conn,
          document: StatifierBlocks.CardRunFixtures.document(),
          palette: StatifierBlocks.CardRunFixtures.palette(),
          declare: StatifierBlocks.CardRunFixtures.declare()
        )

      Phoenix.LiveView.send_update(
        view.pid,
        Editor,
        Keyword.merge(
          [
            id: "editor",
            document: StatifierBlocks.CardRunFixtures.document(),
            palette: StatifierBlocks.CardRunFixtures.palette(),
            declare: StatifierBlocks.CardRunFixtures.declare()
          ],
          opts
        )
      )

      render(view)
      {:ok, view}
    end

    defp select(view, block_id) do
      view
      |> element(~s(.sb-node[data-block-id="#{block_id}"] > .sb-node__chrome > .sb-node__label))
      |> render_click()

      view
    end

    # `data-macrostep` is statifier-ui's own attribute and is drawn nowhere
    # but the event log (`deps/statifier_ui/lib/statifier_ui/live.ex:337`), so
    # counting its occurrences in the rendered markup is counting log rows
    # without a dependency this package does not otherwise carry in tests.
    # The run marks, the way `run_pane_test.exs` reads them. A macrostep count
    # alone cannot tell a handled event from an ignored one - the engine stamps
    # a `trace.macrostep_stable` for an external event no transition matches
    # too - so the live send test asserts the configuration actually moved.
    defp active?(view, block_id) do
      has_element?(view, ~s(.sb-node[data-block-id="#{block_id}"][data-run-active="true"]))
    end

    defp log_row_count(view) do
      view |> render() |> then(&Regex.scan(~r/data-macrostep="\d+"/, &1)) |> length()
    end

    describe "sending a fixture event into a live session" do
      # Sabotage: had the "run-send" handler drop its call to
      # `injection_module.send_draft/3` (replaced with a bare `:ok`) - nothing
      # ever reached the session, the bounded poll for macrostep 2 timed out,
      # and this raised rather than passing (verified).
      test "clicking a palette entry sends the event and the log grows by one macrostep", %{
        conn: conn
      } do
        run = LiveRunFixtures.live()

        {:ok, view} =
          mount_run(conn, run: run.state, run_session: run.session)

        select(view, LiveRunFixtures.open_block())

        before = log_row_count(view)

        view
        |> element(~s(.sb-run__send button[phx-value-event="order.approved"]))
        |> render_click()

        LiveRunFixtures.await_macrostep(run.subscriber, 2)
        seat(view, run: LiveRunFixtures.sync(run, run.subscriber))

        assert log_row_count(view) == before + 1

        # The event was handled, not merely counted: the run left the block
        # that was waiting for it and is now at the one after it.
        assert active?(view, LiveRunFixtures.done_block())
        refute active?(view, LiveRunFixtures.open_block())

        LiveRunFixtures.stop(run)
      end

      # Sabotage: had the "run-send" handler call `notify_change/2` with the
      # current document, the way an edit handler does - the host's
      # `on_change` fired with a `{:document, _}` message and this went red on
      # `refute_receive` (verified).
      test "the document is never touched by a send", %{conn: conn} do
        run = LiveRunFixtures.live()

        {:ok, view} =
          mount_run(conn, run: run.state, run_session: run.session)

        select(view, LiveRunFixtures.open_block())

        view
        |> element(~s(.sb-run__send button[phx-value-event="order.approved"]))
        |> render_click()

        refute_receive {:document, _any}

        LiveRunFixtures.await_macrostep(run.subscriber, 2)
        LiveRunFixtures.stop(run)
      end
    end

    describe "the enabled rule" do
      # Sabotage: had the pane render `disabled={false}` unconditionally
      # instead of `disabled={not @sendable?}` - every button rendered
      # enabled regardless of the run, and this went red on the
      # `:not([disabled])` refute (verified).
      test "a persisted stream with no session renders every button disabled", %{conn: conn} do
        card_run = StatifierBlocks.CardRunFixtures.run()

        {:ok, view} = mount_card_run(conn, run: card_run.state, run_session: nil)

        select(view, StatifierBlocks.CardRunFixtures.entry_block())

        assert has_element?(view, ".sb-run__send button")
        refute has_element?(view, ~s|.sb-run__send button:not([disabled])|)

        assert has_element?(
                 view,
                 ".sb-run__unavailable",
                 "A persisted run has nothing to send to."
               )

        # `blk_card_open` is configured for `"card.captured"`
        # (`CardRunFixtures.capture_event/0`), not for `core.await`'s own
        # `fixtures/0` sample name - so a button carrying the sample name
        # verbatim, and none carrying the configured event, is exactly the
        # palette rule this bead settles: entries never reconcile with the
        # block's configured `event`.
        assert has_element?(view, ~s(button[phx-value-event="order.approved"]))
        refute has_element?(view, ~s(button[phx-value-event="card.captured"]))
      end

      # Sabotage: had `run_sendable?/1` read only `assigns.run_session != nil`
      # - a live session handed in beside a persisted (`stats: nil`) state
      # would then render enabled, which is exactly the half this test pins:
      # the predicate needs BOTH the session and a live stream (verified).
      test "a live session beside a persisted state still renders disabled", %{conn: conn} do
        run = LiveRunFixtures.live()
        card_run = StatifierBlocks.CardRunFixtures.run()

        {:ok, view} = mount_card_run(conn, run: card_run.state, run_session: run.session)

        select(view, StatifierBlocks.CardRunFixtures.entry_block())

        assert has_element?(view, ".sb-run__send button")
        refute has_element?(view, ~s|.sb-run__send button:not([disabled])|)

        LiveRunFixtures.stop(run)
      end
    end

    describe "no fixture events" do
      # Sabotage: had `run_events/1` read `fixture_events/1` off a
      # hard-coded `StatifierBlocks.Core.Await` instead of the resolved
      # block's own module - the container drew `core.await`'s sample as if
      # it were its own, and this went red on the refute (verified).
      test "a block whose type declares no fixtures draws no send region", %{conn: conn} do
        run = LiveRunFixtures.live()

        {:ok, view} =
          mount_run(conn, run: run.state, run_session: run.session)

        select(view, "blk_order_flow")

        refute has_element?(view, ".sb-run__send")

        LiveRunFixtures.stop(run)
      end
    end
  end
end
