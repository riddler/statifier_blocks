### Fixed

- A document whose blocks were built before blocks had a note, and that a
  host kept as a stored Erlang term rather than as JSON, now encodes and
  validates as a note-free document instead of raising `KeyError`.
