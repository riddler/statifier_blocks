### Added

- A host's `field_candidates` list is honoured on `{:path, opts}` and
  `:expression` fields as well as `:string` ones: either spelling draws a
  `<datalist>` the input is bound to, ahead of the declared datamodel paths,
  and the value stays typed by the control.
