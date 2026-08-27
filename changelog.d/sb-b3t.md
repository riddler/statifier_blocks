### Added

- `StatifierBlocks.Assignability`: the one decision function for whether a block may land in a slot, checking structural admission by kind tag and data-flow compatibility by type-expression identity plus an optional host-supplied widening relation (ADR-0003). `check/5` decides a single candidate position; `valid_targets/4` lists every position a candidate may occupy in a document; `validate/3` reports every finding already present in a document; `inbound_type/4` and `assignable?/3` are the two primitives both are built from.
- `StatifierBlocks.Assignability.Relation`: the behaviour a host implements to widen data-flow compatibility beyond exact type-expression identity. A host module can only grow the accepted set, never shrink it.
- `StatifierBlocks.Palette` gains an `assignability` field naming the host's `Assignability.Relation` module, set via `Palette.new(types, assignability: MyApp.Blocks.Types)`. Defaults to `nil`, meaning no widening relation is declared; existing calls to `Palette.new/1` are unaffected.

### Changed

- `c:StatifierBlocks.BlockType.io/1`'s return type is now `StatifierBlocks.Assignability.io/0` instead of `term()`. Every core block type already returns a value of this shape; a custom block type implementing `io/1` should confirm its return value conforms.
