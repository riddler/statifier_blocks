### Added

- `StatifierBlocks.Edit`: the editor's command algebra - insert, remove, move, and update-config - as a purely structural, invertible rewrite over a document with no palette involved (ADR-0005). `apply/2` applies one command and returns both the new document and the command that undoes it; `check_config/3` is the separate config-validity gate one layer up.
- `StatifierBlocks.Edit.History`: undo and redo over `Edit` commands. `commit/4` is the one funnel a host calls - it runs `Edit.check_config/3` before `Edit.apply/2`, then pushes the inverse and clears the redo stack, so invalid config never reaches the document on any path, undo and redo included.
- `StatifierBlocks.Edit.Targets`: `droppable_slots/3` and `droppable_slots_for/3`, which slots would accept a dragged block, at slot granularity rather than gap granularity, built as a reduction of `StatifierBlocks.Assignability.valid_targets/4`.
- `StatifierBlocks.Finding`: the presentation finding ADR-0005 specifies, anchored to a block, a slot, or a config field so the editor knows where to render it. Distinct from the existing `StatifierBlocks.Compiler.Finding`, which serves the compile pipeline.
- `StatifierBlocks.ViewModel`: the structure the editor actually renders, derived from a document, a palette, and a list of findings. Resolves and normalizes every block's slots, form fields, and palette presentation metadata, and routes every finding to the position that renders it.

### Changed

- `c:StatifierBlocks.BlockType.palette_entry/0`'s return type is now `StatifierBlocks.BlockType.palette_entry/0` instead of `map()`. Every core block type already returns a value of this shape; a custom block type implementing `palette_entry/0` should confirm its return value conforms.
