### Added

- `use StatifierBlocks.InvokeStep, failure_outcomes: [...]` declares a step
  family's failure class once at the `use` site, so a host whose steps all
  fail the same way no longer writes `failure_outcomes/1` on every member.
