### Added

- A literal capture pair - `["const", value]` - draws a read-only row in the
  editor's capture section, so a pair the two controls cannot author is
  visible rather than absent.

### Fixed

- Editing a `core.on_event` block no longer drops its literal capture pairs:
  a pair the form could not draw was previously replaced away by the next
  change the form posted.
