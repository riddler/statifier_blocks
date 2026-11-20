### Added

- `StatifierBlocks.Runtime.Back.offered?/3` answers, from an execution's datamodel, its active leaf states and its document, whether delivering the reserved event `statifier_blocks.back` would re-enter a returnable step: `true` when a trail around the current position holds a step behind it, `false` at a first step, past a checkpoint, in a finished scope and for a document with no returnable step.
