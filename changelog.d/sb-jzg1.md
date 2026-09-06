### Removed

- `StatifierBlocks.Predicates.Datamodel` is gone. The datamodel document's
  path/type index moved to the `statifier_datamodel` package as
  `StatifierDatamodel.Index`, which carries the same functions under the same
  names (`index/1`, `declared_paths/1`, `sensitive_paths/1`, `datamodel/1`,
  `entries/1`, `fetch/2`, `type/2`, `declared?/2`, `under/2`); a caller
  swaps the module name and nothing else.

### Changed

- `StatifierBlocks.Datamodel` reads the datamodel document through
  `statifier_datamodel` rather than through an index of its own.
  `declared_paths/1`, `candidates/3`, `candidates_under/2`,
  `value_candidates/2` and `declared_view/3` keep their signatures and their
  behaviour; what changed is where the projection lives.
- The declared type set gains `date` alongside the eight it already carried,
  because the re-homed record widened it. A document that used no `date`
  entry is unaffected.
