### Added

- `StatifierBlocks.Edit.Session` carries a `draft_findings` map: the per-field
  findings each refused `change_config/3` was handed, keyed by block id.
- `StatifierBlocks.ViewModel.overlay_findings/2` routes those findings onto a
  node's form fields, with a finding naming no field landing in
  `form.unrouted` - the findings half of `overlay_draft/2`.

### Changed

- A surface drawing a refused config draft reads the findings from the session
  instead of calling `validate_config/1` again to re-derive them.
