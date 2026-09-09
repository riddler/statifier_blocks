### Fixed

- A read-only editor mount now refuses the Expand gesture. "Replace with its
  steps" reached the document and fired `on_change` on a mount whose profile
  said `read_only?: true`, which every other gesture that changes the document
  already refused.
