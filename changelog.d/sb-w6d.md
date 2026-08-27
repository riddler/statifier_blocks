### Added

- The `core.*` structural block types (ADR-0002 decision 10), one `StatifierBlocks.BlockType` module each: `StatifierBlocks.Core.Sequence`, `.Group`, `.Branch`, `.Parallel`, `.Wait`, `.ResumableGroup` and `.OnEvent`. `core.branch` derives one slot and one `:expression` field per declared arm, `core.parallel` one slot per declared lane, and each type is the authority on its own config through `validate_config/1`.
- `StatifierBlocks.Palette.core/0` and `StatifierBlocks.Palette.core_types/0`: the core vocabulary as a palette, and as the plain `type_name => module` map a host merges its own entries into.
- Structural placement through ADR-0003 decision 3 kind tags: `core.on_event` declares `kinds: [:interrupt_handler]` and the group types accept only that kind in their `interrupts` slot, so an interrupt handler is admitted there and refused everywhere else, and an ordinary step is refused there - in both directions, from the declarations alone, with no special-cased rule.
- `fixtures/0` on `core.branch` (an arm condition evaluated against two datasets) and `core.on_event` (one example event payload). The bundle shape follows an amendment to ADR-0002 decision 9 that is not yet accepted, and is documented as provisional until it is.

### Changed

- `emit/2` on every core type returns `{:error, {:not_implemented, block_id}}` until the compiler lands. It is a deferral, not a failure mode: nothing in this package calls `emit/2` yet.
