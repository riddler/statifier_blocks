defmodule StatifierBlocks.Palette.ManifestTest do
  @moduledoc """
  The one assertion a host pins its palette with.

  A count (`map_size(palette.types) == 27`) is the handle a host reaches
  for today, and every minor that adds a type moves the number without
  saying which type moved or which version did. `manifest/1` is that
  handle with the names and versions in it, so the assertion that fails
  says what changed.

  The properties under test are the ones a pin rests on: the entries are
  sorted, so two palettes built in different insertion orders compare
  equal; a recipe is marked `:recipe` rather than carrying a version it
  does not have; and the core palette's manifest is pinned here in full,
  so a core type added, removed, or version-bumped fails this file with a
  readable list diff rather than a moved integer.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{BlockTypeFixtures, Core, Palette}
  alias StatifierBlocks.BlockTypeFixtures.{Minimal, Toy}

  @core_manifest [
    {"core.assign", 1},
    {"core.await", 1},
    {"core.branch", 1},
    {"core.drafts", 1},
    {"core.foreach", 1},
    {"core.group", 1},
    {"core.invoke", 1},
    {"core.map", 1},
    {"core.on_event", 1},
    {"core.parallel", 1},
    {"core.placeholder", 1},
    {"core.raise", 1},
    {"core.resumable_group", 1},
    {"core.send", 2},
    {"core.sequence", 1},
    {"core.subchart", 1},
    {"core.wait", 2},
    {"deadline", :recipe}
  ]

  describe "manifest/1" do
    # Sabotage: dropped one entry from `core_types/0` - red here, and the
    # failure names the missing type rather than moving a count (verified).
    test "pins the core palette in one assertion" do
      assert Palette.manifest(Palette.core()) == @core_manifest
    end

    # Sabotage: dropped the `Enum.sort/1` and returned the two lists
    # concatenated - red here (verified). The types and the recipes are
    # sorted *together*, so a recipe whose name sorts before a type's is
    # what proves it: concatenation alone would put the type first.
    test "sorts types and recipes into one list, not two appended ones" do
      palette =
        Palette.new(%{"myapp.capture" => Minimal},
          recipes: %{"deadline" => Core.DeadlineRecipe}
        )

      assert Palette.manifest(palette) == [{"deadline", :recipe}, {"myapp.capture", 1}]
    end

    # Sabotage: dropped the `Enum.sort/1` - red here (verified). Two
    # palettes carrying the same entries, one built from a map and one
    # from an ordered registration list, have the same manifest.
    test "insertion order does not change it" do
      forwards =
        Palette.new(%{"myapp.authorize" => Toy}, recipes: %{"deadline" => Core.DeadlineRecipe})

      backwards =
        Palette.from_modules([{"myapp.authorize", Toy}],
          recipes: [{"deadline", Core.DeadlineRecipe}]
        )

      assert Palette.manifest(backwards) == Palette.manifest(forwards)
      assert Palette.manifest(forwards) == [{"deadline", :recipe}, {"myapp.authorize", 2}]
    end

    # Sabotage: had the type clause emit the module instead of
    # `current_version/0` - red here (verified).
    test "carries each type's current version, not its module" do
      assert Palette.manifest(Palette.new(%{"myapp.authorize" => Toy})) ==
               [{"myapp.authorize", Toy.current_version()}]
    end

    # Sabotage: had the recipe clause emit `{name, 1}` - red here
    # (verified).
    test "marks a recipe :recipe rather than giving it a version" do
      palette = Palette.new(%{}, recipes: %{"deadline" => Core.DeadlineRecipe})

      assert Palette.manifest(palette) == [{"deadline", :recipe}]
    end

    # Sabotage: had `manifest/1` merge the two maps before mapping - red
    # here, because one of the two same-named entries is lost (verified).
    test "carries both entries when a type and a recipe share a name" do
      palette =
        Palette.new(%{"deadline" => Minimal},
          recipes: %{"deadline" => Core.DeadlineRecipe}
        )

      assert Palette.manifest(palette) == [{"deadline", 1}, {"deadline", :recipe}]
    end

    # Sabotage: had `manifest/1` fall back to `core()` for an empty
    # palette - red here (verified).
    test "an empty palette has an empty manifest" do
      assert Palette.manifest(Palette.new()) == []
    end

    # Sabotage: had `manifest/1` read `palette.assignability` into the
    # list - red here (verified).
    test "names types and recipes only" do
      palette =
        Palette.new(%{"toy.budget_check" => Toy},
          assignability: StatifierBlocks.AssignabilityFixtures.Widens,
          validators: [BlockTypeFixtures.Minimal]
        )

      assert Palette.manifest(palette) == [{"toy.budget_check", 2}]
    end
  end
end
