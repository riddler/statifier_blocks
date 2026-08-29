### Added

- `core.parallel` accepts a `complete` config key choosing when the block
  is done: `"all"` (the default, and what a document stored before the key
  reads as) keeps the shipped rule, and `"first"` compiles the racing rule
  - one transition per lane on the `<parallel>` element itself, taken on
  that lane's own completion event and targeting the block's done final,
  so the block finishes at the first lane's completion and the engine
  exits the losing lanes with their `<onexit>` content and one
  `CancelInvoke` per live invocation.
- `StatifierBlocks.Core.Parallel.join_label/1`, declared on the type's
  palette entry, so a renderer draws "continue at first" or "continue when
  all" from the block's config without learning the type's name.

### Fixed

- A delayed `core.send` in the body of a `core.group` that carries
  interrupt rules is now cancelled when the group is abandoned. Its
  `<cancel>` is emitted in the body region's `<onexit>` rather than the
  group's own, and abandoning the group exits the region without exiting
  the group, so the old placement never fired.

### Changed

- A delayed `core.send` armed inside a region now has its `<cancel>`
  emitted in that region's `<onexit>` rather than the enclosing block's -
  the nearest enclosing `<state>`, whichever it turns out to be. Charts
  with a delayed `core.send` inside a `core.parallel` lane (under either
  completion rule) or inside an interruptible `core.group`'s body change
  bytes; every other chart is unchanged.
