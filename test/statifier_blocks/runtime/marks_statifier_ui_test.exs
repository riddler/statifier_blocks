# statifier-ui is optional here, exactly as `phoenix_live_view` is, and the
# headless CI job resolves a tree without either. The `:liveview` exclusion
# keeps a test out of that RUN and not out of its COMPILE, so a file naming
# `StatifierUI` at compile time - as this one does, deliberately, to assert
# the real reads rather than a stand-in - needs the whole-file wrapper the
# LiveView-cased tests use, for the same reason and in the same shape.
if Code.ensure_loaded?(StatifierUI.Inspector) do
  defmodule StatifierBlocks.Runtime.MarksStatifierUITest do
    @moduledoc """
    `StatifierBlocks.Runtime.Marks` against statifier-ui's own reads, over a
    wire-format v1 stream of a chart this package compiled.

    The sibling `marks_test.exs` exercises every branch of the resolution
    with a stand-in. This file asserts the half a stand-in cannot: that
    statifier-ui really answers the shapes the module reads, and that a
    macrostep with no configuration of its own marks the blocks of the
    macrostep it was carried from.
    """

    use ExUnit.Case, async: false

    alias StatifierBlocks.{Block, Compiler, Document, Palette}
    alias StatifierBlocks.Runtime.Marks
    alias StatifierUI.Inspector
    alias StatifierUI.Live.State
    alias StatifierUI.Trace.{Manifest, Message}

    @session "sess_sb_marks"

    setup do
      # The real reads, whatever a sibling file left in application config:
      # the key is global, and this file is the one that asserts the default.
      Application.delete_env(:statifier_blocks, :trace_inspector_module)

      compiled = compile_parallel_document()
      {:ok, machine} = Statifier.compile(compiled.scxml)
      {:ok, manifest} = Manifest.build(machine, @session)

      indexes = state_indexes(manifest)

      settled = [
        manifest,
        stable(1, 1, [indexes["s_blk_L__waiting"], indexes["s_blk_R__waiting"]]),
        # A macrostep that stamped no configuration of its own: statifier-ui
        # draws the newest one at or below it, and says it was carried.
        logged(2, 2)
      ]

      {:ok, machine: machine, provenance: compiled.provenance, messages: settled}
    end

    # Sabotage: had `block_ids/2` answer the state ids rather than mapping
    # them through the provenance map -> the marks carried
    # `s_blk_L__waiting` and this went red (verified).
    test "a settled configuration marks exactly the blocks it is inside", context do
      %{machine: machine, provenance: provenance, messages: messages} = context

      marks = Marks.from_trace(read_model(machine, messages, {:macrostep, 1}), provenance)

      assert %{active: active, invoke: nil} = marks
      assert MapSet.equal?(active, MapSet.new(["blk_L", "blk_R"]))
    end

    # Sabotage: had `read_opts/1` drop `:selection` -> every point resolved
    # to the live tip instead of the selected macrostep, and the carried
    # macrostep stopped being a carried reading at all; this went red
    # (verified).
    test "a carried configuration marks what the macrostep it came from marks", context do
      %{machine: machine, provenance: provenance, messages: messages} = context

      # The premise: macrostep 2 stamped nothing, so statifier-ui carries
      # macrostep 1's configuration forward and says so.
      assert {:carried, 2, 1} =
               Inspector.resolution(messages, selection: {:macrostep, 2})

      carried = Marks.from_trace(read_model(machine, messages, {:macrostep, 2}), provenance)
      source = Marks.from_trace(read_model(machine, messages, {:macrostep, 1}), provenance)

      assert carried == source
      assert %{active: active} = carried
      assert MapSet.equal?(active, MapSet.new(["blk_L", "blk_R"]))
    end

    # Sabotage: had `read/4`'s refusal arm build an empty mark map -> a
    # stream with nothing in it started threading marks down the tree and
    # this went red (verified).
    test "an empty stream marks nothing", %{machine: machine, provenance: provenance} do
      assert Inspector.active_configuration_ids([]) == {:error, :no_manifest}
      assert Marks.from_trace(read_model(machine, [], :live), provenance) == nil
    end

    # Sabotage: had `from_trace/2` mark the late-attach case from the bare
    # indexes instead of refusing -> a canvas marked blocks resolved from
    # `"#2"`-shaped names, which name nothing, and this went red (verified).
    test "a late-attached stream, carrying no manifest, marks nothing", context do
      %{machine: machine, provenance: provenance, messages: messages} = context

      late_attach = Enum.reject(messages, &(&1.type == "session.start"))

      assert Marks.from_trace(read_model(machine, late_attach, :live), provenance) == nil
    end

    # Sabotage: had `invoke_mark/2` pass statifier-ui's `invoke_type` through
    # as the pair's second element -> the mark read
    # `{"blk_L", "myapp:authorize"}` and this went red (verified).
    test "a live invocation marks its block with no answer yet", context do
      %{machine: machine, provenance: provenance, messages: messages} = context

      indexes = state_indexes(hd(messages))

      invoking =
        messages ++
          [invoked(3, 2, "inv-1", "myapp:authorize", indexes["s_blk_L__waiting"])]

      assert {:ok, [{"s_blk_L__waiting", "myapp:authorize"}]} = Inspector.active_invokes(invoking)

      assert %{invoke: {"blk_L", nil}} =
               Marks.from_trace(read_model(machine, invoking, :live), provenance)
    end

    defp read_model(machine, messages, selection) do
      machine
      |> State.new(messages: messages)
      |> then(fn state ->
        case selection do
          :live -> state
          {:macrostep, n} -> State.select(state, n)
        end
      end)
    end

    defp stable(seq, macrostep, configuration) do
      %Message{
        type: "trace.macrostep_stable",
        session: @session,
        seq: seq,
        macrostep: macrostep,
        round: 0,
        payload: %{"configuration" => configuration}
      }
    end

    defp logged(seq, macrostep) do
      %Message{
        type: "effect.log",
        session: @session,
        seq: seq,
        macrostep: macrostep,
        round: 0,
        payload: %{"label" => "still working"}
      }
    end

    defp invoked(seq, macrostep, invoke_id, invoke_type, state_index) do
      %Message{
        type: "effect.invoke",
        session: @session,
        seq: seq,
        macrostep: macrostep,
        round: 0,
        payload: %{
          "invoke_id" => invoke_id,
          "invoke_type" => invoke_type,
          "state_index" => state_index
        }
      }
    end

    defp state_indexes(%Message{payload: %{"states" => states}}) do
      for %{"index" => index} = state <- states, id = state["id"], into: %{}, do: {id, index}
    end

    defp compile_parallel_document do
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
      compiled
    end
  end
end
