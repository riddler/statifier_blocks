### Fixed

- A `core.subchart` outcome-routing condition is no longer attributed to the
  `outcomes` config field, so a chart finding landing inside it reports
  `fault: :package` with no `config_key` rather than blaming the author for
  bytes the compiler composed.
