### Added

- The editor accepts an `on_select` function and calls it with a
  `%{id:, type:, label:}` descriptor for each new selection, or `nil` when
  nothing is selected, so a host panel can follow the canvas.
