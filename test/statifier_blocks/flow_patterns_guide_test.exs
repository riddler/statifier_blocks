defmodule StatifierBlocks.FlowPatternsGuideTest do
  @moduledoc """
  The documents `docs/guides/flow-patterns.md` walks through, compiled and
  run on the current release.

  The page quotes each pattern's document byte for byte from a fixture
  under `test/fixtures/documents/flow_patterns/`, and every compiled line,
  Describe line and run outcome the page states is asserted here, so the
  guide and the package cannot drift apart silently.

  A pure test. Nothing here names LiveView, so it compiles and runs headless.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{Block, Compiler, Describe, Document, Palette, ViewModel}
  alias StatifierBlocks.Core.DeadlineRecipe
  alias StatifierBlocks.Map, as: BlockMap

  @page "docs/guides/flow-patterns.md"
  @bounded_step "test/fixtures/documents/flow_patterns/bounded_step.json"
  @optional_arms "test/fixtures/documents/flow_patterns/optional_arms.json"

  # The core.await block the page offers as the shorter answer, as the page
  # quotes it.
  @await_json """
  {"id": "blk_WAIT", "type": "core.await", "type_version": 1,
   "config": {"event": "hold.confirmed", "timeout": "1d"}}
  """

  # The two-arm core.branch the page puts in the parallel's place, as the
  # page quotes it.
  @one_branch_json """
  {"id": "blk_NOTICE", "type": "core.branch", "type_version": 1,
   "config": {"arms": [{"slot": "arm_message", "cond": "wants_message"},
                       {"slot": "arm_card", "cond": "wants_card"}]},
   "slots": {"arm_message": [{"id": "blk_MESSAGE", "type": "core.send", "type_version": 2,
                              "config": {"event": "notice.message_sent"}}],
             "arm_card": [{"id": "blk_CARD", "type": "core.send", "type_version": 2,
                           "config": {"event": "notice.card_requested"}}]}}
  """

  describe "a step that must finish within a bound: the page and its fixture" do
    # Sabotage: changed the page's `"delay": "1d"` to `"2d"` - red: the
    # page no longer quotes the fixture it names (verified).
    test "the page quotes the fixture document byte for byte" do
      assert page() =~ "```json\n" <> File.read!(@bounded_step) <> "```\n"
    end

    # Sabotage: widened `DeadlineRecipe`'s `@groups` with `core.sequence` -
    # red: the root is then answered as an enclosing group (verified).
    test "the pair is the deadline recipe's, and the recipe refuses the root" do
      document = bounded_step()

      assert DeadlineRecipe.members("blk_TIMER", document) == ["blk_TIMER", "blk_EXPIRE"]
      assert DeadlineRecipe.members("blk_EXPIRE", document) == ["blk_TIMER", "blk_EXPIRE"]

      assert DeadlineRecipe.insert({"blk_ROOT", "body", 0}, document) ==
               {:error, {:no_interrupts_slot, "blk_ROOT"}}

      assert page() =~ "`{:error, {:no_interrupts_slot, id}}`"
    end
  end

  describe "a step that must finish within a bound: the compiled chart" do
    # Sabotage: in `Emit.guarded/4`, targeted the abandon transition at the
    # group's `run` state rather than its `done` final - red here and on
    # the run at the bound (verified).
    test "compiles under the core palette with no finding, as the page quotes it" do
      assert {:ok, compiled} = Compiler.compile(bounded_step(), Palette.core())
      assert compiled.warnings == []

      for line <- [
            ~s(<send delay="1d" event="deadline.hold_confirm" id="s_blk_TIMER__send"/>),
            ~s(<transition event="deadline.hold_confirm" target="s_blk_EXPIRE__o_done">) <>
              ~s(<raise event="statifier_blocks.interrupt.abandon.s_blk_CONFIRM"/></transition>),
            ~s(<transition event="statifier_blocks.interrupt.abandon.s_blk_CONFIRM" target="s_blk_CONFIRM__o_done" type="internal"/>),
            ~s(<transition event="done.state.s_blk_CONFIRM" target="s_blk_LEND" type="internal"/>),
            ~s(<onexit><cancel sendid="s_blk_TIMER__send"/></onexit>)
          ] do
        assert compiled.scxml =~ line
        assert page() =~ line
      end
    end
  end

  describe "a step that must finish within a bound: the chart, run" do
    setup do
      {:ok, compiled} = Compiler.compile(bounded_step(), Palette.core())
      {:ok, machine} = Statifier.compile(compiled.scxml)
      {machine_state, effects} = Statifier.initialize(machine)

      %{machine_state: machine_state, initial_effects: effects}
    end

    # Sabotage: in the fixture, the handler's `outcome` set to `"resume"` -
    # red: the group restarts instead of finishing, and no checkout is sent
    # (verified).
    test "at the bound, the group finishes and the flow continues", ctx do
      assert Statifier.active_leaf_states(ctx.machine_state) ==
               MapSet.new(["s_blk_EXPIRE__armed", "s_blk_WAIT__waiting"])

      assert [%{event: "deadline.hold_confirm", send_id: "s_blk_TIMER__send"}] =
               for({:send_delayed, send} <- ctx.initial_effects, do: send)

      {:ok, machine_state, effects} =
        Statifier.send_event(ctx.machine_state, "deadline.hold_confirm")

      assert Statifier.active_leaf_states(machine_state) == MapSet.new(["s_blk_ROOT__o_done"])
      assert sent(effects) == ["loan.checked_out"]
    end

    # Sabotage: in `Cancels.onexit/2`, emitted no `<cancel>` element -
    # red: a confirmed hold left its day-long timer behind (verified).
    test "confirmed in time, the flow continues the same way and the timer is cancelled", ctx do
      {:ok, machine_state, effects} = Statifier.send_event(ctx.machine_state, "hold.confirmed")

      assert Statifier.active_leaf_states(machine_state) == MapSet.new(["s_blk_ROOT__o_done"])
      assert sent(effects) == ["loan.checked_out"]
      assert for({:cancel, cancel} <- effects, do: cancel.send_id) == ["s_blk_TIMER__send"]
    end
  end

  describe "a step that must finish within a bound: what Describe and the Map show" do
    # Sabotage: in the fixture, the handler's event renamed to
    # `deadline.other` - red: no timer line, and the members test above
    # goes red with it (verified).
    test "the Describe lines and the Map's edges the page quotes" do
      document = bounded_step()
      lines = Describe.render(Describe.outline(document, Palette.core(), []), [])

      for line <- [
            "In 1 day, send deadline.hold_confirm",
            "When deadline.hold_confirm, abandon",
            "After Run interruptible steps (done), Send loan.checked_out",
            "On deadline.hold_confirm, When deadline.hold_confirm, abandon abandons the group",
            "In 1 day, deadline.hold_confirm reaches When deadline.hold_confirm, abandon"
          ] do
        assert line in lines
        assert page() =~ line
      end

      graph = document |> ViewModel.build(Palette.core(), []) |> BlockMap.graph()

      assert BlockMap.interrupts(graph) == [
               %{"from" => "blk_EXPIRE", "group" => "blk_CONFIRM", "to" => "exit"}
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

  describe "a step that must finish within a bound: the core.await alternative" do
    # Sabotage: in `Await.outcomes/1`, dropped `timed_out` - red
    # (verified).
    test "the await the page quotes compiles in the group's place and continues either way" do
      assert page() =~ "```json\n" <> @await_json <> "```\n"

      document = with_await_in_place_of_group(bounded_step())

      assert {:ok, compiled} = Compiler.compile(document, Palette.core())
      assert compiled.warnings == []

      assert compiled.scxml =~
               ~s(<transition event="done.state.s_blk_WAIT" target="s_blk_LEND" type="internal"/>)

      lines = Describe.render(Describe.outline(document, Palette.core(), []), [])

      line =
        "After Wait for hold.confirmed, giving up after 1d (received, timed_out), Send loan.checked_out"

      assert line in lines
      assert page() =~ line

      {:ok, machine} = Statifier.compile(compiled.scxml)
      {machine_state, _effects} = Statifier.initialize(machine)

      for event <- ["hold.confirmed", "statifier_blocks.await.blk_WAIT"] do
        {:ok, after_event, effects} = Statifier.send_event(machine_state, event)
        assert Statifier.active_leaf_states(after_event) == MapSet.new(["s_blk_ROOT__o_done"])
        assert sent(effects) == ["loan.checked_out"]
      end
    end
  end

  describe "a branch whose outcome may be both arms: the page and its fixture" do
    # Sabotage: changed the page's `"complete": "all"` to `"first"` - red:
    # the page no longer quotes the fixture it names (verified).
    test "the page quotes the fixture document byte for byte, and lists the pattern" do
      assert page() =~ "```json\n" <> File.read!(@optional_arms) <> "```\n"

      assert page() =~
               "- [A branch whose outcome may be both arms](#a-branch-whose-outcome-may-be-both-arms)\n"

      assert page() =~ "\n## A branch whose outcome may be both arms\n"
    end
  end

  describe "a branch whose outcome may be both arms: the compiled chart" do
    # Sabotage: in the fixture, the parallel's `complete` set to `"first"` -
    # red: no transition on the run's `done.state`, the block finishes per
    # lane instead (verified).
    test "compiles under the core palette with no finding, as the page quotes it" do
      assert {:ok, compiled} = Compiler.compile(optional_arms(), Palette.core())
      assert compiled.warnings == []

      for line <- [
            ~s(<transition cond="wants_message" target="s_blk_MESSAGE"/>) <>
              ~s(<transition target="s_blk_IF_MESSAGE__o_done"/>),
            ~s(<transition event="done.state.s_blk_IF_CARD" target="s_blk_NOTICE__done_lane_card" type="internal"/>),
            ~s(<transition event="done.state.s_blk_NOTICE__run" target="s_blk_NOTICE__o_done" type="internal"/>),
            ~s(<transition event="done.state.s_blk_NOTICE" target="s_blk_DELIVER" type="internal"/>)
          ] do
        assert compiled.scxml =~ line
        assert page() =~ line
      end
    end
  end

  describe "a branch whose outcome may be both arms: the chart, run" do
    setup do
      {:ok, compiled} = Compiler.compile(optional_arms(), Palette.core())
      {:ok, machine} = Statifier.compile(compiled.scxml)

      %{machine: machine}
    end

    # Sabotage: in the fixture, the parallel's `complete` set to `"first"` -
    # red: the message lane wins the race, and the parcel goes out before
    # the card is posted (verified).
    test "both asked: both lanes run, and the flow waits for the card", ctx do
      {machine_state, effects} = start(ctx.machine, true, true)

      assert sent(effects) == ["notice.message_sent", "notice.card_requested"]

      assert Statifier.active_leaf_states(machine_state) ==
               MapSet.new(["s_blk_NOTICE__done_lane_message", "s_blk_POSTED__waiting"])

      {:ok, machine_state, effects} = Statifier.send_event(machine_state, "notice.card_posted")

      assert Statifier.active_leaf_states(machine_state) == MapSet.new(["s_blk_ROOT__o_done"])
      assert sent(effects) == ["parcel.out_for_delivery"]
      assert page() =~ "- **Both asked.**"
    end

    # Sabotage: in the fixture, the message branch's condition set to
    # `true` - red: a message goes to a recipient who did not ask for one (verified).
    test "one asked: only that lane's step runs", ctx do
      {machine_state, effects} = start(ctx.machine, true, false)

      assert Statifier.active_leaf_states(machine_state) == MapSet.new(["s_blk_ROOT__o_done"])
      assert sent(effects) == ["notice.message_sent", "parcel.out_for_delivery"]

      {machine_state, effects} = start(ctx.machine, false, true)
      assert sent(effects) == ["notice.card_requested"]

      {:ok, machine_state, effects} = Statifier.send_event(machine_state, "notice.card_posted")

      assert Statifier.active_leaf_states(machine_state) == MapSet.new(["s_blk_ROOT__o_done"])
      assert sent(effects) == ["parcel.out_for_delivery"]
    end

    # Sabotage: in the fixture, the card branch's condition set to `true` -
    # red: the chart parks on the card for a recipient who asked for
    # nothing (verified).
    test "neither asked: every lane finishes at once and the flow continues", ctx do
      {machine_state, effects} = start(ctx.machine, false, false)

      assert Statifier.active_leaf_states(machine_state) == MapSet.new(["s_blk_ROOT__o_done"])
      assert sent(effects) == ["parcel.out_for_delivery"]
    end
  end

  describe "a branch whose outcome may be both arms: what Describe and the Map show" do
    # Sabotage: in the fixture, the lane `card` renamed `post` (in
    # `lanes` and its slot key) - red: the Map's second lane is titled
    # `post`, not the `card` the page names (verified).
    test "the Describe lines and the Map's lanes the page quotes" do
      document = optional_arms()
      lines = Describe.render(Describe.outline(document, Palette.core(), []), [])

      for line <- [
            "Run 2 lanes at the same time (all of)",
            ~s[Decide: When "asked", otherwise (one of)],
            "After Run 2 lanes at the same time (done), Send parcel.out_for_delivery",
            "The branch: when wants_message, Send notice.message_sent",
            "The branch: when wants_card, Send notice.card_requested",
            "The branch: otherwise, the end of the branch"
          ] do
        assert line in lines
        assert page() =~ line
      end

      graph = document |> ViewModel.build(Palette.core(), []) |> BlockMap.graph()
      parallel = find_node(graph, "blk_NOTICE")

      assert for(lane <- parallel["children"], do: {lane["id"], lane["title"]}) == [
               {"blk_NOTICE/lane_message", "message"},
               {"blk_NOTICE/lane_card", "card"}
             ]

      for {lane, branch} <- [{"lane_message", "blk_IF_MESSAGE"}, {"lane_card", "blk_IF_CARD"}] do
        assert [%{"id" => ^branch} = node] = find_node(graph, "blk_NOTICE/" <> lane)["children"]

        assert for(slot <- node["children"], do: slot["title"]) ==
                 [~s(When "asked"), "Otherwise", "Cannot be decided"]
      end
    end
  end

  describe "a branch whose outcome may be both arms: how it differs from a branch" do
    # Sabotage: in `Branch.emit/2`, reversed the arms' order - red: the
    # card is requested and the message is not (verified).
    test "a two-arm branch in the parallel's place takes only the first arm that holds" do
      assert page() =~ "```json\n" <> @one_branch_json <> "```\n"

      document = with_first_step(optional_arms(), JSON.decode!(@one_branch_json))

      assert {:ok, compiled} = Compiler.compile(document, Palette.core())
      assert compiled.warnings == []

      {:ok, machine} = Statifier.compile(compiled.scxml)
      {machine_state, effects} = start(machine, true, true)

      assert Statifier.active_leaf_states(machine_state) == MapSet.new(["s_blk_ROOT__o_done"])
      assert sent(effects) == ["notice.message_sent", "parcel.out_for_delivery"]
    end

    # Sabotage: in the fixture, the card lane's await removed - red: with
    # nothing to wait for, the message goes out at once in a row too (verified).
    test "one-arm branches in a row take both, but the second waits for the first" do
      document = with_lanes_in_a_row(optional_arms(), ["lane_card", "lane_message"])

      assert {:ok, compiled} = Compiler.compile(document, Palette.core())
      assert compiled.warnings == []

      {:ok, machine} = Statifier.compile(compiled.scxml)
      {machine_state, effects} = start(machine, true, true)

      assert sent(effects) == ["notice.card_requested"]

      {:ok, machine_state, effects} = Statifier.send_event(machine_state, "notice.card_posted")

      assert Statifier.active_leaf_states(machine_state) == MapSet.new(["s_blk_ROOT__o_done"])
      assert sent(effects) == ["notice.message_sent", "parcel.out_for_delivery"]
    end
  end

  defp page, do: File.read!(@page)

  defp bounded_step do
    {:ok, document} = Document.from_json(File.read!(@bounded_step))
    document
  end

  defp optional_arms do
    {:ok, document} = Document.from_json(File.read!(@optional_arms))
    document
  end

  # Starts the parcel notice chart with the recipient's two answers in the
  # datamodel, as a host supplies them.
  defp start(machine, wants_message, wants_card) do
    Statifier.initialize(machine,
      datamodel: %{"wants_message" => wants_message, "wants_card" => wants_card}
    )
  end

  # The document with its root's first step (the parallel) replaced by the
  # decoded block JSON, re-read through the document decoder.
  defp with_first_step(document, step) do
    document
    |> document_json()
    |> update_in(["root", "slots", "body"], fn [_parallel | rest] -> [step | rest] end)
    |> decode_json()
  end

  # The document with the parallel taken out and its lanes' blocks put in
  # the root's body one after the other, in the order given.
  defp with_lanes_in_a_row(document, lanes) do
    document
    |> document_json()
    |> update_in(["root", "slots", "body"], fn [parallel | rest] ->
      Enum.flat_map(lanes, &parallel["slots"][&1]) ++ rest
    end)
    |> decode_json()
  end

  defp document_json(document), do: document |> Document.to_json() |> JSON.decode!()

  defp decode_json(map) do
    {:ok, document} = map |> JSON.encode!() |> Document.from_json()
    document
  end

  defp find_node(%{"id" => id} = node, id), do: node

  defp find_node(%{"children" => children}, id),
    do: Enum.find_value(children, &find_node(&1, id))

  defp find_node(_node, _id), do: nil

  defp with_await_in_place_of_group(%Document{root: %Block{slots: slots} = root} = document) do
    %{"id" => id, "type" => type, "type_version" => version, "config" => config} =
      JSON.decode!(@await_json)

    await = Block.new(type, id: id, type_version: version, config: config)

    body =
      Enum.map(slots["body"], fn
        %Block{id: "blk_CONFIRM"} -> await
        block -> block
      end)

    %{document | root: %{root | slots: %{slots | "body" => body}}}
  end

  defp sent(effects), do: for({:send, send} <- effects, do: send.event)
end
