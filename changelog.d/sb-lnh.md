### Added

- Block types may export an optional `summary/1`, returning `nil`, a short
  string, or a list of chips, which the editor draws as a card's second line
  when the author has not named the block. It is read through
  `StatifierBlocks.BlockType.summary/2`, which normalises every shape to a
  chip list and drops an over-long chip rather than truncating it.
- `core.parallel`, `core.wait`, `core.on_event`, `core.send` and `core.branch`
  summarise themselves on the card: lane names, `timer <duration>`, the outcome
  and the event, the event, and `N arms + otherwise`.

### Changed

- `StatifierBlocks.ViewModel.Node` carries a `summary` field, and
  `ViewModel.subtitle/1` returns it for a block whose title is its type's. A
  block the author has named still reads its type's label there.
