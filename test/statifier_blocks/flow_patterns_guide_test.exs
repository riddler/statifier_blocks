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

  # The core.await block the page offers as the shorter answer, as the page
  # quotes it.
  @await_json """
  {"id": "blk_WAIT", "type": "core.await", "type_version": 1,
   "config": {"event": "hold.confirmed", "timeout": "1d"}}
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

  defp page, do: File.read!(@page)

  defp bounded_step do
    {:ok, document} = Document.from_json(File.read!(@bounded_step))
    document
  end

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
