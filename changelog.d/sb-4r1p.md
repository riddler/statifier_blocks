### Changed

- **Breaking.** A `:duration` field reads one grammar: the duration strings
  `Predicator.Duration` parses, such as `30s`, `1h30m`, `2d` and `3d8h`. Any
  other spelling is a format finding.

  *Migration: a `core.wait` `duration` or a `core.send` `delay` stored in
  ISO-8601 - `PT30S`, `PT1H30M`, `P1D` - no longer validates. Rewrite the
  value in the unit spelling above; `PT1H30M` becomes `1h30m`, `P1DT6H`
  becomes `1d6h`, and the compiled chart is byte-identical either way.*

- `StatifierBlocks.Core.Duration.to_delay/1` now takes the normalised
  duration `parse/1` returns rather than a canonical string.

### Added

- Sub-second and fractional durations are expressible in a `:duration` field
  for the first time: `500ms` and `1.5s` both validate and both compile to a
  `delay` the engine resolves. The recogniser that stood between them and the
  engine is gone.

### Removed

- `StatifierBlocks.Core.Duration.to_iso/1` and
  `StatifierBlocks.Core.Duration.predicator?/1`. With one grammar in and one
  attribute out there is no intermediate form to canonicalise to, and no
  narrower predicate to hold beside `duration?/1`. Callers that compiled a
  stored value should use `parse/1` and then `to_delay/1`.
