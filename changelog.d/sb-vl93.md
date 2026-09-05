### Added

- A palette entry may declare `singleton: :head | :anywhere`, saying how many
  blocks of its type a document may hold and, for `:head`, that the one it
  holds is first in the root's first declared slot. A document that does not
  comply draws one `:config` finding per violating type, anchored on the root
  block, so a host gets "exactly one of this, at the top" without writing a
  validator of its own. Read it with `StatifierBlocks.BlockType.singleton/1`.
  Nothing is inserted, removed or moved on the author's behalf - the editor
  says what is wrong and the author acts. An entry that omits the key, or
  declares a value this package cannot read, is unconstrained exactly as it
  is today.
