### Added

- Block types may declare `outcomes/1`, an optional callback returning ordered
  `{name, label}` pairs for the ways a block can finish; a type that does not
  export it has exactly one outcome, `done`, and behaves as before.
- A child summary in the compiler context carries an `outcomes` field: the
  child's declared outcomes in declaration order, each with the `<final>` it
  compiled to and the completion event a parent wires on. It is never empty.
- The compiler refuses a block type that declares a malformed or duplicated
  outcome name with an `:invalid_outcome` Emit finding, against the block whose
  type declared it.

### Changed

- Every block's conventional `<final>` moves from `s_<block>__done` to
  `s_<block>__o_done` and now raises `done.outcome.<state id>.done` on entry, so
  compiled SCXML moves for every document; a host that stores compiled charts or
  provenance maps recompiles them, and a chart-level position saved against the
  old bytes no longer resolves.
- `Compiler.compiler_version/0` is the third input to the byte-determinism
  guarantee and tracks the package version, so the version move that records
  this byte movement rides the next release rather than this change.
