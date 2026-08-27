# The editor command algebra and view model (ADR-0005 d2-d5, d9) Implementation Plan

## Overview

The pure half of ADR-0005: the four-command algebra with its inverses, the
undo/redo history, drop-target enumeration, the presentation finding, and the
view model every editor component will read. Bead: `sb-ia5`.

Five modules, all of them outside `StatifierBlocks.Editor.*` because ADR-0005
decision 13 puts them there, and none of them naming Phoenix because decision 1
makes that namespace boundary load-bearing:

| Module | Responsibility | Record |
|---|---|---|
| `StatifierBlocks.Edit` | the command type, `apply/2`, inverses | d2, d3, d4 |
| `StatifierBlocks.Edit.History` | undo and redo stacks over commands | d3 |
| `StatifierBlocks.Edit.Targets` | `droppable_slots/3` | d5 |
| `StatifierBlocks.Finding` | the presentation finding and its anchor | d11 |
| `StatifierBlocks.ViewModel` | everything renderable, derived | d9, d10, d12, d13 |

The record's "The contract as typespecs" section is the API contract for
`Edit`, `Edit.Targets` and `Finding`, taken verbatim, with two documented
widenings named in "Design notes" below.

## Current State Analysis

Branch `sb-ia5-editor-commands`, cut from `sb-qz0-provenance-findings`
(stacked and unmerged). `phoenix_live_view` is **absent** from `mix.exs`, and
`grep -rn "Phoenix" lib/ test/` returns nothing: the constraint this bead has
to preserve is already the repository's resting state, so the acceptance
property is "still nothing" rather than "make it so".

What the base branch supplies:

| Module | What this bead uses it for |
|---|---|
| `lib/statifier_blocks/block.ex` | `%Block{}`, `id/0`, `slot_name/0`, `config/0`, `json/0` |
| `lib/statifier_blocks/document.ex` | `%Document{}`, `blocks/1` (pre-order), `fetch_path/2`, `validate/1`, `to_json/1` |
| `lib/statifier_blocks/palette.ex` | `fetch/2`, `resolve/2` (total, migrating), `core/0` |
| `lib/statifier_blocks/block_type.ex` | `slot_decl/0`, `field_decl/0`, `field_type/0`, `finding/0`, the nine callbacks |
| `lib/statifier_blocks/assignability.ex` | `valid_targets/4`, `check/5`, `context/0`, `target/0` |
| `lib/statifier_blocks/core/*.ex` | seven real block types with real `palette_entry/0`, `slots/1`, `config_schema/1` |
| `lib/statifier_blocks/compiler/finding.ex` | a **different**, compiler-side finding; see the note below |
| `test/support/document_generator.ex` | the seeded document generator this bead extends |
| `test/support/core_fixtures.ex`, `block_type_fixtures.ex` | toy block types for tests |

Constraints that bind every phase:

- **Coverage floor is 90%**, `test/support/` excluded. Every new `lib/` line
  needs a test in the phase that adds it.
- **Format runs in check mode.** Run `mix format` by hand before committing.
- **Sabotage rule.** Every new test asserting `lib/` behaviour gets a mutation
  run and a one-line note above the test naming the mutation. `mix quality`
  cannot see a comment, so this is a **Manual** criterion in every phase
  (`sb-xti`'s plan classifies it the same way and for the same reason); the
  scanner that reads the notes runs under `/wurk:verify --unattended`, which
  is Phase 6.
- `@spec` on every public function (dialyzer is in the full gate); errors are
  events (`{:ok, _} | {:error, _}`, never rescue-to-default at a leaf);
  structs and MapSets; pattern matching over multiple asserts.
- **No module may name Phoenix and none may live under
  `StatifierBlocks.Editor.*`.** Both are grep-checkable and both are automated
  criteria in every phase below.

### Key Discoveries

- `Assignability.valid_targets/4`
  (`lib/statifier_blocks/assignability.ex:554`) already enforces ADR-0005 d5
  rule 1: it iterates `module.slots(config)`, the **declared** slot set, not
  the slot keys the stored document happens to carry, and contributes no
  positions for a block whose type does not resolve. Rule 1 is therefore free.
- `valid_targets/4` does **not** filter the candidate's own subtree
  (`assignability.ex:555-564` has no such clause) and does not check slot
  arity. d5 rules 3 and 4 are this bead's to add - the ADR places them on the
  editor, and `sb-b3t` left them there deliberately.
- `Assignability.check/5` (`assignability.ex:321`) consults the upstream seam,
  the downstream seam, and the vacated seam. All three depend on the index
  within the slot. ADR-0005 d5's sentence "Nothing in that list depends on the
  index within the slot" is **not literally true of rule 2**. The reduction
  this bead implements, and the argument that it is still sound, are in
  "Design notes: the stated reduction" below. This was `sb-b3t`'s stated open
  question and it is settled here.
- `Core.Branch.config_schema/1` (`core/branch.ex:71`) keys one `:expression`
  field per arm by that arm's **slot name**, and `validate_config/1` reports
  most findings against the same key - so the common `{:config, block_id, key}`
  anchor routes to a field that exists. But `validate_config/1` also emits
  findings keyed `"arms"` (`core/branch.ex:87`, `:101`, `:115`), and `"arms"`
  is deliberately **not** a schema field (the moduledoc says so at
  `core/branch.ex:41`). A `:config` finding can therefore carry a key that
  matches no field. Where it renders is decided in "Design notes: unrouted
  config findings".
- `StatifierBlocks.Compiler.Finding` already exists and is a different struct
  for a different layer (stage/fault/code/reason, compiler pipeline). Two
  Finding modules is intentional. `StatifierBlocks.Finding` is the
  presentation struct ADR-0005 d11 specifies verbatim.
- `Document` exposes no tree-mutation API. Following `sb-b3t`'s precedent
  (`assignability.ex:291`, which kept its own private `find_block/2` rather
  than extend a module another bead owns), all tree surgery stays private
  inside `Edit`. No `sb-xti` module is modified by this bead.
- `Core.Parallel` declares `layout: :columns` and `Core.ResumableGroup`
  declares `slot_style: %{"interrupts" => :secondary}`, exactly as d10
  describes. The view model has real data to normalize against.
- Palette-aware arity and `:undeclared_slot` validation has no implementation:
  it is `sb-da9`, still open. So the `:arity` finding source has no producer
  yet, which is one of the reasons findings are caller-supplied (see below).

## Desired End State

A host with no Phoenix in its dependency tree can, in plain ExUnit:

1. build a command, apply it, get a new document and an inverse back, and
   apply the inverse to get the original document byte for byte;
2. push edits through a history, undo and redo them, and never get a document
   carrying config that `validate_config/1` rejects;
3. ask which slots would accept a dragged block and get a per-slot list that
   excludes the block's own subtree, full single-child slots, undeclared
   slots, and slots on unresolvable parents;
4. derive a view model from `{document, palette, findings}` in which every
   block already carries its declared slots, its form fields, its palette
   presentation metadata with d10's defaults applied, and its findings routed
   to the position that renders them - including findings whose config key
   names no field, which land somewhere visible rather than vanishing;
5. and run all of it with `phoenix_live_view` absent, because it is absent.

Verified by: full `mix quality` green (dialyzer, credo `--strict`, coverage at
or above 90%); `grep -rn "Phoenix" lib/ test/` empty; no file under
`lib/statifier_blocks/editor/`.

## What We're NOT Doing

- **The LiveView shell.** `StatifierBlocks.Editor` and its seven function
  components are `sb-7f2`. No `phoenix_live_view` dependency is added here,
  and nothing in this bead may require one.
- **The JS hook (d7), the stylesheet (d14), and the `assets/` entry in
  `files:` (d1).** All `sb-7f2`.
- **A compiler-finding-to-presentation-finding adapter.** The bead specifies
  the view model as a function of `{document, palette, findings}`, which reads
  as caller-supplied. See Open Questions - this is recorded, not built.
- **Palette-aware arity and `:undeclared_slot` findings.** `sb-da9`. The view
  model has a place to put an `:arity` finding; it does not produce one.
- **Any change to an accepted ADR.** Two widenings of the record's typespecs
  are documented below; neither contradicts a decision, and both follow the
  precedent `StatifierBlocks.Assignability`'s "The deliberate widening"
  moduledoc section set.
- **Anything built on `sb-ort`'s two package-reserved interrupt event names.**
  They are queued for operator review and are not settled.
- **Re-skinning existing examples.** The ADR-0005 worked example and the
  `myapp.*` fixtures on the base branch stay as they are (`sb-xln` owns that
  sweep); referencing them from tests is fine. Any **new** illustrative
  example in this bead uses a signup wizard with A/B testing, or card
  processing.
- **A second document generator.** `test/support/document_generator.ex` is
  extended, not duplicated.

## Implementation Approach

Bottom up, in dependency order: the command algebra first because everything
else consumes it, then the property that proves it, then the two consumers
(history, targets), then the projection (finding, view model). Each phase adds
one module (or one function group) plus its tests, so each is independently
committable and each leaves the full gate green on its own.

### Design notes: the command algebra

`Edit.apply/2` takes no palette, exactly as d3's spec says, so it is a purely
**structural** rewrite. Four rules make it total and make the inverse law
hold:

1. **A target's index is read against the slot's current children**, where an
   absent slot key means `[]`. Valid indices are `0..length(children)`
   inclusive; anything else is `{:error, {:index_out_of_range, target}}`.
2. **An absent slot key is created by an insert or a move into it.** This is
   not optional: `droppable_slots/3` offers every *declared* slot, and a
   declared slot with no children carries no key in the document's `slots`
   map (`Document.to_json/1` omits it, ADR-0001 d8). Refusing to create it
   would break the commonest drop there is.
3. **A remove prunes a slot key that it empties.** Symmetric with rule 2 and
   with canonical JSON's omission of empty slots, and it is what makes
   `apply(apply(d, e), inverse) == d` hold as **struct equality**, not merely
   as equal canonical bytes.
4. **`:move` reads its target index against the slot with the moved block
   already removed** (d4). Concretely: detach, then insert. The inverse of a
   move from `{P, s, i}` to `{Q, t, j}` is a move to `{P, s, i}` - the same
   `i`, because removing at `i` and re-inserting at `i` in the shortened list
   is the identity, and that is true whether or not `P == Q and s == t`. The
   ADR's own worked example confirms the reading: `blk_NOT` was the second
   block in `lane_nurture` and its inverse target index is `1`.

The four inverses:

| Command | Inverse |
|---|---|
| `{:insert, target, block}` | `{:remove, block.id}` |
| `{:remove, id}` | `{:insert, original_target, detached_subtree}` |
| `{:move, id, target}` | `{:move, id, original_target}` |
| `{:update_config, id, config}` | `{:update_config, id, previous_config}` |

### Design notes: two deliberate widenings of d3's error union

The record lists four error arms. Two more are needed and neither contradicts
a decision - each names a case the record's list does not enumerate:

- **`{:duplicate_block_id, Block.id()}`** - an `:insert` whose block (or whose
  subtree) carries an id already present in the document. ADR-0001 decision 1
  makes document-wide id uniqueness an invariant and `Document.validate/1`
  enforces it, so `apply/2` must refuse rather than produce a document that
  fails its own validator. The spelling matches `Decode`'s existing
  `{:duplicate_block_id, id}`.
- **`{:cannot_remove_root, Block.id()}`** - a `:remove` or `:move` naming the
  document root. The root occupies no slot, so there is no position to detach
  it from and no inverse to write. `{:no_such_block, id}` would be a lie about
  a block that plainly exists.

`{:no_such_slot, block_id, slot_name}`, the record's own arm, is given the one
meaning left to it once rule 2 above allows slot creation: a target whose slot
name is not a usable slot key - not a binary, or empty. Commands are
serializable values that can arrive from a replayed log, so this is a real
arm, not a dead one. It is recorded in Open Questions because the record
plainly imagined a different trigger for it.

Both widenings get a "The deliberate widening" section in the `Edit`
moduledoc, in the same shape `StatifierBlocks.Assignability` uses
(`assignability.ex:35-50`).

### Design notes: the stated reduction (ADR-0003 positions to ADR-0005 slots)

**Verdict: the reduction is sound, and it is implemented as "a slot is
droppable when some index in it is accepted."**

ADR-0003 gives `valid_targets/4 :: [{block_id, slot_name, index}]`; ADR-0005
d5 wants `droppable_slots/3 :: [{block_id, slot_name}]`. `Edit.Targets`
bridges exactly those two functions, and its moduledoc must say so in those
words.

The bridge is existential quantification over the index:

```
{b, s} is droppable  <=>  exists i such that {b, s, i} is in valid_targets/4
```

d5's sentence "Nothing in that list depends on the index within the slot" is
literally true of rules 1, 3 and 4 and **not** literally true of rule 2:
`Assignability.check/5` consults the upstream seam and the downstream seam,
both of which read the neighbours at `index - 1` and `index` and therefore
move with the index. (The third seam it checks, the vacated one, depends on
the candidate's own *current* position rather than on the target index, so it
is constant across a slot's gaps and is not part of what the reduction has to
answer for.) The reduction is sound anyway, for three reasons, and the
moduledoc states all three:

1. **The index-free half of rule 2 is preserved exactly.** Kind admission -
   `Assignability.admits?/3`, ADR-0003 decision 3's structural gate - is a
   function of `{parent module, parent config, slot, child kinds}` with no
   index in it. A slot that fails kind admission fails it at every index, so
   existential quantification drops the whole slot, which is the same verdict
   a per-slot rule would give. This is the half d5's rule 2 is really about:
   an `interrupts` slot does not accept a step, at any index.
2. **The index-dependent half is a seam check, and seams are validation, not
   admission.** d5 says the editor never blocks an edit for a validation
   reason outside its four rules, and ADR-0002 decision 6 already established
   that a document mid-edit is allowed to be invalid. A type mismatch at one
   gap of an otherwise-acceptable slot is exactly that kind of finding.
3. **The reduction is an over-approximation at gap granularity, never an
   under-approximation.** Highlighting a slot when at least one of its gaps
   accepts the block can offer the author a gap that would produce a
   `:type_mismatch` finding; it can never hide a gap that would have been
   clean. The failure mode is a finding the author can see and fix, not a
   legal arrangement they cannot reach - and the asymmetry is the one d5
   already chose when it rejected source-side checks.

The residue is real and gets written down in the moduledoc: **per-slot
highlighting is a superset of per-position validity, and a drop at a
particular gap may still produce an assignability finding.** That is the
documented cost of d5's per-slot granularity, not a defect introduced here.

`droppable_slots/3`'s signature carries no `Assignability.context()`, so the
implementation passes `%{}` - `entry_type` absent, which resolves to
`:unknown`, which ADR-0003 decision 5 makes the permissive default. The
moduledoc says so.

### Design notes: rules 3 and 4, which are this bead's alone

- **Rule 3, room.** After the projection to slots, drop any `{b, s}` whose
  arity in `module.slots(config)` is `:exactly_one` or `:zero_or_one` and
  whose current child count is 1 or more. A block already occupying such a
  slot excludes that slot for itself too; that only forbids moving a block to
  the position it already holds, which costs nothing.
- **Rule 4, subtree.** Drop any `{b, s}` where `b` is the dragged block or a
  descendant of it. Computed once as a `MapSet` of
  `Document.blocks/1`-walked ids rooted at the dragged block, so the filter is
  a membership test rather than a repeated path walk.

`droppable_slots/3` takes a `Block.id()` per the record; a block id that names
nothing in the document yields `[]`. ADR-0005 d8 requires the "+" button's
palette filter to use "the same predicate", and a palette insert has no block
in the document yet, so `Edit.Targets` also exports
`droppable_slots_for/3` taking a `%Block{}` that need not be in the document.
`droppable_slots/3` is implemented as a lookup followed by a call to it, so
there is one implementation, not two. This is the third documented widening
and it goes in the same moduledoc section.

### Design notes: d9's gate, and where it lives

`Edit.apply/2` has no palette, so it cannot ask `validate_config/1` anything.
The gate therefore lives in two named places:

- `Edit.check_config/3` - `@spec check_config(Palette.t(), Document.t(), t())
  :: :ok | {:error, {:invalid_config, Block.id(), [BlockType.finding()]}}`.
  `:ok` for the three commands that are not `:update_config`, and for an
  `:update_config` on a block whose type does not resolve (there is no
  authority to consult; d12 already forbids editing such a block's config, and
  that is the editor's rule, not this function's).
- `Edit.History.commit/4` - the one funnel: `check_config/3`, then
  `Edit.apply/2`, then push the inverse onto the undo stack and clear the redo
  stack. `sb-7f2`'s shell calls only this.

The gate runs on **every** path, undo and redo included - one code path, no
exception to test, and the strict reading of d9. The config an inverse
restores was in the document, so it validated under the palette that put it
there; ADR-0005 d15 makes the editor single-session, so a palette swap
mid-session is out of scope. The consequence (an undo could in principle be
refused if a host swapped the palette under a live session) is recorded in
Open Questions.

### Design notes: the view model, findings, and the unrouted `"arms"` case

`ViewModel.build/3` takes `{document, palette, findings}` where `findings` is
a caller-supplied `[Finding.t()]`. It **derives** two finding sources itself,
because d13 puts resolution, migration and validation inside `ViewModel`:

- `:resolution` - from `Palette.resolve/2` failing on a block
  (`:unknown_block_type`, `:block_type_too_new`, `:migration_failed`),
  anchored `{:block, id}`, severity `:error`.
- `:config` - from `validate_config/1` on a resolved block, one per
  `{key, message}` pair, anchored `{:config, id, key}`, severity `:error`.

`:arity`, `:assignability` and `:lint` findings arrive from the caller,
because their producers live elsewhere (`sb-da9`, `Assignability.validate/3`,
and the compiler's invoke-type lint respectively). Derived and supplied
findings are concatenated - derived first - into one `findings` list, and the
same list is what the document-level panel renders.

**Routing, and the case that must not vanish.** Each finding is placed by its
anchor:

| Anchor | Position in the view model |
|---|---|
| `{:block, id}` | that node's `findings` |
| `{:slot, id, name}` | that slot's `findings` (a slot name the node does not carry falls back to the node's `findings`) |
| `{:config, id, key}` where `key` matches a `config_schema/1` field | that field's `findings` |
| `{:config, id, key}` where `key` matches **no** field | that node's `form.unrouted` |
| any anchor naming a block id not in the document | the view model's top-level `orphan_findings` |

`form.unrouted` is rendered at the head of the config form, and the node also
carries `findings_count` covering its whole subtree so a collapsed node shows
a badge (d11's last sentence). `Core.Branch`'s `"arms"` findings are the live
instance of the fourth row and they get their own test. **No route drops a
finding**: the routing function is total, every arm lands somewhere, and a
test asserts that the number of findings placed anywhere in the view model
equals the number that went in.

**Shape.** All structs, all under `StatifierBlocks.ViewModel`:

```
%ViewModel{document_id, revision, root: %Node{}, palette_groups: [%PaletteGroup{}],
           findings: [Finding.t()], orphan_findings: [Finding.t()]}
%ViewModel.Node{block_id, type, type_version, status, entry: %{}, slots: [%Slot{}],
                form: %Form{} | nil, raw_config_json: String.t() | nil,
                findings: [Finding.t()], findings_count: non_neg_integer()}
%ViewModel.Slot{name, label, arity, style, declared?: boolean(),
                children: [%Node{}], findings: [Finding.t()]}
%ViewModel.Form{fields: [%Field{}], unrouted: [Finding.t()]}
%ViewModel.Field{key, type, label, required?, default, value, findings: [Finding.t()]}
```

- `status` is `:ok` or `{:unresolvable, reason}` carrying `Palette.resolve/2`'s
  error term.
- `entry` is `palette_entry/0` with d10's eight defaults applied - `label`
  defaulting to the type name, `group` to `"Other"`, `description` to `""`,
  `icon` to `nil`, `keywords` to `[]`, `order` to `0`, `layout` to `:stack`,
  `slot_style` to `%{}` - so a type that omits the callback still renders,
  which ADR-0002 decision 5 promised.
- `slots` for a resolved node is `module.slots(config)` in declared order
  (`declared?: true`), **followed by** any slot key the document carries that
  the type did not declare (`declared?: false`, `arity: nil`, raw name as
  label). Undeclared children are data and d12's whole point is that data does
  not vanish; `sb-da9` will attach the finding.
- `slots` for an unresolvable node is every slot key the document carries, all
  `declared?: false`, with raw names as labels - d12 verbatim.
- `form` is `nil` and `raw_config_json` is `CanonicalJson`-encoded config for
  an unresolvable node (d12: config read-only, no schema to guess at). For a
  resolved node it is `config_schema/1` re-derived from current config (d9:
  a projection, never cached), each field carrying its current value.
- `palette_groups` groups the palette's types by `entry.group`, sorted by
  group name then `order` then `label`, feeding `sb-7f2`'s `PaletteBrowser`.

`c:StatifierBlocks.BlockType.palette_entry/0`'s return type is narrowed from
`map()` to a new `BlockType.palette_entry/0` type spelled exactly as ADR-0005
gives it. That is the pin ADR-0002's "Who owns what" table assigns to
ADR-0005, and it mirrors `sb-b3t` pinning `io/1`. It is the only change to a
file this bead does not create.

## Phase 1: The command algebra

### Overview

`StatifierBlocks.Edit`: the types, `apply/2`, the four inverses, the six error
arms, and the private tree surgery.

### Changes Required:

#### 1. The command module
**File**: `lib/statifier_blocks/edit.ex` (new)
**Changes**: `target/0` and `t/0` from the record verbatim; `apply/2`; the two
documented widenings; a "The deliberate widening" moduledoc section; the four
structural rules from "Design notes: the command algebra" stated in the
`apply/2` doc.

```elixir
@spec apply(Document.t(), t()) ::
        {:ok, Document.t(), t()}
        | {:error, {:no_such_block, Block.id()}}
        | {:error, {:no_such_slot, Block.id(), Block.slot_name()}}
        | {:error, {:index_out_of_range, target()}}
        | {:error, {:would_cycle, Block.id()}}
        | {:error, {:duplicate_block_id, Block.id()}}
        | {:error, {:cannot_remove_root, Block.id()}}
```

#### 2. Tests
**File**: `test/statifier_blocks/edit_test.exs` (new)
**Changes**: one describe per command. Every error arm asserted. d4's
edge cases explicitly: same-slot move forward (1 -> 3 of five), same-slot move
backward (3 -> 1), move to the slot's end index, move between slots, move into
a slot that does not yet carry a key, move that empties its source slot
(pruning), `:would_cycle` on a move into the dragged block's own subtree and
onto the dragged block itself, `:duplicate_block_id` on inserting a subtree
whose id is already present, `:cannot_remove_root`.

New fixtures use a signup wizard with A/B testing (steps, variants, conversion
events) built from `Palette.core()` types.

### Success Criteria:

#### Automated Verification:
- [x] `mix format` clean and full `mix quality` green, coverage at or above 90%
- [x] `grep -rn "Phoenix" lib/ test/` returns nothing
- [x] no file exists under `lib/statifier_blocks/editor/`
- [x] every error-arm atom in the `apply/2` spec appears in
      `edit_test.exs`: `for a in no_such_block no_such_slot index_out_of_range
      would_cycle duplicate_block_id cannot_remove_root; do grep -q ":$a"
      test/statifier_blocks/edit_test.exs || echo "MISSING $a"; done`

#### Manual Verification:
- [ ] A sabotage note sits above every new test asserting `lib/` behaviour, and
      each named mutation was actually run and actually went red
- [ ] The four structural rules in the `apply/2` doc match what the code does,
      read side by side
- [ ] The widening section names both widenings and says why the record's list
      did not cover them

**Implementation Note**: Use `mix quality --profile loop` between edits; the
full `mix quality` is the phase gate. In looped execution the Automated
criteria gate advancement and the Manual ones are deferred.

---

## Phase 2: The apply/inverse property

### Overview

The bead's headline acceptance criterion: apply-then-inverse is the identity,
over **generated command sequences**, not three examples (d3).

### Changes Required:

#### 1. Command generation, in the existing generator
**File**: `test/support/document_generator.ex`
**Changes**: add `commands/2` (or `commands/3`) alongside `generate/2`, using
the same explicit `:rand` seeding so a failing case is regenerable from one
integer. Generated commands are drawn against the document as it stands after
the previous command in the sequence, so the sequence is applicable rather
than mostly-refused: pick a real parent and one of its slot keys (or a fresh
slot name, exercising rule 2), a real index in range, and a real block id for
`:remove`/`:move`/`:update_config`. Deliberately include a minority of
refusable commands so the property covers the error paths too.

The moduledoc gains a paragraph saying it now serves two consumers
(`decode_test.exs`'s round-trip corpus and `edit_property_test.exs`).

#### 2. The property test
**File**: `test/statifier_blocks/edit_property_test.exs` (new)
**Changes**: for each of N generated documents, generate a sequence of M
commands; fold the sequence, collecting inverses; assert after every step that
applying the inverse returns the document that step started from, by struct
equality; then assert that unwinding the whole collected inverse list in
reverse yields the original document. A refused command asserts the document
is unchanged and contributes no inverse. On failure, print the seed index.

### Success Criteria:

#### Automated Verification:
- [x] full `mix quality` green, coverage at or above 90%
- [x] `grep -rn "Phoenix" lib/ test/` returns nothing
- [x] the suite is deterministic: `mix test --seed 0` run twice produces
      identical summary lines (`diff <(mix test --seed 0 | tail -3) <(mix test
      --seed 0 | tail -3)` is empty)

#### Manual Verification:
- [ ] A sabotage note sits above every new test asserting `lib/` behaviour, and
      each named mutation was actually run and actually went red
- [ ] The property folds over generated sequences rather than a fixed example
      list, read in the test file
- [ ] The generated commands genuinely exercise all four command tags and both
      the same-slot and cross-slot move cases (inspect a printed sample)
- [ ] The seed is printed on failure and re-running with it reproduces

---

## Phase 3: History and the d9 config gate

### Overview

`Edit.History` (undo/redo over commands) plus `Edit.check_config/3`, together
making "invalid config never reaches the document" a property of the pure
layer.

### Changes Required:

#### 1. The gate
**File**: `lib/statifier_blocks/edit.ex`
**Changes**: add `check_config/3` per "Design notes: d9's gate".

#### 2. The history
**File**: `lib/statifier_blocks/edit/history.ex` (new)
**Changes**: `%History{undo: [Edit.t()], redo: [Edit.t()], limit: pos_integer() | :infinity}`.
`commit/4` clears the redo stack; `undo/3` moves the applied command's inverse
onto redo; `redo/3` moves it back. The gate runs on every path. A bounded
`limit` drops the oldest undo entry.

Argument order is fixed here rather than left to the implementer, because
`sb-7f2` calls `commit/4` as its one funnel and should not have to re-derive
it. The history is the state, so it goes first (the repo's pipeline-threading
convention); the palette follows `check_config/3`'s own position for it:

```elixir
@spec new(keyword()) :: t()
@spec commit(t(), Palette.t(), Document.t(), Edit.t()) ::
        {:ok, t(), Document.t()}
        | {:error, {:invalid_config, Block.id(), [BlockType.finding()]}}
        | {:error, term()}
@spec undo(t(), Palette.t(), Document.t()) ::
        {:ok, t(), Document.t()} | {:error, :nothing_to_undo} | {:error, term()}
@spec redo(t(), Palette.t(), Document.t()) ::
        {:ok, t(), Document.t()} | {:error, :nothing_to_redo} | {:error, term()}
@spec can_undo?(t()) :: boolean()
@spec can_redo?(t()) :: boolean()
```

The trailing `{:error, term()}` arm on the three is `Edit.apply/2`'s own error
union, propagated unchanged rather than re-wrapped.

#### 3. Tests
**File**: `test/statifier_blocks/edit/history_test.exs` (new)
**Changes**: undo/redo round trips over multi-command sessions; redo cleared
by a new commit; the limit; and the d9 acceptance test - an `:update_config`
carrying config that `Core.Branch.validate_config/1` rejects (an arm with no
`"cond"`, and an arm whose slot name is malformed) returns
`{:error, {:invalid_config, id, findings}}`, leaves the document identical,
and leaves both stacks untouched.

### Success Criteria:

#### Automated Verification:
- [x] full `mix quality` green, coverage at or above 90%
- [x] a test asserts the document is unchanged **and** both stacks are
      unchanged after a refused `:update_config`
- [x] `grep -rn "Phoenix" lib/ test/` returns nothing

#### Manual Verification:
- [ ] A sabotage note sits above every new test asserting `lib/` behaviour, and
      each named mutation was actually run and actually went red
- [ ] Running the gate on undo/redo is stated in the moduledoc together with
      the single-session justification

---

## Phase 4: Drop-target enumeration

### Overview

`Edit.Targets.droppable_slots/3`, the stated reduction, and d5's rules 3 and 4.

### Changes Required:

#### 1. The module
**File**: `lib/statifier_blocks/edit/targets.ex` (new)
**Changes**: `droppable_slots/3` and `droppable_slots_for/3`. The moduledoc
carries, in full: the reduction (naming
`Assignability.valid_targets/4` and `droppable_slots/3` as the two functions
it bridges), the three soundness arguments, the over-approximation residue,
the `%{}` context note, and the widening note for `droppable_slots_for/3`.

#### 2. Tests
**File**: `test/statifier_blocks/edit/targets_test.exs` (new)
**Changes**:
- the ADR-0005 worked example's seven-slot expectation, asserted as a set;
- rule 1: an undeclared slot key present in the document is not offered; an
  unresolvable parent offers nothing;
- rule 2: a `core.on_event` handler is offered `interrupts` and not `body`,
  and a step is offered `body` and not `interrupts` - the kind gate surviving
  the reduction, which is soundness argument 1 made executable;
- rule 3: an occupied `:exactly_one` slot is not offered, an empty one is;
- rule 4: **dragging a group that has children** - no slot on the group and no
  slot on any descendant appears, asserted over a three-level subtree;
- the existential reduction itself: a slot where only some indices pass
  `check/5` is still offered, asserted by comparing against
  `Assignability.valid_targets/4` on the same document;
- `droppable_slots/3` on an id not in the document returns `[]`;
- `droppable_slots_for/3` on a fresh palette block returns the same slots as
  the id form does for an equivalent block already in the tree.

### Success Criteria:

#### Automated Verification:
- [x] full `mix quality` green, coverage at or above 90%
- [x] all four d5 rules have a named test, and rule 4's test drags a group with
      descendants
- [x] a test compares `droppable_slots/3`'s output against the projection of
      `Assignability.valid_targets/4`, so the reduction is asserted rather than
      assumed
- [x] `grep -rn "Phoenix" lib/ test/` returns nothing

#### Manual Verification:
- [ ] A sabotage note sits above every new test asserting `lib/` behaviour, and
      each named mutation was actually run and actually went red
- [ ] The moduledoc's reduction paragraph names both functions and states the
      residue, not only the conclusion
- [ ] The seven-slot worked-example assertion matches the ADR's list exactly

---

## Phase 5: The presentation finding and the view model

### Overview

`StatifierBlocks.Finding`, `StatifierBlocks.ViewModel` and its four nested
structs, d9's form generation, d10's defaults, d11's routing, d12's
unresolvable rendering, and the `palette_entry/0` pin.

### Changes Required:

#### 1. The finding
**File**: `lib/statifier_blocks/finding.ex` (new)
**Changes**: the struct and `anchor/0` exactly as ADR-0005's typespec block
gives them, plus `new/4` in the shape `Compiler.Finding.new/4` already uses,
and a moduledoc paragraph saying plainly that this is the **presentation**
finding and `StatifierBlocks.Compiler.Finding` is the compiler's, and that two
modules is intentional.

#### 2. The callback pin
**File**: `lib/statifier_blocks/block_type.ex`
**Changes**: add `@type palette_entry` verbatim from ADR-0005 and narrow
`@callback palette_entry() :: palette_entry()`.

#### 3. The view model
**File**: `lib/statifier_blocks/view_model.ex` (new)
**Changes**: `%ViewModel{}` and the `Node`/`Slot`/`Form`/`Field`/`PaletteGroup`
structs, `build/3`, and the routing described in "Design notes: the view
model". Derives `:resolution` and `:config` findings; concatenates
caller-supplied ones; routes all of them; counts per subtree.

#### 4. Tests
**File**: `test/statifier_blocks/view_model_test.exs` (new)
**Changes**:
- d10 defaults: a block type with no `palette_entry/0` still yields all eight
  keys, `label` being the type name;
- `Core.Parallel`'s `layout: :columns` and `Core.ResumableGroup`'s
  `slot_style` reach the node;
- d9: fields come from `config_schema/1` and carry current values; the schema
  is re-derived after a config change (add an arm to a branch, the field list
  grows) rather than cached;
- d11 routing: one test per anchor row, including a `:slot` anchor naming a
  slot the node does not carry, and a finding naming a block id not in the
  document;
- **the `"arms"` case**: a `Core.Branch` whose `validate_config/1` emits an
  `"arms"`-keyed finding puts it in `form.unrouted`, and it is also present in
  the top-level `findings` list;
- the conservation property: findings in equals findings placed, over a
  document mixing all five sources;
- `findings_count` covers a subtree;
- d12: a block whose type is not in the palette gets
  `status: {:unresolvable, ...}`, `form: nil`, non-nil `raw_config_json`, a
  `:block` finding, and its children still render, with raw slot names;
- `palette_groups` grouping and ordering.

### Success Criteria:

#### Automated Verification:
- [x] full `mix quality` green, coverage at or above 90%
- [x] the conservation test passes: no finding is dropped by routing
- [x] a test asserts an `"arms"`-keyed `:config` finding lands in
      `form.unrouted`
- [x] a test asserts an unresolvable block renders its children
- [x] `grep -rn "Phoenix" lib/ test/` returns nothing, and no file exists under
      `lib/statifier_blocks/editor/`

#### Manual Verification:
- [ ] A sabotage note sits above every new test asserting `lib/` behaviour, and
      each named mutation was actually run and actually went red
- [ ] The view model carries everything `sb-7f2`'s eight components would need,
      checked against ADR-0005 d13's component table row by row
- [ ] The `Finding` moduledoc makes the two-Finding situation unmistakable

---

## Phase 6: Documentation, changelog fragment, and the full gate

### Overview

The prose pass, the changelog fragment, and the phoenix-absent proof recorded.

### Changes Required:

#### 1. Changelog fragment
**File**: `changelog.d/sb-ia5.md` (new)
**Changes**: `### Added` for `Edit`, `Edit.History`, `Edit.Targets`,
`Finding`, `ViewModel`; `### Changed` for the `palette_entry/0` return-type
pin, phrased as `sb-b3t.md` phrased the `io/1` pin - one line per change,
present tense, no nested bullets.

#### 2. Moduledoc pass
**Files**: the five new `lib/` modules
**Changes**: confirm each moduledoc cites its decision numbers, that `Edit`
and `Edit.Targets` both carry their widening sections, and that
`Edit.Targets`'s reduction paragraph is present and complete.

#### 3. Plan record
**File**: this plan
**Changes**: record the machine-checked results under the criteria, as
`sb-w6d`'s and `sb-b3t`'s plans do.

### Success Criteria:

#### Automated Verification:
- [x] full `mix quality` green from a clean `_build`, coverage at or above 90%
- [x] `mix deps.tree` contains no `phoenix` entry and the full suite passes
- [x] `grep -rn "Phoenix" lib/ test/` returns nothing
- [x] the terminology scan in the umbrella's `docs/terminology-firewall.md` is
      clean over the branch's full outbound content
- [x] `changelog.d/sb-ia5.md` exists and uses only standard headings

**Machine-checked (unattended, 2026-08-27):** `rm -rf _build && mix deps.get
&& mix quality` from a genuinely clean `_build` - format, compile
(warnings-as-errors), credo, deps, dialyzer (PLT built this run), 430 of 430
tests, **95.6%** coverage against the 90% floor. `mix deps.tree | grep -i
phoenix` and `grep -rn "Phoenix" lib/ test/` both empty. The umbrella's
terminology-firewall pre-push scan
(the pattern is recorded in the umbrella's
`docs/terminology-firewall.md`, and is deliberately not reproduced here -
the pattern enumerates the very terms the firewall exists to keep out of a
public repo, so quoting it inline is itself a leak)
returns nothing over the whole tree. `changelog.d/sb-ia5.md` exists with only
`### Added` / `### Changed` headings, phrased the way `sb-b3t.md` phrases the
`io/1` pin. The example-domain scan (`enrich|scor(e|ing)|crm_push`) over the
five new `lib/` modules, their five test files, and this bead's addition to
`test/support/document_generator.ex` turned up two hits, both pre-existing
and out of scope: `document_generator.ex`'s `@type_names` list (predates this
bead's `commands/2` addition) and `view_model_test.exs`'s reference to
`test/support/block_type_fixtures.ex`'s pre-existing `"toy.score"` /
`"Enrichment"` toy fixture. Neither is new prose or a new example this bead
introduced.

#### Manual Verification:
- [ ] `/wurk:verify --unattended` run and its findings folded back
- [ ] Every new example is a signup wizard or a card-processing example; no new
      enrichment/scoring/CRM-flavoured example was introduced

---

## Testing Strategy

### Unit Tests:

| File | Covers |
|---|---|
| `test/statifier_blocks/edit_test.exs` | every command, every error arm, d4's edge cases |
| `test/statifier_blocks/edit_property_test.exs` | d3's law over generated sequences |
| `test/statifier_blocks/edit/history_test.exs` | undo/redo, and d9's refusal |
| `test/statifier_blocks/edit/targets_test.exs` | d5's four rules and the reduction |
| `test/statifier_blocks/view_model_test.exs` | d9 forms, d10 defaults, d11 routing, d12 rendering |

Key edge cases, all named above: same-slot moves in both directions (the case
d4 exists for), a move that empties its source slot, insert into a declared
slot that carries no key, duplicate ids, root removal, dragging a group with
descendants, an occupied `:exactly_one` slot, an `"arms"`-keyed config finding,
an anchor naming a missing block, and an unresolvable block with children.

Every test asserting `lib/` behaviour is sabotage-verified: break the line it
covers, confirm red, revert, and write the mutation in one line above the test.
Budget roughly a dozen mutations across the five phases that add `lib/` code.

### Manual Testing Steps:

1. `mix quality` from a clean `_build` in this worktree; read every line,
   including the `○` skipped-stage lines.
2. `mix deps.tree` - confirm no `phoenix` anywhere.
3. `grep -rn "Phoenix" lib/ test/` and `ls lib/statifier_blocks/editor` -
   both must come back empty.
4. Read `Edit.Targets`'s moduledoc against ADR-0005 d5 and ADR-0003's
   `valid_targets/4` doc, side by side, and confirm the reduction paragraph
   says which two functions it bridges and what the residue is.
5. Walk ADR-0005 d13's component table and confirm each row's data needs are
   met by the view model.

## Open Questions

Recorded rather than resolved. None blocks implementation; the first is the
one a reviewer should look at hardest.

1. **d5's "nothing depends on the index" sentence is not literally true of
   rule 2.** `Assignability.check/5`'s three seam checks all read neighbours.
   This plan implements the existential reduction and argues it sound
   (over-approximation at gap granularity; the kind gate, which is the
   index-free half, is preserved exactly). The plan does **not** amend
   ADR-0005 - amending it is the operator's. If the operator wants d5's
   sentence corrected to say "nothing in *rules 1, 3 and 4*, and nothing in
   rule 2's kind gate, depends on the index", that is a one-line clarifying
   amendment and this implementation already matches it.
2. **`{:no_such_slot, block_id, slot_name}` has no natural trigger** in a
   palette-free `apply/2`, because refusing to create an absent-but-declared
   slot key would break the commonest drop there is. This plan gives it the
   malformed-slot-name meaning (not a binary, or empty), which is reachable
   from a replayed command log. If the record intended it to mean "not
   declared by the parent's type", that requires a palette in `apply/2`'s
   signature, which contradicts d3's spec.
3. **No compiler-finding-to-presentation-finding adapter is built.** The bead
   specifies `{document, palette, findings}`, which reads as caller-supplied,
   and the instruction was not to invent one. But `Compiler.Finding` carries
   `block_id` and `config_key`, which map mechanically onto d11's `{:config,
   id, key}` / `{:block, id}` anchors, and the invoke-type lint on the base
   branch is a live producer of exactly the `:lint` source d11 reserves. A ten
   line adapter is the obvious next step; recommended home is `sb-7f2` (where
   a compile result is actually in hand) or a small follow-up bead.
4. **The d9 gate runs on undo and redo too.** One code path, strict d9. The
   theoretical cost is that a host swapping the palette mid-session could see
   an undo refused. ADR-0005 d15 makes the editor single-session, so this is
   out of scope; if `sb-7f2` finds it in practice, the fix is a documented
   exemption for inverses, not a change here.
5. **`:arity` findings have no producer.** `sb-da9` is open. The view model
   has the anchor and the slot-level slot to render them into; nothing
   generates one yet, so that route is tested with a hand-built finding.
6. **`ViewModel.build/3`'s third argument.** ADR-0005 d13's table says the
   view model derives from `{document, palette}`; the bead says
   `{document, palette, findings}`. This plan follows the bead, and reads d13
   as shorthand rather than as a contradiction - d13's own paragraph says the
   view model is where validation happens, which is where the derived findings
   come from, and the third argument is the seam for the sources that live
   outside this package's pure layer.

## References

- Source record: `docs/adr/0005-liveview-editor.md` (decisions 1-5, 9-13, and
  the typespec block)
- Related ADRs: `docs/adr/0001-block-document-schema.md` (decisions 1, 3, 5,
  8), `docs/adr/0002-block-type-behaviour.md` (decisions 3, 5, 6, 7),
  `docs/adr/0003-assignability.md` (decisions 3, 5, 6, 7)
- The function this bead reduces:
  `lib/statifier_blocks/assignability.ex:554` (`valid_targets/4`)
- The index-free kind gate: `lib/statifier_blocks/assignability.ex:140`
  (`admits?/3`)
- The `"arms"` routing edge: `lib/statifier_blocks/core/branch.ex:41`,
  `:71`, `:87`
- The other Finding: `lib/statifier_blocks/compiler/finding.ex`
- The generator to extend: `test/support/document_generator.ex`
- Prior plans for shape: `docs/plans/260826-sb-b3t-assignability-seam.md`,
  `docs/plans/260826-sb-w6d-core-block-types.md`
- Bead: `sb-ia5` (blocks `sb-7f2`; depends on `sb-dvj`, `sb-b3t`)

## Deferred Manual Verification

Manual verification items are deferred during looped (--loop) execution and
surfaced here once, rather than blocking after each phase. Confirm these
before considering the plan fully landed.

### Phase 1

- [ ] A sabotage note sits above every new test asserting `lib/` behaviour, and
      each named mutation was actually run and actually went red
- [ ] The four structural rules in the `apply/2` doc match what the code does,
      read side by side
- [ ] The widening section names both widenings and says why the record's list
      did not cover them

**Implementation Note**: Use `mix quality --profile loop` between edits; the
full `mix quality` is the phase gate. In looped execution the Automated
criteria gate advancement and the Manual ones are deferred.

---

### Phase 2

- [ ] A sabotage note sits above every new test asserting `lib/` behaviour, and
      each named mutation was actually run and actually went red
- [ ] The property folds over generated sequences rather than a fixed example
      list, read in the test file
- [ ] The generated commands genuinely exercise all four command tags and both
      the same-slot and cross-slot move cases (inspect a printed sample)
- [ ] The seed is printed on failure and re-running with it reproduces

---

### Phase 3

- [ ] A sabotage note sits above every new test asserting `lib/` behaviour, and
      each named mutation was actually run and actually went red
- [ ] Running the gate on undo/redo is stated in the moduledoc together with
      the single-session justification

---

### Phase 4

- [ ] A sabotage note sits above every new test asserting `lib/` behaviour, and
      each named mutation was actually run and actually went red
- [ ] The moduledoc's reduction paragraph names both functions and states the
      residue, not only the conclusion
- [ ] The seven-slot worked-example assertion matches the ADR's list exactly

---

### Phase 5

- [ ] A sabotage note sits above every new test asserting `lib/` behaviour, and
      each named mutation was actually run and actually went red
- [ ] The view model carries everything `sb-7f2`'s eight components would need,
      checked against ADR-0005 d13's component table row by row
- [ ] The `Finding` moduledoc makes the two-Finding situation unmistakable

---

### Phase 6

- [ ] `/wurk:verify --unattended` run and its findings folded back
- [ ] Every new example is a signup wizard or a card-processing example; no new
      enrichment/scoring/CRM-flavoured example was introduced

---
