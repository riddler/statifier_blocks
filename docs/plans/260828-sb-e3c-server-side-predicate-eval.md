# Server-side predicate evaluation for fixture truth tables Implementation Plan

## Overview

Replace the spike's precomputed truth-table expected values with real
evaluation, done **server side through predicator**, so a fixture row can be
*checked* rather than asserted. Bead: `sb-e3c`.

The bead's title says "Real JS predicate evaluator". That title predates the
ruling. Campaign-014 pre-decision **D11** settles the contract question the
bead's body raises: evaluation is server side, through predicator, reached
from the LiveView editor path. A JS evaluator would be a second
implementation of the predicator grammar, and this plan writes **no
JavaScript at all**.

Two new public modules, both pure and both outside `StatifierBlocks.Editor.*`:

| Module | Responsibility |
|---|---|
| `StatifierBlocks.Predicates` | the evaluation seam: a condition source plus a context in, `{:ok, boolean()} \| {:error, reason}` out; plus binding-source evaluation and dotted-path context building |
| `StatifierBlocks.Predicates.TruthTable` | the builder: a table spec plus rows in, a `%TruthTable{}` with per-cell outcomes and expectation checks out |

Plus a strictly additive `mix.exs` change (a direct `{:predicator, "~> 9.0"}`
dependency and one new hexdocs module group) and one changelog fragment.

## Current State Analysis

Branch `sb-e3c-server-side-predicate-eval`, a worktree of `statifier_blocks`.

### predicator is present but only transitively

`grep -rn "Predicator" lib/` returns three moduledoc mentions and no call
site:

- `lib/statifier_blocks/core/wait.ex:101` cites `Predicator.Duration.parse/1`
  in prose (see the caution in "Key discoveries" - that function does not
  exist).
- `lib/statifier_blocks/core/branch.ex:208` says condition strings are passed
  verbatim into predicator's datamodel and that the compiler ships no
  expression evaluation.
- `lib/statifier_blocks/editor/field.ex:27` says `:expression` renders as a
  plain source input here.

`mix.lock:28` already resolves `predicator 9.0.1`, pulled in by
`statifier 2.1.1` (`mix.lock:30`), which declares `{:predicator, "~> 9.0"}`.
`mix.exs`'s `deps/0` names no predicator dependency. Calling
`Predicator.evaluate/2` from `lib/` against a transitive dependency is exactly
the coupling a direct dependency exists to make honest, so this plan adds one.

`mix.headless.lock` is gitignored (`.gitignore:16`) and absent from the
worktree, so the headless tree needs no lockfile bookkeeping; the headless
resolution simply picks up the new direct dependency from hex like any other.

### The editor has no fixtures pane, so there is no wiring seam today

`grep -rn "fixtures\|dataset" lib/statifier_blocks/editor.ex
lib/statifier_blocks/editor/` returns nothing. The component's `handle_event/3`
clauses (`lib/statifier_blocks/editor.ex:184-282`) are select, dragstart,
dragend, drop, remove, undo, redo, the four palette events, config-change and
the two field-list events. There is no pane, no assign and no event that a
truth table would attach to.

That is not an oversight. **ADR-0005 decision 15**
(`docs/adr/0005-liveview-editor.md:567`) lists per-palette-entry fixtures -
"the 'test this step' panel ADR-0002 decision 9 sketched" - among the things
the record explicitly does not decide. **ADR-0005 decision 9**
(`docs/adr/0005-liveview-editor.md:336`) ships `:expression` as a plain source
input and hands rich expression editing, including inline evaluation against a
dataset, to statifier-ui (sui-bob, sui-ADR-0006), with a host-supplied
override component as the seam.

So this plan lands the pure half and documents where the wiring would attach.
No LiveView file is edited.

### ADR-0002 decision 9 owns the word "fixtures", and this package does not

`docs/adr/0002-block-type-behaviour.md:250-320`. `fixtures/0` returns a bundle
in one of four spellings, and **the convention is statifier-ui's**
(`StatifierUI.Fixtures.Bundle.load/3`, statifier-ui `docs/fixture-bundles.md`),
adopted whole. The record says in as many words that this package "does not
invent a competing convention" and that the amendment "does not make
`statifier_ui` a required dependency of this package. Nothing here calls the
loader."

That is the naming constraint. A module called `StatifierBlocks.Fixtures`
would assert a contract this package does not own, and would collide with a
bundle shape whose authority lives in another repo. `StatifierBlocks.Predicates`
names what this code actually is - the evaluation seam - and claims nothing
about how a host packages datasets.

### `core.branch` is the shape a truth table is *of*

`docs/adr/0002-block-type-behaviour.md:322` (decision 10) makes `core.branch`'s
config an ordered `arms` list and its conditions `:expression` fields. The
shipped type (`lib/statifier_blocks/core/branch.ex`) stores each arm as
`%{"slot" => "arm_approved", "cond" => "budget_remaining > amount"}` and
`slots/1` returns one slot per arm in config order followed by `otherwise`.
Arms are tried in order; that ordering is the whole reason a branch truth table
is interesting, and it is why this plan's builder computes selection rather
than only raw booleans.

### Verified predicator 9.0.1 behaviour

Probed live in this worktree with `mix run`, context
`%{"transaction" => %{"amount" => 120, "currency" => "USD"}, "flag" => true}`:

| Expression | Result |
|---|---|
| `"transaction.amount > 500"` | `{:ok, false}` - dotted paths resolve into nested string-keyed maps |
| `"flag"` | `{:ok, true}` |
| `"transaction.amount"` | `{:ok, 120}` - a **non-boolean** result is reachable |
| `"missing.thing > 1"` | `{:error, %UndefinedVariableError{variable: "missing", position: {1, 1}}}` |
| `"amount >"` | `{:error, %ParseError{position: {1, 9}, span: {{1, 9}, {1, 9}}}}` |
| `"transaction.amount > 'x'"` | `{:ok, :undefined}` - a **type mismatch in a comparison is an OK-undefined**, not an error |

And the value grammar a binding's source text can use (probed with an empty
context):

| Source | Result |
|---|---|
| `"120"`, `"-3"`, `"1.5"` | `{:ok, 120}`, `{:ok, -3}`, `{:ok, 1.5}` |
| `"'clear'"` | `{:ok, "clear"}` |
| `"true"` | `{:ok, true}` |
| `"15m"`, `"1h30m"` | `{:ok, %{minutes: 15, ...}}` - a duration map |
| `"PT15M"` | `{:error, %UndefinedVariableError{variable: "PT15M"}}` - **ISO-8601 is not predicator source** |
| `"#2026-08-28#"` | `{:ok, ~D[2026-08-28]}` |
| `"#2026-08-28T00:00:00Z#"` | `{:ok, ~U[2026-08-28 00:00:00Z]}` |
| `"[1, 2]"` | `{:ok, [1, 2]}` |
| `"{'a': 1}"` | `{:ok, %{"a" => 1}}` |

`Predicator.evaluate(input, context \\ %{}, opts \\ [])` accepts a binary, an
instruction list or a `%Predicator.Compiled{}`, and returns
`{:ok, Predicator.Types.value()} | {:error, struct()}`. `opts` carries
`on_unbound: :undefined` (default) or `:error`; with `:error`, an unbound bare
identifier returns `{:error, %UndefinedVariableError{}}` rather than
`{:ok, :undefined}`. Error structs live in
`deps/predicator/lib/predicator/errors/`: `ParseError`,
`UndefinedVariableError` (carries `.variable`), `TypeMismatchError`,
`EvaluationError`, `LocationError`.

`Predicator.Duration` has **no** string `parse/1`. Durations are lexer
literals (`15m`), not ISO-8601. `core/wait.ex:101`'s moduledoc mention of
`Predicator.Duration.parse/1` is prose about a syntax family, not a call, and
this plan does not touch it.

### Gate and convention constraints binding every phase

- **Full `mix quality` is the advancement gate.** `--profile loop` is the
  inner loop and is never evidence (`CLAUDE.md`, "This repo's own gate rules").
- **90% coverage floor**, `test/support/` skipped (`coveralls.json`). Every new
  `lib/` line needs a test in the phase that adds it.
- **`format: [check: true]`** (`.quality.exs`): run `mix format` by hand;
  drift fails the gate and nothing is rewritten.
- `credo --strict`, `warnings_as_errors: true`, dialyzer in the full gate.
- `@spec` on every public function; structs and MapSets; pattern matching over
  multiple asserts in tests; errors are events, never rescue-to-default.
- **Sabotage every new test that asserts `lib/` behaviour**: break the code it
  covers, confirm red, revert, leave a one-line note above the test naming the
  mutation. `mix quality` cannot read a comment, so this is a **Manual**
  criterion in every phase, as `sb-ia5`'s and `sb-xti`'s plans classify it.
- **Concurrent workers share this repo.** New modules and new test files only;
  `mix.exs` and `mix.lock` edits are strictly additive; no refactor of an
  existing module.
- **Terminology firewall**: canonical example domains only - credit-card
  processing and the signup wizard. Never the words "enrich", "score",
  "scoring", or "crm_push" in new code, tests, docs or commit messages, even
  though predicator's own docs use "score".

## Desired End State

`StatifierBlocks.Predicates` and `StatifierBlocks.Predicates.TruthTable` ship
as public, `@spec`-ed, fully covered pure modules; `predicator` is a direct
dependency; a new hexdocs group holds both modules; a `changelog.d/sb-e3c.md`
fragment describes the addition; `docs/adr/` is untouched; `spike/` is
untouched; no `lib/statifier_blocks/editor*` file is edited.

Verification: full `mix quality` green, and this snippet behaves as written in
`iex -S mix`:

```elixir
alias StatifierBlocks.Predicates
alias StatifierBlocks.Predicates.TruthTable

Predicates.evaluate("transaction.amount > 500",
                    %{"transaction" => %{"amount" => 120}})
#=> {:ok, false}

Predicates.evaluate("transaction.amount", %{"transaction" => %{"amount" => 120}})
#=> {:error, {:non_boolean, 120}}

Predicates.evaluate("transaction.amount > 'usd'",
                    %{"transaction" => %{"amount" => 120}})
#=> {:error, {:undefined_result, "transaction.amount > 'usd'"}}

Predicates.context(%{"transaction.amount" => "120", "customer.verified" => "true"})
#=> {:ok, %{"transaction" => %{"amount" => 120},
#=>         "customer" => %{"verified" => true}}}

{:ok, table} =
  TruthTable.build(
    %{
      name: "Authorization branch",
      columns: [
        %{key: "arm_declined", label: "Declined", source: "transaction.amount > 500"},
        %{key: "arm_approved", label: "Approved", source: "customer.verified"},
        %{key: "otherwise", label: "Otherwise", source: nil}
      ]
    },
    [
      %{
        name: "Small, verified",
        bindings: %{"transaction.amount" => "120", "customer.verified" => "true"},
        expected: %{"arm_declined" => false, "arm_approved" => true, "otherwise" => false}
      }
    ]
  )

table |> TruthTable.statuses() |> Enum.uniq()
#=> [:match]
```

### Key Discoveries

- **ADR-0002 decision 9/9a-9c** (`docs/adr/0002-block-type-behaviour.md:250`)
  puts the fixture-bundle convention in statifier-ui and forbids a competing
  one here. It is the reason the module is named `Predicates` and not
  `Fixtures`, and the reason nothing in this plan reads or writes a bundle.
- **ADR-0002 decision 10** (`:322`) and `lib/statifier_blocks/core/branch.ex`
  make branch arms an ordered list with `otherwise` last. First-match-wins is
  a config-level fact, not an implementation detail (branch.ex's moduledoc
  says so), so the truth table models selection.
- **ADR-0005 decisions 9 and 15** (`docs/adr/0005-liveview-editor.md:336`,
  `:567`) are the written evidence that the editor has no fixtures pane and
  that inline evaluation against a dataset is deferred to statifier-ui with a
  host-supplied override seam. Verified against
  `lib/statifier_blocks/editor.ex:184-282`.
- **Predicator returns `{:ok, :undefined}` for a cross-type comparison.** That
  is the single most surprising probe result, and the reason `:undefined` gets
  its own error tag rather than being folded into false.
- **Predicator durations are `15m`, not `PT15M`.** ADR-0001 decision 6 stores
  durations as ISO-8601 in *config*; a truth-table *binding* is predicator
  source, so a duration binding is written `15m`. This must be said in the
  moduledoc or the first author to write `"PT15M"` gets an undefined-variable
  error that reads like a bug.
- `deps/predicator/lib/predicator.ex:178` is the `evaluate/3` head;
  `:732`/`:763`/`:794` are `compile/1`, `compile_with_positions/1`,
  `compile_with_spans/1`.

## What We're NOT Doing

- **No JavaScript.** No `assets/js` change, no client-side evaluator. D11
  rules evaluation server side; a JS mirror would be a second implementation
  of the predicator grammar.
- **No change to `spike/`.** The spike is read-only reference for intent.
- **No change to `docs/adr/`.** An ADR amendment needs an independent
  direction-agent gate this bead does not carry. If the work suggests one, it
  is recorded in "Open questions" below and filed as a follow-up, never
  written into an ADR here.
- **No editor wiring.** There is no pane, assign or event to attach to
  (ADR-0005 decision 15). The seam is documented in the `Predicates` moduledoc
  and the wiring is recorded as a note on bead `sb-8dc` by the orchestrator.
- **No `StatifierBlocks.Predicates.Datamodel` module.** The spike's typed
  datamodel (`spike/fixtures/datamodel.json`) is advisory - its own stance is
  that an undeclared path is "unknown", never "wrong" - and nothing in the
  evaluator or the builder consumes it: bindings carry their own values and
  the column order comes from the table spec. A path/type index with no
  consumer would be an unused public module fighting the 90% coverage floor,
  and it would assert an index shape for a pane that does not exist. Preferring
  the smaller contract, it is deferred; see "Open questions" item 1.
- **No type-checking of evaluated bindings against a declared type.** Same
  reason: the spike's stance is advisory, and predicator already types its own
  values.
- **No `statifier_ui` dependency**, optional or otherwise. ADR-0002 decision 9
  is explicit that this package does not gain one; nothing here calls
  `StatifierUI.Fixtures.Bundle.load/3`.
- **No reuse of `spike/fixtures/runs.json` as a test fixture.** New test data
  is written in-line in the test files, in the canonical example domains. The
  spike's tables are consulted for shape, not copied.
- **No compile-once caching across rows** (`Predicator.compile/1` plus
  `%Predicator.Compiled{}`). It is a real option and the API supports it, but a
  truth table is a handful of rows in an authoring UI; caching would add a
  lifetime question and a second code path for no measurable benefit. Recorded
  here so a later reader knows it was considered and declined, not missed.

## Implementation Approach

Two phases, each independently committable with a full `mix quality` green at
its boundary.

**Phase 1** adds the dependency and the evaluation seam. It is the phase that
fixes the error vocabulary, which is the plan's real design content.

**Phase 2** adds the truth-table builder on top, which is pure composition of
Phase 1's seam plus the first-match-wins selection pass.

The changelog fragment is written in Phase 1 and extended in Phase 2; one file,
one branch, no conflict.

### The error vocabulary, and why each tag exists

`StatifierBlocks.Predicates.evaluate/2` classifies four predicator outcomes
into a closed set of tagged tuples. Errors are events: nothing here is coerced
to a default.

| Predicator returns | `evaluate/2` returns | Why this tag exists |
|---|---|---|
| `{:ok, true}` / `{:ok, false}` | `{:ok, boolean()}` | the only success. A condition's answer is a boolean or it is an error |
| `{:ok, :undefined}` | `{:error, {:undefined_result, source}}` | `:undefined` is predicator's absence sentinel and it is distinct from `nil`. It is what a cross-type comparison and an unbound operand both produce. It means "this expression has no answer for this context" - the expression is well formed and the context is the problem. Folding it to `false` is precisely the rescue-to-default the conventions forbid, and it would make a fixture pass for the wrong reason |
| `{:ok, value}`, value not a boolean | `{:error, {:non_boolean, value}}` | `"transaction.amount"` is valid predicator source that evaluates to `120`. A truthiness rule would be a second semantics this package invented on top of predicator's. The value is carried so a caller can say what it got |
| `{:error, %ParseError{} = e}` | `{:error, {:parse_error, e}}` | the source is not predicator source at all. Separated from the context errors because the author has a syntax error, and the struct carries `position` and `span` for an editor to anchor a finding on |
| `{:error, %UndefinedVariableError{variable: v} = e}` | `{:error, {:undefined_variable, v, e}}` | the source is fine and the *context* is incomplete. The variable name is lifted into the tuple because "which binding is missing" is the fixture-authoring error a truth table exists to catch, and a caller should not have to know predicator's struct to read it |
| any other predicator error struct | `{:error, {:evaluation_error, e}}` | a total fallback. Without it, a predicator version that adds an error struct would fall through to a `FunctionClauseError` - a raise where the convention demands an event. `TypeMismatchError`, `EvaluationError` and `LocationError` land here today |

Two further tags belong to the binding layer, not to `evaluate/2`:

| Tag | Meaning |
|---|---|
| `{:binding, path, reason}` | a binding's source text did not produce a value; `reason` is one of the tags above. A binding failure has to name *which* binding, or a table with eight bindings reports an error the author cannot locate |
| `{:binding_conflict, path}` | two dotted paths cannot both be nested - `"transaction"` and `"transaction.amount"` bound together, or a duplicate. Letting one silently win is a default; this is an error |

**How a row's bindings become a context.** The spike's `bindings` values are
predicator *source text* (`"34"`, `"'clear'"`, `"true"`), not JSON values. So
each binding's source is evaluated through `Predicator.evaluate/2` with an
empty context and the resulting value is nested at its dotted path. This is
coherent and it is the right call: it reuses predicator's own value grammar
rather than writing a second literal parser, which is the same argument D11
makes against a JS evaluator, applied one level down. The one wrinkle it
inherits is that a duration binding is written `15m` and not `PT15M`; that is
documented in the moduledoc.

A binding source that evaluates to `:undefined` is an error
(`{:binding, path, {:undefined_result, source}}`), not a skipped cell. A
binding source that yields a non-boolean is **fine** - bindings are values of
any type - which is why binding evaluation is a separate public function
(`evaluate_value/1`) from condition evaluation (`evaluate/2`), rather than a
flag on one function.

**Argument order.** `evaluate(source, context)` mirrors
`Predicator.evaluate(input, context)`. The repo convention that puts a
state/session first is about threading a `%Document{}` or a socket through a
pipeline; a plain binding context is a value, not a session, and diverging from
the wrapped library's own order would cost more at every call site than it
buys. The moduledoc says this in one sentence.

### The `otherwise` column and first-match-wins

The spike's `otherwise` column carries the non-expression string
`"no arm matched"`. It is not evaluated; it is computed.

More importantly, the spike's `expected` values encode **which arm is taken**,
not raw expression truth. Its "Flagged for review" row binds
`risk_rating = 12` and `customer.verified = true`, so `arm_low_risk`'s
expression (`risk_rating < 40 AND customer.verified`) is raw-true - yet the row
expects `arm_low_risk: false`, and the row's own note explains why: the
high-risk arm is declared first and wins. That matches `core.branch`'s
semantics and ADR-0002 decision 10's ordered arms.

So a cell carries both facts:

- `outcome` - the raw `{:ok, boolean()} | {:error, reason}` from `evaluate/2`;
- `selected?` - `true | false | :undecidable`, from one first-match-wins pass
  over the columns in declared order.

The selection pass: a column is selected iff its `outcome` is `{:ok, true}`
and no earlier column was selected. A column with `source: nil` is the
`otherwise` column and is selected iff no earlier column was selected - so
"no arm matched" falls out of the same pass rather than needing a rule of its
own. There may be at most one `otherwise` column and it must be last;
otherwise `build/2` returns `{:error, {:otherwise_not_last, key}}`.

If any column's outcome is an error, selection is **undecidable** from that
column onward: every later column's `selected?` is `:undecidable`, not
`false`. Reporting "no arm matched" while one arm's answer is unknown would be
a guess, and that is the errors-are-events rule applied to the ordering.

`expected` is compared against `selected?`, giving a per-cell `status` that is
deliberately wider than the spike's `true | false | unset` tri-state:

| `status` | When |
|---|---|
| `:match` | `selected?` is a boolean and equals `expected` |
| `:mismatch` | `selected?` is a boolean and differs from `expected` |
| `:unchecked` | `selected?` is a boolean and the row declares no expectation for this column |
| `:error` | this column's own `outcome` is an error |
| `:undecidable` | this column's outcome is fine but an earlier column errored |

A whole row can also fail before any cell is computed - its bindings did not
build a context. Then `%Row{}` carries `error: reason` and `cells: []`, and a
renderer checks `row.error` first.

---

## Phase 1: The predicator dependency and the evaluation seam

### Overview

Add `{:predicator, "~> 9.0"}` as a direct dependency, a hexdocs group for the
new namespace, and `StatifierBlocks.Predicates` with its three public
functions and the closed error vocabulary above.

### Changes Required:

#### 1. The direct dependency

**File**: `mix.exs`
**Changes**: one added line in `deps/0`. Strictly additive - no existing line
is edited, reordered or reformatted, because concurrent workers share this
file.

```elixir
  defp deps do
    [statifier_dep()] ++
      live_view_dep() ++
      [
        {:predicator, "~> 9.0"},

        # Dev / test
        {:ex_quality, "~> 0.14", only: :dev, runtime: false},
        ...
      ]
  end
```

**File**: `mix.lock`
**Changes**: `mix deps.get` records the already-resolved
`predicator 9.0.1` under its own top-level key. **Nothing else in the lock may
move.** `git diff mix.lock` showing any other changed line is a
stop-and-report, not something to commit. `mix.headless.lock` is gitignored and
absent, so nothing there is tracked.

#### 2. The hexdocs group

**File**: `mix.exs`, `docs/0`'s `groups_for_modules:`
**Changes**: one appended entry, after `"LiveView editor"`. ex_doc assigns a
module to the first group whose pattern matches, and no existing pattern
matches `StatifierBlocks.Predicates`, so appending is safe and is the smallest
additive edit.

```elixir
        "LiveView editor": [
          ~r/^StatifierBlocks\.Editor($|\.)/
        ],
        "Predicate evaluation": [
          ~r/^StatifierBlocks\.Predicates($|\.)/
        ]
```

#### 3. The evaluation seam

**File**: `lib/statifier_blocks/predicates.ex` (new)
**Changes**: the module, with a moduledoc that carries four things: why the
name is `Predicates` and not `Fixtures` (ADR-0002 decision 9); the error
vocabulary table; the `15m`-not-`PT15M` caution; and the **"Where this is not
wired"** section naming ADR-0005 decisions 9 and 15, saying that the editor has
no fixtures pane today and that a host reaches this module directly or through
statifier-ui's richer expression component.

```elixir
defmodule StatifierBlocks.Predicates do
  @type reason ::
          {:undefined_result, String.t()}
          | {:non_boolean, term()}
          | {:parse_error, struct()}
          | {:undefined_variable, String.t(), struct()}
          | {:evaluation_error, struct()}
          | {:binding, String.t(), reason()}
          | {:binding_conflict, String.t()}

  @type context :: %{optional(String.t()) => term()}

  @spec evaluate(String.t(), context()) :: {:ok, boolean()} | {:error, reason()}
  @spec evaluate_value(String.t()) :: {:ok, term()} | {:error, reason()}
  @spec context(%{optional(String.t()) => String.t()}) ::
          {:ok, context()} | {:error, reason()}
end
```

- `evaluate/2` calls `Predicator.evaluate(source, context)` and classifies the
  result per the table in "Implementation Approach". `context` defaults to
  `%{}`.
- `evaluate_value/1` calls `Predicator.evaluate(source, %{})` and returns any
  `Predicator.Types.value()` except `:undefined`, which is
  `{:error, {:undefined_result, source}}`.
- `context/1` folds a `%{dotted_path => source_text}` map into a nested
  string-keyed map. Each source goes through `evaluate_value/1`; a failure
  becomes `{:error, {:binding, path, reason}}`. Paths are processed in sorted
  order so the error reported for a map with several bad bindings is
  deterministic. A path that would nest under or over an already-bound
  non-map value is `{:error, {:binding_conflict, path}}`.

#### 4. Tests

**File**: `test/statifier_blocks/predicates_test.exs` (new)
**Changes**: one test per row of the error-vocabulary table plus the context
builder. Every assertion is a pattern match, not a chain of `assert`s.

Coverage must include: `{:ok, true}`, `{:ok, false}`, `{:ok, :undefined}` via
`"transaction.amount > 'usd'"`, non-boolean via `"transaction.amount"`,
`ParseError` via `"amount >"`, `UndefinedVariableError` via
`"missing.thing > 1"`, the `:evaluation_error` fallback, `evaluate_value/1`
over integer / string / boolean / duration (`"15m"`) / date (`"#2026-08-28#"`)
sources, an `evaluate_value/1` failure, `context/1` nesting two dotted paths,
a `context/1` binding failure, and a `context/1` conflict
(`%{"transaction" => "120", "transaction.amount" => "5"}`).

The `:evaluation_error` fallback needs a real predicator error that is neither
a `ParseError` nor an `UndefinedVariableError`. Probe for one in `iex -S mix`,
guided by `deps/predicator/lib/predicator/errors/type_mismatch_error.ex`,
`evaluation_error.ex` and `location_error.ex`. Two outcomes, and one of them
must be chosen in this phase rather than deferred:

- **A source reaches it.** Write the test against that source. Done.
- **No binary source reaches it in predicator 9.0.1.** Then the clause is
  unreachable dead code and would sit uncovered against the 90% floor.
  Suppressing it with a coverage pragma is not the answer, and neither is
  keeping a clause nothing can execute. Instead, drop the separate clause and
  widen the *last* clause to match any error struct - `{:error, e}` ->
  `{:error, {:evaluation_error, e}}` - placing it after the `ParseError` and
  `UndefinedVariableError` clauses. The tag survives, the totality argument
  survives, and the clause is proved by a reachable struct.

Record which outcome held, and why, in the moduledoc.

All example data uses credit-card processing (`transaction.amount`,
`transaction.currency`, `customer.verified`, `fraud.verdict`) or the signup
wizard. The words "enrich", "score", "scoring" and "crm_push" appear nowhere.

#### 5. The changelog fragment

**File**: `changelog.d/sb-e3c.md` (new)
**Changes**:

```markdown
### Added

- `StatifierBlocks.Predicates` evaluates a condition expression against a
  binding context through predicator, returning a boolean or a tagged error.
```

Per `changelog.d/README.md` this is a public API addition, so it earns a
fragment.

### Success Criteria:

#### Automated Verification:
- [x] Full `mix quality` passes (`mix quality`, not `--profile loop`).
- [x] `mix format` leaves no diff (`format: [check: true]` fails on drift).
- [x] Coverage is at or above the 90% floor with `lib/statifier_blocks/predicates.ex` included.
- [x] `git diff mix.lock` changes exactly one region: the added `predicator` entry at version 9.0.1. Any other moved line is a stop-and-report.
- [x] `git diff mix.exs` adds lines only; no existing line is modified or removed.
- [x] `git status --porcelain spike/ docs/adr/` is empty.
- [x] `grep -rniE "enrich|scoring|\bscore\b|crm_push" lib/statifier_blocks/predicates.ex test/statifier_blocks/predicates_test.exs changelog.d/sb-e3c.md` returns nothing.
- [x] `grep -rn "Phoenix" lib/statifier_blocks/predicates.ex` returns nothing.
- [x] `test -f changelog.d/sb-e3c.md`.
- [x] The new module is grouped, not ungrouped: `mix docs && grep -q '"Predicate evaluation"' doc/dist/sidebar_items-*.js && grep -q 'StatifierBlocks.Predicates' doc/dist/sidebar_items-*.js` (adjust the glob to whatever `mix docs` writes; the check is that the group name and the module both appear in the generated sidebar data).
- [x] The headless tree still resolves and passes with the new direct dependency, which is what ADR-0005 decision 1's CI job (`.github/workflows/ci.yml`, job `headless`) proves: `STATIFIER_BLOCKS_HEADLESS=1 mix deps.get && STATIFIER_BLOCKS_HEADLESS=1 mix compile --warnings-as-errors && STATIFIER_BLOCKS_HEADLESS=1 mix test`, and `deps_headless/phoenix_live_view` must not exist. This is not part of `mix quality`, so it has to be run explicitly in the phase that changes `deps/0`.

#### Manual Verification:
- [ ] Every new test asserting `lib/` behaviour has been sabotaged - the covered code broken, the test confirmed red, the change reverted - and carries a one-line note above it naming the mutation.
- [ ] The moduledoc's "Where this is not wired" section names ADR-0005 decisions 9 and 15 and is accurate against `lib/statifier_blocks/editor.ex` as it stands.
- [ ] The `15m` / `PT15M` caution is present and correct.
- [ ] The `:evaluation_error` clause decision from item 4 is recorded in the moduledoc.

**Machine-checked (unattended, 2026-08-29):** all four items checked by an agent, not a human.
Item 1 found a real defect and fixed it in commit `48093f2`: the notes were spelled
`# Sabotage:` while `gate.rb`'s `SABOTAGE_NOTE_RE = /#\s*sabotage:/` is case-sensitive, so all
27 read as absent; and one note above `describe "evaluate_value/1"` covered five tests from
above the first, leaving four unnoted. Seven tests had had no cycle run at all - each was then
genuinely sabotaged (mutation, confirmed red, reverted, noted). `gate.rb` now reports
`sabotage.missing: []`, `unverifiable: []`, `scanned: true`.
Item 2 verified: the moduledoc cites ADR-0005 decision 9 (`:336`) and decision 15 (`:567`), and
`lib/statifier_blocks/editor.ex` has no fixtures pane, assign, or event - grep for
`fixture|dataset|predicator|evaluat` over `lib/` returns no editor hit.
Item 3 verified against a live probe: `Predicator.evaluate("PT15M", %{})` returns
`{:error, %UndefinedVariableError{variable: "PT15M"}}`, and `"15m"` yields a duration.
Item 4 verified: the moduledoc records the probe (`"true + 1"` -> `TypeMismatchError`,
`"1 / 0"` -> `EvaluationError`) and the single catch-all clause it justifies.

**Implementation Note**: Use `mix quality --profile loop` between edits; run
the full `mix quality` as the phase gate. In looped execution the Automated
Verification list gates advancement via `/wurk:commit --auto` and the Manual
items are deferred to `/wurk:verify`.

---

## Phase 2: The truth-table builder

### Overview

`StatifierBlocks.Predicates.TruthTable`: a table spec plus rows in, a struct
with per-cell raw outcomes, first-match-wins selection and expectation status
out.

### Changes Required:

#### 1. The builder

**File**: `lib/statifier_blocks/predicates/truth_table.ex` (new)
**Changes**: the module plus three nested structs. The moduledoc explains why
`expected` is compared against selection rather than raw truth, citing
`core.branch`'s ordered arms (ADR-0002 decision 10,
`lib/statifier_blocks/core/branch.ex`), and states the five-value `status`
vocabulary and why it is wider than a tri-state.

```elixir
defmodule StatifierBlocks.Predicates.TruthTable do
  defmodule Column do
    defstruct [:key, :label, :source]
    @type t :: %__MODULE__{key: String.t(), label: String.t(), source: String.t() | nil}
  end

  defmodule Cell do
    defstruct [:column_key, :outcome, :selected?, :expected, :status]

    @type status :: :match | :mismatch | :unchecked | :error | :undecidable
    @type t :: %__MODULE__{
            column_key: String.t(),
            outcome: {:ok, boolean()} | {:error, StatifierBlocks.Predicates.reason()} | nil,
            selected?: boolean() | :undecidable,
            expected: boolean() | nil,
            status: status()
          }
  end

  defmodule Row do
    defstruct [:name, :bindings, :note, :context, :error, cells: []]

    @type t :: %__MODULE__{
            name: String.t(),
            bindings: %{optional(String.t()) => String.t()},
            note: String.t() | nil,
            context: StatifierBlocks.Predicates.context() | nil,
            error: StatifierBlocks.Predicates.reason() | nil,
            cells: [Cell.t()]
          }
  end

  defstruct [:name, :description, :columns, :paths, rows: []]

  @type t :: %__MODULE__{
          name: String.t(),
          description: String.t() | nil,
          columns: [Column.t()],
          paths: [String.t()],
          rows: [Row.t()]
        }

  @type build_error ::
          {:duplicate_column, String.t()}
          | {:otherwise_not_last, String.t()}
          | {:invalid_source, String.t()}

  @spec build(spec :: map(), rows :: [map()]) :: {:ok, t()} | {:error, build_error()}
  @spec statuses(t()) :: [Cell.status()]
end
```

`build_error/0` is closed for the same reason `Predicates.reason/0` is: this is
the one function whose job is enumerating spec errors, and a `term()` there
would put a loose spec on exactly the place the plan's design content lives.
Row-level binding failures are **not** in `build_error/0` - they are per-row
data (`%Row{error: Predicates.reason()}`), not a build failure, because a
table with one bad row is still a table worth rendering.

- `build/2` validates the spec first: column keys unique
  (`{:error, {:duplicate_column, key}}`), at most one `source: nil` column and
  it must be last (`{:error, {:otherwise_not_last, key}}`), every `source`
  either a binary or `nil` (`{:error, {:invalid_source, key}}`). A malformed
  spec is an error return; a failing *cell* is data, because showing which
  cells fail is the point of the table.
- `paths` is the declared binding order, taken from the spec when given and
  otherwise derived as the sorted union of the rows' binding keys.
- Per row: `Predicates.context/1` over `bindings`. On error the row gets
  `error: reason` and `cells: []`. On success, each column's `outcome` comes
  from `Predicates.evaluate/2` (or is `nil` for the `otherwise` column), then
  one ordered selection pass sets `selected?`, then `status` is derived from
  `selected?` and `expected`.
- `statuses/1` flattens every cell's status in row-then-column order. It exists
  so a caller can assert a whole table in one pattern match, which is what the
  tests use and what a `mix test` fixture check in a host would use.
- The `Predicates` moduledoc gains one cross-reference line pointing at this
  module. That is the only edit to a Phase 1 file.

#### 2. Tests

**File**: `test/statifier_blocks/predicates/truth_table_test.exs` (new)
**Changes**: cases, all in the credit-card-processing domain, all asserted by
pattern match:

- a three-column authorization branch (two arms plus `otherwise`) over four
  rows, asserting `statuses/1` is all `:match`;
- **the first-match-wins row**: bindings under which both arms raw-evaluate
  true, asserting the first arm's cell is `outcome: {:ok, true}, selected?:
  true` and the second is `outcome: {:ok, true}, selected?: false` - the exact
  case the spike's "Flagged for review" row encodes;
- an `otherwise` row where no arm matches, asserting the otherwise cell is
  `selected?: true`;
- a `:mismatch` row - an `expected` that the evaluation contradicts, which is
  the whole point of the bead;
- an `:unchecked` cell - a column with no expectation declared;
- an `:error` cell - a column whose source is `"amount >"`;
- an `:undecidable` cell - a *later* column after an erroring one, asserting
  `selected?: :undecidable` and `status: :undecidable`;
- a row whose bindings fail, asserting `%Row{error: {:binding, _, _}, cells: []}`;
- a row with a binding conflict, asserting `{:binding_conflict, _}`;
- spec errors: duplicate column key, an `otherwise` column that is not last,
  a non-binary source;
- a row `note` surviving onto the struct.

#### 3. The changelog fragment

**File**: `changelog.d/sb-e3c.md`
**Changes**: one added line under the existing `### Added` heading.

```markdown
- `StatifierBlocks.Predicates.TruthTable` builds a checked truth table over
  fixture rows, applying first-match-wins arm ordering.
```

### Success Criteria:

#### Automated Verification:
- [x] Full `mix quality` passes.
- [x] `mix format` leaves no diff.
- [x] Coverage at or above 90% with both new modules included.
- [x] `git diff mix.lock` is empty for this phase.
- [x] `git status --porcelain spike/ docs/adr/` is empty.
- [x] `grep -rniE "enrich|scoring|\bscore\b|crm_push" lib/statifier_blocks/predicates test/statifier_blocks/predicates changelog.d/sb-e3c.md` returns nothing.
- [x] `grep -rn "Phoenix" lib/statifier_blocks/predicates/truth_table.ex` returns nothing.
- [x] `git status --porcelain lib/statifier_blocks/editor.ex lib/statifier_blocks/editor/ assets/` is empty.

#### Manual Verification:
- [ ] Every new test asserting `lib/` behaviour has been sabotaged and carries its one-line mutation note. In particular the selection pass: invert the first-match-wins guard, confirm the ordering test goes red, revert.
- [ ] The moduledoc's account of selection-versus-raw-truth reads correctly against `lib/statifier_blocks/core/branch.ex`'s ordered arms.
- [ ] The five `status` values are each demonstrated by at least one test and each is named in the moduledoc.

**Machine-checked (unattended, 2026-08-29):** all three items checked by an agent, not a human.
Item 1 shares the defect and the fix recorded under Phase 1. The named ordering mutation was run
exactly as written: inverting `otherwise_column?/2`'s `%Column{source: nil}, nil -> true` clause
turned the otherwise-selection test red, and it was reverted. One honest negative: reversing the
cells *within* each row left `statuses/1`'s test green, because both fixture rows happen to be
status-uniform; reversing the whole flat-mapped result turned it red. The note records that.
Item 2 verified: `lib/statifier_blocks/core/branch.ex` emits one conditional transition per arm
in config order followed by an unconditional `otherwise`, which is what the moduledoc describes.
Item 3 verified: `:match`, `:mismatch`, `:unchecked`, `:error` and `:undecidable` are each named
in the moduledoc and each asserted in `truth_table_test.exs`.

The checkboxes above are deliberately left unticked: `plan_state.rb confirm` records a HUMAN
walking the item, and no agent may write it.

**Implementation Note**: same as Phase 1 - loop gate between edits, full gate
at the boundary, Manual items deferred under `--loop`.

---

## Testing Strategy

### Unit Tests:

- `test/statifier_blocks/predicates_test.exs` - one case per error-vocabulary
  row, plus `evaluate_value/1` across predicator's literal grammar (integer,
  string, boolean, duration `15m`, date `#2026-08-28#`) and `context/1`'s
  nesting, binding failure and conflict cases.
- `test/statifier_blocks/predicates/truth_table_test.exs` - spec validation,
  the four cell outcomes, the five statuses, the first-match-wins ordering
  case, the undecidable-after-error case, and row-level binding failure.

Key edge cases, each with a named test: `{:ok, :undefined}` from a cross-type
comparison; a non-boolean condition result; a binding written `"PT15M"`
(undefined variable, and the moduledoc's caution is the fix); two columns both
raw-true; an error in column 1 making columns 2 and 3 undecidable; an
`otherwise` column that is not last.

Every test asserting `lib/` behaviour is sabotaged before it is committed, with
the mutation named in a one-line comment above it. This is the repo's
`CLAUDE.md` convention and it is a Manual criterion in both phases because the
gate cannot read a comment.

### Manual Testing Steps:

1. `iex -S mix`, then run the "Desired End State" snippet verbatim and confirm
   each result.
2. Evaluate `Predicates.evaluate("transaction.amount > 500", %{})` and confirm
   `{:error, {:undefined_variable, "transaction", _}}` - the empty-context case
   an author hits first.
3. Build a table whose second column errors and read the third column's cell:
   confirm `status: :undecidable`, not `:match` or `false`.
4. `mix docs` and confirm both modules appear under "Predicate evaluation" in
   the sidebar rather than ungrouped.
5. Confirm `git diff` touches no file under `spike/`, `docs/adr/`,
   `lib/statifier_blocks/editor*` or `assets/`.

## References

- Bead: `sb-e3c`
- Ruling: campaign-014 pre-decision **D11** - predicate evaluation is server
  side, through predicator, via the LiveView editor; never a JS mirror of the
  grammar.
- `docs/adr/0002-block-type-behaviour.md:250` - decision 9/9a-9c, fixture
  bundles are statifier-ui's convention; `:322` - decision 10, `core.branch`'s
  ordered `arms` and `:expression` conditions.
- `docs/adr/0005-liveview-editor.md:336` - decision 9, `:expression` is a plain
  source input with a host-supplied override seam; `:567` - decision 15,
  per-palette-entry fixtures and rich expression editing are not decided here.
  (Decision 9's closing sentence says "Decision 12 records that as a deferral",
  but `:460`'s decision 12 is about unresolvable blocks. That looks like a
  stale internal cross-reference in the ADR; it is not this bead's to fix -
  `docs/adr/` is out of scope - and nothing in this plan rests on it.)
- `lib/statifier_blocks/core/branch.ex` - the shipped arm shape
  (`%{"slot" => ..., "cond" => ...}`) and the first-match-wins rationale.
- `lib/statifier_blocks/editor.ex:184-282` - the shipped `handle_event/3` set,
  evidence that no fixtures pane exists.
- `deps/predicator/lib/predicator.ex:178` - `evaluate/3`;
  `deps/predicator/lib/predicator/errors/` - the error structs.
- `spike/fixtures/runs.json` - `documents.<id>.tables`, the precomputed truth
  tables this bead replaces with real evaluation (read-only reference).
- `spike/fixtures/datamodel.json` - the typed datamodel, deferred here.
- Similar implementation, for plan and module shape:
  `docs/plans/260827-sb-ia5-editor-command-algebra-and-view-model.md`.
- `changelog.d/README.md` - the fragment convention.

---

## Open questions (recorded, not blocking)

No human was available while this plan was written. Each question below has a
decision taken for now, so the plan is executable as it stands; each is
recorded so the operator can overturn it cheaply.

1. **Does the typed datamodel earn a module?** Decided: no, deferred. Nothing
   in the evaluator or the builder consumes it, the spike's own stance is
   advisory ("unknown", never "wrong"), and an unconsumed public module fights
   the 90% coverage floor. If a later fixtures pane needs a path/type index,
   `StatifierBlocks.Predicates.Datamodel` is the name and
   `spike/fixtures/datamodel.json` is the shape. Worth a follow-up bead.

2. **Is the spike's `expected` really selection rather than raw truth?** This
   plan concludes yes, and builds the table around first-match-wins
   accordingly. The evidence is data, not a written record: the "Flagged for
   review" row in `spike/fixtures/runs.json` binds `risk_rating = 12` and
   `customer.verified = true`, so the low-risk arm's expression is raw-true,
   yet the row expects `arm_low_risk: false` and its own note says the
   first-declared arm wins. If the operator intends `expected` to mean raw
   expression truth, `Cell.selected?` still carries that reading and only the
   `status` comparison changes - a one-function edit.

3. **Should `fixtures/0`'s bundle shape feed the truth-table spec?** Not here.
   ADR-0002 decision 9 puts the bundle convention in statifier-ui and forbids a
   competing one in this package, and `TruthTable.build/2` deliberately takes a
   plain spec rather than a bundle. Whether a bundle-to-spec adapter belongs in
   this package at all is a statifier-ui-owned question that would need an
   ADR-0002 amendment, and `docs/adr/` is out of scope for this bead.

4. **Editor wiring.** No natural seam exists today (ADR-0005 decision 15;
   confirmed against `lib/statifier_blocks/editor.ex`). This plan lands the pure
   evaluator plus builder and documents the seam in the `Predicates` moduledoc.
   The wiring is to be recorded as a note on bead `sb-8dc`; the orchestrator
   writes that note, not this plan.

5. **The `:evaluation_error` fallback's reachability.** Phase 1 resolves this
   by probing predicator 9.0.1 for a source that yields a `TypeMismatchError`,
   `EvaluationError` or `LocationError`. If none is reachable from a binary
   source, the last clause widens to match any error struct and is proved with
   a reachable one; the tag stays, and the finding is recorded in the moduledoc.
   Flagged because the answer changes one line of code and the coverage story
   for that line.

**Machine-checked (unattended, 2026-08-29).** What an agent did with these; none is marked
settled, because a `**Settled**` note records a human and no agent may write one.

1. Typed datamodel module - still deferred, and now tracked rather than only recorded: bead
   `sb-oiq` filed and linked `discovered-from sb-e3c`, carrying the reserved name
   `StatifierBlocks.Predicates.Datamodel`, the datamodel shape, and the advisory-not-a-gate rule.
2. `expected` means selection, not raw truth - implemented as decided. The reading is backed by
   the accepted record, not only by the spike data: ADR-0002 decision 10 says `core.branch` takes
   the first arm whose condition holds. `Cell` carries both readings, so overturning it changes
   one comparison and no data. Left for the operator to confirm.
3. Bundle-to-spec adapter - untouched, out of scope; it needs an ADR-0002 amendment and
   `docs/adr/` is outside this bead.
4. Editor wiring - **done as specified**: recorded as a note on bead `sb-8dc` on 2026-08-29,
   naming the two modules, the D11 ruling, why no seam exists today (ADR-0005 decision 15,
   checked against `editor.ex`), and what a graduated pane inherits.
5. `:evaluation_error` reachability - resolved in Phase 1 and recorded in the moduledoc.

## Deferred Manual Verification

Manual verification items are deferred during looped (--loop) execution and
surfaced here once, rather than blocking after each phase. Confirm these
before considering the plan fully landed.

### Phase 1

- [ ] Every new test asserting `lib/` behaviour has been sabotaged - the covered code broken, the test confirmed red, the change reverted - and carries a one-line note above it naming the mutation.
- [ ] The moduledoc's "Where this is not wired" section names ADR-0005 decisions 9 and 15 and is accurate against `lib/statifier_blocks/editor.ex` as it stands.
- [ ] The `15m` / `PT15M` caution is present and correct.
- [ ] The `:evaluation_error` clause decision from item 4 is recorded in the moduledoc.

**Implementation Note**: Use `mix quality --profile loop` between edits; run
the full `mix quality` as the phase gate. In looped execution the Automated
Verification list gates advancement via `/wurk:commit --auto` and the Manual
items are deferred to `/wurk:verify`.

---

### Phase 2

- [ ] Every new test asserting `lib/` behaviour has been sabotaged and carries its one-line mutation note. In particular the selection pass: invert the first-match-wins guard, confirm the ordering test goes red, revert.
- [ ] The moduledoc's account of selection-versus-raw-truth reads correctly against `lib/statifier_blocks/core/branch.ex`'s ordered arms.
- [ ] The five `status` values are each demonstrated by at least one test and each is named in the moduledoc.

**Implementation Note**: same as Phase 1 - loop gate between edits, full gate
at the boundary, Manual items deferred under `--loop`.

---
