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
  alias StatifierBlocks.Compiler.Context
  alias StatifierBlocks.Core.{Await, OnEvent, Wait}

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

  describe "the optional capture map" do
    # The map is `core.on_event`'s, key, rules and message, so the refusal
    # is asserted against that type's own answer for the same pairs rather
    # than restated as a literal: two spellings of one rule would be free
    # to drift.
    #
    # Sabotage: dropped `Capture.check/2` from `validate_config/1` - red
    # here and on the ordering test below (verified).
    test "refuses a malformed map exactly as core.on_event does" do
      for capture <- [
            %{"loan.copy_id" => ""},
            %{"loan copy" => "copy_id"},
            %{"loan.copy_id" => ["konst", "x"]},
            %{"loan.copy_id" => ["const", "a\u0001b"]},
            "copy_id"
          ] do
        assert {:error, [{"capture", message}]} =
                 Await.validate_config(%{"event" => "loan.requested", "capture" => capture})

        assert {:error, [{"capture", ^message}]} =
                 OnEvent.validate_config(%{
                   "event" => "loan.requested",
                   "outcome" => "abandon",
                   "capture" => capture
                 })
      end
    end

    # Sabotage: made `Capture.check/2`'s `nil` arm a finding - red on the
    # absent case, and on every test here that compiles an await
    # (verified).
    test "admits an absent map, an empty one, a path pair and a literal pair" do
      for capture <- [nil, %{}, %{"loan.copy_id" => "copy_id"}, %{"loan.source" => ["const", 1]}] do
        config =
          if capture == nil,
            do: %{"event" => "loan.requested"},
            else: %{"event" => "loan.requested", "capture" => capture}

        assert Await.validate_config(config) == :ok
      end
    end

    # The finding is the map's own and lands after the declared fields'.
    #
    # Sabotage: checked the capture ahead of the event in
    # `validate_config/1` - red, because the capture finding came first
    # (verified).
    test "reports capture after the two declared fields" do
      assert {:error, [{"event", _event}, {"timeout", _timeout}, {"capture", _capture}]} =
               Await.validate_config(%{"event" => "", "timeout" => "soon", "capture" => "x"})
    end

    # The capture declares no field: `config_schema/1` is the two fields
    # the first test of this file pins, whatever the config holds, because
    # decision 7's field-type set has no member that describes a map.
    #
    # Sabotage: declared a `capture` field whenever the config holds one -
    # red here (verified).
    test "adds no field to config_schema/1" do
      assert Await.config_schema(%{"capture" => %{"loan.copy_id" => "copy_id"}}) ==
               Await.config_schema(%{})
    end
  end

  describe "emit/2 with a capture" do
    # The emission is `core.on_event`'s: the same pairs compile to the same
    # assigns, guards and order, compared as bytes against that type's
    # compile of the same map.
    #
    # Sabotage: reversed the assigns before `emit/2` handed them to the
    # awaited transition - red on both maps (verified). Dropping the sort
    # in `Capture.assigns/1` moves both types at once, so this test cannot
    # see it; `core.on_event`'s forty-pair ordering test is the one that
    # goes red on that mutation (verified).
    test "compiles a capture to the assigns core.on_event emits for it" do
      for capture <- [
            %{"loan.copy_id" => "copy_id", "loan.source" => ["const", "desk"]},
            for(n <- 0..39, into: %{}, do: {"d.k#{String.pad_leading("#{n}", 2, "0")}", "s#{n}"})
          ] do
        awaited = assigns(compile!(await_capturing(capture, "14d")).scxml)
        handled = assigns(compile!(group_around_handler(capture)).scxml)

        assert awaited != ""
        assert awaited == handled
      end
    end

    # The assigns ride the transition the awaited event selects, ahead of
    # nothing and inside it, because `_event.data` is in scope there and
    # nowhere else. The timer's transition carries none: its event is the
    # await's own and has no payload of the host's.
    #
    # Sabotage: put the assigns on the timer's transition as well - red
    # (verified).
    test "puts the assigns on the awaited transition and not on the timer's" do
      scxml = compile!(await_capturing(%{"loan.copy_id" => "copy_id"}, "14d")).scxml

      assert scxml =~
               ~s(<transition event="loan.requested" target="s_blk_AWT__o_received">) <>
                 ~s(<if cond="_event.data.copy_id !== undefined">) <>
                 ~s(<assign expr="_event.data.copy_id" location="loan.copy_id"/></if>) <>
                 ~s(</transition>)

      assert scxml =~
               ~s(<transition event="statifier_blocks.await.blk_AWT" ) <>
                 ~s(target="s_blk_AWT__o_timed_out"/>)
    end

    # An absent map and an empty one are the await with no capture, byte
    # for byte.
    #
    # Sabotage: made `Capture.assigns/1`'s `nil` clause emit an `<if>` -
    # red on the `refute`, and the golden tests below went red with it
    # (verified).
    test "compiles an absent or empty capture to the bytes of an await with none" do
      without = compile!(await_capturing(nil, "14d")).scxml

      assert compile!(await_capturing(%{}, "14d")).scxml == without
      refute without =~ "<assign"
      refute without =~ "<if"
    end

    # `emit/2` is asked directly, for `core.on_event`'s reason: the Config
    # stage refuses this config first, so a compile would go red whether or
    # not `emit/2` answered for it.
    #
    # Sabotage: had `Capture.assigns/1`'s malformed arm answer `{:ok, []}` -
    # red, because the pair was dropped silently (verified).
    test "refuses a malformed capture rather than dropping the pair" do
      assert {:error, [{"capture", _message}]} =
               Await.emit(
                 await_capturing(%{"loan.copy_id" => ""}, ""),
                 Context.new("blk_AWT", "bdoc_T")
               )
    end
  end

  describe "documents with no capture compile as they did before the map" do
    # The goldens were compiled from these fixture documents at the commit
    # this capture's change was branched from, before any of its code was
    # written; a document that carries no capture on any `core.await`
    # compiles to exactly those bytes. A golden is replaced only by a change
    # that says in its own commit why its document's bytes moved.
    #
    # Sabotage: emitted an `<if>` on the awaited transition for an await
    # with no capture - red on all four (verified).
    for {name, path} <- [
          {"patron_registration", "test/fixtures/documents/patron_registration.json"},
          {"composed", "test/fixtures/documents/flow_patterns/composed.json"},
          {"bounded_step", "test/fixtures/documents/flow_patterns/bounded_step.json"},
          {"deadline", "test/fixtures/await_capture/deadline.json"}
        ] do
      test "#{name} compiles byte-identically to its golden" do
        assert compiled(unquote(path)) ==
                 File.read!("test/fixtures/await_capture/#{unquote(name)}.scxml")
      end
    end
  end

  describe "the capture corpus case" do
    # One await with a deadline, a path pair, a nested path pair and a
    # literal pair, pinned as bytes. The golden is this change's own
    # output; what makes it a claim rather than a restatement is the test
    # beside it, which says its assigns are `core.on_event`'s.
    #
    # Sabotage: dropped the assigns from the awaited transition's children
    # in `emit/2` - red here, on the emission tests above and on the runs
    # below (verified).
    test "compiles byte-identically to its golden" do
      assert compiled("test/fixtures/await_capture/capture.json") ==
               File.read!("test/fixtures/await_capture/capture.scxml")
    end

    # Sabotage: reversed the assigns before `emit/2` handed them to the
    # awaited transition - red (verified).
    test "carries the assigns core.on_event emits for the same map" do
      {:ok, document} = Document.from_json(File.read!("test/fixtures/await_capture/capture.json"))
      [%Block{config: %{"capture" => capture}}] = document.root.slots["body"]

      assert assigns(compiled("test/fixtures/await_capture/capture.json")) ==
               assigns(compile!(group_around_handler(capture)).scxml)
    end
  end

  describe "the compiled chart, run with a capture" do
    # The run a creating event's data needs: the awaited event carries the
    # id the next step reads, and the await writes it on the way out.
    #
    # Sabotage: dropped the assigns from the awaited transition - red, and
    # `loan` came back empty (verified).
    test "the awaited event writes its payload into the datamodel" do
      machine_state =
        run_capturing(%{"loan.copy_id" => "copy_id", "loan.source" => ["const", "desk"]},
          event: "loan.requested",
          data: %{"copy_id" => "copy-42"}
        )

      assert machine_state.datamodel["loan"] == %{"copy_id" => "copy-42", "source" => "desk"}

      assert MapSet.member?(
               Statifier.active_leaf_states(machine_state),
               "s_blk_AWT__o_received"
             )
    end

    # `core.on_event`'s absent-source rule, unchanged on this type: a path
    # the payload does not carry writes nothing, and a literal still writes.
    #
    # Sabotage: emitted every path pair's assign unguarded - red, because
    # `copy_id` came back as the engine's unbound marker (verified).
    test "a source the payload omits leaves its destination unwritten" do
      machine_state =
        run_capturing(%{"loan.copy_id" => "copy_id", "loan.source" => ["const", "desk"]},
          event: "loan.requested",
          data: %{}
        )

      assert machine_state.datamodel["loan"] == %{"source" => "desk"}
    end

    # The deadline's way out writes nothing: its event is not the awaited
    # one.
    #
    # Sabotage: put the assigns on the timer transition too - red, because
    # the literal pair was written on the timeout (verified).
    test "the timer's event writes nothing" do
      machine_state =
        run_capturing(%{"loan.source" => ["const", "desk"]},
          event: "statifier_blocks.await.blk_AWT",
          data: %{}
        )

      assert machine_state.datamodel["loan"] == %{}

      assert MapSet.member?(
               Statifier.active_leaf_states(machine_state),
               "s_blk_AWT__o_timed_out"
             )
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

  defp await_capturing(capture, timeout) do
    config = %{"event" => "loan.requested", "timeout" => timeout}
    config = if capture == nil, do: config, else: Map.put(config, "capture", capture)

    Block.new("core.await", id: "blk_AWT", config: config)
  end

  defp group_around_handler(capture) do
    Block.new("core.group",
      id: "blk_GRP",
      slots: %{
        "body" => [Block.new("core.wait", id: "blk_STEP", config: %{"duration" => "48h"})],
        "interrupts" => [
          Block.new("core.on_event",
            id: "blk_INT",
            config: %{"event" => "loan.requested", "outcome" => "abandon", "capture" => capture}
          )
        ]
      }
    )
  end

  # Every `<if>`-wrapped or bare `<assign>` in a compiled chart, in order,
  # as one string: the part of the emission a capture owns.
  defp assigns(scxml) do
    ~r/<if cond="[^"]*"><assign [^>]*\/><\/if>|<assign [^>]*\/>/
    |> Regex.scan(scxml)
    |> Enum.map_join(&hd/1)
  end

  defp compiled(path) do
    {:ok, document} = Document.from_json(File.read!(path))
    {:ok, compiled} = Compiler.compile(document, Palette.core())
    compiled.scxml
  end

  defp run_capturing(capture, opts) do
    {:ok, machine} = Statifier.compile(compile!(await_capturing(capture, "14d")).scxml)
    {machine_state, _effects} = Statifier.initialize(machine, datamodel: %{"loan" => %{}})

    {:ok, machine_state, _effects} =
      Statifier.send_event(
        machine_state,
        Statifier.Event.external(Keyword.fetch!(opts, :event), data: Keyword.fetch!(opts, :data))
      )

    machine_state
  end

  defp compile!(root) do
    {:ok, compiled} = Compiler.compile(Document.new(root, id: "bdoc_T"), Palette.core())
    compiled
  end
end
