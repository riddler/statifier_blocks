### Changed

- The editor's undeclared-path advisory now reads three declaration
  sources rather than one. A config field a block type annotated
  `datamodel_path?: true` is declared when the host's datamodel holds its
  path, when the document's own `datamodel` key declares its root, or when
  the compile call's `:declare` option declares its root. A declared root
  covers every path beneath it; the datamodel's own paths are still matched
  whole. ADR-0005's decision 11 is amended as 11k-11m, taking the open
  question ADR-0001's 2026-08-31 amendment left to it in its clause 11g.
- The check's precondition widens to match: it runs when a datamodel was
  supplied *or* when either surface declares a root, and still produces
  nothing at all when nothing anywhere was declared. A host that passes no
  datamodel and no roots sees exactly what it saw before; a document that
  declares its own roots now lints its own paths with no host involved.

### Added

- `StatifierBlocks.Editor` takes a `declare` assign, the `{id, expr}` roots
  the host will pass `StatifierBlocks.Compiler.compile/3` as `:declare`,
  defaulting to `[]`. `Editor.findings_count/3` takes the matching
  `:declare` option, so the host's number and the drawer's stay the same
  number. The document's own roots need no option - they are read off the
  document.
- `StatifierBlocks.Datamodel.declared_roots/1`, the total normalizer for a
  root set, beside `declared_paths/1`.
