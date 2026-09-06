# Not a LiveView test - `StatifierUI` is named at compile time here, so this
# carries `card_run_fixtures.ex`'s guard rather than the `Phoenix.LiveView`
# one `run_pane_test.exs` uses.
if Code.ensure_loaded?(StatifierUI.Live.State) do
  defmodule StatifierBlocks.LiveRunFixturesTest do
    @moduledoc """
    The live run fixture itself: a real session left running, a `State`
    that already carries `stats`, and one more macrostep per sent event.
    """

    use ExUnit.Case, async: true

    alias StatifierBlocks.LiveRunFixtures
    alias StatifierUI.EventInjection
    alias StatifierUI.Live.State

    # Sabotage: had `live/0` build its `State` with `State.new(machine,
    # messages: messages)` the way `CardRunFixtures.run/0` does, instead of
    # `State.sync/2` - `state.stats` came back `nil` and this went red on the
    # first assertion (verified).
    test "the run is live: the session is alive and stats are populated" do
      run = LiveRunFixtures.live()

      assert Process.alive?(run.session)
      assert run.state.stats != nil

      LiveRunFixtures.stop(run)
    end

    # Sabotage: dropped `live/0`'s `await_macrostep(subscriber, 1)` wait before
    # returning - `before` was snapshotted mid-initialize, sometimes missing
    # macrostep 1's own point, so the count after the send grew by two rather
    # than one and this went red (verified).
    test "sending the sample event produces exactly one more macrostep" do
      run = LiveRunFixtures.live()
      before = State.points(run.state)

      :ok =
        EventInjection.send_draft(run.session, LiveRunFixtures.sample_event(), nil)

      LiveRunFixtures.await_macrostep(run.subscriber, 2)
      after_send = LiveRunFixtures.sync(run, run.subscriber)

      assert length(State.points(after_send)) == length(before) + 1

      LiveRunFixtures.stop(run)
    end
  end
end
