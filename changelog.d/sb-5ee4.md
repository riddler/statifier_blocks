### Added

- A composite declaration may carry `outcomes`, a list of outcome names it
  declares for itself, on both the `use` form and the data form. Present, the
  list replaces the expansion root's derived outcomes - each name labelled by
  the member that raises it - and the compiler checks at Resolve that the
  expansion can raise every declared name, reporting an
  `:outcome_not_raisable` finding against the composite block when it cannot.
  Absent, nothing changes: a document that writes no `outcomes` key compiles
  to the same bytes as before.
