# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Entries for unreleased work are not written here directly. Each issue drops a
fragment in [`changelog.d/`](changelog.d/README.md); the fragments are assembled
into a version section at release. See that README for the format and for when a
change warrants an entry at all.

## [0.3.0] 2026-08-29

Charts get more shapes to compile into. Campaign 015 adds four emitters to the
`core.*` vocabulary - `core.subchart`, which runs another chart and routes on
the outcome the child reported; `core.foreach`, a container whose body runs
once per item of a datamodel list; scope-correct cancellation for a delayed
`core.send`; and `core.parallel`'s `complete: "first"`, which finishes the
block at the first lane's completion and exits the losing lanes. The compiler
gains two root-document options, `terminate:` and `declare:`, a typed
datamodel index that refuses a document reading a path the host declared
sensitive, and predicator duration strings wherever a duration is typed. In
the editor, connectors graduate out of the spike, a default icon set ships so
a host needs no asset pipeline to get one, and the shell is laid out as the
arrangement record describes it. This is a minor bump because every block's
conventional `<final>` moves from `s_<block>__done` to `s_<block>__o_done`:
the compiled bytes of every outcome-bearing chart move with it, so a host that
stores compiled charts or provenance maps recompiles them, and a chart-level
position saved against the old bytes no longer resolves.

Dependency floor: unchanged - `statifier ~> 2.2` and `predicator ~> 9.0`.

### Added

- A `core.subchart` block type: a step that runs another chart and waits,
  routing `done.invoke` on the outcome the child reported
  (`_event.data.outcome`) to one slot per declared outcome, with
  `core.invoke`'s `on_error` slot unchanged for a failed invocation.
- A `core.foreach` block type: a container whose `body` runs once for each
  item of a datamodel list, compiled as a plain SCXML loop - a per-loop cursor
  and a snapshot of the list taken once on entry, the `item_as` and `index_as`
  bindings re-assigned from that snapshot on each pass, and the body compiled
  once with an internal loop-back transition. Iteration ends on the
  out-of-bounds read, `snapshot[cursor] === undefined`.
- `core.parallel` accepts a `complete` config key choosing when the block is
  done: `"all"` (the default, and what a document stored before the key reads
  as) keeps the shipped rule, and `"first"` compiles the racing rule - one
  transition per lane on the `<parallel>` element itself, taken on that lane's
  own completion event and targeting the block's done final, so the block
  finishes at the first lane's completion and the engine exits the losing
  lanes with their `<onexit>` content and one `CancelInvoke` per live
  invocation.
- Block types may declare `outcomes/1`, an optional callback returning ordered
  `{name, label}` pairs for the ways a block can finish; a type that does not
  export it has exactly one outcome, `done`, and behaves as before.
- A child summary in the compiler context carries an `outcomes` field: the
  child's declared outcomes in declaration order, each with the `<final>` it
  compiled to and the completion event a parent wires on. It is never empty.
- `StatifierBlocks.Compiler.compile/3` accepts `terminate: true`, which emits
  one top-level `<final>` per root-block outcome with no `<donedata>`, so a
  compiled root document reaches `:done` when its root block completes;
  without it a root document never terminates, and passing it together with
  `child_use: true` is refused with an `:emit` finding.
- `StatifierBlocks.Compiler.compile/3` accepts `child_use: true`, which
  compiles a document for use as another chart's child: the emission gains one
  top-level `<final>` per outcome the root block declares, carrying that
  outcome name as done data, so a parent session can see which way the child
  finished.
- `StatifierBlocks.Compiler.compile/3` takes a `:declare` option - a list of
  `{id, expr}` pairs - so a host can declare the `<data>` roots its root
  document assigns to and guards on, hoisted ahead of block-declared roots
  into the chart's single `<datamodel>`.
- `Compiler.compile/3` takes a `:datamodel` option and refuses a document that
  reads a path the host declared `sensitive?: true` into a position the chart
  evaluates against the datamodel; with no datamodel supplied nothing is
  produced.
- A block type may now contribute declared `<data>` roots to the chart:
  `StatifierBlocks.Compiler.DeclaredRoots.declare/2` emits a declaration among
  the block's own children and the compiler lifts every one of them into a
  single top-level `<datamodel>`, in document order. A document that declares
  no roots emits no `<datamodel>` element, so charts compiled before this
  change are byte-identical.
- A new Emit-stage finding, `:duplicate_binding`: a declared root whose name a
  block it sits inside already declares is refused against the declaring block
  and the config field the name was typed into, because early binding makes
  both roots global and the inner one would silently overwrite the outer.
- The compiler refuses a block type that declares a malformed or duplicated
  outcome name with an `:invalid_outcome` Emit finding, against the block
  whose type declared it.
- A chart-stage finding for an expression the author typed carries
  `config_value_span`, the byte range of the offending sub-expression within
  that config value, so an editor can underline the sub-expression rather than
  the whole field.
- `StatifierBlocks.Predicates.Datamodel` indexes a datamodel document - the
  typed, three-scope declaration sb ADR-0006 defines - into a path/entry
  index: the type of a path, the entries under a prefix, whether a path is
  declared, and the record's one total derivation of the declared-path set.
  The index is advisory; an undeclared path is unknown, never wrong.
- `StatifierBlocks.Datamodel.declared_paths/1` accepts such a document as a
  fourth shape, alongside `nil`, a list and a `MapSet`, and projects it
  through that derivation. A document declaring no entries normalizes to the
  empty set - a host claim - rather than to `nil`, which stays reserved for no
  datamodel at all.
- The editor renders the arrangement ADR-0005's shell amendment records: a
  palette, canvas and inspector across three columns with a full-width drawer
  row beneath them, at container-query breakpoints of 1280, 1024, 900, 780 and
  640.
- A canvas toolbar with stepped zoom, Fit width, Fit active, and the
  document's block count and depth.
- The inspector is tabbed - Config, Findings and Condition - where Findings is
  the selected block's own and Condition reads the per-arm predicator source.
- A drawer that is never open-or-gone: collapsed it is a strip carrying a
  title and the document's table count, and opened on a block with no table it
  shows an index of the blocks that have one.
- `fixtures`, an assign carrying `%{block_id => [TruthTable.t()]}`, is what
  the drawer's truth-table tab reads; with none supplied the drawer is still
  present and reads 0.
- `drawer_height` and `on_drawer_resize` are the host's seam for the drawer's
  resizable height, which the host remembers per viewer.
- A `:header` slot the host fills with the outer header - document identity,
  the switcher, the theme control, compile and publish - which this package
  now explicitly does not draw.
- Below 780 the palette collapses to a strip that opens as a sheet.
- `StatifierBlocks.Shell` exposes the shell's arrangement as pure functions -
  the zoom ladder, the document metrics, the drawer's five states, and which
  of a block's fields are conditions.
- Three tier-2 theme tokens: `--sb-palette-width`, `--sb-inspector-width` and
  `--sb-drawer-height`.
- The editor draws connectors. Adjacency inside a slot, a container's entry,
  the fan and rejoin around a container arranged side by side, and a rail's
  exit are rendered as SVG in the LiveView tree, derived from the document's
  shape rather than authored.
- A second JavaScript entry point, `statifier_blocks/measure`, exporting the
  `StatifierBlocksMeasure` LiveView hook. Its whole job is measurement: after a
  render it reads the boxes the browser laid out for the anchors the server
  stamped and pushes them, and it issues no commands and mutates no DOM. A
  host that wants connectors adds one import; a host that does not gets the
  editor it had before, minus the drawn connectors.
- `StatifierBlocks.Connectors`: the connector geometry as pure functions from
  measured rectangles to SVG path data, outside the Phoenix guard, so a host
  can route its own connectors and a test can assert them without a browser.
- Three `--sb-*` tokens for the connector layer: `--sb-edge`,
  `--sb-edge-interrupt` and `--sb-edge-width`.
- `StatifierBlocks.Editor.Icons`, a default icon set the editor uses when the
  host passes no `icon` component. Inline SVG for the eleven names the core
  block types declare, with no font, no CDN and nothing to register in a
  host's asset pipeline. Every glyph paints with `currentColor` and fills its
  tile, so `--sb-block-accent` and `--sb-block-accent-tint` still decide the
  colour and a per-block-type `accent_token` still moves a type's tile with
  its stripe.
- Palette entries render their icon. The `icon` assign the editor passes the
  palette browser was declared and never rendered, so no host could put an
  icon on a palette row; a type now looks the same in the palette as on the
  card the pick produces.
- A slot declaring `slot_style: :failure` renders in its own vocabulary - a
  solid error-family edge, its own `sb-slot--failure` class, and an ordinary
  flow edge where an interrupt rail draws a dashed escape.
- `StatifierBlocks.ViewModel.exit_edge/1` says which edge vocabulary a slot's
  exit is drawn in, and the editor stamps it as `data-exit-edge`.
- The editor takes an optional `datamodel` assign - the paths the host
  declares - and reports a config field whose declared datamodel path is not
  among them as an `:info` finding in the findings panel; with no datamodel
  supplied nothing is produced.
- Block types may declare a config field with `datamodel_path?: true`, saying
  its value is a path into the host's datamodel; `core.assign`'s `path` field
  carries it.
- `StatifierBlocks.Core.Parallel.join_label/1`, declared on the type's palette
  entry, so a renderer draws "continue at first" or "continue when all" from
  the block's config without learning the type's name.
- `StatifierBlocks.DurationInput` reads a typed duration for that control,
  accepting exactly what `StatifierBlocks.Core.Duration` compiles and naming
  the limit a refused value hit.

### Changed

- Every block's conventional `<final>` moves from `s_<block>__done` to
  `s_<block>__o_done` and now raises `done.outcome.<state id>.done` on entry,
  so compiled SCXML moves for every document; a host that stores compiled
  charts or provenance maps recompiles them, and a chart-level position saved
  against the old bytes no longer resolves.
- `Compiler.compiler_version/0` (and every compilation record's
  `compiler_version`) moves to `0.3.0` with the package, per ADR-0004
  decision 6, and is the third input to the byte-determinism guarantee: this
  release is where the outcome-final byte movement is recorded.
- `core.send` now emits its `<send>` with `id="<the block's state id>__send"`,
  so a delayed send can be named after it is armed.
- A delayed `core.send` is now cancelled by its scope: the compiler emits
  `<cancel sendid="..."/>` in the `<onexit>` of the nearest enclosing
  `<state>`, so a pending send does not outlive the sequence, group, region or
  lane that armed it. Charts containing a delayed `core.send` change bytes;
  every other chart is unchanged, `core.wait` timers included.
- `core.wait` accepts a predicator duration string (`1h30m`, `2d`, `3d8h`) as
  well as ISO-8601, stores whichever spelling the author typed, and compiles
  it to the emitted `delay` attribute; its refusal message names both
  spellings.
- `core.wait`'s declared `duration` default is now the predicator string `1h`
  rather than the ISO-8601 `PT1H`, so a newly inserted block starts from the
  spelling an author types. Both spellings stay accepted and each compiles to
  the same `delay` attribute, so no chart's emitted SCXML changes and no
  stored document has to be retyped.
- A `:duration` config field renders as one text control taking predicator
  duration strings, with `30s`, `15m`, `1h30m`, `2d` and `3d8h` shown beside
  it; ISO-8601 is still accepted and the author's string is stored verbatim.
- An empty `:duration` field omits its config key rather than storing an empty
  string, so a cleared field and a never-set field are the same value.
- An icon entry that declares no icon renders no tile, rather than an empty
  one, and a host's `icon` component is never called with a `nil` name.
- An icon name the shipped set does not have renders a neutral mark with the
  name in `data-icon`.
- A `slot_style` this editor does not recognize renders as an ordinary body
  slot instead of reaching the markup unresolved; its children are still
  rendered, still selectable and still saved.

### Removed

- `StatifierBlocks.Editor.Field.units/0`, `format_duration/2` and
  `parse_duration/1`, which served the retired value/unit control. Call
  `StatifierBlocks.Core.Duration.to_iso/1` to canonicalise a stored duration.

### Fixed

- The editor no longer renders a `U+25A1` white square in every icon tile when
  the host passes no `icon`. Passing one still overrides every tile, on the
  canvas cards and the palette rows alike.
- A delayed `core.send` in the body of a `core.group` that carries interrupt
  rules is now cancelled when the group is abandoned. Its `<cancel>` is
  emitted in the body region's `<onexit>` rather than the group's own, and
  abandoning the group exits the region without exiting the group, so the old
  placement never fired.

### Known limits

- A `core.foreach` list holding a `nil` item iterates to its end rather than
  stopping at it: `===` is strict, so only an out-of-bounds read is
  `undefined`.
- Two `core.foreach` blocks in one document may not bind the same name, even
  when neither is inside the other; the second is refused with a duplicate-id
  finding on its `item_as` field.

## [0.2.0] 2026-08-29

The editor ships. Campaign 014 graduated the authoring spike into the
package: `StatifierBlocks.Editor` renders from `assets/` with a documented
`--sb-*` theming surface, a drag marks the slots that accept a block and can
say why a slot refused, and a host registers its own block types through
`Palette.from_modules/2`. The `core.*` vocabulary grows by `core.invoke`,
`core.raise`, `core.assign` and `core.send`; the compiler now evaluates
predicator conditions, refuses slot-arity and undeclared-slot violations, and
adapts its findings into the shape the editor renders.

Dependency floor: `statifier ~> 2.2` (was `~> 2.0`); `predicator ~> 9.0` is
now a direct dependency.

### Added

- `core.raise` raises an event for an enclosing group's interrupt rules.
- `core.assign` writes a literal to a datamodel path.
- `docs/theming.md`: the theming guide - the three tiers of the `--sb-*`
  surface, the scheme token, per-block-type accents, and a complete host
  theme that sets custom properties and nothing else.
- `core.send` sends an event, now or after a delay.
- A block type may declare `slot_outcome_key` in its palette entry, naming the
  config key the blocks in one of its slots carry their outcome under, so a
  renderer can route an interrupt rule's escape without branching on a type
  name; the declaration reaches the view model as `Slot.outcome_key` and the
  resolved value as `Node.outcome`.
- `StatifierBlocks.BlockType.slot_outcome_key/2` and
  `StatifierBlocks.BlockType.outcome_name/2` read that declaration totally: a
  malformed declaration or value is refused rather than repaired, and reads as
  no declared outcome.
- A block type may declare `accent_token`, the NAME of a `--sb-*` property,
  and the editor stamps it on that type's cards and palette rows. Two rules
  in the stylesheet read it; no rule and no module names a block type
  (ADR-0005 amendment 14d, consumption side).
- `StatifierBlocks.Finding.severity_class/1`, and `:info` as a third
  severity for advisory findings (decision 11, amended 2026-08-29). Nothing
  emits one yet; only `:lint` may.
- A form whose config the gate has not accepted names the fields that are
  outstanding, says why nothing is stored, and offers "Discard edits". A
  draft was never a command, so it cannot be undone - it can only be thrown
  away, and that gesture had nowhere to live.
- `:expression` and `:duration` controls carry a placeholder. A bare
  `:string` still carries none: there is nothing a type that wide can
  suggest.
- A theme audit test over the stylesheet, failing in both directions: a
  `var(--sb-*)` with no declaration, and a declared token no rule reads (14e).
- `StatifierBlocks.SlotValidation`, a palette-aware whole-document check for
  a block's declared slots (`:undeclared_slot`) and each declared slot's
  arity (`:slot_arity_violated`).
- `StatifierBlocks.Predicates` evaluates a condition expression against a
  binding context through predicator, returning a boolean or a tagged error.
- `StatifierBlocks.Predicates.TruthTable` builds a checked truth table over
  fixture rows, applying first-match-wins arm ordering.
- `StatifierBlocks.Finding.from_compiler/2` and `from_compiler_all/2` adapt a
  compiler finding into the presentation shape the editor renders, so a host
  can route compile findings through `ViewModel.build/3`.
- `StatifierBlocks.Assignability.seam_reason/4`, `finding_reason/2` and
  `seam_reasons/3` name why a data-flow seam came out the way it did:
  `:not_assignable` and `{:fixable_by, block_id}` for a refusal, and
  `:source_untyped` / `:target_untyped` / `:both_untyped` for a seam that
  passed only because a block declared no type. `seam_reasons/3` is how a
  host finds the parts of its palette it has not typed yet.
- `StatifierBlocks.Assignability.target_verdicts/4` returns every position
  `valid_targets/4` enumerates with its full verdict, and
  `StatifierBlocks.Edit.Targets.slot_verdicts/3` projects those to slots -
  the accepting ones and the reason each refusing one gives.
- The editor stamps a refused slot's reason as `data-drop-reason` beside
  `data-drop`, so a hover affordance can explain a refusal with no
  round-trip and no JavaScript.
- A `core.invoke` block type: it names an invoke type for the host to run,
  sends datamodel values along as `<param>`s, writes the result where its
  `assign_to` names, and takes an optional `on_error` subtree entered on a
  permanent invoke failure.
- `StatifierBlocks.Compiler.Context.outcome_id/2` and `outcome_event/2`, for a
  block type with more than one way to finish: one `<final>` per outcome, and
  the `done.outcome.<state id>.<outcome>` event a parent wires on.
- `StatifierBlocks.Palette.from_modules/2`, the registration API a host uses
  to contribute its own block types: an ordered, explicit list of
  `{type_name, module}` registrations, with `core: true` to sit on top of
  the `core.*` vocabulary. Later entries win. It is still a value - no
  global registry, no application-configuration lookup, and no discovery
  pass.
- A palette entry may declare `badge`, a short chip for the card header, and
  `join_label`, a one-argument function of the block's config phrasing the
  join marker under a side-by-side arrangement (ADR-0002 amendment B).
  `StatifierBlocks.BlockType.badge/1` and `join_label/2` read them.
- Both readers are total and **refuse rather than repair**: a chip that is
  blank, carries a newline or tab, or runs past 24 characters is dropped,
  not clipped, and a `join_label` that raises degrades to the editor's own
  word rather than taking the canvas down.
- `accent_token`, `badge` and `join_label` are admitted keys of
  `t:StatifierBlocks.BlockType.palette_entry/0`.
- The README carries a worked host example - a `myapp.risk_hold` block type
  registered beside the core vocabulary, with a badge and an accent token -
  and it is executed on every build rather than trusted.

### Changed

- `Compiler.compiler_version/0` (and every compilation record's
  `compiler_version`) moves to `0.2.0` with the package, per ADR-0004
  decision 6: a record compiled by 0.1.0 identifies itself as such.
- `--sb-drop-ok-border` moves from `#2f9e5f` to `#2c945a`. The outline that
  says a slot accepts a drop was 2.93:1 on the sunken surface, under the 3:1
  a mark carrying information is held to; the tint follows it.
- `predicator` is now a direct dependency (`~> 9.0`), because
  `StatifierBlocks.Core.Duration` calls `Predicator.Duration.parse/1`. It
  already resolved transitively through `statifier`, so the resolved version
  does not move; naming it records the call.
- The editor's stylesheet carries a scoped reset, and every selector in it
  matches the container through `:where(.sb-editor)` so a component rule
  always wins (ADR-0005 amendment 14b).
- `--sb-color-scheme` is declared and read as `color-scheme` on the editor's
  own container, so the parts of a control the browser paints - a `<select>`'s
  drop-down, the scrollbars, the caret - follow the theme (14a).
- The `--sb-*` surface gains the space, type and shape scales, a third text
  step, a strong border, status tints, the drag seam's drag-time height, and
  the canvas sizing constants that were literals in rules.
- A `:secondary` and a `:failure` slot are both placed as attached rails,
  and a container declaring either is drawn as a boundary box - the rail
  partition, not the `:secondary` partition (amendments 10c and 10h).
- `--sb-drop-no-opacity` is **retired**. A drag now marks the slots that
  accept the block and leaves the rest alone rather than dimming them; the
  disabled-control opacity it doubled as is `--sb-disabled-opacity`.
- The compiler now refuses a document whose slots violate their declared
  arity or name a slot the block type does not declare, instead of silently
  dropping those children from the emission.
- Reasons change no verdict: `:unknown` stays permissive in both positions,
  `Assignability.validate/3` reports exactly the findings it did before, and
  neither finding tuple gained a field.
- `slot_style` admits a third value, `:failure`, for a slot whose children
  are an in-band continuation taken on a bad outcome; `core.invoke` declares
  it for `on_error`.
- The role namespace beginning `o_` is reserved for outcome finals;
  `Context.role_id/2` now refuses such a role with a `:reserved_role` finding.

### Fixed

- The editor's root rule sets `font-family` rather than the `font`
  shorthand, so `--sb-font` reaches the editor. `font: <family-list>` is not
  a valid shorthand, so the whole declaration was dropped and the editor's
  text did not inherit the host page's font as the token promised.

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

[0.2.0]: https://github.com/riddler/statifier_blocks/releases/tag/v0.2.0
[0.1.0]: https://github.com/riddler/statifier_blocks/releases/tag/v0.1.0
