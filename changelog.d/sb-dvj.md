### Added

- `StatifierBlocks.BlockType` behaviour: the nine-callback authoring-time extension seam (ADR-0002), five required (`slots/1`, `config_schema/1`, `validate_config/1`, `current_version/0`, `emit/2`) and four optional (`io/1`, `migrate_config/2`, `fixtures/0`, `palette_entry/0`).
- `StatifierBlocks.Palette`: a caller-supplied `type_name => module` value (ADR-0002 decision 2), with `new/1` to build one and a total `fetch/2` that returns `{:ok, module}` or `{:error, {:unknown_block_type, type_name}}` and never raises (ADR-0002 decision 3).
