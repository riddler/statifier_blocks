### Fixed

- A summary chip whose text is a single identifier - `signup.reminder_due`
  - no longer breaks mid-token onto a second line. The chip keeps one line
  and clips at its own edge with an ellipsis, which is the treatment the
  invoke type on the line below it already used. The card's title keeps its
  wrap: a title is prose an author wrote, not an identifier.
- The canvas stage is now at least as wide as the tree it holds
  (`min-width: min-content`). Its box took the panel's width, while the
  tree has a floor of its own - nesting paddings, the interrupt channel, a
  card that will not shrink past its token width - so a panel narrower than
  that floor left the stage short of its own content, and everything read
  off that box, the measurement hook's `offsetWidth` included, was short
  with it.
- `Connectors.fan_path/3`, `Connectors.join_path/3` and
  `Connectors.interrupt_path/4` now clamp an ascending edge level, as
  `flow_path/3` already did: the head is raised to the tail's own `y`
  rather than routed upward. An arrowhead is oriented along its path, so an
  ascending arm rendered an arrow pointing back at the block the flow just
  left - a loop the document does not contain.
