defmodule StatifierBlocks.ViewModel.PaletteGroupOrderTest do
  @moduledoc """
  The host seam a regrouped palette needs (`sb-cvtx`, RQ-SF038-18):
  `order_palette_groups/2` spends the reading order a host already wrote
  down in its profile's `palette_groups` list, instead of leaving every
  palette in the alphabetical order `build/3` produces.

  Asserted over a real view model's groups rather than bare structs,
  because the order the function is asked to replace is the one `build/3`
  builds: this palette carries "Authorization" (the toy type's own
  `palette_entry/0`), "Other" (three types declaring none) and
  "Structure" (core's own), which is alphabetical and is exactly the
  order a host regrouping by intent does not want.

  The function is pure over a list of groups and a list of names, so this
  file is asserted with LiveView absent and carries no `ensure_loaded`
  wrapper. The mount-level half - that a profile's list is a filter as
  well as an order - is in `StatifierBlocks.Editor.ProfileTest`.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{Block, BlockTypeFixtures, Document, Palette, ViewModel}

  doctest StatifierBlocks.ViewModel, only: [order_palette_groups: 2]

  setup do
    palette = Palette.new(Map.merge(Palette.core_types(), BlockTypeFixtures.raw_palette()))
    document = Document.new(Block.new("core.sequence", id: "blk_ROOT"))
    vm = ViewModel.build(document, palette, [])

    # The premise of every assertion below: what the package builds is name
    # order, and the three groups are far enough apart alphabetically that a
    # reordering cannot pass by accident.
    assert Enum.map(vm.palette_groups, & &1.name) == ["Authorization", "Other", "Structure"]

    %{groups: vm.palette_groups}
  end

  describe "order_palette_groups/2" do
    # sabotage: sort the named half by name rather than by the list's index
    # -> red, because the list here is the reverse of name order.
    test "puts the groups the list names first, in the list's order", %{groups: groups} do
      ordered = ViewModel.order_palette_groups(groups, ["Structure", "Other", "Authorization"])

      assert Enum.map(ordered, & &1.name) == ["Structure", "Other", "Authorization"]
    end

    # sabotage: drop the unnamed half from the return -> red here, green on
    # the test above it; the drop rule belongs to the profile, not to this.
    test "puts every group the list does not name after them, by name", %{groups: groups} do
      ordered = ViewModel.order_palette_groups(groups, ["Structure"])

      assert Enum.map(ordered, & &1.name) == ["Structure", "Authorization", "Other"]
    end

    test "a name no group carries orders nothing and drops nothing", %{groups: groups} do
      ordered = ViewModel.order_palette_groups(groups, ["no such group", "Structure"])

      assert Enum.map(ordered, & &1.name) == ["Structure", "Authorization", "Other"]
    end

    # sabotage: return the groups sorted by name in this clause -> still
    # green, which is the point: `:all` is the order `build/3` already put
    # them in, and this clause must not touch it.
    test ":all is the groups as built, unchanged", %{groups: groups} do
      assert ViewModel.order_palette_groups(groups, :all) == groups
    end

    test "an empty list orders nothing and keeps every group, by name", %{groups: groups} do
      assert ViewModel.order_palette_groups(groups, []) == Enum.sort_by(groups, & &1.name)
    end
  end
end
