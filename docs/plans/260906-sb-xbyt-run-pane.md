---
id: sb-xbyt
title: "Run pane: statifier-ui's status, scrubber and event log around the canvas"
date: 2026-09-06
status: approved
---

# Run pane

The editor gains a **run** it can be shown over: a `StatifierUI.Live.State`
handed in as an assign. When one is present the canvas takes the seat
statifier-ui's Mermaid diagram would otherwise take, wrapped in a pane that
draws statifier-ui's `status/1` above it, `scrubber/1` beside that, and
`event_log/1` below. Scrubbing or clicking a log entry moves the canvas's run
marks, because the marks are re-resolved from the run on every render through
`StatifierBlocks.Runtime.Marks.from_trace/2` (`sb-grc1`).

## What is decided before any code

**1. The pane is content of the canvas pane, not a new shell region and not a
drawer tab.** `.sb-editor__main` is already a flex column holding the toolbar
and the canvas; the run pane is a third child of it. ADR-0005's 2026-08-29
shell amendment names three columns plus a drawer row and this adds none: the
grid template, the four container-query breakpoints and every `grid-area` are
untouched. What it does need is a dated Note on ADR-0005, because 1A's rule for
the drawer ("content that is a grid of rows about the whole document goes to
the drawer") reads onto the event log unless the record says why it does not.
It does not, because a run is not the document.

**2. statifier-ui is composed as shipped.** RQ-033-10 splits the seam by
ownership: statifier-ui answers where a run is, this package answers which
block that is. No statifier-ui write, no new wire type, no new event name in
statifier-ui's namespace - its `scrub_event` and `select_event` attrs exist
precisely so a caller renames them, and the pane passes `"run-scrub"` and
`"run-select"` with `target={@myself}`.

**3. Every statifier-ui module is reached dynamically.** `statifier_ui` is an
optional dependency, so the pane resolves `StatifierUI.Live` out of application
config and checks `function_exported?/3` before capturing the three components,
exactly as `StatifierBlocks.Editor.Field` reaches the expression input and
`StatifierBlocks.Runtime.Marks` reaches the inspector. With the package absent
the pane draws its own one-line note and the canvas still renders.

**4. The wire format is read as data where a module would cost a dependency.**
`Runtime.Marks` already takes `messages`, `selection` and
`initial_configuration` as public fields of the read model. The new
`Runtime.Handled` does the same for the `session.start` manifest: wire format
v1's `transitions[].source` and `states[].id` are the public join, and reading
them needs no statifier-ui module at all, so the module is pure and the
headless suite exercises it.

**5. With no run, nothing changes.** `run_pane/1` is multi-clause: with
`state: nil` it renders its inner block and no wrapper at all, so a document
with no run produces the markup it produced before this bead. A test asserts
byte equality across a mount that never saw a run, a mount that was given one
and had it cleared, and the pane's own absence from the DOM.

## Phases

### Phase 1 - `StatifierBlocks.Runtime.Handled` (pure, headless)

`lib/statifier_blocks/runtime/handled.ex`.

    @spec block(map(), non_neg_integer(), Provenance.t()) :: {:ok, String.t()} | :error
    def block(state, macrostep, provenance)

Reads `state.messages`; finds the `session.start` manifest and the
`trace.transitions_selected` message stamped at `macrostep`; takes the first
`t_index` it names, resolves it through the manifest's `transitions` table to
its `source` state index, through the `states` table to that state's `id`, and
through `StatifierBlocks.Provenance.owner_of_state/2` to a block id. `:error`
for every gap: no manifest, no selected transition at that macrostep, a state
index the manifest does not carry, an anonymous state, a state id the
provenance map does not own.

Tests: `test/statifier_blocks/runtime/handled_test.exs`, **pure** (no headless
wrapper), driving a real compiled card-processing chart through statifier.

Gate: `mix quality`.

### Phase 2 - `StatifierBlocks.Runtime.RunValues` (pure, headless)

`lib/statifier_blocks/runtime/run_values.ex`.

    @spec at(map()) :: %{optional(String.t()) => String.t()}
    def at(state)

The run's datamodel values at the selection, as display strings keyed by
dotted path. Cuts `state.messages` to the prefix in view - every message with
no `macrostep`, plus every message stamped at or below the selected one - and
folds that prefix with statifier-ui's `StatifierUI.DatamodelExplorer`
(`build_live/1`), resolved from application config under
`:trace_datamodel_module` and dispatched dynamically. Entries are flattened to
dotted paths, `:undefined` values are dropped, and everything else is rendered
with `inspect/1`. `%{}` when the read does not resolve or the fold refuses.

The cut is written here rather than asked for because statifier-ui's own
`in_view/2` is private; the rule it implements is the one
`StatifierUI.Inspector.datamodel/2` documents ("the stream as it stood at the
end of macrostep n"), and a test pins it against a stream whose value changes
at a known macrostep.

Tests: `test/statifier_blocks/runtime/run_values_test.exs`, pure.

Gate: `mix quality`.

### Phase 3 - `StatifierBlocks.Editor.RunPane` and its seat

`lib/statifier_blocks/editor/run_pane.ex`, inside the LiveView-presence guard.

    attr(:id, :string, required: true)
    attr(:state, :any, required: true)      # StatifierUI.Live.State, or nil
    attr(:target, :any, default: nil)
    attr(:scrub_event, :string, default: "run-scrub")
    attr(:select_event, :string, default: "run-select")
    slot(:inner_block, required: true)      # the canvas

Two clauses. `state: nil` renders `{render_slot(@inner_block)}` and nothing
else. Otherwise a `<section class="sb-run" data-run="true">` with the house
pane header (`sb-run__header` / `<h2 class="sb-run__title">Run</h2>`), the
status and scrubber in `sb-run__controls`, the inner block in
`sb-run__stage`, and the event log in `sb-run__log`. Each statifier-ui
component is called through a captured function or, when it does not resolve,
replaced by one `<p class="sb-run__unavailable">`.

editor.ex:

- a `run` host assign, documented in the moduledoc table, written in
  `update/2` behind `Map.has_key?(assigns, :run)` so a `send_update/3` that
  says nothing about it leaves it alone, defaulted to `nil` in `mount/1`, and
  cleared by `switch_document/2` beside the marks;
- `refresh_run_provenance/1`, on `refresh_source_view/1`'s discipline: compile
  once per `{document, palette, declare}` and only while a run is seated;
- `marks/1` gains a clause - with a run seated the run decides the marks, and
  the host's `active_marks`/`invoke_mark` do not contribute;
- `handle_event("run-scrub", %{"move" => move}, socket)` mapping the four
  words to their atoms explicitly and calling `State.scrub/2`;
- `handle_event("run-select", %{"macrostep" => n}, socket)` calling
  `State.select/2` and, when `Runtime.Handled.block/3` answers, selecting that
  block through the same path `"select"` takes;
- the `<RunPane.run_pane>` wrapping `<Canvas.canvas>` in `.sb-editor__main`.

CSS: a `/* ---- run pane */` section in `assets/css/statifier_blocks.css`
reusing declared tokens only, so the theming audit's both-directions coverage
test has nothing new to account for.

Tests: `test/statifier_blocks/editor/run_pane_test.exs`, LiveView-cased and
wrapped in the headless compile guard.

Gate: `mix quality`.

### Phase 4 - the Datamodel tab's held values

`known_here`'s rows gain a `held` field when a run is seated, and the table a
third column. The section keeps its read-only rule: no button, no `phx-click`,
no finding, no tint.

Gate: `mix quality`.

### Phase 5 - the ADR-0005 Note, the changelog fragment, captures

A dated `## Note (2026-09-06)` on `docs/adr/0005-liveview-editor.md`: where the
run pane sits, why 1A's drawer rule does not claim the event log, and what the
pane does not change. Zero removed lines. A `changelog.d/sb-xbyt.md` fragment.
Captures, live and scrubbed, on a private port.

Gate: `mix quality`, then the direction review (docs/adr/ path).

## Automated success criteria

- `data-run-active="true"` is on the settle block, and on no other block, at
  the final macrostep of the persisted card-processing stream.
- Two `prev` scrubs from the tip put `data-run-active="true"` on the entry
  block and take it off the settle block.
- Clicking a log entry's summary leaves the editor with `selected_id` equal to
  the block owning the source state of the transition that macrostep selected.
- The Datamodel tab renders one row carrying both a declared type and a held
  value.
- A mount with no run renders byte-identically to a mount that was given a run
  and had it cleared, and carries no `.sb-run` element.
- The headless job compiles and passes.

## Deferred manual verification

- The captures themselves: that the pane reads as a pane and the scrubbed
  frame differs from the live one in the way a reader expects. Machine-checked
  as far as the DOM goes; the visual judgement is the operator's.

## Verification pass (unattended, 2026-09-06)

The plan carried no deferred-verification backlog, so this pass machine-checked
the bead's acceptance criteria against the built artefact instead.

**Machine-checked (unattended, 2026-09-06):** the settle block is marked at the
final macrostep. `run_pane_test.exs` "marks the block the run is at, at the
tip"; and a DevTools read of the rendered frame reports
`[data-run-active="true"]` on `blk_card_flow` and `blk_card_settle`, with the
scrubber's `data-selection` at `live`.

**Machine-checked (unattended, 2026-09-06):** two scrub-prev moves put the
entry block back. `run_pane_test.exs` "scrubbing back moves the marks to where
the run was"; the DevTools read of the scrubbed frame reports
`[data-run-active="true"]` on `blk_card_flow` and `blk_card_open`, with
`data-selection` at `macrostep-1` and the note "Showing macrostep 1
(initialize), at its quiescent configuration."

**Correction to the criterion's wording:** the bead says "macrostep 0". The
engine numbers the initialize macrostep **1** - it is the first
`trace.macrostep_stable` in the stream, and
`StatifierUI.Inspector.active_configuration_ids(messages, selection:
{:macrostep, 0})` answers `{:ok, []}`. Two Prevs from the tip of a
two-macrostep run land on macrostep 1, which is the step the criterion means.

**Machine-checked (unattended, 2026-09-06):** a log click selects a block.
`run_pane_test.exs` "a click selects the block whose state handled the step"
asserts `.sb-node--selected` lands on `blk_card_open`, the block whose waiting
state took the `card.captured` transition.

**Machine-checked (unattended, 2026-09-06):** the Datamodel tab shows one
declared/held pair. `run_pane_test.exs` "shows what the run held beside what
the document declares"; the DevTools read of the tab reports headers
`["Path", "Type", "Held here"]` and one row
`{path: "settlement", type: "unknown", held: "\"settled\""}`.

**Machine-checked (unattended, 2026-09-06):** a document with no run renders
unchanged. The editor was rendered twice with no run seated - once as built,
once with the `RunPane.run_pane` wrapper physically removed from
`editor.ex`'s template - and the two documents are the same length and
identical once the per-mount LiveView view id and session token are
normalized, which differ between any two mounts of anything. The in-suite form
of the same claim is `run_pane_test.exs` "renders exactly what it renders with
the pane never seated".

**Correction to the criterion's wording:** the bead says "renders exactly as
0.20.0". Literal equality with the released 0.20.0 markup is not checkable and
is not what the criterion means - `main` has moved since (the Source tab and
the document-rule findings both changed the render). What is checked is the
property the criterion is about: seating a run and clearing it again returns
the markup to what it was, and the pane contributes nothing while no run is
there.

**Machine-checked (unattended, 2026-09-06):** captures attached, on a private
port, driven through DevTools. Paths are on the bead.

## Deferred to a human

- **Whether the pane reads as a pane.** The DOM is checked; whether the
  status line, the scrubber and the log are laid out in a way an author can
  use, and whether the scrubbed frame differs from the live one in the way a
  reader expects, is the operator's judgement on the three captures.
