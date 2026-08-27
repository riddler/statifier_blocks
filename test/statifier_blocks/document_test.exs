defmodule StatifierBlocks.DocumentTest do
  use ExUnit.Case, async: true

  alias StatifierBlocks.{Block, Document}

  # sabotage: default revision to 1 instead of 0 -> red
  test "new/2 defaults revision to 0, metadata to %{}, schema_version to 1" do
    root = Block.new("core.sequence")
    document = Document.new(root)

    assert document.root == root
    assert document.revision == 0
    assert document.metadata == %{}
    assert document.schema_version == 1
    assert "bdoc_" <> _rest = document.id
  end

  # sabotage: hardcode `metadata: %{}` instead of
  # `Keyword.get(opts, :metadata, %{})` -> red
  test "new/2 accepts explicit :id, :revision, :metadata" do
    root = Block.new("core.sequence")

    document =
      Document.new(root, id: "bdoc_explicit", revision: 17, metadata: %{"name" => "Example"})

    assert document.id == "bdoc_explicit"
    assert document.revision == 17
    assert document.metadata == %{"name" => "Example"}
  end

  describe "blocks/1" do
    # sabotage: change `def blocks(%__MODULE__{root: root}), do: walk(root)`
    # to `[root | walk(root)]` (double-counts the root) -> red
    test "returns just the root for a leaf document" do
      root = Block.new("core.wait", id: "blk_root")
      document = Document.new(root)

      assert Document.blocks(document) == [root]
    end

    # sabotage: change walk/1 to collect all direct children before
    # recursing into any of them (breadth-first) instead of recursing into
    # each child immediately (depth-first) -> red
    test "walks pre-order, root first, depth before breadth within a slot" do
      grandchild = Block.new("myapp.notify", id: "blk_grandchild")
      child = Block.new("core.sequence", id: "blk_child", slots: %{"body" => [grandchild]})
      sibling = Block.new("myapp.notify", id: "blk_sibling")

      root =
        Block.new("core.sequence", id: "blk_root", slots: %{"body" => [child, sibling]})

      document = Document.new(root)

      assert Enum.map(Document.blocks(document), & &1.id) == [
               "blk_root",
               "blk_child",
               "blk_grandchild",
               "blk_sibling"
             ]
    end

    # sabotage: change `Enum.sort_by(&elem(&1, 0))` in walk/1 to
    # `Enum.sort_by(&elem(&1, 0), :desc)` -> red
    test "visits slots in UTF-8-sorted name order regardless of insertion order" do
      arm_block = Block.new("myapp.notify", id: "blk_arm")
      otherwise_block = Block.new("myapp.notify", id: "blk_otherwise")

      # Inserted in reverse-sorted order: "otherwise" before "arm_approved".
      root =
        Block.new("core.branch",
          id: "blk_root",
          slots: %{"otherwise" => [otherwise_block], "arm_approved" => [arm_block]}
        )

      document = Document.new(root)

      assert Enum.map(Document.blocks(document), & &1.id) == [
               "blk_root",
               "blk_arm",
               "blk_otherwise"
             ]
    end
  end

  describe "fetch_path/2" do
    # sabotage: return `{:ok, [{id, "self", 0}]}` instead of `{:ok, []}` for
    # the root clause -> red
    test "returns {:ok, []} for the root" do
      root = Block.new("core.sequence", id: "blk_root")
      document = Document.new(root)

      assert Document.fetch_path(document, "blk_root") == {:ok, []}
    end

    # sabotage: in find_in_slot/5's recursive clause, return the child's
    # own path instead of prepending `{parent_id, slot_name, index}` to it
    # -> red
    test "returns the exact {parent_id, slot, index} list for a nested block" do
      grandchild = Block.new("myapp.notify", id: "blk_grandchild")
      child = Block.new("core.sequence", id: "blk_child", slots: %{"body" => [grandchild]})
      root = Block.new("core.sequence", id: "blk_root", slots: %{"body" => [child]})
      document = Document.new(root)

      assert Document.fetch_path(document, "blk_grandchild") ==
               {:ok, [{"blk_root", "body", 0}, {"blk_child", "body", 0}]}
    end

    # sabotage: hardcode index 0 in find_in_slot instead of threading the
    # accumulator -> red
    test "returns index 1 for a second child in the same slot" do
      first = Block.new("myapp.notify", id: "blk_first")
      second = Block.new("myapp.notify", id: "blk_second")
      root = Block.new("core.sequence", id: "blk_root", slots: %{"body" => [first, second]})
      document = Document.new(root)

      assert Document.fetch_path(document, "blk_second") == {:ok, [{"blk_root", "body", 1}]}
    end

    # sabotage: return {:ok, []} for any unmatched id instead of :error -> red
    test "returns :error for an absent id" do
      root = Block.new("core.sequence", id: "blk_root")
      document = Document.new(root)

      assert Document.fetch_path(document, "blk_missing") == :error
    end
  end
end
