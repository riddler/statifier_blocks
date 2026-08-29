---
date: 2026-08-29
issue: sb-zfd
status: draft
---

# Presentation metadata trio and the palette registration API

## Overview

ADR-0002's accepted amendment section B names three palette-entry
declarations - `accent_token`, `badge`, `join_label` - and settles two
things about them that no other record does: `join_label` is code and is
therefore under decision 4's purity rule, and every consumer reads all
three through a total normalizer whose discipline is refuse-never-truncate
(B3). B1 keeps the *contents* of `palette_entry/0` with ADR-0005 decision
10, so this bead adds metadata keys and their normalizers, not callbacks.

The second half is the registration surface a host uses to contribute its
own types: campaign 014 pre-decision D7, an explicit list handed in at
mount, no global registry and no config-time discovery. Bead: sb-zfd.

## Current State Analysis

**One third of the trio already ships.** `ViewModel.accent_token/1`
(view_model.ex) normalizes the `--sb-*` custom-property name and the
graduation work (PR 84) consumes it in `BlockNode` and `PaletteBrowser`.
It landed on the rendering side because its value is interpolated into a
`style` attribute. `badge` and `join_label` have no implementation and no
key in the `palette_entry/0` typespec.

**The normalizer shape to mirror is `BlockType.slot_outcome_key/2`.** It is
total over a non-map entry, a missing key, and a malformed value; it
refuses rather than repairs; it documents the refusal set. `accent_token/1`
has the same shape one module over.

**The typespec is where the key set is fixed.** `BlockType.palette_entry/0`
lists eight optional keys and carries neither `accent_token` (an existing
gap - graduation consumes a key the type does not admit) nor the two new
ones. `ConformanceTest`'s `@entry_keys` is the closed set the core types
are checked against, and it has the same gap.

**Nothing in the behaviour declares a type name.** ADR-0002 decision 1 puts
the string in the document and the mapping in the palette; no core module
exports anything a `[module]`-shaped constructor could derive a name from.
`Palette.new/2` takes the map directly and `core_types/0` is the merge
base a host is told to use in a moduledoc example.

## Desired End State

1. `accent_token`, `badge` and `join_label` are admitted keys of
   `palette_entry/0`.
2. `BlockType.badge/1` and `BlockType.join_label/2` are total normalizers
   implementing B3's row for each, including the raise-degrades case, with
   the 24-character cap as a documented module attribute.
3. `Palette.from_modules/2` is the documented registration entry point: an
   ordered explicit list, an option to sit on top of `core_types/0`.
4. The README carries a worked host example in the credit-card domain, and
   it is executed by a test rather than trusted.

## What We Are NOT Doing

- No new `@callback`. B1 says the trio lives in metadata; the typespec
  appendix's callback table is not amended by this bead.
- No `type_name/0` declaration on the behaviour. Deriving a registration
  name from a module would need one, and that is an ADR-0002 decision 1
  change rather than an implementation choice (open question below).
- No CSS. A badge chip's rule belongs to the concurrent theming bead.
- No ADR edits. The cap number is proposed to decision 10 in the PR body.

## Phases

### Phase 1: the trio as metadata, with normalizers

- Append `accent_token`, `badge`, `join_label` to the `palette_entry/0`
  typespec, plus a `join_label/0` type for the callback value.
- `BlockType.badge/1`: refuse a non-string, an empty or all-whitespace
  string, one carrying a newline, carriage return or tab, and one longer
  than `@presentation_cap` (24 graphemes). Never truncate.
- `BlockType.join_label/2`: refuse a non-function and a function of the
  wrong arity; call a 1-arity function inside a rescue/catch so a raise,
  a throw or an exit degrades to `nil`; apply `badge/1`'s refusal set to
  the return value.
- `nil` from either means the default the caller owns - no chip, and the
  editor's own word.
- Extend `ConformanceTest`'s `@entry_keys` additively.

Gate: full `mix quality`.

### Phase 2: the registration API

- `Palette.from_modules/2`: `[{type_name, module}]` in declaration order,
  later entries winning; `:core` option to start from `core_types/0`;
  `:assignability` passed through to `new/2`. An entry that is not a
  `{binary, atom}` pair raises `ArgumentError` naming it - a mount-time
  programmer error is not a value to degrade.
- Document it as the D7 shape, and say in the moduledoc why the list
  carries names rather than deriving them.

Gate: full `mix quality`.

### Phase 3: the host example

- A `## Registering your own block types` README section defining a
  `myapp.risk_hold` type in the credit-card domain, declaring a badge and
  an accent token, registered beside `Palette.core_types/0`.
- A new test file evaluating that section the way `readme_test.exs`
  evaluates the other two, so the snippet cannot drift.

Gate: full `mix quality`.

## Success Criteria

Automated: full `mix quality` green; one test per B3 refusal row for both
new normalizers including a raising `join_label`; the README section
evaluated and its claims asserted; every new test sabotaged.

Deferred / open questions:

- Where does a registration name come from if a host wants a bare
  `[module]` list? That needs a declaration ADR-0002 decision 1 does not
  give the behaviour. Named, not guessed.

  **Machine-checked (unattended, 2026-08-29):** confirmed that the
  behaviour declares nine `@callback`s and none of them names a type -
  `slots/1`, `config_schema/1`, `validate_config/1`, `current_version/0`,
  `emit/2`, `io/1`, `migrate_config/2`, `fixtures/0`, `palette_entry/0`.
  `Block.type_name/0` is a type, not a declaration a module makes about
  itself. `from_modules/2` therefore takes `{name, module}` pairs, and
  adding a bare-module form is an ADR-0002 change rather than an
  implementation choice. Left open for the operator.

- `accent_token`'s normalizer stays in `ViewModel` while the other two
  land in `BlockType`. The trio therefore reads from two modules; moving
  the existing one is a rename of a function graduation consumes and was
  not in this bead's scope.

  **Machine-checked (unattended, 2026-08-29):** `ViewModel.accent_token/1`
  is still the only definition in `lib/`, and the two graduation call
  sites (`editor/block_node.ex`, `editor/palette_browser.ex`) are
  unchanged and green. `BlockType`'s `palette_entry/0` typedoc names it,
  so a reader arriving at the trio from the behaviour is pointed at it.
  Whether to co-locate all three stays open.

- **The `join_label` arity guard is unobservable from outside.**
  Discovered by the sabotage pass rather than predicted: widening
  `is_function(declared, 1)` to `is_function(declared)`, and dropping the
  guard and the `_refused` arm entirely, both leave every test green,
  because a wrong-arity or non-function call raises and B3's rescue
  degrades that to the same `nil`. The guard is kept as defence in depth -
  B3 says a non-function is refused *without being called* - and the test
  file records the finding above the affected test rather than claiming a
  mutation it cannot make red.

  **Machine-checked (unattended, 2026-08-29):** both mutations run, both
  green, guard kept, note corrected. No code change is warranted; whether
  B3's "refused without being called" wants an observable consequence is
  ADR-0002's question, not this bead's.
