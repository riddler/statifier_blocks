### Added

- `core.map`, the durable fan-out block type (ADR-0009): it runs another
  chart once per item of a datamodel list, all at once, and waits for the
  whole batch. The palette calls it "For every item, run a chart" - it sits
  beside `core.foreach`, which runs the blocks inside it one item at a time,
  and is not a mode of it. Four fields: `items` (the datamodel path holding
  the list), `chart` (the document id run for each item), `collect` (where
  the assembled answer is written, optional), and `on` (`all`, the default,
  or `first_error`). `items` and `collect` are `{:path, opts}` fields, so
  the editor offers the host's declared datamodel paths on both; `collect`
  accepts what `core.subchart`'s `assign_to` accepts, refused with the same
  wording. Any `on` outside the two permitted values is a config finding at
  authoring time, which is what reserves the word `quorum` for its own walk.
- It compiles to exactly **one** `<invoke>` of the constant type
  `"statifier_blocks:map"`, carrying the block's own id, the document id as
  `src`, and the four values as literal `<param>` children. The compiled
  bytes do not scale with the length of the list and cannot: the list is a
  runtime value the compiler never sees, so the params carry the *path* and
  the host's registered handler is what resolves it and starts the runs.
  Nothing about the size of a batch is validated here - a bound on it, if
  one is needed, is the fan-out runtime's to enforce and to refuse against.
  The type is deliberately a different string from
  `"statifier_blocks:subchart"`: a host that wired a single-child handler
  has not thereby wired a fan-out handler, and
  `StatifierBlocks.Compiler.InvokeTypes` reports that gap at deploy time.
- Two fixed outcomes, `done` and `error`, each with an optional slot
  (`on_done`, `on_error`), because N children report N outcomes and there
  is no branch target to be had by joining them - the per-child answers go
  to `collect` instead, and an author who wants to branch on them reads
  that list with a `core.branch` after the block. The collected answer is
  written once, on the success transition, in the shape `core.subchart`
  already uses.
- The core vocabulary is now seventeen types, and `core.map` is registered
  in `StatifierBlocks.Palette.core_types/0` beside the rest.
