### Added

- A composite block type may implement an optional `declared_outcomes/1`
  callback and have its outcomes read from each instance's own config, so one
  type can stand for blocks that finish in different ways.

### Changed

- Every reader of a composite's declared outcome list now reads the list of the
  block in hand. A composite declaring `outcomes:` statically, and one
  declaring nothing at all, behave exactly as before.
