defmodule StatifierBlocks.Core.CheckpointTest do
  @moduledoc """
  `core.checkpoint`'s declarations, as ADR-0002's Amendment of 2026-11-20
  (`C12d`) gives them: no slots, no config, the one default outcome, no
  `returnable?/1`, the injected `io/1`, version 1, and the next free
  `"Structure"` order, labelled "Checkpoint". What it compiles to is
  pinned in `StatifierBlocks.Compiler.TrailTest`.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{Block, BlockType, Palette}
  alias StatifierBlocks.Core.Checkpoint

  doctest StatifierBlocks.Core.Checkpoint

  # `function_exported?/3` answers false for a module not yet loaded.
  setup do
    Code.ensure_loaded!(Checkpoint)
    :ok
  end

  describe "its declarations (C12d)" do
    # Sabotage: gave `Checkpoint` a `slots/1` answering one `body` slot -
    # red on the slots assertion.
    test "no slots, no config fields, nothing refused" do
      assert Checkpoint.slots(%{}) == []
      assert Checkpoint.config_schema(%{}) == []
      assert Checkpoint.validate_config(%{}) == :ok
    end

    # Sabotage: defined `outcomes/1` answering `["passed"]` - red.
    test "one outcome, the default done, and no failure outcome" do
      refute function_exported?(Checkpoint, :outcomes, 1)
      refute function_exported?(Checkpoint, :failure_outcomes, 1)
      refute function_exported?(Checkpoint, :donedata_type, 1)
      assert BlockType.outcomes(Checkpoint, %{}) == [{"done", "Done"}]
    end

    # Sabotage: defined `returnable?/1` answering `true` - red on both.
    test "it is not a returnable step" do
      refute function_exported?(Checkpoint, :returnable?, 1)
      refute BlockType.returnable?(Checkpoint, %{})
    end

    # Sabotage: overrode `io/1` with `%{kinds: [:step]}` - red.
    test "io/1 is the injected empty map, and version 1" do
      assert Checkpoint.io(%{}) == %{}
      assert Checkpoint.current_version() == 1
    end

    # Sabotage: gave the entry the order 19 - red. Dropping the entry
    # from `core_types/0` is red here too.
    test "it is the Structure group's entry 18, labelled Checkpoint" do
      assert %{label: "Checkpoint", group: "Structure", order: 18} = Checkpoint.palette_entry()

      assert {:ok, Checkpoint} = Palette.fetch(Palette.core(), "core.checkpoint")
      assert {"core.checkpoint", 1} in Palette.manifest(Palette.core())
    end

    # Sabotage: emptied `explain/0` - red.
    test "it explains itself in one paragraph that names no host's domain" do
      explain = Checkpoint.explain()

      assert explain =~ "point of no return"
      refute explain =~ ~r/\b(screen|patron|library|card)\b/i
    end

    # Sabotage: made `sentence/1` answer the label - red.
    test "its sentence is not its label" do
      assert Checkpoint.sentence(%{}) != Checkpoint.palette_entry().label
    end
  end

  describe "a fresh block" do
    # Sabotage: dropped the `core.checkpoint` entry from `core_types/0` -
    # `new_block/2` answered an unknown type and this went red.
    test "starts with no config and no slots" do
      assert {:ok, %Block{type: "core.checkpoint", config: config, slots: slots}} =
               Palette.new_block(Palette.core(), "core.checkpoint")

      assert config == %{}
      assert slots == %{}
    end
  end
end
