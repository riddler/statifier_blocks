### Added

- `StatifierBlocks.BlockType` declares an optional thirteenth callback,
  `donedata_type/1`: what a document's `<donedata>` carries when it is
  compiled for use as a child, as a list of `%{name, path, type}` fields
  typed in `statifier_datamodel`'s vocabulary.
  `StatifierBlocks.BlockType.donedata_type/2` is the resolver every consumer
  reads it through, and it is total - a type that does not export the
  callback, or exports one returning something else, declares nothing.
- Compiling with `child_use: true`, each top-level `<final>` now carries one
  `<param name="<name>" expr="<path>"/>` per entry the **root** block type
  declares, in declaration order, **after** the `outcome` param and the
  reserved `statifier_persistence:run_status` param. A root type that
  declares nothing compiles to exactly the bytes it compiled to before, and
  a `terminate` compile emits no declared field at all.
- A declared field name that collides with either of the two names the
  compiler mints, or that is not a bare lowercase identifier, is refused at
  compile with an `:invalid_donedata_field` Emit finding against the root
  block, rather than silently shadowing a param.
- `core.map` gains an optional seventh config field, `collect_type`: the type
  name a collected answer's `"donedata"` carries, read through
  `StatifierDatamodel.Types.parse/2` against the parent document's
  declarations. It is a type rather than a path, it produces no bytes, and it
  has no findings of its own. An absent or empty one means what every stored
  document means today.
- `StatifierBlocks.BlockType.agrees?/3` answers whether a child's declaration
  covers what a parent's `collect_type` expects of it, as
  `StatifierDatamodel.Types`' own read check and in that package's own reason
  vocabulary. The check is **dormant**: it is not a compile finding and
  changes no compiled byte, and it answers only where both documents are in
  hand.
