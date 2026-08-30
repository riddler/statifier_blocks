### Added

- `StatifierBlocks.Shell.severity_counts/1` cuts a findings list by severity,
  in `:error`, `:warning`, `:info` order and omitting any with nothing at
  them; it sums to `findings_count/1` for the same list.
- `StatifierBlocks.Editor.Findings.row/1` and `anchor_tag/1` are public, so a
  host rendering findings of its own gets the editor's row anatomy rather than
  re-deriving it.

### Changed

- A finding renders the same way everywhere: severity word, anchor tail
  (`config.duration`, `slot:body`, nothing for a block anchor), source chip
  and message. The inspector's two findings panels showed only the message
  before.
- Both document-level findings surfaces - the drawer's Findings tab and the
  inspector's with nothing selected - carry a severity pill row above the
  list. The list itself is still grouped by block.
