### Changed

- A read-check `:type_mismatch` whose disagreeing writer is a block a
  composite minted for its own expansion now names the composite the author
  placed, by that composite's sentence, instead of naming an id the author
  cannot see, select or edit. A writer the author did place - including a
  block dropped into a composite's pass-through slot - is still named by its
  own id.
- The finding's reason tuple is unchanged: it still carries the minted id, so
  a fixture run and the Source tab still say which member of the expansion
  wrote the entry.
