### Fixed

- `StatifierBlocks.Composite.Collapse.replacement/4` gives the composite it
  inserts the collapsed arrangement's own block id instead of a freshly
  minted one, so the state ids of the chart a host gets back after committing
  the swap are the ones the document implies rather than a new UXID each time.
