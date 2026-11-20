defmodule StatifierBlocks.Runtime.BackTest do
  @moduledoc """
  Whether Back is offered, read from an execution's datamodel and active
  leaf states. Every answer is checked against what delivering the reserved
  back event to the same execution actually does: `offered?/3` is `true`
  exactly when Back moves the execution.

  The fixtures are test-only types for a library's patron registration.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{Block, Compiler, Document, Palette}
  alias StatifierBlocks.Compiler.Context
  alias StatifierBlocks.Core.Emit
  alias StatifierBlocks.Runtime.Back

  doctest StatifierBlocks.Runtime.Back

  defmodule Collect do
    @moduledoc """
    Collects one answer from a patron: waits for the event its config names
    (`step.submitted` by default) and completes. Returnable unless its
    config says the patron may not come back to it.
    """
    use StatifierBlocks.BlockType

    @impl true
    def config_schema(_config) do
      [
        %{
          key: "revisable",
          type: :boolean,
          label: "The patron may come back to this",
          required?: false,
          default: true
        },
        %{
          key: "event",
          type: :string,
          label: "The event that completes it",
          required?: false,
          default: "step.submitted"
        }
      ]
    end

    @impl true
    def returnable?(config), do: Map.get(config, "revisable", true) == true

    @impl true
    def emit(%Block{config: config}, context) do
      done = Context.done_id(context)
      {:ok, waiting} = Context.role_id(context, "waiting")
      submit = Emit.transition(event: Map.get(config, "event", "step.submitted"), target: done)

      {:ok,
       Emit.state(context.state_id, waiting, [
         Emit.state(waiting, nil, [submit]),
         Emit.final(done)
       ])}
    end
  end

  @back "statifier_blocks.back"

  describe "a registration (L4, L5)" do
    # sabotage: answered `true` for any non-empty trail in `answer/3` (the
    # top-step clause dropped) -> the first step offered Back that does
    # nothing and this went red (verified)
    test "the first step offers nothing, the steps after it offer Back" do
      run = start(registration())
      assert leaves(run) == ["s_blk_NAME__waiting"]
      refute offered?(run)
      refute moves?(run)

      run = deliver(run, "step.submitted")
      assert leaves(run) == ["s_blk_CARD__waiting"]
      assert offered?(run)
      assert moves?(run)
    end

    # sabotage: answered `below != []` whatever the leaf in `answer/3` ->
    # the step that is not returnable, with only the name behind it,
    # offered nothing and this went red (verified)
    test "a step that is not returnable offers Back to the trail's top step" do
      root =
        Block.new("core.sequence",
          id: "blk_ROOT",
          slots: %{"body" => [step("blk_NAME"), note("blk_RULES")]}
        )

      run = root |> start() |> deliver("step.submitted")
      assert leaves(run) == ["s_blk_RULES__waiting"]
      assert run.datamodel["s_blk_ROOT__trail"] == ["s_blk_NAME", []]

      assert offered?(run)
      assert moves?(run)
    end

    # sabotage: dropped the top-step clause of `answer/3` (any non-empty
    # trail offers) -> the first step disagreed with Back and this went red (verified)
    test "every position of a walk answers as Back behaves" do
      run = start(registration())

      Enum.reduce(1..4, run, fn _step, run ->
        assert offered?(run) == moves?(run)
        deliver(run, "step.submitted")
      end)
      |> then(fn run ->
        assert leaves(run) == ["s_blk_ROOT__o_done"]
        refute offered?(run)
        refute moves?(run)
      end)
    end

    # sabotage: made `offered?/3` answer `true` for every leaf -> this went
    # red (verified)
    test "a document with no returnable step offers nothing" do
      run = start(registration(revisable: false))
      run = run |> deliver("step.submitted") |> deliver("step.submitted")

      refute offered?(run)
      refute moves?(run)
    end

    # sabotage: read a block the document lacks as the root, `{:ok, []}`,
    # in place of `Document.fetch_path/2`'s `:error` in `leaf_offers?/3`
    # -> the leaf of the missing block offered Back and this went red (verified)
    test "a leaf this package did not mint, or a block the document lacks, offers nothing" do
      document = Document.new(registration())
      datamodel = %{"s_blk_ROOT__trail" => ["s_blk_CARD", ["s_blk_NAME", []]]}

      refute Back.offered?(datamodel, [:waiting, "waiting", "s_blk_GONE__waiting"], document)
      refute Back.offered?(datamodel, [], document)
      assert Back.offered?(datamodel, MapSet.new(["s_blk_RULES__waiting"]), document)
    end
  end

  describe "the scopes around the position (L1, L6)" do
    # sabotage: read only the document's trail in `trails/3` (the nested
    # comprehension made `[]`) -> the loop body's second step offered
    # nothing and this went red (verified)
    test "inside a loop body the body's trail answers" do
      run = start(looping(), patrons("['ada']"))
      run = deliver(run, "step.submitted")
      assert leaves(run) == ["s_blk_B1__waiting"]
      refute offered?(run)
      refute moves?(run)

      run = deliver(run, "step.submitted")
      assert leaves(run) == ["s_blk_B2__waiting"]
      assert offered?(run)
      assert moves?(run)
    end

    # sabotage: read every trail in the datamodel rather than the ones
    # around the leaf in `trails/3` -> the lane the race stopped still
    # offered Back after the parallel and this went red (verified)
    test "a lane stopped by complete: first offers nothing after the parallel" do
      run = start(racing())
      assert leaves(run) == ["s_blk_RECV__waiting", "s_blk_SEND__waiting"]
      refute offered?(run)
      refute moves?(run)

      run = deliver(run, "send.submitted")
      assert leaves(run) == ["s_blk_AFTER__waiting"]
      assert run.datamodel["s_blk_P__lane_recipient__trail"] == ["s_blk_RECV", []]

      refute offered?(run)
      refute moves?(run)
    end

    # sabotage: answered with the first leaf only (`Enum.take(active, 1)`
    # in `offered?/3`) -> the recipient's lane, sorted second, was never
    # read and this went red (verified)
    test "in parallel lanes each leaf answers for its own lane" do
      run = start(racing(recipient: [step("blk_RECV", "recv.submitted"), note("blk_SIGN")]))
      run = deliver(run, "recv.submitted")
      assert leaves(run) == ["s_blk_SEND__waiting", "s_blk_SIGN__waiting"]

      assert offered?(run)
      assert moves?(run)
    end
  end

  describe "nested scopes (L1, L6)" do
    # sabotage: dropped `Enum.reverse/1` in `trails/3` (the lane's trail
    # read as the innermost) -> the body's first step offered Back and this
    # went red (verified)
    test "a loop inside a lane: the body's trail answers, innermost first" do
      run = start(lane_loop(), patrons("['ada']"))
      run = deliver(run, "step.submitted")
      assert leaves(run) == ["s_blk_B1__waiting"]
      assert run.datamodel["s_blk_P__lane_sender__trail"] == []
      assert run.datamodel["s_blk_F__body__trail"] == ["s_blk_B1", []]

      refute offered?(run)
      refute moves?(run)
    end

    # sabotage: answered `below != []` whatever the leaf in `answer/3` ->
    # the step after the body's only returnable step offered nothing and
    # this went red (verified)
    test "a step that is not returnable inside a loop body offers the body's top step" do
      run = start(lane_loop(), patrons("['ada']"))
      run = run |> deliver("step.submitted") |> deliver("step.submitted")
      assert leaves(run) == ["s_blk_RULES__waiting"]

      assert offered?(run)
      assert moves?(run)
    end
  end

  # -- Fixtures ------------------------------------------------------------------

  # One lane holding a returnable step, then a loop whose body is a
  # returnable step and a step that is not; the other lane is empty.
  defp lane_loop do
    loop =
      Block.new("core.foreach",
        id: "blk_F",
        config: %{"items" => "patrons", "item_as" => "patron"},
        slots: %{"body" => [step("blk_B1"), note("blk_RULES")]}
      )

    Block.new("core.parallel",
      id: "blk_P",
      config: %{"lanes" => ["sender"]},
      slots: %{"lane_sender" => [step("blk_SEND"), loop]}
    )
  end

  defp step(id, event \\ "step.submitted"),
    do: Block.new("library.collect", id: id, config: %{"event" => event})

  defp note(id),
    do: Block.new("library.collect", id: id, config: %{"revisable" => false})

  # Name and card are returnable, the rules step is not, pickup is.
  defp registration(opts \\ []) do
    revisable = Keyword.get(opts, :revisable, true)
    collect = &Block.new("library.collect", id: &1, config: %{"revisable" => &2})

    Block.new("core.sequence",
      id: "blk_ROOT",
      slots: %{
        "body" => [
          collect.("blk_NAME", revisable),
          collect.("blk_CARD", revisable),
          collect.("blk_RULES", false),
          collect.("blk_PICKUP", revisable)
        ]
      }
    )
  end

  # A step before a loop over the patrons and two returnable steps in its
  # body.
  defp looping do
    loop =
      Block.new("core.foreach",
        id: "blk_F",
        config: %{"items" => "patrons", "item_as" => "patron"},
        slots: %{"body" => [step("blk_B1"), step("blk_B2")]}
      )

    Block.new("core.sequence", id: "blk_ROOT", slots: %{"body" => [step("blk_BEFORE"), loop]})
  end

  # A parcel's two lanes racing, done at the first, then a step that is not
  # returnable.
  defp racing(opts \\ []) do
    recipient = Keyword.get(opts, :recipient, [step("blk_RECV", "recv.submitted")])

    parallel =
      Block.new("core.parallel",
        id: "blk_P",
        config: %{"lanes" => ["sender", "recipient"], "complete" => "first"},
        slots: %{
          "lane_sender" => [step("blk_SEND", "send.submitted")],
          "lane_recipient" => recipient
        }
      )

    Block.new("core.sequence", id: "blk_ROOT", slots: %{"body" => [parallel, note("blk_AFTER")]})
  end

  defp patrons(expr), do: [declare: [{"patrons", expr}]]

  defp palette, do: Palette.new(Map.put(Palette.core_types(), "library.collect", Collect))

  # A run is the machine state and the document it was compiled from.
  defp start(root, opts \\ []) do
    document = Document.new(root, id: "bdoc_REG")
    {:ok, compiled} = Compiler.compile(document, palette(), opts)
    {:ok, machine} = Statifier.compile(compiled.scxml)
    {state, _effects} = Statifier.initialize(machine)
    %{state: state, document: document, datamodel: state.datamodel}
  end

  defp deliver(%{state: state} = run, event) do
    {:ok, next, _effects} = Statifier.send_event(state, Statifier.Event.external(event))
    %{run | state: next, datamodel: next.datamodel}
  end

  defp offered?(%{state: state, document: document}),
    do: Back.offered?(state.datamodel, Statifier.active_leaf_states(state), document)

  # Whether delivering Back changes where the execution is or what its
  # trails hold.
  defp moves?(run) do
    after_back = deliver(run, @back)
    leaves(after_back) != leaves(run) or held(after_back) != held(run)
  end

  # The datamodel without the event the engine stamps on every delivery.
  defp held(%{datamodel: datamodel}), do: Map.delete(datamodel, "_event")

  defp leaves(%{state: state}), do: state |> Statifier.active_leaf_states() |> Enum.sort()
end
