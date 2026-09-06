### Added

- A palette entry may declare `default_config`, the config the editor's insert
  probe is built with over `config_schema/1`'s own defaults, so a block type
  whose read is declared on a path field says which path it will read before
  anyone has configured one.

### Fixed

- Dragging or picking a block type whose read is declared on a config field now
  greys the slots that would refuse it. The probe carried only the schema's
  defaults, and a path field defaulting to `""` names no path, so such a type
  declared no read at insert time and every slot accepted it.
