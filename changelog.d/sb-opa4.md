### Changed

- A recipe's `insert/2` may return `{:set_accepts, names}` beside the blocks
  it inserts, as it already could `{:set_datamodel, entries}`:
  `Recipe.within_reach?/2` answers `true` for a list holding it, and
  `Edit.Targets.recipe_inserts/4` no longer refuses such a recipe as
  `{:recipe_out_of_reach, name}`. Every command that names a position is
  still held to the armed position and the block that encloses it.
