### Added

- `StatifierBlocks.Editor` takes a `publish_status` assign, `nil` or
  `%{live: n, class: class}` with `class` one of the four classes
  `Statifier.Chart.diff/3` returns, and draws it as one line beside the
  `:header` slot, such as "3 live executions on the previous revision; this
  change is compatible". The host computes both values and the editor makes
  no query; `nil`, the default, renders exactly what the editor rendered
  before.
