### Added

- The editor takes a `fit` attr - `:manual` (the default, unchanged
  behaviour), `:width` or `:active` - so a host can open a document already
  fitted to the canvas instead of leaving the author to press `Fit width` on
  every document. The first measurement performs the fit once; after it the
  editor behaves exactly as if the author had pressed the button, and an
  unknown value is refused into `:manual`.
