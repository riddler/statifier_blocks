---
date: 2026-09-01
issue: sb-uag7
status: draft
---

# core.drafts and core.placeholder Implementation Plan

## Overview

The record for the drafts shelf and the gap marker is accepted and on main:
ADR-0002's amendment of 2026-08-31 (G9-G13), ADR-0003's (A1-A3), ADR-0004's
(D1-D6) and ADR-0005's (10s-10v, 11n). All four say the same thing from four
sides, and G11 states outright that the record runs ahead of the modules.
This plan builds the modules to the record. Bead: sb-uag7.

Four surfaces move: the `core.*` vocabulary gains two types, the Structure
stage gains two errors, the Emit stage gains two warnings and one elision,
and the editor gains a fourth `slot_style`. The edit algebra is untouched
(G13, ADR-0005 consequences) - parking and placing are ordinary Moves, and
this plan adds no command.

## Current State Analysis

**`Palette.core_types/0` registers thirteen** (`lib/statifier_blocks/palette.ex:87-103`),
and `test/statifier_blocks/core/core_types_test.exs:23` asserts that literal.
`lib/statifier_blocks/core.ex:12-27` carries the matching thirteen-row table.
G11 predicts exactly this gap and names this bead as what closes it.

**The compile pipeline is six stages** (`lib/statifier_blocks/compiler.ex:295-309`):
Document, Resolve, Config, Structure, Chart-use, Emit, then Chart. Structure
(`structure_stage/3`, `:466-484`) walks the *document* and concatenates
`SlotValidation.validate/2` and `Assignability.validate/3`; Emit and Chart-use
walk the *resolved tree*. That split is what makes D1 and G9c compatible with
each other: the Config stage runs over every block in the document including
every block on the shelf, and only the resolved tree the emitter walks is
pruned.

**Emit-stage warnings already have a channel.** `emit_stage/3` returns
`{:ok, {emission, warnings}}` (`compiler.ex:544-553`) and `chart_stage/5`
concatenates that list into `%Compiled{}.warnings` (`compiler.ex:1130`).
`shadowed_finding/2` (`compiler.ex:633-644`) is the shape to copy: an ordinary
`Finding.new(:emit, reason, message, block_id: ..., severity: :warning)`.
`Finding.new/4` derives `code` from the reason tuple's tag and `fault` from
the stage, so both new warnings get `code` and `fault: :author` for free.

**`module.emit/2` has no warning-return channel.** Its contract is
`{:ok, %Emission{}} | {:error, reason}`, and G13 forbids a tenth callback. So
both new warnings are minted by the compiler from the document/resolved tree,
not by the two type modules.

**The data-flow walk has no "reset to `:unknown`" primitive.**
`Assignability.inbound_type/4` (`assignability.ex:440-457`) either reads the
previous sibling's `produces` (`index > 0`) or recurses to the parent's own
inbound (`index == 0`). A2 needs both arms to answer `:unknown` inside a
shelf's `body`, so this plan adds a guard clause ahead of both.

**Nothing is minted for a block the emitter never visits.**
`Compiler.StateId` is a pure derivation called only from a running `emit/2`,
and `Provenance` is populated only by `Attribution.stamp/3` walking the
emitted tree (`compiler.ex:735-753`). D2's "no provenance entry, no state id"
therefore holds by construction once the shelf is pruned from the resolved
tree, with no second mechanism.

**The editor's slot-style vocabulary is spelled once.**
`ViewModel` `@slot_styles [:primary, :secondary, :failure]` and
`@rail_styles [:secondary, :failure]` (`view_model.ex:390-391`) are the only
runtime copy; `slot_style/2` (`:1163-1171`) degrades anything outside
`@slot_styles` to `:primary`, which is 10i's posture and which 10v says is
the one bad rendering `:tray` could produce. `boundary?/1` is
`Enum.any?(slots, &rail?/1)` (`:571-583`), so keeping `:tray` out of
`@rail_styles` is the whole of 10t's "contributes no boundary".

**Three connector sources touch a slot's children**
(`connectors.ex:412-420`): `adjacency_edges/2` (between siblings, over every
slot with no style filter), `entry_edges/2` (into `ViewModel.body_slots/1`,
which today is `Enum.reject(slots, &rail?/1)`), and `rail_edges/2` (exits,
already filtered to rails only). 10u needs the first two to skip a `:tray`
slot; the third needs no change.

**The shelf is also a child of the root's body.** 10u's "none entering the
tray, none leaving it" is not only about the tray slot: the shelf *node* sits
in the root's `body` among ordinary steps, and `adjacency_edges/2` would chain
it to its neighbours. G9a's compiler rule - the sibling before is adjacent to
the sibling after - has an exact rendering counterpart here, and this plan
implements it as the same partition on both sides.

**No new theme token is affordable.** `theme_audit_test.exs` demands two-way
coverage, a tier line, and - for a colour token - an entry in the contrast
accounting *and* a restatement in `docs/theming.md`. `docs/theming.md` is
outside this bead's file map. The tray therefore reuses `--sb-border`, which
is the muted neutral line token the audit already carries as a recorded design
ruling, and spells "flat" as `box-shadow: none`. ADR-0005's consequences leave
that call to this bead; the answer is no new token.

**`placement_test.exs`'s biconditional is falsified by the record, on
purpose.** It asserts
`admitted?(parent, slot, child) <=> (slot == "interrupts") == (child == Core.OnEvent)`
over the whole vocabulary. A `:draft_shelf` child is refused by every `[:step]`
slot (G9b), which the right-hand side would predict admitted; and the shelf's
own `body` accepts `:any` (A1), which admits `core.on_event` outside an
`"interrupts"` slot. Both are the record working as designed, so the property
is restated rather than weakened - see Phase 1.

## What this plan does NOT change

- **The edit algebra.** No command added, none amended (G13, ADR-0005).
- **`docs/adr/**`.** The record is accepted. If the build contradicts it, that
  is a stop-and-report, not an amendment.
- **`palette_entry/0`'s key set** (10s) and **the nine callbacks** (G13).
- **The document schema.** `schema_version` stays `1` (G13).
- **The publish gate.** What a host does with `%Compiled{}.warnings` is the
  host's (D4).

## Two decisions the record defers to this bead

ADR-0005's "Deferred, named rather than guessed" leaves two. Both are answered
from the built surface below and recorded in the PR body and the bead note,
not in the record.

**Where the tray is drawn: the canvas, at the foot.** The drawer is the wrong
home on its own stated test - `drawer.ex`'s moduledoc fixes 1A as "tabular and
document-level", and a shelf is a container's body slot rendered wherever its
block sits, which is neither. A bespoke strip component is refused by decision
13 and by `slot.ex`'s own rule that there is no `Group` component and no
`Parallel` component and there must never be one. What is left is the surface
that already exists: the shelf renders through the ordinary recursive
`BlockNode`/`Slot` pair inside `.sb-canvas`, and because G12a admits it only
as a direct child of the root's `body`, drawing it *after* that slot's flow
children puts it at the foot of the canvas with one partition and no new
component. That partition is the same one 10u's connector suppression needs,
so the answer costs nothing that the accepted text did not already require.

**Palette-to-tray drop: permitted, by doing nothing.** A drop is an Insert and
the tray's `slot_accepts` is `:any` (A1), so the existing target computation
already admits a palette drop onto the tray. Forbidding it would take new
machinery to refuse what the declaration admits, and it would refuse hardest
the half-built fragment A1 says the shelf exists to hold. Phase 4 pins this
with a test rather than leaving it to the absence of a rule.

## Desired End State

`Palette.core_types/0` registers fifteen. A document with a misplaced or
duplicated shelf refuses in the Structure stage with the two named codes. A
document with a shelf compiles to bytes identical to the same document with
the shelf emptied and to the same document with the shelf deleted, carries
`:draft_blocks_present` once when the shelf is occupied, and carries one
`:placeholder_block` per marker. The editor draws the tray at the foot of the
canvas as separate cards with no connectors, no boundary box, and findings on
the fragments.

## Phases

### Phase 1: the two block types and the registry

**Files**

- new `lib/statifier_blocks/core/drafts.ex`
- new `lib/statifier_blocks/core/placeholder.ex`
- `lib/statifier_blocks/palette.ex` (`core_types/0`, 13 -> 15)
- `lib/statifier_blocks/core.ex` (the moduledoc table, +2 rows)
- `lib/statifier_blocks/block_type.ex` (`palette_entry` typespec: `| :tray`)
- `test/statifier_blocks/core/core_types_test.exs` (15, +2 fetches)
- `test/statifier_blocks/core/conformance_test.exs` (`:tray` in the style enum)
- `test/statifier_blocks/core/placement_test.exs` (restated property)
- new `test/statifier_blocks/core/drafts_test.exs`
- new `test/statifier_blocks/core/placeholder_test.exs`

**`core.drafts`** answers G9 exactly: `slots/1` returns
`[{"body", :any, "Drafts"}]` for every config, `config_schema/1` `[]`,
`validate_config/1` `:ok`, `current_version/0` `1`, `io/1`
`%{kinds: [:draft_shelf], slot_accepts: %{"body" => :any}}`, no `outcomes/1`.
`palette_entry/0` declares `slot_style: %{"body" => :tray}` (10s).

`emit/2` is required by the behaviour and, per D1, is never called by the
compiler. It answers with the smallest inert state (`Emit.ordered(context, [])`),
which is what `conformance_test.exs`'s shape assertion requires of every core
type, and its moduledoc says plainly that the compiler's elision - not this
return - is what makes D1 true, and names the byte-identity test in Phase 3 as
the guard. A return that refused would trade a real guarantee for a
conformance exemption.

**`core.placeholder`** answers G10 via `use StatifierBlocks.BlockType`: the
injected defaults give `slots/1` `[]`, `current_version/0` `1` and the
permissive `io/1` A3 asks for in full (`%{}` is stated by `block_type.ex`'s
moduledoc to be exactly what an absent `io/1` means). It overrides
`config_schema/1` with the single `note` field ("What goes here", `:string`,
`required?: false`, default `""`), `validate_config/1` to refuse a non-string
`note` and nothing else (G10b: an empty note is not a finding), and `emit/2`
with D5's shape - `Emit.ordered(context, [])`, one compound state whose
`initial` points at a single `<final>`, no `<log>`, no raise, no data.

**The restated placement property.** `placement_test.exs`'s moduledoc and
biconditional gain the two clauses the record introduces, each citing where it
comes from:

1. the shelf's own `body` accepts `:any` (A1), so it admits every core child
   and is enumerated separately rather than folded into the "interrupts"
   biconditional;
2. a `:draft_shelf` child is refused by every other core slot (G9b), so the
   right-hand side conjoins `child != Core.Drafts`.

Both new clauses get their own directed assertions, so the property is
strengthened by the restatement rather than merely made to pass.

**Success (automated)**: `mix quality` green; `map_size(Palette.core_types()) == 15`;
conformance generates and passes for both new types; the restated placement
property passes in both directions.

### Phase 2: the structure rule

**Files**

- new `lib/statifier_blocks/shelf.ex`
- `lib/statifier_blocks/compiler.ex` (`structure_stage/3`, new `shelf_finding/1`)
- new `test/statifier_blocks/shelf_test.exs`
- `test/statifier_blocks/compiler/findings_test.exs` (the two codes end to end)

`StatifierBlocks.Shelf` owns the two facts `io/1` cannot carry (G12) and the
identity predicates every other surface needs. It keys on the **type name**,
`"core.drafts"` and `"core.placeholder"`: that is what the record says
throughout ("a `core.drafts` block"), ADR-0002 decision 1 puts the name in the
document, `core.` is reserved (G13), and a name test needs no palette resolve
and creates no dependency from the compiler or the editor onto a core type
module. The `:draft_shelf` kind is not redundant with it and is not replaced
by it: the kind does G9b's placement work through the ordinary assignability
intersection, with no code in this plan at all, and this module carries only
the two facts the kind provably cannot express.

`validate/1` walks `Document.blocks/1` and returns, in document order:

| Finding tuple | When |
|---|---|
| `{:drafts_block_misplaced, id}` | a shelf whose parent is not the root, or whose slot is not the root's `"body"` |
| `{:duplicate_drafts_block, id}` | the second and every later shelf, in document order (D3) |

`structure_stage/3` concatenates them with the slot and assignability findings
in the existing `case a ++ b do` shape; `shelf_finding/1` mints
`Finding.new(:structure, reason, message, block_id: id)`, which defaults to
`severity: :error` and `fault: :author` (D3) and derives `code` from the tuple
tag.

**Success (automated)**: a shelf nested in a group refuses with
`:drafts_block_misplaced` anchored on the shelf; two shelves refuse with
`:duplicate_drafts_block` anchored on the second only and not the first; a
shelf at the root's `body` produces neither; both arrive as `:structure`
findings with `fault: :author` and no `config_key`.

### Phase 3: the compiler stance

**Files**

- `lib/statifier_blocks/compiler.ex` (elision step; the two warnings)
- `lib/statifier_blocks/assignability.ex` (`inbound_type/4` guard)
- new `test/statifier_blocks/compiler/drafts_test.exs`
- `test/statifier_blocks/assignability_test.exs` (the shelf's inbound rule)

**Elision.** A step between `structure_stage/3` and `chart_use_stage/2`
returns `{pruned_node, warnings}`: the root's resolved `body` children are
partitioned on `Shelf.shelf_type?/1`, the shelf is dropped, and
`:draft_blocks_present` is minted once, anchored on the shelf, when the
shelf's `body` is non-empty (D4). Pruning before Chart-use and not only before
Emit is D1 read literally - "its contents contribute nothing" - so a shelved
`core.subchart` cannot trip a child-use refusal for a chart it never reaches.
Structure has already run, so by this point any shelf still present is a
direct child of the root's `body` and there is at most one.

**`:placeholder_block`.** The pruned resolved tree is walked once and one
warning is minted per marker, anchored on it, carrying the author's `note` in
the message when they wrote one (D4, G10b).

**The inbound rule.** A guard clause ahead of both `inbound_type/4` arms: when
the parent block is a shelf, the answer is `:unknown` regardless of index
(A2). The walk inside each fragment is untouched, which is the property A2
says makes the shelf worth having.

**The acceptance property (D1).** One test compiles three documents that
differ only in their shelf - one holding four fragments, one with an empty
shelf, one with no shelf at all - and asserts byte-identical `scxml` and
byte-identical serialized provenance across all three. A second asserts D6:
the three `document_hash` values differ while the chart identity does not.

**Success (automated)**: the three-way byte identity holds; provenance and
`StateId` carry no entry for any shelved block; `:draft_blocks_present` is
one per document and absent for an empty shelf; `:placeholder_block` is one
per marker and carries the note; every one of them is a warning on a
successful compile, never a refusal; a broken seam *inside* a parked fragment
is still reported and the fragment's position on the shelf never is.

### Phase 4: the editor tray

**Files**

- `lib/statifier_blocks/view_model.ex` (`@slot_styles`, typespecs,
  `body_slots/1`, `tray?/1`, `shelf?/1`)
- `lib/statifier_blocks/connectors.ex` (`adjacency_edges/2` partition)
- `lib/statifier_blocks/editor/slot.ex` (`sb-slot--tray`; shelf-last children)
- `assets/css/statifier_blocks.css` (`.sb-slot--tray`, existing tokens only)
- new `test/statifier_blocks/editor/tray_test.exs`
- `test/statifier_blocks/connectors_test.exs` (no tray edges)

`:tray` joins `@slot_styles` and not `@rail_styles`, which is 10t's partition
row. `body_slots/1` rejects tray as well as rail, which closes the entry-edge
question and the arrangement question in one edit, exactly as the file's own
comment says rails are rejected for the reason `Connectors` rejects them.
`adjacency_edges/2` skips a `:tray` slot outright (no edges between fragments)
and, in every other slot, chains over the slot's children with shelf nodes
removed - the rendering counterpart of G9a, so the sibling before the shelf is
adjacent to the sibling after it and nothing enters or leaves the shelf.
`rail_edges/2` is untouched: a tray is not a rail, so it already draws no
exit.

The `Slot` component stamps `sb-slot--tray` and renders a slot's shelf
children after its flow children, which is the deferred "where" answer above.
The stylesheet gives the tray a muted `--sb-border` top edge and
`box-shadow: none` on its cards; no `--sb-*` token is added, so the two-way
audit and the tier table stay as they are.

**Success (automated)**, all via LiveView `render_*`/`has_element?` against the
existing `EditorLiveCase` harness - no browser, no ports:
`[data-slot-style="tray"]` present; `.sb-slot--rail` and `.sb-node--boundary`
absent on the shelf; no `.sb-edge` between two fragments, into the tray, or
out of it; a flow edge present between the shelf's two root-body neighbours;
the shelf rendered after the root body's flow children; a `:config` finding on
a parked block rendered beneath its field and counted on the folded tray's
badge; `:draft_blocks_present` rendered on the tray's own chrome; a
palette-to-tray drop offered as a valid target.

### Phase 5: the changelog fragment

`changelog.d/sb-uag7.md`, one `### Added` group naming the two public block
types, the two Structure errors, the two Emit warnings and the `:tray` slot
style, in the terms a caller of the public API would recognise.

## Testing Strategy

Repo house style: every new test that asserts `lib/` behaviour is sabotaged by
hand - the covered code broken, the test confirmed red, the code restored from
a scratchpad backup (never `git checkout --`), and the mutation noted in one
`# Sabotage:` line above the test.

Gate: full `mix quality` per phase, under the campaign's machine-slot and
`gate-statifier_blocks` lock idiom. A `--profile loop` run is never evidence.

## Manual Verification (deferred to the operator)

Machine-checkable items are covered above and by `/wurk:verify --unattended`.
Left for human eyes, deferred and never confirmed by an agent:

1. Whether the tray at the foot of the canvas *reads* as a shelf beside the
   document rather than as a trailing step, at the default zoom.
2. Whether the muted `--sb-border` edge is distinguishable from the ordinary
   slot edge in both the light and dark schemes.
3. Whether the deferred "where the tray is drawn" answer should be brought
   back to ADR-0005 as a rule, or left revisable as the record allows.

## References

- ADR-0002 amendment (2026-08-31), G9-G13 - `docs/adr/0002-block-type-behaviour.md:2049`
- ADR-0003 amendment (2026-08-31), A1-A3 - `docs/adr/0003-assignability.md:723`
- ADR-0004 amendment (2026-08-31), D1-D6 - `docs/adr/0004-compiler-provenance.md:2246`
- ADR-0005 amendment (2026-08-31), 10s-10v, 11n - `docs/adr/0005-liveview-editor.md:3841`
- campaign-024 rulings R-a (the marker joins the shelf's record) and R-b (the
  placement facts are Structure-stage findings)
