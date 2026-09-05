### Fixed

- The editor toolbar's `Fit active` follows the run marks a host paints: it
  is enabled whenever there is a selection or an active mark, and with
  nothing selected it fits and reveals the first marked block.

### Changed

- `StatifierBlocks.Editor.Toolbar.toolbar/1`'s `:selected?` attribute is now
  `:fittable?`, because a selection is no longer the only thing that gives
  `Fit active` something to fit. Rename the attribute at any direct call
  site; hosts rendering the editor pass nothing here.
