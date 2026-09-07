### Added

- Block types may declare an optional `sentence/1` callback, which answers the
  block as one line of prose for a given config. It is read through
  `StatifierBlocks.BlockType.sentence/2`, which is total: a type that declares
  none, and one whose callback raises, throws, exits or answers a non-string, a
  blank string or a multiline one, all read as the type's label. Unlike a chip
  it carries no length cap.
- `use StatifierBlocks.BlockType` injects an overridable `sentence/1` answering
  the type's own palette label, so a type that overrides nothing is
  indistinguishable from one that declares no `sentence/1` at all.
- `StatifierBlocks.ViewModel.Node` carries `sentence`: the type's own sentence
  where it declares a usable one, else the author's `title`, else the type's
  label falling back to the type name. A block whose type the palette cannot
  resolve carries the type name, so a list view never draws a blank line.
- `StatifierBlocks.ViewModel.outline/1` returns the document in reading order:
  one `{node, depth, kind}` per block, pre-order, `kind` in
  `:step | :arm | :rail | :tray`. It is pure and reads only the view model.
  Every block appears exactly once - arms, rails, trays and the drafts shelf
  are kinds and positions, never omissions - and `depth` is block nesting
  depth, so a slot never consumes a level.
- `core.wait`, `core.branch`, `core.subchart`, `core.foreach`, `core.parallel`,
  `core.send` and `core.assign` declare sentences of their own. Every other
  `core.*` type answers its label, which is what it answered before.

Cards are unchanged: `sentence` is not a chip, is never capped, and nothing new
is drawn on a block's card or in the palette browser.
