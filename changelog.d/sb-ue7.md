### Added

- `StatifierBlocks.Assignability.seam_reason/4`, `finding_reason/2` and
  `seam_reasons/3` name why a data-flow seam came out the way it did:
  `:not_assignable` and `{:fixable_by, block_id}` for a refusal, and
  `:source_untyped` / `:target_untyped` / `:both_untyped` for a seam that
  passed only because a block declared no type. `seam_reasons/3` is how a
  host finds the parts of its palette it has not typed yet.
- `StatifierBlocks.Assignability.target_verdicts/4` returns every position
  `valid_targets/4` enumerates with its full verdict, and
  `StatifierBlocks.Edit.Targets.slot_verdicts/3` projects those to slots -
  the accepting ones and the reason each refusing one gives.
- The editor stamps a refused slot's reason as `data-drop-reason` beside
  `data-drop`, so a hover affordance can explain a refusal with no
  round-trip and no JavaScript.

### Changed

- Reasons change no verdict: `:unknown` stays permissive in both positions,
  `Assignability.validate/3` reports exactly the findings it did before, and
  neither finding tuple gained a field.
