### Added

- A `core.foreach` block type: a container whose `body` runs once for each
  item of a datamodel list, compiled as a plain SCXML loop - a per-loop
  cursor and a snapshot of the list taken once on entry, the `item_as` and
  `index_as` bindings re-assigned from that snapshot on each pass, and the
  body compiled once with an internal loop-back transition. Iteration ends
  on the out-of-bounds read, `snapshot[cursor] === undefined`.
- A block type may now contribute **declared `<data>` roots** to the chart:
  `StatifierBlocks.Compiler.DeclaredRoots.declare/2` emits a declaration
  among the block's own children and the compiler lifts every one of them
  into a single top-level `<datamodel>`, in document order. A document that
  declares no roots emits no `<datamodel>` element, so charts compiled
  before this change are byte-identical.
- A new Emit-stage finding, `:duplicate_binding`: a declared root whose name
  a block it sits inside already declares is refused against the declaring
  block and the config field the name was typed into, because early binding
  makes both roots global and the inner one would silently overwrite the
  outer.

### Known limits

- A list holding a `nil` item iterates to its end rather than stopping at
  it: `===` is strict, so only an out-of-bounds read is `undefined`.
- Two `core.foreach` blocks in one document may not bind the same name,
  even when neither is inside the other; the second is refused with a
  duplicate-id finding on its `item_as` field.
