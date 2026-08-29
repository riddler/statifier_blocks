### Changed

- The package's default JavaScript export now carries both hooks, so
  `hooks: { ...StatifierBlocks }` registers `StatifierBlocksDrag` and
  `StatifierBlocksMeasure` together - a host that registered only the drag hook
  got an editor with no connectors and no error explaining it. Both names are
  still exported individually, and `statifier_blocks/measure` still resolves for
  a host that wants measurement alone.
