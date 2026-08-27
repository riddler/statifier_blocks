# The core structural block types (ADR-0002 d10) Implementation Plan

## Overview

The `core.*` vocabulary as answers to the `StatifierBlocks.BlockType`
callbacks: seven modules under `StatifierBlocks.Core.*`, plus the registry
function `Palette.core/0` that hands a host the whole set. Bead: `sb-w6d`.

Scope is ADR-0002 decision 10 as amended at acceptance, read together with
ADR-0003 decision 3 (kind tags), ADR-0005 decision 10 (`palette_entry/0`),
and the sui fixture-bundle convention. Out of scope, by ADR: `emit/2` bodies
(ADR-0004, `sb-ort`), the assignability seam itself (ADR-0003, `sb-b3t`), and
palette-aware document validation (`sb-da9`).

This bead builds on `sb-dvj`, whose branch is this branch's base and whose
pull request (#15) is still open. Nothing here modifies a `sb-xti` or
`sb-dvj` module except `lib/statifier_blocks/palette.ex`, which gains the
registry function decision 10 needs and `sb-dvj` deliberately left out.

## Current State Analysis

The base branch `sb-dvj-block-type-behaviour` ships the contract half of
ADR-0002:

| Module | Role |
|---|---|
| `lib/statifier_blocks/block_type.ex` | the nine `@callback`s, five required, and the `slot_decl`/`field_decl`/`finding` types |
| `lib/statifier_blocks/palette.ex` | `%Palette{}`, `new/1`, total `fetch/2`, migrating `resolve/2` |
| `lib/statifier_blocks/{block,document,validation,canonical_json,decode,id}.ex` | ADR-0001's document model, from `sb-xti` |

Baseline `mix quality --profile loop` in this worktree is green at
`e1108bf`.

Constraints that bind every phase:

- **The behaviour's API is sufficient for decision 10.** Every callback
  decision 10 needs exists at the arity it needs, `io/1`'s return is
  `term()` (so ADR-0003's three-key map fits without touching `sb-dvj`'s
  typespecs), and `slot_arity/0`'s four values cover every core slot. The
  stop-and-report condition on a missing behaviour API does **not** fire.
- **ADR-0002 and ADR-0003 do not conflict.** ADR-0002 decision 10's
  `core.on_event` placement paragraph was amended at acceptance to defer to
  ADR-0003, and ADR-0003 decision 3 states the same rule from the other
  side. They agree; there is no special-cased validation rule to write.
- **Coverage floor is 90%** and `test/support/` is excluded from it. Every
  new `lib/` line needs a test in the same phase.
- **`emit/2` is required**, so a core type that did not define it would not
  compile as a `BlockType` under warnings-as-errors. It is stubbed, not
  omitted (see the deferral note below).
- Repo conventions: `@spec` on every public function, errors as events,
  sabotage note above every new test asserting `lib/` behaviour, `mix
  format` run by hand.

### The d9 amendment (PR #13), verified

`fixtures/0` is implemented to the **amended** spelling set: an atom-keyed
map with keys drawn from `scenarios`, `events`, `datasets`, `expressions`.
That amendment (branch `sb-wm8-amend-adr0002-fixtures`) is **not accepted**,
so every `fixtures/0` in this bead carries the same PROVISIONAL admonition
`sb-dvj` used on the callback itself, and the conformance test's bundle-shape
assertion is marked the same way.

Only two core types earn a bundle. An executable example is worth showing in
a palette panel when the entry has something to evaluate: `core.branch` has
arm conditions (`datasets` + `expressions`) and `core.on_event` has an event
payload (`events`). The five purely structural types ship none, which the
convention names as an ordinary absence - statifier-ui's own
`docs/fixture-bundles.md` uses `core.sequence` as its example of a fragment
that ships no examples.

### `emit/2`, deferred

ADR-0004 decision 4 fixes `emit/2` as
`{:ok, Emission.t()} | {:error, [finding()]}`, and neither `Emission` nor
that `finding()` map exists yet - both are `sb-ort`'s. Each core type
therefore returns `{:error, {:not_implemented, block_id}}`: total, pure, an
ordinary error arm rather than a raise, and inside the behaviour's current
`{:error, term()}` spec. `sb-ort` replaces the body and narrows the spec in
the same commit that introduces `Emission`.

## Desired End State

`Palette.core()` returns a palette of seven `core.*` entries; each entry's
module answers every callback ADR-0002 decision 10 assigns it; the ADR-0001
worked example resolves and validates against the real types; and the
`core.on_event` placement rule holds in both directions purely from `io/1`
kind tags, with no special-cased validation rule anywhere in `lib/`.

## Phases

### Phase 1 - the five structural types and the registry

`lib/statifier_blocks/core.ex` (moduledoc-only vocabulary overview),
`lib/statifier_blocks/core/config.ex` (`@moduledoc false` shared validators),
and `core/{sequence,group,wait,resumable_group,on_event}.ex`, plus
`Palette.core/0` and `Palette.core_types/0`.

Success: `mix quality --profile loop` green; each type's `validate_config/1`
findings and `slots/1` covered.

### Phase 2 - the two config-parameterized types

`core/{branch,parallel}.ex`: config-driven slot sets, per-arm `:expression`
fields, `fixtures/0` on `core.branch`.

Success: slot sets follow config; malformed arms/lanes are findings, not
raises; `slots/1` total for config `validate_config/1` rejects.

### Phase 3 - conformance, placement, and the worked example

`test/support/core_fixtures.ex` (the `myapp.*` toy types the worked example
names, and the ADR-0003 d3 admission helper) plus
`test/statifier_blocks/core/{conformance,placement,worked_example}_test.exs`.

Success (the bead's acceptance criteria):

1. every core type passes one shared behaviour conformance test;
2. the ADR-0001 worked example validates against the real types;
3. the placement property holds in both directions - `core.on_event` is
   admitted in an `interrupts` slot and nowhere else, and nothing but an
   interrupt handler is admitted in an `interrupts` slot - checked
   exhaustively over the finite core vocabulary rather than sampled.

### Phase 4 - full gate, changelog fragment

`changelog.d/sb-w6d.md`, full `mix quality`, `/wurk:verify --unattended`.

## Automated Success Criteria

- [x] full `mix quality` green, coverage at or above 90%
- [x] all three acceptance criteria above assert in the suite
- [x] no special-cased `core.on_event` placement rule exists in `lib/`

**Machine-checked (unattended, 2026-08-26):** full `mix quality` green -
format, compile (warnings-as-errors), credo `--strict`, deps, dialyzer, 208
tests, **96.6%** coverage against the 90% floor. The three acceptance
criteria assert in `conformance_test.exs` (63 generated tests, seven types),
`worked_example_test.exs` and `placement_test.exs`. `grep -rn
"interrupt_handler" lib/` returns only `io/1` declarations and prose - no
`validate_config/1` in `lib/` inspects a parent, so the withdrawn
special-cased rule is genuinely absent rather than merely unused. The
sabotage pass ran eleven mutations across every new `lib/` file; ten went
red first try, and the duration-regex one went red once the mutation dropped
the trailing `\z` rather than the leading `\A` (the test note was corrected
to match what was actually verified).

## Deferred Manual Verification

- How the layout hints actually render is `sb-7f2`'s to see; this bead can
  only assert the declarations. Still deferred: no machine check reaches it.

## Open Questions

- `core.on_event`'s `outcome` `:select` option set. ADR-0002 decision 10
  fixes the field's *type* and names no values. `"abandon"` (the worked
  example's value) and `"resume"` are implemented as the minimal pair the
  ADR-0001 decision 10 compile target needs. `sb-ort` may need a third; that
  is a `config_schema` change plus a `type_version` bump, not a document
  schema change.
- `core.group` is named by this bead but by neither ADR-0001 decision 10 nor
  ADR-0002 decision 10. It is implemented as `core.resumable_group` without
  the history mode - the same two slots, the same kind tags - which is the
  only reading that leaves `core.resumable_group`'s own row intact.
