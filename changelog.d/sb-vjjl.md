### Added

- A write signature whose type is a record, a shape, or an inline shape now
  puts an entry in the environment at every member beneath the path as well as
  at the path itself, recursively and to any depth, so a later block reading a
  nested path is checked rather than given the nothing-is-known advisory.

### Changed

- A document may stop validating where a block reads a nested path the record
  written above it types differently; the fix is either the reading block's
  `expects` or the written record.
