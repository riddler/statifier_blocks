### Added

- `StatifierBlocks.Declarations.add_accepted/1` appends a freshly named
  accepted event, `event_1` or the first `event_N` the list does not already
  hold, and `Declarations.put_accepted/3` writes the name at an index, or
  returns the list unchanged when no name sits there. `Declarations.refusal/1`
  phrases a refused `{:set_accepts, names}` as one sentence for the panel.
- `StatifierBlocks.Editor.Findings.anchor_tag/1` tags a finding anchored on
  the document `document`, with no id.

### Changed

- `StatifierBlocks.Shell.drawer_view/1` takes the document's accepted events
  under an optional `accepts` key, and the Declarations tab's count adds them
  to the datamodel roots it counted before.
