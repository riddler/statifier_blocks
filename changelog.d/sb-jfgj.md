### Fixed

- The palette's count line no longer counts a recipe as a block type. It
  reports the two kinds apart - "16 block types, 1 recipe" - and when a slot's
  acceptance set is narrowing the list it counts types alone, naming the
  recipes in a clause of their own ("2 of 16 block types fit here; 1 recipe
  also listed"), because a recipe is not a block type and no set of type names
  can answer whether one fits.
