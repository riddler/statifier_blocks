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
