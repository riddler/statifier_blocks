### Changed

- The compiler replaces a composite block with its expansion at the Resolve
  stage, so a document holding a composite compiles to bytes identical to the
  same document with that composite expanded in place.
- A finding raised inside an expansion is reported against the composite
  block, carrying the key of the param that produced it or no key at all, and
  the provenance map still owns every span by the expanded block that emitted
  it.

### Added

- A `:composite_expansion_failed` finding at the `:resolve` stage reports a
  composite whose declaration cannot be expanded, in place of the raise.
