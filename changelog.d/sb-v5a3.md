### Added

- `StatifierBlocks.Environment` - the datamodel path to type map at any
  position in a document, carried by one pre-order walk. `at/3` answers it,
  `subject_path/2` names the path a document's subject lives at,
  `read_signatures/3` and `write_signatures/3` say what a block declares
  there, and `type_of/2` and `satisfies/3` read a declaration's spelling
  against the datamodel document's own type declarations.
- `palette_entry/0` gains an optional `subject` key: the datamodel path a
  document's subject lives at, read from the document's entry block.
- `StatifierBlocks.Assignability.context/0` gains an optional `:datamodel`
  key, and `StatifierBlocks.Compiler.compile/3` threads its existing
  `:datamodel` option into it, so the read check can consult the document's
  `record` and `shape` declarations.
- The reason vocabulary gains `{:shape_not_satisfied, missing}`: the
  environment holds a record at the path, the read expects a shape, and
  `missing` names the required fields the record does not cover.

### Changed

- **Breaking.** The data-flow check is no longer a question about the block
  before this one. A block declares what it reads and writes at datamodel
  paths, and `check/5`, `valid_targets/4`, `validate/3`, `inbound_type/4` and
  `seam_reason/4` are defined over the environment at a position. They keep
  their arities. `io/1`'s `consumes` and `produces` keep their meaning as
  sugar: `consumes` is a read at the document's subject path and `produces`
  is a write there. A palette that declares no `subject` on its entry block's
  palette entry has no subject path, so that sugar declares nothing and the
  document validates exactly as an untyped one always did.
- **Breaking.** `{:type_mismatch, block_id, ref, held, expected}` gains a
  sixth member, the datamodel path the read was checked at. A block may carry
  several read signatures on several paths, so a message that says which two
  types disagreed without saying where is one an author cannot act on.
  `{:kind_not_admitted, ...}` is unchanged.
- **Breaking.** A type expression spelled exactly `"unknown"` now reads as
  the permissive `:unknown` rather than as an opaque expression that happens
  to be spelled that way. It only ever admits: an opaque `"unknown"` compared
  by identity was already satisfied against another `"unknown"`, so nothing
  that passed before is refused now.
- The refusal a `{:type_mismatch, ...}` names is the block whose write
  signature put the type at the path, found by name rather than by adjacency.
  A refusal at index 0 of a slot that used to answer `:not_assignable` -
  because there was no previous sibling to name - now answers
  `{:fixable_by, block_id}` when a block upstream of the container did
  declare the type.
- The read check itself is `StatifierDatamodel.Types.satisfies/3`: unknown,
  then identity, then a record covering a shape's required set. The palette's
  host relation still runs, and now runs **last**, after that coverage step -
  so the floor a host cannot lower is higher than it was, and a host that was
  widening records into shapes by hand can delete that half of its module.
- A `core.branch`'s arms and a `core.parallel`'s lanes no longer blank
  everything downstream. What leaves a container is the per-path merge: a
  path every arm holds at one type keeps it, and only a path the arms
  disagree about drops to `:unknown`.
