---
id: sb-djj5
title: "Run pane sends events from the selected block's fixtures palette"
date: 2026-09-06
status: draft
---

# Run pane send control Implementation Plan

## Overview

The Run pane gains a **send** control: a palette of fixture events for the
selected block, rendered by this package over
`StatifierUI.EventInjection`'s entries, that puts an event into a live
`Statifier.Session` without leaving the editor. Live streams only - over a
persisted stream (or with no session supplied) the control is drawn disabled
with the pane's own one-line note. The pane never writes to the document.
Bead: `sb-djj5`.

## Current State Analysis

`StatifierBlocks.Editor.RunPane` (`lib/statifier_blocks/editor/run_pane.ex`,
merged under `sb-xbyt`) composes statifier-ui's `status/1`, `scrubber/1` and
`event_log/1` around the canvas. Three properties of it bound this work:

- `run_pane/1` with `state: nil` renders **only** `{render_slot(@inner_block)}`
  - no wrapper, no class, no attribute - and `run_pane_test.exs` asserts that
  markup is byte-identical to a mount that never saw a run. That property must
  survive unchanged.
- Every statifier-ui module is reached dynamically: `component/1`
  (`run_pane.ex`, bottom) reads
  `Application.get_env(:statifier_blocks, :run_pane_module, StatifierUI.Live)`
  and checks `Code.ensure_loaded?/1` + `function_exported?/3`. The same
  discipline governs `StatifierBlocks.Runtime.Selection` (`:trace_inspector_module`)
  and `StatifierBlocks.Runtime.Marks`. Anything new this bead reaches into
  statifier-ui goes through the same door, under its own config key.
- The pane draws, with the package absent, a `<p class="sb-run__unavailable">`
  line. That is the idiom the disabled note reuses.

What is missing:

- **No send seam exists.** `grep -rn "Statifier.Session" lib/` finds only
  moduledoc prose; nothing in `lib/` holds a session server.
  `StatifierUI.Live.State` (`deps/statifier_ui/lib/statifier_ui/live/state.ex`)
  carries `machine`, `messages`, `selection`, `initial_configuration`, `stats`,
  `last_seq` and no session reference, deliberately: its moduledoc says a
  persisted and a live stream are the same struct and "no pane knows which it
  is looking at".
- **No live run fixture exists.** `test/support/card_run_fixtures.ex:110-146`
  (`run/0`) starts a real session, sends one event, collects the subscriber's
  messages, calls `Statifier.Session.stop(session)` and returns
  `State.new(machine, messages: messages)` - so today's shared fixture is
  persisted-shaped (`stats: nil`) and its session is dead.

## Desired End State

With a live run seated and a session supplied, selecting a block whose type
declares fixture events draws a row of buttons in the Run pane, one per event
name. Clicking one sends that event into the session through
`StatifierUI.EventInjection.send_draft/3`; when the host syncs the run from its
subscriber, the event log carries one more macrostep. Over a persisted stream,
or with no session, the same buttons are drawn `disabled` beside a one-line
note. No document message ever reaches the host's `on_change` because of a
send. With `statifier_ui` absent the pane still draws and the control is simply
not there.

Verified by: the LiveView tests in Phase 2 (a real `Statifier.Session`), the
existing byte-identity test in `run_pane_test.exs`, and `mix quality` including
the headless job.

### Key Discoveries:

- **The bead's parenthetical points at a source that carries no events.**
  The editor's `fixtures` assign is `%{block_id => [TruthTable.t()]}` -
  truth-table rows with `bindings`/`context`/`cells`. `grep -n event
  lib/statifier_blocks/predicates/truth_table.ex` returns nothing, and
  `lib/statifier_blocks/runtime/fixture_runs.ex:264-270` says so in a comment.
  The drawer/inspector Fixtures tab (`Editor.Inspector.block_runs/2`,
  `inspector.ex:676-680`, over `@fixture_runs`) is therefore **not** the
  palette source. See "Divergences from the bead's wording".
- **The implementable source is the selected block's type's `fixtures/0`.**
  `StatifierBlocks.Editor`'s private `fixture_events/1` (`editor.ex:1925-1933`)
  reads a type module's `fixtures/0` (`StatifierBlocks.BlockType`; the
  callback and its four accepted spellings are ADR-0002 decision 9/9a-9c,
  `docs/adr/0002-block-type-behaviour.md:267-317` - ADR-0011 decision 10 only
  cites it in passing for the on_event capture control) and pulls its `events` map in the two spellings this package can
  read without statifier-ui's loader (atom `:events`, string `"events"`).
  `capture_sources/1` just above it (`editor.ex:1907-1920`) is the precedent,
  resolving the block's module with `StatifierBlocks.Palette.resolve/2`.
  `lib/statifier_blocks/core/on_event.ex:376-383` and
  `lib/statifier_blocks/core/await.ex:220-226` declare such fixtures
  (`"order.cancelled"`, `"order.approved"`); `core/branch.ex` is the third.
- **Fixture event names are type-level examples, not the block's configured
  event.** `on_event.ex:370-373` says it outright. This is settled below under
  "The palette rule".
- **statifier-ui ships no HEEx component for `EventInjection`.**
  `deps/statifier_ui/lib/statifier_ui/event_injection.ex` is a pane *model*:
  `build/1` -> `%EventInjection{palette: %Palette{entries: [%Entry{name:,
  payload:, payload_text:}], diagnostics: []}, free_form_only?: bool}`,
  `entries/1`, `send/2`, `send_draft/3`. `StatifierUI.Fixtures.new/1`
  (`events: %{name => payload}`, string keys) builds its input. So this package
  renders the control's markup itself over plain data derived from `Entry`
  values.
- **A `nil` `stats` is statifier-ui's own persisted signal.**
  `deps/statifier_ui/lib/statifier_ui/live.ex:143-151` /
  `398-400`: `defp status_kind(nil), do: "persisted"`, surfaced as
  `data-status="persisted"`. `State.put_stats/2` and `State.sync/2`
  (`state.ex:127-149`) are how a live state gets one.
- **`send_event/2` is a cast.** `EventInjection`'s moduledoc says `:ok` means
  enqueued, not processed. The repo's discipline for that is bounded polling,
  never a sleep: `card_run_fixtures.ex:148-151` (`await_macrostep/2`) and
  `runtime_fixtures.ex:296-330` (`await_configuration/3`).
- **`render/1` derives the palette assigns.** `capture_sources` and its
  neighbours are computed in the `render/1` pipeline (`editor.ex:655-668`), so
  a `handle_event/3` cannot read them; it must re-derive from
  `socket.assigns`, the rule the `declared_view` comment at `editor.ex:640-648`
  already states for the drawer tab.
- **CSS vocabulary already exists.** `.sb-button`
  (`assets/css/statifier_blocks.css:557-600`) with the house disabled
  convention `.sb-button[disabled] { cursor: default; opacity:
  var(--sb-disabled-opacity); }` - the attribute selector, never `:disabled`
  (lines 583-585 say why). `--sb-disabled-opacity` is declared at :349 and
  inventoried at :125. The `.sb-run*` block is 4029-4147 and its section
  comment (4015-4028) limits how far this package styles `statifier-ui-*`
  descendants.

## What We're NOT Doing

- **No mapping from truth-table rows to events.** They carry none; inventing
  one is out of scope and would be a decision the bead did not ask for.
- **No per-palette-entry fixtures panel.** ADR-0005 decision 15 still defers
  it explicitly.
- **No free-form send.** `EventInjection`'s `free_form_only?` degraded mode is
  a form for typing a name and payload by hand. This bead is the palette; a
  free-form field is new authoring surface and is not asked for. With no
  entries, no control is drawn.
- **No payload editing.** Entries send their fixture's `payload_text`
  unmodified.
- **No write to statifier-ui, and no new wire type.** RQ-033-10's split holds:
  statifier-ui answers where a run is; this package answers which block that
  is.
- **The editor does not subscribe to the run.** After a send, `@run` is
  refreshed by the host, exactly as it is seated by the host today
  (`put_run/2`, `editor.ex:2241-2247`). Making the editor own a subscription
  would make it a trace client, which the `sb-xbyt` seam deliberately avoided.
  Recorded here rather than filed, because whether the pane should sync itself
  is a design question for a later bead (see Open questions).
- **No `mix.exs`, `drawer.ex` or `docs/adr/` change.** An ADR touch changes
  this PR's review gate; see Open questions for the one place a Note might be
  argued for.

### Divergences from the bead's wording

1. The bead says the palette is "fed by the selected block's fixture rows (the
   Fixtures tab already attaches rows to blocks)". Those rows are truth tables
   and carry no event name and no payload (evidence above). The palette is fed
   by the selected block's **type's** `fixtures/0` `events` map instead. The
   acceptance criteria are unaffected: a fixture row's event was never a thing
   that existed.
2. The dispatch describes reusing "`StatifierUI.EventInjection`'s palette
   component". statifier-ui ships no such component - only the pane model. This
   package renders the buttons and reuses statifier-ui for the palette *model*
   and the *send*, which is the part that must not be re-derived.

### The palette rule (settled)

Entries come **verbatim from the selected block's type's `fixtures/0` events
map**: one entry per event name, with that sample's `payload_text` as produced
by `StatifierUI.EventInjection.Palette`. No reconciliation with the block's
configured `event` field.

The alternative considered and rejected: taking the entry *name* from the
block's configured `event` and the payload from the type's sample, the posture
`payload_for/2` takes at `editor.ex:1938-1948` for capture sources. Rejected
because it invents a mapping the bead did not ask for, and because
`payload_for/2`'s job is different - it is choosing which *sample payload* to
mine for paths, not renaming an event. The cost of the verbatim rule is that a
type-level example may name an event the running chart is not waiting for; the
LiveView test therefore drives a document whose await block is configured for
`core.await`'s own sample name (`"order.approved"`), so the send is genuinely
handled and the macrostep it produces is not vacuous.

### Forced surface

The bead forces exactly one new public assign on the editor, because nothing in
`lib/` holds a session:

| assign | meaning |
|---|---|
| `run_session` | the live session the Run pane's send control puts events into: a `Statifier.Session.server()`, or `nil` (the default) for none. Held as editor state behind the same guard `run` uses, and cleared when the host opens a different document |

It is documented in `editor.ex`'s moduledoc attr table beside `run`
(`editor.ex:380`), normalized by a `put_run_session/2` mirroring `put_run/2`
(`editor.ex:2241-2247`), defaulted to `nil` in `mount/1` (`editor.ex:468`) and
cleared by `switch_document/2` beside `run` (`editor.ex:1542`). Nothing else
public is added: the palette derivation is private in `editor.ex` beside
`capture_sources/1`, and the pane's new attrs are attrs of an existing
component.

## Implementation Approach

Three phases, each independently committable and gate-verifiable:

1. **The live fixture first** (test support only), so the send test has a
   running session and a `stats`-carrying state to assert against, and so the
   cast-synchronization question is answered by code that already passes the
   gate before any feature depends on it.
2. **The feature**: the `run_session` assign, the private palette derivation,
   the pane's control, the send handler, the CSS, and the LiveView tests for
   all three acceptance criteria.
3. **The changelog fragment.**

Phase 1 leaves no dead lib code (it is test support with its own test); Phase 2
lands the feature complete, so no intermediate commit ships an enabled control
that does nothing.

## Phase 1: A live run fixture

### Overview

A sibling of `CardRunFixtures.run/0` that keeps its session alive and returns a
live-shaped `StatifierUI.Live.State`, over a document whose await block is
configured for `core.await`'s own fixture sample event.

### Changes Required:

#### 1. The fixture module

**File**: `test/support/live_run_fixtures.ex` (new)
**Changes**: `StatifierBlocks.LiveRunFixtures`, wrapped whole-file in
`if Code.ensure_loaded?(StatifierUI.Live.State) do ... end` - the wrapper
`card_run_fixtures.ex:1-6` uses and for its stated reason (the file names
`StatifierUI` at compile time and the headless tree has no such module).

```
# a core.sequence of two core.await blocks
#   core.await  blk_order_open   event: "order.approved"   <- the type's own sample
#   core.await  blk_order_done   event: "order.settled"
#
# @spec live() :: %{session: pid(), subscriber: pid(), machine: Machine.t(),
#                   provenance: Provenance.t(), state: State.t()}
# def live() -- compiles the document, starts a Subscriber, starts a
#   Statifier.Session with trace: true and subscribe: false, attaches, waits
#   for macrostep 1 with a bounded poll, and returns
#   State.new(machine, messages: ...) |> State.sync(subscriber)
#   (State.sync/2 pulls messages AND stats in one call, state.ex:144-149,
#   so the returned state is live-shaped: stats != nil).
#
# @spec sync(State.t(), pid()) :: State.t()          -- re-read after a send
# @spec await_macrostep(pid(), non_neg_integer()) :: :ok
#   -- bounded poll on "trace.macrostep_stable", copied from
#      card_run_fixtures.ex:148-151, never a sleep.
# @spec stop(map()) :: :ok                            -- Session.stop for on_exit
#
# plus document/0, palette/0, declare/0, open_block/0, sample_event/0
```

The blocks are `core.await` so the run stays *at* a block at the tip, the
reason `card_run_fixtures.ex`'s moduledoc gives for the same choice.

The live half has a precedent to follow rather than invent:
`StatifierBlocks.RuntimeFixtures.run/2` (`test/support/runtime_fixtures.ex:293-310`)
already starts a real `Statifier.Session` and hands it back for the caller to
drive with `await_configuration/3` and stop with `Statifier.Session.stop/1`.
This fixture is that shape plus the subscriber and the `State`.

#### 2. Its own test

**File**: `test/statifier_blocks/live_run_fixtures_test.exs` (new)
**Changes**: LiveView is never named here, but `StatifierUI` is, so the file
follows `card_run_fixtures.ex`'s guard shape (`Code.ensure_loaded?(StatifierUI.Live.State)`)
and **not** the `Phoenix.LiveView` wrapper - it is not a LiveView test.
Asserts: the returned session is alive; `state.stats` is not `nil`; sending the
sample event through `StatifierUI.EventInjection.send_draft/3` and re-syncing
produces exactly one more macrostep point (`StatifierUI.Live.State.points/1`
grows by one); `on_exit` stops the session.

### Success Criteria:

#### Automated Verification:
- [ ] Full quality gate passes (`mix quality`)
- [ ] `mix test test/statifier_blocks/live_run_fixtures_test.exs` passes
- [ ] The headless job compiles and passes: `STATIFIER_BLOCKS_HEADLESS=1 mix compile --warnings-as-errors && STATIFIER_BLOCKS_HEADLESS=1 mix test`
- [ ] `test/support/live_run_fixtures.ex` exists and its first line is the
      `Code.ensure_loaded?(StatifierUI.Live.State)` guard

#### Manual Verification:
- [ ] The fixture's chart really waits for the sample event (the run is at
      `blk_order_open` before the send, at `blk_order_done` after), read off
      the test's own assertions rather than assumed
- [ ] No stray sessions survive the suite (`mix test` twice in a row, no
      `session_id` collision warnings)

**Implementation Note**: Use `mix quality --profile loop` between edits; run
the full `mix quality` as the phase gate. In looped execution the Automated
Verification items gate advancement and the Manual items are deferred.

---

## Phase 2: The send control

### Overview

The `run_session` assign, the palette derivation, the pane's buttons, the send
handler, and the CSS - with the three acceptance tests.

### Changes Required:

#### 1. The palette derivation and the send handler

**File**: `lib/statifier_blocks/editor.ex`
**Changes**:

```
# moduledoc attr table, beside `run` (:380): the `run_session` row.
# mount/1 (:468): run_session: nil
# switch_document/2 (:1542): run_session: nil
# update/2 (:581): socket |> put_run(assigns) |> put_run_session(assigns)
#   put_run_session/2 mirrors put_run/2 (:2241-2247) - Map.has_key?(assigns,
#   :run_session), so a send_update saying nothing about it leaves it alone.

# render/1 pipeline (:655-668), beside capture_sources:
#   |> assign(:run_events, run_events(assigns))
#   |> assign(:run_sendable?, run_sendable?(assigns))

# private, beside capture_sources/1 and fixture_events/1 (:1907-1933):
@spec run_events(map()) :: [%{name: String.t(), payload_text: String.t()}]
# nil when no block is selected -> []. Otherwise block_by_id/2 +
# Palette.resolve/2 (capture_sources/1's exact opening), fixture_events/1 for
# the events map, then - dynamically - Fixtures.new(events: events) and
# EventInjection.build/1, and Entry values flattened to plain maps so nothing
# downstream names a statifier-ui struct. Any unresolvable step -> [].

@spec run_sendable?(map()) :: boolean()
# assigns.run_session != nil and assigns.run != nil and
# Map.get(assigns.run, :stats) != nil
# `Map.get/3` rather than a struct match, so this compiles in a tree with no
# statifier-ui - the discipline Runtime.Selection uses for the same reason.

@spec handle_event("run-send", %{"event" => String.t()}, socket) :: ...
# Re-derives run_events/1 and run_sendable?/1 from socket.assigns (the render
# pipeline's assigns do not exist here - editor.ex:640-648's rule), finds the
# entry by name, and calls EventInjection.send_draft(server, name,
# payload_text) through the dynamic resolver. No-op when not sendable, when
# the name is not in the palette, or when the module does not resolve. The
# socket is returned unchanged in every case: the document is never touched.
```

The two statifier-ui modules are resolved exactly as `component/1` and
`Runtime.Selection.inspector_module/0` resolve theirs, under two new
application-config keys with the shipped modules as defaults:

- `:event_injection_module`, default `StatifierUI.EventInjection`
  (`build/1`, `entries/1`, `send_draft/3` checked with `function_exported?/3`)
- `:fixtures_module`, default `StatifierUI.Fixtures` (`new/1`)

Both are documented where they are resolved - a comment beside the private
resolver in `editor.ex` - which is the convention the package already follows
(`lib/statifier_blocks/runtime/selection.ex:20-30` documents
`:trace_inspector_module` in the module that reads it; nothing documents these
keys centrally).

#### 2. The pane

**File**: `lib/statifier_blocks/editor/run_pane.ex`
**Changes**: three new attrs and one new region. The `state: nil` clause is
untouched, so the byte-identity property holds by construction.

```
attr(:events, :list, default: [],
  doc: "the send palette: `%{name:, payload_text:}` maps, already derived.")
attr(:sendable?, :boolean, default: false,
  doc: "whether this run can be sent to: a live stream with a session.")
attr(:send_event, :string, default: "run-send")

# inside the pane, immediately AFTER the existing `.sb-run__unavailable`
# paragraph (run_pane.ex:115-117) and before `.sb-run__stage`:
<div :if={@events != []} class="sb-run__send">
  <button :for={entry <- @events} type="button" class="sb-button"
          disabled={not @sendable?}
          phx-click={@send_event} phx-value-event={entry.name}
          phx-target={@target}>{entry.name}</button>
</div>
<p :if={@events != [] and not @sendable?} class="sb-run__unavailable">
  A persisted run has nothing to send to.
</p>
```

`disabled` is an attribute, matching the CSS convention. With no entries there
is no region at all, so a run over a block whose type declares no fixtures
looks exactly as it does today.

**File**: `lib/statifier_blocks/editor.ex` (render, :724)
**Changes**: `events={@run_events} sendable?={@run_sendable?}` on the
`<RunPane.run_pane>` call.

#### 3. CSS

**File**: `assets/css/statifier_blocks.css`
**Changes**: inside the existing `/* ---- run pane */` section (4029-4147), one
`.sb-run__send` rule - a flex row with `gap: var(--sb-space-half)` and
`flex-wrap: wrap`. Declared tokens only, so amendment 14e's both-directions
theming audit has nothing new to account for. The buttons carry `.sb-button`,
so the disabled treatment (`.sb-button[disabled]`, :583-588) is inherited and
no new disabled rule is written.

#### 4. Tests

**File**: `test/statifier_blocks/editor/run_pane_send_test.exs` (new)
**Changes**: `use StatifierBlocks.EditorLiveCase, async: false` (the sibling
tests install stand-ins at the same config keys), wrapped whole-file in
`if Code.ensure_loaded?(Phoenix.LiveView) do ... end` - **required**, the file
names LiveView at compile time (CLAUDE.md, "The headless compile guard for test
files"; precedent `drop_reason_test.exs`). `setup` deletes
`:run_pane_module`, `:event_injection_module` and `:fixtures_module` and
restores them `on_exit`, the shape `run_pane_test.exs:31-40` uses; `seat/2`
sends `run:` and `run_session:` through `Phoenix.LiveView.send_update/3` the
way `run_pane_test.exs:44-56` seats `run:`. Every test carries a
`# Sabotage:` comment naming the mutation that makes it fail, matching the file
beside it.

Tests:

1. *the live send* - `LiveRunFixtures.live/0`, seated with its session, the
   await block selected; count `.sb-run__log [data-macrostep]` rows; click
   `.sb-run__send button[phx-value-event="order.approved"]`; bounded-poll the
   subscriber to macrostep 2; re-seat with `LiveRunFixtures.sync/2`; assert the
   row count grew by exactly one.
2. *the document is untouched* - in the same flow, `refute_receive {:document,
   _}` (the case template's `on_change` channel, `editor_live_case.ex:171`).
3. *persisted is disabled* - `CardRunFixtures.run/0`'s state (`stats: nil`)
   seated with `run_session: nil`, an on_event/await block selected: the
   buttons render and every one matches `[disabled]`; the
   `.sb-run__unavailable` note is present.
4. *a session with a persisted state is still disabled* - the live session
   handed in beside a `stats: nil` state: still `[disabled]`. This is what pins
   the predicate to both halves rather than to the session alone.
5. *no entries, no region* - a block whose type declares no `fixtures/0`:
   no `.sb-run__send` element at all.
6. *no run, no change* - the existing byte-identity assertion in
   `run_pane_test.exs` still passes untouched (asserted by running it, not by
   duplicating it).

### Success Criteria:

#### Automated Verification:
- [ ] Full quality gate passes (`mix quality`), coverage floor included
- [ ] `mix test test/statifier_blocks/editor/run_pane_send_test.exs` passes
- [ ] `mix test test/statifier_blocks/editor/run_pane_test.exs` passes
      unchanged (the `state: nil` byte-identity property)
- [ ] The headless job compiles and passes:
      `STATIFIER_BLOCKS_HEADLESS=1 mix compile --warnings-as-errors && STATIFIER_BLOCKS_HEADLESS=1 mix test`
- [ ] `grep -c "Sabotage:" test/statifier_blocks/editor/run_pane_send_test.exs`
      equals the number of `test "` lines in the file
- [ ] `git diff --name-only` names no file outside
      `lib/statifier_blocks/editor.ex`,
      `lib/statifier_blocks/editor/run_pane.ex`, `test/`, and
      `assets/css/statifier_blocks.css`

#### Manual Verification:
- [ ] The buttons read as a palette rather than a toolbar, and the disabled
      note reads as an explanation rather than an error
- [ ] Over a persisted stream the disabled buttons are legible at
      `--sb-disabled-opacity` in both light and dark themes
- [ ] Sending from the editor and watching the log grow feels like one action,
      not two (a capture on a private port, the `sb-xbyt` posture)

**Implementation Note**: Use `mix quality --profile loop` between edits; run
the full `mix quality` as the phase gate. In looped execution the Automated
Verification items gate advancement and the Manual items are deferred.

---

## Phase 3: Changelog fragment

### Overview

One fragment for 0.21.0.

### Changes Required:

#### 1. The fragment

**File**: `changelog.d/sb-djj5.md` (new)
**Changes**: `### Added` and one line per user-visible change, present tense, no
nested bullets, long lines unwrapped - the format `changelog.d/README.md` fixes
and `changelog.d/sb-xbyt.md` demonstrates. Two lines: the `run_session` assign
and what the Run pane's send control does; and the live-only rule.

### Success Criteria:

#### Automated Verification:
- [ ] `test -f changelog.d/sb-djj5.md`
- [ ] The file's headings are drawn only from Added/Changed/Deprecated/Removed/Fixed/Security
- [ ] Full quality gate passes (`mix quality`) - no Elixir changed, so this is
      a no-op re-run rather than a new bar

#### Manual Verification:
- [ ] A reader who only calls the public API can tell what changed from the
      fragment alone

**Implementation Note**: CLAUDE.md's authority table allows a change touching
no Elixir code to commit on review of the diff alone; the gate is still run
because the phase is cheap to gate.

## Testing Strategy

### Unit Tests:

- `test/statifier_blocks/live_run_fixtures_test.exs` - the fixture itself: a
  live session, a `stats`-carrying state, and one macrostep per sent event.
  Not a LiveView test, so no `Phoenix.LiveView` wrapper; it does name
  `StatifierUI`, so it carries the `Code.ensure_loaded?(StatifierUI.Live.State)`
  guard `card_run_fixtures.ex` uses.
- `test/statifier_blocks/editor/run_pane_send_test.exs` - the six cases above,
  LiveView-cased and wrapped in the headless compile guard.
- Edge cases pinned: no block selected; a block whose type declares no
  fixtures; a fixture payload statifier-ui cannot encode (the entry is omitted
  and the rest of the palette survives - `Palette`'s documented behavior); a
  tree where `:event_injection_module` points at a module exporting nothing
  (the control is absent and the pane still draws).
- Determinism: `Statifier.Session.send_event/2` is a cast, so every assertion
  after a send is preceded by a bounded poll on the subscriber's messages
  (`await_macrostep/2`), never a sleep.

### Manual Testing Steps:

1. Mount the editor over a live session in the examples host, select an
   `core.await` block, and click its event button; watch the event log gain one
   macrostep and the run marks move.
2. Seat the same editor with a persisted stream: the same buttons are drawn
   disabled with the note, and clicking one does nothing.
3. Remove `statifier_ui` from the host's load path: the pane still draws, the
   canvas is still seated, and no send region appears.

## Verification (unattended pass, 2026-09-06)

The deferred-verification backlog for this plan was EMPTY - no
`/wurk:implement --loop` ran, so no stage wrote a Deferred Manual
Verification section. Under the campaign rule for that case, verification is
a machine-check of every acceptance criterion on the bead against the live
artefact, with the evidence recorded here. An agent never writes the
human-confirmed marker, so nothing below is ticked as confirmed.

**Machine-checked (unattended, 2026-09-06):** with a live session, choosing a
fixture row's event sends it and the log grows by one macrostep.
`run_pane_send_test.exs` "clicking a palette entry sends the event and the log
grows by one macrostep" drives a real `Statifier.Session` from
`StatifierBlocks.LiveRunFixtures.live/0`, clicks
`.sb-run__send button[phx-value-event="order.approved"]`, bounded-polls the
subscriber to macrostep 2, re-seats the run and asserts the `data-macrostep`
row count grew by exactly one. 5 tests, 0 failures.

**Defect found and fixed during this pass.** The macrostep-count assertion
alone could not tell a handled event from an ignored one: the engine stamps a
`trace.macrostep_stable` for an external event no transition matches, so the
count grows either way. The test was strengthened with a configuration
assertion - after the send the run is at `blk_order_done` and no longer at
`blk_order_open` - and `active?/2` was added beside it, reading the marks the
way `run_pane_test.exs` does. Proven non-vacuous by sabotage: sending a
deliberately unmatched event name in place of the entry's name left the
count assertion PASSING and failed only on
`assert active?(view, LiveRunFixtures.done_block())`. The sabotage was
reverted from a copy taken beforehand, and the suite is green again.

**Machine-checked (unattended, 2026-09-06):** with a persisted stream the
control is disabled. Two tests, because the predicate has two halves:
"a persisted stream with no session renders every button disabled" asserts
`.sb-run__send button` exists and `.sb-run__send button:not([disabled])` does
not, plus the `.sb-run__unavailable` note; "a live session beside a persisted
state still renders disabled" pins the `stats` half independently of the
session half.

**Machine-checked (unattended, 2026-09-06):** the pane never writes to the
document. "the document is never touched by a send" sends through the live
session and asserts `refute_receive {:document, _any}` on the case template's
`on_change` channel; the `"run-send"` handler returns `{:noreply, socket}`
unchanged on every path.

**Machine-checked (unattended, 2026-09-06):** the fixture's chart really waits
for the sample event (Phase 1's manual item). Established by the same
configuration assertion above: the run sits at `blk_order_open` before the
send and at `blk_order_done` after it.

**Machine-checked (unattended, 2026-09-06):** no stray sessions survive the
suite (Phase 1's manual item). `mix test` run twice back to back: 121
doctests, 2,361 tests, 0 failures both times, no `session_id` collision
warnings.

**Machine-checked (unattended, 2026-09-06):** the headless job. Reported green
by the implementing pass and re-run here as part of the full gate:
`STATIFIER_BLOCKS_HEADLESS=1 mix compile --warnings-as-errors` clean and
`STATIFIER_BLOCKS_HEADLESS=1 mix test` 0 failures, which is what proves the
two new statifier-ui modules are reached dynamically rather than at compile
time.

### Deferred to a human

- **Whether the send control reads as a palette.** Whether the buttons read as
  a palette rather than a toolbar, and whether the disabled note reads as an
  explanation rather than an error, is the operator's judgement.
- **Whether the disabled buttons are legible** at `--sb-disabled-opacity` in
  both light and dark themes.
- **Whether sending and watching the log grow feels like one action** rather
  than two - the standalone-editor gap open question 2 records.
- **Whether the changelog fragment tells a public-API reader what changed.**
- The three open questions below, which are decisions rather than checks.

## Open questions

Recorded rather than resolved, because no human was available. Neither blocks
implementation.

1. **Does this need an ADR Note?** `sb-xbyt` added a dated Note to
   `docs/adr/0005-liveview-editor.md` because the run pane's event log had to
   be reconciled with 1A's drawer rule. This bead adds an *affordance that
   writes to a run* inside that same pane. The judgement taken here is **no
   Note**: the pane's seat is already recorded, the control writes to a session
   and never to the document, ADR-0005 decision 15's deferral of a
   per-entry fixtures panel is respected, and 1A's own placement rule
   (`docs/adr/0005-liveview-editor.md:1968-1970`, "Content that is about one
   block does not [go to the drawer], whatever its shape") already answers
   where a per-block send palette belongs. If direction disagrees, the Note is a
   separate PR, because a `docs/adr/` touch changes this PR's review gate to
   the cold direction agent. **This is the one question worth an operator
   ruling before merge.**
2. **Should the pane sync the run itself after a send?** Today the host owns
   the trace subscription and re-seats `@run`; the editor sends and stops. An
   author using the editor standalone will see nothing happen until the host
   syncs. Filing a follow-up for an editor-owned subscriber (or a documented
   host recipe) is the operator's call; it is deliberately out of this bead.
3. **Is `run_session` the right assign name?** It pairs with `run` and reads
   correctly in the attr table. `run_server` was the alternative. No blocker
   either way, but renaming after a release is a breaking change.

## References

- Bead: `sb-djj5`
- Prior plan: `docs/plans/260906-sb-xbyt-run-pane.md`
- Pane: `lib/statifier_blocks/editor/run_pane.ex`
- Palette source: `lib/statifier_blocks/editor.ex:1907-1933`
  (`capture_sources/1`, `fixture_events/1`)
- Fixture declarations: `lib/statifier_blocks/core/on_event.ex:376-383`,
  `lib/statifier_blocks/core/await.ex:220-226`
- statifier-ui: `deps/statifier_ui/lib/statifier_ui/event_injection.ex`,
  `.../event_injection/palette.ex`, `.../event_injection/entry.ex`,
  `.../fixtures.ex`, `.../live/state.ex:127-149`, `.../live.ex:143-151`
- Test idioms: `test/statifier_blocks/editor/run_pane_test.exs`,
  `test/support/editor_live_case.ex:171`,
  `test/support/card_run_fixtures.ex:110-151`
- CSS: `assets/css/statifier_blocks.css:557-600`, `:4015-4147`
- Changelog format: `changelog.d/README.md`, `changelog.d/sb-xbyt.md`
- Related ADRs: `docs/adr/0005-liveview-editor.md` (decision 15),
  `docs/adr/0002-block-type-behaviour.md` (decision 9/9a-9c, the `fixtures/0`
  callback), `docs/adr/0011-typed-environment.md` (decision 10, the on_event
  capture control that `capture_sources/1` serves)
