### Added

- A block type may class one of the outcomes it declares as a **failure** through the new optional `failure_outcomes/1` callback, and the compiler emits a reserved `<donedata>` param - `statifier_persistence:run_status` with the value `failed` - on that outcome's top-level `<final>` under both the `:child_use` and the `:terminate` compile options, so a durable stepper can tell that a chart finished badly rather than merely finished. `core.map` and `core.subchart` class their `error` outcome; every other type classes nothing.

### Changed

- A document whose root block is a `core.map` or a `core.subchart`, compiled with `child_use: true` or `terminate: true`, gains the reserved param on its `error` final. Its content hash changes with it, so it is a different chart revision under statifier-ex ADR-0052 - the same one-time choice opting into `terminate` already is. Every other document compiles to the bytes it compiled to.
