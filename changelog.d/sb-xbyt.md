### Added

- The editor takes a `run` - statifier-ui's `StatifierUI.Live.State`, live or persisted - and seats the canvas in a run pane: statifier-ui's status and scrubber above it, its event log below, and no Mermaid diagram. Scrubbing or clicking a log entry moves the canvas's run marks, and clicking a log entry also selects the block whose state handled that step.
- While a run is seated the Datamodel drawer tab's "what is known here" table shows what the run held at each path, beside the type the position declares.
- `StatifierBlocks.Runtime.Handled.block/3` answers which block's state handled one macrostep of a run, and `StatifierBlocks.Runtime.RunValues.at/1` what a run held at its selection; both are pure and neither needs statifier-ui to be present.
- `StatifierBlocks.Runtime.Selection.scrub/2` and `select/2` move a run's selection, which is what the pane's two events do.
