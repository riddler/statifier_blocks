### Added

- `selected_id` is a documented input assign. A host that draws a selection
  surface of its own - an outline pane, a plan view - moves the editor's
  selection by passing the id through `send_update/3`, and hears the result
  back on `on_select` like any other selection. It is honoured only on an
  update that carries it, so a re-render the host made for a reason of its own
  leaves the author's selection where it was, and an id the open document does
  not hold clears the selection rather than naming a block that is not there.
  A selection is not a document edit: no command, nothing serialized, and
  nothing on the undo stack.
