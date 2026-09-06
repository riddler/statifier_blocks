### Added

- A `{:path, opts}` field declares what it reads and writes at its path:
  `expects: T` is a read signature the environment at the block's position
  must satisfy, and `writes: T` puts `T` there for every block after it.
  Both keys are optional, and a field carrying neither behaves exactly as it
  did - a write of `:unknown`, known but untyped, that refuses nothing.
- `field_candidates`, the values a host offers for one field, keyed
  `{type_name, field_key}`. A `:string` field with a closed list -
  `[{value, label}]` - renders a `<select>`; an open one -
  `{:open, [{value, label}]}` - renders the text input with a `<datalist>`;
  no list renders the input the field already had. It draws a control and
  decides nothing: `validate_config/1` is still the only authority on a
  value, and a stored value a closed list does not offer is drawn as its own
  option rather than silently rewritten. It is an editor assign and a
  `StatifierBlocks.Compiler.compile/3` option, where a value outside a
  closed list is a **warning** on the compiled artifact and never an error.
- `core.on_event`'s `capture` has an authoring surface: a repeated
  two-control row, one row per pair - the datamodel path written beside the
  path read inside the firing event's payload - with the source control
  offered the block type's own `fixtures/0` payload for the configured
  event. There is always one blank row at the end, which is what adds a
  pair; clearing both controls of a row removes one. The key was authored
  through the document before this and had no control at all.
- A capture's target paths reach the declared-path advisory, anchored on the
  `capture` key. They are datamodel paths that no field declaration names,
  so the pass covering every other datamodel path could not see them.

### Changed

- `core.subchart`'s `assign_to` accepts a **datamodel path**, not only a
  bare lowercase identifier: any non-empty string with no whitespace in it,
  which is exactly what `core.assign` accepts for the path it writes. The
  validation and the emission widen together. It is a widening and nothing
  else - a bare identifier is a one-segment path, so every document that
  validated before still validates and compiles to the same bytes - and it
  settles the field offering dotted candidates its own validation refused.
  The identical refusal on an `<assign>` location elsewhere in the
  vocabulary is untouched.
