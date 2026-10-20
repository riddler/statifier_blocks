### Added

- `core.await` takes an optional `capture` map with `core.on_event`'s semantics: each pair writes a value out of the awaited event's `_event.data`, or a `["const", value]` literal, into a datamodel path on the transition the event selects, and the editor draws the same "Capture from the event" rows for it. An await with no `capture` compiles to the same bytes as before; an await that already stored a `capture` key, which was ignored until now, compiles to its assigns, and a malformed one is refused.
