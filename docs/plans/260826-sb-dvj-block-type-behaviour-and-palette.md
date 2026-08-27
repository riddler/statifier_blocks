# Block-type behaviour and palette (ADR-0002 d1-d9) Implementation Plan

## Overview

Layer-1 implementation of accepted ADR-0002, contract half: the
`StatifierBlocks.BlockType` behaviour (nine callbacks, five required) and
`%StatifierBlocks.Palette{}` as a caller-supplied value with a total
`fetch/2` and a migrating `resolve/2`. Bead: `sb-dvj`.

Scope is ADR-0002 decisions 1 through 9, with decision 9 implemented to the
**amended** spelling set (PR #13, branch `sb-wm8-amend-adr0002-fixtures`,
not yet accepted). Decision 10 - the `core.*` vocabulary - is explicitly out
of scope and belongs to `sb-w6d`.

This bead builds on `sb-xti` (ADR-0001), whose branch is this branch's base.
`sb-xti`'s pull request is still open; nothing here modifies any file it
owns.

## Current State Analysis

The base branch `sb-xti-block-document-model` (HEAD `aeb24ad`) ships the
whole ADR-0001 document model:

| Module | Role |
|---|---|
| `lib/statifier_blocks/block.ex` | the `%Block{}` struct and the `json`, `id`, `type_name`, `slot_name`, `config`, `t` types |
| `lib/statifier_blocks/document.ex` | `%Document{}`, `new/2`, `blocks/1`, `fetch_path/2`, `validate/1`, `to_json/1`, `content_hash/1`, `from_json/1` |
| `lib/statifier_blocks/validation.ex` | `@moduledoc false`; ADR-0001's ordered structural check |
| `lib/statifier_blocks/canonical_json.ex` | `@moduledoc false`; the deterministic encoder |
| `lib/statifier_blocks/decode.ex` | `@moduledoc false`; the registry-free decoder |
| `lib/statifier_blocks/id.ex` | `blk_` / `bdoc_` id minting |

Baseline `mix quality` (full) in this worktree is **green**: format, compile
(warnings-as-errors), credo `--strict`, deps audit, dialyzer, 73 tests,
**94.2% coverage** against the fleet's 90% floor.

Key constraints discovered:

- **Every type ADR-0002's typespec block references already exists on the
  base branch.** `Block.slot_name/0`, `Block.config/0`, `Block.json/0`,
  `Block.type_name/0`, `Block.id/0` and `Block.t/0` are all defined at
  `lib/statifier_blocks/block.ex:13-38`. Nothing in ADR-0002 needs a change
  to a module `sb-xti` owns, so the stop-and-report condition on that does
  **not** fire.
- **Coverage headroom is 4.2 points.** `Palette` is small but real; a
  `resolve/2` clause left untested is enough to move the number. Every new
  `lib/` line must be reached by a test in the same phase that adds it.
- **Phase 1 has no coverage or warnings trap - verified, not assumed.** A
  throwaway `block_type.ex` carrying only the nine `@callback`s, the five
  `@type`s and `@optional_callbacks`, plus a `test/support/` module
  implementing only the five required callbacks, was written into this
  worktree and put through full `mix quality`: format, compile
  (warnings-as-errors), credo `--strict`, deps, dialyzer all green, tests
  **still 94.2%**. A behaviour module contributes zero relevant lines to
  excoveralls, and a behaviour implementer that omits the four optional
  callbacks compiles with no warning. Both scratch files were deleted; the
  only untracked file left is this plan.
- **`test/support/` is already wired.** `mix.exs:37` compiles it in `:test`
  and `coveralls.json` skips it for coverage, and
  `test/support/document_fixtures.ex` is the pattern to follow for the
  test-only block types. Do not invent a different mechanism.
- **Repo conventions that bind every phase** (`CLAUDE.md`): errors are
  events (`{:ok, v} | {:error, e}`, never rescue-to-default at a leaf);
  `@spec` on every public function; every new test asserting `lib/`
  behaviour is sabotage-verified and carries a one-line mutation note
  directly above it; `mix format` is run by hand because the gate's format
  stage is check-only.
- **The gate is never enlarged.** `.quality.exs` records that this package's
  gate is deliberately smaller than statifier-ex's. Decision 4's purity
  contract is therefore documented and enforced by convention - no new credo
  check, no custom stage.
- **Changelog fragments** (`changelog.d/README.md`): one file per bead,
  `changelog.d/sb-dvj.md`, standard Keep a Changelog headings, no nested
  bullets. Public API additions only.

### The d9 amendment, verified

The amendment on `sb-wm8-amend-adr0002-fixtures` was diffed against this
branch's copy of `docs/adr/0002-block-type-behaviour.md`. It touches exactly
three things:

1. the status line (`Status: accepted (2026-08-26); decision 9 amended
   (2026-08-26)`),
2. decision 9, which gains sub-sections **9a** (the four spellings), **9b**
   (addressed by block type name), and **9c** (per-entry discovery),
3. the final Consequences bullet, marked discharged.

**It conflicts with nothing outside decision 9.** The prior check was
correct and this plan confirms it rather than assuming it. The
stop-and-report condition on an out-of-scope conflict does not fire.

The amendment's premise also holds: sui-13q landed, and
`/Users/johnnyt/Dev/github/statifier/statifier-ui/docs/fixture-bundles.md`
exists on statifier-ui's default branch (commit `2317ea7`, "Adds
per-fragment fixture bundles and loader").

## Desired End State

Two new public modules, specced, documented, dialyzer-clean and tested:

| Function / callback surface | Contract |
|---|---|
| `StatifierBlocks.BlockType` | behaviour, nine `@callback`s, `@optional_callbacks io: 1, migrate_config: 2, fixtures: 0, palette_entry: 0` |
| `BlockType.slot_arity/0`, `slot_decl/0`, `field_type/0`, `field_decl/0`, `finding/0` | the declaration vocabulary of decisions 6 and 7 |
| `Palette.new/1` | builds the value from a `%{type_name => module}` map |
| `Palette.fetch/2` | `{:ok, module}` or `{:error, {:unknown_block_type, name}}`; total, never raises |
| `Palette.resolve/2` | `{:ok, module, block}` with config migrated **in memory only**, plus the typed error arms |

Verification that the end state is reached:

1. A test-only block type in `test/support/` implements **all nine**
   callbacks and every one of them is called by a test.
2. A second test-only block type implements **only the five required** ones,
   and `function_exported?/3` confirms each of the four optional ones is
   absent - the "degrades cleanly" property decision 5 asserts.
3. A block stored at `type_version: 1` against a module whose
   `current_version/0` is `2` resolves with migrated config, and the
   `%Document{}` it came from is unchanged.
4. A block stored at a `type_version` **above** `current_version/0` returns
   `{:error, {:block_type_too_new, id, version}}`.
5. `Palette.fetch/2` returns a value for every input, including a name no
   entry carries, and raises for none.
6. Full `mix quality` is green at the end of every phase.

### Key Discoveries:

- ADR-0002's "The contract as typespecs" section (lines 318-409 of
  `docs/adr/0002-block-type-behaviour.md`) is a near-literal implementation
  target. Transcribe it; do not paraphrase it.
- ADR-0002's worked example (`MyApp.Blocks.Score`, lines 420-528) is the
  shape of the test-only block type: config-parameterized slots, a
  cross-field rule that lives only in `validate_config/1`, and a v1 -> v2
  config-key rename. Model the toy on it rather than inventing a new toy.
- `Palette.resolve/2`'s declared `@spec` (lines 405-408) enumerates only two
  error arms, but `migrate_config/2`'s own declared spec (line 375) can
  return `{:error, term()}`. See Open Question 1.
- The ADR's usage example (line 535) calls `StatifierBlocks.Palette.core()`.
  **That function is `sb-w6d`'s, not this bead's**, and this plan does not
  define it. Tests build palettes from `Palette.new/1` over a map naming only
  the test-only types.
- `lib/statifier_blocks/validation.ex:8-10` states the registry-free rule for
  ADR-0001 validation explicitly. Nothing in this bead may make
  `Document.validate/1` palette-aware. See Open Question 3.
- The four spellings in amendment 9a include `%StatifierUI.Fixtures{}`, a
  struct this package cannot construct because it must not depend on
  `statifier_ui`. See Open Question 4.
- **st-ADR-0018 bans bead IDs and pull-request numbers in `lib/` comments and
  docs**, and permits ADR numbers precisely because they stay resolvable
  (`statifier-ex/docs/adr/0018-no-process-jargon-in-code-comments.md:99-103`;
  `:146-151` exempts `docs/adr/` and `docs/plans/` files themselves, which is
  why ADR-0002's own sketch may cite beads and why this plan document may).
  **That record binds statifier-ex, not this repo**: this repo's `CLAUDE.md`
  "Conventions" section is a short enumerated list that does not include it,
  so it is a practice this plan *adopts*, not a rule already inherited.
  This plan adopts it because ADR-0002's bead citations have **already
  drifted** - `sb-7rx` -> `sb-b3t`, `sb-iwz` -> `sb-ort`, `sb-w50` ->
  `sb-ia5` (verified against `bd show`) - so a literal transcription would
  ship stale pointers in hexdocs on day one. **Every `@doc` in this bead
  cites the ADR number, not the bead.** See Open Question 7.
- **There is no shipped PROVISIONAL marker in any `lib/` module in the
  family** - the only occurrences are inside `docs/adr/0002`'s own code
  sketches (`:378`, `:508`), spelled `PROVISIONAL - <pointer>`. The one
  admonition mechanic the family ships is predicator-ex's
  `> #### Sentence-case title {: .info}` blockquote
  (`predicator-ex/lib/predicator/context_location.ex:175`,
  `lib/predicator.ex:1234`, `lib/predicator/evaluator.ex:1396`). This bead
  sets the `lib/` pattern by combining the two.

## What We're NOT Doing

- **Decision 10, the `core.*` vocabulary.** No `core.sequence`,
  `core.branch`, `core.parallel`, `core.wait`, `core.resumable_group`, or
  `core.on_event` module, and **no `Palette.core/0`**. That is `sb-w6d`.
- **`io/1`'s return shape, type expressions, or the compatibility
  relation.** ADR-0003 / `sb-b3t`. The behaviour declares
  `@callback io(Block.config()) :: term()` and the `@doc` says whose shape it
  is. The looseness is decision 11's explicit intent.
- **`emit/2`'s real signature, the emit context, SCXML, state-id generation,
  or the provenance map.** ADR-0004 / `sb-ort`. The behaviour declares the
  stub with `context :: term()` and `{:ok, term()} | {:error, term()}`, and
  nothing in this bead calls it in anger - the test-only type's `emit/2`
  returns a marker tuple so the callback is exercised without asserting a
  contract this bead does not own.
- **`palette_entry/0`'s contents, form rendering, findings presentation, or
  the unresolvable-block presentation.** ADR-0005 / `sb-ia5`. The behaviour
  declares `@callback palette_entry() :: map()` per the ADR's own typespec
  and says nothing about its keys.
- **Palette-aware document validation.** Neither slot-arity checking, nor the
  `:undeclared_slot` finding decision 6 names, nor a walk that resolves every
  block in a document. This bead supplies the vocabulary those rules will be
  written against; no bead in the scope brief owns the checker. Recorded as
  Open Question 3.
- **A `statifier_ui` dependency.** Amendment 9's closing paragraph is
  explicit: nothing here calls the loader and this package does not gain that
  dependency. `fixtures/0` stays `:: term()` and the amendment lands as
  documentation plus test coverage.
- **Any registry, `Application` env lookup, named ETS table, process, or
  boot-time hook.** Decision 2 forbids all of them. `Palette` is a struct and
  two pure functions.
- **Amending `docs/adr/`.** PR #13 is another worker's, and an ADR
  contradiction discovered here is reported, never patched in place.
- **Touching any module `sb-xti` owns.** `block.ex`, `document.ex`,
  `validation.ex`, `canonical_json.ex`, `decode.ex`, `id.ex` and their tests
  are untouched by every phase.

## Implementation Approach

Three phases, split on the ADR's own decision boundaries so each is
independently committable and leaves a full-gate-green tree with real tests
covering the code it adds:

1. **The contract** (d1, d4, d5, d6, d7, d9) - the behaviour module, its
   declaration types, and the test-only block types that prove every callback
   is implementable from arguments alone.
2. **Resolution** (d2, d3) - the `Palette` value and the total `fetch/2`.
3. **Migration** (d8) - `resolve/2`, in-memory migration, and
   `:block_type_too_new`.

The ordering matters: phase 1's test-only block types are what phases 2 and 3
build palettes out of, and phase 3's migration needs phase 2's resolution to
exist. Phases 2 and 3 are split rather than combined because `fetch/2` and
`resolve/2` answer two different decisions with two different failure
vocabularies, and each is separately gate-verifiable - phase 2 lands `fetch/2`
plus its unknown-type arm with tests that pass on their own.

Module layout:

```
lib/statifier_blocks/block_type.ex        # Phase 1 (public, behaviour only)
lib/statifier_blocks/palette.ex           # Phases 2-3 (public struct + API)
test/support/block_type_fixtures.ex       # Phase 1 (toy types; coverage-skipped)
test/statifier_blocks/block_type_test.exs # Phase 1
test/statifier_blocks/palette_test.exs    # Phases 2-3
changelog.d/sb-dvj.md                     # Phases 1-3 (appended)
```

`BlockType` carries no executable code at all - it is `@type`, `@callback`,
`@doc` and `@optional_callbacks`. That is deliberate: a behaviour that ships
helper functions invites a consumer to depend on the helper instead of the
contract, and `sb-b3t`, `sb-ort` and `sb-ia5` each need to add to this module
without inheriting a stale helper.

### Decision 4's purity contract, and how it is "enforced"

Decision 4 says every callback is a pure function of its arguments. This plan
enforces it exactly as the ADR says - **by convention, stated in the
moduledoc** - and adds no gate stage. The moduledoc names what is forbidden
(process dictionary, `Application.get_env/2`, IO, database, clock,
randomness), states the consequence (validation runs on every edit;
`sb-ort` promises a deterministic compile against a document hash), and names
the escape hatch the ADR gives: a type needing external data gets it from the
host resolving it before the operation, not from the callback reaching for it.

The test-only block types are the demonstration: neither reaches outside its
arguments, and that is the acceptance property ADR-0002's "What this example
is chosen to demonstrate" section names first.

---

## Phase 1: The `BlockType` behaviour and the test-only block types

### Overview

Transcribe ADR-0002's typespec block into a real behaviour module, and prove
with two test-only block types that all nine callbacks are implementable from
arguments alone and that the four optional ones genuinely degrade.

### Changes Required:

#### 1. The behaviour

**File**: `lib/statifier_blocks/block_type.ex` (new, public)
**Changes**: The module exactly as ADR-0002 lines 318-385 declare it - every
`@type`, `@typedoc`, `@callback`, and the `@optional_callbacks` line -
transcribed without alteration.

```elixir
defmodule StatifierBlocks.BlockType do
  @moduledoc """
  The authoring-time extension seam. A host implements this behaviour once
  per palette entry; the only types this package will ship itself are the
  `core.*` structural vocabulary, which lands in a later record (ADR-0002
  decision 10) and is not present yet.

  Every callback is a pure function of its arguments (ADR-0002 decision 4).
  """

  alias StatifierBlocks.Block

  @type slot_arity :: :any | :at_least_one | :exactly_one | :zero_or_one

  @typedoc "Name, arity, human label. Order is presentation order."
  @type slot_decl :: {Block.slot_name(), slot_arity(), String.t()}

  @type field_type ::
          :string
          | :integer
          | :boolean
          | {:select, [{value :: String.t(), label :: String.t()}]}
          | :expression
          | :duration
          | {:list, field_type()}

  @type field_decl :: %{
          key: String.t(),
          type: field_type(),
          label: String.t(),
          required?: boolean(),
          default: Block.json()
        }

  @typedoc "Names the offending config key; message is author-facing."
  @type finding :: {key :: String.t(), message :: String.t()}

  # ... the nine @callbacks, then:
  @optional_callbacks io: 1, migrate_config: 2, fixtures: 0, palette_entry: 0
end
```

The moduledoc is expanded past the ADR's four lines with: decision 4's purity
contract in full (see "Implementation Approach"); the required/optional split
and what each optional absence degrades to; and a "who owns what" table
mirroring decision 5's, naming **ADR-0003** for `io/1`, **ADR-0004** for
`emit/2` and **ADR-0005** for `palette_entry/0`.

Per-callback `@doc`s follow the ADR's own one-liners, each extended with the
owning **record** where the shape is not this record's. The ADR's sketch names
beads there (`"Return shape is sb-7rx's"`); this implementation names the ADR
instead, per st-ADR-0018 and Open Question 7:

- `slots/1` - decision 6 in full: the four arity values and their meanings,
  that declared slots are the complete set (`:undeclared_slot` is a finding a
  later bead raises, not something this module checks), and the stability
  rule - for any config `validate_config/1` accepts, `slots/1` returns
  without raising.
- `config_schema/1` - decision 7: the seven closed field types, that it takes
  config because a branch gains a condition field per arm, and that it is a
  rendering hint and **not** the authority.
- `validate_config/1` - decision 7: this is the authority; findings name a
  config key and carry author-facing text.
- `current_version/0` and `migrate_config/2` - decision 8: migration runs at
  resolution time, is applied in memory, and is **never** written back by this
  package.
- `emit/2` - `context` and the return term are ADR-0004's; this record fixes
  only that the callback lives here and is pure.
- `io/1` - the return shape is ADR-0003's; absent means assignability treats
  the block as unconstrained.
- `palette_entry/0` - contents are ADR-0005's; absent means the editor falls
  back to the type name.
- `fixtures/0` - decision 9 as amended; see below.

#### 2. `fixtures/0`'s doc, marked provisional

**File**: `lib/statifier_blocks/block_type.ex`
**Changes**: `fixtures/0`'s `@doc` documents the **amended** spelling set -
the four spellings of statifier-ui's fixture-bundle convention, addressed by
block type name, discovered per entry - and carries a provisional marker
because the amendment is not yet accepted.

The marker combines the two things the family already has: ADR-0002 decision
9's own `PROVISIONAL - <pointer>` spelling, and predicator-ex's admonition
mechanics (`> #### Sentence-case title {: .info}`, blank `>` line, prose in
the blockquote). `{: .warning}` rather than `{: .info}` because the reader is
being told not to rely on this yet. **The pointer is the ADR number and its
decision number - never the bead, never the pull request** (st-ADR-0018,
Open Question 7).

```elixir
@doc """
Executable examples for this palette entry.

> #### Provisional: the accepted spellings are not settled {: .warning}
>
> PROVISIONAL - see ADR-0002 decision 9. The spellings below come from an
> amendment to that decision which has not been accepted. Until it is,
> treat this list as the intended target rather than a settled contract.
> The callback itself, and its `term()` return, are settled either way.

The return value is one of the four spellings statifier-ui's
`docs/fixture-bundles.md` defines, and that page is the authority:

  * `%StatifierUI.Fixtures{}` - the struct
  * `%{scenarios: ..., events: ..., datasets: ..., expressions: ...}` -
    **atom** top-level keys, the Elixir spelling written by hand
  * `%{"version" => 1, "datasets" => ...}` - **string** top-level keys, the
    JSON spelling that survives a file
  * `"palette/score.fixtures.json"` - a binary path

The bundle is addressed by the `type_name` the palette resolves it under,
and discovery is per entry: one malformed bundle is reported against its own
entry and every other entry still loads.

The spec stays `term()` deliberately. statifier-ui names no single type for
the union of these four spellings, and this package must not assert a type it
does not own. Nothing here calls the loader, and `statifier_ui` is **not** a
dependency of this package: a host that wants palette-entry test panels
depends on it itself.
"""
@callback fixtures() :: term()
```

The exact admonition syntax is set by the family's existing pattern - match
what `statifier-ex` and `statifier-ui` already do rather than inventing a
form. Nothing else in this module or in this plan is marked provisional.

#### 3. The test-only block types

**File**: `test/support/block_type_fixtures.ex` (new)
**Changes**: Two behaviour modules plus a palette helper, following
`test/support/document_fixtures.ex`'s shape (`@moduledoc` explaining what the
fixture is for, `@spec` on the helper).

`StatifierBlocks.BlockTypeFixtures.Toy` - implements **all nine** callbacks,
modelled on ADR-0002's `MyApp.Blocks.Score`:

```elixir
@behaviour StatifierBlocks.BlockType

@impl true
def current_version, do: 2

# Config-parameterized (ADR-0001 decision 5): the review slot exists only
# when the author asked for one.
@impl true
def slots(%{"review_below" => floor}) when is_integer(floor),
  do: [{"review", :at_least_one, "If the score is below the floor"}]

def slots(_config), do: []

@impl true
def config_schema(config), do: [...] ++ review_fields(config)

# The authority (decision 7). The 0..100 bound and the identifier rule live
# here and nowhere else.
@impl true
def validate_config(config), do: ...

@impl true
def io(_config), do: %{consumes: ["record"], produces: ["score"]}

# sb-ort owns the real shape; a marker tuple exercises the callback without
# asserting a contract this bead does not own.
@impl true
def emit(%StatifierBlocks.Block{id: id}, context), do: {:ok, {:emitted, id, context}}

# v1 spelled the target key `field`; v2 spells it `assign_to`.
@impl true
def migrate_config(1, config) do
  {value, rest} = Map.pop(config, "field", "score")
  {:ok, Map.put(rest, "assign_to", value)}
end

def migrate_config(from, _config), do: {:error, {:no_migration_from, from}}

@impl true
def fixtures, do: %{datasets: %{...}, expressions: %{...}}   # atom-keyed

@impl true
def palette_entry, do: %{label: "Score record", group: "Enrichment"}
```

`StatifierBlocks.BlockTypeFixtures.Minimal` - implements **only** `slots/1`,
`config_schema/1`, `validate_config/1`, `current_version/0` and `emit/2`, and
nothing else. It exists to prove the optional four are genuinely optional:
the module must compile with no warning under warnings-as-errors, and
`function_exported?/3` must report each of the four absent.

Two more one-line types for the fixture-spelling coverage, since the four
spellings cannot all come from one module:
`StringKeyedFixtures` returning `%{"version" => 1, "datasets" => %{}}` and
`PathFixtures` returning `"palette/toy.fixtures.json"`. The struct spelling is
not constructible here - see Open Question 4.

A `palette/0` helper returns `Palette.new(...)`-equivalent data. **In phase 1
`Palette` does not exist yet**, so phase 1's helper returns the plain
`%{type_name => module}` map and phase 2 adds the `Palette`-returning helper
beside it. This is called out because it is the one place the phase split
shows in the fixture file.

#### 4. Changelog fragment

**File**: `changelog.d/sb-dvj.md` (new)
**Changes**: Open the `### Added` section with the behaviour line. Phases 2
and 3 append to the same file.

### Success Criteria:

#### Automated Verification:
- [x] Full gate green: `mix quality`
- [x] `lib/statifier_blocks/block_type.ex` and
      `test/support/block_type_fixtures.ex` exist
- [x] A test asserts
      `StatifierBlocks.BlockType.behaviour_info(:callbacks)` contains exactly
      the nine `{name, arity}` pairs, and
      `behaviour_info(:optional_callbacks)` contains exactly
      `io: 1, migrate_config: 2, fixtures: 0, palette_entry: 0`
- [x] A test calls **every one of the nine callbacks** on
      `BlockTypeFixtures.Toy` and asserts on each return value:
      `slots/1` for both the review and no-review config, `config_schema/1`
      for both, `validate_config/1` for `:ok` and for a findings list,
      `current_version/0`, `emit/2`, `io/1`, `migrate_config/2` for both its
      clauses, `fixtures/0`, `palette_entry/0`
- [x] A test asserts `function_exported?(BlockTypeFixtures.Minimal, :io, 1)`
      and the three other optional callbacks are all `false`, while all five
      required ones are `true` (with `Code.ensure_loaded!/1` first, so the
      assertion cannot pass vacuously against an unloaded module)
- [x] A test asserts every `slot_decl` the Toy returns has an arity drawn
      from the closed set `[:any, :at_least_one, :exactly_one,
      :zero_or_one]`, and every `field_decl` a type drawn from the seven
      closed field types (a recursive check, so `{:list, :string}` passes and
      `{:list, {:map, ...}}` would not)
- [x] A test asserts the stability rule of decision 6: for each config the
      Toy's `validate_config/1` returns `:ok` for, `slots/1` returns a list
      and does not raise
- [x] A test asserts each of the three constructible `fixtures/0` spellings
      is recognized: the Toy's atom-keyed map has only atom top-level keys,
      `StringKeyedFixtures`' map only binary top-level keys, and
      `PathFixtures`' return is a binary - and that no bundle mixes atom and
      string top-level keys (amendment 9a's `:mixed_bundle_keys` discriminator)
- [x] Dialyzer is green with the behaviour in place, which is the bead's
      "dialyzer-clean typespecs" criterion - it is part of full `mix quality`
      and is listed separately here because it is the criterion the bead names
- [x] `grep -rn "statifier_ui" mix.exs mix.lock lib/` returns nothing - the
      amendment's no-dependency rule, machine-checked
- [x] `grep -rnE "Application\.(get|fetch)_env|System\.get_env|Process\.(get|put)|:rand\.|:crypto\.|DateTime\.|NaiveDateTime\.|System\.(os_time|monotonic_time)|IO\.|File\.|:ets\.|GenServer|Agent\.|:persistent_term"
      lib/statifier_blocks/block_type.ex test/support/block_type_fixtures.ex`
      returns nothing. This is a **partial** machine check on decision 4's
      most common violations, not an enforcement of it - decision 4 is
      enforced by convention (see "Implementation Approach"), and the gate is
      never enlarged to cover it. The list is kept in sync with decision 4's
      own enumeration: process dictionary, `Application.get_env/2`, IO,
      database, clock, randomness
- [x] `grep -rnE "\bs(b|t|ui|p|ob)-[a-z0-9]{3,4}\b|PR #[0-9]" lib/` returns
      nothing - st-ADR-0018's ban on bead IDs and pull-request numbers in
      `lib/`, machine-checked (Open Question 7)

#### Manual Verification:
- [ ] Every new test carries its one-line sabotage mutation note, and the
      mutation described actually turns that test red (no command checks
      this - `mix quality` cannot see a comment)
- [ ] The `@type` and `@callback` definitions are a character-faithful
      transcription of ADR-0002 lines 318-385, with no callback added,
      dropped, renamed, or re-arity'd, and no type widened or narrowed. Two
      departures are deliberate and are **not** transcription errors: `@doc`
      prose cites ADR numbers where the sketch cited bead IDs (Open Question
      7), and the moduledoc's `core.*` sentence is reworded to future tense
      because decision 10 has not landed (Open Question 8). There should be
      no third departure
- [ ] The `fixtures/0` provisional marker reads as the family's own idiom:
      ADR-0002 decision 9's `PROVISIONAL - <pointer>` spelling inside
      predicator-ex's admonition shape, sentence-case title, blank `>` line
- [ ] The per-callback `@doc`s name the correct owning **record** for each of
      the four shapes this record does not own: ADR-0003 for `io/1`,
      ADR-0004 for `emit/2`, ADR-0005 for `palette_entry/0`, and ADR-0002
      decision 9 plus statifier-ui's `docs/fixture-bundles.md` for
      `fixtures/0`

**Implementation Note**: Use `mix quality --profile loop` between edits; run
full `mix quality` as the phase gate. In interactive execution pause here for
the human; in `--loop` execution the Automated Verification block gates
advancement and the Manual items defer to `/wurk:verify`.

---

## Phase 2: The palette as a value, and total resolution

### Overview

Implement decisions 2 and 3: `%StatifierBlocks.Palette{}` as a caller-supplied
value with no global state anywhere, and `fetch/2` as a total lookup with one
typed error arm.

### Changes Required:

#### 1. The struct and `fetch/2`

**File**: `lib/statifier_blocks/palette.ex` (new, public)
**Changes**: The struct and type exactly as ADR-0002 lines 387-399 declare
them, plus `new/1` and `fetch/2`.

```elixir
defmodule StatifierBlocks.Palette do
  @moduledoc """
  A caller-supplied value, never global state (ADR-0002 decision 2).
  """

  alias StatifierBlocks.Block

  @type t :: %__MODULE__{types: %{optional(Block.type_name()) => module()}}

  defstruct types: %{}

  @spec new(%{optional(Block.type_name()) => module()}) :: t()
  def new(types \\ %{}) when is_map(types), do: %__MODULE__{types: types}

  @doc "Total; never raises (ADR-0002 decision 3)."
  @spec fetch(t(), Block.type_name()) ::
          {:ok, module()}
          | {:error, {:unknown_block_type, Block.type_name()}}
  def fetch(%__MODULE__{types: types}, type_name) do
    case Map.fetch(types, type_name) do
      {:ok, module} -> {:ok, module}
      :error -> {:error, {:unknown_block_type, type_name}}
    end
  end
end
```

The moduledoc carries decision 2 in full: what a palette is, that it is
passed explicitly into validation, the editor's session state and the
compiler, and the four things it is **not** - no `Application` env lookup, no
named ETS table, no process registry, no boot-time registration. It also
carries decision 2's cadence paragraph: a palette is fixed for an editing or
compiling operation, not for a session, and nothing in this package holds one
across operations. And it carries decision 3's consumer discipline: every
consumer that walks a document carries the unresolvable case as an ordinary
arm.

`new/1` is a convenience the ADR's typespec block does not list - see Open
Question 2. `Map.fetch/2` rather than a `Map.get/3` sentinel, so a palette
that genuinely maps a name to `nil` is still distinguishable from an absent
name.

#### 2. Fixture helper

**File**: `test/support/block_type_fixtures.ex`
**Changes**: Add `palette/0` returning
`Palette.new(%{"toy.score" => Toy, "toy.minimal" => Minimal, ...})`.

#### 3. Changelog fragment

**File**: `changelog.d/sb-dvj.md`
**Changes**: Append the palette and `fetch/2` lines.

### Success Criteria:

#### Automated Verification:
- [ ] Full gate green: `mix quality`
- [ ] `fetch/2` returns `{:ok, Toy}` for a name the palette carries
- [ ] `fetch/2` returns `{:error, {:unknown_block_type, "myapp.retired"}}`
      for a name it does not, with the offending name carried in the tuple
- [ ] `fetch/2` returns a value and raises for none over a table of hostile
      type names (the empty string, a binary that is not valid UTF-8, a very
      long binary), and over an empty palette
- [ ] `new/0` and `new/1` produce `%Palette{types: %{}}` and
      `%Palette{types: given}` respectively
- [ ] `grep -rn "Application.get_env\|:ets\.\|Process.whereis\|GenServer\|Agent\|:persistent_term"
      lib/statifier_blocks/palette.ex` returns nothing - decision 2's
      no-global-state rule, machine-checked
- [ ] Two palettes built in the same test with different modules under the
      same type name both resolve to their own module - the multi-tenant
      property decision 2 names, which a global registry would break

#### Manual Verification:
- [ ] Every new test carries its sabotage mutation note, verified by hand
- [ ] The struct and `t/0` are a character-faithful transcription of
      ADR-0002 lines 392-394
- [ ] The moduledoc states all four of decision 2's prohibitions explicitly,
      not a summary of them
- [ ] No rescue-to-default anywhere in the module (`CLAUDE.md` convention)

**Implementation Note**: as phase 1.

---

## Phase 3: In-memory migration and `:block_type_too_new`

### Overview

Implement decision 8: `resolve/2` resolves a block's type through the palette,
applies `migrate_config/2` in memory when the block's `type_version` is below
the module's `current_version/0`, never writes anything back, and refuses with
`:block_type_too_new` when the data is newer than the code.

### Changes Required:

#### 1. `resolve/2`

**File**: `lib/statifier_blocks/palette.ex`
**Changes**: `resolve/2` with the ADR's declared spec plus the third arm
Open Question 1 records.

```elixir
@doc """
Resolves and, if needed, migrates in memory. `:block_type_too_new` when the
block's `type_version` exceeds the module's `current_version/0`;
`:migration_failed` when the stored version is below it and the type's
`migrate_config/2` either returns an error or is not implemented at all.

The migrated config is applied to the returned struct only. Nothing here
writes a document back - persisting a migration is the caller's decision
(ADR-0002 decision 8).
"""
@spec resolve(t(), Block.t()) ::
        {:ok, module(), Block.t()}
        | {:error, {:unknown_block_type, Block.type_name()}}
        | {:error, {:block_type_too_new, Block.id(), pos_integer()}}
        | {:error, {:migration_failed, Block.id(), term()}}
def resolve(%__MODULE__{} = palette, %Block{} = block) do
  with {:ok, module} <- fetch(palette, block.type) do
    migrate(module, block, module.current_version())
  end
end
```

The ordered logic, one arm per distinguishable cause:

1. `fetch/2` the type. Absent -> `{:error, {:unknown_block_type, type}}`.
2. `block.type_version == current` -> `{:ok, module, block}` unchanged. This
   clause runs first among the version comparisons, so the overwhelmingly
   common case never touches `Code.ensure_loaded?/1`.
3. `block.type_version > current` -> `{:error, {:block_type_too_new,
   block.id, block.type_version}}`. **Hard error, never a best-effort read** -
   decision 8's grounds are that the code is older than the data and guessing
   there is how a rollback corrupts documents.
4. `block.type_version < current` -> call `migrate_config/2` **once**, from
   the stored version straight to current. One call, not a version-by-version
   ladder: the callback's signature is `migrate_config(from, config)` and the
   ADR's worked example handles `migrate_config(1, config)` against a
   `current_version` of `2` with a catch-all error clause for every other
   `from`. A ladder would be a contract this record does not declare.
   - `{:ok, config}` -> `{:ok, module, %{block | config: config}}`.
   - `{:error, reason}` -> `{:error, {:migration_failed, block.id, reason}}`.
   - The callback is not exported at all (`Code.ensure_loaded?/1` then
     `function_exported?(module, :migrate_config, 2)`) ->
     `{:error, {:migration_failed, block.id, :no_migration_available}}`.
     Decision 5 says "no `migrate_config/2` means the type has never changed
     its config shape", so a type whose `current_version/0` is above `1`
     without the callback is a broken palette entry, and the alternative -
     silently passing stale config through - is exactly the corruption
     decision 8's `:block_type_too_new` arm exists to prevent.

Only `block.config` is ever rewritten, and only on the returned in-memory
struct. `type_version` on the returned block is left **as stored**: nothing
this package hands back may look like a document that was migrated on disk,
and a caller that wants to persist the migration is making its own decision
about the `revision` axis (ADR-0001 decision 7). Recorded as Open Question 5.

`resolve/2` never walks a document. It takes one block, because the caller -
validation, the editor, the compiler - owns the walk and owns what to do with
a per-block failure.

#### 2. Changelog fragment

**File**: `changelog.d/sb-dvj.md`
**Changes**: Append the `resolve/2` and migration lines, including the
"migrated in memory, never written back" fact, which is the user-visible
behaviour a host has to know.

### Success Criteria:

#### Automated Verification:
- [ ] Full gate green: `mix quality`
- [ ] A block at `type_version: 2` against `Toy` (`current_version/0 == 2`)
      resolves to `{:ok, Toy, block}` with `block` **identical** to the input
      (`assert resolved == block`)
- [ ] **The migration path**: a block at `type_version: 1` carrying
      `%{"field" => "lead_score"}` resolves to `{:ok, Toy, migrated}` where
      `migrated.config["assign_to"] == "lead_score"` and
      `Map.has_key?(migrated.config, "field") == false`
- [ ] **Never written back**: the migration test holds a `%Document{}`
      containing that block, calls `resolve/2` on the block, and asserts the
      document is byte-identical afterwards -
      `Document.content_hash(doc)` unchanged and `doc == doc_before`
- [ ] **The hard error**: a block at `type_version: 99` against `Toy`
      returns `{:error, {:block_type_too_new, block.id, 99}}`, with the block
      id and the offending version both named
- [ ] `resolve/2` on a block whose `type` no entry carries returns
      `{:error, {:unknown_block_type, type}}` and never reaches
      `current_version/0`
- [ ] A migration returning `{:error, reason}` (the Toy's catch-all clause,
      reached by a block at `type_version: 1` against a type whose
      `current_version/0` is `3`) surfaces as
      `{:error, {:migration_failed, id, {:no_migration_from, 1}}}`
- [ ] A type with `current_version/0 == 2` and **no** `migrate_config/2`
      (add a third fixture module) returns
      `{:error, {:migration_failed, id, :no_migration_available}}`
- [ ] `resolve/2` returns a value and raises for none over the same hostile
      table phase 2 used, plus a block whose `type_version` is `1` against
      every fixture module
- [ ] Coverage stays at or above the 90% floor with every `resolve/2` clause
      reached - full `mix quality` decides this, and it is called out because
      the headroom is 4.2 points

#### Manual Verification:
- [ ] Every new test carries its sabotage mutation note, verified by hand
- [ ] The check order is defensible as "one arm per distinguishable cause"
      against decision 8 - read the ordered list beside the ADR
- [ ] Migration is applied exactly once per `resolve/2` call, not iterated -
      confirm by reading, since a ladder and a single call are
      indistinguishable for a 1 -> 2 migration
- [ ] Nothing in `palette.ex` calls `Document.to_json/1`, `from_json/1`, or
      anything that could persist - the "never written back" rule read rather
      than only tested

**Implementation Note**: as phase 1. This is the last phase; run
`/wurk:verify --unattended` after it to work the deferred manual items and
the open questions below.

---

## Open Questions

These are recorded rather than resolved because no human is available. Each
carries the resolution this plan implements so the work is not blocked; each
is a `/wurk:verify` item.

**1. `resolve/2`'s declared spec has no arm for a failing migration
(BLOCKING-shaped, resolved provisionally here).** ADR-0002 line 405-408 gives
`resolve/2` exactly two error arms, while `migrate_config/2`'s own declared
spec at line 375 is `{:ok, Block.config()} | {:error, term()}`. The ADR's own
worked example (line 506) has a `migrate_config/2` clause that returns
`{:error, {:no_migration_from, from}}`. So the ADR declares a callback failure
mode its resolution function has nowhere to put. The same gap covers an
optional `migrate_config/2` that is absent while `current_version/0` is above
the stored version.

This plan adds a third arm, `{:error, {:migration_failed, Block.id(),
term()}}`, because every alternative is worse: swallowing the error and
returning unmigrated config is the silent corruption decision 8 exists to
prevent; raising contradicts `CLAUDE.md`'s errors-are-events rule and decision
3's totality discipline; and collapsing it into `:block_type_too_new` would
put two distinguishable causes in one arm, which decision 3 explicitly
forbids. **This is a gap in an accepted ADR and needs an operator ruling and
probably an amendment** - which this bead may not make, since `docs/adr/` is
owned by another worker this session. The blast radius if the ruling goes
another way is one clause, one `@spec` line, and two phase-3 tests.

**2. `Palette.new/1` is public API the ADR's typespec block does not list
(non-blocking).** ADR-0002 declares `defstruct types: %{}`, `fetch/2` and
`resolve/2`. This plan adds `new/1` over a map. Grounds: the ADR's own usage
example builds a palette with struct literal syntax **merged with
`Palette.core()`**, and `core/0` is `sb-w6d`'s, so without `new/1` every
caller and every test in this bead writes `%Palette{types: ...}` directly
against a struct - which is exactly the coupling a constructor exists to
avoid, and which `sb-xti` already avoided with `Block.new/2` and
`Document.new/2` against the same ADR-shaped situation. The ADR lists the
functions it constrains, not an exhaustive API, so this reads as an addition
rather than a contradiction. Reversing it is a deletion plus two test edits.

**3. No bead owns palette-aware document validation (non-blocking, but a real
gap).** Decision 6 names a `:undeclared_slot` finding and says arity is "a
validation rule applied against the uniform document shape". Nothing in this
bead's scope implements either, `sb-xti`'s plan deferred slot-arity checking
to assignability (`sb-b3t`), and `sb-b3t`'s own scope per decision 11 is
`io/1`'s return shape and the compatibility relation - which is a different
question from arity and undeclared slots. So the checker that consumes this
bead's vocabulary is currently unowned. This plan implements the vocabulary
and no checker, which is the correct scope for `sb-dvj`; the gap is recorded
so it becomes a bead rather than being discovered by `sb-ort` at compile time.

**4. The struct spelling of `fixtures/0` cannot be covered here
(non-blocking).** Amendment 9a lists four spellings, one of which is
`%StatifierUI.Fixtures{}`. This package must not depend on `statifier_ui`
(the amendment says so explicitly), so no test here can construct that struct,
and phase 1 covers the other three. This is a genuine and acceptable coverage
limitation, not an omission: statifier-ui's own `Bundle.load/3` tests are
where the struct spelling is exercised, and asserting it here would require
the dependency the amendment forbids.

**5. `resolve/2` returns the block with `type_version` left as stored
(non-blocking).** Decision 8 says migration is applied to the in-memory block
and is not written back, but does not say whether the in-memory block's
`type_version` field is bumped. This plan leaves it as stored, so the returned
struct is never mistakable for a persisted migration and a caller that
re-resolves gets the same answer idempotently (decision 8's consequence bullet
requires migrations to be cheap and idempotent). The cost is that a caller
reading `block.type_version` after `resolve/2` sees the old number while the
config is new. If the operator prefers the bumped form it is a one-line change
plus one assertion.

**6. The d9 amendment is not yet accepted (recorded, resolution given by the
task).** The amendment's pull request is open. This plan implements
`fixtures/0` to the amended spelling set and marks that one surface
provisional in its `@doc`, per the task's explicit instruction. If the
amendment is rejected or changed, the blast radius is one `@doc` and the three
spelling tests in phase 1 - the `@callback fixtures() :: term()` line does not
change either way, which is precisely why the amendment left it alone. No
other surface in this plan is marked provisional.

**7. This plan adopts st-ADR-0018's no-bead-IDs-in-`lib/` rule, which this
repo has not actually inherited (non-blocking, resolved here).** ADR-0002's
sketch carries `@doc "Type expressions for assignability. Return shape is
sb-7rx's."` and similar for `emit/2` and `palette_entry/0`. st-ADR-0018
(`statifier-ex/docs/adr/0018-no-process-jargon-in-code-comments.md:99-103`)
bans bead IDs, plan filenames and pull-request numbers from code comments and
docs while explicitly permitting ADR numbers, on the grounds that an ADR is
never deleted or renumbered and so stays resolvable; `:146-151` exempts
`docs/adr/`, `docs/plans/` and `docs/research/` files themselves, which is why
ADR-0002's own sketch may cite beads and why this plan document may.

**Being honest about its standing here**: this repo's `CLAUDE.md` inherits a
short *enumerated* list of statifier-ex conventions (errors-as-events,
structs and `@spec`s, sabotage notes, commit-message format). st-ADR-0018 is
not on that list, so it is not already binding on `statifier_blocks`. This
plan **adopts** it rather than claiming to follow it.

The grounds for adopting it are concrete rather than stylistic: ADR-0002's
bead citations have **already drifted**. `sb-7rx`, `sb-iwz` and `sb-w50` are
the names the ADR uses; `bd show` confirms the implementation beads are
`sb-b3t` (ADR-0003), `sb-ort` (ADR-0004) and `sb-ia5` (ADR-0005). A faithful
transcription would therefore have shipped three unresolvable pointers into
hexdocs on day one, while ADR numbers stay correct forever. Recorded because
it is a visible, deliberate departure from near-literal transcription of an
accepted ADR, and an operator may prefer the ADR's literal text - or may
prefer to record the convention in this repo's `CLAUDE.md` so the next bead
does not have to re-derive it.

**8. Two lines of ADR-0002's sketch are deliberately not transcribed verbatim
(non-blocking, recorded for the reader).** Beyond Open Question 7's `@doc`
citations, the `BlockType` moduledoc's `"this package ships only the `core.*`
types"` is a present-tense claim that is **false** between this bead merging
and `sb-w6d` merging - decision 10 is explicitly not this bead's. Phase 1
rewords it to say the `core.*` vocabulary lands in a later record and is not
present yet. Both departures are flagged in phase 1's manual verification so
the transcription check does not read them as transcription errors.

## Testing Strategy

### Unit Tests:

- `test/statifier_blocks/block_type_test.exs` - the callback surface
  (`behaviour_info/1` for both required and optional), the nine-callback
  exercise against the Toy, the optional-absence assertions against Minimal,
  the closed arity and field-type sets, decision 6's stability rule, and the
  three constructible `fixtures/0` spellings.
- `test/statifier_blocks/palette_test.exs` - `new/0`, `new/1`, `fetch/2`'s
  both arms and its totality over hostile names, then `resolve/2`'s four arms,
  the migration, the never-written-back property against a real `%Document{}`,
  and `:block_type_too_new`.

Key edge cases to cover explicitly: an empty palette; two palettes mapping the
same name to different modules in one test; a block whose `type_version`
equals `current_version/0` exactly (the no-migration path); a block one below
and one above; a `migrate_config/2` that returns `{:error, _}`; a type at
`current_version/0 > 1` with no `migrate_config/2` at all; a config the Toy's
`validate_config/1` rejects, confirming `slots/1` is only promised stable over
configs it accepts.

Per `CLAUDE.md`, every test that asserts `lib/` behaviour is sabotage-verified
- break the code it covers, confirm red, revert - and carries a one-line
mutation note directly above it.

### Manual Testing Steps:

1. Read `lib/statifier_blocks/block_type.ex` side by side with ADR-0002's
   "The contract as typespecs" section and confirm the transcription is
   faithful - no callback added, dropped, renamed, or re-arity'd.
2. In `iex -S mix`, build a palette with the Toy, resolve a `type_version: 1`
   block, and confirm the returned config carries `assign_to` while the
   original block value is untouched.
3. Confirm `Palette.fetch/2` on a name the palette never had returns a value
   rather than raising - the registry-free promise ADR-0001 decision 9 and
   ADR-0002 decision 3 share, checked by eye as well as by test.
4. Confirm nothing in `lib/` references `statifier_ui`, an ETS table, an
   `Application` env key, or `Palette.core/0`.

## References

- Source spec: `docs/adr/0002-block-type-behaviour.md` (accepted 2026-08-26),
  decisions 1-9, "The contract as typespecs" (lines 318-409) and the worked
  example (lines 420-528)
- The d9 amendment, **not yet accepted**: PR #13, branch
  `sb-wm8-amend-adr0002-fixtures`, sections 9a/9b/9c of the same file
- The convention the amendment adopts:
  `/Users/johnnyt/Dev/github/statifier/statifier-ui/docs/fixture-bundles.md`
  (statifier-ui commit `2317ea7`)
- Foundation: `docs/adr/0001-block-document-schema.md` and its implementation
  on this branch's base, `lib/statifier_blocks/block.ex:13-38`
- Out of scope, each named in decision 11: `docs/adr/0003-assignability.md`
  (`sb-b3t`), `docs/adr/0004-compiler-provenance.md` (`sb-ort`),
  `docs/adr/0005-liveview-editor.md` (`sb-ia5`), and `sb-w6d` for decision 10
- Sibling plan and its conventions:
  `docs/plans/260826-sb-xti-block-document-model.md`
- Test-support pattern to follow: `test/support/document_fixtures.ex`
- Conventions and gate rules: `CLAUDE.md`, `.quality.exs`, `coveralls.json`,
  `changelog.d/README.md`, `.claude/wurk.json`
- Bead: `sb-dvj` (depends on `sb-nny`, `sb-xti`; blocks `sb-b3t`, `sb-w6d`,
  `sb-ia5`, `sb-ort`)

## Deferred Manual Verification

Manual verification items are deferred during looped (--loop) execution and
surfaced here once, rather than blocking after each phase. Confirm these
before considering the plan fully landed.

### Phase 1

- [ ] Every new test carries its one-line sabotage mutation note, and the
      mutation described actually turns that test red (no command checks
      this - `mix quality` cannot see a comment)
- [ ] The `@type` and `@callback` definitions are a character-faithful
      transcription of ADR-0002 lines 318-385, with no callback added,
      dropped, renamed, or re-arity'd, and no type widened or narrowed. Two
      departures are deliberate and are **not** transcription errors: `@doc`
      prose cites ADR numbers where the sketch cited bead IDs (Open Question
      7), and the moduledoc's `core.*` sentence is reworded to future tense
      because decision 10 has not landed (Open Question 8). There should be
      no third departure
- [ ] The `fixtures/0` provisional marker reads as the family's own idiom:
      ADR-0002 decision 9's `PROVISIONAL - <pointer>` spelling inside
      predicator-ex's admonition shape, sentence-case title, blank `>` line
- [ ] The per-callback `@doc`s name the correct owning **record** for each of
      the four shapes this record does not own: ADR-0003 for `io/1`,
      ADR-0004 for `emit/2`, ADR-0005 for `palette_entry/0`, and ADR-0002
      decision 9 plus statifier-ui's `docs/fixture-bundles.md` for
      `fixtures/0`

**Implementation Note**: Use `mix quality --profile loop` between edits; run
full `mix quality` as the phase gate. In interactive execution pause here for
the human; in `--loop` execution the Automated Verification block gates
advancement and the Manual items defer to `/wurk:verify`.

---
