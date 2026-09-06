### Added

- `StatifierBlocks.Palette.manifest/1` returns a palette as a sorted list of
  `{name, version}` entries - a block type beside its `current_version/0`, a
  recipe beside `:recipe` - so a host pins what its palette carries in one
  assertion that names the entry which moved instead of a count that does not.
