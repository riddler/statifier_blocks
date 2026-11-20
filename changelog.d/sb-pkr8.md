### Added

- A document with a returnable step compiles with Back: delivering the reserved event `statifier_blocks.back` re-enters the most recent returnable step behind the current position and pops the trail, does nothing when nothing is behind it or the scope has finished, and never crosses a `core.subchart`, `core.map`, `core.foreach` or `core.parallel` boundary, a loop iteration or a parallel lane; a document with no returnable step compiles to the same bytes as before.
