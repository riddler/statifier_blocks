# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Entries for unreleased work are not written here directly. Each issue drops a
fragment in [`changelog.d/`](changelog.d/README.md); the fragments are assembled
into a version section at release. See that README for the format and for when a
change warrants an entry at all.

## [0.1.0] 2026-08-27

First release: the authoring layer above the
[statifier](https://hex.pm/packages/statifier) statechart engine. A block
document is the source of truth - a tree of typed blocks, each with a declared
shape - and it compiles one way to SCXML plus a provenance map that points a
runtime position back at the block that produced it. Block types are
host-pluggable: a host registers the types its own domain needs, and the
compiler and the editor work off that registry rather than a closed built-in
vocabulary. The `core.*` structural vocabulary, the compiler, the edit algebra,
and the LiveView editor shell all ship here.

The `Changed` entries below describe the shape of callbacks and metadata as
they stand at this first release; there is no earlier published version to have
changed from.

### Added

- `StatifierBlocks.Document.validate/1` checks a block document's structure:
  schema version, envelope shape, per-block shape, and document-wide id
  uniqueness.
- `StatifierBlocks.Document.to_json/1` encodes a document to ADR-0001's
  deterministic canonical JSON: sorted object keys, no insignificant
  whitespace, empty `slots`/`config`/`metadata` omitted, no floats.
- `StatifierBlocks.Document.content_hash/1` returns a `"sha256:" <> hex`
  document identity over `to_json/1`'s canonical bytes.
- `StatifierBlocks.Document.from_json/1` decodes canonical JSON back into a
  document, structurally and registry-free: unknown block types decode
  successfully, and every refusal is one of ADR-0001's typed error arms.
- `StatifierBlocks.BlockType` behaviour: the nine-callback authoring-time
  extension seam (ADR-0002), five required (`slots/1`, `config_schema/1`,
  `validate_config/1`, `current_version/0`, `emit/2`) and four optional
  (`io/1`, `migrate_config/2`, `fixtures/0`, `palette_entry/0`).
- `StatifierBlocks.Palette`: a caller-supplied `type_name => module` value
  (ADR-0002 decision 2), with `new/1` to build one and a total `fetch/2` that
  returns `{:ok, module}` or `{:error, {:unknown_block_type, type_name}}` and
  never raises (ADR-0002 decision 3).
- `StatifierBlocks.Palette.resolve/2`: resolves a block through the palette and
  migrates its config in memory when the stored `type_version` is below the
  type's `current_version/0` (ADR-0002 decision 8). Migration is applied to the
  returned struct only and never written back to a document; a stored version
  above `current_version/0` hard-errors as
  `{:error, {:block_type_too_new, id, version}}` rather than reading
  best-effort, and a failing or missing `migrate_config/2` surfaces as
  `{:error, {:migration_failed, id, reason}}`.
- The `core.*` structural block types (ADR-0002 decision 10), one
  `StatifierBlocks.BlockType` module each: `StatifierBlocks.Core.Sequence`,
  `.Group`, `.Branch`, `.Parallel`, `.Wait`, `.ResumableGroup` and `.OnEvent`.
  `core.branch` derives one slot and one `:expression` field per declared arm,
  `core.parallel` one slot per declared lane, and each type is the authority on
  its own config through `validate_config/1`.
- `StatifierBlocks.Palette.core/0` and `StatifierBlocks.Palette.core_types/0`:
  the core vocabulary as a palette, and as the plain `type_name => module` map
  a host merges its own entries into.
- Structural placement through ADR-0003 decision 3 kind tags: `core.on_event`
  declares `kinds: [:interrupt_handler]` and the group types accept only that
  kind in their `interrupts` slot, so an interrupt handler is admitted there
  and refused everywhere else, and an ordinary step is refused there - in both
  directions, from the declarations alone, with no special-cased rule.
- `fixtures/0` on `core.branch` (an arm condition evaluated against two
  datasets) and `core.on_event` (one example event payload). The bundle shape
  follows an amendment to ADR-0002 decision 9 that is not yet accepted, and is
  documented as provisional until it is.
- `StatifierBlocks.Assignability`: the one decision function for whether a
  block may land in a slot, checking structural admission by kind tag and
  data-flow compatibility by type-expression identity plus an optional
  host-supplied widening relation (ADR-0003). `check/5` decides a single
  candidate position; `valid_targets/4` lists every position a candidate may
  occupy in a document; `validate/3` reports every finding already present in a
  document; `inbound_type/4` and `assignable?/3` are the two primitives both
  are built from.
- `StatifierBlocks.Assignability.Relation`: the behaviour a host implements to
  widen data-flow compatibility beyond exact type-expression identity. A host
  module can only grow the accepted set, never shrink it.
- `StatifierBlocks.Palette` gains an `assignability` field naming the host's
  `Assignability.Relation` module, set via
  `Palette.new(types, assignability: MyApp.Blocks.Types)`. Defaults to `nil`,
  meaning no widening relation is declared; existing calls to `Palette.new/1`
  are unaffected.
- `StatifierBlocks.Compiler`: the one-way compile (ADR-0004 decisions 1-4,
  6-7). `compile/3` is a total function of `{document, palette}` returning
  `{:ok, %StatifierBlocks.Compiled{}}` or
  `{:error, [%StatifierBlocks.Compiler.Finding{}]}` - no process state, no
  clock, no IO, and no arm that raises. The pipeline runs Document, Resolve,
  Config and Emit, stopping at the first stage that produces errors and
  reporting every error from that stage.
- `StatifierBlocks.Emission`: the structural representation of one SCXML
  subtree a block type returns from `emit/2`, with `element/3` and the
  `child_ref/1` placeholder the compiler splices its children into.
- `StatifierBlocks.Compiler.Serializer`: the deterministic serializer.
  Attributes sorted, one canonical empty-element form, no incidental whitespace
  at all. It is identity-bearing code - chart identity hashes source bytes
  (st-ADR-0052) - and `serializer_test.exs` now enforces the whitespace
  sensitivity ADR-0004 decision 6 named and left unenforced.
- `StatifierBlocks.Compiler.StateId`: `state_id/1`, `state_id/2`,
  `unstate_id/1` and `done_event/1`. State ids derive from block ids
  (`"s_" <> block_id`, `"__" <> role` for an auxiliary state), so they are
  unique, invertible and total over generated states.
- `StatifierBlocks.Compiler.Context`: what a block type is entitled to know
  while emitting - its own ids, the document id, its children's summaries
  (block id, state id, done event) and the role-minting function. No palette,
  and no child's emitted SCXML.
- `StatifierBlocks.Compiled` and `StatifierBlocks.CompilationRecord`: the
  artifact, and the join between document identity and chart identity.
  `chart_name` carries the document id and `chart_version` stays `nil`, so a
  revision bump or a metadata-only edit still matches the identity a running
  session holds.
- `StatifierBlocks.Core.Emit`: the SCXML shapes the `core.*` vocabulary
  compiles to, and the builders a host block type follows to compose with them.
- `StatifierBlocks.Provenance`: the map from generated SCXML back to the blocks
  that produced it (ADR-0004 decision 5). Keyed by state id for highlighting a
  running session's configuration, and by byte span for routing findings that
  carry no element reference. `owner_at/2`, `owner_of_state/2`,
  `owners_of_states/2`, and canonical `to_json/1` / `from_json/1` so a host can
  store the map beside the chart.
- `StatifierBlocks.Compiled` now carries all five of ADR-0004 decision 1's
  fields: `provenance`, `invoke_types` and `warnings` join `scxml` and
  `record`.
- `invoke_types` publishes the sorted set of invoke types the chart emits,
  unconditionally, so a host can compare it against its `Statifier.Session`
  registration at deploy time (ADR-0004 decision 8).
- `Compiler.compile/3` accepts `:known_invoke_types`, an opt-in lint that
  **warns** - never errors - for every emitted invoke type absent from the set
  the caller believes will be registered.
- `Compiler.compile/3` accepts `:entry_type`, ADR-0003 decision 4's
  caller-supplied context, which the new Structure stage passes to
  `StatifierBlocks.Assignability.validate/3`.
- The compiler now runs a **Structure** stage (assignability) and a **Chart**
  stage (statifier's own pipeline over the generated bytes), and maps every
  upstream finding back to the block that caused it.
- `StatifierBlocks.Emission.attributed_to/2`, `from_config/2` and
  `attribute_from_config/3`: the hints a block type leaves so a finding lands
  on the block an author would recognise, and on the config field they typed
  into.
- `StatifierBlocks.Edit`: the editor's command algebra - insert, remove, move,
  and update-config - as a purely structural, invertible rewrite over a
  document with no palette involved (ADR-0005). `apply/2` applies one command
  and returns both the new document and the command that undoes it;
  `check_config/3` is the separate config-validity gate one layer up.
- `StatifierBlocks.Edit.History`: undo and redo over `Edit` commands.
  `commit/4` is the one funnel a host calls - it runs `Edit.check_config/3`
  before `Edit.apply/2`, then pushes the inverse and clears the redo stack, so
  invalid config never reaches the document on any path, undo and redo
  included.
- `StatifierBlocks.Edit.Targets`: `droppable_slots/3` and
  `droppable_slots_for/3`, which slots would accept a dragged block, at slot
  granularity rather than gap granularity, built as a reduction of
  `StatifierBlocks.Assignability.valid_targets/4`.
- `StatifierBlocks.Finding`: the presentation finding ADR-0005 specifies,
  anchored to a block, a slot, or a config field so the editor knows where to
  render it. Distinct from the existing `StatifierBlocks.Compiler.Finding`,
  which serves the compile pipeline.
- `StatifierBlocks.ViewModel`: the structure the editor actually renders,
  derived from a document, a palette, and a list of findings. Resolves and
  normalizes every block's slots, form fields, and palette presentation
  metadata, and routes every finding to the position that renders it.
- `StatifierBlocks.Editor`: the LiveView editor shell (ADR-0005). A
  `LiveComponent` a host embeds over a `%Document{}` and a `%Palette{}`; it is
  the only stateful module in the package's rendered half, and everything it
  does is translate a `phx-` event into one of `StatifierBlocks.Edit`'s four
  commands. Drag is two round-trips - one at `dragstart` to enumerate valid
  slots, one at `drop` - with zero per hover, because validity reaches the
  client as `data-drop` markup rather than as client-side logic.
- `StatifierBlocks.Editor.Canvas`, `.BlockNode`, `.Slot`, `.ConfigForm`,
  `.Field`, `.PaletteBrowser`, `.Findings`: the function components the shell
  renders, each independently renderable in a test. `BlockNode` and `Slot`
  recurse into each other, and there is no per-block-type component: a block
  type's `layout` and `slot_style` presentation metadata is the only thing that
  distinguishes a group from a set of lanes.
- `assets/js/statifier_blocks.js`: the package's entire client-side surface,
  one hook named `StatifierBlocksDrag`, shipped as source. A host adds
  `"statifier_blocks": "file:../deps/statifier_blocks"` to its
  `assets/package.json` and imports the hook in `app.js`; this repository
  bundles nothing and has no Node toolchain.
- `assets/css/statifier_blocks.css`: one stylesheet of structural CSS and no
  visual opinion beyond it. Every class is prefixed `sb-`, every color, space,
  radius and drag treatment is a `--sb-*` custom property with a default, and
  every top-level component takes a `class` attr appended to its own.
- A headless CI job that resolves the dependency tree with `phoenix_live_view`
  absent, compiles it with warnings as errors, and runs the non-LiveView suite
  - the acceptance property that makes the optional dependency's guard
  trustworthy rather than decorative. `STATIFIER_BLOCKS_HEADLESS=1` reproduces
  it locally without disturbing the ordinary build.
- `StatifierBlocks.BlockType`: a config field declaration may now carry an
  optional `value_path`, a list of keys and list indexes from the config root
  down to the value it edits (ADR-0002 decision 7, amended 2026-08-27). A
  declaration without one behaves exactly as before - its `key` addresses
  `config[key]`. The `key` remains the field's identity in both cases: the DOM
  id, the form param name, and what a `{:config, block_id, key}` finding
  anchors to.
- `StatifierBlocks.BlockType.value_path/1`, `fetch_value/2` and `put_value/3`:
  the reader and writer that resolve a declaration to a path and then read or
  write through it. `value_path/1` answers `[key]` for a declaration that
  declares none, so a caller never branches on which case it has.
  `fetch_value/2` is total and answers `:error` for a path that does not
  resolve. `put_value/3` writes the last segment whether or not a value was
  already there - an arm with no condition yet is exactly the one an author is
  about to type into - but never invents an intermediate map or list a block
  type did not write.
- `StatifierBlocks.ViewModel.Field` carries `value_path`, and
  `ViewModel.Field.value_path/1` reads it with the same `[key]` default.

### Changed

- `c:StatifierBlocks.BlockType.io/1`'s return type is
  `StatifierBlocks.Assignability.io/0` instead of `term()`. Every core block
  type already returns a value of this shape; a custom block type implementing
  `io/1` should confirm its return value conforms.
- All seven `core.*` block types implement `emit/2` for real; the
  `{:error, {:not_implemented, block_id}}` placeholder and
  `StatifierBlocks.Core.Config.emit_deferred/1` are gone.
- `c:StatifierBlocks.BlockType.emit/2` is narrowed from
  `(Block.t(), term()) :: {:ok, term()} | {:error, term()}` to
  `(Block.t(), StatifierBlocks.Compiler.Context.t()) :: {:ok, StatifierBlocks.Emission.t()} | {:error, StatifierBlocks.BlockType.emit_error()}`.
  A host block type that was returning something else now has a type to conform
  to.
- `StatifierBlocks.Compiler.Finding` gains `path`, `severity`, `fault` and
  `code`. `fault` is `:author` when a document edit fixes the finding and
  `:package` when it is a bug in this package or a host's block type - which is
  what lets an editor say "this cannot be fixed here" rather than blaming the
  author for a generated state id.
- Findings from every stage come back in document order over blocks rather than
  in the order a stage happened to collect them.
- A bad `:expression` config field now surfaces as an `:author` finding naming
  the arm's config key, rather than as an unrouted upstream error.
- `c:StatifierBlocks.BlockType.palette_entry/0`'s return type is
  `StatifierBlocks.BlockType.palette_entry/0` instead of `map()`. Every core
  block type already returns a value of this shape; a custom block type
  implementing `palette_entry/0` should confirm its return value conforms.
- `phoenix_live_view` is a declared optional dependency at `~> 1.0`, matching
  statifier_ui's floor. Every module under `StatifierBlocks.Editor.*` is
  compiled behind `Code.ensure_loaded?(Phoenix.LiveView)`, and no module
  outside that namespace references Phoenix - so a host that only compiles
  documents adds no Phoenix dependency and compiles no editor code.
- The hex package's `files:` list includes `assets`. The hook and the
  stylesheet ship as source, and source that is not in the tarball is not
  public API.
- Every illustrative example in the package - ADR worked examples, doc
  examples, and the shipped fixture bundles - uses one of the family's two
  canonical example domains: credit-card authorization and capture, or a signup
  wizard with A/B testing.
- `StatifierBlocks.Core.Branch.fixtures/0` ships budget-decision datasets
  (`"approved"` / `"declined"`) and the expression `"budget_remaining > amount"`.
  A host rendering the bundle in a palette panel sees those names.
- The arm-slot and lane-name validation messages on `core.branch` and
  `core.parallel` name `"arm_approved"` and `"capture"` as their exemplars.

### Fixed

- A `core.branch` arm's condition is now readable and editable in the editor.
  `Core.Branch.config_schema/1` keys one `:expression` field per arm by the
  arm's slot name, but the condition is stored at `config["arms"][i]["cond"]`;
  the form previously read and wrote the slot name as a top-level config key,
  so every branch condition rendered empty, no edit to one reached the arm, and
  a junk `config["arm_approved"]` accumulated beside it. Each per-arm field now
  declares `value_path: ["arms", i, "cond"]`, and `StatifierBlocks.ViewModel`
  and `StatifierBlocks.Editor.ConfigForm` read and write through it. `i` is the
  arm's index in the **stored** list rather than its index among the
  well-formed ones, so a good arm below a malformed one still addresses its own
  condition while an author is mid-edit.
- `StatifierBlocks.Editor`'s `field-list-add` and `field-list-remove` events
  read and write the rows through the field's `value_path` as well, rather than
  through the top-level key. A key naming no field in the selected block's
  schema now edits nothing, matching the guard `ConfigForm.decode/3` already
  applied.
- `StatifierBlocks.Assignability.check/5` and `valid_targets/4` no longer raise
  a `MatchError` when the candidate is the document root.
  `Document.fetch_path/2` answers `{:ok, []}` for the root, and the
  vacated-seam check now reads that as what it is - the root occupies no slot,
  so it leaves no seam behind - instead of calling `List.last/1` on the empty
  path. `StatifierBlocks.Edit.Targets.droppable_slots/3` answers `[]` for the
  root rather than crashing, so a caller no longer has to guard around it.

[0.1.0]: https://github.com/riddler/statifier_blocks/releases/tag/v0.1.0
