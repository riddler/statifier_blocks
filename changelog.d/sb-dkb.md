### Changed

- `core.wait`'s declared `duration` default is now the predicator string
  `1h` rather than the ISO-8601 `PT1H`, so a newly inserted block starts
  from the spelling an author types. Both spellings stay accepted and each
  compiles to the same `delay` attribute, so no chart's emitted SCXML
  changes and no stored document has to be retyped.
