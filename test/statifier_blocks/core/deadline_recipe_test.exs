defmodule StatifierBlocks.Core.DeadlineRecipeTest do
  use ExUnit.Case, async: true

  alias StatifierBlocks.{Block, BlockType, Compiler, Core, Document, Edit, Palette, Recipe}
  alias StatifierBlocks.Core.DeadlineRecipe

  doctest StatifierBlocks.Recipe
  doctest StatifierBlocks.Palette, only: [core_recipes: 0, fetch_recipe: 2]

  #   blk_ROOT (core.sequence)
  #     body: [blk_GROUP, blk_SEQ]
  #
  #   blk_GROUP (core.group)
  #     body: [blk_STEP]
  #
  #   blk_SEQ (core.sequence) - a block with no interrupts rail, for the
  #   refusal case
  defp document do
    step = Block.new("core.wait", id: "blk_STEP", config: %{"duration" => "1s"})
    group = Block.new("core.group", id: "blk_GROUP", slots: %{"body" => [step]})
    seq = Block.new("core.sequence", id: "blk_SEQ")

    Document.new(
      Block.new("core.sequence", id: "blk_ROOT", slots: %{"body" => [group, seq]}),
      id: "bdoc_DEADLINE"
    )
  end

  defp applied(commands), do: Edit.apply(document(), {:compound, commands})

  describe "insert/2" do
    # ADR-0010 decision 1: the send at the HEAD of the group's body, the
    # handler on that same group's interrupts rail, both named by the target's
    # parent - never by the block the author armed beside.
    #
    # Sabotage: the send's target reading `{group.id, @interrupts, 0}` - both
    # halves land on the rail and the body assertion goes red.
    test "puts the send at the head of the body and the handler on the rail" do
      assert {:ok, [send_command, handler_command]} =
               DeadlineRecipe.insert({"blk_GROUP", "body", 1}, document())

      assert {:insert, {"blk_GROUP", "body", 0}, %Block{type: "core.send"}} = send_command

      assert {:insert, {"blk_GROUP", "interrupts", 0}, %Block{type: "core.on_event"}} =
               handler_command
    end

    # The coupling ADR-0010 decision 5 records as the family rule, written
    # twice by the recipe rather than twice by the author.
    #
    # Sabotage: deriving the handler's event from its OWN id rather than the
    # send's - the two names differ and this goes red.
    test "both halves name the same generated event" do
      assert {:ok, [{:insert, _t1, timer}, {:insert, _t2, handler}]} =
               DeadlineRecipe.insert({"blk_GROUP", "body", 0}, document())

      assert timer.config["event"] == handler.config["event"]
      assert timer.config["event"] =~ ~r/\Adeadline\.[0-9a-z]{8}\z/
      assert timer.config["delay"] == DeadlineRecipe.default_delay()
      assert handler.config["outcome"] == "abandon"
    end

    # Clause 3C's refusal: nowhere to put the handler, so nothing is written
    # at all. A refused gesture is not a finding.
    #
    # Sabotage: `enclosing_group/2` matching any block rather than the two
    # group types - the sequence answers `{:ok, ...}` and this goes red.
    test "refuses a position whose enclosing block has no interrupts rail" do
      assert {:error, {:no_interrupts_slot, "blk_SEQ"}} =
               DeadlineRecipe.insert({"blk_SEQ", "body", 0}, document())

      assert {:error, {:no_interrupts_slot, "blk_NOWHERE"}} =
               DeadlineRecipe.insert({"blk_NOWHERE", "body", 0}, document())
    end

    # Clause 3C's bound, checked by the caller's own check against the
    # recipe's own output.
    #
    # Sabotage: the handler's target reading `{"blk_ROOT", @interrupts, 0}` -
    # the command reaches a level above the enclosing group and this goes red.
    test "the commands it returns stay inside the caller's reach check" do
      target = {"blk_GROUP", "body", 0}
      assert {:ok, commands} = DeadlineRecipe.insert(target, document())
      assert Recipe.within_reach?(target, commands)
    end

    # A second deadline goes on the END of the rail rather than over the
    # first, and the two name different events.
    #
    # Sabotage: `rail_length/1` returning 0 unconditionally - the second
    # handler lands at index 0, the order assertion goes red.
    test "a second deadline appends to the rail" do
      assert {:ok, first} = DeadlineRecipe.insert({"blk_GROUP", "body", 0}, document())
      assert {:ok, once, _inverse} = applied(first)

      assert {:ok, [_timer, {:insert, {"blk_GROUP", "interrupts", 1}, _handler}]} =
               DeadlineRecipe.insert({"blk_GROUP", "body", 0}, once)
    end
  end

  describe "the pair it produces" do
    # The generated name is what both cards draw as their summary chip, and
    # `StatifierBlocks.BlockType`'s presentation cap REFUSES a chip longer
    # than it rather than truncating one. A name over the cap therefore ships
    # a pair whose cards say nothing about the event they are coupled by, with
    # a lint finding on each.
    #
    # Sabotage: `event_name/1` returning the whole block id - the name is 39
    # characters and this goes red on both halves.
    test "the generated event fits the summary chip's presentation cap" do
      assert {:ok, [{:insert, _t1, timer}, {:insert, _t2, handler}]} =
               DeadlineRecipe.insert({"blk_GROUP", "body", 0}, document())

      assert [] == BlockType.summary_refusals(Core.Send, timer.config)
      assert [] == BlockType.summary_refusals(Core.OnEvent, handler.config)
    end

    # The whole point of the arrangement: it compiles, with no findings, the
    # moment the pick lands. An author who has typed nothing yet has a
    # document that builds.
    #
    # Sabotage: the send's config leaving `"event" => ""` - the Config stage
    # reports the event finding and this goes red.
    test "compiles clean with nothing else typed" do
      assert {:ok, commands} = DeadlineRecipe.insert({"blk_GROUP", "body", 0}, document())
      assert {:ok, with_deadline, _inverse} = applied(commands)

      assert {:ok, %{warnings: []}} = Compiler.compile(with_deadline, Palette.core())
    end
  end
end
