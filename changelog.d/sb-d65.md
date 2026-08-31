### Added

- `core.on_event` takes an optional `cond`: an `:expression` config field
  that becomes the guard on the handler's transition, so an interrupt rule
  fires only when its event arrives *and* the condition holds. A handler
  whose `cond` is absent, empty, or whitespace emits exactly the bytes it
  emitted before the key existed, so the key is additive over every
  document authored without it. The condition is passed through to
  predicator verbatim - `validate_config/1` only asks that the stored value
  be a string - and the transition carries `"cond"` as its attribution key,
  so an upstream expression error lands on the field the author typed into.
  Recorded as ADR-0002's 2026-08-31 note.
