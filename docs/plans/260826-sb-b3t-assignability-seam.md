# The assignability seam (ADR-0003) Implementation Plan

## Overview

ADR-0003 as code: `StatifierBlocks.Assignability`, the one decision function
both the editor (ADR-0005, `sb-w50`) and the compiler (ADR-0004, `sb-iwz`)
will call, plus the `Assignability.Relation` behaviour a host implements to
widen the relation, plus the palette field that carries it. Bead: `sb-b3t`.

The record's "The relation as typespecs" section is the API contract, taken
verbatim: types `type_expr/0`, `kind/0`, `produces/0`, `io/0`, `context/0`,
`target/0`, `finding/0`, and functions `check/5`, `valid_targets/4`,
`validate/3`, `inbound_type/4`, `assignable?/3`. The record's closing line
pins `c:StatifierBlocks.BlockType.io/1` from `term()` to
`StatifierBlocks.Assignability.io()`, and that pin is this bead's deliverable
too.

The bead also collects a deliberate debt `sb-w6d` left: `test/support/core_fixtures.ex`
carries `admits?/3`, `kinds/2`, `slot_accepts/3` and `io/2` as a test-only
spelling of ADR-0003 decision 3, with a moduledoc saying so and naming this
bead as where they move. They move here.

Out of scope, by ADR and by the bead's own boundary:

- `CoreFixtures.check/2`, the palette-aware document walk (resolution, config,
  arity and undeclared-slot findings). That walk is `sb-da9`'s and it stays in
  `test/support/`. Only its kind-admission helper call is redirected.
- The compiler (`sb-iwz`): whether a finding refuses emission, and whether type
  expressions appear in emitted SCXML. ADR-0003 decision 9 assigns both there.
- The editor (`sb-w50`): all presentation - highlighting, greying, drop
  blocking, finding copy.
- Any version bump, release, or `CHANGELOG.md` edit. A `changelog.d/sb-b3t.md`
  fragment is the whole changelog surface (`changelog.d/README.md`).

## Current State Analysis

Branch `sb-b3t-assignability`, cut from `sb-w6d-core-block-types` (stacked and
unmerged). Baseline `mix quality --profile loop` is green in this worktree at
`9340bdd`: 207 tests, format, compile with warnings-as-errors, credo
`--strict`.

What is already in place, and what each phase can lean on:

| Module | What it gives this bead |
|---|---|
| `lib/statifier_blocks/block.ex` | `Block.t()`, `id/0`, `type_name/0`, `slot_name/0`, `config/0`, `json/0`. Struct only - `new/2` is the sole public function |
| `lib/statifier_blocks/document.ex` | `blocks/1` (pre-order, slots in UTF-8 sorted order), `fetch_path/2` returning `{:ok, [{parent_id, slot, index}]}` or `:error` for a block not in the document, `validate/1` |
| `lib/statifier_blocks/palette.ex` | `%Palette{types: %{}}`, `new/1`, total `fetch/2`, migrating `resolve/2`, `core/0`, `core_types/0` (seven entries, including `core.group`) |
| `lib/statifier_blocks/block_type.ex` | the nine callbacks; `io/1` is optional and currently specced `term()` |
| `lib/statifier_blocks/core/*.ex` | every core type already implements `io/1` to ADR-0003 decision 2's shape |
| `test/support/core_fixtures.ex` | the four `myapp.*` toy types, `palette/0`, `core_modules/0`, `valid_config/1`, the four helpers to be migrated, and `check/2` |

What is **not** in place and has to be written: nothing in `test/` today
implements `Assignability.Relation`, and `CoreFixtures`' existing `myapp.*`
types declare only the bare `"record"` type expression - none of the
`myapp.credit_card_txn` / `myapp.settled_txn` / `myapp.card_txn` widening
vocabulary this bead's fixtures need. Phases
3 through 5 all need both. They go in a **new** `test/support/assignability_fixtures.ex`
(`StatifierBlocks.AssignabilityFixtures`), not in `core_fixtures.ex` - Phase 2
is slimming that module, and the two support files then have one subject each:
`CoreFixtures` is the core vocabulary and `sb-da9`'s stand-in walk,
`AssignabilityFixtures` is ADR-0003's worked example. It carries the
worked-example toy types (`myapp.authorize`, `myapp.settle`,
`myapp.post_to_ledger`, `myapp.on_chargeback` - ADR-0003's worked example
re-expressed in the family's canonical credit-card example domain per the
umbrella's `docs/terminology-firewall.md`, structurally isomorphic to the
record's own table), a
`Widens` module implementing `Assignability.Relation` over the record's
`@widens` map, a `Deny` module answering `false` to everything (the floor case
Phase 3 and Phase 5 both need), `palette/1` building the palette with or
without a relation module, and the worked-example document. `test/support/` is
excluded from the coverage floor, so nothing in it has to be covered - but
everything it exercises in `lib/` does.

The core `io/1` declarations as shipped, which every structural test in this
bead reads:

| Type | `io/1` |
|---|---|
| `core.sequence` | `kinds: [:step]`, `produces: {:passthrough, "body"}`, `slot_accepts: %{"body" => [:step]}` |
| `core.group` | `slot_accepts: %{"body" => [:step], "interrupts" => [:interrupt_handler]}` (+ kinds/produces) |
| `core.resumable_group` | same slot map as `core.group` |
| `core.branch` | `kinds: [:step]`, `produces: :unknown`, `slot_accepts` derived per declared arm slot |
| `core.parallel` | `kinds: [:step]`, `produces: :unknown`, `slot_accepts` derived per declared lane slot |
| `core.wait` | `kinds: [:step]` |
| `core.on_event` | `kinds: [:interrupt_handler]` |

Constraints that bind every phase:

- **The gate is `mix quality`, full, and only the full run is the advancement
  gate.** `--profile loop` is the inner loop and is never evidence of green
  (CLAUDE.md, "This repo's own gate rules").
- **Coverage floor is 90%** with `test/support/` excluded (`coveralls.json`).
  Every new `lib/` line needs a test in the same phase, which is part of why
  the phases below are cut by function group rather than by file.
- **Sabotage note on every new test asserting `lib/` behaviour**, one line
  above the test, in the wording the existing tests use ("Sabotage: <mutation>
  - red on <assertion>").
- **No property-testing dependency exists** and adding one is a gate decision
  this bead does not get to make. `stream_data` is not in `mix.exs` or
  `mix.lock`. The bead's "property test" is therefore satisfied the way
  `placement_test.exs` already satisfies its own: exhaustive enumeration over
  a finite constructed palette and document, which is a stronger statement
  than sampling and needs no dep.
- Repo conventions: `@spec` on every public function, errors as events (never
  rescue-to-default at a leaf), state-ish argument first, `mix format` run by
  hand, no AI attribution.

### Contract checks against the ADRs, done up front

ADR-0003 is accepted and nothing in the current code contradicts it. Four
places were checked specifically:

1. `Palette`'s struct has no `assignability` field yet. ADR-0002's typespec
   appendix shows `%Palette{types: ...}`; ADR-0003 decision 6 shows
   `%StatifierBlocks.Palette{types: %{...}, assignability: MyApp.Blocks.Types}`.
   ADR-0003 is the later accepted record and names the field, so the field name
   is fixed and ADR-0002's appendix is superseded on that one line. See the
   open questions for whether ADR-0002 gets an editorial amendment; this bead
   does not write one.
2. `io/1` is `@optional_callbacks` and specced `term()`. Pinning it to
   `Assignability.io()` narrows a return type the seven core types already
   satisfy (each returns a map whose keys are a subset of the four).
3. `CoreFixtures.kind_findings/4` emits a four-element
   `{:kind_not_admitted, child_id, parent_id, slot}` tuple, while ADR-0003
   decision 8 fixes the shipped finding at six elements
   `{:kind_not_admitted, block_id, parent_id, slot_name, kinds, accepts}`.
   These are not in conflict: the four-tuple belongs to `check/2`, which is a
   test-only stand-in for `sb-da9`'s walk and owns its own finding vocabulary
   until that bead lands. This bead redirects the *decision* and leaves the
   tuple alone (see Phase 2).
4. `Core.Sequence.io/1` declares `slot_accepts: %{"body" => [:step]}` where
   ADR-0003's worked example shows only `produces: {:passthrough, "body"}` for
   that type. The record's example is illustrative, not exhaustive, and the
   shipped declaration is what the accepted decision 3 mechanism is for. No
   contradiction; the placement biconditional in `placement_test.exs` depends
   on the shipped form.

## Desired End State

`StatifierBlocks.Assignability` exists in `lib/`, implements ADR-0003's
typespec block exactly, and is the only implementation of the relation in the
repository. `StatifierBlocks.Assignability.Relation` is the host seam.
`%Palette{}` carries `assignability`, defaulting to `nil`, and `Palette.new/1`
still works unchanged. `c:StatifierBlocks.BlockType.io/1` is pinned.
`test/support/core_fixtures.ex` carries the `myapp.*` types, the fixture
accessors and `check/2` - and none of the four assignability helpers, because
`placement_test.exs`, `conformance_test.exs` and `check/2` itself all call the
shipped module.

## Design notes the phases implement

These were derived from the record and verified against the code; they are
recorded here so no phase re-derives them.

### The public primitives, and why they exist

ADR-0003's typespec block lists five functions. This bead ships four more
public primitives alongside them:

```elixir
@spec io(module(), Block.config()) :: io()
@spec kinds(module(), Block.config()) :: [kind()]
@spec slot_accepts(module(), Block.config(), Block.slot_name()) :: [kind()] | :any
@spec admits?({module(), Block.config()}, Block.slot_name(), {module(), Block.config()}) :: boolean()
```

This is a **deliberate widening of the record's listed surface**, and it does
not weaken decision 7's "one decision function" property, because these are
the one implementation that `check/5`, `valid_targets/4` and `validate/3` are
built out of, not a second path around them. They are public for two reasons
the record's own acceptance criteria create: the kind gate has to be testable
in isolation to state the both-directions placement property over the finite
core vocabulary, and `CoreFixtures.check/2` - `sb-da9`'s stand-in - has to
delegate to the shipped rule rather than keep a copy of it. Their bodies are
the four helpers being deleted from `test/support/`, moved verbatim in
behaviour.

Defaults, per ADR-0003 decision 5: an absent `io/1` callback (or a module that
is not loadable) is `%{}`; absent `:kinds` is `[:step]`; absent `:slot_accepts`
entry is `:any`; absent `:consumes` and `:produces` are `:unknown`. Checked
with `Code.ensure_loaded?/1` plus `function_exported?/3`, the pattern
`Palette.resolve/2` and `CoreFixtures.io/2` already use.

### `assignable?/3` - the ordered relation

Exactly decision 6's four steps, in that order, and the order is the contract:

1. either side `:unknown` -> `true`
2. `produced == consumed` -> `true`
3. `palette.assignability == nil` -> `false`
4. `module.assignable?(produced, consumed)`

Reflexivity holds without the host because step 2 short-circuits. The host
callback is only ever reached after identity has failed, so it can only widen.
Step 4 is guarded the same way every other optional callback in this package
is: a module that is not loadable or does not export `assignable?/2` yields
`false` rather than raising, keeping the function total and keeping a
misconfigured palette from turning a validation pass into an exception.

### `produces` resolution, and why it terminates

`produces` resolves as decision 4 states: a type expression is itself;
`:unknown` is `:unknown`; `{:passthrough, slot}` is the `produces` of the last
block in that slot, or, when the slot is empty, the block's own inbound type.

Termination argument, which the moduledoc states and a test pins: every
recursive step moves to a strictly earlier position in the document's
pre-order. Resolving a `{:passthrough, slot}` on block `B` either descends to
the last child of `B`'s slot (later than `B`, but still strictly earlier than
whatever position asked, since that position is after `B`), or falls back to
`B`'s own inbound type, which is either `B`'s previous sibling or - at index 0
- `B`'s parent's inbound. Previous-sibling and parent are both strictly earlier
in pre-order, and the root terminates at the context's entry type. Pre-order
rank over a finite tree is a well-founded measure, so the recursion cannot
cycle even for a tree of nothing but empty passthrough sequences.

### `inbound_type/4`

At `{parent_id, slot, index}`:

- `index > 0` -> the resolved `produces` of the sibling at `index - 1`;
- `index == 0` -> the parent block's own inbound type, computed recursively:
  `Document.fetch_path(document, parent_id)` gives the parent's position, and
  `inbound_type/4` is applied to its last step;
- the root (`fetch_path` returns `{:ok, []}`) -> `ctx[:entry_type] || :unknown`.

A `parent_id` no block in the document carries, or an index past the end of the
slot, is `:unknown` - total, never raising, consistent with decision 5's
permissive default and with the package's rule that a walk carries every
failure as an ordinary arm.

Block lookup by id is `Document.blocks/1` plus `Enum.find/2`. That is O(n) per
lookup and it is the right first implementation: it uses only the public API
`sb-xti` shipped, it needs no new function on `Document` (whose contract is
another bead's), and the editor's hot path is `valid_targets/4`, which is free
to build one id-to-block map for its own pass. If profiling ever says
otherwise, an index is an internal change behind these specs.

### `check/5` - the three pairs

Kind admission for the candidate at the target, plus the seams:

- **insert** (`Document.fetch_path(document, candidate.id) == :error`): two
  seams - `inbound_type(target)` against the candidate's `consumes`, and the
  candidate's resolved `produces` against the `consumes` of the block currently
  at `index` (nothing to check when the slot ends there).
- **move** (`fetch_path` returns a path): the same two, plus the vacated seam.
  At the candidate's current position `{p, s, i}`, removing it makes `i - 1`
  and `i + 1` adjacent: the resolved `produces` of the block at `i - 1` - or
  the slot inbound when `i == 0` - against the `consumes` of the block at
  `i + 1`. Nothing to check when the slot has no `i + 1`.

Three pairs total, which decision 7 states is the exact set of seams whose
verdict can change - not an approximation of a whole-document check.

Findings are decision 8's vocabulary verbatim:

```elixir
{:kind_not_admitted, block_id, parent_id, slot_name, kinds, accepts}
{:type_mismatch, block_id, upstream_block_id | :slot_entry, produced, consumed}
```

Order within `{:error, findings}` is kind admission first, then the seams in
the order listed above, so a caller rendering the first finding renders the
structural refusal when both fail. `:ok` when the list is empty.

Degradation, per decision 5: a block that fails `Palette.resolve/2` - the
candidate, the parent, or any block on a seam - contributes the permissive
default rather than a finding. Unresolvability is ADR-0002 decision 3's
finding, reported by the document walk that owns it (`sb-da9`), and reporting
it here as well would give a host two places to look for one problem.

### `valid_targets/4`

For every block in `Document.blocks/1`, for every slot in that block's
**declared** slots (`module.slots(config)`, not the slot keys the stored
document happens to carry), for every index in `0..length(children)`: keep the
target when `check/5` returns `:ok`. Positions are returned in document
pre-order, slots in the order `slots/1` declares them, indices ascending, so
the list is deterministic.

A block that fails `Palette.resolve/2` contributes no positions, because there
is no module to ask for a declared slot set. That is an absence of positions
rather than a refusal, and it is the only sensible reading: an undeclared slot
is already a finding under ADR-0002 decision 6, so offering a drop target
inside one would be offering the author a position the walk then rejects.

### The `Relation` behaviour

```elixir
defmodule StatifierBlocks.Assignability.Relation do
  @callback assignable?(produced :: type_expr(), consumed :: type_expr()) :: boolean()
end
```

Its own file, `lib/statifier_blocks/assignability/relation.ex`, so a host
`@behaviour` line points at a module with nothing else in it. The moduledoc
carries decision 6's widen-only property and ADR-0002 decision 4's purity rule.

### `Palette.assignability`

`defstruct types: %{}, assignability: nil`, `@type t` gains
`assignability: module() | nil`. `new/1` keeps working; the option arrives as
`new(types \\ %{}, opts \\ [])` with `:assignability` the only key read, so
both `Palette.new(types)` and `Palette.new(types, assignability: MyApp.Types)`
are spellings of the same thing and the struct literal ADR-0003 decision 6
shows stays valid. `core/0` and `core_types/0` are untouched: a core palette
has no widening relation, which is the correct default for a vocabulary that
declares no type expressions.

## Phases

### Phase 1 - the structural gate, the host seam, and the pin

`lib/statifier_blocks/assignability.ex` with the seven types from ADR-0003's
typespec block and the four primitives (`io/2`, `kinds/2`, `slot_accepts/3`,
`admits?/3`). `lib/statifier_blocks/assignability/relation.ex` with the
behaviour. `Palette` gains the `assignability` field and the `new/2` option.
`BlockType`'s `io/1` callback is pinned to `StatifierBlocks.Assignability.io()`
and its `@doc` updated from "The return shape is ADR-0003's" to name the type.

Tests: `test/statifier_blocks/assignability_test.exs` covering the primitives -
the four defaults with a module carrying no `io/1`, the `:any` arm, the
intersection arm, and both directions of a two-kind palette - plus the palette
field in `test/statifier_blocks/palette_test.exs`.

Success:

- full `mix quality` green, including dialyzer against the narrowed `io/1`
  callback (the pin is the one change here that dialyzer can disagree with; if
  it does, the disagreement is a real finding about a core type's declaration,
  not something to widen the spec back for)
- `Palette.new(%{})` still returns a palette; `%Palette{}.assignability` is
  `nil`
- the four helpers still exist in `test/support/` and nothing calls the new
  ones yet - this phase is additive and commits on its own

### Phase 2 - migrate the tests off the test-only spelling

Delete `admits?/3`, `kinds/2`, `slot_accepts/3` and `io/2` from
`test/support/core_fixtures.ex`. Repoint the three call sites:
`placement_test.exs` (every call to `CoreFixtures.admits?/3` - eight of them,
at lines 49, 69, 70, 80 and 93 through 96),
`conformance_test.exs` (three calls to `CoreFixtures.io/2`), and
`CoreFixtures.kind_findings/4`'s own `admits?/3` call. Rewrite the
`CoreFixtures` moduledoc: the second bullet goes, `check/2` stays with its note
that `sb-da9` ships the real walk, and the closing paragraph drops its
`sb-b3t` half.

`check/2`'s finding tuples are **not** changed. `check/2` is the stand-in for
`sb-da9`'s walk and owns its own vocabulary until that bead lands; only the
decision it consults moves. `placement_test.exs`'s sabotage note referring to
`CoreFixtures.kinds/2` is updated to name `Assignability.kinds/2` - the same
mutation, on the module that now carries it, re-run rather than reworded.

Success:

- full `mix quality` green, 207 tests still passing with no behaviour change
- `grep -n "admits?\|slot_accepts\|def kinds\|def io" test/support/core_fixtures.ex`
  is empty
- the bead's second acceptance property now holds **against `lib/`**: both
  `core.on_event` misplacement directions are rejected through
  `Assignability.admits?/3` from kind tags alone

### Phase 3 - the data-flow relation

`assignable?/3` (the four ordered steps), `produces` resolution including
`{:passthrough, slot}`, and `inbound_type/4`. This phase also writes the new
`test/support/assignability_fixtures.ex` described above - the toy types, the
`Widens` and `Deny` relation modules, and `palette/1` - since it is the first
phase that needs a host relation to point at. Phases 4 and 5 extend it with the
worked-example document rather than starting a second support file.

Tests: the ordered relation one step at a time - `:unknown` permissive in both
positions, identity, no module on the palette, host module consulted only after
identity fails; reflexivity holding with and without a host module, including a
host module that returns `false` for everything (it cannot narrow); a
monotonicity check at this level - for every pair drawn from a small fixed set
of type expressions, the with-module verdict set is a superset of the
without-module one. Then `inbound_type/4` over a constructed document: index
greater than zero, index zero inside a nested container, the root taking
`ctx[:entry_type]`, the root with no entry type, a passthrough sequence
carrying a type out past itself, an empty passthrough sequence falling back to
its own inbound, and a passthrough chain deep enough that a non-terminating
implementation would hang.

Success:

- full `mix quality` green
- reflexivity, `:unknown` permissiveness and widen-only all assert
- the passthrough chain test completes (a termination regression shows up as a
  hang or a stack overflow, not as a wrong answer)

### Phase 4 - `check/5`

The decision function: kind admission plus the two insert seams plus the
vacated seam for a move, with decision 8's finding vocabulary and the
degradation rule for unresolvable blocks.

Tests: an accepted insert; a `:type_mismatch` on the upstream seam naming the
upstream block id; a `:type_mismatch` on the downstream seam; a
`:type_mismatch` at index 0 naming `:slot_entry`; a `:kind_not_admitted`
carrying the candidate's kinds and the slot's accepted list; a move that is
clean at the insertion point and refused at the vacated seam; a move whose
vacated slot has no block after the candidate (nothing to check); a candidate
whose type is not in the palette (permissive, no finding); the worked example's
positions as a table, mirroring ADR-0003's own worked-example table row for row.

Success:

- full `mix quality` green
- every finding shape in decision 8 is produced by at least one test, with the
  arity and element order the record fixes
- the ADR-0003 worked-example table reproduces, including the row that flips
  from widened to `:type_mismatch` when `assignability` is dropped from the
  palette

### Phase 5 - `valid_targets/4`, `validate/3`, and the acceptance properties

`valid_targets/4` over declared slots, and `validate/3` walking every seam and
every placement in the document.

Tests, which are where the bead's four acceptance properties land:

1. **Widening can only grow the accepted set.** Over a constructed document and
   a palette built twice - once with an `assignability` module, once without -
   `valid_targets/4`'s result with the module is a superset of the result
   without it. Checked exhaustively over the enumerated position set rather
   than sampled, the way `placement_test.exs` enumerates the core vocabulary.
   Asserted for a widening module, and again for a module that answers `false`
   everywhere (the superset is then an equality, which is the floor property).
2. **Both `core.on_event` misplacement directions from kind tags alone.**
   Already asserted at the primitive level in Phase 2; restated here at the
   `check/5` level so the property holds through the function the consumers
   actually call.
3. **An `:unknown`-everywhere palette accepts everything.** A palette of block
   types that declare no `io/1` at all yields `valid_targets/4` equal to the
   full enumerated position set, and `validate/3` returns `:ok` on any document
   built from them.
4. **The decision function is the single call site both consumers use.**
   Asserted behaviourally: for every position in the enumerated set,
   `valid_targets/4` contains it exactly when `check/5` returns `:ok` for it,
   and `validate/3` reports a finding for a seam exactly when `check/5` refuses
   the block sitting on it. An implementation that grew a second relation would
   have to keep two copies in agreement across all three, which the test would
   catch the moment they diverged.

Success:

- full `mix quality` green, coverage at or above 90%
- all four properties assert in the suite
- `valid_targets/4` is deterministic: the same call returns the same list,
  in pre-order

### Phase 6 - moduledocs, changelog fragment, full gate

The `Assignability` moduledoc as ADR-0003's typespec block writes it, plus the
termination argument and the note that the four primitives are a deliberate
widening of the record's listed surface. `changelog.d/sb-b3t.md` under
`changelog.d/README.md`'s rules: `Added` for the module, the behaviour and the
palette field; `Changed` for the `io/1` callback pin (a user-visible narrowing
of a public callback's spec). Full `mix quality`, then
`/wurk:verify --unattended`.

Success:

- full `mix quality` green
- every public function carries an `@spec` and a `@doc`
- the fragment describes the change to someone who only calls the public API

## Automated Success Criteria

- [x] full `mix quality` green, coverage at or above 90%
- [x] `StatifierBlocks.Assignability` exports `check/5`, `valid_targets/4`,
      `validate/3`, `inbound_type/4` and `assignable?/3` at ADR-0003's
      signatures, and defines all seven of its types
- [x] `StatifierBlocks.Assignability.Relation` declares `assignable?/2`
- [x] `%Palette{}.assignability` defaults to `nil` and `Palette.new/1` is
      unchanged for existing callers
- [x] `c:StatifierBlocks.BlockType.io/1` is specced
      `StatifierBlocks.Assignability.io()`
- [x] `test/support/core_fixtures.ex` contains no `admits?`, `kinds/2`,
      `slot_accepts/3` or `io/2`
- [x] the four acceptance properties from the bead assert in the suite
- [x] the widening fixtures live in `test/support/assignability_fixtures.ex`
      and `test/support/core_fixtures.ex` gained nothing
- [x] no second implementation of the relation exists: `grep -rn
      "slot_accepts\|:interrupt_handler" lib/` returns only the core types'
      `io/1` declarations, `Assignability`, and prose

## Manual Success Criteria

- [ ] a host reading only `Assignability`'s moduledoc and `Relation`'s can
      write a widening module without opening ADR-0003
- [ ] the `Assignability` moduledoc's termination argument is legible to
      someone who has not read this plan

## Deferred Manual Verification

- How a widened match is presented differently from an exact one is ADR-0005's
  and `sb-w50`'s; this bead can only make the distinction computable. No
  machine check here reaches it.
- Whether a `:type_mismatch` refuses compilation or is emitted and left to the
  runtime is ADR-0003 decision 9's explicit hand-off to `sb-iwz`. The finding
  vocabulary is what this bead owes that bead.

## Open Questions

None of these blocks implementation; each has a recorded default the phases
implement, and each is written down because ADR-0003 does not settle it.

1. **Move indices: pre-removal or post-removal?** Decision 7 says a move checks
   three pairs and does not say whether the `target` index is read against the
   document as it stands or against the document with the candidate already
   lifted out. For a move within one slot the two readings differ by one.
   **Default taken:** every index is interpreted against the document exactly as
   passed in, and the vacated seam is computed from that same pre-removal
   document. It is the only reading that needs no mutation of the document
   inside a pure query, and the caller performing the move already knows both
   forms. If `sb-w50` finds it wants the other reading, that is an amendment to
   ADR-0003 decision 7, not a patch here.
   **Machine-checked (unattended, 2026-08-26):** confirmed in
   `lib/statifier_blocks/assignability.ex` - `check/5`'s vacated-seam helper
   (`vacated_seam_finding/4`) reads the candidate's current position with
   `Document.fetch_path(document, candidate.id)` against `document` exactly
   as passed in, with no removal step applied first. The stated default is
   what the code does. The underlying design question (whether a future
   caller wants the other reading) is not settled by this check and is left
   open for `sb-w50`.
2. **Does `valid_targets/4` exclude the candidate's own subtree?** Dropping a
   block inside itself is not an assignability question - it is a
   tree-well-formedness question - and ADR-0003 does not mention it.
   **Default taken:** not filtered, and this one is close to settled rather
   than merely defaulted: ADR-0005 decision 5 lists the subtree rule as the
   fourth of `droppable_slots/3`'s four conditions, alongside slot declaration
   and slot room, with assignability named separately as the second. The
   editor owns the cycle check; a filter here would make this module partly
   responsible for a rule it does not state.
   **Machine-checked (unattended, 2026-08-26):** confirmed `valid_targets/4`
   in `lib/statifier_blocks/assignability.ex` enumerates every block via
   `Document.blocks/1` with no exclusion of the candidate or its subtree.
   The stated default is what the code does. Whether the editor's own
   subtree-cycle filter is in place is `sb-w50`'s to confirm, not this bead's.
3. **Does ADR-0002's typespec appendix get an editorial amendment?** Its
   `%Palette{types: ...}` line is now one field short of the accepted struct.
   ADR-0002 already carries a precedent for this (its decision 10 was amended
   at acceptance to defer to ADR-0003). **Default taken:** no ADR edit in this
   bead - out of the scope handed to it - and the mismatch is recorded here so
   whoever does the next ADR pass has it.
   **Machine-checked (unattended, 2026-08-26):** confirmed no ADR file under
   `docs/adr/` was edited by this bead (`git diff --stat` against this
   branch's base shows no `docs/adr/` changes). The stated default (no ADR
   edit in this bead) holds; the underlying question of whether ADR-0002
   should get an editorial amendment is still open, for the next ADR pass.
4. **`{:passthrough, slot}` naming a slot the block does not declare.**
   Decision 4 defines passthrough over a slot's contents and is silent on a
   declaration that names a slot `slots/1` does not return.
   **Default taken:** treated as an empty slot, so it falls back to the block's
   own inbound type. Permissive, total, and consistent with decision 5; the
   undeclared-slot condition is already ADR-0002 decision 6's finding and is
   reported by the walk that owns it.
   **Machine-checked (unattended, 2026-08-26):** confirmed in `produces/4`
   (`lib/statifier_blocks/assignability.ex`) - resolving `{:passthrough,
   slot}` reads the slot's children with a lookup that defaults to `[]` for
   a slot the block's config does not carry, which falls straight through to
   the "empty slot -> own inbound type" arm. No special case exists for an
   undeclared slot name. The stated default is what the code does.
5. **`valid_targets/4` is per position; ADR-0005's `droppable_slots/3` is per
   slot.** ADR-0003's typespec block returns `[target()]`, and `target()` is
   `{block_id, slot_name, index}` - the data-flow gate genuinely depends on the
   index, since the seam is between adjacent siblings. ADR-0005 decision 5
   (also accepted, same day) specs
   `droppable_slots(Document.t(), Palette.t(), Block.id()) :: [{Block.id(), Block.slot_name()}]`
   and says "nothing in that list depends on the index within the slot, which
   is why validity is per-slot". Both records are accepted and neither is wrong
   about its own layer, but the two shapes do not compose without a stated
   reduction. **This is not a contradiction inside ADR-0003 and nothing in this
   bead depends on resolving it**, so it is recorded rather than decided.
   **Default taken:** ship `valid_targets/4` exactly as ADR-0003 specs it, per
   position. The obvious reduction - a slot is droppable when at least one
   index in it is accepted - is `sb-w50`'s to make and to record, and it is the
   one that keeps ADR-0005's "consulted through one predicate and nothing else"
   true. Whoever picks up `sb-w50` should read this note first.
   **Machine-checked (unattended, 2026-08-26):** confirmed `valid_targets/4`
   ships exactly as ADR-0003 specs it - returns `[target()]` with a
   `{block_id, slot_name, index}` per accepted position, no per-slot
   reduction applied. The stated default holds; the reconciliation with
   ADR-0005's `droppable_slots/3` is still `sb-w50`'s to make.
