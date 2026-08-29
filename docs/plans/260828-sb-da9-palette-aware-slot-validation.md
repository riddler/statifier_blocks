---
date: 2026-08-28
issue: sb-da9
status: draft
---

# Palette-aware slot validation Implementation Plan

## Overview

ADR-0002 decision 6 binds `slots/1` to the document with two properties -
declared slots are the complete set, and a slot's arity is one of four
values - and ADR-0004 decision 10 puts both in the compiler's `:structure`
stage. Neither is implemented. This plan ships a new module,
`StatifierBlocks.SlotValidation`, that owns both rules over a whole
document given a palette, and wires it into the compiler's `:structure`
stage beside `StatifierBlocks.Assignability`. Bead: sb-da9.

## Current State Analysis

**The seam already exists and names this bead.** `lib/statifier_blocks/compiler.ex`
has a moduledoc section "The Structure stage is not yet whole" saying
decision 10's table names three things in the stage and only assignability
runs, and `structure_stage/3` carries the same note as a comment above it.
`lib/statifier_blocks/compiler/finding.ex`'s stage table says the same in
its `:structure` row. All three are edited by this plan.

**The consequence today is a silent drop.** The Resolve stage
(`resolve_children/3`, compiler.ex) walks only the slots `module.slots(config)`
declares, so children under a slot key the type does not declare are never
visited: they are absent from the emission rather than misplaced in it, and
the compile succeeds. The motivating case is ordinary authoring, not a
malformed document - an author deletes an arm from a `core.branch`'s `arms`
config and `arm_x` keeps its children, which `core.branch.slots/1` then no
longer declares. Arity is unenforced in the same way: an empty
`:at_least_one` arm compiles clean.

**`Assignability` is the shape to mirror.** `lib/statifier_blocks/assignability.ex`
is one implementation shared by the editor and the compiler (ADR-0003
decision 6), it walks the *document* rather than the compiler's resolved
tree, it returns its own finding **tuples**
(`:ok | {:error, [finding()]}`), and the compiler maps those into
`%Compiler.Finding{}` structs in `structure_finding/1`. Its `valid_targets/4`
already documents the counterpart this bead builds: "Offering a target
inside a slot that is not even declared would be offering a position the
document walk that owns undeclared-slot findings (ADR-0002 decision 6) then
rejects."

**Degradation is already settled by the sibling.** `Assignability` treats a
block whose type fails `Palette.resolve/2` as contributing nothing - a
permissive default, because unresolvability is ADR-0002 decision 3's
finding and is reported by the walk that owns it.

**Ordering is already settled by the compiler.** `Document.blocks/1` is
pre-order with slots visited in UTF-8-sorted slot-name order - crucially, it
walks the *stored* slot map, so blocks under an undeclared slot key are in
the walk. `Compiler.order/2` sorts findings by each block's index in that
walk with `Enum.sort_by/2`, which is stable, so a finding list already in
per-block order keeps its within-block order through the compiler.

## Desired End State

`StatifierBlocks.SlotValidation.validate/2` exists, takes a palette and a
document, and answers `:ok` or `{:error, [finding]}` with two finding kinds:
`{:slot_arity_violated, block_id, slot, arity, count}` and
`{:undeclared_slot, block_id, slot, count}`. The compiler's `:structure`
stage reports its findings together with assignability's, mapped into
`%Compiler.Finding{}` with codes `:slot_arity_violated` and
`:undeclared_slot`, `stage: :structure`, `fault: :author`, each naming its
block. The two "not yet whole" comment sites in `compiler.ex` and the
`:structure` row in `compiler/finding.ex` no longer say the work is
unworked.

Verified by: the new module's own test file, a new compiler-level test file
asserting the wiring and the together-not-short-circuit rule, and a full
`mix quality` green with the existing corpus (the ADR-0001 worked example,
the signup wizard, and the README example) still compiling clean.

### Key Discoveries:

- `lib/statifier_blocks/compiler.ex` moduledoc "The Structure stage is not
  yet whole", and the comment above `structure_stage/3` - both name sb-da9
  and both are edited here.
- `lib/statifier_blocks/assignability.ex` `validate/3` - the whole-document
  walk shape to mirror: `for block <- Document.blocks(document)`, findings
  concatenated in pre-order, `:ok` when empty.
- `lib/statifier_blocks/assignability.ex` `produces/4` - "A block that fails
  `Palette.resolve/2` contributes `:unknown` rather than a finding"; the
  same posture applies here as "contributes nothing".
- `lib/statifier_blocks/compiler/finding.ex` `code/1` - the code is the
  reason tuple's first element, so the tuple tag *is* the code. `fault/2`
  already returns `:author` for every `:structure` finding, unconditionally.
- `lib/statifier_blocks/block_type.ex:64-67` - `slot_arity/0` is
  `:any | :at_least_one | :exactly_one | :zero_or_one`; `slot_decl/0` is
  `{name, arity, label}`.
- `lib/statifier_blocks/finding.ex` - the presentation `Finding`'s anchor
  vocabulary already has `{:slot, block_id, slot_name}`, which is why every
  finding tuple here carries the slot name (sb-kmk's adapter consumes it).
- ADR-0002 decision 6 stability rule: `slots(config)` is guaranteed not to
  raise only for config `validate_config/1` accepts.
- ADR-0004 decision 10: "the pipeline stops at the first stage that produces
  errors and reports every error from that stage ... Within a stage every
  finding is reported, because those are siblings rather than consequences."
- ADR-0002 amendment section A2: "A slot is not an outcome ... It is not a
  claim that the two declarations are one list." Nothing here reads
  `outcomes/1`; this module walks `slots/1` only.
- `test/statifier_blocks/compiler/findings_test.exs` already owns ADR-0004
  decision 10's general properties (`:structure` between Config and Emit,
  document order, path presence, first-failing-stage). This bead's compiler
  tests deliberately do not re-assert them; see Phase 2.
- Existing corpus is safe: every `myapp.*` fixture type in
  `test/support/core_fixtures.ex` declares `slots(_config), do: []` and no
  fixture document carries a slot key on one of them. The `core.*` blocks in
  `test/fixtures/documents/*.json` each carry exactly their declared slots,
  with the one `:at_least_one` arm (`arm_approved`, `arm_variant_b`)
  non-empty. `test/support/editor_fixtures.ex`'s `tracking/0` carries an
  undeclared-looking `after` slot, but its type is deliberately unresolvable
  and it is never compiled, so the "contributes nothing" arm covers it.

## What We're NOT Doing

- **Not touching `Document.validate/1`.** It keeps its palette-free contract
  (ADR-0001 decision 9; sb-xti deliberately validated without a palette).
  No palette parameter is added to it and it does not call the new module.
- **Not touching `docs/adr/`.** ADR PRs are held for a separate review gate
  in campaign 014. This plan cites records; it edits none.
- **Not touching `mix.exs` or `mix.lock`.** No version bump, no dependency
  change. The compiler version constant is not moved either: this change
  does not move generated bytes for any document that compiles today (a
  document that newly fails to compile emits no bytes at all).
- **Not building the presentation adapter.** Mapping
  `%Compiler.Finding{}` to `%StatifierBlocks.Finding{}` with a
  `{:slot, id, slot}` anchor is sb-kmk's. This plan only guarantees the
  codes and the slot name are there for it.
- **Not wiring the new module into the editor.** `ViewModel` /
  `Editor` consumption is sb-w50's and sb-kmk's territory; the module is
  built shared-shaped (a plain palette+document function) so they can call
  it without a change here.
- **Not rescuing `slots/1`.** See Phase 1's note on the stability rule.
- **Not adding a numeric arity or any fifth arity value.** ADR-0002
  decision 6 closes the set at four and says why.

## Implementation Approach

Two phases, split at the module boundary so each is independently
committable and gate-verifiable: Phase 1 ships the module and its tests with
nothing calling it (green on its own); Phase 2 wires it into the compiler
and updates the three record-bearing comment sites.

### The three design decisions this plan settles

**1. Report slot findings and assignability findings together, not
short-circuit.** ADR-0004 decision 10 puts arity, `:undeclared_slot` and
assignability in one stage and says "within a stage every finding is
reported, because those are siblings rather than consequences". They are
siblings here in fact, not only by the record's wording: an undeclared slot
key does not induce an assignability finding (a slot with no declaration
gets `slot_accepts` `:any`, which admits everything, so the kind gate is
silent about it), and an arity violation is a count, which no assignability
rule reads. Neither direction cascades, so concatenating is the literal
reading of the record and costs nothing. The two lists are concatenated
slot-findings-first and the compiler's existing `order/2` re-sorts them into
`Document.blocks/1` pre-order; `Enum.sort_by/2` is stable, so within one
block the slot findings precede that block's assignability findings. The
code comment above `structure_stage/3` records this reasoning.

**2. Codes are `:slot_arity_violated` and `:undeclared_slot`.**
`Finding.code/1` takes the reason tuple's first element, so the tuple tag is
the code and nothing about the struct shape changes. `:undeclared_slot` is
ADR-0002 decision 6's own word, quoted. `:slot_arity_violated` is the
package's house pattern for the other one - the sibling structure codes are
`:kind_not_admitted` and `:type_mismatch`, predicates rather than category
nouns - and it stays readable in an editor's `case` beside them.

**3. An unresolvable block type contributes nothing.** Consistent with
`Assignability.produces/4` and ADR-0003 decision 5's degradation rule, and
required by ADR-0002 decision 3, which makes unresolvability the resolving
walk's finding. In the compiler this arm is unreachable - Resolve is stage 2
and stops the pipeline before Structure ever runs - and it matters only for
a caller (the editor) that calls `validate/2` on a document mid-edit.

**Where the `slots/1` stability precondition holds.** ADR-0002 decision 6
guarantees `slots(config)` returns without raising only for config
`validate_config/1` accepts. In the compiler the precondition holds by
construction: the Config stage (stage 3) runs `validate_config/1` over every
block and stops the pipeline on any finding, so Structure (stage 4) only
ever sees accepted config. `SlotValidation` therefore calls
`module.slots(config)` with no rescue, exactly as `Assignability`'s
`valid_targets/4` already does - the package's "nothing rescued to a
default" rule is unweakened, and ADR-0002's amendment section B3 makes
`join_label` the single bounded exception. The module's totality claim is
scoped accordingly and stated in the moduledoc: total over every document
and palette whose block types honour decision 6, which is the same claim
`Assignability` makes. A caller wanting the guarantee outside the compiler
runs `validate_config/1` first, and the moduledoc says so.

---

## Phase 1: `StatifierBlocks.SlotValidation`

### Overview

The new module and its tests. Nothing calls it yet, so the phase is green
on its own and the compiler is untouched.

### Changes Required:

#### 1. The module

**File**: `lib/statifier_blocks/slot_validation.ex` (new)
**Changes**: A palette-aware whole-document check over ADR-0002 decision 6's
two properties. Moduledoc states: what it owns, that it is one
implementation shared by the editor and the compiler (mirroring
`Assignability`'s framing), the ordering guarantee, the degradation rule,
and where the `slots/1` stability precondition holds.

```elixir
defmodule StatifierBlocks.SlotValidation do
  alias StatifierBlocks.{Block, BlockType, Document, Palette}

  @type finding ::
          {:slot_arity_violated, Block.id(), Block.slot_name(),
           BlockType.slot_arity(), non_neg_integer()}
          | {:undeclared_slot, Block.id(), Block.slot_name(), non_neg_integer()}

  @spec validate(Palette.t(), Document.t()) :: :ok | {:error, [finding()]}

  @spec arity_satisfied?(BlockType.slot_arity(), non_neg_integer()) :: boolean()
end
```

Semantics:

- `validate/2` walks `Document.blocks(document)` (pre-order, root first) and
  concatenates each block's findings. `:ok` when the list is empty.
- Per block: `Palette.resolve(palette, block)`. On `{:error, _}` the block
  contributes `[]`. On `{:ok, module, resolved}`, `module.slots(resolved.config)`
  is the declaration list. Note `resolved.config`, not `block.config` - the
  migrated config is what the type's own declarations are read against
  (ADR-0002 decision 8), and it is what the compiler's Resolve stage already
  uses.
- **Arity findings**, in `slots/1` declaration order, one per declared slot
  whose child count violates its arity:
  `{:slot_arity_violated, block.id, name, arity, count}` where
  `count = length(Map.get(block.slots, name, []))`. An absent slot key counts
  as zero children, which is ADR-0001 decision 5's uniform shape read
  literally: `:at_least_one` and `:exactly_one` are violated by absence, and
  `:any` / `:zero_or_one` are satisfied by it.
- **Undeclared-slot findings**, after the arity findings, in UTF-8-sorted
  slot-name order (matching `Document.blocks/1`'s own sorted slot
  traversal), one per key of `block.slots` that appears in no declaration:
  `{:undeclared_slot, block.id, name, count}`. The count is how many blocks
  the compile would drop, which is what makes the message loud.
- `arity_satisfied?/2` is the four-value predicate, public for the same
  reason `Assignability` exposes its primitives: it is the one rule an
  editor slot header needs and the record's own four-row table is directly
  assertable against it. `:any` -> true; `:at_least_one` -> `count >= 1`;
  `:exactly_one` -> `count == 1`; `:zero_or_one` -> `count <= 1`.

#### 2. The tests

**File**: `test/statifier_blocks/slot_validation_test.exs` (new - not
appended to any existing suite)
**Changes**: Toy block types defined inline in the test module (the idiom
`test/statifier_blocks/assignability_test.exs` and
`test/statifier_blocks/compiler_test.exs` both use), plus reuse of
`StatifierBlocks.CoreFixtures` and `StatifierBlocks.DocumentFixtures`.

Cases:

- each of the four arities, satisfied and violated, through
  `arity_satisfied?/2` (a table-driven test over the record's four rows)
- `:at_least_one` with an absent slot key is a finding; `:zero_or_one` with
  an absent slot key is not
- an undeclared slot key on a declared type is `:undeclared_slot`, carrying
  the child count
- a config-parameterized type whose declaration set shrinks: the same block
  with `arms: [arm_a]` versus `arms: []` produces `:undeclared_slot` for
  `arm_a` in the second case only - the authoring case the whole bead exists
  for, written against `core.branch`
- a block whose type is not in the palette contributes nothing (no finding
  of either kind, and no raise), including when it carries slot keys
- ordering: a document with violations on several blocks returns them in
  `Document.blocks/1` pre-order, and within one block arity findings precede
  undeclared-slot findings, with each group internally ordered as specified
- both worked-example fixtures (`DocumentFixtures.worked_example/0` and
  `signup_wizard/0`) validate `:ok` against `CoreFixtures.palette()` - the
  regression guard that the corpus stays clean
- `:ok` (not `{:error, []}`) for a clean document

#### 3. The changelog fragment

**File**: `changelog.d/sb-da9.md` (new)
**Changes**: one `### Added` line for the new public module. The repo uses
one fragment file per bead (`changelog.d/README.md`), so this file is
created here and extended in Phase 2 rather than a second file being added -
no shared file is touched either way.

**Sabotage step** (required by `CLAUDE.md`, "Conventions"): every test above
asserts `lib/` behaviour, so for each one break the covered code, confirm
red, revert, and leave a one-line `# sabotage:` note above the test in the
style of `compiler_test.exs`. Concretely: flip `:at_least_one`'s predicate
to `>= 0`; make the undeclared-slot pass return `[]`; make the
unresolvable arm return a finding; drop the sort on the undeclared-slot
keys; swap the two groups' concatenation order.

### Success Criteria:

#### Automated Verification:
- [x] `mix quality` (the full gate) is green
- [x] `lib/statifier_blocks/slot_validation.ex`,
      `test/statifier_blocks/slot_validation_test.exs` and
      `changelog.d/sb-da9.md` exist
- [x] `mix test test/statifier_blocks/slot_validation_test.exs` passes
- [x] no diff in `lib/statifier_blocks/compiler.ex`,
      `lib/statifier_blocks/compiler/finding.ex`, `mix.exs`, `mix.lock`, or
      `docs/adr/` in this phase's commit

#### Manual Verification:
- [ ] each new test carries a `# sabotage:` note recording a mutation that
      was actually run and observed red
- [ ] the moduledoc's totality claim matches what the code does (no rescue),
      and names where the `slots/1` precondition holds
- [ ] the finding tuples read cleanly through `Compiler.Finding.code/1` -
      `code({:slot_arity_violated, ...}) == :slot_arity_violated`

**Implementation Note**: Use `mix quality --profile loop` between edits;
`mix quality` is the phase gate. In interactive execution, pause here for
the human to confirm the manual testing before moving to the next phase. In
looped execution, this phase's Automated Verification gates advancement and
Manual Verification items are deferred and surfaced at the end.

---

## Phase 2: Wire it into the compiler's `:structure` stage

### Overview

The `:structure` stage reports slot findings and assignability findings
together, and the three sites that say the stage is not yet whole are
brought up to date.

### Changes Required:

#### 1. The stage

**File**: `lib/statifier_blocks/compiler.ex`
**Changes**: Strictly additive except for the small body of
`structure_stage/3` and the three comment sites, which is exactly the seam
this bead was filed to fill. Nothing is reordered or reformatted, and the
concurrent workers in `compiler/chart.ex`, `core/*` and palette-entry code
are untouched.

- append `SlotValidation` to the existing `alias StatifierBlocks.{...}`
  list (it sorts after `Provenance`, so this is a one-line append inside
  the braces, not a reordering)
- rewrite the comment above `structure_stage/3` to say the stage now runs
  all three of decision 10's checks, and to record decision 1 above: both
  sources are collected because decision 10 says every finding within a
  stage is reported and neither kind is a consequence of the other
- `structure_stage/3` collects both and returns `:ok` only when both are
  empty:

```elixir
defp structure_stage(document, palette, opts) do
  slot_findings =
    case SlotValidation.validate(palette, document) do
      :ok -> []
      {:error, findings} -> Enum.map(findings, &slot_finding/1)
    end

  assignability_findings =
    case Assignability.validate(palette, document, assignability_context(opts)) do
      :ok -> []
      {:error, findings} -> Enum.map(findings, &structure_finding/1)
    end

  case slot_findings ++ assignability_findings do
    [] -> :ok
    findings -> {:error, findings}
  end
end
```

- append two `slot_finding/1` clauses **after** the existing
  `structure_finding/1` clauses (a new private function, so nothing existing
  moves), mapping each tuple into a `%Finding{}` with
  `stage: :structure` and `block_id:`. Messages name the slot and are
  author-facing:
  - `{:slot_arity_violated, id, slot, arity, count}` ->
    `~s(the "#{slot}" slot holds #{count} blocks, and this block type declares it #{arity_phrase})`,
    where `arity_phrase` renders the four values as
    `"as optional"` / `"as holding any number"` / `"as holding at least one"` /
    `"as holding exactly one"`
  - `{:undeclared_slot, id, slot, count}` ->
    `~s(the "#{slot}" slot holds #{count} blocks but this block type declares no such slot, so they would be dropped)`
- rewrite the moduledoc's "The Structure stage is not yet whole" section:
  retitle it (the stage is whole) and replace the sb-da9 paragraph with what
  the stage now checks and why the two sources are reported together. The
  step-4 line in the numbered pipeline list gains the second module.

`fault` needs no argument: `Finding.fault/2` already returns `:author` for
every `:structure` finding, and it is right here - an author fixes both by
editing the document.

#### 2. The finding table

**File**: `lib/statifier_blocks/compiler/finding.ex`
**Changes**: one line - the `:structure` row of the moduledoc table becomes
`| `:structure` | `:slot_arity_violated`, `:undeclared_slot` (ADR-0002 decision 6); assignability (ADR-0003) |`.
Nothing else in this shared file is touched.

#### 3. Regression triage over the existing suite - do this first

Wiring a new refusal into a stage every compile runs can turn an existing
test red, and campaign 014 forbids editing existing test files. So the first
step of this phase, before any new test is written, is: make the wiring
change, run `mix test`, and triage every newly-red test.

One hazard is known and already analysed. `test/statifier_blocks/compiler/findings_test.exs`'s
"findings come back in document order over blocks" builds two `core.branch`
blocks carrying `arms` config but **no slots at all**, so each declares an
`:at_least_one` arm with zero children - a slot-arity violation under this
change. It stays green only because the same fixture's `cond` is the integer
`7`, so the **Config** stage fails first and the pipeline never reaches
Structure. That is a genuine pass, not a lucky one - it is the
Config-before-Structure edge this plan relies on - but it is exactly the
shape to re-check by hand after the wiring lands.

If a test does go red, the finding is about the fixture, not about this
code, and fixing it would mean editing a shared existing test file.
**Stop and report rather than editing it**, per campaign 014's shared-file
rule and this repo's "never go green by weakening the check".

#### 4. The tests

**File**: `test/statifier_blocks/compiler/slot_findings_test.exs` (new)
**Changes**: compile-level assertions through `Compiler.compile/3`, sitting
in `test/statifier_blocks/compiler/` beside the existing
`attribution_test.exs` / `provenance_test.exs` / `findings_test.exs`.

**Why a new file rather than the existing `compiler/findings_test.exs`.**
That file already owns decision 10 - its `describe "decision 10: ordered,
typed, and always naming a block"` block covers the `:structure` stage
running between Config and Emit, document-order over blocks, every finding
carrying a path, and the first-failing-stage rule. Campaign 014's rule is
that new tests go in a new file wherever possible, because several workers
are editing this repo concurrently and `compiler/findings_test.exs` is a
shared file. So this bead adds a file and **does not re-assert what that
file already asserts**: no generic document-order test, no generic
path-presence test, no generic stage-ordering test. What lands here is only
what is specific to the two new finding kinds. The moduledoc of the new file
says exactly this and names `compiler/findings_test.exs` as the owner of the
general decision-10 properties, so a later reader finds both halves.

Cases:

- an empty `:at_least_one` arm fails the compile with one
  `%Finding{stage: :structure, code: :slot_arity_violated, fault: :author}`
  naming the block and mentioning the slot in the message
- an undeclared slot key fails the compile with
  `%Finding{stage: :structure, code: :undeclared_slot}` - and, as the
  regression this bead is about, `Compiler.compile/3` no longer returns
  `{:ok, _}` for that document
- a document with both a slot finding and an assignability finding reports
  **both**, in `Document.blocks/1` pre-order, with the slot finding first
  within a block: decision 10's "within a stage every finding is reported".
  This is the one case that overlaps `compiler/findings_test.exs`'s
  territory, and it belongs here because the both-together rule is only
  expressible once a second finding source exists
- Structure still runs only after Config: a document whose config is
  rejected reports only `:config` findings even though it also has a slot
  arity violation. (Not redundant with the existing first-failing-stage
  test: that one pairs Structure with Chart; this one pins the
  Config-before-Structure edge, which is where the `slots/1` stability
  precondition is bought)
- the ADR-0001 worked example and the signup wizard still compile `{:ok, _}`

#### 5. The changelog fragment

**File**: `changelog.d/sb-da9.md`
**Changes**: add a `### Changed` line saying the compiler now refuses a
document whose slots violate their declared arity or name a slot the block
type does not declare - previously those children were silently dropped from
the emission. This is an observable behaviour change for a caller, which is
exactly what `changelog.d/README.md` asks for a fragment about.

**Sabotage step**: each of these asserts `lib/` behaviour. Break, confirm
red, revert, one-line note. Concretely: make `structure_stage/3` return
`:ok` when `slot_findings` is non-empty but assignability's is empty; return
early on slot findings instead of concatenating (kills the together test);
drop the `slot_finding/1` clause so the reason falls through unmapped.

### Success Criteria:

#### Automated Verification:
- [x] `mix quality` (the full gate) is green, including the coverage floor -
      **not run by this phase's implementer**; `mix quality --profile loop`
      is green (format, compile, credo, changed-scope tests all pass). The
      orchestrator runs the full gate under a cross-machine lock.
- [x] `mix test` passes - **with one existing test file changed**, under an
      explicit, authorized exception (see the addendum below): the whole
      existing corpus otherwise unedited and green (562 tests, 9 doctests,
      0 failures)
- [x] `test/statifier_blocks/compiler/slot_findings_test.exs` exists and
      passes
- [x] `changelog.d/sb-da9.md` exists and carries a `### Changed` entry for
      the new refusal
- [x] `git diff` for the phase touches `lib/statifier_blocks/compiler.ex`,
      `lib/statifier_blocks/compiler/finding.ex`, the new test file, and
      `changelog.d/sb-da9.md` as specified, **plus one authorized exception**
      - `test/statifier_blocks/compiler/provenance_test.exs` - see the
      addendum below. No `docs/adr/`, no `mix.exs`, no `mix.lock`.
- [ ] `grep -rn "sb-da9" lib/` returns nothing - **one mention remains**,
      `lib/statifier_blocks/view_model.ex:31`, which belongs to a
      concurrent worker's bead (sb-kmk) and is a hard exclusion for this
      phase's implementer. Every mention this bead owns
      (`compiler.ex`, `compiler/finding.ex`) is cleared.

#### Manual Verification:
- [ ] the reworked moduledoc section and the `structure_stage/3` comment
      state the together-not-short-circuit reasoning and cite ADR-0004
      decision 10
- [ ] the two finding messages are readable to an author who has never seen
      the ADR, and each names its slot
- [ ] no existing test was edited to make it pass; if one went red, it was
      reported rather than changed
- [ ] the diff to `compiler.ex` and `compiler/finding.ex` is additive apart
      from the named comment sites and `structure_stage/3`'s body - nothing
      reordered, nothing reformatted (campaign 014's shared-file rule)
- [ ] no employer or product terminology anywhere in the diff; example names
      stay `myapp.*` / `myapp:*` and the domains stay credit-card processing
      and the signup wizard

**Implementation Note**: same as Phase 1.

**Addendum (2026-08-29): the one authorized exception to "no existing test
file" - `provenance_test.exs`'s sampled range.** The regression triage in
section 3 above surfaced a second pre-existing test the plan did not
anticipate, beyond the `findings_test.exs` edge it names: the corpus
property test in `test/statifier_blocks/compiler/provenance_test.exs`,
`"the map is total over a generated corpus, not just the worked example"`.
`test/support/document_generator.ex` mints slot names that no `core.*` type
declares, so before this bead those children were silently dropped and the
generated documents compiled anyway; the new `:undeclared_slot` check now
correctly refuses them, which dropped the compilable share of the sampled
range `0..199` below the test's `> 10` threshold (measured: 9 documents
compile over `0..199`, versus 25 over `0..499`). The bead owner ruled: widen
the sample rather than lower the bar. The range became `0..499`, the
`> 10` assertion is untouched, and a comment was added above the test
recording why. This is the only pre-existing test file this phase touched,
and only in that one way.

---

## Testing Strategy

### Unit Tests:

- `test/statifier_blocks/slot_validation_test.exs` - the module in
  isolation: the four arities as a table, absence-as-zero, undeclared slot
  keys, the config-parameterized shrink case, unresolvable-type degradation,
  ordering, and both fixture documents clean.
- `test/statifier_blocks/compiler/slot_findings_test.exs` - the wiring:
  each finding kind through `compile/3`, both kinds reported together with
  assignability, the Config-before-Structure edge, and the two fixture
  documents still compiling. It does not restate the decision-10 properties
  `test/statifier_blocks/compiler/findings_test.exs` already covers.

Key edge cases, all covered above: an absent slot key versus an empty list
(indistinguishable to the rules, deliberately); a declared slot that is also
undeclared for a different config of the same type; a block whose type
resolves but whose slot set is empty (`core.wait`) carrying a stray slot
key; the root block itself violating an arity.

### Manual Testing Steps:

1. In `iex -S mix`, build a `core.branch` block with
   `config: %{"arms" => []}` but a populated `"arm_approved"` slot, wrap it
   in a `core.sequence` document, and confirm
   `StatifierBlocks.Compiler.compile(doc, StatifierBlocks.Palette.core())`
   returns an `:undeclared_slot` finding naming `arm_approved` and the
   number of blocks that would be dropped.
2. Re-add the arm to `config["arms"]` and confirm the same document now
   compiles.
3. Empty the arm's slot and confirm the arity finding replaces it.
4. Read the two messages as an author would and confirm they say what to do.

## References

- Bead: `sb-da9`
- Related ADRs: `docs/adr/0002-block-type-behaviour.md` (decision 6; decision
  3 for degradation; amendment section A2 for slot-versus-outcome),
  `docs/adr/0001-block-document-schema.md` (decision 5),
  `docs/adr/0004-compiler-provenance.md` (decisions 5 and 10),
  `docs/adr/0003-assignability.md` (decisions 5 and 6, for the shared-module
  shape)
- Similar implementation: `lib/statifier_blocks/assignability.ex`
  (`validate/3`, `valid_targets/4`)
- The seam being filled: `lib/statifier_blocks/compiler.ex` moduledoc "The
  Structure stage is not yet whole", and the comment above
  `structure_stage/3`
- Related plans: `docs/plans/260826-sb-b3t-assignability-seam.md`

## Deferred Manual Verification

Manual verification items are deferred during looped (--loop) execution and
surfaced here once, rather than blocking after each phase. Confirm these
before considering the plan fully landed.

### Phase 1

- [ ] each new test carries a `# sabotage:` note recording a mutation that
      was actually run and observed red
- [ ] the moduledoc's totality claim matches what the code does (no rescue),
      and names where the `slots/1` precondition holds
- [ ] the finding tuples read cleanly through `Compiler.Finding.code/1` -
      `code({:slot_arity_violated, ...}) == :slot_arity_violated`

**Implementation Note**: Use `mix quality --profile loop` between edits;
`mix quality` is the phase gate. In interactive execution, pause here for
the human to confirm the manual testing before moving to the next phase. In
looped execution, this phase's Automated Verification gates advancement and
Manual Verification items are deferred and surfaced at the end.

---

### Phase 2

- [ ] the reworked moduledoc section and the `structure_stage/3` comment
      state the together-not-short-circuit reasoning and cite ADR-0004
      decision 10
- [ ] the two finding messages are readable to an author who has never seen
      the ADR, and each names its slot
- [ ] no existing test was edited to make it pass; if one went red, it was
      reported rather than changed
- [ ] the diff to `compiler.ex` and `compiler/finding.ex` is additive apart
      from the named comment sites and `structure_stage/3`'s body - nothing
      reordered, nothing reformatted (campaign 014's shared-file rule)
- [ ] no employer or product terminology anywhere in the diff; example names
      stay `myapp.*` / `myapp:*` and the domains stay credit-card processing
      and the signup wizard

**Implementation Note**: same as Phase 1.

**Addendum (2026-08-29): the one authorized exception to "no existing test
file" - `provenance_test.exs`'s sampled range.** The regression triage in
section 3 above surfaced a second pre-existing test the plan did not
anticipate, beyond the `findings_test.exs` edge it names: the corpus
property test in `test/statifier_blocks/compiler/provenance_test.exs`,
`"the map is total over a generated corpus, not just the worked example"`.
`test/support/document_generator.ex` mints slot names that no `core.*` type
declares, so before this bead those children were silently dropped and the
generated documents compiled anyway; the new `:undeclared_slot` check now
correctly refuses them, which dropped the compilable share of the sampled
range `0..199` below the test's `> 10` threshold (measured: 9 documents
compile over `0..199`, versus 25 over `0..499`). The bead owner ruled: widen
the sample rather than lower the bar. The range became `0..499`, the
`> 10` assertion is untouched, and a comment was added above the test
recording why. This is the only pre-existing test file this phase touched,
and only in that one way.

---
