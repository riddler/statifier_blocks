### Added

- A palette may name **recipes** beside block types: arrangements an author
  picks the way they pick a type. A recipe is a module implementing
  `StatifierBlocks.Recipe` - `insert/2`, handed the armed position and the
  document, answering with the commands that build the arrangement, and
  `palette_entry/0`, which draws it in the palette browser exactly as a type
  draws. Register recipes with the new `:recipes` option on
  `StatifierBlocks.Palette.new/2` (a `name => module` map) or on
  `from_modules/2` (an ordered list, later entries winning), and resolve one
  with `fetch_recipe/2`. Recipe names and type names are two namespaces, not
  one: a recipe named `"deadline"` and a block type named `"deadline"` do not
  collide. A recipe may target the armed position and any slot of the block
  enclosing it, and nothing above that.

- The core palette registers one recipe, `"deadline"`
  (`StatifierBlocks.Palette.core_recipes/0`). One pick puts down the pair that
  spells a clock interrupt: a `core.send` carrying a generated deadline event
  and a delay, at the head of the enclosing group's `body`, and a
  `core.on_event` naming the same event on that group's `interrupts` rail. The
  pair compiles clean before the author types anything. Picked at a position
  whose enclosing block has no interrupts rail, the gesture is refused and
  nothing is written.

- `StatifierBlocks.Edit.t()` admits a composition, `{:compound, [t()]}`,
  carrying a non-empty list of the five commands. `Edit.apply/2` applies its
  members left to right and returns the compound of their inverses in reverse
  order, so `StatifierBlocks.Edit.History` remembers it as **one undo entry**:
  one gesture in, one gesture out. A member that refuses refuses the whole
  compound, with that member's own error term and no document at all. The set
  of edits is still five - a compound's leaves are drawn from it, and a list
  that is empty or holds a compound of its own is refused rather than
  flattened.

### Changed

- A `StatifierBlocks.ViewModel.PaletteGroup` entry now carries `:kind`
  (`:type` or `:recipe`) and `:name`, the name in whichever of the palette's
  two maps it came from. `:type_name` is unchanged on a type entry and absent
  on a recipe entry, which has no type name at all.
