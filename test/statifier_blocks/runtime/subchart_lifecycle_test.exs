defmodule StatifierBlocks.Runtime.SubchartLifecycleTest do
  @moduledoc """
  Pins `StatifierBlocks.Runtime.Subchart`'s two lifecycle callbacks -
  `cancel/2` and `forward/3` - against a real `Statifier.Session` (Phase
  3, sb-6edf). Both need hand-written SCXML fixtures rather than compiled
  block documents:

    * the compiled `core.subchart` `<invoke>` carries no `autoforward`
      attribute, so no block document can produce an autoforwarding
      subchart (`test/fixtures/runtime/autoforward_parent.scxml`);
    * the compiled `core.subchart` block leaves its `__running` state only
      on `done.invoke`/`error.communication.invoke`, so nothing an
      in-flight test can send cancels it
      (`test/fixtures/runtime/cancel_parent.scxml`).

  Both fixtures still resolve through the real handler and the real
  resolver seam (`StatifierBlocks.RuntimeFixtures.MapResolver`) - only the
  driving chart is hand-written. See each fixture file's own comment for
  why it cannot be replaced with a block document.

  `async: false` for the same reasons `SubchartSessionTest` is:
  `MapResolver` reads its answers out of process-global
  `:persistent_term`, and `Statifier.Supervisor` is placed once for the
  whole suite in `test/test_helper.exs`.
  """

  use ExUnit.Case, async: false

  alias Statifier.Session
  alias StatifierBlocks.Runtime.Subchart
  alias StatifierBlocks.RuntimeFixtures
  alias StatifierBlocks.RuntimeFixtures.MapResolver

  @autoforward_fixture "test/fixtures/runtime/autoforward_parent.scxml"
  @cancel_fixture "test/fixtures/runtime/cancel_parent.scxml"

  # Bounded poll for `Statifier.Session.invocations/1` to become non-empty
  # - the initial macrostep that plans and starts (or refuses) the
  # `<invoke>` runs asynchronously after `start_link/2` returns
  # (`handle_continue`), so a caller reading the table immediately after
  # start_link may still see it empty. Mirrors
  # `RuntimeFixtures.await_configuration/3`'s own shape rather than a bare
  # fixed-duration sleep.
  defp await_invocation(session, attempts \\ 200) do
    case Session.invocations(session) do
      [] when attempts > 0 ->
        Process.sleep(5)
        await_invocation(session, attempts - 1)

      other ->
        other
    end
  end

  # Bounded poll for a cancelled child to reach terminal status
  # `:cancelled` - `Session.cancel/1` runs the child's `<onexit>` handlers
  # before halting it (6.4.3), so that is not necessarily synchronous with
  # the `:stop_child` instruction that triggers it. Deliberately not a
  # poll for the process to *exit*: `Statifier.Session`'s own moduledoc
  # ("`:done` idles the session; it does not stop it") states that `:done`
  # and `:cancelled` alike leave the process alive and inspectable at its
  # terminal status - stopping is only ever the caller's or the
  # supervisor's own move, never `cancel/1`'s.
  defp await_status(pid, expected, attempts \\ 200) do
    case Session.status(pid).status do
      ^expected ->
        :ok

      other when attempts == 0 ->
        flunk(
          "expected #{inspect(pid)} to reach status #{inspect(expected)}, got #{inspect(other)}"
        )

      _other ->
        Process.sleep(5)
        await_status(pid, expected, attempts - 1)
    end
  end

  describe "autoforward" do
    # Sabotage: changed `forward/3` in
    # `lib/statifier_blocks/runtime/subchart.ex` to `def forward(_id, _event, _ctx),
    # do: {:ok, []}` (dropping the `{:forward, invoke_id, event}`
    # instruction entirely) -> the parent's `autoforward="true"` invoke
    # never delivers "go" into the child, the child never reaches its
    # "arrived" outcome, `await_configuration`'s bounded poll ran out, and
    # this went red on the `flunk` naming the observed `s_invoking`
    # configuration instead of `s_arrived` (verified). Reverted after
    # confirming red.
    test "the parent's autoforward delivers the event into the child, which only then finishes" do
      MapResolver.put(
        "bdoc_AUTOFORWARD_CHILD",
        {:ok, RuntimeFixtures.waiting_child_document("go", "arrived", "bdoc_AUTOFORWARD_CHILD")}
      )

      {:ok, machine} = Statifier.compile(File.read!(@autoforward_fixture))

      {:ok, session} =
        Session.start_link(machine, invoke_handlers: Subchart.handlers(MapResolver))

      try do
        # Nothing routes "go" to the child directly - only the parent's
        # own autoforward can. Sending it to the *parent* is the whole
        # point of this test.
        Session.send_event(session, "go")

        assert RuntimeFixtures.await_configuration(session, MapSet.new(["s_arrived"])) ==
                 MapSet.new(["s_arrived"])
      after
        Session.stop(session)
      end
    end
  end

  describe "cancel" do
    # Sabotage: changed `cancel/2` in
    # `lib/statifier_blocks/runtime/subchart.ex` to `def cancel(_id, _ctx),
    # do: {:ok, []}` (dropping the `{:stop_child, invoke_id}` instruction)
    # -> the child is never asked to cancel, so it never reaches
    # `:cancelled` status, `await_status`'s bounded poll ran out, and this
    # went red on the `flunk` naming the observed status instead
    # (verified). Reverted after confirming red.
    test "cancel/2 really routes to this handler and stops the live child" do
      MapResolver.put(
        "bdoc_CANCEL_CHILD",
        {:ok,
         RuntimeFixtures.waiting_child_document(
           "child_never_arrives",
           "done",
           "bdoc_CANCEL_CHILD"
         )}
      )

      {:ok, machine} = Statifier.compile(File.read!(@cancel_fixture))

      {:ok, session} =
        Session.start_link(machine, invoke_handlers: Subchart.handlers(MapResolver))

      try do
        assert [%{invoke_id: "inv_sub", pid: pid}] = await_invocation(session)
        assert is_pid(pid)
        assert Process.alive?(pid)

        Session.send_event(session, "cancel.now")

        assert RuntimeFixtures.await_configuration(session, MapSet.new(["s_cancelled"])) ==
                 MapSet.new(["s_cancelled"])

        assert Session.invocations(session) == []

        # Deviation from the plan's exact wording: the plan says to
        # assert the child pid "is no longer alive". Verified against
        # `deps/statifier/lib/statifier/session.ex`'s own moduledoc
        # ("`:done` idles the session; it does not stop it" - true "with
        # a narrower meaning" for `:cancelled` too), a cancelled child's
        # process stays alive and inspectable at terminal status
        # `:cancelled`; only an explicit `stop/2` (the caller's or a
        # supervisor's) ever ends the process. Asserting non-aliveness
        # would assert something the engine does not do. What actually
        # proves `cancel/2` reached the child is asserted instead: it
        # reaches `:cancelled` status, and the process is still alive to
        # report it.
        await_status(pid, :cancelled)
        assert Process.alive?(pid)
      after
        Session.stop(session)
      end
    end

    # The counterintuitive half of the contract: after an `unknown_document`
    # refusal there IS a live invocation entry, because the engine writes a
    # `{:notify, {:invoke, invoke}}`-driven entry for any *registered* type
    # before `start/2`'s own instructions run, regardless of what `start/2`
    # answers (`deps/statifier/lib/statifier/session.ex:1724`). That
    # pid-less entry is what lets a later cancel still route back to this
    # handler's own `cancel/2` instead of the built-in default. Asserting
    # `Session.invocations/1 == []` immediately after the refusal would
    # fail - deliberately not asserted here.
    #
    # Sabotage: asserted `pid: :anything_but_nil` (a value no pid-less
    # entry ever carries) on the first `assert [%{...}] = ...` match ->
    # the match itself fails against the real `pid: nil` entry, and this
    # went red on the pattern-match `MatchError` (verified). Reverted
    # after confirming red.
    test "cancel of an invocation that never started: a pid-less entry, popped with no process signalled" do
      # Deliberately not put for this document id: `MapResolver`
      # defaults an un-put document id to `:error`, which is
      # `"unknown_document"` - the refusal this test needs.
      MapResolver.put("bdoc_CANCEL_CHILD", :error)

      {:ok, machine} = Statifier.compile(File.read!(@cancel_fixture))

      {:ok, session} =
        Session.start_link(machine, invoke_handlers: Subchart.handlers(MapResolver))

      try do
        # The pid-less entry: live, but with nothing to cancel or
        # monitor. This is the contract, not a bug - see the moduledoc
        # comment above.
        assert [%{invoke_id: "inv_sub", pid: nil}] = await_invocation(session)

        # This fixture's SCXML carries no `error.communication.invoke`
        # transition at all (it is hand-written, not compiled from
        # `core.subchart`), so the refusal has nowhere to route and the
        # session simply stays in `s_invoking` with the pid-less entry
        # still live - exactly `core.subchart`'s own documented
        # empty-slot behaviour, pinned here at the raw-SCXML level. Only
        # the ordinary external event exits the invoking state.
        Session.send_event(session, "cancel.now")

        assert RuntimeFixtures.await_configuration(session, MapSet.new(["s_cancelled"])) ==
                 MapSet.new(["s_cancelled"])

        # The entry is popped by `{:stop_child, invoke_id}`'s dedicated
        # `{%{pid: nil}, invocations}` clause - a no-op that drops the
        # table entry with no process to demonitor or cancel - not by an
        # absent entry ever having been there.
        assert Session.invocations(session) == []
      after
        Session.stop(session)
      end
    end
  end
end
