### Added

- `use StatifierBlocks.Runtime.Subchart` declares the canonical
  `statifier_blocks:subchart` invoke handler for the in-memory
  `Statifier.Session` case: the host supplies a document resolver and a
  palette, and the generated module resolves the chart a `core.subchart`
  names, compiles it as a child, and starts it as a child session. Refusals
  surface on `error.communication.invoke` with a stated reason -
  `unknown_document`, `child_compile_findings`, or `cycle_refused`.
- `StatifierBlocks.Runtime.Subchart.handlers/1` builds the `:invoke_handlers`
  map for `Statifier.Session.start_link/2`.
