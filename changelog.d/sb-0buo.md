### Added

- `StatifierBlocks.ViewModel` answers the readers a host writing its own surface
  over a document would otherwise write privately: `find_node/2`, `parent_of/2`,
  `positions/1`, `sentence/1`, `shown_fields/1`, `fields_for/2`,
  `overlay_draft/2` and `drafted_field/2`.
- `StatifierBlocks.Document.committed_config/2` and `effective_config/2` and
  `/3` answer what the document holds for a block, and what an unaccepted draft
  says instead.
