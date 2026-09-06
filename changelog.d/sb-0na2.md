### Added

- `core.on_event` takes an optional `payload` config key: the name of a type
  the datamodel document declares, saying what `_event.data` carries for the
  event that handler names. With one declared, a `capture` pair whose source
  path reads a member the payload does not carry is refused at compile - one
  `:config` finding on the `capture` key, naming the pairs and the payload -
  so the interpreter's unbound marker is never written for a captured path on
  a typed document. A handler with no `payload`, a `payload` naming a type the
  document does not declare, and a compile with no `:datamodel` are all
  unchanged: no new finding, and the same compiled bytes. `payload` itself
  emits nothing.
