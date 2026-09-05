defmodule StatifierBlocks.Compiler.StateIdTest do
  use ExUnit.Case, async: true

  alias StatifierBlocks.Compiler.StateId

  doctest StatifierBlocks.Compiler.StateId

  @hostile_roles [
    "",
    "Done",
    "0done",
    "done-state",
    "a__b",
    "__",
    "done ",
    :done,
    nil,
    123
  ]

  describe "state_id/1" do
    # sabotage: change the @prefix from "s_" to "" -> this assertion goes
    # red (verified)
    test "prefixes the block id with s_" do
      assert StateId.state_id("blk_ABC") == "s_blk_ABC"
    end

    # sabotage: make state_id/1 return a constant -> two distinct block ids
    # collide and this goes red (verified)
    test "is injective over distinct block ids" do
      ids = for n <- 1..200, do: StateId.state_id("blk_#{n}")

      assert length(Enum.uniq(ids)) == 200
    end
  end

  describe "state_id/2" do
    # sabotage: change the @separator from "__" to "_" -> the expected id
    # no longer matches and this goes red (verified)
    test "joins block id and role with the double underscore" do
      assert StateId.state_id("blk_ABC", "done") == {:ok, "s_blk_ABC__done"}
    end

    # sabotage: drop the `not String.contains?(role, "__")` clause from
    # role?/1 -> "a__b" is minted and this goes red (verified)
    test "refuses every role it could not invert" do
      for role <- @hostile_roles do
        assert {:error, {:invalid_role, "blk_ABC", ^role}} = StateId.state_id("blk_ABC", role)
      end
    end

    # sabotage: make state_id/2 ignore its role argument -> two roles on one
    # block produce the same id and this goes red (verified)
    test "is injective over distinct roles on one block" do
      {:ok, a} = StateId.state_id("blk_ABC", "done")
      {:ok, b} = StateId.state_id("blk_ABC", "run")

      refute a == b
    end

    # sabotage: drop the "s_" prefix from state_id/2 -> a generated id can
    # collide with an author's own `<data id>` and this goes red (verified)
    test "keeps generated ids out of the namespace an author's config writes into" do
      {:ok, id} = StateId.state_id("blk_ABC", "done")

      assert String.starts_with?(id, "s_")
    end
  end

  describe "unstate_id/1" do
    # sabotage: make unstate_id/1 split on every "__" rather than the first
    # (`parts: 2` removed) -> a role carrying no separator is unaffected,
    # but the round-trip property below goes red for the role case (verified)
    test "inverts state_id/1 and state_id/2 for every well-formed id" do
      for n <- 1..50 do
        block_id = "blk_#{n}"
        {:ok, with_role} = StateId.state_id(block_id, "lane_#{n}")

        assert StateId.unstate_id(StateId.state_id(block_id)) == {:ok, {block_id, nil}}
        assert StateId.unstate_id(with_role) == {:ok, {block_id, "lane_#{n}"}}
      end
    end

    # sabotage: make unstate_id/1 accept any binary -> this goes red (verified)
    test "refuses a string that is not a generated state id" do
      assert StateId.unstate_id("blk_ABC") == :error
      assert StateId.unstate_id("") == :error
      assert StateId.unstate_id("s_") == :error
    end
  end

  describe "unoutcome_id/1" do
    # The inversion `Core.Emit.final/1` rests on: it must round-trip every
    # outcome name, and it must not read an ordinary role as an outcome
    # just because the role contains `o_`.
    # sabotage: derived the outcome by splitting the role on `"o_"` rather
    # than matching it as a prefix -> "not_o_here" reads as the outcome
    # "here" and the refusal loop goes red (verified)
    test "round-trips every outcome name and refuses every ordinary role" do
      for outcome <- ["done", "error", "abandoned", "o_looking"] do
        {:ok, id} = StateId.state_id("blk_ABC", "o_" <> outcome)

        assert StateId.unoutcome_id(id) == {:ok, {"s_blk_ABC", outcome}}
      end

      for role <- ["done", "not_o_here", "body_done", "o"] do
        {:ok, id} = StateId.state_id("blk_ABC", role)

        assert StateId.unoutcome_id(id) == :error
      end

      assert StateId.unoutcome_id("s_blk_ABC") == :error
      assert StateId.unoutcome_id("blk_ABC__o_done") == :error
    end
  end

  describe "done_event/1" do
    # sabotage: change the prefix to "done." -> this goes red (verified)
    test "names the SCXML done.state event of a state id" do
      assert StateId.done_event("s_blk_ABC") == "done.state.s_blk_ABC"
    end
  end

  describe "undone_event/1" do
    # sabotage: invert only the `done.outcome` form and answer :error for
    # `done.state` -> the second row of ADR-0005 decision 10w's table never
    # draws, and every block that declares no outcomes keeps the raw name
    test "round-trips both forms of a generated completion event" do
      assert StateId.undone_event(StateId.done_event(StateId.state_id("blk_SEQ"))) ==
               {:ok, {"blk_SEQ", nil}}

      for outcome <- ["done", "error", "abandoned"] do
        event = StateId.outcome_event(StateId.state_id("blk_AUTH"), outcome)

        assert StateId.undone_event(event) == {:ok, {"blk_AUTH", outcome}}
      end
    end

    # sabotage: drop the `nil` role requirement in `block_of/2` -> a role
    # state's completion is reported as the BLOCK's, so a card claims a
    # block finished when only one lane inside it did
    test "an auxiliary state's completion is not the block's" do
      {:ok, lane} = StateId.state_id("blk_PAR", "lane_capture")

      assert StateId.undone_event(StateId.done_event(lane)) == :error
      assert StateId.undone_event(StateId.outcome_event(lane, "error")) == :error
    end

    # ADR-0005 decision 10y, hazard one. `StatifierBlocks.Validation` admits
    # any non-empty UTF-8 block id, so an id carrying the role separator is
    # a document this package must read - and its generated event name has
    # two readings, block `a__b` and block `a` under role `b`.
    #
    # sabotage: answer `{:ok, {"a", "b"}}` here (which is what `unstate_id/1`
    # alone says) -> the chip draws a DIFFERENT block's label, which is the
    # one outcome 10y refuses
    test "an authored block id carrying the role separator does not invert" do
      assert StateId.undone_event("done.state.s_a__b") == :error
      assert StateId.undone_event("done.outcome.s_a__b.error") == :error

      assert StateId.undone_event(StateId.outcome_event(StateId.state_id("a__b"), "error")) ==
               :error
    end

    # ADR-0005 decision 10y, hazard two. A dot is not a character the
    # derivation reserves at all, so an authored id containing one gives
    # `done.outcome.s_A.B.C` two readings - outcome `B.C` and outcome `C`.
    #
    # sabotage: split on the LAST dot instead of refusing -> the chip names
    # outcome `C` on a block called `A.B`, which nothing declared
    test "an authored block id carrying a dot does not invert an outcome event" do
      assert StateId.undone_event("done.outcome.s_A.B.C") == :error

      assert StateId.undone_event(StateId.outcome_event(StateId.state_id("a.b"), "error")) ==
               :error
    end

    # sabotage: drop the `role?/1` check on the outcome -> a segment no
    # `outcome_id/2` could ever have minted reads as an outcome name
    test "refuses everything that is not a generated completion event" do
      for name <- [
            "order.paid",
            "done.state.blk_SEQ",
            "done.state.s_",
            "done.outcome.s_blk_AUTH",
            "done.outcome.s_blk_AUTH.",
            "done.outcome.s_blk_AUTH.Error",
            "done.outcome.s_blk_AUTH.a__b",
            "done.outcomes.s_blk_AUTH.error",
            "",
            :done,
            nil
          ] do
        assert StateId.undone_event(name) == :error, "expected #{inspect(name)} to be refused"
      end
    end
  end
end
