### Added

- `StatifierBlocks.Predicates.Datamodel` indexes a datamodel document - the
  typed, three-scope declaration sb ADR-0006 defines - into a path/entry
  index: the type of a path, the entries under a prefix, whether a path is
  declared, and the record's one total derivation of the declared-path set.
  The index is advisory; an undeclared path is unknown, never wrong.
- `StatifierBlocks.Datamodel.declared_paths/1` accepts such a document as a
  fourth shape, alongside `nil`, a list and a `MapSet`, and projects it
  through that derivation. A document declaring no entries normalizes to the
  empty set - a host claim - rather than to `nil`, which stays reserved for
  no datamodel at all.
