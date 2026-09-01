### Added

- The editor's drawer carries a third tab, Declarations, where an author
  adds, edits, reorders and removes the document's own `datamodel` roots
  (ADR-0001 decision 11's entries: `id`, `expr`, `description`).
- `StatifierBlocks.Edit` gains a fifth command,
  `{:set_datamodel, entries}`, which replaces the document's whole
  declaration list and whose inverse is the list that was there before, so
  a declaration edit undoes and redoes like any other. It refuses a list
  `StatifierBlocks.Document.validate/1` would refuse, in the same
  `{:malformed_envelope, {:datamodel, reason}}` family.
- `StatifierBlocks.Declarations`, the pure list-to-list arithmetic behind
  the panel: `add/1`, `remove/2`, `move/3`, `put/4`, `change/3`,
  `count/1` and `refusal/1`.
