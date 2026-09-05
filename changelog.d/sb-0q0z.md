### Added

- `core.on_event` takes an optional `capture` map: each pair writes one value
  out of the firing event's payload into the datamodel, the key naming the
  datamodel path written and the value the path inside `_event.data` it is
  read from. The pairs compile to one `<assign>` each on the handler's own
  transition, ahead of the raise that carries the outcome, ordered by their
  datamodel paths so a document compiles to one byte sequence. A handler
  without the key, or with an empty map, compiles exactly as it did before
  the key existed. A source path the payload does not carry is written as the
  interpreter's explicit unbound marker rather than `nil`, so a consumer of a
  captured path tests for that marker. The key has no editor control yet -
  the field-type set has no member describing a map - so it is authored
  through the document.
