# The block-level flow graph

This note defines one reading of a compiled chart: the **block-level flow
graph**, a graph with one node per block and one edge per way control can
pass from one block to another, lifted from the transitions the compiler
emits. It says what an edge is, how interrupts and resume loops appear, how
convergence after a branch is drawn, and what `done.state` firing on any
outcome means for an edge.

It is a note, not a record. It decides nothing the compiler does not already
do, and nothing in this package computes the graph: it is the vocabulary a
chart-view proposal cites for what its edges mean. Every claim about the
compiler's output below was read at commit `01af1f5`, and the cites table at
the end carries that SHA for each function named.

## What it is not

Three things in and around this package are also drawn as nodes and edges.
The block-level flow graph is none of them.

- **Not `StatifierBlocks.Graph`.** That module is the publish-time check
  between a parent document and the child documents it names. Its nodes are
  documents and its edges are the references a `core.subchart` or a
  `core.map` makes to another document; `check/2` and `consumers_broken/2`
  walk it one pair at a time. The block-level flow graph never leaves one
  document: its nodes are that document's blocks.
- **Not the editor's connector layer.** `StatifierBlocks.Connectors.edges/2`
  draws the edges that adjacency and nesting in the view-model tree imply,
  from measured rectangles. It reads no compiled chart. The block-level flow
  graph is read from the chart, so it shows what the compiled transitions do
  rather than what the document's layout suggests.
- **Not a state-index renderer.** Another package ships a renderer that
  draws a chart's states indexed by state id. Drawn that way, one block is
  several nodes: the compiler gives most blocks generated role states
  (`__pick`, `__waiting`, `__armed`, `__run`, `__body`, `__body_done`,
  `__history`) and one `<final>` per outcome (`__o_<name>`). The block-level
  flow graph folds every one of those into the block that produced it, so an
  author sees their own blocks and the paths between them, not the scaffolding
  the compiler built to realise them.

## Nodes: one per block

Every state id the compiler emits belongs to exactly one block. The
provenance map says which: `StatifierBlocks.Provenance.owner_of_state/2`
answers a state id with its owning block id and its role.

Lifting a transition finds the block at each end. The target end is the
block that owns the target state. The source end is the block the
transition leaves: for a transition on a block's own `done.state` or
`done.outcome` event, the block that event names
(`StatifierBlocks.Compiler.StateId.undone_event/1` inverts the generated
name, and answers `:error` for a role state's completion); for any other
transition, the block that owns the state it sits on. A transition whose
two ends are the same block is internal to that block and draws no edge; it
can still label the block (an await's `received` and `timed_out` finals are
both inside the await's node). Interrupts take one more step, described
under "Edges" below.

A container block (a sequence, a group, a branch) is a node with an
**entry** and an **exit**. Its entry is where its compound state starts: its
first child, or a branch's `__pick` state. Its exit is its own outcome
final, the `<final>` whose entry raises `done.state.<its state id>` for its
parent; a group with handlers adds its body region's `__body_done` final,
which leads only to that outcome final.

## Edges: what the compiler emits between blocks

Four kinds of compiled transition lift to an edge.

1. **A sequence edge.** A parent sequences its children with transitions on
   its own state, one per adjacent pair, each on the finished child's
   `done.state.<state id>` and targeting the next child's state; the last
   child's transition targets the parent's exit (`Emit.chain/2`). Each is
   attributed to the child it leaves, which is also the end the lifted edge
   starts from.
2. **A branch edge.** `core.branch` enters an atomic `__pick` state holding
   one eventless transition per arm, guarded by the arm's condition, and a
   last unguarded one for `otherwise` (`Branch.emit/2`). Each lifts to an
   edge from the branch's entry to the arm's first child, labelled with the
   condition. An empty arm's transition targets the branch's own exit, so it
   lifts to an edge straight from the branch's entry to its exit.
3. **An interrupt edge.** A handler in a group's `interrupts` slot sits in a
   region of the group's `__run` `<parallel>`, beside the body. Its transition
   on its event raises one of two events salted with the group's state id, and
   the group's own state carries the transition for each: abandon targets the
   group's exit, resume targets the group's `__run` or its `__history`
   (`Emit.interruptible/2`). The raise and the transition together lift to one
   edge from the handler to where the group goes.
4. **An exit edge.** The transition that carries a finished child to its
   parent's exit (the last case of 1, and a group's
   `done.state.<body id>` transition to its own exit) lifts to an edge from
   that child to the parent's exit.

The coupling of two blocks by an **event name** alone is not an edge. A
`core.send` that schedules an event and a handler that listens for the same
name share a string, not a transition; the compiled chart has nothing that
connects them, and neither does the graph.

## `done.state` fires on any outcome

A block with more than one outcome compiles each one to its own outcome
final. Every one of them raises the same `done.state.<state id>` when entered,
because SCXML raises that event whenever a compound state's configuration
enters a `<final>` child. The child summary a parent is handed says so in its
own words: its `done_event` is the "finished, do not care how" signal
(`StatifierBlocks.Compiler.Context`, the `child_summary` type).

Every sequence and exit edge is on that event. So a lifted edge **carries
every outcome its source block can finish with**. A `core.await` with a
timeout finishes as `received` or `timed_out` (`Await.outcomes/1`); in a
sequence, both leave by the one edge to the next sibling. Drawing
`timed_out` as a second exit would draw a fork the chart does not contain.
Labelling the edge with the outcomes it carries stays true to the chart;
splitting it does not.

The same holds for a group's abandon. The group's transition on its abandon
event targets the same exit final that a finished body reaches
(`Emit.interruptible/2`), so
from outside, a group that completed and a group that was abandoned leave by
the same edge.

Where outcomes do route to different places, the routing is inside the
block that declares them. `core.invoke`'s failure transition targets its
`on_error` child inside the invoke's own state, and both of its outcome
finals then raise the invoke's one `done.state` (`Invoke.emit/2`). The
per-outcome completion events, `done.outcome.<state id>.<name>`
(`StateId.outcome_event/2`), are what an interrupt handler can listen for
when it is wired onto a sibling's outcome (`StatifierBlocks.Core.OnEvent`,
"Candidates for `event`"); such a handler draws an interrupt edge whose
trigger is that outcome, not a second sequence edge.

## Convergence after a branch

Every arm of a `core.branch` chains its children to the **branch's own
exit** (`Branch.emit/2` passes the one exit final to `Emit.chain/2` for each
arm), and an empty arm's pick transition targets that exit directly. The
branch then leaves its parent by the one sequence edge on its own
`done.state`.

So convergence is drawn at the branch's exit: every arm's last block has an
exit edge into it, and one edge leaves it. There is no separate join node,
and none is needed; the branch's exit is where the chart converges. A
wired `undecided` slot is one more guarded pick transition and one more arm
into the same exit.

## Interrupts and resume loops

A handler is not a step in the body. It is a region beside the body, active
for as long as the group's `__run` `<parallel>` is, so its edge starts from
the handler node and can fire from any point in the body; it does not hang
off any one body step.

Where an interrupt edge ends is the handler's `outcome` config
(`StatifierBlocks.Core.OnEvent`, "The `outcome` values"):

- **abandon** ends at the group's exit, the same exit a finished body
  reaches.
- **resume** is a loop back into the group. On `core.group` it targets the
  group's `__run` `<parallel>`, so the body starts again from its first step.
  On `core.resumable_group` it targets a `<history>` in the body region, of the
  type the group's `history` config names: `shallow` re-enters at the
  top-level step the group was last in, `deep` at the exact position. The
  history's default transition targets the body's first step. A resume loop
  into a resumable group therefore ends at "the step it was in", which is not
  one fixed block; the lifted edge ends at the body, not at a block the chart
  does not name.

Each group's pair of interrupt events is salted with that group's state id
(`Emit.interrupt_events/1`), and the raises inside a group's rail are
rewritten to that salt (`StatifierBlocks.Compiler.Interrupts`). An interrupt
edge therefore always ends at its own group, never at an enclosing one.

A handler with a `finish_as` name also completes under that name, which an
enclosing declaring composite can route on (`StatifierBlocks.Core.OnEvent`,
the `finish_as` section). This note does not work composites through.

## Worked example: patron registration

The fixture `test/fixtures/documents/patron_registration.json` is a sequence
holding one group. The group's body schedules a 24-hour deadline and then
awaits the patron's email verification; two handlers abandon the group when
the registration is abandoned or the deadline arrives.

```text
blk_PROOT  core.sequence
  body:
    blk_PGRP  core.group
      body:
        blk_PDLN  core.send       event registration.deadline, delay 24h
        blk_PVER  core.await      event email.verified
      interrupts:
        blk_PABN  core.on_event   event registration.abandoned, outcome abandon
        blk_PEXP  core.on_event   event registration.deadline, outcome abandon
```

The transitions that cross a block boundary, as compiled:

```xml
<!-- on s_blk_PROOT -->
<transition event="done.state.s_blk_PGRP" target="s_blk_PROOT__o_done" type="internal"/>
<!-- on s_blk_PGRP -->
<transition event="done.state.s_blk_PGRP__body" target="s_blk_PGRP__o_done" type="internal"/>
<transition event="statifier_blocks.interrupt.abandon.s_blk_PGRP" target="s_blk_PGRP__o_done" type="internal"/>
<transition event="statifier_blocks.interrupt.resume.s_blk_PGRP" target="s_blk_PGRP__run" type="internal"/>
<!-- on s_blk_PGRP__body -->
<transition event="done.state.s_blk_PDLN" target="s_blk_PVER" type="internal"/>
<transition event="done.state.s_blk_PVER" target="s_blk_PGRP__body_done" type="internal"/>
<!-- on s_blk_PABN__armed and s_blk_PEXP__armed -->
<transition event="registration.abandoned" target="s_blk_PABN__o_done">
  <raise event="statifier_blocks.interrupt.abandon.s_blk_PGRP"/></transition>
<transition event="registration.deadline" target="s_blk_PEXP__o_done">
  <raise event="statifier_blocks.interrupt.abandon.s_blk_PGRP"/></transition>
```

Lifted:

```text
blk_PROOT entry  -> blk_PGRP
blk_PGRP         -> blk_PROOT exit   exit, on done.state (the group's one outcome, done)

blk_PGRP entry   -> blk_PDLN
blk_PDLN         -> blk_PVER         sequence, on done.state (done)
blk_PVER         -> blk_PGRP exit    exit, on done.state (received)
blk_PABN         -> blk_PGRP exit    interrupt, abandon, on registration.abandoned
blk_PEXP         -> blk_PGRP exit    interrupt, abandon, on registration.deadline
```

Four things the example shows:

- The group's resume transition is present in the chart, but no handler
  raises resume, so no resume loop is drawn. An edge is drawn only where a
  transition can be taken from a block.
- `blk_PVER` has no timeout, and the compiled chart holds only its `received`
  final, so its exit edge carries `received` alone.
- Three edges end at the group's exit: a verified patron, an abandoned
  registration and an expired one. The group then leaves by one edge,
  because `done.state.s_blk_PGRP` fires for all three.
- `blk_PDLN` schedules `registration.deadline` and `blk_PEXP` listens for
  it. No transition joins them, so there is no edge between them; the
  delayed send is cancelled in the body region's `<onexit>` when the body is
  left (`StatifierBlocks.Compiler.Cancels`).

## Worked example: a library loan

This document is illustrative. It is written out here and is not a fixture
in this repository; it compiles with the `core.*` palette at `01af1f5` with
no findings and no warnings. A patron who owes fines is sent a notice and
the loan waits for the fines to be paid; the book is then checked out, and
the loan waits up to 21 days for the return. A renewal resumes the wait; a
report that the book is lost abandons it. Either way, the loan is closed.

```json
{
  "schema_version": 1,
  "id": "bdoc_01JLIBRARYLOAN",
  "revision": 1,
  "metadata": {"name": "Library loan"},
  "accepts": ["fines.paid", "loan.renewed", "loan.returned", "loan.reported_lost"],
  "datamodel": [{"id": "patron", "description": "The borrowing patron."}],
  "root": {
    "id": "blk_LROOT", "type": "core.sequence", "type_version": 1,
    "slots": {"body": [
      {"id": "blk_LCHK", "type": "core.branch", "type_version": 1,
       "config": {"arms": [{"slot": "arm_owes", "cond": "patron.fines_owed > 0"}]},
       "slots": {
         "arm_owes": [
           {"id": "blk_LFIN", "type": "core.send", "type_version": 1,
            "config": {"event": "loan.fines_notice"}},
           {"id": "blk_LPAY", "type": "core.await", "type_version": 1,
            "config": {"event": "fines.paid"}}
         ],
         "otherwise": [],
         "undecided": []
       }},
      {"id": "blk_LOUT", "type": "core.send", "type_version": 1,
       "config": {"event": "loan.checked_out"}},
      {"id": "blk_LLEN", "type": "core.resumable_group", "type_version": 1,
       "config": {"history": "shallow"},
       "slots": {
         "body": [
           {"id": "blk_LRET", "type": "core.await", "type_version": 1,
            "config": {"event": "loan.returned", "timeout": "21d"}}
         ],
         "interrupts": [
           {"id": "blk_LREN", "type": "core.on_event", "type_version": 1,
            "config": {"event": "loan.renewed", "outcome": "resume"}},
           {"id": "blk_LLOS", "type": "core.on_event", "type_version": 1,
            "config": {"event": "loan.reported_lost", "outcome": "abandon"}}
         ]
       }},
      {"id": "blk_LEND", "type": "core.send", "type_version": 1,
       "config": {"event": "loan.closed"}}
    ]}
  }
}
```

The transitions that cross a block boundary, as compiled:

```xml
<!-- on s_blk_LROOT -->
<transition event="done.state.s_blk_LCHK" target="s_blk_LOUT" type="internal"/>
<transition event="done.state.s_blk_LOUT" target="s_blk_LLEN" type="internal"/>
<transition event="done.state.s_blk_LLEN" target="s_blk_LEND" type="internal"/>
<transition event="done.state.s_blk_LEND" target="s_blk_LROOT__o_done" type="internal"/>
<!-- on s_blk_LCHK__pick, then on s_blk_LCHK -->
<transition cond="patron.fines_owed &gt; 0" target="s_blk_LFIN"/>
<transition target="s_blk_LCHK__o_done"/>
<transition event="done.state.s_blk_LFIN" target="s_blk_LPAY" type="internal"/>
<transition event="done.state.s_blk_LPAY" target="s_blk_LCHK__o_done" type="internal"/>
<!-- on s_blk_LLEN -->
<transition event="done.state.s_blk_LLEN__body" target="s_blk_LLEN__o_done" type="internal"/>
<transition event="statifier_blocks.interrupt.abandon.s_blk_LLEN" target="s_blk_LLEN__o_done" type="internal"/>
<transition event="statifier_blocks.interrupt.resume.s_blk_LLEN" target="s_blk_LLEN__history" type="internal"/>
<!-- on s_blk_LLEN__body, and its history -->
<transition event="done.state.s_blk_LRET" target="s_blk_LLEN__body_done" type="internal"/>
<history id="s_blk_LLEN__history" type="shallow"><transition target="s_blk_LRET"/></history>
<!-- on s_blk_LREN__armed and s_blk_LLOS__armed -->
<transition event="loan.renewed" target="s_blk_LREN__o_done">
  <raise event="statifier_blocks.interrupt.resume.s_blk_LLEN"/></transition>
<transition event="loan.reported_lost" target="s_blk_LLOS__o_done">
  <raise event="statifier_blocks.interrupt.abandon.s_blk_LLEN"/></transition>
```

Inside `blk_LRET`, `s_blk_LRET__waiting` carries one transition to its
`received` final and one, on the deadline its entry schedules, to its
`timed_out` final. Both ends are `blk_LRET`, so neither is an edge.

Lifted:

```text
blk_LROOT entry  -> blk_LCHK
blk_LCHK         -> blk_LOUT         sequence, on done.state (done)
blk_LOUT         -> blk_LLEN         sequence, on done.state (done)
blk_LLEN         -> blk_LEND         sequence, on done.state (done)
blk_LEND         -> blk_LROOT exit   exit, on done.state (done)

blk_LCHK entry   -> blk_LFIN         branch, when patron.fines_owed > 0
blk_LCHK entry   -> blk_LCHK exit    branch, otherwise (empty arm)
blk_LFIN         -> blk_LPAY         sequence, on done.state (done)
blk_LPAY         -> blk_LCHK exit    exit, on done.state (received)

blk_LLEN entry   -> blk_LRET
blk_LRET         -> blk_LLEN exit    exit, on done.state (received, timed_out)
blk_LREN         -> blk_LLEN body    interrupt, resume, on loan.renewed, at shallow history
blk_LLOS         -> blk_LLEN exit    interrupt, abandon, on loan.reported_lost
```

What it shows:

- **Convergence.** The fines arm and the empty `otherwise` arm both end at
  `blk_LCHK`'s exit, and one edge leaves the branch for `blk_LOUT`.
- **Any outcome.** `blk_LRET` finishes as `received` or `timed_out`, and
  both leave by its one exit edge. An overdue book is not routed anywhere
  different in this document: `blk_LEND` follows either way. A view that
  drew `timed_out` as its own path would show a behaviour this document does
  not have.
- **The resume loop.** `blk_LREN` loops back into `blk_LLEN`'s body at its
  shallow history. Here the body has one top-level step, so the loop lands
  on `blk_LRET` in practice; in a longer body it lands on whichever top-level
  step was active, which is why the edge ends at the body rather than at a
  block.
- **Abandon shares the exit.** A lost book leaves `blk_LLEN` by the same exit
  as a returned one, so `loan.closed` is sent in both cases.

## What this note does not decide

It fixes no view: no node shape, no layout, no colour, and no rule for how
an entry, an exit or a history target is drawn. It says nothing about
`core.parallel`, `core.foreach`, `core.map`, `core.subchart` or a composite
beyond the general rules above; each of those has emitted shapes of its own
that a proposal covering it works through the same way, against the compiled
chart. It adds nothing to the compiler, and a flow-graph emitter would be a
proposal of its own.

## Cites

Every cite was read at `01af1f5`.

| Anchor | File | SHA |
|---|---|---|
| `StatifierBlocks.Graph`, `check/2`, `consumers_broken/2` | `lib/statifier_blocks/graph.ex` | `01af1f5` |
| `StatifierBlocks.Connectors.edges/2` | `lib/statifier_blocks/connectors.ex` | `01af1f5` |
| `StatifierBlocks.Provenance.owner_of_state/2` | `lib/statifier_blocks/provenance.ex` | `01af1f5` |
| `StatifierBlocks.Core.Emit.chain/2`, `interruptible/2`, `interrupt_events/1`, `final/1` | `lib/statifier_blocks/core/emit.ex` | `01af1f5` |
| `StatifierBlocks.Compiler.Context`, the `child_summary` type | `lib/statifier_blocks/compiler/context.ex` | `01af1f5` |
| `StatifierBlocks.Compiler.StateId.done_event/1`, `outcome_event/2`, `undone_event/1` | `lib/statifier_blocks/compiler/state_id.ex` | `01af1f5` |
| `StatifierBlocks.Compiler.Interrupts` | `lib/statifier_blocks/compiler/interrupts.ex` | `01af1f5` |
| `StatifierBlocks.Compiler.Cancels` | `lib/statifier_blocks/compiler/cancels.ex` | `01af1f5` |
| `StatifierBlocks.Core.Branch.emit/2` | `lib/statifier_blocks/core/branch.ex` | `01af1f5` |
| `StatifierBlocks.Core.Await.outcomes/1`, `emit/2` | `lib/statifier_blocks/core/await.ex` | `01af1f5` |
| `StatifierBlocks.Core.Invoke.emit/2` | `lib/statifier_blocks/core/invoke.ex` | `01af1f5` |
| `StatifierBlocks.Core.OnEvent`, "The `outcome` values", `finish_as`, "Candidates for `event`" | `lib/statifier_blocks/core/on_event.ex` | `01af1f5` |
| `StatifierBlocks.Core.ResumableGroup.emit/2` | `lib/statifier_blocks/core/resumable_group.ex` | `01af1f5` |
| The patron registration fixture | `test/fixtures/documents/patron_registration.json` | `01af1f5` |

## Note (2026-09-26): where the graph is computed

This is a dated note on the sentence in the introduction that nothing in
this package computes the graph, not a change to anything the note
defines. ADR-0016, at proposed, decides that `StatifierBlocks.Describe`
computes it: `StatifierBlocks.Describe.outline/3` answers one node per
block and the sequence, branch, interrupt and exit edges of this note
(plus an entry edge from a container's entry to its first child), for
`core.sequence`, `core.group`, `core.resumable_group` and `core.branch`,
and `StatifierBlocks.Describe.render/2` writes them as one line each.

It reads the document's structure and never compiles, so it does not lift
edges from a compiled chart the way this note does by hand, and the
sentence that a flow-graph emitter would be a proposal of its own still
stands. Its edges carry the outcomes a block's type declares rather than
the finals the compiler emits. In the two worked examples above those
differ only at an await with no timeout, `blk_PVER` and `blk_LPAY`, where
the lifted listings say `received` and the describe says `received,
timed_out` (ADR-0016, decision 1).

Until the module ships in a published version, the introduction's
sentence stays true of main. Every other claim here is unchanged.
