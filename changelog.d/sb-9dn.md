### Added

- The palette carries a count line under its search box: the size of the
  palette when nothing is filtering it, and how much of it is left plus what
  is doing the narrowing when something is - a query, or the acceptance set of
  the slot the palette was opened from.
- Each group header carries the number of rows currently under it, so a
  filtered section says how much of it survived the filter.

### Changed

- A palette row is now a tile, a name, and the type's description on a second
  line, at a row height that gives the description room to wrap. The tile is a
  slot rather than an icon: a block type that declared no icon still renders
  the box, so every name in the list lines up.
- A row's accent moved from a stripe down its leading edge onto the tile, which
  is where the card the pick produces carries it. The stamp itself is
  unchanged - a type that declares no accent token still gets neither the
  attribute nor the custom property.
