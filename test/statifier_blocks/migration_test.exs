defmodule StatifierBlocks.MigrationTest do
  @moduledoc """
  `StatifierBlocks.Migration.plan/2`: the state mapping between two compiled
  revisions of one document (ADR-0004's amendment of 2026-09-23, M1 to M5).

  The documents are the library's. A hold routes a copy to the patron's
  pickup branch and then waits for the patron to collect it, with the pickup
  timer armed by the wait block; the edit relabels that wait block "Ready for
  pickup" and gives the routing step a `transferred` outcome and a new block
  after the wait. A loan keeps a renewal reminder and a due-date wait inside a
  resumable group, which is where a history state and an `<invoke>` come from.

  Pure: nothing here names LiveView, so it runs in the headless job too.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{Block, Compiled, Compiler, Document, Migration, Palette, Provenance}
  alias StatifierBlocks.Compiler.Context
  alias StatifierBlocks.Core.Emit
  alias StatifierBlocks.Emission

  defmodule RouteCopy do
    @moduledoc """
    Routes a copy to a branch. Its outcomes are the newline-separated
    `outcomes` config field, each an outcome final inside its own state.
    """

    use StatifierBlocks.BlockType

    @impl true
    def outcomes(%{"outcomes" => outcomes}) do
      outcomes
      |> String.split("\n", trim: true)
      |> Enum.map(&{&1, String.capitalize(&1)})
    end

    @impl true
    def emit(%Block{config: config}, context) do
      finals =
        Enum.map(outcomes(config), fn {name, _label} ->
          {:ok, id} = Context.outcome_id(context, name)
          id
        end)

      {:ok, Emit.state(context.state_id, hd(finals), Enum.map(finals, &Emit.final/1))}
    end
  end

  defmodule NotifyPatron do
    @moduledoc """
    Notifies a patron on each of its `channels` (a count): one `<invoke>` per
    channel, all in the block's own state.
    """

    use StatifierBlocks.BlockType

    @impl true
    def emit(%Block{config: %{"channels" => channels}}, context) do
      {:ok, done} = Context.outcome_id(context, "done")

      invokes =
        for _channel <- 1..channels//1,
            do: Emission.element("invoke", [{"type", "library:notify_patron"}])

      {:ok, Emit.state(context.state_id, done, invokes ++ [Emit.final(done)])}
    end
  end

  defp palette do
    Palette.new(
      Map.merge(Palette.core_types(), %{
        "library.route_copy" => RouteCopy,
        "library.notify_patron" => NotifyPatron
      })
    )
  end

  defp compile!(document) do
    {:ok, %Compiled{} = compiled} = Compiler.compile(document, palette())
    compiled
  end

  defp route(outcomes),
    do: Block.new("library.route_copy", id: "blk_ROUTE", config: %{"outcomes" => outcomes})

  defp pickup(label),
    do: Block.new("core.wait", id: "blk_PICKUP", config: %{"duration" => "3d", "label" => label})

  defp hold(body, id \\ "bdoc_HOLD"),
    do: Document.new(Block.new("core.sequence", id: "blk_HOLD", slots: %{"body" => body}), id: id)

  # The hold as published: route the copy, then wait at the pickup branch.
  defp hold_before, do: compile!(hold([route("routed"), pickup("Awaiting pickup")]))

  # The edit: the wait relabelled, the routing step given a `transferred`
  # outcome, and a new block after the wait.
  defp hold_after do
    transfer = Block.new("core.wait", id: "blk_TRANSFER", config: %{"duration" => "1d"})

    compile!(hold([route("routed\ntransferred"), pickup("Ready for pickup"), transfer]))
  end

  defp loan(channels) do
    notify =
      Block.new("library.notify_patron", id: "blk_NOTIFY", config: %{"channels" => channels})

    due = Block.new("core.wait", id: "blk_DUE", config: %{"duration" => "14d"})

    renew =
      Block.new("core.on_event",
        id: "blk_RENEW",
        config: %{"event" => "loan.renew", "outcome" => "resume"}
      )

    group =
      Block.new("core.resumable_group",
        id: "blk_RENEWAL",
        config: %{"history" => "shallow"},
        slots: %{"body" => [notify, due], "interrupts" => [renew]}
      )

    compile!(
      Document.new(Block.new("core.sequence", id: "blk_LOAN", slots: %{"body" => [group]}),
        id: "bdoc_LOAN"
      )
    )
  end

  defp identity(ids), do: Map.new(ids, &{&1, &1})

  @hold_states ~w(
    s_blk_HOLD s_blk_HOLD__o_done
    s_blk_ROUTE s_blk_ROUTE__o_routed
    s_blk_PICKUP s_blk_PICKUP__waiting s_blk_PICKUP__o_done
  )

  describe "the library hold's edit (M1, M2)" do
    # Sabotage: `counterpart?/4` answering `false` for any state whose owner
    # carries a role - every auxiliary state (the outcome finals, the wait's
    # `waiting` state) moves to `unmapped` and the equality goes red.
    test "maps every state of the old chart to itself, roles included, and leaves nothing unmapped" do
      assert Migration.plan(hold_before(), hold_after()) ==
               {:ok,
                %{
                  "states" => identity(@hold_states),
                  "history" => %{},
                  "invocations" => [],
                  "unmapped" => []
                }}
    end

    # Sabotage: `chart_states/1` reading the ids from `by_state_id`'s keys
    # instead of the chart's state elements - the wait's timer send id is a
    # key there, lands in `states`, and the refutation goes red.
    test "the pickup timer's send id is not a state and is mapped nowhere" do
      before = hold_before()
      assert Map.has_key?(before.provenance.by_state_id, "s_blk_PICKUP__send")

      {:ok, mapping} = Migration.plan(before, hold_after())

      refute Map.has_key?(mapping["states"], "s_blk_PICKUP__send")
      refute Enum.any?(mapping["unmapped"], &(&1["state_id"] == "s_blk_PICKUP__send"))
    end

    # Sabotage: building `states` from the to chart's states instead of the
    # from chart's - the new outcome final and the new block's states appear
    # as keys and the refutation goes red.
    test "a state only the new revision has appears nowhere" do
      {:ok, mapping} = Migration.plan(hold_before(), hold_after())

      for new_id <- ~w(s_blk_ROUTE__o_transferred s_blk_TRANSFER s_blk_TRANSFER__waiting) do
        refute Map.has_key?(mapping["states"], new_id)
        refute new_id in Map.values(mapping["states"])
      end
    end

    # Sabotage: `plan/2` keying `"states"` by atoms
    # (`Map.new(states, &{String.to_atom(&1.id), &1.id})`) - the JSON round
    # trip reads string keys back and the equality goes red.
    test "is plain data with string keys that survives a JSON round trip" do
      {:ok, mapping} = Migration.plan(hold_before(), hold_after())

      assert mapping |> JSON.encode!() |> JSON.decode!() == mapping
    end
  end

  describe "a state with no counterpart (M3)" do
    # Sabotage: `plan/2` putting every from state in `states` whatever
    # `counterpart?/4` answers - the wait's states are mapped and `unmapped`
    # is empty, so the equality goes red.
    test "a deleted wait block's states are listed with their owner, sorted, and never mapped" do
      without_pickup = compile!(hold([route("routed\ntransferred")]))

      {:ok, mapping} = Migration.plan(hold_before(), without_pickup)

      assert mapping["unmapped"] == [
               %{"state_id" => "s_blk_PICKUP", "block_id" => "blk_PICKUP", "role" => nil},
               %{
                 "state_id" => "s_blk_PICKUP__o_done",
                 "block_id" => "blk_PICKUP",
                 "role" => "o_done"
               },
               %{
                 "state_id" => "s_blk_PICKUP__waiting",
                 "block_id" => "blk_PICKUP",
                 "role" => "waiting"
               }
             ]

      assert mapping["states"] ==
               identity(~w(s_blk_HOLD s_blk_HOLD__o_done s_blk_ROUTE s_blk_ROUTE__o_routed))
    end

    # Sabotage: `unmapped_entry/2` reading the owner from the to side's
    # provenance map - the retired final and the dropped block have no owner
    # there, the call raises, and the test goes red.
    test "an outcome a surviving block no longer declares leaves its final unmapped, in either order" do
      {:ok, mapping} = Migration.plan(hold_after(), hold_before())

      assert mapping["unmapped"] == [
               %{
                 "state_id" => "s_blk_ROUTE__o_transferred",
                 "block_id" => "blk_ROUTE",
                 "role" => "o_transferred"
               },
               %{"state_id" => "s_blk_TRANSFER", "block_id" => "blk_TRANSFER", "role" => nil},
               %{
                 "state_id" => "s_blk_TRANSFER__o_done",
                 "block_id" => "blk_TRANSFER",
                 "role" => "o_done"
               },
               %{
                 "state_id" => "s_blk_TRANSFER__waiting",
                 "block_id" => "blk_TRANSFER",
                 "role" => "waiting"
               }
             ]

      assert mapping["states"] == identity(@hold_states)
    end

    # Sabotage: `same_owner?/2` answering `true` for any two owners - the
    # state whose to-side owner reads as a different block is mapped, and the
    # assertion goes red.
    test "an equal state id whose two owners differ does not correspond" do
      after_edit = hold_after()
      # The other reading of `s_blk_PICKUP__waiting`: block `blk_PICKUP__waiting`'s own state.
      other_reading = Provenance.owner("blk_PICKUP__waiting")

      by_state_id =
        Map.put(after_edit.provenance.by_state_id, "s_blk_PICKUP__waiting", other_reading)

      after_edit = put_in(after_edit.provenance.by_state_id, by_state_id)

      {:ok, mapping} = Migration.plan(hold_before(), after_edit)

      assert mapping["unmapped"] == [
               %{
                 "state_id" => "s_blk_PICKUP__waiting",
                 "block_id" => "blk_PICKUP",
                 "role" => "waiting"
               }
             ]

      refute Map.has_key?(mapping["states"], "s_blk_PICKUP__waiting")
    end
  end

  describe "two documents (M4)" do
    # Sabotage: deleting `plan/2`'s `document_id` clause - the two charts
    # share no state, so the answer is `{:ok, _}` with everything unmapped.
    test "an artifact of the hold and one of patron registration are refused" do
      registration = compile!(hold([route("routed")], "bdoc_PATRON_REGISTRATION"))

      assert Migration.plan(hold_before(), registration) == {:error, :different_documents}
      assert Migration.plan(registration, hold_before()) == {:error, :different_documents}
    end

    # Sabotage: comparing `record.revision` as well as `document_id` - two
    # compiles of the same revision still map, but a revision-1 artifact
    # against a revision-0 one is refused and the second assertion goes red.
    test "two artifacts of one document map whatever their revisions" do
      before = hold_before()
      assert {:ok, %{"unmapped" => []}} = Migration.plan(before, before)

      revised = %{hold_after() | record: %{hold_after().record | revision: 1}}
      assert {:ok, %{"unmapped" => []}} = Migration.plan(before, revised)
    end
  end

  describe "history and invocations (M2, M5)" do
    # Sabotage: `plan/2` splitting on `&1.kind == "final"` instead of
    # `"history"` - the history state lands in `states` and the finals in
    # `history`, and the equality goes red.
    test "a mapped history state is under history and nowhere else" do
      {:ok, mapping} = Migration.plan(loan(1), loan(1))

      assert mapping["history"] == %{"s_blk_RENEWAL__history" => "s_blk_RENEWAL__history"}
      refute Map.has_key?(mapping["states"], "s_blk_RENEWAL__history")
      assert Map.has_key?(mapping["states"], "s_blk_RENEWAL__run")
      assert mapping["unmapped"] == []
    end

    # Sabotage: `invocations/2` reading `ordinals(count)` from the from
    # state alone - the from state's second `<invoke>`, ordinal 1, gets an
    # entry the to state has no ordinal for, and the equality goes red.
    test "an invocation maps to the same ordinal only where the to state has one" do
      assert {:ok, %{"invocations" => both}} = Migration.plan(loan(2), loan(2))

      assert both == [
               ["s_blk_NOTIFY", 0, "s_blk_NOTIFY", 0],
               ["s_blk_NOTIFY", 1, "s_blk_NOTIFY", 1]
             ]

      assert {:ok, %{"invocations" => fewer}} = Migration.plan(loan(2), loan(1))
      assert fewer == [["s_blk_NOTIFY", 0, "s_blk_NOTIFY", 0]]

      assert {:ok, %{"invocations" => []}} = Migration.plan(loan(1), loan(0))
    end
  end

  describe "artifacts compile/3 never produces" do
    # Sabotage: `chart_states/1` treating a parse error as an empty chart -
    # the call answers `{:ok, _}` and `assert_raise` goes red.
    test "an scxml that does not parse raises" do
      broken = %{hold_before() | scxml: "<scxml><state id=\"s_blk_HOLD\">"}

      assert_raise ArgumentError, ~r/does not parse/, fn ->
        Migration.plan(broken, hold_after())
      end
    end

    # Sabotage: `unmapped_entry/2` answering `nil` owners for a state it
    # cannot find - the call answers `{:ok, _}` and `assert_raise` goes red.
    test "a from state its own provenance map does not own raises" do
      before = hold_before()

      orphaned =
        put_in(
          before.provenance.by_state_id,
          Map.delete(before.provenance.by_state_id, "s_blk_PICKUP")
        )

      assert_raise ArgumentError, ~r/s_blk_PICKUP/, fn ->
        Migration.plan(orphaned, hold_after())
      end
    end
  end
end
