### Added

- A `StatifierBlocks.Composite.Data` declaration may carry a `"migrations"` list: ordered `rename` / `drop` / `default` steps, each keyed by the `type_version` it migrates from. `migrate_config/3` walks every step at or above the stored version and below the declaration's `"version"` in one call, so a block saved against an older revision of a saved composite resolves instead of being refused.
- The whole chain is validated at `declaration/1`, entry-build time: a step of the wrong shape, a step carrying none of the three parts, a key named by both `"drop"` and `"default"`, a duplicate, out-of-order or gapped `"from"`, a chain not ending at `"version" - 1`, and a step naming a key the declaration's own params do not account for are each refused before the entry reaches a palette.

### Changed

- A block stored below a declaration's earliest migration step still answers `{:error, {:no_migration_from, from}}`, and so does every stored version of a declaration that writes no `"migrations"` key - the previous behaviour, unchanged. A module composite is untouched: `use StatifierBlocks.Composite` gains no `migrations:` option and still writes `migrate_config/2` itself.
