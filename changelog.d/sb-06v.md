### Added

- A block type may declare a `:string` config field keyed `label`, and the
  editor draws that value as the card's title with the type's own label as a
  subtitle underneath - so a host's steps read as the names an author gave
  them without the type ever being hidden.
- A card carrying `invoke_type` in its config draws it in mono on a third
  line, which is the fact an author checks most on a step that calls out to a
  handler.
- `StatifierBlocks.ViewModel.title/1` and `subtitle/1` answer what a card's
  two name lines say, and `ViewModel.Node` carries `title` and `invoke_type`
  for a host rendering its own cards.

### Changed

- The delete control on a card is revealed on hover, on keyboard focus and on
  the selected card, and is hidden at rest. It is still in the DOM and still
  focusable, so the keyboard path is unchanged.
- The card title reads as a title rather than as a native button, and the
  count badge, the subtitle and the invoke line are placed by a grid on the
  card's chrome.
- The per-block-type accent stripe is drawn on cards whose type declared an
  `accent_token` and on no others. A type that declared nothing keeps a plain
  card; its icon tile is unchanged.
