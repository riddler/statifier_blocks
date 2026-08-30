### Added

- The editor takes run marks from its host: `active_marks`, the block ids a run
  has activated, and `invoke_mark`, the block a run is calling out to together
  with how the call came back. Both are ordinary assigns, so a host pushes them
  with `Phoenix.LiveView.send_update/3` and needs no new API; both are held as
  editor state, so a re-render the host makes for its own reasons does not drop
  them; and both are cleared when the host opens a different document, because
  a mark addresses one block.
- The marks reach the markup as `data-run-active`, `data-run-invoking` and -
  only once a call has come back - `data-invoke-outcome` on the block's
  `.sb-node`, and the stylesheet draws them in tokens a host theme already
  retunes: the accent family for the active mark, the finding severities for
  the outcomes. A mark on a folded container stays visible.
