### Added

- `StatifierBlocks.BlockType`'s closed field-type set gains a ninth member,
  `{:type_expr, opts}`: a field holding the name of a type the datamodel
  document declares, or an inline unnamed shape as a list of
  `"name"` / `"type"` / `"required?"` objects, or nothing at all. `opts`
  carries `arms:` (which of the two the field admits, both by default) and
  `allow_empty?:` (whether an empty value is admitted, true by default).
- `StatifierBlocks.BlockType.type_expr_findings/2` is the one shared check
  behind that field type, consulted by both the compiler's `:config` stage
  and the editor's view model: a value that is not an arm the declaration
  admits is a `:config` finding carrying the field's key, and an undeclared
  type name is not one.
- The editor draws a `{:type_expr, opts}` field in the inspector's Config
  tab: a text input bound to a `<datalist>` of the document's declared type
  names for the name arm, an ordered member-list form for the inline arm
  whose member types are the same control recursing, and a toggle when the
  field admits both. Switching arms replaces the value rather than
  translating it, and a value the control cannot read is drawn raw with its
  finding beneath it.
- `StatifierBlocks.Environment`'s type expression admits an inline unnamed
  shape, `{:shape, members}`, and `StatifierBlocks.Environment.inline_shape/1`
  reads a stored member list into one. The read check reaches it through
  `StatifierDatamodel.Types.satisfies/3` unchanged - this package defines no
  second one.

### Changed

- The environment now **seeds** the declared path types the datamodel
  document carries: before the walk begins it holds an entry at every path
  the document declares, at the type it declares there, and a type a block
  writes replaces it from that position on. A read at a declared path that
  found nothing before, and was an `:info` advisory, now meets the declared
  type - so a stored document that validated may refuse once its host
  supplies a datamodel, and the fix is either the block's declaration or the
  document's. A caller that supplies no datamodel is unaffected in every
  particular.
- A seeded entry's writer is `:declaration`, which
  `StatifierBlocks.Assignability`'s `:type_mismatch` reports as its upstream
  ref. Such a refusal carries no `{:fixable_by, block_id}` reason - there is
  no block whose declaration an author would change - and its message says
  the datamodel document declares the type rather than naming a block.
- `core.map`'s `collect` writes `{:list, <the ADR-0009 envelope>}` rather
  than `{:list, :unknown}`: one collected element is a shape of `index`,
  `status`, an optional `donedata` typed by the block's own `collect_type`,
  and an optional `failure`. A block after a `core.map` learns this whether
  or not anything was declared, and no compiled byte moves.
- The `statifier_datamodel` requirement rises to `~> 0.4`, which is where a
  type expression admits an inline shape. Raising the floor alone also
  widens what a document projects: an entry whose `type` names a declaration
  contributes that declaration's fields as declared paths beneath it.
