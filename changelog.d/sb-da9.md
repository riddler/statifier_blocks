### Added

- `StatifierBlocks.SlotValidation`, a palette-aware whole-document check for
  a block's declared slots (`:undeclared_slot`) and each declared slot's
  arity (`:slot_arity_violated`).

### Changed

- The compiler now refuses a document whose slots violate their declared
  arity or name a slot the block type does not declare, instead of silently
  dropping those children from the emission.
