defmodule StatifierBlocks.Runtime.SubchartTest do
  @moduledoc """
  Unit-level coverage of `StatifierBlocks.Runtime.Subchart`'s callbacks in
  isolation: no `Statifier.Session`, no child ever actually started.
  Session-level integration (a real session, real routing, the cancel and
  autoforward lifecycle) is Phase 2/3's job; this file is Phase 1's.

  `async: false` because `StatifierBlocks.RuntimeFixtures.MapResolver`
  reads its answers out of `:persistent_term`, which is process-global.
  """

  use ExUnit.Case, async: false

  alias Statifier.Testing.HandlerCase
  alias StatifierBlocks.Core.Subchart, as: SubchartBlock

  alias StatifierBlocks.{Compiler, Palette}
  alias StatifierBlocks.Runtime.Subchart
  alias StatifierBlocks.RuntimeFixtures

  alias StatifierBlocks.RuntimeFixtures.{
    CycleResolver,
    MapResolver,
    NonConformingResolver,
    UnknownResolver
  }

  @type_string SubchartBlock.invoke_type()

  defmodule RaisesIfCalledResolver do
    @moduledoc """
    Proves the non-binary-`src` totality rule short-circuits before the
    resolver is ever reached: `resolve_chart/2` fails the test outright if
    it is invoked.
    """

    use StatifierBlocks.Runtime.Subchart

    @impl true
    def resolve_chart(_document_id, _ctx),
      do: raise("resolve_chart/2 must not be called for a non-binary src")

    @impl true
    def palette, do: Palette.core()
  end

  describe "handlers/1" do
    # Sabotage: hard-coded the map's key as a literal string that drifted
    # from Core.Subchart.invoke_type/0 -> the second assertion caught the
    # drift and went red (verified).
    test "builds %{type => module}, keyed by StatifierBlocks.Core.Subchart.invoke_type/0" do
      assert Subchart.handlers(Kernel) == %{SubchartBlock.invoke_type() => Kernel}
      assert @type_string == "statifier_blocks:subchart"
    end
  end

  describe "start/2 with {:ok, %Document{}}" do
    # Sabotage: had start/2 pass the original `invoke` through unchanged
    # instead of `%{invoke | content: scxml}` -> `started.content` read
    # nil instead of the compiled child's scxml, and this went red
    # (verified).
    test "plans exactly one {:start_child, invoke, {:invoke, invoke}} carrying the compiled child" do
      MapResolver.put("bdoc_OK1", {:ok, RuntimeFixtures.trivial_child("bdoc_OK1")})

      invoke = HandlerCase.build_invoke(@type_string, src: "bdoc_OK1")
      ctx = HandlerCase.build_ctx(@type_string, MapResolver)

      assert {:ok, [{:start_child, started, {:invoke, ^invoke}}]} =
               Subchart.start(invoke, ctx, MapResolver)

      assert started.invoke_id == invoke.invoke_id
      assert started.src == invoke.src

      assert started.content =~
               ~s(<final id="s_blk_SEQ__child_done"><donedata>) <>
                 ~s(<param expr="'done'" name="outcome"/></donedata></final>)

      assert {:ok, _machine} = Statifier.compile(started.content)
    end
  end

  describe "start/2 with {:ok, %Compiled{}}" do
    # Sabotage: had start/2 pass the original `invoke` through unchanged
    # instead of `%{invoke | content: scxml}` -> `started.content` read
    # nil instead of the pre-compiled `.scxml`, and this went red
    # (verified).
    test "uses .scxml verbatim, with no recompile" do
      {:ok, compiled} =
        Compiler.compile(RuntimeFixtures.trivial_child("bdoc_PRE"), Palette.core(),
          child_use: true
        )

      MapResolver.put("bdoc_PRE", {:ok, compiled})

      invoke = HandlerCase.build_invoke(@type_string, src: "bdoc_PRE")
      ctx = HandlerCase.build_ctx(@type_string, MapResolver)

      assert {:ok, [{:start_child, started, {:invoke, ^invoke}}]} =
               Subchart.start(invoke, ctx, MapResolver)

      assert started.content == compiled.scxml
    end
  end

  describe "start/2 with :error" do
    test "refuses unknown_document, with no attempts key" do
      MapResolver.put("bdoc_MISSING", :error)

      invoke = HandlerCase.build_invoke(@type_string, src: "bdoc_MISSING", invoke_id: "inv_7")
      ctx = HandlerCase.build_ctx(@type_string, MapResolver)

      assert {:ok, [instruction]} = Subchart.start(invoke, ctx, MapResolver)

      assert {:raise, :platform, "error.communication.invoke.inv_7", {:invoke, 0, 0},
              [data: data]} = instruction

      assert data["reason"] == "unknown_document"
      refute Map.has_key?(data, "attempts")
    end
  end

  describe "start/2 with {:cycle, path}" do
    test "refuses cycle_refused, with the path in detail" do
      invoke = HandlerCase.build_invoke(@type_string, src: "bdoc_ANY")
      ctx = HandlerCase.build_ctx(@type_string, CycleResolver)

      assert {:ok, [{:raise, :platform, _name, _origin, [data: data]}]} =
               Subchart.start(invoke, ctx, CycleResolver)

      assert data["reason"] == "cycle_refused"
      assert data["detail"]["cycle"] == ["bdoc_A", "bdoc_B"]
    end
  end

  describe "start/2 with a document that does not compile" do
    # Sabotage: fed the raw findings straight into `detail` instead of
    # reducing them through finding_detail/1 -> the map instead lost the
    # data:%{...} JSON-shape assertion below (a raw %Finding{} is not a
    # map with string keys the way the test expects) and went red
    # (verified).
    test "refuses child_compile_findings, with findings reduced to string-keyed maps" do
      MapResolver.put("bdoc_BAD", {:ok, RuntimeFixtures.self_referencing_child("bdoc_BAD")})

      invoke = HandlerCase.build_invoke(@type_string, src: "bdoc_BAD")
      ctx = HandlerCase.build_ctx(@type_string, MapResolver)

      assert {:ok, [{:raise, :platform, _name, _origin, [data: data]}]} =
               Subchart.start(invoke, ctx, MapResolver)

      assert data["reason"] == "child_compile_findings"
      assert [%{"code" => code, "message" => message} | _] = data["detail"]["findings"]
      assert is_binary(code)
      assert is_binary(message)
    end
  end

  describe "start/2 with a non-binary src" do
    test "refuses unknown_document without ever calling the resolver" do
      invoke = HandlerCase.build_invoke(@type_string, src: nil)
      ctx = HandlerCase.build_ctx(@type_string, RaisesIfCalledResolver)

      assert {:ok, [{:raise, :platform, _name, _origin, [data: data]}]} =
               Subchart.start(invoke, ctx, RaisesIfCalledResolver)

      assert data["reason"] == "unknown_document"
    end
  end

  describe "start/2 with a non-conforming resolver return" do
    test "raises ArgumentError naming the module" do
      invoke = HandlerCase.build_invoke(@type_string, src: "bdoc_ANY")
      ctx = HandlerCase.build_ctx(@type_string, NonConformingResolver)

      assert_raise ArgumentError, ~r/NonConformingResolver/, fn ->
        Subchart.start(invoke, ctx, NonConformingResolver)
      end
    end
  end

  describe "the child compile is linted against the session's own registered set" do
    # Sabotage: made compile_child/4 treat any non-empty `warnings` list on
    # a successful compile as a `child_compile_findings` refusal -> the
    # unregistered-type warning (ADR-0004 decision 8's own lint) turned
    # into a refusal instead of a successful {:start_child, _, _}, and
    # this went red (verified).
    test "a child naming an unregistered invoke type still compiles, as a warning" do
      MapResolver.put("bdoc_WARN", {:ok, RuntimeFixtures.unregistered_invoke_child("bdoc_WARN")})

      invoke = HandlerCase.build_invoke(@type_string, src: "bdoc_WARN")
      ctx = HandlerCase.build_ctx(@type_string, MapResolver)

      assert {:ok, [{:start_child, _started, {:invoke, ^invoke}}]} =
               Subchart.start(invoke, ctx, MapResolver)
    end
  end

  describe "cancel/2 and forward/3" do
    # Sabotage: had cancel/2 return {:ok, []} instead of the built-in
    # {:stop_child, invoke_id} instruction -> this went red (verified).
    test "return the engine's built-in instructions" do
      ctx = HandlerCase.build_ctx(@type_string, UnknownResolver)
      event = HandlerCase.build_event()

      assert Subchart.cancel("inv_9", ctx) == {:ok, [{:stop_child, "inv_9"}]}
      assert Subchart.forward("inv_9", event, ctx) == {:ok, [{:forward, "inv_9", event}]}
    end
  end
end
