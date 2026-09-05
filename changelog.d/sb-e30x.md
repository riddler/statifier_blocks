### Added

- A condition field now draws a hint beside its control, derived from the
  selected block's fixture rows. The exemplar is what the block's first
  fixture row in declaration order binds to the path the condition names, and
  every distinct value that path takes across the block's rows is listed on
  the hint's `title`. `StatifierBlocks.Shell.fixture_hint/3` is the
  derivation, over the `fixtures` the editor already holds.

  It is a hint and never an option: nothing reaches a picker, nothing is
  merged with `one_of` or with a host's `value_candidates`, and no value it
  shows can be selected. A block with no fixture rows, or a document with no
  fixtures source, renders exactly as it did before.
