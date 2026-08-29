defmodule StatifierBlocks.Compiler.ContextTest do
  @moduledoc """
  The outcome half of the context (ADR-0004's outcome amendment, 2b/2c):
  the one home for an outcome final's id, the completion event a parent
  wires on, and the `o_` role namespace both of them reserve.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.Compiler.{Context, StateId}

  defp context(block_id \\ "blk_AUTH"), do: Context.new(block_id, "bdoc_T")

  describe "outcome_id/2" do
    # sabotage: minted the outcome final under the bare outcome name rather
    # than the `o_` prefix -> the id comes back "s_blk_AUTH__done" and both
    # asserts below go red (verified)
    test "mints the amendment's id, in the reserved namespace" do
      assert {:ok, "s_blk_AUTH__o_done"} = Context.outcome_id(context(), "done")
      assert {:ok, "s_blk_AUTH__o_error"} = Context.outcome_id(context(), "error")
    end

    # sabotage: dropped the `role?/1` check so any binary was minted anyway
    # -> the error arm never fires and this goes red (verified)
    test "refuses a name that is not in the role shape" do
      assert {:error, {:invalid_outcome, "blk_AUTH", "Done"}} =
               Context.outcome_id(context(), "Done")

      assert {:error, {:invalid_outcome, "blk_AUTH", "a__b"}} =
               Context.outcome_id(context(), "a__b")

      assert {:error, {:invalid_outcome, "blk_AUTH", ""}} = Context.outcome_id(context(), "")
    end

    # sabotage: minted the id by string concatenation without the `__`
    # separator -> `unstate_id/1` reads the whole tail as the block id and
    # this goes red (verified)
    test "stays invertible, so a diff reader can still see the block" do
      {:ok, id} = Context.outcome_id(context(), "error")

      assert StateId.unstate_id(id) == {:ok, {"blk_AUTH", "o_error"}}
    end
  end

  describe "outcome_event/2" do
    # sabotage: built the event from the block id rather than the state id
    # -> the event reads "done.outcome.blk_AUTH.done" and this goes red
    # (verified)
    test "is the completion event a parent wires on" do
      assert {:ok, "done.outcome.s_blk_AUTH.done"} = Context.outcome_event(context(), "done")
    end

    # A parent that does not discriminate wires the prefix, so the full
    # event has to be the prefix plus a token boundary and nothing else.
    # sabotage: joined the outcome with "_" rather than "." -> the prefix
    # no longer matches at a token boundary and this goes red (verified)
    test "extends the per-block prefix at a token boundary" do
      ctx = context()
      {:ok, event} = Context.outcome_event(ctx, "error")

      assert event == "done.outcome." <> ctx.state_id <> "." <> "error"
    end

    # sabotage: returned the event for any binary -> the error arm never
    # fires and this goes red (verified)
    test "refuses a name that is not in the role shape" do
      assert {:error, {:invalid_outcome, "blk_AUTH", "boom!"}} =
               Context.outcome_event(context(), "boom!")
    end
  end

  describe "done_id/1" do
    # sabotage: minted `done_id/1` through `StateId.state_id(block_id,
    # "done")` again, as it did before the amendment -> the id comes back
    # "s_blk_AUTH__done" and this goes red (verified)
    test "is the default outcome's final, in the reserved namespace" do
      assert Context.done_id(context()) == "s_blk_AUTH__o_done"
    end

    # The two have to stay the same function, or a block type calling
    # `done_id/1` and a parent wiring `outcome_id/2` would name different
    # states.
    # sabotage: had `done_id/1` mint the outcome `"complete"` -> the two
    # ids stop agreeing and this goes red (verified)
    test "agrees with outcome_id/2 on the default outcome" do
      assert {:ok, Context.done_id(context())} == Context.outcome_id(context(), "done")
    end
  end

  describe "summary/1 and summary/2 (2e)" do
    # sabotage: dropped the `outcomes` key from `summary/2`'s map -> the
    # match goes red, which is the "always non-empty" half of 2e (verified)
    test "a defaulting child carries exactly one outcome, done" do
      assert %{
               block_id: "blk_STEP",
               state_id: "s_blk_STEP",
               done_event: "done.state.s_blk_STEP",
               outcomes: [
                 %{
                   name: "done",
                   state_id: "s_blk_STEP__o_done",
                   done_event: "done.outcome.s_blk_STEP.done"
                 }
               ]
             } = Context.summary("blk_STEP")
    end

    # sabotage: sorted `summary/2`'s names -> "abandoned" leads and the
    # list match goes red (verified)
    test "a multi-outcome child carries every outcome, in declaration order" do
      summary = Context.summary("blk_MANY", ["done", "error", "abandoned"])

      assert Enum.map(summary.outcomes, & &1.name) == ["done", "error", "abandoned"]

      assert Enum.map(summary.outcomes, & &1.state_id) == [
               "s_blk_MANY__o_done",
               "s_blk_MANY__o_error",
               "s_blk_MANY__o_abandoned"
             ]

      assert Enum.map(summary.outcomes, & &1.done_event) == [
               "done.outcome.s_blk_MANY.done",
               "done.outcome.s_blk_MANY.error",
               "done.outcome.s_blk_MANY.abandoned"
             ]
    end

    # `done_event` is the accepted record's, unchanged: a parent written
    # before outcomes existed still wires the same event.
    # sabotage: had `summary/2` set `done_event` to the default outcome's
    # completion event -> every pre-amendment parent's wiring breaks and
    # this goes red (verified)
    test "the summary's own done_event stays done.state" do
      assert Context.summary("blk_MANY", ["done", "error"]).done_event ==
               "done.state.s_blk_MANY"
    end

    # Total rather than raising, which is what lets `summary/2` be called
    # with names the Emit stage has already refused elsewhere.
    # sabotage: had `outcome_summary/2` raise on its error arm instead of
    # answering `[]` -> this goes red with the raise (verified)
    test "a name outside the role shape is dropped rather than raising" do
      assert Context.summary("blk_MANY", ["done", "Nope"]).outcomes == [
               %{
                 name: "done",
                 state_id: "s_blk_MANY__o_done",
                 done_event: "done.outcome.s_blk_MANY.done"
               }
             ]
    end
  end

  describe "the reserved `o_` namespace" do
    # sabotage: dropped the reserved clause from `role_id/2` -> the role is
    # minted and collides with `outcome_id/2`'s id, taking this red
    # (verified)
    test "role_id/2 refuses a role a block type could collide an outcome with" do
      assert {:error, {:reserved_role, "blk_AUTH", "o_done"}} =
               Context.role_id(context(), "o_done")

      assert {:error, {:reserved_role, "blk_AUTH", "o_"}} = Context.role_id(context(), "o_")
    end

    # The reservation is a prefix, not a substring: a role that merely
    # contains `o_` is ordinary.
    # sabotage: matched `String.contains?(role, "o_")` instead of the
    # prefix -> "not_o_here" is refused and this goes red (verified)
    test "a role that only contains o_ is still minted" do
      assert {:ok, "s_blk_AUTH__not_o_here"} = Context.role_id(context(), "not_o_here")
      assert {:ok, "s_blk_AUTH__running"} = Context.role_id(context(), "running")
    end
  end
end
