defmodule StatifierBlocks.ViewModel.OutlineTest do
  @moduledoc """
  The document in reading order (ADR-0005's 2026-09-07 amendment): one
  `{node, depth, kind}` per block, pre-order, every block exactly once.

  The four kinds are asserted on ONE document rather than four, because
  the property that matters is the partition - a walk that returns a
  `:rail` entry but drops the `:tray` beside it is a walk a reviewer
  cannot trust to be the document, and only one document can show that.

  `outline/1` reads nothing but the struct `build/3` already returned, so
  it is asserted here with LiveView absent from the dependency tree.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{Block, Document, Palette, ViewModel}

  doctest StatifierBlocks.ViewModel, only: [outline: 1]

  defmodule Outer do
    @moduledoc """
    One body slot, one failure rail and one tray: `:step` for the body's
    children by `arrangement/1`'s `:stack`, and the rail-then-tray tail.
    """

    @behaviour StatifierBlocks.BlockType

    @impl true
    def current_version, do: 1

    @impl true
    def slots(_config),
      do: [{"body", :any, "Body"}, {"on_error", :any, "On error"}, {"shelf", :any, "Shelf"}]

    @impl true
    def config_schema(_config), do: []

    @impl true
    def validate_config(_config), do: :ok

    @impl true
    def emit(%Block{id: id}, _context), do: {:ok, {:emitted, id}}

    @impl true
    def palette_entry,
      do: %{
        label: "Settle the batch",
        slot_style: %{"on_error" => :failure, "shelf" => :tray}
      }
  end

  defmodule Fan do
    @moduledoc "Two body slots and no `layout`, which is `arrangement/1`'s `:fan`."

    @behaviour StatifierBlocks.BlockType

    @impl true
    def current_version, do: 1

    @impl true
    def slots(_config), do: [{"left", :any, "Left"}, {"right", :any, "Right"}]

    @impl true
    def config_schema(_config), do: []

    @impl true
    def validate_config(_config), do: :ok

    @impl true
    def emit(%Block{id: id}, _context), do: {:ok, {:emitted, id}}

    @impl true
    def palette_entry, do: %{label: "Decide"}
  end

  defmodule Lanes do
    @moduledoc "One body slot but `layout: :columns`, the OTHER route to `:arm`."

    @behaviour StatifierBlocks.BlockType

    @impl true
    def current_version, do: 1

    @impl true
    def slots(_config), do: [{"body", :any, "Body"}]

    @impl true
    def config_schema(_config), do: []

    @impl true
    def validate_config(_config), do: :ok

    @impl true
    def emit(%Block{id: id}, _context), do: {:ok, {:emitted, id}}

    @impl true
    def palette_entry, do: %{label: "At the same time", layout: :columns}
  end

  defmodule Leaf do
    @moduledoc "A step with nothing under it: one entry and nothing follows."

    @behaviour StatifierBlocks.BlockType

    @impl true
    def current_version, do: 1

    @impl true
    def slots(_config), do: []

    @impl true
    def config_schema(_config), do: []

    @impl true
    def validate_config(_config), do: :ok

    @impl true
    def emit(%Block{id: id}, _context), do: {:ok, {:emitted, id}}

    @impl true
    def palette_entry, do: %{label: "Step"}
  end

  defp palette do
    Palette.new(%{
      "host.outer" => Outer,
      "host.fan" => Fan,
      "host.lanes" => Lanes,
      "host.leaf" => Leaf,
      "core.drafts" => StatifierBlocks.Core.Drafts
    })
  end

  # One document carrying every kind: a stacked body holding a step, a fan
  # holding an arm and a lanes container holding another arm, a drafts
  # shelf at the foot of that body, a failure rail and a tray.
  defp document do
    Document.new(
      Block.new("host.outer",
        id: "root",
        slots: %{
          "body" => [
            Block.new("host.leaf", id: "step"),
            Block.new("host.fan",
              id: "fan",
              slots: %{"left" => [Block.new("host.leaf", id: "arm")], "right" => []}
            ),
            Block.new("host.lanes",
              id: "lanes",
              slots: %{"body" => [Block.new("host.leaf", id: "lane")]}
            ),
            Block.new("core.drafts", id: "shelf")
          ],
          "on_error" => [Block.new("host.leaf", id: "rail")],
          "shelf" => [Block.new("host.leaf", id: "tray")]
        }
      ),
      id: "doc"
    )
  end

  defp outline do
    document()
    |> ViewModel.build(palette(), [])
    |> ViewModel.outline()
    |> Enum.map(fn {node, depth, kind} -> {node.block_id, depth, kind} end)
  end

  describe "outline/1" do
    # sabotage: swap `body ++ rails ++ trays` for `rails ++ body ++ trays`
    # in `outline_walk/3` -> the rail sorts above the body -> red
    test "is the document in reading order, one entry per block" do
      assert outline() == [
               {"root", 0, :step},
               {"step", 1, :step},
               {"fan", 1, :step},
               {"arm", 2, :arm},
               {"lanes", 1, :step},
               {"lane", 2, :arm},
               {"shelf", 1, :step},
               {"rail", 1, :rail},
               {"tray", 1, :tray}
             ]
    end

    # sabotage: make the root's entry `{root, 0, :arm}` -> red
    test "the first entry is always the root, at depth 0, kind :step" do
      assert [{"root", 0, :step} | _rest] = outline()
    end

    # sabotage: hard-code `body_kind` to `:step` -> the two arms read as
    # steps -> red. `:fan` and `:lanes` are both asserted, so a walk that
    # re-derived the distinction from a slot count would fail on `lanes`
    test ":step versus :arm is arrangement/1's question, on both its routes" do
      kinds = Map.new(outline(), fn {id, _depth, kind} -> {id, kind} end)

      assert kinds["step"] == :step
      assert kinds["arm"] == :arm
      assert kinds["lane"] == :arm
    end

    # sabotage: reject `shelf_children/1` from `outline_slot/2` -> the
    # shelf vanishes from the list -> red
    test "a rail, a tray and a drafts shelf are kinds and positions, never omissions" do
      ids = Enum.map(outline(), fn {id, _depth, _kind} -> id end)

      assert "rail" in ids
      assert "tray" in ids
      assert "shelf" in ids
      assert length(ids) == 9
    end

    # sabotage: pass `depth + 2` for an arm in `outline_slot/3` -> the arm
    # sits two below its container -> red. A slot is not an entry and
    # never consumes a level, in all four rows
    test "depth is block nesting depth: a slot never consumes a level" do
      depths = Map.new(outline(), fn {id, depth, _kind} -> {id, depth} end)

      assert depths["root"] == 0
      assert depths["fan"] == 1
      assert depths["rail"] == 1
      assert depths["tray"] == 1
      assert depths["arm"] == 2
      assert depths["lane"] == 2
    end

    # sabotage: read a findings list into the walk -> calling it twice on
    # one view model would still match, so this pins purity by comparing
    # two walks of the same struct
    test "is pure: two walks of one view model return identical lists" do
      view_model = ViewModel.build(document(), palette(), [])

      assert ViewModel.outline(view_model) == ViewModel.outline(view_model)
    end
  end
end
