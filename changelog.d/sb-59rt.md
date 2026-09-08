### Fixed

- The "Save as a step" control and its marking tray are no longer drawn on a
  mount that registered no `on_collapse` callback, and the four events the
  gesture is made of are answered with the socket unchanged there. The
  gesture's only outcome is that callback, so a mount without one offered a
  marking step, a Save, and then silence. "Replace with its steps" is
  unaffected in both directions: it commits an edit the editor makes itself.
- The card's controls no longer draw on top of a title that wrapped to two
  lines. They sit in a reserved control strip beside the title - a grid
  column of its own, held whether or not the controls are revealed - so a
  long name wraps beside them and nothing truncates.

### Changed

- The card's controls moved into a `.sb-node__strip` element inside
  `.sb-node__chrome`. A host stylesheet or test selecting
  `.sb-node__chrome > .sb-node__remove`, `> .sb-node__expand`,
  `> .sb-node__save-step`, `> .sb-node__fold` or `> .sb-node__offer` should
  select `.sb-node__chrome > .sb-node__strip > ...` instead. The classes, the
  `data-reveal` contract and the events are unchanged, and the strip is drawn
  on every card. Within it the controls are in left-to-right order, so a
  keyboard now reaches Save before Expand.
- `StatifierBlocks.Editor.Canvas.canvas/1`, `.Slot.slot/1` and
  `.BlockNode.block_node/1` take a `collapsible` attr, threaded the way
  `expandable` is; it is `false` by default and the editor passes whether its
  `on_collapse` assign is a one-arity function.
