### Added

- The editor's canvas is a named panel: the toolbar is its header row, with a
  `Canvas` label, a `nested tree` chip, one segmented zoom control, and the
  depth and block-count metrics as right-aligned chips.
- The canvas sits on a bordered, dotted ground, and `--sb-canvas-grid` is the
  tier-2 token a theme sets to change the dots' colour and spacing together.

### Changed

- The canvas stage renders inside a `.sb-canvas-panel` element, which is now
  the scrolling box; `#sb-canvas` stays the drag hook's element, the stage
  anchor, and where the `theme` assign's declarations land.
