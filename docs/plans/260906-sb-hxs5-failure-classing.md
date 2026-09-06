---
id: sb-hxs5
title: "core.invoke declares and classes error, a failure final is unconditional, and an unhandled failure below the root reaches the root"
date: 2026-09-06
status: implemented
---

# Failure classing across the vocabulary Implementation Plan

## Overview

ADR-0002's amendment of 2026-09-06 (`sb-ii2k`, merged as `757ff3f`) is
implemented in code. `core.invoke` gains the `outcomes/1` it has been
emitting without declaring and a `failure_outcomes/1` classing `error`;
`StatifierBlocks.InvokeStep`'s `use` layer classes `error` for every host
type built on it, overridably; the failure final of `core.invoke`,
`core.map` and `core.subchart` is emitted whether or not the failure slot
is occupied; and the compiler catches an unhandled failure-classed outcome
below the root on the root block's own state, into one shared top-level
final carrying the reserved run-status param. Bead: `sb-hxs5`.

## Current State Analysis

- `lib/statifier_blocks/core/invoke.ex` exports **no** `outcomes/1`, so
  `BlockType.outcomes/2` answers the default `[{"done", "Done"}]` while
  `emit/2` mints an `error` outcome final at `Context.outcome_id(context,
  "error")` (`:242` / `:284`). Its `error_parts/1` (`:270`) answers `nil`
  for an empty `on_error`, and `failure_transition/1`, `error_children/1`
  and `error_final/1` each answer `[]` on that `nil`.
- `lib/statifier_blocks/core/map.ex` has the identical `error_parts/1` /
  `failure_transition/1` / `error_final/1` shape (`:606`-`:630`) and does
  export `outcomes/1` (`:295`) and `failure_outcomes/1` (`:314`).
- `lib/statifier_blocks/core/subchart.ex` builds a `route/4` per declared
  outcome (`:439`); `failure_transition/1` (`:488`) finds the `error`
  route **only when it carries a child**, and `finals/1` (`:516`) filters
  `routed? or child`, so with `on_error` empty and `error` not in the
  author's own list there is no `error` final.
- `lib/statifier_blocks/invoke_step.ex`'s `__using__/1` (`:137`) defines
  `outcomes/1` from `InvokeStep.outcomes/0` and lists it in
  `defoverridable` (`:178`); there is no `failure_outcomes/1`. Its
  `emit/4` (`:410`) already emits the `error` final unconditionally - the
  type declares no slot at all.
- `lib/statifier_blocks/compiler.ex` `completion_finals/3` (`:1345`) and
  `/4` (`:1364`) read **the root block's** outcomes and classes only;
  nothing walks below the root.
- `test/statifier_blocks/compiler/failure_outcome_test.exs` is the
  campaign-033 half. Its `compile_map!/2` occupies `on_error` "on
  purpose", with a closing comment saying the failure final is emitted
  only when the slot holds something - a sentence section 2 supersedes.

## Desired End State

The record's sections 1-4 hold in code, section 5's table is true of the
shipped types, and section 6's five byte-change classes are the only ones:
every corpus document that has no unhandled failure-classed outcome
compiles to the bytes it compiled to at 0.21.0, under all three compile
option sets.

### Key Discoveries

- Under `terminate: true` / `child_use: true` the root's own outcome
  finals already exist; the propagation final is a **sibling** of them,
  minted under the same `child_`/`root_` prefix with the role name
  `failed` (`compiler.ex:245`/`:258`), which collides with no outcome name
  because an outcome named `failed` would mint `child_failed` too - see
  "Open questions".
- `Resolved.slots` (`compiler.ex:288`) carries **every** declared slot,
  including empty ones (`resolve_children/3` folds over `module.slots/1`),
  so "the type declares no such slot, or declares it and the document left
  it empty" is one lookup.
- `Attribution.stamp/3` takes the allowed-id set; the completion
  transitions pass `MapSet.new([root_id])`. A propagation transition
  stamped to the failing block passes that block's own id.
- The corpus goldens in `test/fixtures/corpus/` were captured from this
  branch's base (`origin/main` at `757ff3f`, version 0.21.0) before any
  code change, which is what makes the byte assertion a real one.

## What We're NOT Doing

- Not flipping ADR-0002's amendment to accepted (`sb-ju4d`).
- Not bumping `mix.exs` or `@compiler_version` (`sb-n7sn`, the 0.22.0 prep).
- Not touching `drawer.ex`, the editor, the wire format, the palette, any
  slot arity or any `slot_style`.
- Not changing `core.map`'s `collect` shape: ADR-0009's Note of
  2026-09-06 records that the shipped driver already writes
  `{"index", "status" => "failed", "failure" => %{...}}` and files no
  runtime bead. This bead verifies that reading and records it; it writes
  no code for it, and `statifier_persistence` is outside this campaign's
  footprint for this bead.

## Implementation Approach

Four phases, each independently committable and gate-verifiable.

## Phase 1: The declarations

### Changes Required

- `lib/statifier_blocks/core/invoke.ex`: `outcomes/1` returning
  `[{"done", "Done"}, {"error", "Error"}]` and `failure_outcomes/1`
  returning `["error"]`, each with the moduledoc-grade `@doc` the sibling
  types carry, citing section 1 and section 3.
- `lib/statifier_blocks/invoke_step.ex`: `failure_outcomes/1` in the
  `__using__` quote beside `outcomes/1`, delegating to a new
  `InvokeStep.failure_outcomes/0`, and `failure_outcomes: 1` added to
  `defoverridable`.

### Success Criteria

- `BlockType.outcome_names(Core.Invoke, %{}) == ["done", "error"]`,
  `BlockType.failure_outcomes(Core.Invoke, %{}) == ["error"]`.
- A `use StatifierBlocks.InvokeStep` type classes `error`; one that
  defines `failure_outcomes/1 -> []` classes nothing.
- `mix quality` green.

## Phase 2: The unconditional failure final (section 2)

### Changes Required

- `invoke.ex`: `error_parts/1` always mints the `error` final and carries
  the slot child or `nil`; `failure_transition/1` targets the child when
  there is one and the final directly when there is not;
  `error_children/1` stays empty for `nil`; `error_final/1` always emits.
- `map.ex`: the same three edits, its `chain/2` already handling `nil`.
- `subchart.ex`: `failure_transition/1` finds the `error` route whatever
  it holds and targets `route.target`; `finals/1` also keeps a route whose
  name is failure-classed.
- The three moduledoc paragraphs that state today's conditional behaviour
  are corrected in place, each citing the amendment's section 2.

### Success Criteria

- With `on_error` empty, each of the three emits its `error` final and a
  failure transition targeting it directly; with it occupied every byte is
  the 0.21.0 golden.
- The compiled document still loads in `Statifier.compile/1`.

## Phase 3: The propagation rule (section 4)

### Changes Required

- `lib/statifier_blocks/compiler.ex`: a walk below the root collecting
  `{state_id, outcome}` for every unhandled failure-classed declared
  outcome in document pre-order; when non-empty, one shared final under
  `<prefix>failed` carrying `statifier_persistence:run_status` (and the
  `outcome` param valued `'error'` under `:child_use`), plus one external
  transition per pair on the root block's state, each stamped to the
  failing block.
- Gated on `:child_use` / `:terminate` exactly as the completion finals
  are; empty set emits nothing.

### Success Criteria

- The chunk shape (a `core.sequence` around one `core.invoke` with
  `on_error` empty) compiles a top-level failed final carrying the
  reserved param byte-exact, under both options.
- Provenance is total: the transition resolves to the failing block, the
  final to the root block in its `child_failed` / `root_failed` role.
- The corpus is byte-identical to its 0.21.0 goldens in all three modes.

## Phase 4: The record Note, the fragment and the docs

### Changes Required

- `docs/adr/0004-compiler-provenance.md`: a dated Note recording the root
  shape the propagation adds and its attribution, by addition, zero
  removed lines (the `sb-napt` precedent).
- `changelog.d/` fragment naming the bytes change for 0.22.0 (MINOR).
- Any shipped doc that lists `core.invoke`'s outcomes.

### Success Criteria

- `git diff origin/main -- docs/adr/` shows zero removed lines.
- The fragment exists and names the five byte-change classes.

## Testing Strategy

### Unit Tests

- `test/statifier_blocks/compiler/failure_outcome_test.exs` gains the
  `core.invoke` declaration asserts, the empty-slot cases for all three
  types, the propagation asserts (bytes, provenance, engine load) and the
  `InvokeStep` default/override asserts.
- A new corpus test asserts each golden byte for byte.

### Manual Testing Steps

None: this bead ships no rendered surface.

## Verification (unattended pass, 2026-09-06)

The plan artifact carried no Deferred Manual Verification backlog, so the
pass machine-checked each of the bead's acceptance criteria against the
built artefact. Every one is **checked**; nothing is deferred to a human,
because this bead ships no rendered surface.

| Criterion | Evidence |
|---|---|
| `core.invoke`'s `outcomes/1` and `failure_outcomes/1` exist and resolve through `BlockType` | `failure_outcome_test.exs` "core.invoke declares the pair it has always emitted, and classes error" - `BlockType.outcomes/2`, `outcome_names/2` and `failure_outcomes/2` all asserted |
| A host `InvokeStep` type classes `error` unless it overrides | `invoke_step_test.exs` "error is failure-classed by default, and a host may override it" (`Receipt`, `Authorize`, and `Probe` overriding with `[]`) plus "the class is in the overridable list beside the outcomes" |
| The chunk shape compiles a top-level failure-classed final carrying the reserved donedata param byte-exact | `failure_outcome_test.exs` "under terminate, one catch transition and one shared failed final" and "under child_use, the outcome param says error"; the key and value are spelled out rather than read off this package's attribute |
| Every corpus document without an unhandled failure compiles unchanged from 0.21.0 | `byte_corpus_test.exs`, 15 goldens (five documents x three compile modes) captured from `origin/main` at `757ff3f` before any code change |
| The map/subchart empty-`on_error` case ends the block on `error` and propagates | "each of the three emits it, and routes the failure straight into it" and "a nested core.map and core.subchart with an empty on_error reach the root too" |
| Provenance owns the new spans | "the transition belongs to the failing block, the final to the root" - `Provenance.owner_at/2` over the transition's own offset and `owner_of_state/2` over the shared final |
| Fragment present | `changelog.d/sb-hxs5.md`, `Added` + `Changed`, naming the bytes change |
| The ADR-0004 dated Note | `git diff --numstat origin/main -- docs/adr/` reports `68 0` - zero removed lines |
| The compiled charts load in the engine | `Statifier.compile/1` asserted on every emitted shape, and the run itself in "a failed call ends the run in the failed final, carrying the reserved key" |

Sixteen sabotages were applied and reverted from a copy, one per
`(verified)` comment this bead added or rewrote; each took the named test
file red and none was left in place.

`core.map`'s `collect` entry for a failed child (ADR-0009's Note of
2026-09-06) was verified by reading `statifier_persistence`'s
`lib/statifier_persistence/driver.ex:1155-1172`: `outcome_entry/2` writes
`%{"index" => index, "status" => "failed", "failure" => failure_data(failure)}`
with `failure_data/1`'s `"reason"` / `"attempts"` / `"detail"`, beside
`"completed"` + `"donedata"` and `"cancelled"`. The shipped handler is
right, so no runtime change and no bead follow from it, exactly as that
Note records. No file in that repository was written.

## Open questions

1. An author-declared root outcome literally named `failed` would mint the
   same `<prefix>failed` id the propagation final is minted under. The
   record fixes that role name and does not name the collision, so it is
   implemented as written and the collision is reported to the conductor
   rather than resolved here: inventing a fallback role would be a new
   record decision taken in code.

## References

- `docs/adr/0002-block-type-behaviour.md:4325` onward - the amendment.
- `docs/adr/0009-fan-out-block-type.md` - the 2026-09-06 `collect` Note.
- `docs/adr/0004-compiler-provenance.md` - the root shape and decision 5.
