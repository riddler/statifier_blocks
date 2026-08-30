### Fixed

- An editor opened with `fit: :width` or `fit: :active` no longer paints its
  first frame at 100% and then snaps to the fit. While a fit is armed the
  root carries `data-fit-pending` and the stylesheet keeps the stage
  unpainted under it, so the first frame an author sees is the fitted one; a
  host that never imported the measurement hook, and so never spends the fit,
  is revealed by a CSS-only fallback half a second in rather than left blank.
