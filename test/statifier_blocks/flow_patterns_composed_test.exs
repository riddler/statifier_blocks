defmodule StatifierBlocks.FlowPatternsComposedTest do
  @moduledoc """
  The three patterns `docs/guides/flow-patterns.md` shows one by one,
  composed in one document: optional arms (a `core.parallel` whose lanes
  are each guarded by a one-arm `core.branch`), with the bounded step (a
  `core.group` carrying the deadline recipe around a `core.await`) in one
  lane, and the park (a `core.group` whose body is a `core.wait` and whose
  rail carries handlers) in the other.

  The document is `test/fixtures/documents/flow_patterns/composed.json`, in
  the guide's library world: a hold is placed, the desk may be asked to
  confirm it within a day, the item may wait on the hold shelf for seven
  days, and the hold is closed when both lanes are done. The compiled lines
  each pattern carries are the guide's own lines, byte for byte, which is
  what shows that nesting a pattern inside another changes nothing about it.

  A pure test. Nothing here names LiveView, so it compiles and runs headless.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{Compiler, Describe, Document, Finding, Palette, Publish, ViewModel}
  alias StatifierBlocks.Map, as: BlockMap

  @page "docs/guides/flow-patterns.md"
  @composed "test/fixtures/documents/flow_patterns/composed.json"

  # One day and seven days, as the host is asked to schedule the two
  # delayed sends.
  @one_day_ms 24 * 60 * 60 * 1000
  @seven_days_ms 7 * @one_day_ms

  describe "the composed document: publish and compile" do
    # Sabotage: in the fixture, the parallel's `complete` set to `"every"`
    # - red: Publish reports an error finding on `complete` (verified).
    test "Publish reports no error, and it compiles under the core palette with no warning" do
      document = composed()

      assert for(
               %Finding{severity: :error} = finding <- Publish.findings(document, palette(), %{}),
               do: finding
             ) == []

      assert {:ok, compiled} = Compiler.compile(document, palette())
      assert compiled.warnings == []
      assert {:ok, _machine} = Statifier.compile(compiled.scxml)
    end
  end

  describe "the composed document: the compiled chart" do
    # Sabotage: in the fixture, the deadline handler (`blk_EXPIRE`) dropped
    # from the group's rail - red here on the deadline's interrupt
    # transition, and red on the two run tests that ask for the confirm
    # lane and on the Describe test below; no Publish finding and no
    # compile warning appear, so the first test stays green (verified).
    # Sabotage: in the fixture, the deadline's send moved out of the group
    # to just ahead of it in the branch arm - red here: the send is no
    # longer inside the group (verified).
    test "each pattern's timers and interrupt transitions are the guide's own lines" do
      assert {:ok, compiled} = Compiler.compile(composed(), palette())

      # The bounded step, inside the confirm lane's group: the guide's
      # first pattern. The hold shelf, inside the shelf lane's group: the
      # guide's third pattern.
      for {group, lines} <- [
            {"s_blk_CONFIRM",
             [
               ~s(<send delay="1d" event="deadline.hold_confirm" id="s_blk_TIMER__send"/>),
               ~s(<transition event="deadline.hold_confirm" target="s_blk_EXPIRE__o_done">) <>
                 ~s(<raise event="statifier_blocks.interrupt.abandon.s_blk_CONFIRM"/></transition>),
               ~s(<transition event="statifier_blocks.interrupt.abandon.s_blk_CONFIRM" target="s_blk_CONFIRM__o_done" type="internal"/>),
               ~s(<onexit><cancel sendid="s_blk_TIMER__send"/></onexit>)
             ]},
            {"s_blk_SHELF",
             [
               ~s(<send delay="7d" event="statifier_blocks.wait.blk_SHELVED" id="s_blk_SHELVED__send"/>),
               ~s(<transition event="hold.collected" target="s_blk_COLLECTED__o_done">) <>
                 ~s(<raise event="statifier_blocks.interrupt.abandon.s_blk_SHELF"/></transition>),
               ~s(<transition event="done.state.s_blk_SHELF__body" target="s_blk_SHELF__o_done" type="internal"/>),
               ~s(<transition event="statifier_blocks.interrupt.abandon.s_blk_SHELF" target="s_blk_SHELF__o_done" type="internal"/>),
               ~s(<onexit><cancel sendid="s_blk_SHELVED__send"/></onexit>)
             ]}
          ],
          line <- lines do
        assert within(compiled.scxml, group, group <> "__o_done") =~ line
        assert page() =~ line
      end

      for {lane, group} <- [{"confirm", "s_blk_CONFIRM"}, {"shelf", "s_blk_SHELF"}] do
        lane_xml =
          within(
            compiled.scxml,
            "s_blk_PICKUP__lane_" <> lane,
            "s_blk_PICKUP__done_lane_" <> lane
          )

        assert lane_xml =~ within(compiled.scxml, group, group <> "__o_done")
      end

      # The optional arms around them: the guide's second pattern, with
      # this document's lanes and guards.
      for line <- [
            ~s(<transition cond="wants_confirmation" target="s_blk_CONFIRM"/>) <>
              ~s(<transition target="s_blk_IF_CONFIRM__o_done"/>),
            ~s(<transition cond="held_on_shelf" target="s_blk_SHELF"/>) <>
              ~s(<transition target="s_blk_IF_SHELF__o_done"/>),
            ~s(<transition event="done.state.s_blk_CONFIRM" target="s_blk_IF_CONFIRM__o_done" type="internal"/>),
            ~s(<transition event="done.state.s_blk_SHELF" target="s_blk_IF_SHELF__o_done" type="internal"/>),
            ~s(<transition event="done.state.s_blk_IF_CONFIRM" target="s_blk_PICKUP__done_lane_confirm" type="internal"/>),
            ~s(<transition event="done.state.s_blk_IF_SHELF" target="s_blk_PICKUP__done_lane_shelf" type="internal"/>),
            ~s(<transition event="done.state.s_blk_PICKUP__run" target="s_blk_PICKUP__o_done" type="internal"/>),
            ~s(<transition event="done.state.s_blk_PICKUP" target="s_blk_CLOSE" type="internal"/>)
          ] do
        assert compiled.scxml =~ line
      end
    end
  end

  describe "the composed document: the chart, run" do
    setup do
      {:ok, compiled} = Compiler.compile(composed(), palette())
      {:ok, machine} = Statifier.compile(compiled.scxml)

      %{machine: machine}
    end

    # Sabotage: in `Cancels.onexit/2`, emitted no `<cancel>` element - red:
    # the bound abandons the group and leaves its day-long timer behind
    # (verified).
    test "both asked: each lane arms its own deadline, and the bound fails open inside its lane",
         ctx do
      {machine_state, effects} = start(ctx.machine, true, true)

      assert sent(effects) == ["hold.placed"]

      assert delayed(effects) == [
               {"deadline.hold_confirm", @one_day_ms},
               {"statifier_blocks.wait.blk_SHELVED", @seven_days_ms}
             ]

      assert Statifier.active_leaf_states(machine_state) ==
               MapSet.new([
                 "s_blk_WAIT__waiting",
                 "s_blk_EXPIRE__armed",
                 "s_blk_SHELVED__waiting",
                 "s_blk_COLLECTED__armed",
                 "s_blk_CANCELLED__armed"
               ])

      {:ok, machine_state, effects} =
        Statifier.send_event(machine_state, "deadline.hold_confirm")

      assert sent(effects) == []
      assert cancelled(effects) == ["s_blk_TIMER__send"]

      assert Statifier.active_leaf_states(machine_state) ==
               MapSet.new([
                 "s_blk_PICKUP__done_lane_confirm",
                 "s_blk_SHELVED__waiting",
                 "s_blk_COLLECTED__armed",
                 "s_blk_CANCELLED__armed"
               ])

      {:ok, machine_state, effects} = Statifier.send_event(machine_state, "hold.collected")

      assert Statifier.active_leaf_states(machine_state) == MapSet.new(["s_blk_ROOT__o_done"])
      assert sent(effects) == ["hold.closed"]
      assert cancelled(effects) == ["s_blk_SHELVED__send"]
    end

    # Sabotage: in the fixture, the two branches' conditions swapped - red:
    # the shelf lane parks and the confirm lane arms no deadline (verified).
    test "only the confirm lane asked: the bound alone ends the pickup", ctx do
      {machine_state, effects} = start(ctx.machine, true, false)

      assert delayed(effects) == [{"deadline.hold_confirm", @one_day_ms}]

      assert Statifier.active_leaf_states(machine_state) ==
               MapSet.new([
                 "s_blk_WAIT__waiting",
                 "s_blk_EXPIRE__armed",
                 "s_blk_PICKUP__done_lane_shelf"
               ])

      {:ok, machine_state, effects} =
        Statifier.send_event(machine_state, "deadline.hold_confirm")

      assert Statifier.active_leaf_states(machine_state) == MapSet.new(["s_blk_ROOT__o_done"])
      assert sent(effects) == ["hold.closed"]
      assert cancelled(effects) == ["s_blk_TIMER__send"]
    end

    # Sabotage: in the fixture, the shelf branch's condition set to `true`
    # - red: the chart parks on the hold shelf for a hold that asked for
    # neither lane (verified).
    test "neither asked: every lane finishes at once, with no timer, and the hold is closed",
         ctx do
      {machine_state, effects} = start(ctx.machine, false, false)

      assert Statifier.active_leaf_states(machine_state) == MapSet.new(["s_blk_ROOT__o_done"])
      assert sent(effects) == ["hold.placed", "hold.closed"]
      assert delayed(effects) == []
    end
  end

  describe "the composed document: what Describe and the Map show" do
    # Sabotage: in the fixture, the lane `shelf` renamed `rack` (in
    # `lanes` and its slot key) - red: the Map's second lane is titled
    # `rack`, not `shelf` (verified).
    test "Describe names every arm, and the Map draws both lanes and every edge" do
      document = composed()
      lines = Describe.render(Describe.outline(document, palette(), []), [])

      for line <- [
            "Run 2 lanes at the same time (all of)",
            "After Run 2 lanes at the same time (done), Send hold.closed",
            "The branch: when wants_confirmation, Run interruptible steps",
            "The branch: when held_on_shelf, Run interruptible steps",
            "In 1 day, send deadline.hold_confirm",
            "When deadline.hold_confirm, abandon",
            "On deadline.hold_confirm, When deadline.hold_confirm, abandon abandons the group",
            "In 1 day, deadline.hold_confirm reaches When deadline.hold_confirm, abandon",
            "Wait 7d",
            "Wait 7d (done) ends the group",
            "On hold.collected, When hold.collected, abandon abandons the group",
            "On hold.cancelled, When hold.cancelled, abandon abandons the group"
          ] do
        assert line in lines
      end

      assert Enum.count(lines, &(&1 == ~s[Decide: When "asked", otherwise (one of)])) == 2
      assert Enum.count(lines, &(&1 == "The branch: otherwise, the end of the branch")) == 2

      graph = document |> ViewModel.build(palette(), []) |> BlockMap.graph()
      parallel = find_node(graph, "blk_PICKUP")

      assert for(lane <- parallel["children"], do: {lane["id"], lane["title"]}) == [
               {"blk_PICKUP/lane_confirm", "confirm"},
               {"blk_PICKUP/lane_shelf", "shelf"}
             ]

      assert BlockMap.interrupts(graph) == [
               %{"from" => "blk_EXPIRE", "group" => "blk_CONFIRM", "to" => "exit"},
               %{"from" => "blk_COLLECTED", "group" => "blk_SHELF", "to" => "exit"},
               %{"from" => "blk_CANCELLED", "group" => "blk_SHELF", "to" => "exit"}
             ]

      assert BlockMap.timers(graph) == [
               %{
                 "from" => "blk_TIMER",
                 "to" => "blk_EXPIRE",
                 "event" => "deadline.hold_confirm",
                 "delay" => "1d"
               }
             ]
    end
  end

  defp page, do: File.read!(@page)

  defp palette, do: Palette.core()

  defp composed do
    {:ok, document} = Document.from_json(File.read!(@composed))
    document
  end

  # Starts the chart with the hold's two answers in the datamodel, as a host
  # supplies them.
  defp start(machine, wants_confirmation, held_on_shelf) do
    Statifier.initialize(machine,
      datamodel: %{
        "wants_confirmation" => wants_confirmation,
        "held_on_shelf" => held_on_shelf
      }
    )
  end

  # The compiled chart's state `id`, from its opening tag to the final
  # `final` it closes with: everything the state holds that this test
  # looks for.
  defp within(scxml, id, final) do
    [_before, rest] = String.split(scxml, ~s(<state id="#{id}"), parts: 2)
    [inside, _after] = String.split(rest, ~s(<final id="#{final}"), parts: 2)
    inside
  end

  defp sent(effects), do: for({:send, send} <- effects, do: send.event)

  defp delayed(effects),
    do: for({:send_delayed, send} <- effects, do: {send.event, send.delay_ms})

  defp cancelled(effects), do: for({:cancel, cancel} <- effects, do: cancel.send_id)

  defp find_node(%{"id" => id} = node, id), do: node

  defp find_node(%{"children" => children}, id),
    do: Enum.find_value(children, &find_node(&1, id))

  defp find_node(_node, _id), do: nil
end
