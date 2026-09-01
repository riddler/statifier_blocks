### Added

- `core.drafts`, the document's shelf: a container whose one `body` slot
  holds fragments an author has built but not placed. It is admitted as a
  direct child of the root block's `body` and nowhere else, a document
  carries at most one, and it compiles to nothing at all - a document with
  work on its shelf, the same document with the shelf emptied, and the same
  document with no shelf produce byte-identical SCXML.
- `core.placeholder`, an in-flow leaf marking a step left unwritten on
  purpose. One optional `note` field, and it compiles to a state that
  completes on entry, so a preview of a half-built workflow walks straight
  through the gap.
- Two Structure-stage errors: `:drafts_block_misplaced` and
  `:duplicate_drafts_block`, the second naming the second and every later
  shelf in document order rather than the first.
- Two Emit-stage warnings on a compile that succeeds:
  `:draft_blocks_present`, once per document on a non-empty shelf, and
  `:placeholder_block`, once per marker, carrying the author's note. What a
  host does with either - a publish gate, say - is the host's.
- `slot_style: :tray`, a fourth value for `palette_entry/0`'s `slot_style`
  map. A tray is a detached shelf: no boundary box, and no connector into
  it, out of it, or between one fragment and the next. `StatifierBlocks.ViewModel`
  gains `tray?/1`, `shelf?/1`, `flow_children/1` and `shelf_children/1`.
- `StatifierBlocks.Shelf`, the module owning the shelf's placement rules and
  the type-name predicates other layers ask about it.
