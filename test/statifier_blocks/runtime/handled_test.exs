defmodule StatifierBlocks.Runtime.HandledTest do
  @moduledoc """
  `StatifierBlocks.Runtime.Handled` against a real compiled provenance map and
  hand-built wire-format messages.

  The messages are plain maps rather than `StatifierUI.Trace.Message` structs,
  and that is the point of this file's placement: statifier-ui is absent from
  the headless tree, the module under test names none of it, and a map
  carrying `type`, `macrostep` and `payload` is what its own pattern matches.
  Building them here rather than driving a session is also what makes every
  refusal reachable - a manifest with a transition naming a state that is not
  in its own table is not a stream any engine produces, and it is exactly the
  shape a chart revision the provenance map does not describe would arrive as.

  The end of the join - that statifier really stamps these messages and that
  the source state resolves to the block an author would expect - is asserted
  against a real run in the Run pane's own test.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{Block, Compiled, Compiler, Document, Palette}
  alias StatifierBlocks.Runtime.Handled

  setup do
    document =
      Document.new(
        Block.new("core.sequence",
          id: "blk_card_flow",
          slots: %{
            "body" => [
              Block.new("core.await", id: "blk_card_open", config: %{"event" => "card.captured"}),
              Block.new("core.await", id: "blk_card_settle", config: %{"event" => "card.settled"})
            ]
          }
        ),
        id: "bdoc_card_run"
      )

    {:ok, %Compiled{provenance: provenance}} = Compiler.compile(document, Palette.core())

    {:ok, provenance: provenance}
  end

  # The manifest names two transitions: t_index 0 leaves the block the run is
  # waiting in, t_index 1 leaves a state no block owns.
  defp manifest do
    %{
      type: "session.start",
      macrostep: nil,
      payload: %{
        "version" => 1,
        "states" => [
          %{"index" => 0, "kind" => "scxml"},
          %{"index" => 1, "kind" => "state", "id" => "s_blk_card_open__waiting"},
          %{"index" => 2, "kind" => "state", "id" => "s_not_from_this_document"},
          %{"index" => 3, "kind" => "state"}
        ],
        "transitions" => [
          %{"t_index" => 0, "source" => 1, "targets" => [], "events" => []},
          %{"t_index" => 1, "source" => 2, "targets" => [], "events" => []},
          %{"t_index" => 2, "source" => 3, "targets" => [], "events" => []},
          %{"t_index" => 3, "source" => 99, "targets" => [], "events" => []}
        ]
      }
    }
  end

  defp selected(macrostep, t_indexes) do
    %{
      type: "trace.transitions_selected",
      macrostep: macrostep,
      payload: %{"t_indexes" => t_indexes}
    }
  end

  defp stream(messages), do: %{messages: [manifest() | messages], selection: :live}

  describe "the block a macrostep was handled by" do
    # Sabotage: had `source_of/2` answer the transition's first `targets`
    # entry rather than its `source` - the answer became the block the run
    # moved INTO and this went red naming it (verified).
    test "is the one owning the source state of the transition it selected", %{
      provenance: provenance
    } do
      state = stream([selected(2, [0])])

      assert Handled.block(state, 2, provenance) == {:ok, "blk_card_open"}
    end

    # A macrostep holds several rounds and only the first that selected
    # anything is the one the author's event fired; everything below it is the
    # cascade that transition started.
    #
    # Sabotage: had `selected_transition/2` take the LAST non-empty selection
    # rather than the first - the answer became the internal round's
    # transition, which owns no block here, and this went red (verified).
    test "comes from the first round that selected anything", %{provenance: provenance} do
      state = stream([selected(2, []), selected(2, [0]), selected(2, [2])])

      assert Handled.block(state, 2, provenance) == {:ok, "blk_card_open"}
    end

    # Sabotage: dropped the `macrostep: ^macrostep` pin from the find clause -
    # macrostep 1's empty rounds stopped hiding macrostep 2's selection and
    # this went red with an answer for a step that handled nothing (verified).
    test "is nothing for a macrostep whose every round selected nothing", %{
      provenance: provenance
    } do
      state = stream([selected(1, []), selected(1, []), selected(2, [0])])

      assert Handled.block(state, 1, provenance) == :error
    end
  end

  describe "the refusals" do
    # The manifest is found by its TYPE, and the impostor here is what makes
    # that assertable: a runtime message carrying tables that would resolve
    # perfectly well if anything read them. A stream with no `session.start`
    # is the late-attach case, and it answers nothing however much of the
    # shape a later message happens to have.
    #
    # Sabotage: had `manifest/1` take the first message carrying a payload
    # rather than the first `session.start` - the impostor's tables resolved
    # and this went red with `{:ok, "blk_card_open"}` (verified).
    test "a stream with no manifest answers nothing", %{provenance: provenance} do
      impostor = %{
        type: "trace.transitions_selected",
        macrostep: 2,
        payload: %{
          "t_indexes" => [0],
          "states" => [%{"index" => 1, "id" => "s_blk_card_open__waiting"}],
          "transitions" => [%{"t_index" => 0, "source" => 1}]
        }
      }

      assert Handled.block(%{messages: [impostor], selection: :live}, 2, provenance) == :error
    end

    test "a state this provenance map does not own answers nothing", %{provenance: provenance} do
      assert Handled.block(stream([selected(2, [1])]), 2, provenance) == :error
    end

    test "an anonymous source state answers nothing", %{provenance: provenance} do
      assert Handled.block(stream([selected(2, [2])]), 2, provenance) == :error
    end

    test "a source index the manifest does not carry answers nothing", %{provenance: provenance} do
      assert Handled.block(stream([selected(2, [3])]), 2, provenance) == :error
    end

    test "a transition number the manifest does not carry answers nothing", %{
      provenance: provenance
    } do
      assert Handled.block(stream([selected(2, [77])]), 2, provenance) == :error
    end

    # A host holds a run in whatever shape its own runtime produced, and the
    # editor calls this on every log click.
    #
    # Sabotage: removed the catch-all `block/3` clause - the bare map raised a
    # `FunctionClauseError` inside the editor's handler instead of declining,
    # and this went red as an exit (verified).
    test "a shape that is not a read model answers nothing", %{provenance: provenance} do
      assert Handled.block(%{}, 2, provenance) == :error
      assert Handled.block(%{messages: "not a list"}, 2, provenance) == :error
    end
  end
end
