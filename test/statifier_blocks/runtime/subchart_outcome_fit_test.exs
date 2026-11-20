defmodule StatifierBlocks.Runtime.SubchartOutcomeFitTest do
  @moduledoc """
  A `chart_from` child must fit the block that runs it (ADR-0004's
  Amendment of 2026-11-19, J2 and J3): each outcome the child's root
  declares is among the block's declared outcomes, or both handlers refuse
  it `child_outcome_undeclared` before it is started. A child declaring
  fewer outcomes fits, and a literal `chart` block's child is not judged.

  `async: false` because `StatifierBlocks.RuntimeFixtures.MapResolver`
  reads its answers out of `:persistent_term`, which is process-global.
  """

  use ExUnit.Case, async: false

  alias Statifier.Session
  alias Statifier.Testing.HandlerCase
  alias StatifierBlocks.{Block, Compiled, Compiler, Document}
  alias StatifierBlocks.Core.Subchart, as: SubchartBlock
  alias StatifierBlocks.Runtime.{DurableSubchart, Subchart}
  alias StatifierBlocks.RuntimeFixtures
  alias StatifierBlocks.RuntimeFixtures.MapResolver

  @type_string SubchartBlock.invoke_type()
  @carrier SubchartBlock.outcomes_param()

  @root MapSet.new(["s_blk_ROOT"])

  # A child whose root is a `core.subchart` declaring `outcomes`, so its
  # root declares them in that order with `error` appended.
  defp declaring_child(id, outcomes) do
    root =
      Block.new("core.subchart",
        id: "blk_SETUP_ROOT",
        config: %{"chart" => "bdoc_ANY", "outcomes" => Enum.join(outcomes, "\n")}
      )

    Document.new(root, id: id)
  end

  defp carrier_invoke(src, carrier, extra \\ %{}) do
    HandlerCase.build_invoke(@type_string,
      src: src,
      invoke_id: "blk_SETUP",
      params: Map.put(extra, @carrier, carrier)
    )
  end

  defp in_memory(invoke), do: Subchart.start(invoke, ctx(), MapResolver)

  defp durable(invoke),
    do: DurableSubchart.dispatch(@type_string, invoke.params, %{invoke: invoke}, MapResolver)

  defp ctx, do: HandlerCase.build_ctx(@type_string, MapResolver)

  describe "a child that declares an outcome the block did not is refused" do
    # sabotage: had `fit/2` answer `{:ok, scxml}` whatever the carrier held
    # -> both handlers plan the child's start and this goes red (verified)
    test "in-memory: no start is planned, one refusal naming the misfit" do
      MapResolver.put(
        "bdoc_CARD_READER_SETUP",
        {:ok, declaring_child("bdoc_CARD_READER_SETUP", ["done", "skipped", "needs_site_visit"])}
      )

      invoke = carrier_invoke("bdoc_CARD_READER_SETUP", "done skipped error")

      assert {:ok, [{:raise, :platform, "error.communication.invoke.blk_SETUP", origin, opts}]} =
               in_memory(invoke)

      assert origin == {:invoke, invoke.state_index, invoke.invoke_index}

      assert opts[:data] == %{
               "reason" => "child_outcome_undeclared",
               "detail" => %{
                 "chart" => "bdoc_CARD_READER_SETUP",
                 "outcomes" => ["needs_site_visit"],
                 "declared" => ["done", "skipped", "error"]
               }
             }
    end

    test "durable: dispatch answers the refusal and no child execution is asked for" do
      MapResolver.put(
        "bdoc_CARD_READER_SETUP",
        {:ok, declaring_child("bdoc_CARD_READER_SETUP", ["done", "skipped", "needs_site_visit"])}
      )

      invoke = carrier_invoke("bdoc_CARD_READER_SETUP", "done skipped error")

      assert durable(invoke) ==
               {:error,
                reason: "child_outcome_undeclared",
                detail: %{
                  "chart" => "bdoc_CARD_READER_SETUP",
                  "outcomes" => ["needs_site_visit"],
                  "declared" => ["done", "skipped", "error"]
                }}
    end

    # sabotage: reported the undeclared outcomes in sorted order -> "zeta"
    # comes after "audit" and this goes red (verified)
    test "the misfit lists the child's outcomes in the child's order, the set in the block's" do
      MapResolver.put("bdoc_R4", {:ok, declaring_child("bdoc_R4", ["zeta", "done", "audit"])})

      invoke = carrier_invoke("bdoc_R4", "skipped done error")

      assert {:error, reason: "child_outcome_undeclared", detail: detail} = durable(invoke)
      assert detail["outcomes"] == ["zeta", "audit"]
      assert detail["declared"] == ["skipped", "done", "error"]
    end

    # sabotage: had `fit/2` judge only a compile it made itself (passing a
    # resolver's `%Compiled{}` through) -> this goes red (verified)
    test "a child the resolver hands back compiled is judged by its interface" do
      {:ok, compiled} =
        Compiler.compile(
          declaring_child("bdoc_R5", ["done", "needs_site_visit"]),
          MapResolver.palette(),
          child_use: true
        )

      MapResolver.put("bdoc_R5", {:ok, compiled})

      invoke = carrier_invoke("bdoc_R5", "done error")

      assert {:ok, [{:raise, :platform, _event, _origin, opts}]} = in_memory(invoke)
      assert opts[:data]["reason"] == "child_outcome_undeclared"
      assert opts[:data]["detail"]["outcomes"] == ["needs_site_visit"]

      assert {:error, reason: "child_outcome_undeclared", detail: _detail} = durable(invoke)
    end

    test "a child that fails to compile is refused for that, before its outcomes are judged" do
      MapResolver.put("bdoc_SELF", {:ok, RuntimeFixtures.self_referencing_child("bdoc_SELF")})

      invoke = carrier_invoke("bdoc_SELF", "done")

      assert {:error, reason: "child_compile_findings", detail: _detail} = durable(invoke)
    end
  end

  describe "a child that fits starts as it always has" do
    test "a child declaring fewer outcomes than the block starts, the carrier removed" do
      MapResolver.put(
        "bdoc_READING_LIST_IMPORT",
        {:ok, declaring_child("bdoc_READING_LIST_IMPORT", ["done"])}
      )

      invoke =
        carrier_invoke("bdoc_READING_LIST_IMPORT", "done skipped error", %{"branch" => "north"})

      assert {:ok, [{:start_child, started, {:invoke, ^invoke}}]} = in_memory(invoke)
      assert started.params == %{"branch" => "north"}

      assert {:start_child, durable_started, {:invoke, ^invoke}} = durable(invoke)
      assert durable_started.params == %{"branch" => "north"}
    end

    test "an artifact whose interface declares no outcomes fits any block" do
      compiled = %Compiled{
        scxml: ~s(<scxml xmlns="http://www.w3.org/2005/07/scxml" version="1.0"/>),
        provenance: nil,
        record: nil
      }

      MapResolver.put("bdoc_R6", {:ok, compiled})

      assert {:start_child, _started, _origin} = durable(carrier_invoke("bdoc_R6", "done"))
    end
  end

  describe "a literal chart block's child is not judged" do
    # sabotage: had `fit/2` judge every child against the block's outcomes
    # from an absent carrier read as an empty set -> the literal child is
    # refused and this goes red (verified)
    test "with no carrier, a child declaring outcomes the block lacks still starts" do
      MapResolver.put(
        "bdoc_R7",
        {:ok, declaring_child("bdoc_R7", ["done", "needs_site_visit"])}
      )

      for params <- [%{}, :undefined, %{"branch" => "north"}] do
        invoke = HandlerCase.build_invoke(@type_string, src: "bdoc_R7", params: params)

        assert {:ok, [{:start_child, started, _origin}]} = in_memory(invoke)
        assert started.params == params

        assert {:start_child, durable_started, _origin} = durable(invoke)
        assert durable_started.params == params
      end
    end

    test "a live literal parent runs a child whose outcome it never declared, as before" do
      MapResolver.put("bdoc_CHILD", {:ok, RuntimeFixtures.child_document("needs_site_visit")})

      parent = RuntimeFixtures.parent_document(chart: "bdoc_CHILD", outcomes: ["done"])
      session = RuntimeFixtures.run(parent, MapResolver)

      try do
        # The undeclared outcome falls to the unconditioned arm, the first
        # declared outcome, exactly as a literal child did before.
        assert RuntimeFixtures.await_configuration(session, settled("done")) == settled("done")
      after
        Session.stop(session)
      end
    end
  end

  describe "a live chart_from session" do
    # sabotage: had `carried_outcomes/1` answer `:no_carrier` for every
    # payload -> the misfit child starts, the block settles on `done` by
    # the unconditioned arm and this goes red (verified)
    test "a misfit child is never started and the block settles on error" do
      MapResolver.put(
        "bdoc_CARD_READER_SETUP",
        {:ok, RuntimeFixtures.child_document("needs_site_visit")}
      )

      session = run(parent(), %{"onboarding" => %{"setup_document" => "bdoc_CARD_READER_SETUP"}})

      try do
        assert RuntimeFixtures.await_configuration(session, settled("error")) == settled("error")
      after
        Session.stop(session)
      end
    end

    test "a fitting child runs and the parent routes on its outcome" do
      MapResolver.put("bdoc_CATALOGUE_SYNC", {:ok, RuntimeFixtures.child_document("skipped")})

      session = run(parent(), %{"onboarding" => %{"setup_document" => "bdoc_CATALOGUE_SYNC"}})

      try do
        assert RuntimeFixtures.await_configuration(session, settled("skipped")) ==
                 settled("skipped")
      after
        Session.stop(session)
      end
    end
  end

  defp settled(outcome), do: MapSet.union(@root, MapSet.new(["s_blk_ROOT__o_#{outcome}"]))

  defp parent do
    root =
      Block.new("core.subchart",
        id: "blk_ROOT",
        config: %{"chart_from" => "onboarding.setup_document", "outcomes" => "done\nskipped"},
        slots: %{"on_error" => [Block.new("core.sequence", id: "blk_ON_error")]}
      )

    Document.new(root, id: "bdoc_ONBOARD")
  end

  defp run(document, datamodel) do
    {:ok, %Compiled{scxml: scxml}} =
      Compiler.compile(document, MapResolver.palette(), known_invoke_types: [@type_string])

    {:ok, machine} = Statifier.compile(scxml)

    {:ok, session} =
      Session.start_link(machine,
        invoke_handlers: Subchart.handlers(MapResolver),
        datamodel: datamodel
      )

    session
  end
end
