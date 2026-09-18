### Added

- A composite block type may implement an optional `declared_outcomes/1`
  callback and have its outcomes read from each instance's own config, so one
  type can stand for blocks that finish in different ways.

### Changed

- Every reader of a composite's declared outcome list now reads the list of the
  block in hand. A composite declaring `outcomes:` statically, and one
  declaring nothing at all, behave exactly as before.
- **Breaking:** `StatifierBlocks.Composite.unraisable_outcomes/4` is now
  `unraisable_outcomes/5`, taking the block's config as its third argument;
  a caller passes the config of the block it expanded, between the type ref
  and the expansion members.
