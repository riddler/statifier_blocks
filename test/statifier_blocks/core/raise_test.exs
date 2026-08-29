defmodule StatifierBlocks.Core.RaiseTest do
  use ExUnit.Case, async: true

  alias StatifierBlocks.{Block, Compiler, Document, Palette, Provenance}
  alias StatifierBlocks.Compiler.Context
  alias StatifierBlocks.Core.Raise

  describe "validate_config/1" do
    # sabotage: made `validate_config/1` take the error branch
    # unconditionally -> a good event name was rejected, taking this red
    # (verified)
    test "accepts a well-formed event name" do
      assert Raise.validate_config(%{"event" => "signup.abandoned"}) == :ok
    end

    # sabotage: dropped the call to `Config.event_name?/1` and returned `:ok`
    # unconditionally -> every bad config below went green, taking this red
    # (verified)
    test "rejects everything an event name cannot be" do
      assert {:error, [{"event", _}]} = Raise.validate_config(%{"event" => ""})
      assert {:error, [{"event", _}]} = Raise.validate_config(%{"event" => "two words"})
      assert {:error, [{"event", _}]} = Raise.validate_config(%{"event" => 1})
      assert {:error, [{"event", _}]} = Raise.validate_config(%{})
    end
  end

  describe "leaf-ness" do
    # sabotage: gave `slots/1` a `body` slot -> red, since a raise is a
    # leaf with nothing to sequence (verified)
    test "declares no slots and one step kind" do
      assert Raise.slots(%{"event" => "signup.abandoned"}) == []
      assert Raise.io(%{}) == %{kinds: [:step]}
    end
  end

  # sabotage: renamed the field label to "Event" -> red, because the label
  # is what an editor puts on the control and is part of the declaration
  # (verified)
  test "config_schema/1 declares one required string field" do
    assert Raise.config_schema(%{}) == [
             %{
               key: "event",
               type: :string,
               label: "Raise this event",
               required?: true,
               default: ""
             }
           ]
  end

  describe "compiled SCXML" do
    # sabotage: dropped the `<onentry>` wrapper so the raise sat as a direct
    # child of the state -> the assertion on `<onentry><raise` went red
    # (verified)
    test "emits <raise> inside <onentry>, and a compound state with its own <final>" do
      root = Block.new("core.raise", id: "blk_RAI", config: %{"event" => "signup.abandoned"})

      scxml = compile!(root).scxml

      assert scxml =~ ~s(<state id="s_blk_RAI" initial="s_blk_RAI__o_done">)
      assert scxml =~ ~s(<onentry><raise event="signup.abandoned"/></onentry>)

      assert scxml =~
               ~s(<final id="s_blk_RAI__o_done"><onentry>) <>
                 ~s(<raise event="done.outcome.s_blk_RAI.done"/></onentry></final>)
    end
  end

  describe "end to end" do
    # The body is `[raise_block, waiting]` rather than `[raise_block]` alone
    # on purpose: a body that finishes the instant it raises would reach
    # `blk_GRP__o_done` through the body's own completion regardless of
    # whether the interrupt handler ever saw the event, and the property
    # under test - that the raise is caught in the same macrostep, before
    # the sequence can advance to `waiting` - would go unchecked either way.
    #
    # sabotage: emitted `<send>` instead of `<raise>` for the event -> the
    # send lands on the external queue rather than the internal one, nothing
    # delivers it back into the machine, the interrupt handler never fires,
    # and the body proceeds past the raise straight into `waiting` - which
    # this test catches by asserting `waiting` never becomes active
    # (verified)
    test "an enclosing group's interrupt handler catches the raised event in the same macrostep" do
      raise_block =
        Block.new("core.raise", id: "blk_RAI", config: %{"event" => "signup.abandoned"})

      waiting =
        Block.new("core.wait", id: "blk_WAI", config: %{"duration" => "PT48H"})

      body =
        Block.new("core.sequence", id: "blk_SEQ", slots: %{"body" => [raise_block, waiting]})

      handler =
        Block.new("core.on_event",
          id: "blk_OE",
          config: %{"event" => "signup.abandoned", "outcome" => "abandon"}
        )

      group =
        Block.new("core.group",
          id: "blk_GRP",
          slots: %{"body" => [body], "interrupts" => [handler]}
        )

      {:ok, machine} = Statifier.compile(compile!(group).scxml)
      {machine_state, _effects} = Statifier.initialize(machine)

      active = Statifier.active_leaf_states(machine_state)

      assert MapSet.member?(active, "s_blk_GRP__o_done")
      refute MapSet.member?(active, "s_blk_WAI__waiting")
    end
  end

  describe "emit/2" do
    # sabotage: made `event_name/1` fall through to `{:ok, event}`
    # unconditionally -> emit/2 answered {:ok, ...} for a config
    # validate_config/1 rejects, taking this red (verified)
    test "refuses a config it cannot compile rather than emitting nonsense" do
      block = Block.new("core.raise", id: "blk_RAI", config: %{"event" => ""})

      assert {:error, [{"event", _message}]} = Raise.emit(block, Context.new("blk_RAI", "bdoc_T"))
    end
  end

  describe "provenance" do
    # sabotage: dropped the `Emission.attribute_from_config/3` call on the
    # raise element -> the event value's span carried no config key, taking
    # this red (verified)
    test "the raised event's value is attributed to the block and the event field" do
      root = Block.new("core.raise", id: "blk_RAI", config: %{"event" => "signup.abandoned"})
      compiled = compile!(root)

      {offset, _length} = :binary.match(compiled.scxml, "signup.abandoned")

      assert {:ok, %{block_id: "blk_RAI", config_key: "event"}} =
               Provenance.owner_at(compiled.provenance, offset)
    end
  end

  defp compile!(root) do
    {:ok, compiled} = Compiler.compile(Document.new(root, id: "bdoc_T"), Palette.core())
    compiled
  end
end
