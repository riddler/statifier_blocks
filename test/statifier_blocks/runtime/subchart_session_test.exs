defmodule StatifierBlocks.Runtime.SubchartSessionTest do
  @moduledoc """
  Session-level integration for `StatifierBlocks.Runtime.Subchart` (Phase
  2, sb-6edf): a real `Statifier.Session`, over a real compiled
  `core.subchart` block document, with the handler registered and a real
  child session actually started. Phase 1's unit tests already pin every
  refusal's exact reason string and `detail` shape against `start/2`
  directly; this file's job is proving those refusals - and the two
  success paths - actually route through a live session end to end.

  `async: false` because `StatifierBlocks.RuntimeFixtures.MapResolver`
  reads its answers out of `:persistent_term`, which is process-global,
  and because `Statifier.Supervisor` is placed once for the whole suite
  in `test/test_helper.exs`.
  """

  use ExUnit.Case, async: false

  alias Statifier.Session
  alias Statifier.Testing.HandlerCase
  alias StatifierBlocks.Core.Subchart, as: SubchartBlock
  alias StatifierBlocks.Runtime.Subchart
  alias StatifierBlocks.RuntimeFixtures
  alias StatifierBlocks.RuntimeFixtures.MapResolver

  @type_string SubchartBlock.invoke_type()

  @root MapSet.new(["s_blk_ROOT"])

  defp settled(outcome), do: MapSet.union(@root, MapSet.new(["s_blk_ROOT__o_#{outcome}"]))

  describe "outcome routing" do
    # Sabotage: asserted the settle target as `settled("approved")` (the
    # first declared outcome) instead of `settled("declined")` -> the
    # session actually settles at "declined", the poll times out on the
    # wrong target, and this went red (verified).
    test "the parent settles in the outcome the child actually reported, not the first declared one" do
      MapResolver.put("bdoc_DECLINED", {:ok, RuntimeFixtures.child_document("declined")})

      parent =
        RuntimeFixtures.parent_document(
          chart: "bdoc_DECLINED",
          outcomes: ["approved", "declined"]
        )

      session = RuntimeFixtures.run(parent, MapResolver)

      try do
        assert RuntimeFixtures.await_configuration(session, settled("declined")) ==
                 settled("declined")
      after
        Session.stop(session)
      end
    end
  end

  describe "the default (unconditioned, last) arm" do
    # Sabotage: asserted the settle target as `settled("declined")`
    # instead of `settled("approved")` (the first declared outcome, which
    # is where the default arm actually lands for an unmapped "done") ->
    # the poll times out on the wrong target and this went red (verified).
    test "an outcome the parent did not declare falls through to the first declared outcome" do
      MapResolver.put("bdoc_SURPRISE", {:ok, RuntimeFixtures.trivial_child("bdoc_SURPRISE")})

      parent =
        RuntimeFixtures.parent_document(
          chart: "bdoc_SURPRISE",
          outcomes: ["approved", "declined"]
        )

      session = RuntimeFixtures.run(parent, MapResolver)

      try do
        assert RuntimeFixtures.await_configuration(session, settled("approved")) ==
                 settled("approved")
      after
        Session.stop(session)
      end
    end
  end

  describe "unknown_document" do
    # Sabotage: asserted the settle target as `running()` instead of
    # `settled("error")` -> the occupied `on_error` slot really does
    # route to the error final, the poll times out on the wrong target,
    # and this went red (verified).
    test "with on_error occupied, the parent settles in the error outcome's final" do
      parent =
        RuntimeFixtures.parent_document(chart: "bdoc_MISSING", outcomes: [], on: ["error"])

      session = RuntimeFixtures.run(parent, MapResolver)

      try do
        assert RuntimeFixtures.await_configuration(session, settled("error")) ==
                 settled("error")
      after
        Session.stop(session)
      end
    end

    # `core.subchart`'s other half, as ADR-0002's amendment of 2026-09-06
    # section 2 (the operator's ruling `RQ-034-13`) now leaves it: with
    # `on_error` empty the block still emits the
    # `error.communication.invoke` transition and the `error` final, so
    # the refusal has somewhere to route and the block ends on `error`
    # rather than parking in its inner running state forever. Before that
    # amendment this test asserted the session stayed in `running()`.
    #
    # Sabotage: restored `finals/1`'s `routed? or child` filter -> the
    # transition targets a state nothing emitted, the compile is refused,
    # and this goes red on the fixture's own compile (verified).
    test "with on_error empty, the block still ends on its error outcome" do
      parent = RuntimeFixtures.parent_document(chart: "bdoc_MISSING_EMPTY", outcomes: [])

      session = RuntimeFixtures.run(parent, MapResolver)

      try do
        assert RuntimeFixtures.await_configuration(session, settled("error")) ==
                 settled("error")
      after
        Session.stop(session)
      end
    end
  end

  describe "cycle_refused" do
    # This test's job is routing, not the reason string - a cycle refusal
    # routes through `on_error` exactly like any other refusal, and the
    # reason vocabulary itself is guarded separately below at the
    # `data.reason` level, where reason drift is actually observable.
    #
    # Sabotage: asserted the settle target as `running()` instead of
    # `settled("error")` -> a cycle refusal really does reach the error
    # final when the slot is occupied, the poll times out on the wrong
    # target, and this went red (verified).
    test "routes to the error outcome's final exactly like any other refusal" do
      MapResolver.put("bdoc_CYCLE", {:cycle, ["bdoc_A", "bdoc_B"]})

      parent = RuntimeFixtures.parent_document(chart: "bdoc_CYCLE", outcomes: [], on: ["error"])
      session = RuntimeFixtures.run(parent, MapResolver)

      try do
        assert RuntimeFixtures.await_configuration(session, settled("error")) ==
                 settled("error")
      after
        Session.stop(session)
      end
    end
  end

  describe "child_compile_findings" do
    # Sabotage: asserted the settle target as `running()` instead of
    # `settled("error")` -> a real compile finding really does reach the
    # error final through the same `on_error` route every refusal takes,
    # the poll times out on the wrong target, and this went red
    # (verified).
    test "a real compile finding (self-reference) routes to the error outcome's final" do
      MapResolver.put(
        "bdoc_SELFREF",
        {:ok, RuntimeFixtures.self_referencing_child("bdoc_SELFREF")}
      )

      parent = RuntimeFixtures.parent_document(chart: "bdoc_SELFREF", outcomes: [], on: ["error"])
      session = RuntimeFixtures.run(parent, MapResolver)

      try do
        assert RuntimeFixtures.await_configuration(session, settled("error")) ==
                 settled("error")
      after
        Session.stop(session)
      end
    end
  end

  describe "the reason vocabulary is exactly three (campaign-023 ruling R-b)" do
    # Sabotage: added a fourth entry (`"timeout"`) to the literal list on
    # the right-hand side of the comparison -> the two lists no longer
    # match by length even though every reason the module actually
    # produces is still present, and this went red (verified). This is
    # the mechanical guard: nothing here should ever need to widen it.
    test "start/2 produces no reason outside {unknown_document, child_compile_findings, cycle_refused}" do
      ctx = HandlerCase.build_ctx(@type_string, MapResolver)

      unknown =
        Subchart.start(
          HandlerCase.build_invoke(@type_string, src: "bdoc_NOWHERE"),
          ctx,
          MapResolver
        )

      cycle_document_id = "bdoc_CYCLE_GUARD"
      MapResolver.put(cycle_document_id, {:cycle, ["bdoc_A", "bdoc_B"]})

      cycle =
        Subchart.start(
          HandlerCase.build_invoke(@type_string, src: cycle_document_id),
          ctx,
          MapResolver
        )

      findings_document_id = "bdoc_FINDINGS_GUARD"

      MapResolver.put(
        findings_document_id,
        {:ok, RuntimeFixtures.self_referencing_child(findings_document_id)}
      )

      findings =
        Subchart.start(
          HandlerCase.build_invoke(@type_string, src: findings_document_id),
          ctx,
          MapResolver
        )

      reasons =
        [unknown, cycle, findings]
        |> Enum.map(fn {:ok, [{:raise, :platform, _name, _origin, [data: data]}]} ->
          data["reason"]
        end)
        |> Enum.sort()

      assert reasons == ["child_compile_findings", "cycle_refused", "unknown_document"]
    end
  end
end
