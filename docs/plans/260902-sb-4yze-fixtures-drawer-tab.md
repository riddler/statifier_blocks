# Fixtures drawer tab Implementation Plan

## Overview

A fourth drawer tab, `:fixtures`, that lists every fixture row attached to the
document's blocks, runs each row through the **compiled** chart server-side,
and reports per-row PASS/FAIL against the row's expected outcome plus the
outcome slot the run actually took. An ADR-0005 amendment recording the tab
lands in the same pull request, Status **proposed** in the diff. Bead:
`sb-4yze`.

No new JavaScript. The package ships exactly two hooks
(`assets/js/statifier_blocks.js`, `assets/js/statifier_blocks_measure.js`) and
this work touches neither file; `test/statifier_blocks/assets_test.exs` already
holds that limit against the files, and the amendment restates it as
acceptance.

## Current State Analysis

**The drawer has three tabs.** `lib/statifier_blocks/shell.ex:69` types
`drawer_tab :: :tables | :findings | :declarations`; `shell.ex:160` lists
`@drawer_tabs [:tables, :findings, :declarations]` with the comment recording
that the list order is *also* the order `drawer_view/1` resolves an unchosen
tab in, and that the order is arrival order. `@drawer_titles` sits beside it.
`drawer_tabs/0` and `drawer_tab/2` are at `shell.ex:449-479`, `host_tabs/1` at
`shell.ex:490` (it rejects any host tab id colliding with the package's own),
and `drawer_view/1` at `shell.ex:806-918`.

**The panel dispatches per tab** in `lib/statifier_blocks/editor/drawer.ex`
around lines 240-260: a `cond` over `@host_tab`, `@view.tab == :findings`,
`@view.tab == :declarations`, and a `true ->` fall-through that draws the
truth-tables surface (`index_page/1`, `table/1`).

**The reserved place is named in the code.** The `drawer-tab` handler's comment
at `lib/statifier_blocks/editor.ex:758-765` says "The remaining reserved places
(fixture runs, the datamodel view) arrive as entries in `Shell.drawer_tabs/0`
and need no second handler." `drawer.ex`'s moduledoc says the same. This bead
consumes "fixture runs" and leaves "the datamodel view" for `sb-ouly`.

**Fixtures arrive built.** `shell.ex:34-49` and the editor's assigns table
(`editor.ex:333`) describe `fixtures` as
`%{block_id => [StatifierBlocks.Predicates.TruthTable.t()]} | nil`, where `nil`
means *no fixtures source at all*, a distinct state from a source holding
nothing. `Shell.tables_for/2`, `table_block_ids/1` and `table_count/1`
(`shell.ex:644-674`) are the existing readers.

**Nothing runs a chart from the editor today.** `lib/statifier_blocks/compiler/
chart.ex:141` is the only `Statifier.compile/2` call in `lib/`, and it compiles
to check, not to drive. `lib/statifier_blocks/runtime/subchart.ex` is the
package's first runtime module and its moduledoc sets the naming precedent:
`StatifierBlocks.Runtime.*` is "the half that runs", against the authoring half
that is everything else in `lib/`.

## Desired End State

Opening the drawer on the **Fixtures** tab shows one row per fixture row in the
document, grouped by the block the table is attached to, each carrying:

- the block id and the table name,
- the row name and its bindings,
- the outcome slot the row **expected** (the column the row declares
  `expected: true` for),
- the outcome slot the compiled chart actually **took**,
- a verdict: `pass`, `fail`, `row error`, `no expectation`, `not comparable`,
  or `unreached`.

The collapsed strip reads `Fixtures N`, where N is the number of fixture
**rows** in the document. A document with no fixtures source shows the
`sb-drawer__empty` copy the other tabs use. A document that does not compile
shows the compile findings instead of a run list.

`docs/adr/0005-liveview-editor.md` carries a new trailing
`## Amendment (2026-09-02): ...` section, Status **proposed**, and
`git diff origin/main -- docs/adr/` shows zero removed lines.

Verify: `mix quality` green; `git diff origin/main -- docs/adr/ | grep -c '^-[^-]'`
returns 0; `git diff origin/main --stat -- assets/js/` empty.

### Key Discoveries:

- **The four-function driving contract is already on the pinned dep.**
  `mix.lock` pins statifier 2.2.0 and `mix.exs` wants `~> 2.2`. No upstream
  blocker, no pin change. `deps/statifier/lib/statifier/testing/case.ex:1-30`
  names the closed ADR-0053 / ADR-0006 surface: `Statifier.compile/2`,
  `Statifier.initialize/2`, `Statifier.send_event/2`,
  `Statifier.active_leaf_states/1`.
- **`Statifier.Testing.Case` cannot be used from `lib/`.** It is an ExUnit case
  template (`use`-able only in a test), and its own moduledoc says no module in
  `lib/` outside `Statifier.Testing.*` may reference anything inside it. So the
  runtime code here calls the four functions **directly** - that *is* the
  ADR-0053 surface, not a way around it - and the tests may
  `use Statifier.Testing.Case` where it helps. Recorded in the amendment.
- **`initialize/2` alone drives a fixture row.** A `%TruthTable.Row{}` carries
  bindings and a context, never an event, and `core.branch` compiles to a
  compound state whose `initial` is a transient `pick` state
  (`lib/statifier_blocks/core/branch.ex:220-266`). The pick fires inside
  `initialize/2`'s macrostep, so no `send_event/2` is needed for the question
  this tab asks. `send_event/2` stays available for the day a row carries an
  event.
- **`:datamodel` and `Predicates.context/1` agree.**
  `Statifier.MachineState.new/2` (`deps/statifier/lib/statifier/machine_state.ex:513-530`)
  merges the `:datamodel` option and **raises `ArgumentError` unless every key
  is a string at every level** (`checked_datamodel!/1`, `:587`).
  `StatifierBlocks.Predicates.context/1` folds dotted paths into a nested
  **string-keyed** map (`lib/statifier_blocks/predicates.ex:133`), so
  `row.context` hands straight to `datamodel:`. The runner still guards the
  call, because a host builds these tables and a raise in a render path is a
  crashed editor.
- **The final configuration is not enough; `entered_states` is.** A branch arm
  is transient: the arm's child can be entered and left inside one macrostep,
  and the whole chart can reach its final state during `initialize/2`, leaving
  the configuration empty. `%Statifier.MachineState{}.entered_states` is the
  answer - its moduledoc (`machine_state.ex:94-125`) says it "accumulates
  across the whole session" and is "populated unconditionally - every entered
  state's index". It is the union of entered states as an integer-index MapSet;
  `Statifier.Machine.id/2` (`deps/statifier/lib/statifier/machine.ex:378`) maps
  an index to its string id and returns `nil` for a nameless state.
  Trace effects (`{:trace, %Statifier.Effect.Trace.EntrySet{}}` under
  `trace: true`) carry the same information as per-microstep deltas that the
  caller would have to union by hand into exactly the set `entered_states`
  already holds - so this plan reads the field and does not turn tracing on.
  Reading a field of a value the driver already holds is the same inspection
  `Statifier.Testing.Case` performs on `MachineState.active_leaf_states/1`
  and calls "not a fifth driving function".
- **Provenance maps states back to blocks.**
  `StatifierBlocks.Provenance.owners_of_states/2`
  (`lib/statifier_blocks/provenance.ex:120-127`) returns
  `%{block_id:, role:, config_key:}` owners and silently drops a state id it
  has never heard of.
- **A column key on a `core.branch` is the arm's slot name.**
  `Core.Branch.config_schema/1` (`branch.ex:70-90`) keys one `:expression`
  field per arm by that arm's slot name, and `slots/1` returns those same names
  followed by `"otherwise"`. That is what makes "which column did the row
  expect" comparable to "which slot did the chart take".
- **A compile failure is a first-class state.**
  `StatifierBlocks.Compiler.compile/3` (`lib/statifier_blocks/compiler.ex:302-320`)
  returns `{:ok, %StatifierBlocks.Compiled{}} | {:error, [%Finding{}]}`, never a
  raise. The document is being edited, so not compiling is normal.
- **Amendment-with-implementation precedent, verified.** Commit `cea57f1`
  ("Adds a declarations panel and a fifth command", bead `sb-d0nv`, PR 211)
  touched `docs/adr/0005-liveview-editor.md` *together with* `lib/statifier_blocks/
  shell.ex`, `lib/statifier_blocks/editor/drawer.ex`, `assets/css/statifier_blocks.css`,
  `changelog.d/sb-d0nv.md` and five test files in one commit; the section it
  added, `## Amendment (2026-09-01): decision 2, a fifth command, and the
  declarations panel` (line 4109), was drafted **proposed** there and flipped to
  accepted later in `ecf182b`. Same shape as this bead (a new drawer tab), and
  the one the amendment cites.
- **ADR-0005 decision 15's deferred seam**, at
  `docs/adr/0005-liveview-editor.md:608-632`, reads "**Per-palette-entry
  fixtures** - the 'test this step' panel ADR-0002 decision 9 sketched - wait on
  sui-13q, unchanged and still provisional". This tab is *not* that panel - it
  is document-level and tabular, which is 1A's admission test - and the
  amendment must say so explicitly so the deferral is narrowed rather than
  contradicted. The sui-13q convention doc is the read-only sibling
  `/Users/johnnyt/Dev/github/statifier/statifier-ui/docs/fixture-bundles.md`.
- **The headless guard.** ADR-0005 decision 1 wraps every LiveView module in
  `Code.ensure_loaded?(Phoenix.LiveView)` and a CI job proves the package
  compiles with LiveView absent. `Shell`'s moduledoc (`shell.ex:1-30`) states
  the rule: what is worth testing goes in `lib/statifier_blocks/`, unguarded.

## What We're NOT Doing

- **No per-palette-entry "test this step" panel.** ADR-0005 decision 15 defers
  that to sui-13q and this plan does not take it. The amendment narrows the
  deferral; it does not close it.
- **No fixture-bundle format.** ADR-0002 decision 9 puts that convention in
  statifier-ui. Tables still arrive built, through the existing `fixtures`
  assign, unchanged.
- **No new JavaScript, no hook-file edit, no third hook.** `assets/js/` is not
  in any file map below.
- **No declared-path view tab.** That is `sb-ouly`, and it takes the last
  reserved place.
- **No change to the truth-tables tab.** Its `status`, `tables` and `jumps`
  fields on `drawer()` keep their present meanings; nothing fixtures-flavoured
  is written into `status`.
- **No event-driven fixture rows.** A `%TruthTable.Row{}` carries no event
  today. `send_event/2` is named in the amendment as the seam for when one
  does; nothing here sends one.
- **No caching across mounts, no persistence.** The runs are recomputed from
  the document and are per-socket.
- **No `mix.exs` / `mix.lock` change.** The driving path is on the pinned dep.

## Implementation Approach

Three phases, in this order.

1. **The runner first, headless.** `StatifierBlocks.Runtime.FixtureRuns` is a
   pure function of `(document, palette, fixtures)` that compiles once and
   drives once per row. It lives outside the LiveView guard, under the
   `Runtime.*` namespace `runtime/subchart.ex` established, so the headless
   suite exercises the part that is worth testing. Committable and
   gate-verifiable on its own: a new module plus its own tests, consumed by
   nobody yet.
2. **The tab, in one commit.** Shell's tab list, the editor's memoized
   recompute, the drawer panel, the stylesheet and the LiveView tests land
   together. Splitting them would ship an intermediate where a tab labelled
   "Fixtures" renders the truth-tables panel, because `drawer.ex`'s `cond`
   falls through to it - green on the gate and wrong on the screen. The plan
   skill's rule is to combine rather than split in exactly that case.
3. **The amendment last.** It touches no Elixir code, so per this repo's
   `CLAUDE.md` it has no gate to run and commits on review of the diff alone.
   Ordering it last is deliberate: it is written from what shipped rather than
   from a shape guessed ahead of the code, which is what precedent `cea57f1`
   did, and it can name the module, the verdict vocabulary and the count
   exactly. All three commits go in one pull request, which is what ruling
   R27-9 asks for.

### The count on the strip is rows, not failures

Decided, and the amendment argues it. Two reasons.

The precedent is that the strip counts **content, not problems**: the truth
tables tab counts tables (`Shell.table_count/1`), the findings tab counts
findings, the declarations tab counts declaration entries. A tab whose chip
counted failures would read `Fixtures 0` for a document whose forty fixture
rows all pass, which is the exact defect 2A's strip exists to prevent - the
strip's job is to say what the drawer is holding.

The mechanical reason is decisive. `Shell.drawer_view/1` is called on **every**
render, and it resolves an unchosen tab to the first tab with a non-zero count.
A failure count is only knowable by compiling the document and running every
row; a row count is `Enum.sum` over the tables already in the assign. Counting
failures would put a full compile plus N chart runs inside every render of the
editor. So the count is rows, `Shell.fixture_row_count/1` is pure and cheap, and
`drawer_view/1` stays what it is.

### Where the runs live, and how they are memoized

Not on `drawer()`. `drawer_view/1` is pure, cheap and called per render, and
the runs are neither. The editor holds two new assigns, `:fixture_runs` and
`:fixture_runs_key`, and a private `refresh_fixture_runs/1` recomputes only
when all three of these hold:

- the drawer is open, and
- the resolved active tab is `:fixtures`, and
- the memo key differs from the stored one.

The memo key is the tuple `{document, palette, fixtures, declare}` compared with
`==`. It is exact rather than hashed: a `:erlang.phash2/1` collision would
render a stale verdict with nothing to say so, and a structural comparison is
still orders of magnitude cheaper than one compile plus N chart runs. The terms
are the ones already in assigns, so nothing is copied.

`declare` and **not** `host_roots`. The two are easy to confuse and only one of
them is the compiler's input. `declare` is the host's raw `{id, expr}` list, the
assign the assigns table at `editor.ex:324` describes as "the roots the host
will pass the compiler as `:declare`". `host_roots` is
`Datamodel.declared_roots(assigns.declare)` (`editor.ex:471`) - a derived
`MapSet.t(String.t())` of root **ids**, built for the undeclared-path
advisories. `Compiler.DeclaredRoots.declarations/1`
(`lib/statifier_blocks/compiler/declared_roots.ex:213-225`) accepts `nil` or a
list and answers anything else with
`{:error, [{:invalid_declaration, other}]}`, so passing the `MapSet` would fail
every compile and pin the tab to its `:compile_error` panel forever - green on
the gate, permanently wrong on the screen.

`refresh_fixture_runs/1` is appended to `rebuild/1`'s pipeline - the single
funnel every document, selection and config change already goes through
(13 call sites, including `update/2` at `editor.ex:503`) - and called from the
`drawer-open` and `drawer-tab` handlers, which do not go through `rebuild/1`.
That is "on tab open, and on document change while open", with nothing running
on an unrelated re-render.

---

## Phase 1: The runner - `StatifierBlocks.Runtime.FixtureRuns`

### Overview

A headless, unguarded module that turns `(document, palette, fixtures)` into a
list of per-row verdicts, by compiling the document once and driving the
compiled chart once per fixture row.

### File map

- `lib/statifier_blocks/runtime/fixture_runs.ex` - **new**. The module, its
  `%FixtureRuns{}` result struct, its nested `%FixtureRuns.Run{}` row struct,
  `run/4`, and the private compile / drive / attribute pipeline.
- `test/statifier_blocks/runtime/fixture_runs_test.exs` - **new**. Headless
  unit tests over every status and every verdict.

### Changes Required:

#### 1. The module and its two structs

**File**: `lib/statifier_blocks/runtime/fixture_runs.ex`
**Changes**: New module under the `Runtime.*` namespace, with no
`Code.ensure_loaded?(Phoenix.LiveView)` guard, so the headless suite runs it.
The moduledoc states three things: why it is `Runtime.*` (it drives a chart -
`runtime/subchart.ex`'s precedent), why it is unguarded (ADR-0005 decision 1
and `Shell`'s moduledoc rule), and why it calls the four `Statifier` functions
directly instead of `Statifier.Testing.Case` (a `use`-able ExUnit template
cannot be reached from `lib/`, and its own moduledoc forbids `lib/` referencing
`Statifier.Testing.*`; the four functions *are* the ADR-0053 surface).

```elixir
defmodule StatifierBlocks.Runtime.FixtureRuns do
  defmodule Run do
    @type verdict ::
            :pass | :fail | :row_error | :no_expectation | :not_comparable | :unreached

    @enforce_keys [:block_id, :table_name, :row_name, :verdict]
    defstruct [
      :block_id,
      :table_name,
      :row_name,
      :expected_slot,
      :taken_slot,
      :verdict,
      :detail,
      bindings: %{}
    ]
  end

  @type status :: :no_fixtures | :compile_error | :ready

  defstruct status: :no_fixtures, runs: [], findings: [], row_count: 0, failure_count: 0

  @spec run(Document.t(), Palette.t(), Shell.fixtures(), keyword()) :: t()
  def run(document, palette, fixtures, opts \\ [])
end
```

`opts` carries `:declare` - forwarded verbatim to `Compiler.compile/3`, default
`[]`, and it is the host's raw `{id, expr}` declaration **list**, never the
derived root-id `MapSet` the editor keeps as `host_roots`; the `@doc` says so,
because `Compiler.DeclaredRoots.declarations/1` answers a `MapSet` with
`{:error, [{:invalid_declaration, _}]}` and every compile would then fail - and
`:view_model` (an already-built `%ViewModel{}`; the editor always has one, and
the module builds its own with `ViewModel.build(document, palette, [])` when it
is absent).

#### 2. The three statuses

**File**: `lib/statifier_blocks/runtime/fixture_runs.ex`
**Changes**:

- `fixtures == nil` or every table empty and no block keyed -> `:no_fixtures`,
  `runs: []`. `nil` and an empty source answer alike here, exactly as
  `Shell.tables_for/2` already does; `drawer_view/1` is the only place that
  tells them apart and this module does not need to.
- `Compiler.compile/3` returns `{:error, findings}` -> `:compile_error`, with
  those `%Compiler.Finding{}` structs on `findings` and `runs: []`. The document
  is mid-edit; this is normal, not exceptional.
- otherwise `:ready`.

#### 3. Driving one row

**File**: `lib/statifier_blocks/runtime/fixture_runs.ex`
**Changes**: The compiled chart's `scxml` bytes are compiled **once** for the
whole document, then each row drives its own fresh machine state.

```elixir
# Per document, once.
{:ok, %Compiled{scxml: scxml, provenance: provenance}} =
  Compiler.compile(document, palette, declare: declare)
{:ok, machine} = Statifier.compile(scxml, chart_name: document.id)

# Per row.
{machine_state, _effects} = Statifier.initialize(machine, datamodel: row.context)
entered_ids =
  machine_state.entered_states
  |> Enum.map(&Statifier.Machine.id(machine, &1))
  |> Enum.reject(&is_nil/1)

entered_block_ids =
  provenance
  |> Provenance.owners_of_states(entered_ids)
  |> MapSet.new(& &1.block_id)
```

`Statifier.initialize/2` cannot fail - a `%Machine{}` is valid by construction -
but the `:datamodel` option can raise `ArgumentError` on a non-string key at any
depth, and a host builds these contexts. The call is wrapped so that a raise
becomes `verdict: :row_error` with the message on `detail`, never a crashed
editor. `Statifier.compile/2` on the emitted bytes is likewise handled: an
`{:error, _}` there is folded into `:compile_error` with a finding saying the
generated chart did not compile.

No `send_event/2` call. A `%TruthTable.Row{}` carries no event; the branch's
`pick` state is transient and fires inside `initialize/2`. A comment says so and
names `send_event/2` as the seam for an event-carrying row.

#### 4. Expected slot, taken slot, verdict

**File**: `lib/statifier_blocks/runtime/fixture_runs.ex`
**Changes**:

*Expected slot* - the `column_key` of the single cell in `row.cells` whose
`expected` is `true`. None -> `verdict: :no_expectation` (the row records raw
truth without declaring an arm; nothing to compare). More than one is
impossible under first-match-wins but is folded to `:no_expectation` with a
`detail` rather than raised on.

*Taken slot* - walk the fixture block's `%ViewModel.Node{}` slots **in
declaration order** (`slots/1`'s order, which is what `ViewModel` preserves) and
return the name of the first slot any of whose descendant blocks, at any depth,
is in `entered_block_ids`.

Three fallbacks, each deliberate:

- No slot matched **and** the block's own id is in `entered_block_ids` **and**
  exactly one slot is empty -> that slot, by elimination. This is the empty
  `otherwise` case, and it is sound: `Core.Branch.emit/2` targets an empty arm's
  transition straight at the block's `done` final (`branch.ex:283-284`), so an
  empty arm mints no state and can only be identified this way. Arms are
  `:at_least_one` and `otherwise` is `:any`, so at most one slot is ever empty
  in a valid document. Two or more empty slots -> `:not_comparable`.
- No slot matched and the block's own id is **not** entered ->
  `verdict: :unreached`. The chart never got to this block with this row's
  datamodel, which is a real finding about the fixture and not a failure of the
  arm.
- The expected slot names no slot the block declares -> `:not_comparable`. A
  host may attach a table to a block that is not a `core.branch`, and then a
  column key is not a slot name. Reported, not guessed at.

Otherwise `:pass` when `expected_slot == taken_slot`, `:fail` when they differ,
with both recorded on the run so the panel can show what was taken.

`row.error` (the bindings themselves failed to build a context) is checked
**first**, before any driving: `verdict: :row_error`, `detail` the reason. That
is the order `TruthTable`'s own moduledoc prescribes for a renderer.

`row_count` is every row across every table; `failure_count` is the runs whose
verdict is `:fail`. Both are computed here so no caller counts a list of its
own - the defect `Shell.findings_count/1`'s docstring records.

#### 5. Tests

**File**: `test/statifier_blocks/runtime/fixture_runs_test.exs`
**Changes**: `use ExUnit.Case, async: true` - **not** tagged `:liveview`, and
not `use StatifierBlocks.EditorLiveCase`, because the whole point of the
module's placement is that it runs headless. Build a two-arm `core.branch`
document with `Palette.core()`, and tables with
`Predicates.TruthTable.build/2`.

Cases: a passing row; a failing row (expects the other arm); a row whose
bindings error (`:row_error`); a row declaring no `expected: true`
(`:no_expectation`); a table attached to a `core.sequence`
(`:not_comparable`); a branch nested under an unreachable arm (`:unreached`);
an empty `otherwise` taken by elimination; `fixtures: nil` (`:no_fixtures`);
`fixtures: %{}` (`:no_fixtures`); a document that does not compile
(`:compile_error`, findings non-empty); `row_count` and `failure_count`.
Also: a row whose context reaches the chart, asserting the arm chosen actually
depends on the datamodel (the same document, two rows, two different taken
slots).

Every test asserting `lib/` behavior carries the repo's one-line sabotage note
above it, and each is actually sabotaged during the phase.

### Success Criteria:

#### Automated Verification:
- [x] `mix format` leaves no drift, then full `mix quality` is green (dialyzer,
      credo, deps audit and the coverage floor included). A `--profile loop` run
      is the inner loop and is never the evidence.
- [x] `test/statifier_blocks/runtime/fixture_runs_test.exs` exists and passes.
- [x] The headless tree still compiles and passes: the module is under no
      `Code.ensure_loaded?(Phoenix.LiveView)` guard and references no Phoenix
      module. `grep -rn "Phoenix" lib/statifier_blocks/runtime/fixture_runs.ex`
      returns nothing.
- [x] `git diff --stat -- assets/js/ mix.exs mix.lock` is empty.
- [x] Each new test asserting `lib/` behavior carries a one-line sabotage note,
      and each mutation was run red and reverted before the commit.

#### Manual Verification:
- [ ] The `:not_comparable` / `:unreached` split reads as the right vocabulary
      to a reviewer, rather than as two names for "we could not tell".
- [ ] The empty-`otherwise`-by-elimination inference is judged sound rather than
      clever.

**Machine-checked (unattended, 2026-09-02):** the inference's factual premise
holds. `Core.Branch.emit/2` builds
`[Emit.state(pick, nil, picks)] ++ transitions ++ refs ++ [Emit.final(done)]`
(`lib/statifier_blocks/core/branch.ex`), so an arm with no children
contributes no entry to `refs` and mints no state of its own; its transition
targets the block's final directly. An empty arm is therefore genuinely
unobservable in `entered_states`, which is what the by-elimination step
relies on. Whether the inference is *sound rather than clever* as a design
call is a judgement and stays deferred for a human.

**Implementation Note**: Use `mix quality --profile loop` between edits; the
full `mix quality` is the phase gate. In interactive execution, pause here for
the human to confirm the manual items. Under `--loop`, the Automated
Verification block gates advancement and the manual items are deferred.

---

## Phase 2: The tab - shell, editor, panel, stylesheet

### Overview

`:fixtures` becomes a real fourth tab: on the strip with its row count, wired
to a memoized recompute in the editor, and drawn by its own function component.

### File map

- `lib/statifier_blocks/shell.ex` - `@type drawer_tab` (`:69`) gains
  `| :fixtures`; `@drawer_tabs` (`:160`) becomes
  `[:tables, :findings, :declarations, :fixtures]` and its comment is extended
  with a sentence on why the new tab goes **last** (the list order is also the
  unchosen-tab resolution order and that order is arrival order, so a document
  with tables in it still opens where it always did); `@drawer_titles` gains
  `fixtures: "Fixtures"`; a new public `fixture_row_count/1`; `drawer_view/1`'s
  `own` list (`:846`) gains the `:fixtures` entry using it. `host_tabs/1`
  (`:490`) needs no edit but now reserves the id `"fixtures"` for the package -
  called out in its docstring.
- `lib/statifier_blocks/editor.ex` - `mount/1`'s `assign` block (`:400-420`)
  gains `fixture_runs: nil, fixture_runs_key: nil`; `rebuild/1` (`:1382`) gains
  `|> refresh_fixture_runs()` at the end of its pipeline; the `drawer-open`
  (`:752`) and `drawer-tab` (`:766`) handlers each pipe through it; a new
  private `refresh_fixture_runs/1`; the `drawer-tab` handler comment
  (`:758-765`) is rewritten to consume "fixture runs" and leave "the datamodel
  view" for `sb-ouly`; the assigns table (`:318-340`) gains a row for the
  `fixtures` assign's new second reader; `render/1` (`:551`) passes
  `fixture_runs={@fixture_runs}` down to the drawer.
- `lib/statifier_blocks/editor/drawer.ex` - a new
  `attr(:fixture_runs, :any, default: nil)`; the panel `cond` (`:~245`) gains a
  `@view.tab == :fixtures ->` branch **above** the `true ->` fall-through; a new
  private `fixture_runs/1` function component; the moduledoc's "Three tabs ship"
  paragraph gains the fourth and drops "Fixture runs still have a reserved
  place", keeping the declared-path view as the one that remains.
- `assets/css/statifier_blocks.css` - new structural `sb-fixtures__*` rules
  beside the existing `.sb-declarations__*` block (`:3565-3660`), modelled on
  it: `.sb-fixtures__scroll`, `.sb-fixtures__scroll table`, `th`/`td`, and
  `td[data-verdict="fail"]` / `[data-verdict="pass"]`. **Only tokens the
  stylesheet already declares** - `test/statifier_blocks/theme_audit_test.exs`
  fails on both a `var(--sb-*)` with no declaration and a declared token no rule
  reads, so no new `--sb-*` property is introduced.
- `test/statifier_blocks/shell_test.exs` - the tab list, the title, the count,
  the resolution order, and the host-tab id reservation.
- `test/statifier_blocks/editor/fixtures_tab_test.exs` - **new**. The LiveView
  tests.
- `test/support/editor_live_case.ex` - only if the existing `fixtures` session
  key proves insufficient. `StatifierBlocks.EditorHost.mount/3` already reads
  `session["fixtures"]` and passes it to the component, so the expectation is
  **no edit**; the file is listed so the phase is honest about where a change
  would go.
- `changelog.d/sb-4yze.md` - **new**, category `### Added`, one line, present
  tense, no nested bullets, per `changelog.d/README.md`.

### Changes Required:

#### 1. `Shell.fixture_row_count/1`

**File**: `lib/statifier_blocks/shell.ex`
**Changes**: Pure, total, and the single definition of the number the strip
carries - the same discipline `findings_count/1`'s docstring records.

```elixir
@doc """
How many fixture rows the whole source holds - the number the Fixtures tab's
strip carries.

Rows and not failures, and the reason is both editorial and mechanical. The
strip counts CONTENT, the way the tables tab counts tables and the findings
tab counts findings; a chip reading `Fixtures 0` over forty passing rows says
the opposite of what 2A's strip is for. And `drawer_view/1` runs on every
render: a row count is a sum over the assign, while a failure count would put
a compile plus one chart run per row inside every keystroke.
"""
@spec fixture_row_count(fixtures()) :: non_neg_integer()
def fixture_row_count(nil), do: 0

def fixture_row_count(fixtures) do
  Enum.reduce(fixtures, 0, fn {_id, tables}, acc ->
    acc + Enum.reduce(tables, 0, fn %TruthTable{rows: rows}, inner -> inner + length(rows) end)
  end)
end
```

#### 2. The memoized recompute

**File**: `lib/statifier_blocks/editor.ex`
**Changes**:

```elixir
# The runs are not on `drawer()` and not in `drawer_view/1`, deliberately.
# That function is pure, cheap and called on every render; a compile plus one
# chart run per fixture row is none of those. So the runs are their own
# assign, recomputed only when the drawer is OPEN on the fixtures tab and the
# inputs actually moved.
#
# The key is compared with `==` rather than hashed: a phash2 collision would
# render a stale verdict with nothing on screen to say so, and a structural
# comparison is still far cheaper than the work it is guarding.
@spec refresh_fixture_runs(Socket.t()) :: Socket.t()
defp refresh_fixture_runs(socket) do
  assigns = socket.assigns
  # The host's RAW `{id, expr}` list, which is what `Compiler.compile/3`'s
  # `:declare` takes. NOT `host_roots`, which is the derived MapSet of root
  # ids the advisories read - the compiler refuses it.
  declare = Map.get(assigns, :declare, [])
  key = {assigns.document, assigns.palette, assigns.fixtures, declare}

  cond do
    not assigns.drawer_open -> socket
    drawer_view(assigns).tab != :fixtures -> socket
    key == assigns.fixture_runs_key -> socket
    true ->
      socket
      |> assign(:fixture_runs, FixtureRuns.run(assigns.document, assigns.palette,
           assigns.fixtures, declare: declare, view_model: assigns.view_model))
      |> assign(:fixture_runs_key, key)
  end
end
```

`drawer_view(assigns)` is the existing private wrapper at `editor.ex:1326`; it
is called here because the active tab may be *resolved* rather than picked, and
resolution is its business and nowhere else's.

#### 3. The panel

**File**: `lib/statifier_blocks/editor/drawer.ex`
**Changes**: A branch in the `cond`, placed above `true ->` so the fixtures tab
never falls through to the truth-tables surface, and a function component that
renders one of three things off `@fixture_runs.status`:

- `:no_fixtures` (and `@fixture_runs == nil`) - a `<p class="sb-drawer__empty">`
  in the register the other tabs use: no fixtures source is attached, a host
  supplies them alongside the document.
- `:compile_error` - a `<p class="sb-drawer__empty">` saying the document does
  not currently compile, so no case can be run, followed by the findings'
  messages. An editor mid-edit reaches this constantly and it must not read as
  a failure of the fixtures.
- `:ready` - a table inside `.sb-fixtures__scroll`: Block, Table, Case,
  Expected, Taken, Verdict. Each `<td>` for the verdict carries
  `data-verdict={verdict}` so the tests select on data attributes rather than
  on copy, which is the convention `tray_test.exs` and `declarations_test.exs`
  follow.

#### 4. LiveView tests

**File**: `test/statifier_blocks/editor/fixtures_tab_test.exs`
**Changes**: `if Code.ensure_loaded?(Phoenix.LiveView) do` wrapper and
`use StatifierBlocks.EditorLiveCase`, following `tray_test.exs` and
`declarations_test.exs` exactly. `mount_editor(conn, document: ..., palette:
Palette.core(), fixtures: ...)`, then click the Fixtures tab
(`element(~s([phx-value-tab="fixtures"])) |> render_click()`).

The four the bead's acceptance names, plus three the design needs:

1. **pass** - a row whose expected arm is the one the chart takes renders
   `data-verdict="pass"` with the expected and taken slot equal.
2. **fail** - a row expecting the other arm renders `data-verdict="fail"` and
   shows the slot actually taken.
3. **no fixtures** - `fixtures: nil` shows the `sb-drawer__empty` copy and no
   run table.
4. **the count** - the strip reads the number of rows, not the number of
   failures; a document whose rows all pass still shows a non-zero chip.
5. the panel does not fall through to the truth-tables surface (no
   `.sb-table` element while the fixtures tab is active).
6. a document that does not compile shows the compile message, not a run list.
7. editing the document while the tab is open re-runs the rows (change a
   condition through the config form and watch a verdict flip).

Sabotage notes on every one of them.

### Success Criteria:

#### Automated Verification:
- [x] `mix format`, then full `mix quality` green.
- [x] `Shell.drawer_tabs/0 == [:tables, :findings, :declarations, :fixtures]`
      and `Shell.drawer_title(:fixtures) == "Fixtures"`, asserted in
      `shell_test.exs`.
- [x] `Shell.host_tabs/1` drops a host tab whose id is `"fixtures"`, asserted.
- [x] The four bead-named LiveView cases (pass, fail, no-fixtures, count) pass.
- [x] A LiveView test mounts with a **non-empty `declare`** assign and still
      reaches `status: :ready` with a `pass` verdict. This is the regression
      guard for the `declare` / `host_roots` confusion above: forwarding the
      derived `MapSet` makes `Compiler.compile/3` refuse every document, and
      without this case the tab would show its compile-error panel forever with
      the whole suite green.
- [x] `git diff origin/main --stat -- assets/js/` is empty, and
      `test/statifier_blocks/assets_test.exs` still passes (the two-hook limit
      held against the files).
- [x] `test/statifier_blocks/theme_audit_test.exs` passes (no orphan or
      undeclared `--sb-*` token from the new CSS).
- [x] `changelog.d/sb-4yze.md` exists, opens with `### Added`, and holds one
      unnested line.
- [x] Every new test asserting `lib/` behavior carries a sabotage note, each
      mutation run red and reverted.

#### Manual Verification:
- [ ] Browser check on a **private** port - never 8645, 8643, 8642 or 4002,
      which the campaign freeze holds - with captures written to
      `/Users/johnnyt/Dev/github/statifier/.claude/fleet/journal/027-screens/`.
      **Deferred: no human is available in this session.**

**Machine-checked (unattended, 2026-09-02): NOT TAKEN - still deferred.** The
capture was attempted and abandoned deliberately, not skipped. A scratch
`statifier_examples` worktree was stood up at
`/Users/johnnyt/Dev/github/statifier/statifier_examples-worktrees/sb-4yze-capture`
with `STATIFIER_BLOCKS_PATH` pointed at this worktree, its `config/dev.exs`
re-pointed off the frozen 8645 to **8650**, and a throwaway harness added to
`editor_live.ex` supplying three truth-table rows against
`blk_cp_risk_branch` (pass / fail / unbound-binding). The host compiled and
served `/editor` with HTTP 200 on 8650. The browser step was then abandoned
because the fleet's `chrome` resource lock is held by another agent
(`campaign=027 bead=W0 pid=27793 at=2026-09-02T13:03Z`), and contending for
a held lock is not permitted. The server was stopped and 8650 released;
8645/8643/8642/4002 were never touched. The harness is left on disk so the
capture is a two-command job once `chrome` frees:
`env STATIFIER_BLOCKS_PATH=... mix phx.server` in that worktree, then
capture to `027-screens/sb-4yze-*`. **Still owed to the operator/conductor.**
- [ ] The fixtures table stays readable at the drawer's minimum height (6 rem)
      without the horizontal scroll the drawer exists to avoid.
- [ ] The compile-error copy reads as a normal mid-edit state and not as an
      error the author caused.
- [ ] Typing in the config form with the tab open does not feel laggy on a
      document with many fixture rows (the memo doing its job).

**Machine-checked (unattended, 2026-09-02):** the memo is present and
correct. `refresh_fixture_runs/1` (`lib/statifier_blocks/editor.ex`)
short-circuits before any compile on three conditions - the drawer is
closed, the active tab is not `:fixtures`, or the key
`{document, palette, fixtures, declare}` is unchanged - so an unrelated
re-render performs no compile and no chart run. The
`re-runs the rows when a config-form edit moves the condition` test proves
the other half, that a real document change does invalidate the key.
Whether typing *feels* laggy on a large document is a human perception
check and stays deferred.

**Implementation Note**: Loop gate between edits, full `mix quality` as the
phase gate. Manual items deferred under `--loop`.

---

## Phase 3: The ADR-0005 amendment

### Overview

A purely additive `## Amendment (2026-09-02): ...` section appended to the end
of `docs/adr/0005-liveview-editor.md`, Status **proposed**, recording the tab a
direction agent will then review.

### File map

- `docs/adr/0005-liveview-editor.md` - **append only**. A new
  `## Amendment (2026-09-02): the drawer's fourth tab, fixture runs against the
  compiled chart` section after the file's current last section,
  `## Note (2026-09-01): decision 2, what amendment 2b's "clears it" means`
  (line ~4479, file is 4511 lines). **No line above it is edited.**

### Changes Required:

#### 1. The section

**File**: `docs/adr/0005-liveview-editor.md`
**Changes**: Append. Match the file's house style exactly - it uses em dashes
and a specific Status-line convention, and the repo rule is that house style
wins inside an existing file. Read
`## Amendment (2026-09-01): decision 2, a fifth command, and the declarations
panel` (line 4109) and
`## Amendment (2026-08-29): decision 10, slot_outcome_key` (line 1490) first
and follow their shape: Status line, an additive-and-nothing-above-is-edited
sentence, `### Context`, `### Proposed decision`, consequences.

Status line, proposed and not accepted:

```markdown
**Status: proposed (2026-09-02), drafted with the implementation it records,
implementing bead `sb-4yze`, campaign-027's Lane E.** Additive; decisions 1, 7,
14 and 15 stand as written and no text above this line is edited by this
section.
```

Content, all of it required by the bead:

- **What the tab is.** A fourth drawer tab, `:fixtures`, listing every fixture
  row attached to the document's blocks with a per-row verdict. It passes 1A's
  admission test - tabular, and about the whole document - the same test the
  findings and declarations tabs passed.
- **The data path**, named end to end: the `fixtures` assign
  (`%{block_id => [TruthTable.t()]} | nil`, unchanged) ->
  `StatifierBlocks.Compiler.compile/3` -> `Statifier.compile/2` on the emitted
  bytes -> `Statifier.initialize/2` per row with `datamodel: row.context` ->
  `%MachineState{}.entered_states` mapped through `Statifier.Machine.id/2` and
  `StatifierBlocks.Provenance.owners_of_states/2` -> the slot of the fixture's
  block that holds an entered descendant -> the verdict.
- **Why `initialize/2` alone, and why `entered_states` rather than the final
  configuration.** A branch arm is transient: it can be entered and left inside
  one macrostep and the chart can reach its final state during initialization,
  so the final configuration can miss the arm that was taken. `entered_states`
  "accumulates across the whole session"; reading it is the same inspection
  `Statifier.Testing.Case` performs on `MachineState.active_leaf_states/1` and
  is not a fifth driving function.
- **Why the driving code calls `Statifier`'s four functions directly.**
  `Statifier.Testing.Case` is an ExUnit case template - `use`-able only in a
  test - and its own moduledoc forbids any module in `lib/` outside
  `Statifier.Testing.*` from referencing it. The four functions **are** the
  closed ADR-0053 / ADR-0006 surface it names; `lib/` calls them, and the tests
  may `use` the template where it helps.
- **Where the runner lives, and why.**
  `StatifierBlocks.Runtime.FixtureRuns`, outside the
  `Code.ensure_loaded?(Phoenix.LiveView)` guard, on the same rule `Shell`
  follows: decision 1's headless CI job is what makes the guard trustworthy,
  and the part worth testing belongs where the headless tree can reach it. The
  `Runtime.*` namespace is `runtime/subchart.ex`'s precedent - the half that
  runs.
- **What counts in the strip: rows.** With both arguments - the strip counts
  content not problems (the tables tab counts tables, findings counts findings),
  and `drawer_view/1` runs on every render so a failure count would put a
  compile plus N chart runs inside every keystroke.
- **The drawer's `status` field is not overloaded.** `status`, `tables` and
  `jumps` on `drawer()` describe the truth-tables tab and keep their present
  meanings. The fixtures tab's own state is a separate editor assign, because
  it is neither pure nor cheap and `drawer_view/1` is both.
- **Decision 7's two-hook limit, restated as acceptance.** The package ships
  exactly two hooks, `StatifierBlocksDrag` and `StatifierBlocksMeasure`; this
  tab is server-rendered, adds no JavaScript, and edits neither hook file.
  `test/statifier_blocks/assets_test.exs` holds the limit against the files
  rather than against reviewer memory, and it is unchanged by this section.
- **Decision 15 is narrowed, not contradicted.** Cite it at
  `docs/adr/0005-liveview-editor.md:608-632`, quoting its bullet - "**Per-
  palette-entry fixtures** - the 'test this step' panel ADR-0002 decision 9
  sketched - wait on sui-13q, unchanged and still provisional" - and say
  plainly that this tab is not that panel: it is document-level and tabular,
  not per-palette-entry, it invents no fixture-bundle format, and the deferred
  per-entry pane stays deferred. Cite the sui-13q convention doc, statifier-ui
  `docs/fixture-bundles.md` (`StatifierUI.Fixtures` / `StatifierUI.Fixtures.Bundle`),
  as the convention this tab consumes rather than competes with.
- **The last reserved place.** `drawer.ex`'s moduledoc and
  `editor.ex:758-765` named two reserved places, "fixture runs, the datamodel
  view". This section takes the first. The read-only declared-path view is
  `sb-ouly`'s and is the one that remains.
- **The precedent for landing a proposed amendment with its implementation.**
  Name it by heading and PR: `## Amendment (2026-09-01): decision 2, a fifth
  command, and the declarations panel`, Status line "PR 211", bead `sb-d0nv`,
  landed as commit `cea57f1`, which carried
  `docs/adr/0005-liveview-editor.md` together with `lib/statifier_blocks/shell.ex`,
  `lib/statifier_blocks/editor/drawer.ex`, `assets/css/statifier_blocks.css`,
  `changelog.d/sb-d0nv.md` and five test files in one commit, and was flipped
  to accepted afterwards in `ecf182b`. Verified with `git show --stat cea57f1`.

### Success Criteria:

#### Automated Verification:
- [x] `git diff origin/main -- docs/adr/ | grep -c '^-[^-]'` returns `0`
      (zero removed lines under `docs/adr/`).
- [x] `git diff origin/main -- docs/adr/` shows added lines only, all of them
      after the file's previous last line.
- [x] The new section's Status line contains `proposed` and does not contain
      `accepted`.
- [x] The section cites `sui-13q` / `docs/fixture-bundles.md`, ADR-0005
      decision 15, and commit `cea57f1` / PR 211 / bead `sb-d0nv`.
- [x] No Elixir file is touched by this commit, so per this repo's `CLAUDE.md`
      there is no gate to run; the diff is the review. Running `mix quality`
      anyway costs only time and is not forbidden.

#### Manual Verification:
- [ ] The direction agent's review of the proposed amendment. **Deferred: this
      is the direction gate the bead names, and nothing in this plan may
      self-confirm it or flip the Status to accepted.**
- [ ] The section's prose matches the file's house voice, not this plan's.

**Machine-checked (unattended, 2026-09-02):** the mechanical half conforms.
The section is appended at the end of the file, opens with the same
`## Amendment (YYYY-MM-DD): ...` heading form as its neighbours, carries a
bold `**Status: proposed (2026-09-02) ...**` line in the established
convention, uses the file's em-dash punctuation rather than this plan's
hyphens, and closes with the file's customary "No decision moves, no clause
is edited" sentence plus the filing line. `git diff origin/main --
docs/adr/` reports **0** removed lines. Whether the *voice* matches is a
judgement and stays deferred for the direction agent.

**Implementation Note**: Docs-only. Ordered last so it records what shipped
rather than a shape guessed ahead of the code - the same order precedent
`cea57f1` used. All three phases land in one pull request, which is what ruling
R27-9 asks for.

---

## Testing Strategy

### Unit Tests:

- `test/statifier_blocks/runtime/fixture_runs_test.exs` (headless, `async: true`,
  **not** `:liveview`-tagged) - every status (`:no_fixtures`, `:compile_error`,
  `:ready`) and every verdict (`:pass`, `:fail`, `:row_error`,
  `:no_expectation`, `:not_comparable`, `:unreached`), plus the empty-`otherwise`
  elimination, `row_count` and `failure_count`.
- `test/statifier_blocks/shell_test.exs` - the tab list and its order, the
  title, `fixture_row_count/1` against `nil` / `%{}` / a populated source, the
  unchosen-tab resolution putting fixtures last, and the `"fixtures"` host id
  reservation.
- `test/statifier_blocks/editor/fixtures_tab_test.exs` (guarded,
  `use StatifierBlocks.EditorLiveCase`) - the seven cases in Phase 2.
- Unchanged and load-bearing: `test/statifier_blocks/assets_test.exs` (the
  two-hook limit) and `test/statifier_blocks/theme_audit_test.exs` (the token
  audit). Both must stay green without edits.

Edge cases that must each have a test: `fixtures: nil` vs `fixtures: %{}`; a
table on a block the document no longer holds; a row whose bindings error; a
document that does not compile; a fixture block never reached by the run; an
empty `otherwise` arm.

### Manual Testing Steps:

1. Start the dev host on a **private** port - not 8645, 8643, 8642 or 4002.
2. Open a document with a `core.branch` and a fixtures source attached; confirm
   the collapsed strip reads `Fixtures N` with N the row count.
3. Open the tab; confirm one line per row, with the expected slot, the taken
   slot and a verdict.
4. Edit an arm's condition so a passing row should now fail; confirm the verdict
   flips without a reload.
5. Break the document so it does not compile; confirm the compile message
   replaces the run list and does not read as an error the fixtures caused.
6. Detach the fixtures source; confirm the empty-state copy.
7. Capture 2, 3, 4 and 5 into
   `/Users/johnnyt/Dev/github/statifier/.claude/fleet/journal/027-screens/`.

All seven are **deferred**: no human is available in this session, and the
capture step is the bead's own acceptance item.

## Open questions

**Machine-checked (unattended, 2026-09-02):** no question below is *settled* -
settling one is a human's call and none carries a `**Settled**` marker. What
an unattended pass could do was re-verify each decision's load-bearing factual
premise against the tree, and all of them hold: the strip count is
`Shell.fixture_row_count/1` and `drawer_view/1` calls it per render (so a
failure count really would put a compile in every keystroke); an empty arm
mints no state in `Core.Branch.emit/2` (the by-elimination premise); and
`:datamodel` takes `row.context` unchanged. The decisions themselves remain
for the direction gate.

Every one of these was **decided** so the plan is actionable without a human.
They are recorded because no human was available to rule on them, and each is a
thing the direction gate on the proposed amendment should confirm or reverse.
None blocks implementation.

1. **Rows or failures in the strip?** Decided: **rows**. Precedent (the strip
   counts content) and mechanics (`drawer_view/1` runs per render, and a failure
   count is not computable without compiling) both point the same way. The
   amendment argues it; a reviewer who wants failures instead is changing a
   documented decision, not fixing an oversight.
2. **A table attached to a non-`core.branch` block.** Decided:
   `verdict: :not_comparable` rather than an error or a silent skip. A host may
   legitimately attach a table anywhere, and a column key is only a slot name on
   a branch.
3. **The empty-`otherwise` inference.** Decided: when exactly one slot is empty
   and the block itself was entered but no slot's descendant was, that empty
   slot is the one taken. It is sound for `core.branch` (`emit/2` targets an
   empty arm straight at the block's final, minting no state) but it is an
   inference, and two or more empty slots fall back to `:not_comparable`.
4. **Selection-awareness.** Decided: the fixtures tab is **document-level** and
   ignores the selection, unlike the truth-tables tab. The bead says "every
   fixture row attached to the document's blocks", and 1A's admission test is
   "about the whole document".
5. **Does `drawer()` gain a field?** Decided: **no**. The runs are their own
   editor assign; `status`, `tables` and `jumps` stay the truth-tables tab's.
6. **Recompute trigger.** Decided per the bead: on tab open and on document
   change while open, memoized on `{document, palette, fixtures, host_roots}`.
   Not a manual "Run" button.
7. **Long or non-terminating runs.** Decided: no cap beyond
   `Statifier.MachineState`'s own `max_macrostep_rounds` default of 10 000. A
   process-less run fires no timers and executes no effects - `initialize/2`
   returns an effect list that nobody runs - so a chart with a `core.wait` or a
   `core.invoke` simply parks. If a real document ever makes the tab slow, that
   is a bead, not a guess encoded here.

## References

- Bead: `sb-4yze` (campaign 027, W0, Lane E; ruling R27-9)
- ADR being amended: `docs/adr/0005-liveview-editor.md` (decision 1 the headless
  guard, decision 7 the hook limit, decision 14 the `sb-` prefix, decision 15
  the deferred per-entry fixtures pane at `:608-632`)
- Related ADRs: `docs/adr/0002-block-type-behaviour.md` decision 9 (the
  fixture-bundle convention is statifier-ui's), `docs/adr/0004-compiler.md`
  (the compile artifact and the provenance map)
- Sibling convention, read-only:
  `/Users/johnnyt/Dev/github/statifier/statifier-ui/docs/fixture-bundles.md`
  (sui-13q)
- Upstream contract: `deps/statifier/lib/statifier/testing/case.ex:1-30`
  (ADR-0053's four-function surface),
  `deps/statifier/lib/statifier/machine_state.ex:94-125` (`entered_states`),
  `deps/statifier/lib/statifier/machine.ex:378` (`Machine.id/2`)
- Amendment-with-implementation precedent: commit `cea57f1`, PR 211, bead
  `sb-d0nv`, section at `docs/adr/0005-liveview-editor.md:4109`; accepted
  afterwards in `ecf182b`
- Similar implementation: `lib/statifier_blocks/editor/declarations.ex` and its
  tab wiring; `lib/statifier_blocks/runtime/subchart.ex:18-40` (the `Runtime.*`
  naming precedent)
- Follow-on: `sb-ouly`, the declared-path view tab, which takes the last
  reserved place

## Deferred Manual Verification

Manual verification items are deferred during looped (--loop) execution and
surfaced here once, rather than blocking after each phase. Confirm these
before considering the plan fully landed.

### Phase 1

- [ ] The `:not_comparable` / `:unreached` split reads as the right vocabulary
      to a reviewer, rather than as two names for "we could not tell".
- [ ] The empty-`otherwise`-by-elimination inference is judged sound rather than
      clever.

**Implementation Note**: Use `mix quality --profile loop` between edits; the
full `mix quality` is the phase gate. In interactive execution, pause here for
the human to confirm the manual items. Under `--loop`, the Automated
Verification block gates advancement and the manual items are deferred.

---

### Phase 2

- [ ] Browser check on a **private** port - never 8645, 8643, 8642 or 4002,
      which the campaign freeze holds - with captures written to
      `/Users/johnnyt/Dev/github/statifier/.claude/fleet/journal/027-screens/`.
      **Deferred: no human is available in this session.**
- [ ] The fixtures table stays readable at the drawer's minimum height (6 rem)
      without the horizontal scroll the drawer exists to avoid.
- [ ] The compile-error copy reads as a normal mid-edit state and not as an
      error the author caused.
- [ ] Typing in the config form with the tab open does not feel laggy on a
      document with many fixture rows (the memo doing its job).

**Implementation Note**: Loop gate between edits, full `mix quality` as the
phase gate. Manual items deferred under `--loop`.

---

### Phase 3

- [ ] The direction agent's review of the proposed amendment. **Deferred: this
      is the direction gate the bead names, and nothing in this plan may
      self-confirm it or flip the Status to accepted.**
- [ ] The section's prose matches the file's house voice, not this plan's.

**Implementation Note**: Docs-only. Ordered last so it records what shipped
rather than a shape guessed ahead of the code - the same order precedent
`cea57f1` used. All three phases land in one pull request, which is what ruling
R27-9 asks for.

---
