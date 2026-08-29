defmodule StatifierBlocks.Core.EmitTest do
  use ExUnit.Case, async: true

  alias StatifierBlocks.{Block, Compiler, Document, Palette}
  alias StatifierBlocks.Compiler.Context
  alias StatifierBlocks.Core.{Emit, OnEvent}
  alias StatifierBlocks.CoreFixtures

  describe "the one convention (ADR-0004 decision 2)" do
    # sabotage: drop the <final> child from Core.Emit.ordered/2 -> the
    # block's state stops being compound-with-a-final and this goes red for
    # every core type (verified)
    test "every core type compiles to one compound state carrying a <final>" do
      for {type_name, module} <- CoreFixtures.core_modules() do
        config = CoreFixtures.valid_config(module)
        block = Block.new(type_name, id: "blk_ONE", config: config, slots: filled(module, config))

        scxml = compile!(block, Palette.core()).scxml

        assert scxml =~ ~s(<state id="s_blk_ONE"), type_name
        # The `done` role for a single-outcome type; an outcome final for
        # one that declares more than one way to finish (ADR-0004 outcome
        # amendment, 2b). Either way the state is compound and carries a
        # `<final>`, which is the whole of the convention.
        assert scxml =~ ~s(<final id="s_blk_ONE__done"/>) or
                 scxml =~ ~s(<final id="s_blk_ONE__o_),
               type_name
      end
    end
  end

  describe "core.sequence" do
    # sabotage: make Core.Emit.chain/2 drop the last transition to
    # `exit_target` -> the sequence never reaches its <final> and this goes
    # red (verified)
    test "runs its steps in order and finishes when the last one does" do
      root = sequence([container("blk_A"), container("blk_B")])

      {machine_state, _effects} = run(root)

      assert done?(machine_state, "s_blk_SEQ__done")
    end

    # sabotage: make chain/2 return the first child as `initial` even for an
    # empty run -> `initial` names a state that does not exist and the
    # engine refuses the compile, taking this red (verified)
    test "an empty body enters its <final> directly" do
      root = sequence([])

      assert {:ok, _machine} = Statifier.compile(compile!(root, Palette.core()).scxml)
      assert compile!(root, Palette.core()).scxml =~ ~s(initial="s_blk_SEQ__done")
    end
  end

  describe "core.branch" do
    # sabotage: emit the arms' conditional transitions after the
    # unconditional `otherwise` one -> the unconditional transition always
    # wins and this goes red (verified)
    test "takes the first arm whose condition holds" do
      {machine_state, _effects} =
        run(branch(), datamodel: %{"budget_remaining" => 500, "amount" => 120})

      scxml = compiled_branch()

      assert done?(machine_state, "s_blk_BR__done")
      assert scxml =~ ~s(cond="budget_remaining &gt; amount" target="s_blk_HIT")

      # Order is the whole of the semantics here: an unconditional
      # `otherwise` transition emitted first would be selected before any
      # arm's condition was ever evaluated.
      assert index(scxml, ~s(cond="budget_remaining &gt; amount")) <
               index(scxml, ~s(<transition target="s_blk_MISS"/>))
    end

    # sabotage: make entry/2 return the block's own state id for an empty
    # arm -> the transition targets a state that is not there and this goes
    # red (verified)
    test "an empty otherwise transitions straight to the block's <final>" do
      root =
        Block.new("core.branch",
          id: "blk_BR",
          config: %{"arms" => [%{"slot" => "arm_hit", "cond" => "true"}]},
          slots: %{"arm_hit" => [container("blk_HIT")]}
        )

      assert compile!(root, Palette.core()).scxml =~ ~s(<transition target="s_blk_BR__done"/>)
    end
  end

  describe "core.parallel" do
    # sabotage: emit the lanes as siblings of a <state> rather than regions
    # of a <parallel> -> only one lane runs and the join below never fires,
    # taking this red (verified)
    test "runs its lanes concurrently and is done when every one of them is" do
      root =
        Block.new("core.parallel",
          id: "blk_PAR",
          config: %{"lanes" => ["one", "two"]},
          slots: %{"lane_one" => [container("blk_A")], "lane_two" => [container("blk_B")]}
        )

      {machine_state, _effects} = run(root)

      assert done?(machine_state, "s_blk_PAR__done")
    end

    # sabotage: emit an empty <parallel> for a lane-less config -> the
    # engine refuses a parallel with no regions and this goes red (verified)
    test "a parallel with no lanes emits no <parallel> at all" do
      root = Block.new("core.parallel", id: "blk_PAR", config: %{"lanes" => []})
      scxml = compile!(root, Palette.core()).scxml

      refute scxml =~ "<parallel"
      assert {:ok, _machine} = Statifier.compile(scxml)
    end
  end

  describe "core.group and the interrupt protocol" do
    # sabotage: emit the handlers as siblings of the body instead of regions
    # of the <parallel> -> the handler is never active while the body runs,
    # the event is ignored, and this goes red (verified)
    test "an interrupt handler fires while the body is running" do
      {machine_state, _effects} = run(group("abandon"))
      {:ok, machine_state, _effects} = Statifier.send_event(machine_state, "order.cancelled")

      assert done?(machine_state, "s_blk_GRP__done")
    end

    # sabotage: drop the `statifier_blocks.interrupt.resume` transition from
    # Core.Emit.guarded/4 -> a resuming handler leaves the group stuck and
    # this goes red (verified)
    test "a resuming handler re-enters the group rather than abandoning it" do
      {machine_state, _effects} = run(group("resume"))
      {:ok, machine_state, _effects} = Statifier.send_event(machine_state, "order.cancelled")

      refute done?(machine_state, "s_blk_GRP__done")
      assert done?(machine_state, "s_blk_STEP__waiting")
      # The re-armed handler is what distinguishes a resume from an event
      # nothing acted on: without the resume transition the body would also
      # still be waiting, but the handler would be sitting in its <final>.
      assert done?(machine_state, "s_blk_INT__armed")
    end

    # Nested groups carry the *same* two protocol event names, so which one
    # a raise reaches is decided by SCXML's transition selection rather than
    # by anything this package emits: the raise happens inside the inner
    # group's region, both groups' transitions are enabled, and the inner
    # one preempts the outer because its source is a descendant. That is a
    # claim about the engine, so it is checked by running one rather than
    # asserted in a moduledoc - the outer body must advance to the step
    # *after* the inner group, and the outer handler must stay armed.
    #
    # sabotage: drop the `statifier_blocks.interrupt.abandon` transition from
    # Core.Emit.guarded/4 -> the inner group has nothing to catch its own
    # handler's raise, the outer group catches it instead, and the step
    # after the inner group never runs, taking this red (verified)
    test "an inner group's interrupt abandons only the inner group" do
      inner =
        Block.new("core.group",
          id: "blk_IN",
          slots: %{
            "body" => [waiting("blk_STEP")],
            "interrupts" => [handler("blk_IH", "x.cancel")]
          }
        )

      outer =
        Block.new("core.group",
          id: "blk_OUT",
          slots: %{
            "body" => [inner, waiting("blk_AFTER")],
            "interrupts" => [handler("blk_OH", "y.cancel")]
          }
        )

      {machine_state, _effects} = run(outer)
      {:ok, machine_state, _effects} = Statifier.send_event(machine_state, "x.cancel")

      assert done?(machine_state, "s_blk_AFTER__waiting")
      assert done?(machine_state, "s_blk_OH__armed")
      refute done?(machine_state, "s_blk_OUT__done")
    end

    # sabotage: make Core.Group.emit/2 pass a history mode -> a plain group
    # grows a <history> it has no config for and this goes red (verified)
    test "a plain group emits no <history>; a resumable one emits the mode it was given" do
      refute compile!(group("abandon"), Palette.core()).scxml =~ "<history"

      resumable = %Block{
        group("abandon")
        | type: "core.resumable_group",
          config: %{"history" => "deep"}
      }

      assert compile!(resumable, Palette.core()).scxml =~
               ~s(<history id="s_blk_GRP__history" type="deep">)
    end

    # sabotage: make interruptible/2 always take the guarded path -> a group
    # with no handlers grows a one-region <parallel> and this goes red
    # (verified)
    test "a group with no interrupt handlers is exactly a sequence" do
      bare = %Block{group("abandon") | slots: %{"body" => [container("blk_STEP")]}}

      refute compile!(bare, Palette.core()).scxml =~ "<parallel"
    end
  end

  describe "core.wait" do
    # sabotage: translate the ISO `M` before `T` as minutes -> the delay
    # reads `1m` instead of `1mo` and this goes red (verified)
    test "translates every ISO component into the unit statifier's delay parser reads" do
      for {duration, delay} <- [
            {"PT30S", "30s"},
            {"PT48H", "48h"},
            {"P1D", "1d"},
            {"P1W", "1w"},
            {"P1M", "1mo"},
            {"P1Y", "1y"},
            {"P1Y2M3DT4H5M6S", "1y2mo3d4h5m6s"}
          ] do
        root = Block.new("core.wait", id: "blk_WAI", config: %{"duration" => duration})

        assert compile!(root, Palette.core()).scxml =~ ~s(delay="#{delay}"), duration
      end
    end

    # sabotage: use a constant event name rather than one carrying the block
    # id -> two waits in one chart wake each other and this goes red
    # (verified)
    test "two waits in one chart cannot wake each other" do
      root =
        Block.new("core.sequence",
          id: "blk_SEQ",
          slots: %{
            "body" => [
              Block.new("core.wait", id: "blk_W1", config: %{"duration" => "PT1S"}),
              Block.new("core.wait", id: "blk_W2", config: %{"duration" => "PT1S"})
            ]
          }
        )

      scxml = compile!(root, Palette.core()).scxml

      assert scxml =~ "statifier_blocks.wait.blk_W1"
      assert scxml =~ "statifier_blocks.wait.blk_W2"
    end
  end

  describe "core.on_event" do
    # sabotage: swap the two protocol events in outcome_event/1 -> an
    # abandoning handler raises the resume event and this goes red (verified)
    test "raises the protocol event its outcome names" do
      for {outcome, event} <- [
            {"abandon", Emit.interrupt_events().abandon},
            {"resume", Emit.interrupt_events().resume}
          ] do
        root =
          Block.new("core.on_event",
            id: "blk_OE",
            config: %{"event" => "order.cancelled", "outcome" => outcome}
          )

        assert compile!(root, Palette.core()).scxml =~ ~s(<raise event="#{event}"/>), outcome
      end
    end

    # `emit/2` is checked directly rather than through `Compiler.compile/3`
    # on purpose: the Config stage rejects this config first, so a compile
    # would go red whether or not `emit/2` had a guard of its own, and the
    # guard is the thing under test.
    #
    # sabotage: make outcome_event/1 fall through to {:ok, to_string(other)}
    # -> emit/2 answers {:ok, ...} and raises `?` as an event nothing
    # listens for, taking this red (verified)
    test "refuses a config it cannot compile rather than emitting nonsense" do
      block =
        Block.new("core.on_event", id: "blk_OE", config: %{"event" => "e", "outcome" => "?"})

      assert {:error, [{"outcome", _message}]} =
               OnEvent.emit(block, Context.new("blk_OE", "bdoc_T"))
    end
  end

  # -- helpers ---------------------------------------------------------------

  defp compile!(root, palette) do
    {:ok, compiled} = Compiler.compile(Document.new(root, id: "bdoc_T"), palette)
    compiled
  end

  defp run(root, opts \\ []) do
    {:ok, machine} = Statifier.compile(compile!(root, Palette.core()).scxml)
    Statifier.initialize(machine, opts)
  end

  defp index(haystack, needle) do
    [{start, _length}] = Regex.run(~r/#{Regex.escape(needle)}/, haystack, return: :index)
    start
  end

  defp done?(machine_state, state_id) do
    MapSet.member?(Statifier.active_leaf_states(machine_state), state_id)
  end

  defp sequence(children),
    do: Block.new("core.sequence", id: "blk_SEQ", slots: %{"body" => children})

  # A `core.sequence` with an empty body: the smallest block that is done the
  # moment it is entered, which is what lets these tests exercise sequencing
  # without an invoke or a timer.
  defp container(id), do: Block.new("core.sequence", id: id)

  # The opposite of `container/1`: a block that stays put until something
  # external happens, so an interrupt has a body to interrupt.
  defp waiting(id), do: Block.new("core.wait", id: id, config: %{"duration" => "PT48H"})

  defp handler(id, event),
    do: Block.new("core.on_event", id: id, config: %{"event" => event, "outcome" => "abandon"})

  defp branch do
    Block.new("core.branch",
      id: "blk_BR",
      config: %{"arms" => [%{"slot" => "arm_hit", "cond" => "budget_remaining > amount"}]},
      slots: %{
        "arm_hit" => [container("blk_HIT")],
        "otherwise" => [container("blk_MISS")]
      }
    )
  end

  defp compiled_branch, do: compile!(branch(), Palette.core()).scxml

  # The body is a `core.wait` rather than an always-done container on
  # purpose: a body that finishes on entry completes the group before any
  # interrupt could arrive, so these tests would pass without the handler
  # ever having been live.
  defp group(outcome) do
    Block.new("core.group",
      id: "blk_GRP",
      slots: %{
        "body" => [Block.new("core.wait", id: "blk_STEP", config: %{"duration" => "PT48H"})],
        "interrupts" => [
          Block.new("core.on_event",
            id: "blk_INT",
            config: %{"event" => "order.cancelled", "outcome" => outcome}
          )
        ]
      }
    )
  end

  # Every slot a type declares for `config`, filled with one always-done
  # container, so the "one compound state" property is checked on a block
  # that actually has children rather than only on leaves.
  defp filled(module, config) do
    config
    |> module.slots()
    |> Map.new(fn {name, _arity, _label} -> {name, [child_for(name)]} end)
  end

  defp child_for("interrupts") do
    Block.new("core.on_event",
      id: "blk_interrupts",
      config: %{"event" => "order.cancelled", "outcome" => "abandon"}
    )
  end

  defp child_for(name), do: container("blk_#{name}")
end
