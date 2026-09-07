### Added

- `StatifierBlocks.Palette.new_block/2` builds a block of a named type from a
  palette - the type's `config_schema/1` defaults as the config and its
  `current_version/0` as the stored version - so a host view that inserts from
  a palette no longer has to reimplement what the editor's insert does.
