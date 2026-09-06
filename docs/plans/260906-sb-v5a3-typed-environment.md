# The typed environment Implementation Plan

## Overview

`StatifierBlocks.Environment` is the flow-sensitive walk ADR-0011 decides: a
map from datamodel path to type, carried through the document in
`Document.blocks/1`'s pre-order, seeded from the entry block's subject and
updated by every block's write signatures. `StatifierBlocks.Assignability` is
redefined over it - `check/5`, `valid_targets/4`, `validate/3`,
`inbound_type/4` and `seam_reason/4` keep their arities and stop asking about
a seam between adjacent siblings. Bead: `sb-v5a3`.

The read check is `StatifierDatamodel.Types.satisfies/3` and this package
writes no second one, and no `Compatibility` or `Coverage` module of its own
(ADR-0011 decision 3).

## Current State Analysis

**The seam is the whole data-flow gate today.**
`lib/statifier_blocks/assignability.ex:458` computes `inbound_type/4` by
walking to the previous sibling's resolved `produces/4` (`:383`), or to the
parent's own inbound at index 0. `check/5` (`:539`) builds three seam findings
out of it and `validate/3` (`:861`) reaches two of the same primitives
directly.

**`io/1`'s `consumes` and `produces` are the only declarations.** Every core
type's `io/1` is a `kinds` / `slot_accepts` declaration plus, on the
containers, `produces: :unknown`
(`core/branch.ex:138`, `core/parallel.ex:163`, `core/invoke.ex:147`,
`core/map.ex:329`, `core/subchart.ex:319`). `core.sequence` is the only
`{:passthrough, "body"}` producer (`core/sequence.ex:45`). No shipped type
declares a `consumes`.

**Four core fields already name a datamodel path**, in the two spellings
`BlockType.datamodel_path?/1` accepts (`block_type.ex:614-617`):
`core.assign`'s `path` (`core/assign.ex:70-81`, `:string` plus
`datamodel_path?: true`), `core.foreach`'s `items` (`core/foreach.ex:174-185`,
same spelling), `core.map`'s `items` and `collect` (`core/map.ex:232-252`,
`{:path, %{}}`) and `core.subchart`'s `assign_to`
(`core/subchart.ex:250-256`, `{:path, %{}}`). `core.on_event`'s `capture`
(`core/on_event.ex:283-298`) is a config map with no field declaration at all.

**`core.foreach` already declares `item_as` and `index_as`**
(`core/foreach.ex:186-199`), defaults `"item"` and `""`. `core.map` declares
neither (ADR-0009's Note deferred them; ADR-0011 decision 11 keeps them with
the defaults `item` and `index`).

**The datamodel document reaches two places and neither is assignability.**
The editor takes it as an assign (`editor.ex:439`, normalized at `:530`) and
the compiler as a `:datamodel` option read only by the sensitive-path refusal
(`compiler.ex:1378`). `Assignability.context/0` (`assignability.ex:101`)
carries `:entry_type` and nothing else, and the only producer of a non-empty
context in `lib/` is `compiler.ex:534`. `Edit.Targets` deliberately passes
`%{}` (`edit/targets.ex:54-57`).

**`statifier_datamodel` is on the git pin.**
`StatifierDatamodel.Types` gives `parse/2`, `scalar/1`, `satisfies?/3`,
`satisfies/3` and `to_string/1`; `StatifierDatamodel.Declarations` gives
`from_document/1` and `fetch/2`.

## Desired End State

`Environment.at/3` answers "what does the environment hold here" for any
position, and `Assignability` asks it instead of asking a sibling. A read that
the environment does not satisfy is a validation `:error` naming the block, the
field and the path; a path the environment does not hold is satisfied and stays
ADR-0005 clause 11e's `:info`, produced elsewhere. A branch whose arms agree
keeps its types; a branch whose arms disagree drops that path and only that
path to `:unknown`.

## What We're NOT Doing

- No `Compatibility` and no `Coverage` module here (ADR-0011 decision 3;
  `sd-ADR-0001` decisions 9-11 own them).
- No `expects:` / `writes:` on `t:StatifierBlocks.BlockType.path_opts/0` and
  no validation of them - the walk *reads* them where a declaration carries
  them, and `sb-xk1h` declares them.
- No write signatures across the `core.*` vocabulary - `sb-u7zt` does that.
  `core.assign`, `core.foreach`, `core.map` and `core.subchart` get theirs
  here only because the existing `datamodel_path?` declarations already imply
  them under decision 2's rule.
- No `field_candidates`, no Datamodel-tab environment listing, no declared
  labels in findings (`sb-xk1h` / `sb-sy0q`).
- No widening of `Edit.Targets`' signatures to carry a datamodel document;
  the editor's drop check keeps running with no declarations, which is
  permissive-degrading, and `sb-sy0q` is where the surface work is.
- No ADR edit. ADR-0011 already decides everything here.

## Implementation Approach

One new module, one rewritten half of `Assignability`, and one threading edit
in the compiler.

`Environment` holds `%{path => {type, writer}}` internally, where `writer` is
the block id whose write signature put the type there or `:slot_entry`, which
is what ADR-0011 decision 8's `{:type_mismatch, ...}` tuple needs for its
`upstream_ref` member. `at/3` returns the path-to-type projection the record
describes; `annotated/3` returns the internal form for the one caller that
needs the writer.

The walk is uniform. For a block `B` reached with environment `Γ`:

1. every slot `B` carries is walked from `Γ` (the shelf is not entered);
2. what the slots produce is merged per path by agreement (decision 4) - a
   container with one slot merges to that slot's own answer, so a `core.group`
   body's writes flow out of the group, and a `core.on_event`'s `capture` in a
   group's `interrupts` slot is held by one arm only and so leaves as
   `:unknown`, which is decision 10's own answer;
3. `B`'s write signatures are applied to the merge.

`core.foreach` binds its item and index names inside its `body` slot and they
do not leave it, per decision 11.

## Phase 1: `StatifierBlocks.Environment`

`lib/statifier_blocks/environment.ex`, and
`test/statifier_blocks/environment_test.exs` (a pure test - no headless
wrapper).

- `at/3`, `at/4`, `annotated/4`, `seed/3`, `subject_path/2`,
  `read_signatures/2`, `write_signatures/2`, `declarations/1`, `type_of/2`,
  `satisfies/3`.
- Decision 2's three write-signature forms and one read-signature form,
  decision 6's `consumes`/`produces` desugaring against the subject path,
  decision 4's merge, decision 11's fan-out binding.
- `:unknown` is the atom; the string `"unknown"` normalizes onto it
  (RQ-032-5's named reinterpretation); `{:list, T}` maps onto the document's
  own `list`.

### Success criteria

- `mix quality` green.
- The worked shape of ADR-0011 (the `scopes` + `types` document verbatim)
  drives the tests: the seed, the assign, the agreeing branch, the
  disagreeing branch.
- A document of nothing but empty sequences terminates.

## Phase 2: `Assignability` over the environment

- `assignable?/3` (and a `/4` taking declarations) keeps its steps and runs
  the host relation **last**, after the read check's coverage step.
- `seam_reason/4` (and `/5`) gains `{:shape_not_satisfied, missing}`.
- `finding/0`'s `{:type_mismatch, ...}` gains the path as its sixth member.
- `inbound_type/4` is redefined as the environment's type at the subject path.
- `check/5`, `valid_targets/4`, `target_verdicts/4` and `validate/3` keep their
  arities and are defined over read signatures at a position.
- `context/0` gains `:datamodel`.
- `compiler.ex`'s `assignability_context/1` threads the `:datamodel` option;
  `structure_finding/1` reads the six-member tuple.
- The existing assignability fixtures get a `subject:` so their
  `consumes`/`produces` declarations keep saying what they said.

### Success criteria

- `mix quality` green, both CI jobs green.
- Every existing assignability test keeps its verdict.
- A palette with no host relation gets the new steps and the old floor.

## Testing Strategy

`test/statifier_blocks/environment_test.exs` for the walk, additions to
`test/statifier_blocks/assignability_test.exs` and
`test/statifier_blocks/assignability/host_relation_test.exs` for the read
check and the reason arm. Every new test that asserts `lib/` behavior is
sabotaged once and the mutation noted above it, per the repo's convention.

## Open questions

None blocking. ADR-0011 decides the record half; the walk's rulings were taken
on 2026-09-06.

## References

- `docs/adr/0011-typed-environment.md` - decisions 1-14 and the worked shape.
- `docs/adr/0003-host-pluggable-assignability.md` - the five superseded
  decisions and the four that stand.
- `statifier_datamodel`'s `ADR-0001` decisions 5 and 8.

## Deferred Manual Verification

### Phase 1

- Nothing. The walk is pure and every property is assertable.

### Phase 2

- The editor's drop check runs with no declarations available, so a host that
  types a read as a shape sees the coverage step skipped there while the
  compiler applies it. Threading the datamodel document into
  `Edit.Targets.slot_verdicts/3` is surface work and belongs with `sb-sy0q`;
  a human decides whether it waits that long. **Still deferred** after the
  unattended pass below: it is a scope call, not a check.

## Acceptance, machine-checked

**Machine-checked (unattended, 2026-09-06):** each criterion on the bead,
run against the tree rather than reasoned about. An agent ran these; none of
them is a human confirmation.

- *A leaf expecting a shape fits where the environment holds a record
  covering it, and is refused with `:shape_not_satisfied` (path named)
  otherwise.* Both halves assert in
  `test/statifier_blocks/environment_test.exs` - "a record covering a shape's
  required set satisfies the read" and "a record that does not cover the
  shape is refused, naming the path and the fields", the second asserting the
  finding tuple verbatim including the path and the
  `{:shape_not_satisfied, ["settled_on"]}` reason. Sabotaged by deleting
  `refused/2`'s `{:missing, names}` clause: red.
- *Every existing assignability test keeps its verdict through the sugar.*
  The full suite is green (2,161 tests, 95.8% coverage). Three groups of test
  edits were required and none of them changes a verdict: the fixture palettes
  gained the `subject:` the sugar desugars against, the `:type_mismatch`
  literals gained the sixth member the record adds, and five assertions moved
  from `:not_assignable` to `{:fixable_by, "blk_AUTH"}` because ADR-0011
  decision 8 removes ADR-0003's index-0 limit by name. Three `inbound_type/4`
  assertions about passthrough moved to `produces/4`, which is where that
  resolution still lives.
- *A palette without a host relation gets the new steps and the old floor.*
  "a palette with no host relation gets the new steps and the old floor",
  plus "the host relation runs last" and "the host is reached only after
  coverage has failed". Sabotaged by asking the host first: red.
- *The walk over a document built only of empty sequences terminates.* "a
  document built only of empty sequences terminates", 2,000 deep under a
  5-second `Task.await`.
- *This package defines no `Compatibility` or `Coverage` module.* "no
  Compatibility or Coverage module of this package's own", plus a grep over
  `lib/` and `test/` finding no such `defmodule`.
- *The record's worked shape.* The entry seed, the assign, the branch whose
  arms agree, and the branch where one arm rewrites the subject are four
  tests, driven by the record's own `scopes` + `types` document as the
  fixture.

Two defects the pass found and fixed, both in the walk rather than in the
tests: a `{:path, opts}` field carrying `expects` was being read as a write
as well as a read, which blanked the very path it was declared to check; and
the environment at a position was being computed by recursing **upward**
through every ancestor, which was correct but quadratic and timed the
termination check out at depth 2,000. It descends now.

One live claim this change falsified was corrected in the same pass:
`README.md`'s data-flow paragraph described the superseded seam.
