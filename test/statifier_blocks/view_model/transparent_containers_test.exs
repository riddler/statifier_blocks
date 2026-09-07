defmodule StatifierBlocks.ViewModel.TransparentContainersTest do
  @moduledoc """
  The host seam a flattened outline needs (`sb-6xkf`, RQ-SF038-7):
  `transparent?/2`, `effective_parent/3` and `end_of_list_target/3`, with
  `core_containers/0` as the documented default rather than a built-in
  policy.

  Asserted over both worked-example documents, because the two reach
  different halves of the same question: the card-authorization document
  nests an opaque `core.branch` under a transparent
  `core.resumable_group`, so the climb stops below the root, and the
  signup wizard puts two flow children directly in a transparent
  `core.group` under a transparent root, so the climb runs the whole way
  up and the append lands in the root's own body.

  All three readers are pure over a `%ViewModel{}` and an id, so this file
  is asserted with LiveView absent from the dependency tree and carries no
  `ensure_loaded` wrapper.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{Block, CoreFixtures, Document, DocumentFixtures, Palette, ViewModel}

  doctest StatifierBlocks.ViewModel,
    only: [core_containers: 0, transparent?: 2, effective_parent: 3, end_of_list_target: 3]

  setup do
    palette = CoreFixtures.palette()

    %{
      card: ViewModel.build(DocumentFixtures.worked_example(), palette, []),
      signup: ViewModel.build(DocumentFixtures.signup_wizard(), palette, []),
      types: ViewModel.core_containers()
    }
  end

  describe "core_containers/0" do
    # sabotage: drop `"core.resumable_group"` from the list -> red. The
    # ORDER is asserted too, because the doctest above prints the list and
    # a reordered default would leave that doctest stale.
    test "is the three core containers, in the order the docs name them" do
      assert ViewModel.core_containers() == [
               "core.sequence",
               "core.group",
               "core.resumable_group"
             ]
    end
  end

  describe "transparent?/2" do
    # sabotage: make `transparent?/2` ignore `types` and test against
    # `core_containers/0` -> still green here, which is why the two tests
    # below exist; sabotage `type in types` to `type not in types` -> red
    test "answers on the caller's list, not on a built-in one", %{card: vm, types: types} do
      assert ViewModel.transparent?(ViewModel.find_node(vm, "blk_ROOT"), types)
      assert ViewModel.transparent?(ViewModel.find_node(vm, "blk_GRP"), types)
      refute ViewModel.transparent?(ViewModel.find_node(vm, "blk_BR"), types)
      refute ViewModel.transparent?(ViewModel.find_node(vm, "blk_AUTH"), types)
    end

    # sabotage: have `transparent?/2` fall back to `core_containers/0` when
    # `types` is empty -> the two containers read transparent -> red
    test "an empty list makes every node opaque", %{card: vm} do
      refute ViewModel.transparent?(ViewModel.find_node(vm, "blk_ROOT"), [])
      refute ViewModel.transparent?(ViewModel.find_node(vm, "blk_GRP"), [])
    end

    # sabotage: hard-code `core_containers/0` inside `transparent?/2` -> the
    # host's extended list stops mattering -> red
    test "a host's own container joins the list without a package change", %{card: vm} do
      node = ViewModel.find_node(vm, "blk_BR")

      refute ViewModel.transparent?(node, ViewModel.core_containers())
      assert ViewModel.transparent?(node, ["core.branch" | ViewModel.core_containers()])
    end
  end

  describe "effective_parent/3" do
    # sabotage: climb unconditionally (drop the `transparent?/2` guard) ->
    # the answer becomes `{"blk_GRP", "body", 0}` -> red
    test "is parent_of/2 when the parent is opaque", %{card: vm, types: types} do
      assert ViewModel.parent_of(vm, "blk_PAR") == {"blk_BR", "arm_approved", 0}
      assert ViewModel.effective_parent(vm, "blk_PAR", types) == {"blk_BR", "arm_approved", 0}
    end

    # sabotage: return `position` without recursing -> `{"blk_GRP", "body",
    # 0}` -> red. Run: the climb was disabled and this test failed.
    test "climbs past a transparent group to the root's own body", %{card: vm, types: types} do
      assert ViewModel.parent_of(vm, "blk_BR") == {"blk_GRP", "body", 0}
      assert ViewModel.effective_parent(vm, "blk_BR", types) == {"blk_ROOT", "body", 1}
    end

    # sabotage: recurse only one level (climb past the group but not the
    # root) -> both answers stay `{"blk_WGRP", "body", _}` -> red
    test "climbs past two transparent ancestors in the signup wizard", %{
      signup: vm,
      types: types
    } do
      assert ViewModel.parent_of(vm, "blk_WBR") == {"blk_WGRP", "body", 0}
      assert ViewModel.parent_of(vm, "blk_CNV") == {"blk_WGRP", "body", 1}

      assert ViewModel.effective_parent(vm, "blk_WBR", types) == {"blk_WROOT", "body", 1}
      assert ViewModel.effective_parent(vm, "blk_CNV", types) == {"blk_WROOT", "body", 1}
    end

    # sabotage: restrict the climb to body slots -> the rail child answers
    # `{"blk_WGRP", "interrupts", 0}` -> red
    test "a rail child climbs by the transparent group's own position", %{
      signup: vm,
      types: types
    } do
      # `blk_WINT` sits in the group's `interrupts` rail, not its body, and
      # the climb answers where the GROUP sits - one tuple, whichever slot
      # of a transparent ancestor the block came out of.
      assert ViewModel.parent_of(vm, "blk_WINT") == {"blk_WGRP", "interrupts", 0}
      assert ViewModel.effective_parent(vm, "blk_WINT", types) == {"blk_WROOT", "body", 1}
    end

    # sabotage: drop the `parent_of(vm, parent_id) != nil` half of the guard
    # -> unchanged here, but see the two climb tests above; sabotage the
    # `nil ->` arm to raise -> red
    test "the root has no position, transparent or not", %{card: vm, types: types} do
      assert ViewModel.effective_parent(vm, "blk_ROOT", types) == nil
      assert ViewModel.effective_parent(vm, "blk_ROOT", []) == nil
    end

    # sabotage: make the `nil ->` arm return `{id, "body", 0}` -> red
    test "an id no block carries is nil", %{card: vm, types: types} do
      assert ViewModel.effective_parent(vm, "absent", types) == nil
    end

    # sabotage: climb whenever the parent has more than one slot (a shape
    # test rather than a type test) -> the group is climbed past with an
    # empty list -> red
    test "an empty type list makes it parent_of/2 exactly", %{signup: vm} do
      for id <- ["blk_WBR", "blk_CNV", "blk_WGRP", "blk_VAR", "blk_WROOT"] do
        assert ViewModel.effective_parent(vm, id, []) == ViewModel.parent_of(vm, id)
      end
    end
  end

  describe "end_of_list_target/3" do
    # sabotage: return `effective_parent/3`'s own index instead of the flow
    # count -> `{"blk_WROOT", "body", 1}` -> red
    test "appends after the last flow child of the effective slot", %{
      signup: vm,
      types: types
    } do
      assert ViewModel.effective_parent(vm, "blk_WBR", types) == {"blk_WROOT", "body", 1}
      assert ViewModel.end_of_list_target(vm, "blk_WBR", types) == {"blk_WROOT", "body", 2}
    end

    # sabotage: look the slot up on the ROOT rather than on
    # `effective_parent/3`'s parent id -> `{"blk_BR", "arm_approved", 2}`
    # -> red
    test "the effective slot is the opaque parent's own slot", %{card: vm, types: types} do
      assert ViewModel.end_of_list_target(vm, "blk_PAR", types) == {"blk_BR", "arm_approved", 1}
    end

    # sabotage: count `flow_children/1` of the wrong slot (take the first
    # slot rather than the named one) -> red
    test "the root's body in the card document holds two flow children", %{
      card: vm,
      types: types
    } do
      assert ViewModel.end_of_list_target(vm, "blk_BR", types) == {"blk_ROOT", "body", 2}
    end

    # sabotage: replace the `else` arm with `{id, "body", 0}` -> red
    test "the root is nil, as effective_parent/3 is", %{card: vm, types: types} do
      assert ViewModel.end_of_list_target(vm, "blk_ROOT", types) == nil
      assert ViewModel.end_of_list_target(vm, "absent", types) == nil
    end

    # sabotage: count `slot.children` instead of `flow_children(slot)` ->
    # `{"root", "body", 2}` -> red. Run: this is the mutation that failed.
    test "a shelf is not counted: the append lands before it" do
      wait = Block.new("core.wait", id: "wait", config: %{"duration" => "30s"})
      shelf = Block.new("core.drafts", id: "shelf")

      vm =
        "core.sequence"
        |> Block.new(id: "root", slots: %{"body" => [wait, shelf]})
        |> Document.new()
        |> ViewModel.build(Palette.core(), [])

      assert ViewModel.end_of_list_target(vm, "wait", ViewModel.core_containers()) ==
               {"root", "body", 1}
    end
  end
end
