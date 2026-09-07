defmodule StatifierBlocks.Core.DeadlineRecipeMembersTest do
  use ExUnit.Case, async: true

  @moduledoc """
  `DeadlineRecipe.members/2` - ADR-0005's amendment of 2026-09-07, clause 2D.

  The recipe recognises its arrangement by its SHAPE in the document it is
  shown, not by anything written down beside it, and every test here is a
  consequence of that sentence rather than of the code that implements it.

  Pure: nothing in this file names LiveView, so it carries no `ensure_loaded`
  wrapper and runs in the headless job, which is where the claim "this is
  recognition, not rendering" is actually proved.
  """

  alias StatifierBlocks.{Block, Document}
  alias StatifierBlocks.Core.DeadlineRecipe

  # The record's worked example (`docs/adr/0005-liveview-editor.md`, the
  # amendment's "Worked example: a settlement deadline in the card-processing
  # document"): a `core.group` named "Settle" whose body holds the deadline's
  # send and a `myapp:capture` invoke, and whose interrupts rail holds the
  # handler naming the same event.
  #
  #   blk_root (core.sequence)
  #     body: [blk_settle]
  #
  #   blk_settle (core.group)
  #     body:       [blk_send, blk_capture]
  #     interrupts: [blk_handler]
  defp settlement(opts \\ []) do
    send_event = Keyword.get(opts, :send_event, "deadline.a1b2c3d4")
    handler_event = Keyword.get(opts, :handler_event, "deadline.a1b2c3d4")
    delay = Keyword.get(opts, :delay, "1h")

    timer =
      Block.new("core.send",
        id: "blk_send",
        config: %{"event" => send_event, "delay" => delay}
      )

    capture =
      Block.new("core.invoke",
        id: "blk_capture",
        config: %{"invoke_type" => "myapp:capture"}
      )

    handler = Block.new("core.on_event", id: "blk_handler", config: %{"event" => handler_event})

    group =
      Block.new("core.group",
        id: "blk_settle",
        slots: %{"body" => [timer, capture], "interrupts" => [handler]}
      )

    Document.new(
      Block.new("core.sequence", id: "blk_root", slots: %{"body" => [group]}),
      id: "bdoc_settlement"
    )
  end

  describe "the worked example, from either half" do
    # The amendment's table, first row: asked about a half of an arrangement
    # it recognises, the recipe answers BOTH ids including the asked-about
    # one. Asked from the rail it answers the same list, because one
    # arrangement is one answer however the author reached it.
    #
    # Sabotage: dropping the asked-about id from either clause's return -
    # the editor would then remove a block the author never pointed at and
    # leave the one they did, and both assertions go red.
    test "the send and the handler each answer both ids" do
      document = settlement()

      assert DeadlineRecipe.members("blk_send", document) == ["blk_send", "blk_handler"]
      assert DeadlineRecipe.members("blk_handler", document) == ["blk_send", "blk_handler"]
    end

    # The example's last paragraph: "Had the author instead deleted the
    # `myapp:capture` invoke, no recipe would claim it."
    #
    # Sabotage: `pair/3`'s catch-all clause answering the group's whole body
    # instead of `[]` - this goes red and the delete of any ordinary block
    # starts offering a compound.
    test "the invoke beside the timer is claimed by nobody" do
      assert DeadlineRecipe.members("blk_capture", settlement()) == []
    end

    # `members/2` is pure on `insert/2`'s terms: a question about a document,
    # answered without touching one.
    test "the document is not written" do
      document = settlement()

      assert DeadlineRecipe.members("blk_send", document) == ["blk_send", "blk_handler"]
      assert document == settlement()
    end
  end

  describe "recognition is structural" do
    # "A hand-built pair is claimed." The event here is nothing
    # `event_name/1` would ever generate - no `deadline.` prefix, no
    # eight-character tail - and the pair is claimed anyway, because the
    # recipe cannot tell a hand-built arrangement from a picked one and the
    # amendment says it should not.
    #
    # Sabotage: matching the event against `~r/\Adeadline\./` before
    # claiming - this goes red while the worked example above still passes,
    # which is exactly the drift the test exists to catch.
    test "a pair an author built by hand, under their own event name, is claimed" do
      document = settlement(send_event: "settlement.window", handler_event: "settlement.window")

      assert DeadlineRecipe.members("blk_send", document) == ["blk_send", "blk_handler"]
    end

    # "A renamed event still matches" only because recognition tests that the
    # two halves AGREE. Renamed apart, they are no longer a pair - the
    # amendment's third table row, the conservative reading of a partial
    # arrangement.
    #
    # Sabotage: `partner/4` finding the first block of the right TYPE in the
    # slot without comparing events - both of these go red.
    test "halves whose events disagree are not a pair" do
      document = settlement(handler_event: "settlement.window")

      assert DeadlineRecipe.members("blk_send", document) == []
      assert DeadlineRecipe.members("blk_handler", document) == []
    end

    # A send with no delay is not the arrangement `insert/2` writes: 2D's
    # shape is a send "carrying an `event` and a `delay`".
    test "a send with no delay is not half of a deadline" do
      document = settlement(delay: "")

      assert DeadlineRecipe.members("blk_send", document) == []
      assert DeadlineRecipe.members("blk_handler", document) == []
    end
  end

  describe "the enclosing group bounds the answer" do
    # Clause 3C's bound, arriving by construction: the rail is read off the
    # group the asked-about block sits in and off no other block. Two groups,
    # one half in each, agreeing event names - and no claim, because they are
    # not in the same group.
    #
    # Sabotage: searching `Document.blocks/1` for the partner instead of the
    # enclosing group's own slots - the halves match on event name and this
    # goes red.
    test "two halves in different groups are not a pair" do
      timer =
        Block.new("core.send",
          id: "blk_send",
          config: %{"event" => "deadline.a1b2c3d4", "delay" => "1h"}
        )

      handler =
        Block.new("core.on_event", id: "blk_handler", config: %{"event" => "deadline.a1b2c3d4"})

      here = Block.new("core.group", id: "blk_here", slots: %{"body" => [timer]})
      there = Block.new("core.group", id: "blk_there", slots: %{"interrupts" => [handler]})

      document =
        Document.new(
          Block.new("core.sequence", id: "blk_root", slots: %{"body" => [here, there]}),
          id: "bdoc_split"
        )

      assert DeadlineRecipe.members("blk_send", document) == []
      assert DeadlineRecipe.members("blk_handler", document) == []
    end

    # The rail is a rail: a `core.on_event` sitting in a group's BODY is not
    # the handler half, and a `core.send` on the rail is not the timer half.
    test "the halves are only halves in the slots the recipe writes them to" do
      timer =
        Block.new("core.send",
          id: "blk_send",
          config: %{"event" => "deadline.a1b2c3d4", "delay" => "1h"}
        )

      handler =
        Block.new("core.on_event", id: "blk_handler", config: %{"event" => "deadline.a1b2c3d4"})

      group = Block.new("core.group", id: "blk_group", slots: %{"body" => [timer, handler]})

      document =
        Document.new(
          Block.new("core.sequence", id: "blk_root", slots: %{"body" => [group]}),
          id: "bdoc_body_only"
        )

      assert DeadlineRecipe.members("blk_send", document) == []
      assert DeadlineRecipe.members("blk_handler", document) == []
    end

    # A block with no enclosing block at all, and a block the document does
    # not hold: neither is half of anything, and neither raises.
    test "the root and an absent id answer []" do
      document = settlement()

      assert DeadlineRecipe.members("blk_root", document) == []
      assert DeadlineRecipe.members("blk_nowhere", document) == []
    end
  end
end
