### Added

- `StatifierBlocks.Datamodel.candidates/3` returns the declared datamodel
  paths, unioned from the host's datamodel, the compile call's `:declare`
  roots and the document's own `datamodel` key, sorted and deduplicated.
- `StatifierBlocks.Datamodel.candidates_under/2` narrows those candidates to
  a prefix, in the datamodel document's own order.
- An `:expression` config field offers the declared paths as a `<datalist>`,
  suggesting without constraining; supplying no datamodel renders the plain
  input unchanged.

### Changed

- The `expression_component` override now receives a `:candidates` key
  alongside `:field`, `:id`, `:name` and `:value`. Existing overrides read
  the keys they know and are unaffected.
