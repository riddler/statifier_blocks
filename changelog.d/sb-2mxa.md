### Changed

- A block type's `summary/1` chips draw as a row of separate chips under the
  card's title (`.sb-node__summary`, one `.sb-node__chip` per chip) instead of
  one string joined with `", "`; the row wraps, and a type declaring no summary
  draws no row at all.
- `StatifierBlocks.ViewModel.subtitle/1` answers only the type label an author-
  named card carries, and `nil` otherwise. Read the chips from the new
  `StatifierBlocks.ViewModel.summary_chips/1` instead of the joined string.
