### Added

- `StatifierBlocks.Palette.preflight/1` lists every host type in a palette whose own defaults, or the block `Palette.new_block/2` builds from them, disagree with their declared field types, each finding naming the type, the field's key, its declared type and the value; `preflight/2` also lists every block of the given documents whose config its type's declared field types refuse, by block id. A type whose callbacks raise is a finding, never a raise.
