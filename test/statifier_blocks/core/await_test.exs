defmodule StatifierBlocks.Core.AwaitTest do
  @moduledoc """
  `core.await`, the in-flow leaf that holds until a named event arrives
  (ADR-0002 decision 10, the 2026-09-05 amendment): what it declares, what
  it compiles to with and without a deadline, that its timer is a
  cancellable armed send like every other, and that both of its outcomes
  are reachable in a running chart.

  The shape assertions every core type shares are generated in
  `conformance_test.exs` and the vocabulary registration is pinned in
  `core_types_test.exs`; neither is repeated here.
  """

  use ExUnit.Case, async: true

  alias Statifier.Effect.Cancel
  alias StatifierBlocks.{Block, Compiler, Document, Palette}
  alias StatifierBlocks.Core.{Await, Wait}

  doctest StatifierBlocks.Core.Await, only: [summary: 1]

  describe "what it declares" do
    # Sabotage: gave `slots/1` a `"body"` slot - red, because an await is a
    # leaf and a slot would make it a container the compiler splices into.
    test "is a leaf with two config fields" do
      assert Await.slots(%{}) == []

      assert Await.config_schema(%{}) == [
               %{
                 key: "event",
                 type: :string,
                 label: "Wait for this event",
                 required?: true,
                 default: ""
               },
               %{
                 key: "timeout",
                 type: :duration,
                 label: "Give up after",
                 required?: false,
                 default: ""
               }
             ]
    end

    # "Valid wherever `core.wait` is" is exactly this identity, so it is
    # asserted against the other type rather than restated as a literal.
    #
    # Sabotage: declared `produces: :unknown` on the await - red, because
    # the two declarations stopped being the same map.
    test "declares core.wait's io/1 byte for byte" do
      assert Await.io(%{}) == Wait.io(%{})
      assert Await.io(%{"timeout" => "48h"}) == %{kinds: [:step]}
    end

    # The G14d decision: the list does not follow `timeout`. An outcome
    # whose final is never emitted costs a parent nothing (ADR-0004's
    # outcome amendment, 2c), and a list that shrank when the field was
    # cleared would take a declared seam away from an author who had
    # already wired it.
    #
    # Sabotage: made `outcomes/1` return only `received` for a blank
    # timeout - red on the three blank-timeout asserts and on the
    # no-deadline declaration test below, which is the decision.
    test "declares both outcomes for every config" do
      both = [{"received", "Received"}, {"timed_out", "Timed out"}]

      assert Await.outcomes(%{}) == both
      assert Await.outcomes(%{"event" => "order.approved"}) == both
      assert Await.outcomes(%{"event" => "order.approved", "timeout" => ""}) == both
      assert Await.outcomes(%{"event" => "order.approved", "timeout" => "48h"}) == both
    end

    # Sabotage: bumped `current_version/0` to 2 - red, because a version
    # this type has no `migrate_config/2` arm for makes every stored block
    # unresolvable.
    test "is at version 1, with no stored documents to migrate" do
      assert Await.current_version() == 1
      refute function_exported?(Await, :migrate_config, 2)
    end
  end

  describe "validate_config/1" do
    # Sabotage: dropped the `check_event/2` clause - red, because a blank
    # event is the one thing this type cannot compile.
    test "requires an event name" do
      assert Await.validate_config(%{"event" => "order.approved"}) == :ok

      assert {:error, [{"event", message}]} = Await.validate_config(%{})
      assert message =~ "event name"

      assert {:error, [{"event", _message}]} = Await.validate_config(%{"event" => "not an event"})
      assert {:error, [{"event", _message}]} = Await.validate_config(%{"event" => 5})
    end

    # An absent key and the field's own default are both "no deadline",
    # exactly as an absent `core.send` `delay` is.
    #
    # Sabotage: made `check_timeout/2` treat `""` as a finding - red on
    # both blank arms, and every block the config form had written would
    # have carried a finding it could not clear.
    test "accepts a blank or absent timeout, and refuses one it cannot parse" do
      assert Await.validate_config(%{"event" => "order.approved"}) == :ok
      assert Await.validate_config(%{"event" => "order.approved", "timeout" => ""}) == :ok
      assert Await.validate_config(%{"event" => "order.approved", "timeout" => "48h"}) == :ok
      assert Await.validate_config(%{"event" => "order.approved", "timeout" => "1h30m"}) == :ok

      assert {:error, [{"timeout", message}]} =
               Await.validate_config(%{"event" => "order.approved", "timeout" => "soon"})

      assert message =~ "duration"

      assert {:error, [{"timeout", _message}]} =
               Await.validate_config(%{"event" => "order.approved", "timeout" => nil})
    end

    # Findings come back in the order the fields are declared in, which is
    # the order the editor renders them.
    #
    # Sabotage: ran `check_timeout/2` ahead of `check_event/2` in
    # `validate_config/1` - red, because the timeout finding came first.
    test "reports both fields in declaration order" do
      assert {:error, [{"event", _event}, {"timeout", _timeout}]} =
               Await.validate_config(%{"event" => "", "timeout" => "soon"})
    end
  end

  describe "emit/2 with a deadline" do
    setup do
      %{scxml: compile!(await("48h")).scxml}
    end

    # Sabotage: targeted the awaited transition at the `timed_out` final -
    # red, because the two ways out stopped being distinguishable.
    test "the awaited event reaches the received outcome", ctx do
      assert ctx.scxml =~
               ~s(<transition event="order.approved" target="s_blk_AWT__o_received"/>)

      assert ctx.scxml =~
               ~s(<final id="s_blk_AWT__o_received">) <>
                 ~s(<onentry><raise event="done.outcome.s_blk_AWT.received"/></onentry></final>)
    end

    # The delay is compiled rather than read out, so the attribute is the
    # normalised duration and not the author's bytes - `core.wait`'s rule.
    #
    # Sabotage: emitted the stored string as the `delay` rather than
    # rendering the parsed duration - red on the `3h2h` case below, which
    # is the whole reason the parse/render pair is called.
    test "the deadline arms a delayed send whose event reaches timed_out", ctx do
      assert ctx.scxml =~
               ~s(<onentry><send delay="48h" event="statifier_blocks.await.blk_AWT" ) <>
                 ~s(id="s_blk_AWT__send"/></onentry>)

      assert ctx.scxml =~
               ~s(<transition event="statifier_blocks.await.blk_AWT" ) <>
                 ~s(target="s_blk_AWT__o_timed_out"/>)

      assert ctx.scxml =~
               ~s(<final id="s_blk_AWT__o_timed_out">) <>
                 ~s(<onentry><raise event="done.outcome.s_blk_AWT.timed_out"/></onentry></final>)

      assert compile!(await("3h2h")).scxml =~ ~s(<send delay="5h")
    end

    # The whole waiting child, in order, because the order is what the
    # moduledoc's sketch shows a reader: the timer is armed on entry, the
    # awaited event is the first transition, and the deadline is the
    # second. A sketch the emission does not match is worse than none.
    #
    # Sabotage: emitted the deadline's transition ahead of the awaited one
    # - red, and the moduledoc started lying about its own bytes.
    test "emits the waiting child the moduledoc sketches", ctx do
      assert ctx.scxml =~
               ~s(<state id="s_blk_AWT__waiting">) <>
                 ~s(<onentry><send delay="48h" event="statifier_blocks.await.blk_AWT" ) <>
                 ~s(id="s_blk_AWT__send"/></onentry>) <>
                 ~s(<transition event="order.approved" target="s_blk_AWT__o_received"/>) <>
                 ~s(<transition event="statifier_blocks.await.blk_AWT" ) <>
                 ~s(target="s_blk_AWT__o_timed_out"/></state>)
    end

    # Sabotage: passed `nil` as the compound state's `initial` - red,
    # because the pin is what says which child the block enters, and an
    # await that names none is one SCXML's own default has to answer for.
    test "the waiting child is what the block enters", ctx do
      assert ctx.scxml =~ ~s(<state id="s_blk_AWT" initial="s_blk_AWT__waiting">)
    end
  end

  describe "emit/2 with no deadline" do
    # Every one of the three deadline elements is absent together: an
    # await with no timeout is the awaited transition and one final.
    #
    # Sabotage: emitted the `timed_out` final unconditionally - red on the
    # `refute`, and the chart carried a state nothing could enter.
    test "arms nothing and emits no timed_out final" do
      for config <- [
            %{"event" => "order.approved"},
            %{"event" => "order.approved", "timeout" => ""}
          ] do
        scxml = compile!(Block.new("core.await", id: "blk_AWT", config: config)).scxml

        assert scxml =~ ~s(<transition event="order.approved" target="s_blk_AWT__o_received"/>)
        assert scxml =~ ~s(<final id="s_blk_AWT__o_received">)
        refute scxml =~ "<send"
        refute scxml =~ "<onentry><send"
        refute scxml =~ "timed_out"
      end
    end

    # The declared outcome outlives its final, which is what makes the
    # G14d answer safe: a parent wiring the event gets a transition that
    # never fires rather than an unresolved target.
    #
    # Sabotage: derived `outcomes/1` from `timeout` - red here, because
    # the declaration and the emission stopped disagreeing on purpose.
    test "still declares timed_out, whose final was never emitted" do
      config = %{"event" => "order.approved"}

      assert {"timed_out", _label} = List.last(Await.outcomes(config))
      refute compile!(Block.new("core.await", id: "blk_AWT", config: config)).scxml =~ "timed_out"
    end
  end

  describe "the deadline's timer is a cancellable armed send" do
    # The send id rides `Cancels.armed_role/0`, so the enclosing scope
    # reaches it exactly as it reaches a `core.send`'s and a `core.wait`'s.
    #
    # Sabotage: minted the send id under a role of its own ("timer") - red
    # on both asserts, and a durable host would have been left holding a
    # timer for an await nobody was in any more.
    test "the enclosing scope cancels it on exit" do
      scxml = compile!(sequence_around(await("48h"))).scxml

      assert scxml =~ ~s(id="s_blk_AWT__send")
      assert scxml =~ ~s(<onexit><cancel sendid="s_blk_AWT__send"/></onexit>)
    end

    # Sabotage: had `deadline/4`'s blank arm arm a send anyway - red here
    # and on both no-deadline emit tests, which is the arm earning its keep.
    test "an await with no deadline gives its scope nothing to cancel" do
      scxml = compile!(sequence_around(await(""))).scxml

      refute scxml =~ "<cancel"
      refute scxml =~ "<onexit>"
    end
  end

  describe "the compiled chart, run" do
    # Both outcomes reachable, through the resolved statifier rather than
    # through the emitted bytes: the awaited event lands in `received`,
    # and the timer's own event lands in `timed_out`.
    setup do
      {:ok, machine} = Statifier.compile(compile!(await("48h")).scxml)
      {machine_state, _effects} = Statifier.initialize(machine)

      %{machine_state: machine_state}
    end

    # Sabotage: targeted the awaited transition at the `timed_out` final -
    # red here. Targeting the timer transition at the `received` final is
    # the mirror mutation, and it takes the test below red instead, which
    # is what makes these two tests a pair rather than one assertion.
    test "the awaited event reaches the received outcome", ctx do
      {:ok, machine_state, _effects} =
        Statifier.send_event(ctx.machine_state, "order.approved")

      assert MapSet.member?(
               Statifier.active_leaf_states(machine_state),
               "s_blk_AWT__o_received"
             )
    end

    test "the timer's event reaches the timed_out outcome", ctx do
      {:ok, machine_state, _effects} =
        Statifier.send_event(ctx.machine_state, "statifier_blocks.await.blk_AWT")

      assert MapSet.member?(
               Statifier.active_leaf_states(machine_state),
               "s_blk_AWT__o_timed_out"
             )
    end
  end

  describe "a worked example: an approval that may be abandoned" do
    # The await sits in a group's body behind an interrupt rail, which is
    # the arrangement a deadline on an await actually ships inside: the
    # awaited event never arrives, the group is abandoned, and the timer
    # the await armed must not survive the run that armed it.
    setup do
      compiled = compile!(group_around(sequence_around(await("48h"))))
      {:ok, machine} = Statifier.compile(compiled.scxml)
      {machine_state, effects} = Statifier.initialize(machine)

      %{machine_state: machine_state, initial_effects: effects}
    end

    # Sabotage: made the block's own `initial` the `received` final rather
    # than the waiting child - the await went final on entry, the run was
    # past it before the first assertion, and this went red.
    test "the run parks in the await with its timer armed", ctx do
      assert cancels(ctx.initial_effects) == []

      assert MapSet.member?(
               Statifier.active_leaf_states(ctx.machine_state),
               "s_blk_AWT__waiting"
             )
    end

    # Sabotage: minted the await's send id under a role of its own - red,
    # because no cancel effect came back and the abandoned approval left a
    # 48h timer behind in a durable host.
    test "abandoning the group cancels the timer the await armed", ctx do
      {:ok, _machine_state, effects} =
        Statifier.send_event(ctx.machine_state, "signup.abandoned")

      assert [%Cancel{send_id: "s_blk_AWT__send"}] = cancels(effects)
    end
  end

  defp cancels(effects), do: for({:cancel, cancel} <- effects, do: cancel)

  defp await(timeout) do
    Block.new("core.await",
      id: "blk_AWT",
      config: %{"event" => "order.approved", "timeout" => timeout}
    )
  end

  defp sequence_around(block) do
    Block.new("core.sequence", id: "blk_SEQ", slots: %{"body" => [block]})
  end

  defp group_around(body) do
    Block.new("core.group",
      id: "blk_GRP",
      slots: %{
        "body" => [body],
        "interrupts" => [
          Block.new("core.on_event",
            id: "blk_INT",
            config: %{"event" => "signup.abandoned", "outcome" => "abandon"}
          )
        ]
      }
    )
  end

  defp compile!(root) do
    {:ok, compiled} = Compiler.compile(Document.new(root, id: "bdoc_T"), Palette.core())
    compiled
  end
end
