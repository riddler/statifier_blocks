defmodule StatifierBlocks.Core.ParallelCompleteTest do
  @moduledoc """
  `core.parallel`'s completion rule: the `complete` config key, the two
  emissions it picks between, and the lane-scoped cancel that both of them
  share.

  ADR-0004's 2026-08-29 amendment, "`core.parallel` `complete: first` -
  per-lane transitions, losing lanes exit and cancel": P1 is the emission,
  P2 is Appendix D's exit of the losing lanes (the engine's, proven here
  through the resolved dependency rather than implemented), and P3 is the
  delayed send's `<cancel>` landing in the lane's own region.
  """

  use ExUnit.Case, async: true

  alias Statifier.Effect.{Cancel, CancelInvoke}
  alias Statifier.Invoke.Types, as: InvokeTypes
  alias StatifierBlocks.{Block, BlockType, Compiler, Document, Palette}
  alias StatifierBlocks.Compiler.Context
  alias StatifierBlocks.Core.Parallel

  @lanes ["authorize", "fraud_check"]

  describe "the `complete` declaration" do
    # Sabotage: dropped the `complete` map from `config_schema/1` -> the
    # editor had no control to author the rule with and this went red on
    # the missing key (verified).
    test "config_schema declares it as a select over the two rules, defaulting to all" do
      assert %{
               key: "complete",
               type: {:select, options},
               label: "Continue",
               required?: false,
               default: "all"
             } = complete_field()

      assert options == [
               {"all", "All - when every lane is done"},
               {"first", "First - when any one lane is done"}
             ]
    end

    # The backward-compatibility property the spike's selftest names: every
    # `core.parallel` stored before the key existed has to validate exactly
    # as it did.
    #
    # Sabotage: read the key with `Map.get(config, "complete")` instead of
    # through its default -> an absent key became `nil`, every stored
    # parallel in the vocabulary grew a finding, and this went red along
    # with a good part of the suite (verified).
    test "an absent key validates as it did before the key existed" do
      assert Parallel.validate_config(%{}) == :ok
      assert Parallel.validate_config(%{"lanes" => @lanes}) == :ok
    end

    # Sabotage: made `check_complete/1` return `:ok` unconditionally -> a
    # config could name any rule at all, `emit/2`'s refusal arm became the
    # only guard, and this went red (verified).
    test "a value that is neither rule is refused, and a stored null is not an absent key" do
      assert Parallel.validate_config(%{"lanes" => @lanes, "complete" => "first"}) == :ok
      assert {:error, [{"complete", _}]} = Parallel.validate_config(%{"complete" => "sideways"})
      assert {:error, [{"complete", _}]} = Parallel.validate_config(%{"complete" => nil})
    end

    # Sabotage: swapped the arguments to `combine/2` -> the complete
    # finding came back ahead of the lane one, which is not the order the
    # schema declares the fields in, and this went red (verified).
    test "lane findings come first, then complete's" do
      assert {:error, [{"lanes", _}, {"complete", _}]} =
               Parallel.validate_config(%{"lanes" => 5, "complete" => "sideways"})
    end

    # The join marker's words are the type's, read off the palette entry by
    # `BlockType.join_label/2` - so nothing on the layout path branches on
    # the string "core.parallel" (ADR-0005 decision 10).
    #
    # Sabotage: dropped `join_label` from `palette_entry/0` -> the entry
    # declared no callback, `BlockType.join_label/2` answered `nil`, and
    # the two entry assertions went red (verified).
    test "join_label reads the completion rule, and the palette entry declares it" do
      assert Parallel.join_label(%{"complete" => "first"}) == "continue at first"
      assert Parallel.join_label(%{"complete" => "all"}) == "continue when all"
      assert Parallel.join_label(%{}) == "continue when all"

      entry = Parallel.palette_entry()

      assert BlockType.join_label(entry, %{"complete" => "first"}) == "continue at first"
      assert BlockType.join_label(entry, %{}) == "continue when all"
    end
  end

  describe "complete: all" do
    # The golden pin the amendment's "what this does not change" clause
    # asks for: the shipped rule moves no byte, and an explicit "all" is
    # the same document as one stored before the key existed.
    #
    # Sabotage: had `running/4`'s "all" clause emit the per-lane joins as
    # well as the wrapper transition -> the two documents still matched
    # each other but no longer matched the shipped bytes, and the pinned
    # substring below went red (verified).
    test "an absent key and an explicit all compile to the same bytes" do
      absent = compile!(parallel(%{"lanes" => @lanes})).scxml
      explicit = compile!(parallel(%{"lanes" => @lanes, "complete" => "all"})).scxml

      assert absent == explicit

      assert absent =~
               ~s(<state id="s_blk_PAR" initial="s_blk_PAR__run">) <>
                 ~s(<transition event="done.state.s_blk_PAR__run" ) <>
                 ~s(target="s_blk_PAR__o_done" type="internal"/>) <>
                 ~s(<parallel id="s_blk_PAR__run"><state id="s_blk_PAR__lane_authorize")
    end

    # Sabotage: dropped the `lanes(config) == []` clause from `emit/2` ->
    # an empty parallel emitted `<parallel>` with no region, which is not
    # valid SCXML, and both arms went red (verified).
    test "a parallel with no lanes ignores the rule entirely" do
      all = compile!(parallel(%{"lanes" => [], "complete" => "all"})).scxml
      first = compile!(parallel(%{"lanes" => [], "complete" => "first"})).scxml

      assert all == first
      refute all =~ "<parallel"
    end
  end

  describe "complete: first" do
    # P1, the whole of it: one transition per lane, on the `<parallel>`
    # element itself, each on that lane's own completion event and
    # targeting the block's done final - and ahead of the regions, which is
    # the fixed position decision 6's determinism asks the emitter to pick.
    #
    # Sabotage: put the joins after the regions instead of before them ->
    # the bytes stayed valid SCXML and the runtime cases below still
    # passed, which is exactly why the position needs its own pin; this
    # went red (verified).
    test "one transition per lane, on the parallel, ahead of the regions" do
      scxml = compile!(parallel(%{"lanes" => @lanes, "complete" => "first"})).scxml

      assert scxml =~
               ~s(<parallel id="s_blk_PAR__run">) <>
                 ~s(<transition event="done.state.s_blk_PAR__lane_authorize" ) <>
                 ~s(target="s_blk_PAR__o_done"/>) <>
                 ~s(<transition event="done.state.s_blk_PAR__lane_fraud_check" ) <>
                 ~s(target="s_blk_PAR__o_done"/>) <>
                 ~s(<state id="s_blk_PAR__lane_authorize")
    end

    # The transitions leave the `<parallel>`, and leaving it is the point:
    # `type="internal"` would preserve the very regions P2 needs exited.
    #
    # Sabotage: passed `internal: true` to the join builder -> each join
    # wrote `type="internal"`, the losing lane was never exited, and this
    # went red alongside the runtime cases (verified).
    test "the joins are external" do
      scxml = compile!(parallel(%{"lanes" => @lanes, "complete" => "first"})).scxml

      refute scxml =~
               ~s(<transition event="done.state.s_blk_PAR__lane_authorize" ) <>
                 ~s(target="s_blk_PAR__o_done" type="internal"/>)
    end

    # The wrapper's `done.state.<run>` transition is dropped rather than
    # kept: it can never be taken, because the first region to go final
    # raises its own completion event and exits the `<parallel>` on it.
    #
    # Sabotage: kept the wrapper transition in the "first" clause -> the
    # chart still ran identically, which is the point - a transition that
    # can never fire is bytes a reader has to explain away; this went red
    # (verified).
    test "the wrapper's done.state.<run> transition is gone" do
      scxml = compile!(parallel(%{"lanes" => @lanes, "complete" => "first"})).scxml

      refute scxml =~ ~s(event="done.state.s_blk_PAR__run")
    end

    # The case dropping it could have needed: both lanes reach their finals
    # in the same macrostep, so the all-lanes `done.state.<run>` is raised
    # too. A region's own completion event is still raised and processed
    # first, so the block finishes on it and the dropped transition is not
    # missed.
    #
    # Sabotage: dropped the joins entirely -> `done.state.<run>` was the
    # only completion event left and nothing was listening for it, so the
    # block sat in its lanes and this went red (verified).
    test "lanes that finish in the same macrostep still finish the block" do
      compiled = compile!(parallel(%{"lanes" => @lanes, "complete" => "first"}))
      {:ok, machine} = Statifier.compile(compiled.scxml)
      {machine_state, _effects} = Statifier.initialize(machine)

      assert MapSet.member?(Statifier.active_leaf_states(machine_state), "s_blk_PAR__o_done")
    end

    # The transition set is a pure function of the ordered lane list
    # (decision 6), so reordering the lanes reorders the joins and nothing
    # else.
    #
    # Sabotage: built the joins from a `MapSet` of region ids rather than
    # from the ordered list -> the order stopped tracking config and this
    # went red (verified).
    test "the joins follow the ordered lane list" do
      scxml = compile!(parallel(%{"lanes" => Enum.reverse(@lanes), "complete" => "first"})).scxml

      assert scxml =~
               ~s(<transition event="done.state.s_blk_PAR__lane_fraud_check" ) <>
                 ~s(target="s_blk_PAR__o_done"/>) <>
                 ~s(<transition event="done.state.s_blk_PAR__lane_authorize" )
    end

    # `emit/2` is total for the config it is handed, whatever the Config
    # stage would have said about it (ADR-0004 decision 4).
    #
    # Sabotage: dropped the `complete not in @complete` clause from
    # `emit/2` -> `running/4` had no matching clause and the emitter raised
    # a FunctionClauseError instead of answering, taking this red
    # (verified).
    test "an unknown rule is answered, not raised on" do
      block = Block.new("core.parallel", id: "blk_PAR", config: %{"lanes" => @lanes})

      assert {:error, [{"complete", _}]} =
               Parallel.emit(
                 %{block | config: %{"lanes" => @lanes, "complete" => "sideways"}},
                 Context.new("blk_PAR", "bdoc_T", %{})
               )
    end
  end

  describe "P3: the lane's own region carries its cancel" do
    # The composition the amendment records: a lane is a region and
    # therefore a scope, so a delayed send armed in a lane is cancelled by
    # that lane's `<onexit>` and not by the block wrapper's.
    #
    # Sabotage: had `Cancels.arm/2` place every cancel on the parent's own
    # emission root, as it did before this bead -> the `<onexit>` landed on
    # `s_blk_PAR` and this went red on both arms (verified).
    test "in first, the cancel is in the lane's region" do
      scxml = compile!(racing_with_send()).scxml

      assert scxml =~
               ~s(<state id="s_blk_PAR__lane_fraud_check" initial="s_blk_SND">) <>
                 ~s(<onexit><cancel sendid="s_blk_SND__send"/></onexit>)

      refute scxml =~ ~s(<state id="s_blk_PAR" initial="s_blk_PAR__run"><onexit>)
    end

    # The same placement under the shipped rule: an `all` parallel exits
    # its regions too, and a send armed in one of them is cancelled the
    # same way. P3 is about the scope, not about the completion rule.
    #
    # Sabotage: took the `<state>` clause off `Cancels.claim/3`, so no
    # scope inside the emission claimed anything -> every cancel fell
    # through to the block wrapper, which is where the pass put them
    # before this bead, and this went red (verified).
    test "in all, the cancel is in the lane's region too" do
      scxml = compile!(racing_with_send("all")).scxml

      assert scxml =~
               ~s(<state id="s_blk_PAR__lane_fraud_check" initial="s_blk_SND">) <>
                 ~s(<onexit><cancel sendid="s_blk_SND__send"/></onexit>)
    end

    # One send, one cancel, wherever the scope turns out to be.
    #
    # Sabotage: let a scope claim ids it had already emitted a cancel for
    # -> the wrapper repeated the region's cancel and this went red
    # (verified).
    test "the send is cancelled once" do
      scxml = compile!(racing_with_send()).scxml

      assert [_one] = Regex.scan(~r/<cancel /, scxml)
    end

    # A `core.parallel` lane is not the only region in the vocabulary: a
    # `core.group` with an interrupt rail puts its body in one too. Placing
    # the cancel there rather than on the group's own state is a fix as well
    # as a move - the group's abandon transition is internal and targets the
    # group's own final, so it exits the body region WITHOUT exiting the
    # group, and a cancel on the group's `<onexit>` never fired for it.
    #
    # Sabotage: took the `<state>` clause off `Cancels.claim/3`, which is
    # the placement this pass had before the bead -> the `<onexit>` went
    # back onto `s_blk_GRP`, the compile assertion went red, and the run
    # case came back with no cancel at all (verified).
    test "a guarded group's body region carries its own cancel, and it fires" do
      scxml = compile!(abandonable_send()).scxml

      assert scxml =~
               ~s(<state id="s_blk_GRP__body" initial="s_blk_SND">) <>
                 ~s(<onexit><cancel sendid="s_blk_SND__send"/></onexit>)

      {:ok, machine} = Statifier.compile(scxml)
      {machine_state, _effects} = Statifier.initialize(machine)
      {:ok, _machine_state, effects} = Statifier.send_event(machine_state, "payment.cancelled")

      assert [%Cancel{send_id: "s_blk_SND__send"}] = cancels(effects)
    end
  end

  describe "the racing chart, run" do
    setup do
      compiled = compile!(racing_with_send())
      {:ok, machine} = Statifier.compile(compiled.scxml)

      {machine_state, effects} =
        Statifier.initialize(machine,
          invoke_types: InvokeTypes.new(types: ["myapp:fraud_check"])
        )

      %{machine_state: machine_state, initial_effects: effects}
    end

    # Both lanes are live and neither has won: the authorize lane is parked
    # on its interrupt rail, the fraud lane on its invocation.
    #
    # Sabotage: built the joins with no `event` at all -> an eventless
    # transition is eligible the moment the `<parallel>` is entered, the
    # block finished during initialization with both lanes untouched, and
    # this went red (verified).
    test "both lanes are still running before either finishes", ctx do
      active = Statifier.active_leaf_states(ctx.machine_state)

      assert MapSet.member?(active, "s_blk_AOK__armed")
      assert MapSet.member?(active, "s_blk_FRAUD__running")
      assert cancels(ctx.initial_effects) == []
    end

    # P2, first half: the block is done at the FIRST lane's completion, and
    # the losing lane is no longer in the configuration.
    #
    # Sabotage: emitted one join on the all-lanes `done.state.<run>` event
    # instead of one per lane -> the authorize lane finished, the fraud
    # lane kept running, the block never reached its final and this went
    # red (verified).
    test "the first lane's completion finishes the block and exits the loser", ctx do
      {:ok, machine_state, _effects} =
        Statifier.send_event(ctx.machine_state, "payment.authorized")

      active = Statifier.active_leaf_states(machine_state)

      assert MapSet.member?(active, "s_blk_PAR__o_done")
      refute MapSet.member?(active, "s_blk_FRAUD__running")
    end

    # P2, second half, and none of it this package's to implement: exiting
    # the `<parallel>` exits the losing region, and the engine raises one
    # `CancelInvoke` for the invocation it owned (spec 6.4, "as if it were
    # the final <onexit> handler"). The invoke id is the engine's to mint -
    # `core.invoke` writes no `id` - so what is pinned is the one the
    # resolved dependency actually produces.
    #
    # `st-iefu` records that a WINNING lane draws a cancel too, for an
    # invocation that has already completed. That is pre-existing engine
    # behaviour, ruled upstream as an `Invoke.Handler` documentation line
    # (`st-9wkc`); the winning lane here holds no invocation, so this shape
    # does not observe it and does not contradict it.
    #
    # Sabotage: dropped the join transitions entirely -> nothing exited the
    # parallel, no cancel was raised and this went red (verified).
    test "the losing lane's live invocation draws one CancelInvoke", ctx do
      {:ok, _machine_state, effects} =
        Statifier.send_event(ctx.machine_state, "payment.authorized")

      assert [%CancelInvoke{invoke_id: "s_blk_FRAUD__running.inv_1"}] =
               for({:cancel_invoke, cancel} <- effects, do: cancel)
    end

    # P3 at runtime: the losing lane's `<onexit>` cancel resolves to a
    # `{:cancel, %Cancel{}}` naming the derived send id - the pair
    # `{session scope, send id}` statifier-ex ADR-0054 decision 3 keys a
    # pending delayed send on.
    #
    # Sabotage: wrote the send block's state id as the `sendid` rather
    # than the derived send id -> a cancel still surfaced, naming a send
    # nothing had armed, and this went red on the id (verified). Taking
    # the `<state>` clause off `Cancels.claim/3`, which moves the cancel
    # back onto the block wrapper, takes it red too.
    test "the losing lane's delayed send is cancelled on the way out", ctx do
      {:ok, _machine_state, effects} =
        Statifier.send_event(ctx.machine_state, "payment.authorized")

      assert [%Cancel{send_id: "s_blk_SND__send"}] = cancels(effects)
    end
  end

  defp cancels(effects), do: for({:cancel, cancel} <- effects, do: cancel)

  defp complete_field do
    Enum.find(Parallel.config_schema(%{}), &(&1.key == "complete"))
  end

  defp parallel(config, slots \\ %{}) do
    Block.new("core.parallel", id: "blk_PAR", config: config, slots: slots)
  end

  # A credit-card authorization racing a fraud check: the authorize lane
  # finishes when the host reports the authorization, the fraud lane is
  # still holding an invocation and a delayed send when it does.
  defp racing_with_send(complete \\ "first") do
    parallel(
      %{"lanes" => @lanes, "complete" => complete},
      %{
        "lane_authorize" => [
          Block.new("core.group",
            id: "blk_AUTH",
            slots: %{
              "body" => [
                Block.new("core.wait", id: "blk_AUTHW", config: %{"duration" => "PT48H"})
              ],
              "interrupts" => [
                Block.new("core.on_event",
                  id: "blk_AOK",
                  config: %{"event" => "payment.authorized", "outcome" => "abandon"}
                )
              ]
            }
          )
        ],
        "lane_fraud_check" => [
          Block.new("core.send",
            id: "blk_SND",
            config: %{"event" => "payment.review_due", "delay" => "2h"}
          ),
          Block.new("core.invoke",
            id: "blk_FRAUD",
            config: %{"invoke_type" => "myapp:fraud_check"}
          )
        ]
      }
    )
  end

  # A group that can be abandoned mid-body, so the body region is genuinely
  # exited at runtime while the group's own state stays in the configuration.
  defp abandonable_send do
    Block.new("core.group",
      id: "blk_GRP",
      slots: %{
        "body" => [
          Block.new("core.send",
            id: "blk_SND",
            config: %{"event" => "payment.review_due", "delay" => "2h"}
          ),
          Block.new("core.wait", id: "blk_HOLD", config: %{"duration" => "PT48H"})
        ],
        "interrupts" => [
          Block.new("core.on_event",
            id: "blk_INT",
            config: %{"event" => "payment.cancelled", "outcome" => "abandon"}
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
