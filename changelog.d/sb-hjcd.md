### Added

- `StatifierBlocks.BlockType.finishing_outcome_name/2` answers the outcome a
  block in a declared slot finishes with: the name it carries under
  `finish_as` when that name is well formed, and the outcome its config
  declares at the given key otherwise.

### Changed

- The editor view model reads a `core.on_event` handler that names the
  outcome it finishes with under `finish_as` as that name; a handler naming
  none still reads as its `outcome` select value.
