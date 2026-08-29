### Added

- The editor draws a `ONE OF` pill above a container whose body slots are
  alternatives and an `ALL OF` pill above one whose lanes run concurrently,
  which is the only place that distinction is stated on the canvas.
- `StatifierBlocks.ViewModel.arrangement/1`, `body_slots/1` and `fan_label/1`
  derive how a container arranges its body slots, shared by the renderer and
  the connector geometry so the layout and the lines cannot disagree.
- `StatifierBlocks.Connectors.fan_anchor/1` and `join_anchor/1` name the two
  markers a fan leaves from and rejoins at, so an edge is no longer drawn
  through the words that say what it means.
- `--sb-card-width` sets the width of a block's card, which is what keeps the
  measured connector geometry from collapsing every edge onto one spine.

### Changed

- A container with more than one body slot now lays its slots out side by side
  and fans into them, as a container declaring `layout: :columns` already did -
  a branch's arms no longer stack full-width with each fan edge running down
  through the arm above its target.
- Columns are a CSS grid taking their natural heights, cards are a fixed width
  centred in the box they sit in, and a column's header is card-width and
  centred over the first card it governs.
- The "+" between two blocks is now the insertion marker: subtle at rest,
  highlighted on hover, on keyboard focus and for the whole of a drag, and
  drawn as a placeholder ring in a slot that is still empty. It is the same
  button with the same events, so nothing about the keyboard path changed.
- `StatifierBlocks.Editor.Slot` stamps `data-empty`, and
  `StatifierBlocks.Editor.BlockNode` stamps `data-container` and
  `data-arrangement`, on the markup a host may style against.

### Removed

- The stub exit tick a rail drew below itself in CSS. The exit edge is
  measured and drawn now, and a fixed-length mark beside it was a second claim
  about the same thing that pointed somewhere else.
