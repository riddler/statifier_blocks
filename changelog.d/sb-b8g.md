### Fixed

- A host's `icon` component is rendered as a function component rather than
  applied to a bare map, so it receives a tracked assigns map and may use
  `Phoenix.Component` helpers such as `assign/3` and `assign_new/3`. A host
  that worked around the old behavior by adding `__changed__` to the assigns
  itself no longer needs to; the component must still return a `~H` template,
  which it always had to.
