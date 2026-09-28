### Added

- `StatifierBlocks.Schema.for_palette/1` answers a draft-07 schema for a palette: the shipped root with every block also judged by its own type's definition, a `core.*` type's from `definitions/core` and a host type's generated from its declared `config_schema/1` and `slots/1`, each declared field typed from its declared field type.
