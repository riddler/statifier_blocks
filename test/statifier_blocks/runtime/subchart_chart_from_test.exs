defmodule StatifierBlocks.Runtime.SubchartChartFromTest do
  @moduledoc """
  The run-time half of `core.subchart`'s `chart_from` (ADR-0004's Amendment
  of 2026-11-19): the engine evaluates the emitted `srcexpr` when the
  invocation starts, the handlers resolve the string it yields exactly as
  they resolve a literal `src` (J5, J6), a value that is not a string is
  refused `unknown_document` without the resolver being called, and the
  reserved outcomes carrier is removed before the child starts (J2).

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

  defmodule RaisesIfCalledResolver do
    @moduledoc "Fails the test outright if `resolve_chart/2` is ever reached."

    use StatifierBlocks.Runtime.Subchart

    @impl true
    def resolve_chart(_document_id, _ctx),
      do: raise("resolve_chart/2 must not be called for a non-binary src")

    @impl true
    def palette, do: StatifierBlocks.Palette.core()
  end

  defp settled(outcome), do: MapSet.union(@root, MapSet.new(["s_blk_ROOT__o_#{outcome}"]))

  describe "a live session evaluates srcexpr and runs the child it names" do
    # sabotage: had `child_source/1` emit the path as a literal `src` ->
    # the resolver is asked for the id "onboarding.setup_document", answers
    # :error, the block settles on `error` and this goes red (verified)
    test "the evaluated string is resolved and the parent routes on the child's outcome" do
      MapResolver.put("bdoc_CATALOGUE_SYNC", {:ok, RuntimeFixtures.child_document("skipped")})

      session = run(parent(), %{"onboarding" => %{"setup_document" => "bdoc_CATALOGUE_SYNC"}})

      try do
        assert RuntimeFixtures.await_configuration(session, settled("skipped")) ==
                 settled("skipped")
      after
        Session.stop(session)
      end
    end

    test "an id the host does not resolve is refused unknown_document" do
      session = run(parent(), %{"onboarding" => %{"setup_document" => "bdoc_BRANCH_CLOSURE"}})

      try do
        assert RuntimeFixtures.await_configuration(session, settled("error")) == settled("error")
      after
        Session.stop(session)
      end
    end

    test "a path that holds a value that is not a string is refused unknown_document" do
      session = run(parent(), %{"onboarding" => %{"setup_document" => 42}})

      try do
        assert RuntimeFixtures.await_configuration(session, settled("error")) == settled("error")
      after
        Session.stop(session)
      end
    end
  end

  describe "Resolution's non-binary rule, unchanged for a srcexpr result" do
    # A regression guard over unchanged code: the clause predates `chart_from`,
    # and this pins it for the values a `srcexpr` can evaluate to.
    test "every non-string value is refused without the resolver being called" do
      for value <- [nil, :undefined, 42, %{"id" => "bdoc_X"}, ["bdoc_X"]] do
        invoke = HandlerCase.build_invoke(@type_string, src: value, invoke_id: "blk_SETUP")
        ctx = HandlerCase.build_ctx(@type_string, RaisesIfCalledResolver)

        assert {:ok, [{:raise, :platform, "error.communication.invoke.blk_SETUP", _origin, opts}]} =
                 Subchart.start(invoke, ctx, RaisesIfCalledResolver)

        assert opts[:data] == %{
                 "reason" => "unknown_document",
                 "detail" => %{"chart" => inspect(value)}
               }
      end
    end
  end

  describe "the outcomes carrier is removed before the child starts (J2)" do
    # sabotage: had `Resolution.child_invoke/2` keep the params as given ->
    # the carrier reaches the started payload and this goes red (verified)
    test "in-memory: the carrier is dropped and the author's params pass through" do
      MapResolver.put("bdoc_R1", {:ok, RuntimeFixtures.trivial_child("bdoc_R1")})

      params = %{@carrier => "done skipped error", "branch" => "north"}
      invoke = HandlerCase.build_invoke(@type_string, src: "bdoc_R1", params: params)
      ctx = HandlerCase.build_ctx(@type_string, MapResolver)

      assert {:ok, [{:start_child, started, {:invoke, ^invoke}}]} =
               Subchart.start(invoke, ctx, MapResolver)

      assert started.params == %{"branch" => "north"}
      assert {:ok, _machine} = Statifier.compile(started.content)
    end

    # sabotage: answered `%{}` rather than `:undefined` for a map the
    # carrier was the only entry of -> this goes red (verified)
    test "durable: a carrier that was the only param leaves the engine's no-params shape" do
      MapResolver.put("bdoc_R2", {:ok, RuntimeFixtures.trivial_child("bdoc_R2")})

      invoke =
        HandlerCase.build_invoke(@type_string,
          src: "bdoc_R2",
          params: %{@carrier => "done error"}
        )

      assert {:start_child, started, {:invoke, ^invoke}} =
               DurableSubchart.dispatch(
                 @type_string,
                 invoke.params,
                 %{invoke: invoke},
                 MapResolver
               )

      assert started.params == :undefined
    end

    test "a literal chart's params, which carry no carrier, are handed on unchanged" do
      MapResolver.put("bdoc_R3", {:ok, RuntimeFixtures.trivial_child("bdoc_R3")})

      for params <- [%{}, :undefined, %{"branch" => "north"}] do
        invoke = HandlerCase.build_invoke(@type_string, src: "bdoc_R3", params: params)
        ctx = HandlerCase.build_ctx(@type_string, MapResolver)

        assert {:ok, [{:start_child, started, _origin}]} =
                 Subchart.start(invoke, ctx, MapResolver)

        assert started.params == params

        assert {:start_child, durable, _origin} =
                 DurableSubchart.dispatch(@type_string, params, %{invoke: invoke}, MapResolver)

        assert durable.params == params
      end
    end
  end

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
