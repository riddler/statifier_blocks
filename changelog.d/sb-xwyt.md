### Fixed

- `StatifierBlocks.Core.OnEvent.validate_config/1` answers `:ok` instead of
  raising `UnicodeConversionError` when a direct caller passes a `capture`
  literal that is not valid UTF-8; the encoding refusal stays with the
  compiler, which already refuses such a literal before the walk runs.
