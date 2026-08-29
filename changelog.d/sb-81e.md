### Added

- A `core.subchart` block type: a step that runs another chart and waits,
  routing `done.invoke` on the outcome the child reported
  (`_event.data.outcome`) to one slot per declared outcome, with
  `core.invoke`'s `on_error` slot unchanged for a failed invocation.
- `StatifierBlocks.Compiler.compile/3` accepts `child_use: true`, which
  compiles a document for use as another chart's child: the emission gains
  one top-level `<final>` per outcome the root block declares, carrying that
  outcome name as done data, so a parent session can see which way the child
  finished.
