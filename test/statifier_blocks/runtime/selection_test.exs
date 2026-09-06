defmodule StatifierBlocks.Runtime.SelectionTest do
  @moduledoc """
  `StatifierBlocks.Runtime.Selection` with a stand-in for statifier-ui's two
  scrubber reads.

  `async: false`, because the stand-in is installed in application config and
  the key is global - it is the same `:trace_inspector_module` key
  `StatifierBlocks.Runtime.Marks` resolves, which is itself worth asserting:
  one key, one module, two readers, and no way for a scrubber and a set of
  marks to end up reading different packages.

  Naming no `StatifierUI` module at compile time, so this runs in the headless
  tree. That statifier-ui really decides where Prev lands, and that the run's
  marks follow it, is asserted against the real package in the Run pane's own
  test.
  """

  use ExUnit.Case, async: false

  alias StatifierBlocks.Runtime.Selection

  defmodule StubInspector do
    @moduledoc """
    Test-only stand-in for `StatifierUI.Inspector`'s `points/1` and `step/3`.

    `step/3` records what it was asked and answers the move as a macrostep,
    so a test can assert that the current selection and the stream's points
    both reached it - which is the whole of what this module delegates.
    """

    def points(messages), do: Enum.map(messages, &%{macrostep: &1})

    def step(selection, points, move) do
      send(self(), {:stepped, selection, points, move})
      {:macrostep, length(points)}
    end
  end

  defmodule NoInspector do
    @moduledoc "A module with neither read: the absent-package branch."
  end

  setup do
    Application.put_env(:statifier_blocks, :trace_inspector_module, StubInspector)
    on_exit(fn -> Application.delete_env(:statifier_blocks, :trace_inspector_module) end)

    {:ok, state: %{messages: [1, 2, 3], selection: :live}}
  end

  describe "scrubbing" do
    # Sabotage: had `move_selection/4` pass `:live` rather than the state's
    # own selection - a second Prev asked the same question as the first and
    # the scrubber stopped moving past the newest point (verified).
    test "asks statifier-ui where the move lands, from where the view is", %{state: state} do
      moved = Selection.scrub(%{state | selection: {:macrostep, 2}}, :prev)

      assert moved.selection == {:macrostep, 3}
      assert_received {:stepped, {:macrostep, 2}, points, :prev}
      assert points == [%{macrostep: 1}, %{macrostep: 2}, %{macrostep: 3}]
    end

    test "takes the four moves and nothing else", %{state: state} do
      for move <- [:first, :prev, :next, :live] do
        assert Selection.scrub(state, move).selection == {:macrostep, 3}
      end

      assert Selection.scrub(state, :sideways) == state
      refute_received {:stepped, _selection, _points, :sideways}
    end

    # Sabotage: removed the `function_exported?/3` checks from
    # `inspector_module/0` - the scrub reached a module with neither read and
    # raised `UndefinedFunctionError` instead of standing still (verified).
    test "does nothing in a tree where the reads do not resolve", %{state: state} do
      Application.put_env(:statifier_blocks, :trace_inspector_module, NoInspector)

      assert Selection.scrub(state, :prev) == state
    end

    test "does nothing to a shape that is not a read model" do
      assert Selection.scrub(%{}, :prev) == %{}
      assert Selection.scrub(%{messages: "not a list"}, :prev) == %{messages: "not a list"}
    end
  end

  describe "selecting one macrostep" do
    # Sabotage: had `select/2` write the bare integer rather than the
    # `{:macrostep, n}` pair - every read downstream fell to its catch-all and
    # the view silently stayed on the tip (verified).
    test "writes the selection directly, with no read at all", %{state: state} do
      assert Selection.select(state, 2).selection == {:macrostep, 2}
      refute_received {:stepped, _selection, _points, _move}
    end

    test "declines a value that is not a macrostep", %{state: state} do
      assert Selection.select(state, -1) == state
      assert Selection.select(state, "2") == state
      assert Selection.select(%{}, 2) == %{}
    end
  end
end
