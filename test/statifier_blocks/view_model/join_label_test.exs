defmodule StatifierBlocks.ViewModel.JoinLabelTest do
  @moduledoc """
  `Node.join_label`: the words the join marker under a side-by-side
  arrangement reads, resolved from the block type's own callback (ADR-0002
  amendment B's `join_label`, ADR-0005 decision 10).

  The derivation is a pure function of the palette entry and the block's
  config, so it is asserted here with LiveView absent from the dependency
  tree; the markup half lives beside the other rendering tests and asserts
  only that the string reaches the DOM.

  The property that matters is the negative one, and it is why the field is
  on the node at all: nothing on this path knows the string
  `"core.parallel"`, or that a completion rule exists. A host type that fans
  into lanes with a rule of its own declares its own callback and gets its
  own words in the same place.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{Block, BlockTypeFixtures, Document, Palette, ViewModel}
  alias StatifierBlocks.ViewModel.{Node, Slot}

  defp palette do
    Palette.new(Map.merge(Palette.core_types(), BlockTypeFixtures.raw_palette()))
  end

  defp document_with(child) do
    root = Block.new("core.sequence", id: "blk_ROOT", slots: %{"body" => [child]})
    Document.new(root, id: "bdoc_SIGNUP", revision: 1)
  end

  defp node_for(child) do
    %ViewModel{root: root} = ViewModel.build(document_with(child), palette(), [])
    find_node(root, child.id)
  end

  defp find_node(%Node{block_id: id} = node, id), do: node

  defp find_node(%Node{slots: slots}, id) do
    Enum.find_value(slots, fn %Slot{children: children} ->
      Enum.find_value(children, &find_node(&1, id))
    end)
  end

  defp parallel(id, config) do
    lane = Block.new("core.wait", id: id <> "_L", config: %{"duration" => "PT1S"})
    Block.new("core.parallel", id: id, config: config, slots: %{"lane_started" => [lane]})
  end

  describe "the callback's words reach the node" do
    # Sabotage: drop `join_label: BlockType.join_label(entry, config)` from
    # the `%Node{}` `build_resolved_node/4` returns - the field falls back to
    # its `nil` default and both of these fail, which is the whole gap this
    # bead closed: the callback was declared and exercised and never read.
    test "core.parallel completing at the first lane says so" do
      node = node_for(parallel("blk_FIRST", %{"lanes" => ["started"], "complete" => "first"}))

      assert node.join_label == "continue at first"
    end

    test "core.parallel completing when all lanes are done says that instead" do
      node = node_for(parallel("blk_ALL", %{"lanes" => ["started"], "complete" => "all"}))

      assert node.join_label == "continue when all"
    end

    # The config is read at build time, not at registration time: the same
    # type, two documents, two strings.
    test "the words follow the block's config rather than the type" do
      first = node_for(parallel("blk_F2", %{"lanes" => ["started"], "complete" => "first"}))
      all = node_for(parallel("blk_A2", %{"lanes" => ["started"]}))

      refute first.join_label == all.join_label
    end
  end

  describe "a type declaring no callback carries nothing" do
    # Sabotage: give `join_label/2` a default string instead of `nil` for an
    # entry that declares nothing - every block in every document grows a
    # marker, which is this package inventing semantics it does not own.
    test "a core type with no join_label declaration is nil" do
      node = node_for(Block.new("core.wait", id: "blk_W", config: %{"duration" => "PT1S"}))

      assert node.join_label == nil
    end

    test "a type with no palette_entry/0 at all is nil" do
      node = node_for(Block.new("toy.minimal", id: "blk_MIN"))

      assert node.join_label == nil
    end

    # An unresolvable block's entry is the placeholder's, which declares no
    # callback - so it reaches `nil` by the ordinary route and needs no arm
    # of its own.
    test "an unresolvable block is nil, by the ordinary route" do
      node = node_for(Block.new("host.absent", id: "blk_GONE"))

      assert {:unresolvable, _reason} = node.status
      assert node.join_label == nil
    end
  end
end
