### Added

- The block document gains a top-level `datamodel` key: a list of
  `StatifierBlocks.Document.DatamodelEntry` structs, each an `id` plus an
  optional `expr` and an optional `description`, naming the `<data>` roots
  the document's own guards and assigns read. `Document.new/2` takes a
  `:datamodel` option (default `[]`); a document declaring none compiles
  and encodes byte-identically to one built before this key existed. The
  key is part of the document's canonical bytes, so it participates in
  `content_hash/1` and in compile determinism.
- `Compiler.compile/3`'s `:declare` compile option now leads a second
  declaration surface rather than being the only one: the compile call's
  roots emit first, the document's own `datamodel` roots follow, and
  block-declared roots follow those, all in one `<datamodel>`. A root
  both the compile call and the document declare is host-wins: the
  compile call's declaration is emitted, the document's is dropped, and
  the compile succeeds with a `:shadowed_document_root` warning on
  `Compiled.warnings` rather than refusing. A document root colliding
  with a block-declared root is still refused as `:duplicate_binding`.

### Changed

- Decoding a document now refuses an envelope object carrying a key
  outside `id`, `revision`, `root`, `schema_version`, `metadata`,
  `datamodel`, and refuses a `datamodel` entry carrying a key outside
  `id`, `expr`, `description`, or carrying an explicit JSON `null` for
  `expr` or `description` - matching the round-trip discipline already
  applied to unrecognized block keys.
