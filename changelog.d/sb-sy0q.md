### Added

- A `:type_mismatch` finding names a declared type by its **label**. A pair
  of names the datamodel document's `types` key declares reads as the two
  human names an author recognises; a pair of opaque spellings a host
  carries reads exactly as it did before there were declarations. The rule
  is one function, `StatifierBlocks.Environment.type_label/2`, so the
  finding and the editor cannot disagree about what a type is called.
- The drawer's Datamodel tab answers **what is known here**: the paths the
  environment holds at the selected block's position, with their types, as
  computed by the pre-order walk at that exact position - before the block's
  own writes land. Nothing selected and nothing known are two different
  states and the panel says which it is.
- The same tab lists the **declared records and shapes**, each with its
  ordered fields, their types and their required marks, through
  `StatifierBlocks.Datamodel.declared_types/1`. An author told that a record
  does not cover a shape can now read what that shape requires without
  leaving the editor.

### Fixed

- The editor's drop check consults the datamodel document the editor already
  holds, instead of asking the data-flow question with an empty context. The
  coverage step - a record satisfying a shape by covering its required set -
  could not run there, so a placement the compiler accepts was drawn as
  refused. `StatifierBlocks.Edit.Targets.droppable_slots/3`,
  `droppable_slots_for/3` and `slot_verdicts/3` each take an optional
  context as a fourth argument; called with three, every one of them behaves
  exactly as it did.
