### Added

- A condition's value picker now offers what the datamodel declares. A path
  whose ADR-0006 entry carries `one_of` gets those values by default, with no
  `value_candidates` map supplied; a host entry for a path replaces the
  derived list for that path and leaves every other path's default in place.
  `StatifierBlocks.Datamodel.value_candidates/2` is the derivation, and
  nothing validates against the list - `one_of` stays a hint.
