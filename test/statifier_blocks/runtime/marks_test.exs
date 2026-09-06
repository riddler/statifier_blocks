defmodule StatifierBlocks.Runtime.MarksTest do
  @moduledoc """
  Headless unit coverage of `StatifierBlocks.Runtime.Marks`: the resolution
  half of the seam, against a real compiled provenance map and a stand-in
  for statifier-ui's reads.

  `async: false`, because the stand-in is installed in application config and
  that is global: the sibling file below reads the same key and must see the
  real package there. **Not** tagged `:liveview`, not
  `use StatifierBlocks.EditorLiveCase`, and - the point of this file's
  placement - naming no `StatifierUI` module at compile time either. Both
  optional packages are absent from the headless tree, and this module is
  what proves the mapping runs there.

  The stand-in is the whole reason the reads are dispatched dynamically: a
  stream is modelled here as a keyword list carrying the two answers, so
  every branch of the resolution is exercised with statifier-ui absent *and*
  present. The other side of the seam - that statifier-ui really answers
  those shapes, and what it answers at a carried macrostep - is asserted
  against the real package in `marks_statifier_ui_test.exs`.
  """

  use ExUnit.Case, async: false

  alias StatifierBlocks.{Block, Compiler, Document, Palette}
  alias StatifierBlocks.Runtime.Marks

  defmodule StubInspector do
    @moduledoc """
    Test-only stand-in for `StatifierUI.Inspector`'s two reads.

    The "stream" is a keyword list holding the answers directly, so a test
    names the configuration it wants resolved rather than building a wire
    stream to imply it. A list carrying neither answer is the empty stream:
    the read refuses with `{:error, :no_manifest}`, which is what
    statifier-ui answers for a stream with no `session.start` in it.
    """

    def active_configuration_ids(messages, opts) do
      send(self(), {:configuration_read, opts})
      Keyword.get(messages, :configuration, {:error, :no_manifest})
    end

    def active_invokes(messages, opts) do
      send(self(), {:invokes_read, opts})
      Keyword.get(messages, :invokes, {:ok, []})
    end
  end

  setup do
    Application.put_env(:statifier_blocks, :trace_inspector_module, StubInspector)
    on_exit(fn -> Application.delete_env(:statifier_blocks, :trace_inspector_module) end)

    {:ok, provenance: provenance()}
  end

  describe "the active set" do
    # Sabotage: had `block_ids/2` answer `MapSet.new(state_ids)` instead of
    # mapping through `Provenance.owners_of_states/2` -> the marks carried
    # the two generated state ids and this went red (verified).
    test "a configuration owned by two blocks marks exactly those two block ids", %{
      provenance: provenance
    } do
      state = trace(configuration: {:ok, ["s_blk_L__waiting", "s_blk_R__waiting"]})

      assert %{active: active, invoke: nil} = Marks.from_trace(state, provenance)
      assert MapSet.equal?(active, MapSet.new(["blk_L", "blk_R"]))
    end

    # Sabotage: had `block_ids/2` keep every owner as a list rather than a
    # `MapSet` -> the canvas's membership question got a list and this went
    # red on the `MapSet.equal?` (verified).
    test "two states of one block are one marked block", %{provenance: provenance} do
      state = trace(configuration: {:ok, ["s_blk_L", "s_blk_L__waiting"]})

      assert %{active: active} = Marks.from_trace(state, provenance)
      assert MapSet.equal?(active, MapSet.new(["blk_L"]))
    end

    # Sabotage: had `block_ids/2` raise on an unowned id (`Enum.map` over
    # `owner_of_state/2` without the drop) -> this went red with a
    # MatchError instead of marking the one block it owns (verified).
    test "a state id from another chart is dropped, not raised on", %{provenance: provenance} do
      state = trace(configuration: {:ok, ["s_blk_L__waiting", "s_from_another_chart"]})

      assert %{active: active} = Marks.from_trace(state, provenance)
      assert MapSet.equal?(active, MapSet.new(["blk_L"]))
    end
  end

  describe "the invoke mark" do
    # Sabotage: had `invoke_mark/2` put statifier-ui's `invoke_type` in the
    # pair's second element -> the mark read `{"blk_L", "myapp:authorize"}`
    # and this went red (verified). The canvas's second element is how a
    # call came back, and a live invocation has not come back.
    test "a live invocation marks its block with no answer yet", %{provenance: provenance} do
      state =
        trace(
          configuration: {:ok, ["s_blk_L__waiting"]},
          invokes: {:ok, [{"s_blk_L__waiting", "myapp:authorize"}]}
        )

      assert %{invoke: {"blk_L", nil}} = Marks.from_trace(state, provenance)
    end

    # Sabotage: had `invoke_mark/2` answer the whole list rather than the
    # first owned invocation -> the mark stopped matching the canvas's
    # single-valued shape and this went red (verified).
    test "the first live invocation this map owns is the mark", %{provenance: provenance} do
      state =
        trace(
          configuration: {:ok, ["s_blk_L__waiting"]},
          invokes: {:ok, [{"s_blk_L__waiting", "myapp:authorize"}, {"s_blk_R__waiting", nil}]}
        )

      assert %{invoke: {"blk_L", nil}} = Marks.from_trace(state, provenance)
    end

    # Sabotage: had the `:error` arm of `invoke_mark/2`'s `owner_of_state/2`
    # answer `{state_id, nil}` -> a state from another chart marked a block
    # id that is not a block id at all, and this went red (verified).
    test "an invocation on a state from another chart marks no block", %{provenance: provenance} do
      state =
        trace(
          configuration: {:ok, ["s_blk_L__waiting"]},
          invokes: {:ok, [{"s_from_another_chart", "myapp:authorize"}]}
        )

      assert %{invoke: nil} = Marks.from_trace(state, provenance)
    end

    # Sabotage: dropped `invoke_mark/2`'s catch-all clause -> the refusal
    # raised a FunctionClauseError instead of marking no call, and this went
    # red (verified).
    test "a refused invoke read marks no call rather than raising", %{provenance: provenance} do
      state =
        trace(configuration: {:ok, ["s_blk_L__waiting"]}, invokes: {:error, :no_manifest})

      assert %{active: active, invoke: nil} = Marks.from_trace(state, provenance)
      assert MapSet.equal?(active, MapSet.new(["blk_L"]))
    end
  end

  describe "nothing to mark" do
    # Sabotage: had `read/4`'s refusal arm answer `%{active: MapSet.new(),
    # invoke: nil}` instead of `nil` -> an empty stream started threading an
    # empty mark set down the tree and this went red (verified).
    test "an empty stream marks nothing", %{provenance: provenance} do
      assert Marks.from_trace(trace([]), provenance) == nil
    end

    # Sabotage: had `marks/2` always build the map -> a configuration inside
    # no block of this document answered an empty mark set rather than the
    # `nil` the editor threads for "no run over this document", and this
    # went red (verified).
    test "a configuration owning no block and no live call marks nothing", %{
      provenance: provenance
    } do
      state = trace(configuration: {:ok, ["s_from_another_chart"]})

      assert Marks.from_trace(state, provenance) == nil
    end

    # Sabotage: had `inspector_module/0` answer the configured module
    # without the `Code.ensure_loaded?`/`function_exported?` checks -> the
    # dynamic call raised UndefinedFunctionError in a tree without
    # statifier-ui, which is the whole failure the guard exists to prevent,
    # and this went red (verified).
    test "without a resolvable read, nothing is marked", %{provenance: provenance} do
      Application.put_env(
        :statifier_blocks,
        :trace_inspector_module,
        StatifierBlocks.Runtime.MarksTest.NoSuchInspector
      )

      state = trace(configuration: {:ok, ["s_blk_L__waiting"]})

      assert Marks.from_trace(state, provenance) == nil
    end

    # Sabotage: dropped `from_trace/2`'s catch-all clause -> a host holding
    # a run in a shape this module does not recognise raised inside a
    # render instead of marking nothing, and this went red (verified).
    test "a read model of an unrecognised shape marks nothing", %{provenance: provenance} do
      assert Marks.from_trace(%{}, provenance) == nil
      assert Marks.from_trace(nil, provenance) == nil
      assert Marks.from_trace(%{messages: :not_a_list}, provenance) == nil
    end
  end

  describe "the options the reads are given" do
    # Sabotage: had `read_opts/1` hard-code `selection: :live` -> the
    # scrubber's selected macrostep stopped reaching statifier-ui, every
    # point resolved to the live tip, and this went red (verified).
    test "the read model's selection and initial configuration reach both reads", %{
      provenance: provenance
    } do
      state = %{
        messages: [configuration: {:ok, ["s_blk_L__waiting"]}],
        selection: {:macrostep, 7},
        initial_configuration: [0, 1]
      }

      Marks.from_trace(state, provenance)

      assert_received {:configuration_read, opts}
      assert opts[:selection] == {:macrostep, 7}
      assert opts[:initial_configuration] == [0, 1]

      assert_received {:invokes_read, ^opts}
    end

    # Sabotage: had `read_opts/1` fetch the fields with `Map.fetch!/2` ->
    # a bare map carrying only `messages` raised instead of defaulting, and
    # this went red (verified).
    test "a read model carrying only messages defaults to the live tip", %{
      provenance: provenance
    } do
      Marks.from_trace(%{messages: [configuration: {:ok, ["s_blk_L__waiting"]}]}, provenance)

      assert_received {:configuration_read, opts}
      assert opts[:selection] == :live
      assert opts[:initial_configuration] == []
    end
  end

  defp trace(messages), do: %{messages: messages, selection: :live, initial_configuration: []}

  # Two `core.wait` leaves in the two lanes of a `core.parallel`: a document
  # whose settled configuration really is inside two different blocks.
  defp provenance do
    root =
      Block.new("core.parallel",
        id: "blk_PAR",
        config: %{"lanes" => ["left", "right"]},
        slots: %{
          "lane_left" => [Block.new("core.wait", id: "blk_L", config: %{"duration" => "PT1S"})],
          "lane_right" => [Block.new("core.wait", id: "blk_R", config: %{"duration" => "PT2S"})]
        }
      )

    {:ok, compiled} = Compiler.compile(Document.new(root, id: "bdoc_MARKS"), Palette.core())
    compiled.provenance
  end
end
