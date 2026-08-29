### Added

- `StatifierBlocks.Compiler.compile/3` accepts `terminate: true`, which emits
  one top-level `<final>` per root-block outcome with no `<donedata>`, so a
  compiled root document reaches `:done` when its root block completes;
  without it a root document never terminates, and passing it together with
  `child_use: true` is refused with an `:emit` finding.
