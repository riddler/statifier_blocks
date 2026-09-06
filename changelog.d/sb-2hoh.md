### Added

- `core.branch` declares a third slot, `undecided`, labelled "Cannot be decided". A branch that puts children in it emits one extra transition, after every arm and before `otherwise`, taken when an arm's condition could not be decided - a comparison predicator answers with its undefined sentinel rather than `true` or `false`, such as a path missing under a bound datamodel root, or operands whose types do not match.

### Changed

- A `core.branch` that leaves `undecided` empty compiles to exactly the bytes it compiled to at 0.20.0, so every stored document is unaffected until its author wires the slot.
