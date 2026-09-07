### Changed

- `StatifierBlocks.Palette.new/2` refuses two entries of one palette-browser
  group that declare the same `order`, raising the `ArgumentError` naming both
  entries that `from_modules/2` already raised, so a palette built by merging
  onto `core_types/0` meets the same refusal; the fix is to renumber one of the
  two entries, and the moduledoc's "Ordering a group" states the convention.
- Both builders now admit one pair at a single `order`: a composite's `types`
  entry beside that same composite's own derived `<Module>.Recipe`, whose
  `palette_entry/0` is the block type's. Registering both stays the host's
  choice to show two entries; `from_modules/2` used to refuse it.
