### Added

- The editor draws the join marker under a container whose slots sit side by
  side, reading the words the block type's `join_label` callback returns -
  `core.parallel` completing on its first lane says "continue at first" - and
  falling back to the editor's own word for a type that declares none.
- `StatifierBlocks.ViewModel.Node` carries `join_label`, the normalized words
  that callback returned for the block's config, or `nil` when it declared
  none.
