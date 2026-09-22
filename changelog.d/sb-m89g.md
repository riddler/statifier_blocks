### Added

- `Compiler.structure_findings/3` returns the findings the compile's Document,
  Resolve, Config and Structure stages refuse a document for, without emitting
  anything: exactly the list `Compiler.compile/3` refuses with when it refuses
  at one of those stages, and `[]` otherwise. It takes `compile/3`'s own
  options and never raises.
- `StatifierBlocks.Publish.findings/3` returns every finding a host's publish
  step judges a document by before it compiles, in the order the editor shows
  them: the structure findings above, then the editor's own findings for the
  same document and the same `:datamodel`, `:declare` and `:chart_outcomes`. A
  document the Document stage refuses comes back as that one finding. The
  host refuses the publish on an `:error`; an undeclared datamodel path stays
  an `:info` advisory.
- `StatifierBlocks.Finding` gains the anchor `:document` for a finding about
  the document rather than a block. `Finding.from_compiler/2` adapts the
  compile's Document-stage finding to it instead of refusing it as
  `:unanchorable`, and the editor lists it first on both findings surfaces,
  under `Document`, with nothing to select. `Shell.findings_groups/3`'s groups
  gain a `document?` key, and the inspector stamps `data-document` on each
  group.

### Fixed

- `Compiler.compile/3` returns its Document-stage refusal for a document whose
  `root` is not a block, or whose `slots` value is not a map of block lists,
  where it raised.
