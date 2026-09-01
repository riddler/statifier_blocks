defmodule StatifierBlocks.Runtime.DurableSubchartTest do
  @moduledoc """
  Unit-level coverage of `StatifierBlocks.Runtime.DurableSubchart` against
  the shape of `StatifierPersistence.Driver`'s dispatch seam, without
  depending on that package: the context is a plain map here, exactly as
  it is there, and every answer this module gives is a plain tuple the
  driver pattern-matches. sb-2i04 deliberately adds no dependency edge -
  see the module's own "No dependency on statifier_persistence" section -
  so the end-to-end proof against a live driver belongs downstream, in the
  reference embedder that currently refuses with
  `{:error, {:durable_subchart_unsupported, type}}`.

  `async: false` because `StatifierBlocks.RuntimeFixtures.MapResolver`
  reads its answers out of `:persistent_term`, which is process-global.
  """

  use ExUnit.Case, async: false

  alias Statifier.Effect.Invoke
  alias Statifier.Testing.HandlerCase
  alias StatifierBlocks.{Block, Document, Palette}
  alias StatifierBlocks.Core.Subchart, as: SubchartBlock
  alias StatifierBlocks.Runtime.DurableSubchart
  alias StatifierBlocks.RuntimeFixtures

  alias StatifierBlocks.RuntimeFixtures.{
    CycleResolver,
    MapResolver,
    NonConformingResolver,
    UnknownResolver
  }

  @type_string SubchartBlock.invoke_type()

  defmodule UsingHost do
    @moduledoc """
    A host wired the `use` way: the macro is what defines `dispatch/3`
    here, so a test calling it proves the macro and not just `dispatch/4`.
    """

    use StatifierBlocks.Runtime.DurableSubchart

    @impl StatifierBlocks.Runtime.Subchart
    def resolve_chart(document_id, _ctx),
      do: {:ok, StatifierBlocks.RuntimeFixtures.trivial_child(document_id)}

    @impl StatifierBlocks.Runtime.Subchart
    def palette, do: StatifierBlocks.Palette.core()
  end

  defmodule RaisesIfCalledResolver do
    @moduledoc "Fails the test outright if `resolve_chart/2` is ever reached."

    use StatifierBlocks.Runtime.DurableSubchart

    @impl StatifierBlocks.Runtime.Subchart
    def resolve_chart(_document_id, _ctx),
      do: raise("resolve_chart/2 must not be called for a non-binary src")

    @impl StatifierBlocks.Runtime.Subchart
    def palette, do: Palette.core()
  end

  describe "invoke_type/0" do
    # Sabotage: hard-coded the string in DurableSubchart.invoke_type/0 so
    # it no longer read Core.Subchart.invoke_type/0, then changed the
    # literal -> the first assertion went red (verified).
    test "is the same one definition site the in-memory variant serves" do
      assert DurableSubchart.invoke_type() == SubchartBlock.invoke_type()
      assert DurableSubchart.invoke_type() == "statifier_blocks:subchart"
    end
  end

  describe "dispatch/4 with a resolvable document" do
    # Sabotage: had dispatch/4 answer {:start_child, invoke, {:invoke,
    # invoke}} with the payload unchanged instead of %{invoke | content:
    # scxml} -> `started.content` read nil and the compile assertion went
    # red (verified).
    test "answers {:start_child, resolved, {:invoke, invoke}} carrying the compiled child" do
      MapResolver.put("bdoc_D1", {:ok, RuntimeFixtures.trivial_child("bdoc_D1")})

      invoke = HandlerCase.build_invoke(@type_string, src: "bdoc_D1")

      assert {:start_child, started, {:invoke, ^invoke}} =
               DurableSubchart.dispatch(@type_string, invoke.params, context(invoke), MapResolver)

      assert started.invoke_id == invoke.invoke_id
      assert started.src == invoke.src
      assert started.params == invoke.params
      assert {:ok, _machine} = Statifier.compile(started.content)
    end

    # Sabotage: had dispatch/4 synthesise a fresh %Invoke{} for the second
    # element (invoke_id and type only, the pre-widening shape the sp
    # tests used) -> the equality assertion went red (verified).
    test "hands back the payload it was given, unchanged, as the second element" do
      MapResolver.put("bdoc_D2", {:ok, RuntimeFixtures.trivial_child("bdoc_D2")})

      invoke = HandlerCase.build_invoke(@type_string, src: "bdoc_D2", autoforward: true)

      assert {:start_child, _started, {:invoke, echoed}} =
               DurableSubchart.dispatch(@type_string, invoke.params, context(invoke), MapResolver)

      assert echoed == invoke
    end

    # Sabotage: made Resolution.resolve/3 read `src` off the ctx's
    # :invoke_id instead of the payload's :src -> the resolver was asked
    # for "inv_1", answered :error, and this went red (verified).
    test "reads the document id from context.invoke.src, the only place core.subchart puts it" do
      MapResolver.put("bdoc_SRC", {:ok, RuntimeFixtures.trivial_child("bdoc_SRC")})

      invoke = HandlerCase.build_invoke(@type_string, src: "bdoc_SRC")

      assert {:start_child, _started, _echo} =
               DurableSubchart.dispatch(@type_string, invoke.params, context(invoke), MapResolver)
    end

    # Sabotage: had resolve/3 recompile a %Compiled{} through
    # Compiler.compile/3 instead of using its .scxml as it stands -> the
    # compile raised on a struct rather than a document and this went red
    # (verified).
    test "uses a pre-compiled {:ok, %Compiled{}} exactly as it stands" do
      {:ok, compiled} =
        StatifierBlocks.Compiler.compile(
          RuntimeFixtures.trivial_child("bdoc_PRE"),
          Palette.core(),
          child_use: true
        )

      MapResolver.put("bdoc_PRE", {:ok, compiled})
      invoke = HandlerCase.build_invoke(@type_string, src: "bdoc_PRE")

      assert {:start_child, started, _echo} =
               DurableSubchart.dispatch(@type_string, invoke.params, context(invoke), MapResolver)

      assert started.content == compiled.scxml
    end
  end

  describe "dispatch/4 refusals - the three reasons this half raises" do
    # Sabotage: had the refusal arm answer {:error, reason} (a bare
    # string, st-ADR-0068's shape without the keyword list) -> the
    # keyword match went red (verified).
    test "an unresolvable document id is {:error, reason: \"unknown_document\", detail: ...}" do
      invoke = HandlerCase.build_invoke(@type_string, src: "bdoc_MISSING")

      assert {:error, failure} =
               DurableSubchart.dispatch(
                 @type_string,
                 invoke.params,
                 context(invoke),
                 UnknownResolver
               )

      assert Keyword.fetch!(failure, :reason) == "unknown_document"
      assert Keyword.fetch!(failure, :detail) == %{"chart" => "bdoc_MISSING"}
      refute Keyword.has_key?(failure, :attempts)
    end

    # Sabotage: dropped Resolution.resolve/3's non-binary-src clause so a
    # nil src reached the resolver -> RaisesIfCalledResolver raised and
    # this went red (verified).
    test "a non-binary src refuses unknown_document without reaching the resolver" do
      invoke = HandlerCase.build_invoke(@type_string, src: nil)

      assert {:error, failure} =
               DurableSubchart.dispatch(
                 @type_string,
                 invoke.params,
                 context(invoke),
                 RaisesIfCalledResolver
               )

      assert Keyword.fetch!(failure, :reason) == "unknown_document"
      assert Keyword.fetch!(failure, :detail) == %{"chart" => "nil"}
    end

    # Sabotage: folded the {:cycle, path} arm into the :error arm so it
    # answered unknown_document -> the reason assertion went red
    # (verified).
    test "a {:cycle, path} answer is cycle_refused, carrying the path" do
      invoke = HandlerCase.build_invoke(@type_string, src: "bdoc_A")

      assert {:error, failure} =
               DurableSubchart.dispatch(
                 @type_string,
                 invoke.params,
                 context(invoke),
                 CycleResolver
               )

      assert Keyword.fetch!(failure, :reason) == "cycle_refused"

      assert Keyword.fetch!(failure, :detail) == %{
               "chart" => "bdoc_A",
               "cycle" => ~w(bdoc_A bdoc_B)
             }
    end

    # Sabotage: had compile_child/4 answer {:ok, ""} on {:error, findings}
    # instead of refusing -> a start_child with empty content came back
    # and this went red (verified).
    test "a child that does not compile is child_compile_findings, carrying the findings" do
      MapResolver.put("bdoc_SELF", {:ok, RuntimeFixtures.self_referencing_child("bdoc_SELF")})

      invoke = HandlerCase.build_invoke(@type_string, src: "bdoc_SELF")

      assert {:error, failure} =
               DurableSubchart.dispatch(@type_string, invoke.params, context(invoke), MapResolver)

      assert Keyword.fetch!(failure, :reason) == "child_compile_findings"
      detail = Keyword.fetch!(failure, :detail)
      assert detail["chart"] == "bdoc_SELF"
      assert [%{"code" => code, "block_id" => "blk_SELF"} | _] = detail["findings"]
      assert is_binary(code)
    end

    # Sabotage: replaced raise_non_conforming/2 with a refusal of
    # "unknown_document" -> the assert_raise went red (verified).
    test "a resolver answer outside the four raises ArgumentError naming the module" do
      invoke = HandlerCase.build_invoke(@type_string, src: "bdoc_ANY")

      assert_raise ArgumentError,
                   ~r/NonConformingResolver\.resolve_chart\/2 returned :banana/,
                   fn ->
                     DurableSubchart.dispatch(
                       @type_string,
                       invoke.params,
                       context(invoke),
                       NonConformingResolver
                     )
                   end
    end
  end

  describe "wiring" do
    # Sabotage: had dispatch_fun/1 return a two-arity fun (the shape a
    # host would need if `type` were not passed) -> the arity assertion
    # went red (verified).
    test "dispatch_fun/1 builds the three-arity fun the driver's :dispatch option takes" do
      MapResolver.put("bdoc_FUN", {:ok, RuntimeFixtures.trivial_child("bdoc_FUN")})

      dispatch = DurableSubchart.dispatch_fun(MapResolver)
      assert is_function(dispatch, 3)

      invoke = HandlerCase.build_invoke(@type_string, src: "bdoc_FUN")

      assert {:start_child, _started, _echo} =
               dispatch.(@type_string, invoke.params, context(invoke))
    end

    # Sabotage: removed ensure_type!/1's raise so any type was served ->
    # the assert_raise went red (verified).
    test "a foreign invoke type raises rather than being served" do
      invoke = HandlerCase.build_invoke("myapp:authorize", src: "bdoc_FUN")

      assert_raise ArgumentError, ~r/serves "statifier_blocks:subchart"/, fn ->
        DurableSubchart.dispatch("myapp:authorize", invoke.params, context(invoke), MapResolver)
      end
    end

    # ADR-0008 decision 4: a durable cancel is statifier_persistence's,
    # and this package "should offer no callback that looks like it does".
    # Sabotage: added a `cancel/2` to the __using__ quote delegating to the
    # in-memory module -> the first refute went red (verified).
    test "the host gains dispatch/3 and no durable look-alike of cancel or forward" do
      assert function_exported?(UsingHost, :dispatch, 3)

      refute function_exported?(UsingHost, :cancel, 2)
      refute function_exported?(UsingHost, :forward, 3)
      refute function_exported?(DurableSubchart, :cancel, 2)
      refute function_exported?(DurableSubchart, :forward, 3)
    end

    # Sabotage: dropped payload!/1's raising clause so a context without
    # :invoke fell through to a FunctionClauseError -> the assert_raise on
    # ArgumentError went red (verified).
    test "a dispatch context without :invoke raises, naming the seam it needs" do
      pre_widening = %{run_id: "run_1", content_hash: "hash", invoke_id: "inv_1"}

      assert_raise ArgumentError, ~r/dispatch context's :invoke key/, fn ->
        DurableSubchart.dispatch(@type_string, %{}, pre_widening, MapResolver)
      end
    end

    # Sabotage: had __using__ define dispatch/3 delegating to the
    # in-memory Subchart.start/3 instead -> the returned tuple was
    # {:ok, [instruction]} and this went red (verified).
    test "`use` defines dispatch/3 on the host module itself" do
      invoke = HandlerCase.build_invoke(@type_string, src: "bdoc_USE")

      assert {:start_child, started, {:invoke, ^invoke}} =
               UsingHost.dispatch(@type_string, invoke.params, context(invoke))

      assert {:ok, _machine} = Statifier.compile(started.content)
    end
  end

  describe "nesting (ADR-0008 decision 6)" do
    # Sabotage: restored the unconditional
    # `known_invoke_types: Map.keys(ctx.invoke_handlers)` in
    # Resolution.compile_child/4 -> a durable dispatch context has no such
    # key and this raised KeyError (verified red). The other direction -
    # passing an empty set - is deliberately NOT pinned by a test: the
    # lint is warning-only, so it changes no answer this module gives,
    # and the reason to omit it is honesty about what is known rather
    # than an observable behavior.
    test "a child that itself invokes a durable subchart compiles clean, with no false lint" do
      MapResolver.put("bdoc_NEST", {:ok, nesting_child("bdoc_NEST")})

      invoke = HandlerCase.build_invoke(@type_string, src: "bdoc_NEST")

      assert {:start_child, started, _echo} =
               DurableSubchart.dispatch(@type_string, invoke.params, context(invoke), MapResolver)

      assert started.content =~ ~s(type="statifier_blocks:subchart")
      assert {:ok, _machine} = Statifier.compile(started.content)
    end
  end

  # The dispatch context `StatifierPersistence.Driver` builds, as a plain
  # map: the executor's own two keys plus this invocation's id and the
  # whole payload being dispatched. Written out here rather than imported
  # because sb-2i04 adds no dependency on that package.
  @spec context(Invoke.t()) :: map()
  defp context(%Invoke{} = invoke) do
    %{
      run_id: "run_1",
      content_hash: "sha256:parent",
      invoke_id: invoke.invoke_id,
      invoke: invoke
    }
  end

  # A child document whose root is itself a `core.subchart` naming a
  # different document - the nested durable subchart ADR-0008 decision 6
  # allows from day one.
  @spec nesting_child(String.t()) :: Document.t()
  defp nesting_child(id) do
    root = Block.new("core.subchart", id: "blk_NEST", config: %{"chart" => "bdoc_GRANDCHILD"})
    Document.new(root, id: id)
  end
end
