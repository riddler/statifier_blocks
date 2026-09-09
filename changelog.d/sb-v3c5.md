### Added

- `StatifierBlocks.Assignability.assignable?/5` takes an options keyword whose
  `strict: true` refuses a pair either side of which resolves to `:unknown`,
  for the caller that must not admit a value nothing has typed. The host
  relation is not asked about an unknown side.
- The option defaults to `strict: false`, so `assignable?/3` and
  `assignable?/4` decide exactly what they decided before.
