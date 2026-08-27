### Added

- `StatifierBlocks.Compiler`: the one-way compile (ADR-0004 decisions 1-4, 6-7). `compile/3` is a total function of `{document, palette}` returning `{:ok, %StatifierBlocks.Compiled{}}` or `{:error, [%StatifierBlocks.Compiler.Finding{}]}` - no process state, no clock, no IO, and no arm that raises. The pipeline runs Document, Resolve, Config and Emit, stopping at the first stage that produces errors and reporting every error from that stage.
- `StatifierBlocks.Emission`: the structural representation of one SCXML subtree a block type returns from `emit/2`, with `element/3` and the `child_ref/1` placeholder the compiler splices its children into.
- `StatifierBlocks.Compiler.Serializer`: the deterministic serializer. Attributes sorted, one canonical empty-element form, no incidental whitespace at all. It is identity-bearing code - chart identity hashes source bytes (st-ADR-0052) - and `serializer_test.exs` now enforces the whitespace sensitivity ADR-0004 decision 6 named and left unenforced.
- `StatifierBlocks.Compiler.StateId`: `state_id/1`, `state_id/2`, `unstate_id/1` and `done_event/1`. State ids derive from block ids (`"s_" <> block_id`, `"__" <> role` for an auxiliary state), so they are unique, invertible and total over generated states.
- `StatifierBlocks.Compiler.Context`: what a block type is entitled to know while emitting - its own ids, the document id, its children's summaries (block id, state id, done event) and the role-minting function. No palette, and no child's emitted SCXML.
- `StatifierBlocks.Compiled` and `StatifierBlocks.CompilationRecord`: the artifact, and the join between document identity and chart identity. `chart_name` carries the document id and `chart_version` stays `nil`, so a revision bump or a metadata-only edit still matches the identity a running session holds.
- `StatifierBlocks.Core.Emit`: the SCXML shapes the `core.*` vocabulary compiles to, and the builders a host block type follows to compose with them.

### Changed

- All seven `core.*` block types now implement `emit/2` for real; the `{:error, {:not_implemented, block_id}}` placeholder and `StatifierBlocks.Core.Config.emit_deferred/1` are gone.
- `c:StatifierBlocks.BlockType.emit/2` is narrowed from `(Block.t(), term()) :: {:ok, term()} | {:error, term()}` to `(Block.t(), StatifierBlocks.Compiler.Context.t()) :: {:ok, StatifierBlocks.Emission.t()} | {:error, StatifierBlocks.BlockType.emit_error()}`. A host block type that was returning something else now has a type to conform to.
