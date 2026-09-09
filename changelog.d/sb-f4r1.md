### Fixed

- A gesture the editor refuses now draws the refusal as one sentence in the
  canvas column, under the toolbar. Every refusal already recorded its reason
  and nothing read it, so a gesture the editor refused looked on screen
  exactly like a gesture that did nothing.

### Added

- `StatifierBlocks.Edit.Session.refusal/1` says what is in a session's
  `last_error` as one sentence, so a host driving the same commit funnel
  draws the same words for the same refusal.
