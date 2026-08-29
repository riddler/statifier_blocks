defmodule StatifierBlocks.Core.InvokeTest do
  @moduledoc """
  What `core.invoke` means and what it compiles to: ADR-0002's amendment
  section D1 (the `on_error` slot and its ADR-0068 target) and ADR-0004's
  outcome amendment (one `<final>` per outcome reached, the outcome on an
  event, the parent deciding continuation).

  The shape assertions every core type shares live in
  `conformance_test.exs`; nothing here repeats them.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{Block, Compiler, Document, Palette, Provenance}
  alias StatifierBlocks.Core.Invoke

  @authorize %{
    "invoke_type" => "myapp:authorize",
    "assign_to" => "authorization",
    "params" => "amount=order.amount\nreference=order.id"
  }

  describe "validate_config/1 (ADR-0002 decision 7)" do
    # sabotage: accepted any non-empty string as an invoke type -> a bare
    # "authorize" validates and this goes red (verified)
    test "an invoke type is namespace:name" do
      assert Invoke.validate_config(%{"invoke_type" => "myapp:authorize"}) == :ok

      assert {:error, [{"invoke_type", message}]} =
               Invoke.validate_config(%{"invoke_type" => "authorize"})

      assert message =~ "namespace:name"
      assert {:error, [{"invoke_type", _m}]} = Invoke.validate_config(%{})
    end

    # sabotage: dropped the blank arm so an absent assign_to was checked as
    # an identifier -> the optional field becomes required and this goes
    # red (verified)
    test "assign_to is optional, and an identifier when it is there" do
      assert Invoke.validate_config(%{"invoke_type" => "myapp:capture"}) == :ok

      assert Invoke.validate_config(%{"invoke_type" => "myapp:capture", "assign_to" => ""}) == :ok

      assert {:error, [{"assign_to", _message}]} =
               Invoke.validate_config(%{
                 "invoke_type" => "myapp:capture",
                 "assign_to" => "Auth.x"
               })
    end

    # sabotage: stopped splitting the line on "=" and treated the whole
    # line as a name -> a well-formed row is reported as malformed and this
    # goes red (verified)
    test "params is one name=path per line" do
      assert Invoke.validate_config(Map.put(@authorize, "params", "amount=order.amount")) == :ok
      assert Invoke.validate_config(Map.put(@authorize, "params", "")) == :ok

      assert {:error, [{"params", separator}]} =
               Invoke.validate_config(Map.put(@authorize, "params", "amount"))

      assert separator =~ "name=path"

      assert {:error, [{"params", name}]} =
               Invoke.validate_config(Map.put(@authorize, "params", "Amount=order.amount"))

      assert name =~ "is not a name"

      assert {:error, [{"params", path}]} =
               Invoke.validate_config(Map.put(@authorize, "params", "amount=two words"))

      assert path =~ "datamodel path"
    end

    # sabotage: made `param_rows/1` sort the rows -> the order the author
    # wrote is lost and this goes red (verified)
    test "param_rows/1 reads the rows in the order they were written" do
      # The rows are deliberately not in alphabetical order: a reading that
      # sorted them would pass on any input that already was.
      assert Invoke.param_rows("reference=order.id\n\namount=order.amount") ==
               {:ok, [{"reference", "order.id"}, {"amount", "order.amount"}]}

      assert Invoke.param_rows(nil) == {:ok, []}
      assert Invoke.param_rows(42) == {:error, "must be text, one name=path per line"}
    end
  end

  describe "palette_entry/0" do
    # ADR-0005 decision 10's 2026-08-29 amendment (10g) names this slot's
    # style, and names this type by name while doing it.
    # sabotage: declared the rail `:secondary` -> the failure vocabulary the
    # accepted record asks for is gone and this goes red (verified)
    test "declares the on_error rail as a failure slot" do
      assert Invoke.palette_entry().slot_style == %{"on_error" => :failure}
    end
  end

  describe "emit/2 with an occupied on_error slot" do
    setup do
      %{scxml: compile!(invoke(park())).scxml}
    end

    # sabotage: emitted the `<invoke>` without its `type` attribute -> the
    # chart names no invoke type and this goes red (verified)
    test "names the invoke type it was configured with, and never runs one", %{scxml: scxml} do
      assert scxml =~ ~s(<invoke type="myapp:authorize">)
      assert compile!(invoke(park())).invoke_types == ["myapp:authorize"]
    end

    # sabotage: emitted `<param>` with the name and path swapped -> the
    # param carries the path as its name and this goes red (verified)
    test "flattens each params row into a <param>", %{scxml: scxml} do
      assert scxml =~ ~s(<param expr="order.amount" name="amount"/>)
      assert scxml =~ ~s(<param expr="order.id" name="reference"/>)
    end

    # sabotage: dropped the `<assign>` from the success transition -> the
    # result is never written anywhere and this goes red (verified)
    test "writes the result where assign_to names, on the success path", %{scxml: scxml} do
      assert scxml =~
               ~s(<transition event="done.invoke" target="s_blk_INV__o_done">) <>
                 ~s(<assign expr="_event.data" location="authorization"/></transition>)
    end

    # sabotage: emitted the failure transition on ADR-0068's full event
    # with a literal invoke id -> the descriptor no longer matches the id
    # the engine mints and this goes red (verified)
    test "targets the on_error subtree on ADR-0068's event", %{scxml: scxml} do
      assert scxml =~ ~s(<transition event="error.communication.invoke" target="s_blk_PARK"/>)
    end

    # sabotage: wired the child's completion to an event it never raises ->
    # the on_error subtree finishes and nothing carries the run to the error
    # outcome, taking this red (verified)
    test "the on_error subtree's completion reaches the error outcome", %{scxml: scxml} do
      assert scxml =~
               ~s(<transition event="done.state.s_blk_PARK" target="s_blk_INV__o_error" type="internal"/>)
    end

    # sabotage: emitted the two finals without their `<onentry><raise>` ->
    # the outcome stops riding on an event and a parent can no longer tell
    # the two apart, taking this red (verified)
    test "one <final> per outcome, each raising its own completion event", %{scxml: scxml} do
      assert scxml =~
               ~s(<final id="s_blk_INV__o_done"><onentry>) <>
                 ~s(<raise event="done.outcome.s_blk_INV.done"/></onentry></final>)

      assert scxml =~
               ~s(<final id="s_blk_INV__o_error"><onentry>) <>
                 ~s(<raise event="done.outcome.s_blk_INV.error"/></onentry></final>)
    end
  end

  describe "emit/2 with an empty on_error slot" do
    setup do
      %{scxml: compile!(invoke(nil)).scxml}
    end

    # sabotage: emitted the failure transition unconditionally -> it
    # targets a state that was never emitted, the engine refuses the
    # compile, and this goes red (verified)
    test "emits no failure transition and no error final", %{scxml: scxml} do
      refute scxml =~ "error.communication.invoke"
      refute scxml =~ "s_blk_INV__o_error"
      assert {:ok, _machine} = Statifier.compile(scxml)
    end

    # sabotage: dropped the success final's raise for the no-error case ->
    # the block completes with no outcome event and this goes red
    # (verified)
    test "still completes with its done outcome", %{scxml: scxml} do
      assert scxml =~ ~s(<final id="s_blk_INV__o_done">)
      assert scxml =~ ~s(<raise event="done.outcome.s_blk_INV.done"/>)
    end
  end

  describe "the compiled chart, run" do
    # sabotage: pointed the success transition back at the running state ->
    # the run never reaches a final and this goes red (verified)
    test "a done.invoke lands the run in the done outcome" do
      {:ok, machine_state, _effects} = send_to(invoke(park()), "done.invoke.inv_1")

      assert active?(machine_state, "s_blk_INV__o_done")
    end

    # sabotage: wired the child's completion to an event it never raises ->
    # the run parks in the subtree forever and this goes red (verified)
    test "ADR-0068's error enters the on_error subtree, which reaches the error outcome" do
      {:ok, machine_state, _effects} =
        send_to(invoke(park()), "error.communication.invoke.inv_1")

      # The parked subtree is an always-done container, so the run passes
      # straight through it into the error outcome's final - which is the
      # whole of 2d: the block's emission ends there and the parent decides
      # what comes next.
      assert active?(machine_state, "s_blk_INV__o_error")
    end

    # ADR-0004 2d, end to end: the block's emission ends at its error final
    # and the enclosing sequence is what carries the run on - which is the
    # answer the spike's `run_cp_invoke_error` fixture was waiting for.
    # sabotage: wired the child's completion to an event it never raises ->
    # the run stays parked and never reaches the next step, taking this red
    # (verified)
    test "the enclosing parent carries on once the failure path finishes" do
      inv =
        Block.new("core.invoke",
          id: "blk_INV",
          config: %{"invoke_type" => "myapp:authorize"},
          slots: %{"on_error" => [waiting("blk_PARK")]}
        )

      root =
        Block.new("core.sequence",
          id: "blk_SEQ",
          slots: %{"body" => [inv, waiting("blk_NEXT")]}
        )

      {:ok, parked, _effects} = send_to(root, "error.communication.invoke.inv_1")
      assert active?(parked, "s_blk_PARK__waiting")

      {:ok, carried_on, _effects} =
        Statifier.send_event(parked, "statifier_blocks.wait.blk_PARK")

      assert active?(carried_on, "s_blk_NEXT__waiting")
    end
  end

  describe "provenance (ADR-0004 decision 5)" do
    # sabotage: minted the done final with `Context.role_id/2` in the `o_`
    # namespace -> the reservation refuses it, the compile fails with an Emit
    # finding, and this goes red (verified)
    test "every state this block emits is owned, and the outcome finals carry their role" do
      compiled = compile!(invoke(park()))

      for state_id <- [
            "s_blk_INV",
            "s_blk_INV__running",
            "s_blk_INV__o_done",
            "s_blk_INV__o_error"
          ] do
        assert {:ok, owner} = Provenance.owner_of_state(compiled.provenance, state_id)
        assert owner.block_id == "blk_INV", state_id
      end

      assert {:ok, owner} = Provenance.owner_of_state(compiled.provenance, "s_blk_INV__o_error")
      assert owner.role == "o_error"
    end
  end

  defp invoke(on_error) do
    slots = if on_error, do: %{"on_error" => [on_error]}, else: %{}

    Block.new("core.invoke", id: "blk_INV", config: @authorize, slots: slots)
  end

  # An always-done container standing in for the parking subtree: it
  # finishes the moment it is entered, so a test can watch the completion
  # travel from the slot child to the error outcome without a second event.
  defp park, do: Block.new("core.sequence", id: "blk_PARK")

  # The opposite: a step that stays put until its timer fires, so a test can
  # watch a run park in the failure path before anything moves it on.
  defp waiting(id), do: Block.new("core.wait", id: id, config: %{"duration" => "PT48H"})

  defp compile!(root) do
    {:ok, compiled} = Compiler.compile(Document.new(root, id: "bdoc_T"), Palette.core())
    compiled
  end

  defp send_to(root, event) do
    {:ok, machine} = Statifier.compile(compile!(root).scxml)
    {machine_state, _effects} = Statifier.initialize(machine)

    Statifier.send_event(machine_state, event)
  end

  defp active?(machine_state, state_id) do
    MapSet.member?(Statifier.active_leaf_states(machine_state), state_id)
  end
end
