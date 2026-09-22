### Added

- `Compiler.compile/3` records the document's parent/child interface on
  `%Compiled{}` as a new `interface` field: the outcomes and done-data keys its
  root block declares, and for each `core.subchart` or `core.map` block the
  document it names, the child outcomes it routes on and the child done-data
  keys it reads. The SCXML and chart identity do not change with it, and
  `%CompilationRecord{}` does not carry it.
- `StatifierBlocks.Graph.check/2` judges a parent's compiled artifact against
  each child it names, through a resolver the host supplies, and
  `StatifierBlocks.Graph.consumers_broken/2` judges a child's next revision
  against the parents that name it, for a host's publish step to refuse on. A
  child that is not published, an outcome the parent routes on that the child
  does not declare, and a done-data key the parent reads that the child does
  not declare are each an `:error` finding on the parent's referencing block.
  The reverse direction pairs each finding with the parent's document id.
- `StatifierBlocks.Finding` gains the source `:graph` for those findings.
