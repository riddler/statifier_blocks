### Added

- `StatifierBlocks.Editor.MapRegions.description_region/1` takes a `label`
  attr, the live region's accessible name, rendered as its `aria-label`;
  it defaults to `"Description"`, so a host that passes nothing gets the
  region it had.
