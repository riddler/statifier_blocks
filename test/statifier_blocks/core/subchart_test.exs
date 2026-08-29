defmodule StatifierBlocks.Core.SubchartTest do
  @moduledoc """
  What `core.subchart` means and what it compiles to: ADR-0004's
  2026-08-29 amendment, C2 (the block's state routes `done.invoke` on
  `_event.data.outcome`, unconditioned transition last) and C3 (a static
  `<invoke id>`), with `error.communication.invoke` routing to `on_error`
  unchanged from `core.invoke`.

  C1 - the child half of the same amendment - is
  `StatifierBlocks.Compiler.ChildUseTest`'s.

  The shape assertions every core type shares live in
  `conformance_test.exs`; nothing here repeats them.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{Block, Compiler, Document, Palette, Provenance}
  alias StatifierBlocks.Core.Subchart

  @eligibility %{
    "chart" => "bdoc_CHILD",
    "outcomes" => "done\nabandoned",
    "assign_to" => "eligibility",
    "params" => "email=signup.email"
  }

  describe "validate_config/1 (ADR-0002 decision 7)" do
    # sabotage: accepted any value as a chart reference -> an absent
    # `chart` validates and this goes red (verified)
    test "a chart reference is required and names one document" do
      assert Subchart.validate_config(%{"chart" => "bdoc_CHILD"}) == :ok

      assert {:error, [{"chart", message}]} = Subchart.validate_config(%{})
      assert message =~ "names the document to run"

      assert {:error, [{"chart", _m}]} =
               Subchart.validate_config(%{"chart" => "bdoc_CHILD bdoc_OTHER"})
    end

    # sabotage: dropped the identifier check from `outcome_rows/1` -> a
    # capitalised outcome name validates, no role can be minted from it,
    # and this goes red (verified)
    test "outcomes is one lowercase name per line, and never the same one twice" do
      assert Subchart.validate_config(%{"chart" => "bdoc_CHILD", "outcomes" => "done\nabandoned"}) ==
               :ok

      assert Subchart.validate_config(%{"chart" => "bdoc_CHILD", "outcomes" => ""}) == :ok

      assert {:error, [{"outcomes", shape}]} =
               Subchart.validate_config(%{"chart" => "bdoc_CHILD", "outcomes" => "Done"})

      assert shape =~ "one outcome name"

      assert {:error, [{"outcomes", twice}]} =
               Subchart.validate_config(%{"chart" => "bdoc_CHILD", "outcomes" => "done\ndone"})

      assert twice =~ "twice"
    end

    # sabotage: made `outcome_rows/1` sort the names -> the order the
    # author wrote is lost and this goes red (verified)
    test "outcome_rows/1 reads the names in the order they were written" do
      assert Subchart.outcome_rows("abandoned\n\ndone") == {:ok, ["abandoned", "done"]}
      assert Subchart.outcome_rows(nil) == {:ok, []}
      assert Subchart.outcome_rows(42) == {:error, "must be text, one outcome name per line"}
    end
  end

  describe "outcomes/1 and slots/1" do
    # sabotage: appended `error` unconditionally -> a child that finishes
    # `error` gets two finals and two slots for one outcome, and this goes
    # red on the second assertion (verified)
    test "the declared outcomes, then error unless the author declared it" do
      assert Subchart.outcomes(@eligibility) == [
               {"done", "Done"},
               {"abandoned", "Abandoned"},
               {"error", "Failed"}
             ]

      assert Subchart.outcomes(%{"chart" => "bdoc_CHILD", "outcomes" => "done\nerror"}) == [
               {"done", "Done"},
               {"error", "Failed"}
             ]
    end

    # sabotage: defaulted `child_outcomes/1` to `[]` -> a subchart that
    # declares nothing has no routed outcome at all and this goes red
    # (verified)
    test "a subchart that declares nothing has core.invoke's two outcomes" do
      assert Subchart.outcomes(%{"chart" => "bdoc_CHILD"}) == [
               {"done", "Done"},
               {"error", "Failed"}
             ]

      assert Subchart.child_outcomes(%{"chart" => "bdoc_CHILD"}) == ["done"]
    end

    # sabotage: named the slots after the outcome rather than `on_<name>`
    # -> `on_error` is no longer the slot `core.invoke` declares and this
    # goes red (verified)
    test "one zero_or_one slot per outcome, on_error last and unchanged" do
      assert Subchart.slots(@eligibility) == [
               {"on_done", :zero_or_one, "If it finishes done"},
               {"on_abandoned", :zero_or_one, "If it finishes abandoned"},
               {"on_error", :zero_or_one, "If it fails"}
             ]

      assert Subchart.palette_entry().slot_style == %{"on_error" => :failure}
    end

    # sabotage: read `outcomes` with `String.split/2` and no identifier
    # check -> a config `validate_config/1` rejects reaches `slots/1` as a
    # slot name no role inverts, and this goes red (verified)
    test "every callback answers for a config validate_config/1 rejects" do
      junk = %{"chart" => "", "outcomes" => "Done\ndone\ndone"}

      assert {:error, _findings} = Subchart.validate_config(junk)

      assert Subchart.slots(junk) ==
               [{"on_done", :zero_or_one, "If it finishes done"}] ++
                 [
                   {"on_error", :zero_or_one, "If it fails"}
                 ]

      assert Subchart.outcomes(junk) == [{"done", "Done"}, {"error", "Failed"}]
    end
  end

  describe "emit/2 (C2, C3)" do
    setup do
      %{scxml: compile!(subchart(nudge: true, park: true)).scxml}
    end

    # sabotage: dropped the `id` attribute from the `<invoke>` -> the
    # engine mints one, `_event.invokeid` is no longer known at compile
    # time, and this goes red (verified)
    test "writes a static invoke id and the host-registered invoke type", %{scxml: scxml} do
      assert scxml =~
               ~s(<invoke id="blk_ELIG" src="bdoc_CHILD" type="statifier_blocks:subchart">)

      assert Subchart.invoke_type() == "statifier_blocks:subchart"
      assert compile!(subchart(nudge: true, park: true)).invoke_types == [Subchart.invoke_type()]
    end

    # sabotage: emitted the condition with `==` -> the loose operator the
    # campaign ruling rejected is back in the bytes and this goes red
    # (verified)
    test "routes done.invoke on _event.data.outcome, with the strict operator", %{scxml: scxml} do
      assert scxml =~
               ~s(<transition cond="_event.data.outcome === 'done'" ) <>
                 ~s(event="done.invoke" target="s_blk_ELIG__o_done">)

      assert scxml =~
               ~s(<transition cond="_event.data.outcome === 'abandoned'" ) <>
                 ~s(event="done.invoke" target="s_blk_NUDGE">)

      refute scxml =~ ~r/_event\.data\.outcome == '/
    end

    # sabotage: emitted the unconditioned transition first -> it shadows
    # every conditioned one after it, and this goes red on the ordering
    # assertion (verified)
    test "the unconditioned done.invoke transition comes last", %{scxml: scxml} do
      default = ~s(<transition event="done.invoke" target="s_blk_ELIG__o_done">)

      assert scxml =~ default

      assert :binary.match(scxml, default) |> elem(0) >
               :binary.match(scxml, "_event.data.outcome === 'abandoned'") |> elem(0)
    end

    # sabotage: pointed the failure transition at the error final rather
    # than at the slot's child -> the on_error subtree never runs and this
    # goes red (verified)
    test "error.communication.invoke reaches the on_error subtree, unchanged", %{scxml: scxml} do
      assert scxml =~ ~s(<transition event="error.communication.invoke" target="s_blk_PARK"/>)

      assert scxml =~
               ~s(<transition event="done.state.s_blk_PARK" target="s_blk_ELIG__o_error" type="internal"/>)
    end

    # sabotage: dropped the failure outcome from `finals/1` -> the error
    # final the on_error subtree targets is never emitted and this goes
    # red (verified)
    test "one <final> per outcome, each raising its own completion event", %{scxml: scxml} do
      for outcome <- ["done", "abandoned", "error"] do
        assert scxml =~
                 ~s(<final id="s_blk_ELIG__o_#{outcome}"><onentry>) <>
                   ~s(<raise event="done.outcome.s_blk_ELIG.#{outcome}"/></onentry></final>)
      end
    end

    # sabotage: wrote the `<assign>` only on the first conditioned
    # transition -> the result is written on one path and not the others,
    # and this goes red (verified)
    test "writes the child's result where assign_to names, on every done path", %{scxml: scxml} do
      assert scxml
             |> String.split(~s(<assign expr="_event.data" location="eligibility"/>))
             |> length() ==
               4
    end

    # sabotage: emitted `<param>` with the name and path swapped -> the
    # param carries the path as its name and this goes red (verified)
    test "flattens each params row into a <param>", %{scxml: scxml} do
      assert scxml =~ ~s(<param expr="signup.email" name="email"/>)
    end
  end

  describe "emit/2 with an empty on_error slot" do
    setup do
      %{scxml: compile!(subchart(nudge: false, park: false)).scxml}
    end

    # sabotage: emitted the failure transition unconditionally -> it
    # targets a state that was never emitted, the engine refuses the
    # compile, and this goes red (verified)
    test "emits no failure transition and no error final", %{scxml: scxml} do
      refute scxml =~ "error.communication.invoke"
      refute scxml =~ "s_blk_ELIG__o_error"
      assert {:ok, _machine} = Statifier.compile(scxml)
    end

    # sabotage: pointed an empty slot's route at a state nothing emitted
    # -> the engine refuses the compile and this goes red (verified)
    test "an outcome with an empty slot routes straight to its final", %{scxml: scxml} do
      assert scxml =~
               ~s(<transition cond="_event.data.outcome === 'abandoned'" ) <>
                 ~s(event="done.invoke" target="s_blk_ELIG__o_abandoned">) <>
                 ~s(<assign expr="_event.data" location="eligibility"/></transition>)
    end
  end

  describe "the compiled chart, run" do
    setup do
      {:ok, machine} = Statifier.compile(compile!(subchart(nudge: true, park: true)).scxml)
      {machine_state, _effects} = Statifier.initialize(machine)

      %{machine_state: machine_state}
    end

    # sabotage: made `condition/1` name the first declared outcome for
    # every route -> every conditioned arm tests for `done`, the abandoned
    # subtree is unreachable, and this goes red (verified)
    test "each declared outcome selects its own slot or final", ctx do
      assert routed(ctx.machine_state, %{"outcome" => "done"}) ==
               MapSet.new(["s_blk_ELIG__o_done"])

      # The abandoned slot is occupied, so the run enters the subtree
      # first; the always-done nudge passes straight through it into the
      # abandoned final, which is ADR-0004 2d end to end.
      assert routed(ctx.machine_state, %{"outcome" => "abandoned"}) ==
               MapSet.new(["s_blk_ELIG__o_abandoned"])
    end

    # sabotage: dropped the unconditioned transition -> a child reporting
    # an outcome the parent does not route leaves the run parked in the
    # inner state forever, and this goes red (verified)
    test "an outcome the parent does not route falls through to the default path", ctx do
      assert routed(ctx.machine_state, %{"outcome" => "surprise"}) ==
               MapSet.new(["s_blk_ELIG__o_done"])
    end

    # The `st-iz97` pin is why the conditions are written `===`: a loose
    # `==` against an absent `_event.data.outcome` is non-boolean. This
    # asserts the clean half - the default arm routes and nothing else
    # happens - rather than the counterfactual.
    # sabotage: dropped the unconditioned transition -> a completion
    # carrying no donedata matches nothing, the run stays in the inner
    # state, and this goes red (verified). Swapping `===` for `==` does
    # NOT redden it against the statifier this package resolves today.
    test "a done.invoke with no donedata routes to the default and raises nothing", ctx do
      event = Statifier.Event.external("done.invoke.blk_ELIG", invokeid: "blk_ELIG")

      assert {:ok, machine_state, effects} = Statifier.send_event(ctx.machine_state, event)
      assert Statifier.active_leaf_states(machine_state) == MapSet.new(["s_blk_ELIG__o_done"])
      assert effects == []
    end

    # sabotage: wired the on_error child's completion to an event it never
    # raises -> the run parks in the failure subtree and never reaches the
    # error outcome, taking this red (verified)
    test "ADR-0068's error enters on_error, which reaches the error outcome", ctx do
      event =
        Statifier.Event.external("error.communication.invoke.blk_ELIG", invokeid: "blk_ELIG")

      assert {:ok, machine_state, _effects} = Statifier.send_event(ctx.machine_state, event)
      assert Statifier.active_leaf_states(machine_state) == MapSet.new(["s_blk_ELIG__o_error"])
    end
  end

  describe "provenance (ADR-0004 decision 5)" do
    # sabotage: minted an outcome final with `Context.role_id/2` instead
    # of `outcome_id/2` -> the reserved `o_` namespace refuses it, the
    # compile fails with an Emit finding, and this goes red (verified)
    test "every state this block emits is owned, and the outcome finals carry their role" do
      compiled = compile!(subchart(nudge: true, park: true))

      for state_id <- [
            "s_blk_ELIG",
            "s_blk_ELIG__running",
            "s_blk_ELIG__o_done",
            "s_blk_ELIG__o_abandoned",
            "s_blk_ELIG__o_error"
          ] do
        assert {:ok, owner} = Provenance.owner_of_state(compiled.provenance, state_id)
        assert owner.block_id == "blk_ELIG", state_id
      end

      assert {:ok, owner} =
               Provenance.owner_of_state(compiled.provenance, "s_blk_ELIG__o_abandoned")

      assert owner.role == "o_abandoned"
    end
  end

  # The signup wizard's eligibility step, run as another chart: the
  # ADR's own illustration, compiled. Asserting the block's whole subtree
  # byte for byte is what makes decision 6's determinism visible - a
  # reordering that no single assertion above would catch moves these
  # bytes.
  describe "the signup wizard's eligibility step, compiled" do
    # sabotage: emitted the slot children before the inner running state
    # -> every assertion above still passes and this one goes red on the
    # first differing byte, which is the whole reason it is here
    # (verified)
    test "compiles to the bytes ADR-0004's illustration describes" do
      compiled = compile!(wizard())

      assert compiled.scxml =~
               ~s(<state id="s_blk_ELIG" initial="s_blk_ELIG__running">) <>
                 ~s(<state id="s_blk_ELIG__running">) <>
                 ~s(<invoke id="blk_ELIG" src="bdoc_CHILD" type="statifier_blocks:subchart">) <>
                 ~s(<param expr="signup.email" name="email"/></invoke>) <>
                 ~s(<transition cond="_event.data.outcome === 'done'" event="done.invoke" ) <>
                 ~s(target="s_blk_ELIG__o_done">) <>
                 ~s(<assign expr="_event.data" location="eligibility"/></transition>) <>
                 ~s(<transition cond="_event.data.outcome === 'abandoned'" event="done.invoke" ) <>
                 ~s(target="s_blk_NUDGE">) <>
                 ~s(<assign expr="_event.data" location="eligibility"/></transition>) <>
                 ~s(<transition event="done.invoke" target="s_blk_ELIG__o_done">) <>
                 ~s(<assign expr="_event.data" location="eligibility"/></transition>) <>
                 ~s(<transition event="error.communication.invoke" target="s_blk_PARK"/>) <>
                 ~s(</state>)
    end

    # sabotage: dropped the enclosing sequence's transition on the
    # subchart's `done.state` -> the wizard never carries on past the
    # eligibility step and this goes red (verified)
    test "the enclosing sequence carries on whichever way the child finished" do
      compiled = compile!(wizard())

      assert compiled.scxml =~
               ~s(<transition event="done.state.s_blk_ELIG" target="s_blk_CNV" type="internal"/>)
    end
  end

  defp subchart(opts) do
    slots =
      %{}
      |> put_slot("on_abandoned", Keyword.get(opts, :nudge, false) && nudge())
      |> put_slot("on_error", Keyword.get(opts, :park, false) && park())

    Block.new("core.subchart", id: "blk_ELIG", config: @eligibility, slots: slots)
  end

  defp wizard do
    Block.new("core.sequence",
      id: "blk_WROOT",
      slots: %{
        "body" => [
          subchart(nudge: true, park: true),
          Block.new("core.wait", id: "blk_CNV", config: %{"duration" => "PT48H"})
        ]
      }
    )
  end

  defp put_slot(slots, _name, false), do: slots
  defp put_slot(slots, name, block), do: Map.put(slots, name, [block])

  # Always-done containers standing in for the two continuation subtrees:
  # each finishes the moment it is entered, so a test can watch the
  # completion travel from the slot child to its outcome without a second
  # event.
  defp nudge, do: Block.new("core.sequence", id: "blk_NUDGE")
  defp park, do: Block.new("core.sequence", id: "blk_PARK")

  defp compile!(root) do
    {:ok, compiled} = Compiler.compile(Document.new(root, id: "bdoc_WIZ"), Palette.core())
    compiled
  end

  defp routed(machine_state, data) do
    event = Statifier.Event.external("done.invoke.blk_ELIG", data: data, invokeid: "blk_ELIG")
    {:ok, machine_state, _effects} = Statifier.send_event(machine_state, event)

    Statifier.active_leaf_states(machine_state)
  end
end
