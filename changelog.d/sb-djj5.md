### Added

- The editor takes a `run_session` - a `Statifier.Session.server()` - and the Run pane draws a send control over it: one button per event in the selected block's type's fixture sample, sending straight into the session through statifier-ui's `EventInjection`.
- The send control is enabled only over a live stream with a session supplied; over a persisted run, or with no session, every button renders disabled with a one-line note, and a send never writes to the document.
