### Changed

- `core.wait` accepts a predicator duration string (`1h30m`, `2d`, `3d8h`) as
  well as ISO-8601, stores whichever spelling the author typed, and compiles it
  to the emitted `delay` attribute; its refusal message names both spellings.
