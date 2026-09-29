### Changed

- The Map hook warns once per mount in the browser console when its element
  has no `data-map-canvas` child. It still draws into the element itself, as
  before, but that is not supported: LiveView patches the element, so a
  patch can take the drawing away. `map_region/1` always renders the child;
  a host that attaches the hook to its own element gives it one.
