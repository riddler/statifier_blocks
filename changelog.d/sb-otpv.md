### Added

- `core.map` declares `item_as` and `index_as` - the names a child run sees its item and its position under, defaulting to `item` and to no position name - and carries both into its `<invoke>` beside the list's path, so a child recipe reads what the author named rather than whatever the fan-out handler chose.

### Changed

- A `core.map` compiled before this release gains an `item_as` param carrying the default name; a stored config that never had the key still validates and needs no migration.
