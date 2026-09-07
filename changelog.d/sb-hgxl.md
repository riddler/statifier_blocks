### Added

- The editor replaces a selected composite block with the blocks it stands
  for. The control sits on the composite's own card, reads "Replace with its
  steps", and commits the removal and the expansion's inserts as one compound
  edit: one undo puts the composite back whole, and the document it writes is
  the one `StatifierBlocks.Composite.expand/2` answers, so the chart compiles
  to the same bytes on both sides of the gesture.
- The gesture is refused, and nothing is written, when the slot the composite
  sits in will not admit the blocks that come out of it.
