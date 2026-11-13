### Added

- `core.await` takes an optional `timeout_capture` map from a datamodel path to a `["const", value]` literal, written as bare `<assign>`s on the deadline's transition, so a chart can record that a wait timed out; `capture` still writes on the awaited transition only.
- An await that already stored a well-formed `timeout_capture` key now compiles to its assigns, and one whose `timeout_capture` is malformed is refused at compile.
