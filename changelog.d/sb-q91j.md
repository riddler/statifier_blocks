### Added

- The edit command `{:update_note, id, note}` writes a block's author note,
  with the previous note as its inverse, so undo and redo move it like any
  other edit; an empty note removes it. `StatifierBlocks.Edit.t()` gains this
  member, so a host that matches every member of the union by hand has one
  more to handle.
- The editor's inspector opens its Config tab on a Note field for the
  selected block, which writes the note through that command; a read-only
  mount shows the note as text and does not edit it.
