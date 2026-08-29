### Added

- The editor takes an optional `datamodel` assign - the paths the host
  declares - and reports a config field whose declared datamodel path is not
  among them as an `:info` finding in the findings panel; with no datamodel
  supplied nothing is produced.
- Block types may declare a config field with `datamodel_path?: true`, saying
  its value is a path into the host's datamodel; `core.assign`'s `path` field
  carries it.
