### Added

- The editor's `profile` assign takes a `run?` key: `run?: false` mounts an
  editor that seats no run at all, so there is no run pane, no run marks on the
  canvas and no **Held here** column, whatever the host passes in `run` and
  `run_session`. It defaults to `true`, and it does not touch the marks a host
  paints itself through `active_marks` and `invoke_mark`.
