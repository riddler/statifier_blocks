### Added

- A `core.on_event` capture pair may take a literal source, written
  `["const", value]` in the block document, so a handler records a value the
  document states rather than one the firing event's payload has to carry; a
  string source is still the payload path it has always been, and the two are
  told apart by shape.
