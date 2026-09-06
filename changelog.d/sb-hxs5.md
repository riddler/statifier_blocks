### Added

- A failure-classed outcome a block below the document root leaves unhandled
  now reaches the document's own ending: under `child_use: true` or
  `terminate: true` the compiler emits one shared top-level `<final>`
  carrying the reserved `statifier_persistence:run_status` donedata param,
  and one transition into it per unhandled pair.
- `core.invoke` declares the two outcomes it has always emitted, `done` and
  `error`, so a parent may wire `done.outcome.<state id>.error` and the
  editor offers both on the outcome-event candidate list.

### Changed

- `core.invoke` classes its `error` outcome as a failure, and so does every
  host type built on `use StatifierBlocks.InvokeStep`. A host whose `error`
  is routine defines `failure_outcomes/1` returning `[]` beside its
  `outcomes/1` to keep the old classing.
- `core.invoke`, `core.map` and `core.subchart` emit their `error` outcome's
  `<final>` whether or not the failure slot is occupied; with the slot empty
  the failure transition targets that final directly instead of being
  selected by nothing. A document containing one of the three with an empty
  failure slot, one with an unhandled failure below its root under the two
  compile options, or a host `InvokeStep` type, compiles to different bytes
  and so is a new chart revision; every other document is byte-identical.
