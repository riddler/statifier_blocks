### Changed

- A `:duration` config field renders as one text control taking predicator
  duration strings, with `30s`, `15m`, `1h30m`, `2d` and `3d8h` shown beside
  it; ISO-8601 is still accepted and the author's string is stored verbatim.
- An empty `:duration` field omits its config key rather than storing an empty
  string, so a cleared field and a never-set field are the same value.

### Added

- `StatifierBlocks.DurationInput` reads a typed duration for that control,
  accepting exactly what `StatifierBlocks.Core.Duration` compiles and naming
  the limit a refused value hit.

### Removed

- `StatifierBlocks.Editor.Field.units/0`, `format_duration/2` and
  `parse_duration/1`, which served the retired value/unit control. Call
  `StatifierBlocks.Core.Duration.to_iso/1` to canonicalise a stored duration.
