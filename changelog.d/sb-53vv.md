### Added

- A block type may declare its instances returnable steps with the optional `returnable?/1` callback (config in, boolean out), read through `StatifierBlocks.BlockType.returnable?/2`, which answers `true` only for exactly `true`; `use StatifierBlocks.BlockType` does not inject it, so a type that changes nothing is unaffected.
- `StatifierBlocks.Palette.new/2` raises `ArgumentError` for a composite that declares `returnable?/1`, and for a declaring type whose answer for a fresh block's config is not a boolean or raises, throws or exits.
- A palette entry in the view model carries `returnable: true` when its type declares `returnable?/1`, and the palette browser draws that entry with `data-returnable="true"` and a "Returnable step" marker.
