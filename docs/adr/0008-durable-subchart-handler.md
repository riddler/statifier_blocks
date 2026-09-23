# ADR-0008: The durable subchart handler answers at dispatch time, not from a pure `start/2`, and its refusal set gains exactly one reason

Status: accepted (2026-09-01, campaign-025; unqualified direction-agent
verdict)

## Context

`StatifierBlocks.Runtime.Subchart` (PR 197, ADR-0007's 2026-08-31 note) is the
canonical `statifier_blocks:subchart` handler for the in-memory case. It closes
the gap `StatifierBlocks.Core.Subchart` deliberately leaves open: a block type
names an invoke type and runs nothing (ADR-0002 decision 2), so something has to
resolve the document id on `src` to an actual chart and start it. That module is
that something, written once because every host embedding `core.subchart` would
otherwise write the same one.

Its own moduledoc names what it is not. `Statifier.Invoke.Handler.start/2` is a
**planning** callback: it is pure, it performs nothing, and it returns
instructions that `Statifier.Session` then executes. That is exactly right for
an in-memory resolver reading a document out of the host's own process, and it
is exactly what scopes the module to `Statifier.Session`. A durable subchart -
the child running as its own persisted run, composing with
`statifier_persistence` and `statifier_oban` - has to durably record the
parent-child linkage as part of starting, and recording something durably is not
a planning-time operation. The module says so and stops there; the follow-up was
filed as `sb-2i04`, mirrored with `statifier_persistence`'s `sp-nt8`.

Two things have landed since that made the follow-up answerable.

**The async-invocation seam exists.** `sp-ADR-0007` (accepted 2026-09-01)
gives the durable path a `:pending` arm on its `Driver` dispatch fun - a call
that has *started* and will answer later, with nothing buffered, the drive
reaching quiescence and the position persisting with the invocation
live in `machine_state.active_invocations` - plus two public re-entry doors,
`Driver.done_invocation/5` and `Driver.failed_invocation/5`, which build the
same `done.invoke.<id>` and `error.communication.invoke.<id>` events the
in-drive path builds. A durable invocation that outlives the process that
started it now has a supported shape and a supported way home.

**The reference embedder surfaced the gap honestly rather than papering over
it.** `statifier_examples` refuses a durable subchart with
`{:error, {:durable_subchart_unsupported, type}}` rather than pretending to
start one. That refusal is the thing this record exists to delete.

The operator's ruling notes on `sb-2i04` (2026-08-31, recorded on both mirror
halves) then settled the design questions, and split the write-up in two: this
record takes the handler shape and the refusals, and statifier_persistence's
`sp-ADR-0008`, "child-run linkage and `start_child` stepping for durable
subcharts" (its bead `sp-2yt`), takes the linkage, the stepping, and cancel
across restart. Neither record reopens what those notes decided; each states
it in the half of the system that owns it, which is the umbrella's
contract-ownership rule - handler shape here, storage and stepping there.

**What this record therefore has to answer**, and nothing wider: what shape the
durable handler has, given that a pure `start/2` will not carry it; and what a
durable start may refuse for, given that campaign-023 ruling R-b closed the
in-memory set at three reasons.

## Decision

### 1. The durable variant is a second module, not a mode inside the first

`StatifierBlocks.Runtime.Subchart` is untouched: it stays the in-memory
canonical handler, its `start/2` stays pure, and a host wiring an in-memory
session gets exactly what it gets today. The durable variant is a **new module
beside it** under the same namespace convention ADR-0007's note fixed -
canonical host-side runtime helpers live under `StatifierBlocks.Runtime.*` - and
the module's own name is the implementation bead's to choose.

A runtime flag inside one module was the alternative and is rejected. The
in-memory module's most valuable stated property is that its `start/2` is a pure
planning callback; a flag that sometimes made it write to storage would make
that property conditional on a value, which is the same as not having it. The
two modules also answer to different callers - one to `Statifier.Session`, one
to `StatifierPersistence.Driver` - and a module with two callers of different
purity is harder to read than two modules with one each.

**Both serve the same invoke type string.** `core.subchart` compiles a fixed
`type` attribute from `StatifierBlocks.Core.Subchart.invoke_type/0`
(`"statifier_blocks:subchart"`, the one definition site), so a durable host
embeds the same block type and the document reaches the runtime naming the same
string. Which module answers it is the host's session wiring, not the
document's - see consequence 1.

### 2. Resolution and refusal are shared, and unchanged

The resolver contract the in-memory module states is the durable module's too,
in full and without additions: the host implements `resolve_chart/2` and
`palette/0`; the four answers are `{:ok, %StatifierBlocks.Document{}}` compiled
here with `child_use: true` against `palette/0`, `{:ok,
%StatifierBlocks.Compiled{}}` used as it stands, `{:cycle, path}`, and `:error`;
a non-binary `src` refuses `unknown_document` without ever reaching the
resolver; and a return outside the four raises `ArgumentError` naming the
offending module, because a host program defect reported as a refusal of the
author's chart is a worse error message than a crash.

This is the half of the work that is genuinely pure in both variants -
resolving a document id and compiling a child chart reads nothing durable and
writes nothing - so it is shared code, not a second copy. What differs between
the variants begins after resolution has produced a chart.

### 3. The instruction stays `{:start_child, invoke, {:invoke, invoke}}`

The in-memory module plans `{:start_child, %{invoke | content: scxml},
{:invoke, invoke}}` on a successful resolve. The durable variant emits the same
tuple, with the same shape and the same meaning: *start this chart as the child
of this invocation*. It is not renamed, not wrapped, and not given a durable
twin.

Two reasons, and the second is the load-bearing one.

The effect vocabulary is `statifier`'s, not this package's - the umbrella's
contract-ownership rule puts the interpreter contract, chart identity,
serialization and the effect vocabulary in `statifier-ex`. A satellite that
minted `{:start_durable_child, ...}` because its executor differed would be
deciding something it does not own, and would do it by accident.

And the executor differing is the whole of the difference. An instruction is a
description of what to do; the same description is executed by
`Statifier.Session` in the in-memory case and by the durable executor
`sp-ADR-0008` describes in the durable case. Nothing in the tuple names the
executor, so nothing in the tuple has to change to reach a different one.

The chart-identity pin the linkage requires needs no new field for the same
reason. ADR-0004's 2026-08-29 amendment, section R2, already says where pinning
lives: on the **run**, in run metadata, from the identity the handler actually
resolved. The durable executor has the resolved chart in hand, because the
instruction carries it in `invoke.content`, so it can record the identity
without the instruction growing a field to carry it. What the ruling notes on
`sb-2i04` change about R2 is its status, not its mechanism: recording the pin
was a host's option there and is mandatory for a durable child here, which is
`sp-ADR-0008`'s clause to state, and this record only observes that aligning on
the existing tuple costs nothing to reach it.

### 4. Why it is not a pure `start/2`: the answer is given at dispatch time

The durable path does not have `Statifier.Session`. Its invocations are answered
by `StatifierPersistence.Driver`'s dispatch fun inside the durable step that
emitted them, and that fun - not a per-session handler module registered under
`st-ADR-0051` - is the seam a durable host wires. So the durable subchart module
contributes a **dispatch-time answer**, and the shape of that answer is what
this decision fixes.

There are three separate reasons a pure `start/2` cannot be that answer, and
they are worth keeping apart because only the first is about purity.

**A durable start is a write, and it has to happen under the parent's
exclusion.** The linkage - the parent's run id, the invocation id, and the
mandatory chart-identity pin - has to be durably recorded as part of starting,
and it has to be recorded in the same serialized step that persists the parent's
position. A planning callback returns data and performs nothing, so it can
neither make that write nor be inside that exclusion. Splitting it - plan here,
write later - is precisely the window that loses: a crash between a persisted
parent that believes it has a child and a child run that was never created
leaves an invocation that can never be answered, and the mirror-image ordering
leaves an orphan run nothing will ever cancel. `sp-ADR-0007` decision 3
already establishes that the durable path's reads about invocation
liveness are taken *inside* `with_run/3` rather than before the call, for the
same class of reason; the write that starts a child belongs on the same side of
that line.

**The answer does not arrive in the same breath.** `Statifier.Session` can own a
child session process and route its completion itself, which is what makes the
in-memory `{:start_child, ...}` a complete story. A durable child is its own
persisted run, and no process holds either side while it runs - the parent may
be resting for days, across a deploy. So starting a durable child is exactly the
case ADR-0007's `:pending` arm exists for: the dispatch has *started* the call
and answers nothing, the parent reaches quiescence, and completion comes back
later through the seam's public `done.invoke` and failure doors from a process
that did not exist when the child started. That is the ruling notes' "no bespoke
parent-child channel" clause: the durable subchart introduces no transport of
its own, and this package writes no completion path at all.

**The handler is therefore not the thing that completes the invocation, and
must not pretend to be.** In-memory `cancel/2` plans `{:stop_child, invoke_id}`
and `forward/3` plans `{:forward, invoke_id, event}`, both of which name a live
child process. Neither has a durable counterpart on this module. A durable
cancel happens because the parent left the invoking state and
`active_invocations` lost the entry, and what follows from that - a cascade
through the child's own children, records retained under a distinct terminal
status, nothing deleted, late completions dropped idempotently - is
`sp-ADR-0008`'s, per the ruling notes on `sb-2i04`. This package contributes
nothing to it and should offer no callback that looks like it does.

### 5. The refusal set is four reasons, closed

The campaign-023 closed set is reused verbatim -
`"unknown_document"`, `"child_compile_findings"`, `"cycle_refused"` - and the
ruling notes on `sb-2i04` permit at most one durable-only addition. This record
takes that one and spells it **`"child_run_creation_failed"`**, in the same
snake_case as the other three. The set is closed at four, never a fifth.

| Reason | When | Durable-only |
|---|---|---|
| `unknown_document` | the resolver answered `:error`, or `src` was not a binary | no |
| `child_compile_findings` | the child document was resolved and did not compile | no |
| `cycle_refused` | the resolver answered `{:cycle, path}` | no |
| `child_run_creation_failed` | the chart resolved and compiled, and creating the child run did not succeed | **yes** |

**Why exactly one is needed.** Creating the child run is the one new way a start
can fail that the in-memory variant has no analogue for. Folding it into
`unknown_document` would say the author named a chart that does not exist, which
is false and sends whoever reads the event to the wrong place. Leaving it out
entirely would mean a storage failure at that moment either crashes the parent's
step or is silently swallowed, and both are worse than a refusal: the invocation
is one the chart is waiting on, and an author's `on_error` slot is where a
failure to start belongs, whoever's fault it was.

**Why not more than one.** The candidates for a fifth are all better answered
elsewhere. A child that starts and *then* fails is not a refusal - it is the
child's own outcome, arriving through the completion doors as any other
invocation's would. A cancelled child is not a refusal either; see decision 4. A
resolver returning something outside its four answers still raises, exactly as
in the in-memory case, because that is a host program defect and not a chart
problem. And a transient storage error is the host's to retry before answering,
which is the posture `sp-ADR-0007` decision 2 already states for its failing
door: `child_run_creation_failed` means the creation
*permanently* did not happen.

**The reasons are the handler's; the carrier is the path's.** In-memory, a
refusal is one `{:raise, :platform, "error.communication.invoke." <> invoke_id,
...}` instruction carrying `reason` and a JSON-shaped `detail` map, deliberately
not an `{:error, _}` from `start/2`, which the engine turns into a data-less
`error.execution` and which would lose the reason. On the durable path the
dispatch fun's failing arm is what carries it, and the event it produces is the
same `error.communication.invoke.<invoke id>` with `st-ADR-0068`'s
`reason`/`attempts`/`detail` payload. Same four strings, same `detail` maps,
same event name, same block-level `on_error` transition catching it by SCXML's
descriptor prefix rule, because `core.subchart` emits its `<invoke>` with
`id=<block id>`. `attempts` stays absent for the same reason it is absent
in-memory: a refusal made no attempt.

### 6. Nesting is in; fan-out is named and not built

**A durable child may itself invoke a durable subchart, from the first
version.** The protection against a document graph that loops back on itself
is the one already in place and already in the refusal set: the compiler
refuses a document that names itself (ADR-0004's amendment, R3), and a
cross-document cycle is the resolver's to detect and report as
`cycle_refused`, because a compile of one document cannot see the document
graph a cycle needs. Whether a *runtime* ancestry or depth guard is also
wanted is an implementation question this record deliberately leaves open
rather than deciding by silence.

**One invocation mapping to N children is a seam this design leaves room for and
does not build.** The room is real and worth naming: N children are N runs
linked to the same parent invocation, and their completions would ride the same
public re-entry door a single child's does, so nothing in decisions 3, 4 or 5
would have to move. What is missing is not machinery but decisions - what block
type expresses fan-out, and what aggregation policy turns N answers into one
outcome - and SCXML's own `foreach` is synchronous, so it is not the answer
either. Those get their own walk, against working single-child machinery. This
record decides only that the seam is not closed off; it does not authorize
building it.

### 7. What this record does not change

* **The two-registry seam.** ADR-0002 decision 2 holds: a block type names an
  invoke type, and something registered separately runs it. Both variants here
  are on the running side of that line; neither resolves a block type, neither
  appears in a palette, and no block type reaches for one.
* **`core.subchart`'s compiled contract.** ADR-0004's 2026-08-29 amendment,
  C1 to C3 - a child compiled with `:child_use`, the outcome carried on
  `<donedata>`, one slot per outcome, `id=<block id>` on the `<invoke>` - is
  unchanged, and so is R1's rule that `src` carries the document id verbatim.
  Not one compiled byte differs between a document destined for an in-memory
  host and the same document destined for a durable one.
* **`StatifierBlocks.Runtime.Subchart`.** No change to its callbacks, its
  purity, its instruction, or its three-reason refusal set. The fourth reason
  above is the durable module's and cannot be raised by the in-memory one,
  which has no child run to fail to create.
* **The `Runtime.*` convention.** ADR-0007's note fixed where canonical
  host-side runtime helpers live, and this is the second module to land there
  rather than a reason to revisit the namespace.
* **Chart identity and the effect vocabulary.** Both are `statifier-ex`'s, and
  this record cites `st-ADR-0051`, `st-ADR-0052` and `st-ADR-0068` rather than
  restating any of them.

## Consequences

**Durability becomes a property of the host's wiring, not of the document.** The
same block document, compiled to the same bytes, runs in-memory or durably
depending on which module the host wired for the session. That is the right
place for the choice - a durable run and an in-memory one are the same workflow
with different operational requirements, and an author has no business
expressing the difference - but it has a cost worth stating plainly: a host that
wires the in-memory module into a durable run gets an in-memory child, which is
to say a child that does not survive the restart the parent was made durable to
survive. Whether the durable stack can detect and refuse that wiring, rather
than only documenting it, is the implementation bead's question and this record
does not assume it can.

**The reference embedder's honest refusal goes away.**
`{:error, {:durable_subchart_unsupported, type}}` was the correct thing to ship
while nothing supported it; it is also the concrete measure of whether this
design landed, and deleting it is `statifier_examples`' own bead.

**Two modules now have to be kept in step, and the sharing bounds how far they
can drift.** Resolution, compilation and three of the four refusal reasons are
one implementation used by both, so a change to the resolver contract cannot
land in one variant only. What is genuinely separate is the start half and
nothing else, which is the smallest surface this split could have had.

**This record and `sp-ADR-0008` have to be read together.**
Neither is complete alone: this one says what the handler answers and what it
may refuse for, and that one says what the executor does with the answer, how
the linkage is stored, and what cancel means across a restart. Each cites the
other by repo and number; a reader who has one and not the other is missing
half of a single design, and the ruling notes on `sb-2i04` split it that way
deliberately so that each half goes through its own repository's review.

**Nothing here is implemented.** This is the design record; the implementation
is `sb-2i04`, mirrored with `sp-nt8`, and the two halves close together.

---

## Note (2026-09-01): decision 5, the four-reason table is satisfied jointly

A dated note rather than an amendment. Decision 5 is unchanged in every
clause: the refusal set is the campaign-023 three plus exactly one
durable-only reason, `child_run_creation_failed`, and it is closed at four.
What this records is *which package raises which of the four*, which the
table above deliberately did not say and which the implementation
(`sb-2i04`, mirrored with `sp-nt8`) has now fixed on both sides.

**The set is satisfied jointly by the two packages, not by this one alone.**

| Reason | Raised by |
|---|---|
| `unknown_document` | `StatifierBlocks.Runtime.DurableSubchart` |
| `child_compile_findings` | `StatifierBlocks.Runtime.DurableSubchart` |
| `cycle_refused` | `StatifierBlocks.Runtime.DurableSubchart` |
| `child_run_creation_failed` | `StatifierPersistence.Driver`, from its own `start_child/3` refusals |

This module's handler surface is therefore the **three inherited reasons**,
carried on the `{:error, reason: reason, detail: detail}` answer its dispatch
fun returns, and nothing it can do produces the fourth. That follows from
decision 4 rather than adding to it: creating the child run happens *after*
this package has answered, inside the parent's serialized step, so the module
has no way to observe the failure and does not pretend to. The driver's
`{:start_child, ...}` arm is the one site that turns a `{:refused, detail}`
from `start_child/3` into `{:failed, reason: "child_run_creation_failed",
detail: detail}`, and that side funnels every one of its own refusal causes
back through that single return, so the fourth string is emitted in exactly
one place there. The causes themselves - an adapter that cannot enumerate
children, a `Statifier.Invoke.Source.resolve/2` reason, an unidentified
chart, an existing run - are enumerated in the comment on `start_child/3`
in `statifier_persistence`'s `lib/statifier_persistence/driver.ex`, and in
that repo's `sp-21o` note; `sp-ADR-0008` decision 4 states the
three-plus-one set rather than the causes, so the code comment is what this
sentence cites.

**Decision 7's third bullet reads as the durable variant, not the module.**
That bullet says the fourth reason "is the durable module's and cannot be
raised by the in-memory one", and beside this table a reader can take "the
durable module" for `StatifierBlocks.Runtime.DurableSubchart` - which would
have the record disagreeing with itself and with the code. Read it as the
durable **variant**: the handler here plus the executor `sp-ADR-0008`
describes, which decision 4 and the consequence on reading the two records
together already treat as one design in two halves. The contrast the bullet
draws is with the in-memory variant, which has no child run to fail to
create, and that contrast is exactly as true of the variant as the bullet
reads it of a module. No clause is edited, and the move is the same one the
ADR-0005 note of this date makes for its amendment 2b's "clears it".

Both halves of the split are visible in the shipped code: the same table
stands in `StatifierBlocks.Runtime.DurableSubchart`'s moduledoc under "The
refusal set, and which half raises which reason", and the driver's clause is
the one that spells the string.

Nothing about the closure changes. The set is still four, this package can
still not emit a fifth, and `StatifierBlocks.Runtime.Subchart` still has
three - it has no child run to fail to create. The record's closing bullet
above was written before the implementation landed; the design it describes
is what landed, and the mirrored pair stays open for the operator to close.

Filed with `sb-8fsb`, campaign-026.

---

## Note (2026-09-04): the closing bullet is superseded - both halves have landed

A dated note rather than an edit. The Consequences section closes with
**"Nothing here is implemented."** That sentence was true when this record
was written and is false now; it stays where it is, and this note supersedes
it.

**Both halves of the design landed on 2026-09-01, and the mirrored pair has
since been closed.**

| Half | Where it landed | Merged |
|---|---|---|
| The handler this record specifies - `StatifierBlocks.Runtime.DurableSubchart` in `lib/statifier_blocks/runtime/durable_subchart.ex` | this repository, PR 210, "Adds the durable subchart handler"; landed on `main` at `05f0a4a` | 2026-09-01 |
| The executor half `sp-ADR-0008` specifies - the `{:start_child, ...}` arm and `start_child/3` in `StatifierPersistence.Driver` | `statifier_persistence` PR 39, "Implements durable subchart child runs (ADR-0008)"; landed on `main` at `8f46a9c` | 2026-09-01 |

The implementation bead the bullet names, `sb-2i04`, and its mirror `sp-nt8`
were closed together by the operator on 2026-09-02, which is the event the
2026-09-01 note above was still waiting on when it wrote that "the mirrored
pair stays open for the operator to close". That clause of that note is
superseded here too; nothing else in it is.

What is *not* superseded is anything the bullet's second sentence says about
where the design is recorded. This is still the design record, `sp-ADR-0008`
is still its other half, and the two are still read together. The only claim
retired is that no code answers to them.

Two questions this record deliberately left to the implementation bead are
worth naming as still open rather than as answered by the landings. Whether
the durable stack can *detect and refuse* a host that wires the in-memory
module into a durable run - stated in Consequences as the implementation
bead's question, with this record explicitly not assuming it can - is not
something either merge settled. And the reference embedder's honest refusal,
`{:error, {:durable_subchart_unsupported, type}}`, is `statifier_examples`'
own bead by that same section and is not in either PR above. A reader should
not take "both halves landed" for "everything Consequences anticipated is
done".

No decision clause is edited and no status changes: this record's status
line stands as it was.

Filed with `sb-143s`, campaign-029.

---

## Note (2026-09-05): decision 4 read for a fan-out - the write is the enqueue

A dated note rather than an amendment. Decision 4 is unchanged in every clause.
For the single-child durable subchart this record specifies, the child run is
created inside the parent's serialized step, and a pure `start/2` still cannot
be the answer for the three reasons the section gives, in the order it gives
them. What this records is how the *first* of those three reasons - "a durable
start is a write, and it has to happen under the parent's exclusion" - reads
when the invocation being answered is a **fan-out** rather than a single child.
That case did not exist when this record was written: decision 6 above named
one invocation mapping to N children as a seam and refused to build it, and
ADR-0009 built it afterwards.

**For a fan-out the write under the parent's exclusion is the fan-out job's
enqueue.** ADR-0009 decision 3 compiles `core.map` to exactly **one**
`<invoke>`, so the parent's serialized step has exactly one invocation to
answer, and what that step durably records is the same pair decision 4
requires - the linkage, and the parent's position - with the linkage widened
to the ordered set of children ADR-0009 decision 10 names (`sp-ADR-0008`'s
amendment, bead `sp-3n2`). The step does not create N child runs. It records
the set and enqueues the work that will create them, and that enqueue is the
write that happens under the exclusion.

**The N children are created later, idempotently, from the linkage set.** Each
start reads the recorded linkage, creates the run for its position if no run
for that position exists yet, and is safe to run again when it is retried or
replayed - each one going through the starter seam the durable host wires,
which is decision 4's own answer to "which seam starts a child", applied N
times instead of once. Per-position idempotency is what carries the property
decision 4 bought by putting the write inside the exclusion. The window that
section calls out - a persisted parent that believes it has a child, and a
child run that was never created - does not open here, because the set is
already durable before any start runs: a position with no run is created on the
next attempt rather than being unrecoverable, and a position that already has
one is not created twice. How those starts are batched, bounded and
carried across a restart is `sob-djz`'s record, as ADR-0009 decision 9
already says; this note fixes only
where the exclusion boundary falls.

**Nothing about the single-child case changes.** Where one child is started the
run creation *is* the write, it happens in the parent's serialized step, and
every sentence of decision 4 applies as written - which is what the shipped
`StatifierPersistence.Driver` `{:start_child, ...}` arm does, per the
2026-09-04 note above. The fan-out reading is a second case beside it, not a
replacement for it, and the handler this record specifies,
`StatifierBlocks.Runtime.DurableSubchart`, is untouched by it: fan-out is a
different handler with a different invoke type (ADR-0009 decision 3), and
this record's refusal set stays four and closed.

Filed with `sb-uxko`, campaign-031 ruling `D31-9` (the 2026-09-05 scale walk).

## Note (2026-09-18): the unpublished identifiers cited above

A dated note, not an amendment: it changes no decision in this record.

The text above this Note cites rulings, or the questions they answered, by
identifiers that name entries in unpublished lists, so they name nothing a
public reader can follow. They stay as written, and this Note repeats none
of them.

The test `no lib/ or docs/adr/ file gains a private ruling or question id`
in `test/statifier_blocks/block_type_test.exs`, added in the same request as
this Note, fails when an identifier of the shapes it defines is added to a
Markdown file in this directory or to an `.ex` file under `lib/`.

Filed with `sb-4wh3`, campaign RF058.

---

## Amendment (2026-09-22): what a parent and its child agree on at publish, and who checks it

**Status: accepted (2026-09-22), drafted for `sb-mwpx`; the implementation is
`sb-vkyz`.** Additive: no text above this line is edited, every decision above
stands as written, and the header line's status history is not extended here.
This is an amendment rather than a dated Note because it decides five things
the record did not - what the parent/child interface is, where its check
lives, what a child republish may not do, what an unresolvable reference is at
publish, and what the check reads - and by this directory's README a note
decides nothing.

### Context

Decision 2 fixes how the handler resolves a child at **start**, and decision 5
fixes what a start may refuse for. Neither says what a published parent and a
published child have to agree on, and nothing checks it before an execution
starts. Two facts make that gap worth closing.

**A compile of one document cannot see the child.** `core.subchart` names its
child by document id in `chart` and declares, in `outcomes`, the outcomes the
author expects that child to finish with; the compile routes on them and
cannot read the child (the `StatifierBlocks.Core.Subchart` moduledoc, "Which
outcomes, and where the author says so"). Decision 6 already says a
cross-document cycle is the resolver's to report for the same reason. The
document graph is the host's: it holds every published document and knows
which parent names which child.

**The runtime does not refuse a disagreement; it misroutes it.** The parent's
`done.invoke` transitions are one conditioned arm per declared outcome and an
unconditioned arm last, and that last arm targets the first outcome the author
listed (`lib/statifier_blocks/core/subchart.ex:519`, `defp default_target/1`,
read at `aa657cd`). A child that finishes with an outcome the parent does not
route on therefore takes the parent's first-listed path, and no refusal in
decision 5 fires. What decision 5 does refuse at start is a reference that
does not resolve at all: `unknown_document`, its first reason.

Two checks across documents already exist, and this amendment says how it
stands beside each:

- `StatifierBlocks.ViewModel.outcome_findings/3`
  (`lib/statifier_blocks/view_model.ex:1863`, `def outcome_findings/3`, read
  at `aa657cd`) compares a `core.subchart`'s declared `outcomes` with a map of
  child finals the host supplies, in both directions, at `:warning`, and
  treats a child the map says nothing about as agreement.
- `StatifierBlocks.BlockType.agrees?/3`
  (`lib/statifier_blocks/block_type.ex:1023`, `def agrees?/3`, read at
  `aa657cd`) is ADR-0013 decision 4's dormant check of a `core.map`'s
  `collect_type` against the child's declared done-data **types**.

`%StatifierBlocks.Compiled{}` carries neither side of the interface today: its
fields are `scxml`, `provenance`, `record`, `invoke_types` and `warnings`
(`lib/statifier_blocks/compiled.ex:46`, `defstruct`, read at `aa657cd`).

### Decision

**A1. The interface a parent relies on is the child's declared outcomes and the
done-data keys the child declares.**

- A child's **declared outcomes** are the outcomes its root block declares:
  the set a `:child_use` compile gives one top-level `<final>` each
  (ADR-0004's 2026-08-29 child-use amendment, C1).
- A child's **declared done-data keys** are the names its root block's
  `donedata_type/1` declares (ADR-0013 decision 2), which a `:child_use`
  compile emits as `<param>`s on every top-level final (ADR-0013 decision 3).
- A `core.subchart` parent **routes on** the outcomes its author listed in
  `outcomes`, read through `child_outcomes/1`
  (`lib/statifier_blocks/core/subchart.ex:606`, `def child_outcomes/1`, read
  at `aa657cd`), so a parent that listed none routes on `done` for this
  check. That is the reading the check takes because it is what the compile
  emits: `child_outcomes/1` answers `["done"]` for an empty field, and the
  parent's conditioned `done` arm is built from that answer, so a child that
  does not declare `done` leaves that arm dead exactly as a listed name
  would. `error` is exempt, and a child
  is never required to declare it: `core.subchart` appends `error` to every
  parent's outcomes whether or not the author listed it, and a child reports
  an unhandled failure below its root as `error` without its root declaring
  it (`lib/statifier_blocks/compiler.ex:390`, `@propagated_outcome`, read at
  `aa657cd`).
- A `core.subchart` parent **reads no declared done-data key**. It routes on
  the compiler-minted `outcome` param and, when `assign_to` is set, writes the
  whole of `_event.data` to that path (`lib/statifier_blocks/core/subchart.ex:693`,
  the `<assign>` in `defp assign/1`, read at `aa657cd`). What a later block
  reads under that path is not declared anywhere today, and this amendment
  does not decide a declaration for it.
- A `core.map` parent **reads** the members its `collect_type` marks required,
  when `collect_type` resolves to a shape with members - the inline arm, or a
  name the parent's own declarations define. A `collect_type` that resolves to
  nothing with members contributes no keys: unknown is not disagreement. A
  `core.map` routes on its own two outcomes and on none of the child's
  (ADR-0009 decision 4).

References are recognized by block type module, not by type name, as
`outcome_findings/3` does, so a host palette that maps another name onto
either module is covered. No new block config key is decided here.

**A2. The package ships a pairwise check; the host walks its graph.**

The check is a pure function of **one parent and one child**, both as
`%Compiled{}` artifacts. The package holds no document store and gains no
publish step, and the check performs no IO. It comes in two directions, both
of them the host's to call:

- **Forward, when a parent is published.** For each reference in the parent,
  the host's resolver answers the child's currently published artifact, and
  the pair is judged: every outcome the parent routes on is a declared outcome
  of the child, and every key the parent reads is a declared done-data key of
  the child.
- **Reverse, when a child is republished.** The next child artifact is judged
  against each parent the host says currently references that child's
  document id, with the same two rules.

The publish-time resolver is a host function from a document id to
`{:ok, %Compiled{}}` or `{:error, :not_published}`. It is not decision 2's
`resolve_chart/2`, and decision 2's contract is unchanged by it.

**A3. A child republish that breaks an active parent is refused, naming the
parents.** A child revision that no longer declares an outcome some published
parent routes on, or a done-data key some published parent reads, is refused
at publish, and the refusal names every such parent document and the
referencing block in each. The way through is **expand, then contract**:
publish a child revision that declares both the old name and the new one,
republish each parent to route on or read the new name, then publish the child
revision that drops the old one. Executions already started are not the
concern of this check: a started child runs the chart resolved for it at its
start, which the start instruction carries in `invoke.content` (decision 3),
so a republish changes what the next start resolves and nothing already
running.

**A4. An unresolvable reference is a publish finding on the referencing
block.** When the resolver answers `{:error, :not_published}` for a parent's
reference, the parent's publish carries a finding anchored on that block's
`chart` field. At publish that answer is knowledge, not absence: the host
holds the graph and has said the child is not there. `unknown_document` stays
the runtime backstop for a reference that goes missing after publish.

**A5. What the check reads, and the finding it produces.**

- **The compile records the interface on `%Compiled{}`**, as one new field,
  `interface`, on every compile, whatever the chart-use option: the document's
  declared outcomes and declared done-data keys (A1's child side), and one
  entry per referencing block holding the block id, the referenced document
  id, the outcomes it routes on and the keys it reads (A1's parent side). It
  is a function of ADR-0004 decision 6's triple - the document's canonical
  bytes, the palette and the compiler version. Decision 6 as written
  guarantees the SCXML and the provenance map over that triple, and this
  amendment extends the same determinism to `interface`. The field adds
  nothing to the SCXML and therefore nothing to chart identity. It is not
  added to `%CompilationRecord{}`.
- **Every finding is a `StatifierBlocks.Finding` at `:error` severity with a
  new source, `:graph`**: the rule lives on an edge of the host's document
  graph, not in one document. This grows the source list of ADR-0005
  decision 11 (`lib/statifier_blocks/finding.ex:63`, `@type source`, read at
  `aa657cd`) by one value; the anchor union is unchanged.
- **Anchors.** An unresolvable reference is anchored `{:config, block_id,
  "chart"}`, an outcome the child does not declare `{:config, block_id,
  "outcomes"}`, and a key the child does not declare `{:config, block_id,
  "collect_type"}` - each on the referencing block, under the field its author
  would change.
- **Naming the parent.** The anchor has no document arm, and this amendment
  does not add one. In the reverse direction each finding is returned paired
  with the parent's document id, and its message names that document.

**How it stands beside the two existing checks.** `outcome_findings/3` is left
as it is: it remains the editor's advisory at `:warning`, both directions,
over a map a host may supply without holding compiled children. At publish,
A2 and A3 refuse the **dead-arm** direction: an outcome the parent routes on
that the child does not declare, whose conditioned arm can never match. That
is how every drop or rename of a child outcome shows at the parent. The other
direction, a child outcome the parent has **no** arm for - a child revision
that adds an outcome, for one - is the one that misroutes: it falls to the
unconditioned arm of ADR-0004's child-use amendment, C2, and so to the
parent's first-listed path. It is not refused here; it stays with that arm
and with `outcome_findings/3`'s `:warning`. A host that builds `chart_outcomes`
from each child's recorded `interface` gets the same set in both places.
`agrees?/3` is also left as it is: A2 checks that a read key is **declared**,
not what type it has. Type agreement stays ADR-0013 decision 4's dormant
advisory and is not raised to a refusal here, which also keeps that record's
record-against-record case out of the refusal.

**Worked example: patron registration.** The parent document
`patron_registration` has a `core.subchart` block `blk_VERIFY` whose `chart`
is `email_verification` and whose `outcomes` lists `verified` and `expired`.
The published `email_verification` revision's root declares the same two, so
the forward check returns nothing. A new `email_verification` revision renames
`verified` to `confirmed`. The reverse check against `patron_registration`
returns one `:error` finding, source `:graph`, anchored
`{:config, "blk_VERIFY", "outcomes"}`, paired with `patron_registration`, and
the host refuses the child's publish. Unchecked, the next start of that child
would finish `confirmed`, match no conditioned arm, and take the parent's
first-listed path, `verified`, with no refusal. Expand-then-contract gets
there: a child revision declaring `verified`, `confirmed` and `expired`, then
`patron_registration` republished to route on `confirmed`, then the child
revision without `verified`.

**What this does not decide.** The order the host walks its graph in, and
whether it walks it all at once; the host's document store, and what "active"
means for a parent beyond "currently published and referencing this document
id"; migration of any kind, automatic or not, of a parent or of a running
execution; how the editor renders `:graph` findings, and whether it runs the
check at edit time; the misrouting direction - a child outcome its parent
has no arm for, such as one a child revision adds - which is left to C2's
unconditioned arm and the editor's `:warning`; a declaration for keys read
under a `core.subchart`'s
`assign_to`; the done-data types A2 does not check; and the parameters a
parent passes to a child.

### Consequences

- `sb-vkyz` has a target: the `interface` field on `%Compiled{}`, the two
  directions of A2 over it, the `:graph` source, and the anchors in A5.
- A host's publish step gains two calls and refuses on their `:error`
  findings. Nothing in this package calls them, and the runtime refusals of
  decision 5 are unchanged.
- ADR-0004 decision 1's artifact grows by one field and ADR-0005 decision
  11's source list by one value, both through this amendment. Neither record
  is edited.
- A renamed outcome becomes a three-publish change instead of a one-publish
  change. That cost is deliberate: the one-publish change is the silent
  misroute described in the context above.

## Note (2026-09-22): `interface` reads the compile's `:datamodel` option beside decision 6's triple, and A2's check is judged pair by pair

A dated Note rather than an amendment: it carries no `Status:` line, decides
nothing, and edits no clause. It states two facts that sentences of the
Amendment of 2026-09-22 above read past. Each sentence read past its fact on
the day it was written: A1 already had a `core.map` read the members of "a
name the parent's own declarations define" (`:577-580`), and A2's own
forward bullet already had the host's resolver answer each child (`:595-599`).

### What `interface` reads

A5 says the `interface` field "is a function of ADR-0004 decision 6's
triple - the document's canonical bytes, the palette and the compiler
version" (`:635-637`). One member of it is not. A `core.map` whose `collect_type` is a
declared type name, rather than the inline arm, contributes the required
fields that name has in the typed datamodel document the compile's
`:datamodel` option supplies, and no keys when that option is absent or does
not declare the name. The "parent's own declarations" of A1 are that
document: nothing in the parent's stored bytes defines a type name. The
option is not in the triple, so one document, one palette and one compiler
version record different `reads` for such a reference with and without
`:datamodel`.

Every anchor below was read at `main` `abf3f06`; a later reader re-locates by
the anchor and not by the number.

- The private `interface/2` in `lib/statifier_blocks/compiler.ex` (`:3269`)
  reads its declarations off the options through `assignability_context/1`
  (`:1823`) and `StatifierBlocks.Environment.declarations/1`, and hands them
  to the private `required_members/2`, whose name arm fetches the trimmed
  name from them (`:3330`). The comment above `interface/2` says it reads the
  resolved tree and the `:datamodel` option and nothing else.
- The test `a collect_type naming a declaration reads its required fields,
  and unknown reads none` in `test/statifier_blocks/graph_test.exs` compiles
  one document twice, with and without `:datamodel`, and asserts `reads` of
  `["card_number", "branch"]` and `[]`.

The child side of `interface` and every `core.subchart` reference read the
resolved tree alone, so for a document holding no `core.map` with a named
`collect_type` the recorded `interface` is a function of the triple as A5
says. A5's other claims about the field hold: it adds nothing to the SCXML
and is not on `%CompilationRecord{}`.

### The shape of A2's check

A2 says the check "is a pure function of **one parent and one child**, both
as `%Compiled{}` artifacts", and that it "performs no IO" (`:590-592`). The
rule is judged one pair at a time, over the two artifacts' `interface`
fields, and the package ships it as two public functions, one per direction,
that each walk several pairs:

- `StatifierBlocks.Graph.check/2` (`lib/statifier_blocks/graph.ex:96`) takes
  one parent artifact and the host's resolver, and judges the parent against
  each child the resolver answers for a document id the parent names. The
  resolver is the host's function and the one call `check/2` makes that may
  touch IO; the module's own code performs none.
- `StatifierBlocks.Graph.consumers_broken/2` (`graph.ex:130`) takes one next
  child artifact and a list of parent artifacts, and judges the child against
  each parent's references to its document id. It takes no resolver.

Both hand each pair to the private `pair/3` (`graph.ex:157`), which reads
one reference and one child `interface` and nothing else.

## Note (2026-09-22): the Amendment of 2026-09-22 is flipped to accepted

A dated Note rather than an amendment: it carries no `Status:` line, decides
nothing, and edits no clause. The only line this request changes above it is
the Amendment's status line (`:495`), by one word, `proposed` to `accepted`.
Everything else is this Note and the one before it, at the foot of the file,
so no line another record cites moves.

The operator granted, on 2026-09-22, the flip of proposed records in this
repository. This request takes that grant for the Amendment alone, through the
same `docs/adr/` direction gate, after checking every claim the Amendment
makes against the code on `main`. The record's own header `Status:` line
(`:3`) is not extended.

Every `lib/` cite below was read at `main` `abf3f06` and is written anchor
first, line second. The Amendment's own cites are labelled `aa657cd`; those
that have moved still name what the Amendment says, and it is not edited for
them: `outcome_findings/3` now reads at `view_model.ex:1878`, the
`%Compiled{}` `defstruct` at `compiled.ex:110`, `@propagated_outcome` at
`compiler.ex:406` and `@type source` at `finding.ex:78`. `default_target/1`
(`subchart.ex:519`), `child_outcomes/1` (`subchart.ex:606`), the `<assign>`
in `assign/1` (`subchart.ex:693`) and `agrees?/3` (`block_type.ex:1023`) have
not moved.

### Each section, and where it reads today

| Section | Read at `abf3f06` |
|---|---|
| A1, the child side (`:551-556`) | `%Compiled{}`'s `interface` holds `declared_outcomes` from `BlockType.outcome_names/2` over the root block and `declared_donedata_keys` from its `donedata_type/1` (`interface/2`, `compiler.ex:3269`). The test `the child side is the root's outcomes and done-data keys, whatever the chart use` compiles one child with and without `child_use: true` and asserts the same interface |
| A1, the parent side (`:557-582`) | the private `reference/3` (`compiler.ex:3301`) records a `Subchart` reference with `routes_on` from `Subchart.child_outcomes/1` and `reads: []`, and a `FanOut` reference with `routes_on: []` and `reads` from `required_members/2`, which answers the required members of the inline arm or of a declared name and `[]` for anything else. It matches on the block type module, not the type name; no test pins that reading, because the tests' palette maps no other name onto either module. `StatifierBlocks.Graph`'s `@exempt_outcome` is `"error"`, and the private `pair/3` skips it. The tests `a subchart routes on its author's outcomes and reads nothing`, `a subchart with no outcomes listed routes on done`, `a map reads the members its inline collect_type marks required` and `error is exempt: a child need not declare it` pin each reading. What a named `collect_type` resolves against is the Note above |
| A2, a pairwise check in two directions (`:588-606`) | the two functions and the pair they judge are the Note above. Both judge over `interface`; `consumers_broken/2` also reads `record.document_id` on the child and on each parent (`graph.ex:131`, `:134`), to select the parent's references to that child and to name the parent. The module holds no store and starts no process. `@type resolver` (`graph.ex:73`) answers `{:ok, %Compiled{}}` or `{:error, :not_published}`, and its documentation says it is not the start-time `resolve_chart/2`. The tests `the stored pair returns no finding`, `a parent naming two distinct children judges each against its own` and `the resolver is asked once per distinct document id` pin the forward direction |
| A3, a breaking republish names the parents (`:608-619`) | `consumers_broken/2` returns one `{parent_document_id, finding}` pair per failed rule, and each message names the parent document; the anchor names the referencing block. The tests `the renaming revision names the stored parent` and `names every parent the next child revision breaks, and none other` pin it |
| A4, an unresolvable reference (`:621-626`) | `check/2` turns `{:error, :not_published}` into a finding anchored `{:config, block_id, "chart"}` (the private `unpublished/1`); the test `an unresolvable child is a finding on the referencing block's chart field` pins it |
| A5, what the check reads and produces (`:628-653`) | `interface` is on `%Compiled{}` (`compiled.ex:110`) and not on `%CompilationRecord{}`; the Chart stage sets it on every compile (`chart_stage/5`, `compiler.ex:3241`), after serializing, so it adds nothing to the SCXML. Every finding is built by `Finding.new/4` with source `:graph` and its default severity `:error` (the private `finding/3`, `graph.ex:183`); `:graph` is a member of `@type source` (`finding.ex:78`). The three anchors are the ones A5 names |
| How it stands beside the two existing checks (`:655-670`) | `outcome_findings/3` and `agrees?/3` are unchanged by it; the test `a child declaring an outcome the parent does not route on is not refused` pins the direction left to the `:warning` |
| Consequences (`:699-711`) | no module under `lib/` other than `StatifierBlocks.Graph` calls `check/2` or `consumers_broken/2`; `Publish.findings/3` does not |

The tests named above are in `test/statifier_blocks/graph_test.exs`.

### Sentences that name their own status

They are met here, not edited.

- The status line says "the implementation is `sb-vkyz`" (`:495-496`), and
  the Consequences say "`sb-vkyz` has a target" (`:701`). That implementation
  has landed; the table above is where it reads.
- The Context's "`%StatifierBlocks.Compiled{}` carries neither side of the
  interface today: its fields are `scxml`, `provenance`, `record`,
  `invoke_types` and `warnings`" (`:542-544`) describes the day it was
  written. `%Compiled{}` now carries `interface`, as A5 decided, and
  `accepts`, by `ADR-0014` decision 3.

### Sentences that no longer hold as written, and the records that name the change

- **"The anchor has no document arm" (`:651`).** It held when written, and
  the rest of that sentence and "the anchor union is unchanged" (`:645`)
  still hold: this Amendment adds no anchor. The union has since gained
  `:document`, by `ADR-0005`'s Amendment of 2026-09-22, "a `:document`
  anchor for the one finding that names no block", clause `11v`
  (`docs/adr/0005-liveview-editor.md:12022`); `@type anchor` reads it at
  `finding.ex:46`. Of the pairing decided here that Amendment says "that
  pairing is unchanged, and `:document` never names a document other than
  the one the list is about" (`docs/adr/0005-liveview-editor.md:12148-12149`),
  so the pairing with the parent's document id stands.
- **A5's triple sentence (`:635-637`) and A2's "one parent and one child"
  (`:590-592`).** Each read past a fact when written; the first Note above
  states both.

### Not decided by the Amendment

- **A reference inside a composite's expansion.** `interface/2` reads the
  resolved tree after expansion, so a `core.subchart` or `core.map` placed by
  a composite's expansion is recorded under its expansion member's block id,
  and a `:graph` finding on it anchors on a block id the author's stored
  document does not hold. A5 says each anchor is "on the referencing block,
  under the field its author would change" (`:649-650`) and does not say
  which block that is for an expansion member; re-anchoring such a finding
  onto the composite block is not decided here.

Filed with `sb-tysd`, campaign RF069.

## Amendment (2026-09-22): a `core.map` `collect_type` name that cannot be resolved without `:datamodel` is reported unchecked

**Status: accepted (2026-09-22), drafted for `sb-kndj`, which also carries the
implementation.** Additive: no text above this line is edited, the Amendment
of 2026-09-22 above (A1 to A5) and the Notes after it stand as written except
where the section "What this changes above" says otherwise, and the header
line's status history is not extended here. This is an amendment rather than
a dated Note because it decides three things the record did not - that a
host need not pass `:datamodel`, what `interface` records when a key check
cannot be made, and the severity of the report - and by this directory's
README a note decides nothing.

### Context

A1 lets a `core.map` read the members its `collect_type` marks required when
the name is one "the parent's own declarations define", and says that a
`collect_type` that resolves to nothing with members "contributes no keys:
unknown is not disagreement" (`:578-580`). Two dated Notes of 2026-09-22
record what those declarations are: `ADR-0004`'s Note "`interface` also
varies with the `:datamodel` compile option"
(`docs/adr/0004-compiler-provenance.md:4221`), and this record's Note on what
`interface` reads (`:722`). Both say that a parent compiled without
`:datamodel` records `reads: []` for a `core.map` whose `collect_type` is a
name. `ADR-0004`'s Note adds that `StatifierBlocks.Graph.check/2` and
`StatifierBlocks.Graph.consumers_broken/2` then pass the key check for that
reference without a finding, and it leaves open whether a host must pass
`:datamodel` (`docs/adr/0004-compiler-provenance.md:4252`).

Every code cite below was read at `1d0d873`; re-locate by the anchor, not by
the number. The declarations of a compile given no `:datamodel` are empty
(`StatifierBlocks.Environment.declarations/1`,
`lib/statifier_blocks/environment.ex:489`), and the name clause of the private
`required_members/2` answers `[]` for a name they do not hold
(`lib/statifier_blocks/compiler.ex:3330`). A host that omits the option
therefore gets a key check that looks complete and is not.

### Decision

**U1. A host is not required to pass `:datamodel`.** No compile is refused
for its absence, and neither check refuses a parent or a child because of it:
an option the host chose not to pass is not an author's error.

**U2. `interface` marks a named `collect_type` it could not resolve.** Every
entry of `references` gains one field, `unresolved`. For a `core.map`
reference it is the trimmed `collect_type` name when that name is not blank
and the compile was given no `:datamodel` (the option absent or `nil`). It is
`nil` in every other case: the inline arm, an absent or blank `collect_type`,
a name read against a supplied `:datamodel`, and every `core.subchart`
reference. When `unresolved` is set, `reads` is `[]`, as A1 already has it.
The field is a function of the same inputs as the rest of `interface`, the
`:datamodel` option included, and like the rest it adds nothing to the SCXML.

**U3. Both directions report the unchecked read at `:warning`.** Where A2
judges a reference whose `unresolved` is set against a child - forward, when
the resolver answers that child; reverse, for each of a parent's references
to the next child's document id - the pair yields one
`StatifierBlocks.Finding` with source `:graph` and severity `:warning`,
anchored `{:config, block_id, "collect_type"}` on the referencing block. Its
message names the type name and says the done-data keys read there are
unchecked because the name is not resolvable without `:datamodel`. In the
reverse direction it is paired with the parent's document id and its message
names that parent, as A5 has it for every finding. It is never an `:error`,
so a host that refuses on `:error` findings, as the Consequences above have it
(`:703`), does not refuse on it. The outcome check for the same reference is
unchanged, and a reference whose child the resolver answers
`{:error, :not_published}` yields A4's `:error` alone.

With `:datamodel` supplied nothing changes: a name the datamodel declares
reads its required members, the key check judges them as A1 and A2 say, and
no `:warning` is produced.

### What this changes above

- A1's "unknown is not disagreement" (`:580`) stands: an unresolved name
  contributes no keys and no `:error`. What changes is that one kind of
  unknown, a name with no `:datamodel` to resolve it against, is reported
  instead of passing without a finding.
- A5's "Every finding is a `StatifierBlocks.Finding` at `:error` severity"
  (`:641`) holds for every finding but U3's, which is a `:warning`. A5's
  anchor for a key finding is the one U3 uses.
- `ADR-0005`'s clause `11y` says `StatifierBlocks.Graph` produces `:graph`
  findings "always at `:error`" (`docs/adr/0005-liveview-editor.md:12344`).
  After U3 it also produces a `:warning`. `ADR-0005`'s clause `11i` already
  made severity and source independent
  (`docs/adr/0005-liveview-editor.md:2573`), so the enum `11y` adds to is
  unchanged; `ADR-0005` is not edited, and this amendment is where the change
  is recorded.
- `ADR-0004`'s Note and this record's Note on what `interface` reads stay
  true of `reads`: U2 adds a field beside it and changes neither.

### Worked example: patron registration

The parent `patron_registration` has a `core.map` block `blk_CARDS` that runs
the child `library_card_issue` once per household member, with
`collect_type` the name `library.card_receipt`; the host's datamodel declares
that name with the required fields `card_number` and `branch`, and the
published `library_card_issue` declares both as done-data keys. Compiled with
that datamodel, the reference reads `card_number` and `branch`, `unresolved`
is `nil`, and both directions return nothing. Compiled without `:datamodel`,
the reference reads nothing and `unresolved` is `"library.card_receipt"`:
`check/2` against the same child returns one `:warning` anchored
`{:config, "blk_CARDS", "collect_type"}`, and `consumers_broken/2` returns it
paired with `"patron_registration"`. Before this amendment both returned
nothing.

### What this does not decide

- **A name that a supplied `:datamodel` does not declare.** `unresolved`
  stays `nil` for it, `reads` is `[]`, and the key check passes it without a
  finding, as before.
- How the editor renders a `:graph` `:warning`, as A5 leaves every `:graph`
  rendering undecided.
- Anything about done-data types, which stay `ADR-0013` decision 4's dormant
  advisory.

### Consequences

- Each `references` entry of `%Compiled{}`'s `interface` carries
  `unresolved`, and `StatifierBlocks.Graph`'s two functions may return a
  `:warning` beside their `:error` findings.
- A host that passes `:datamodel` sees no change. A host that does not sees
  one `:warning` per such reference in each judged pair, and clears it by
  passing the option or by writing the `collect_type` inline.

## Note (2026-09-22): the rendering non-decision the second Amendment credits to A5 is the first Amendment's, in its "What this does not decide"

A dated Note rather than an amendment: it carries no `Status:` line, decides
nothing, and edits no clause. It states where one sentence of the Amendment
on an unresolvable `collect_type` name points, which was inexact on the day
it was written.

That Amendment leaves "How the editor renders a `:graph` `:warning`"
undecided, "as A5 leaves every `:graph` rendering undecided" (`:967-968`).
A5 (`:628-653`) decides what the check reads and the finding it produces,
and says nothing about rendering. The sentence that leaves "how the editor
renders `:graph` findings" undecided is the first Amendment's paragraph
"What this does not decide" (`:687-697`), which follows A5, "How it stands
beside the two existing checks" and that Amendment's worked example. The
non-decision carried over holds as written; only the clause it is credited
to is inexact.

Filed with `sb-qiox`.

## Note (2026-09-22): the Amendment on an unresolvable `collect_type` name is flipped to accepted

A dated Note rather than an amendment: it carries no `Status:` line, decides
nothing, and edits no clause. The only line this request changes above it is
the status line of the Amendment on an unresolvable `collect_type` name
(`:859`), by one word, `proposed` to `accepted`. Everything else is added at
the foot of the file - this Note and the dated Note just above it - so no
line another record cites moves.

The operator granted, on 2026-09-22, the flip of proposed records in this
repository. This request takes that grant for this Amendment alone, through
the same `docs/adr/` direction gate, after checking every claim it makes
against the code on `main`. The record's own header `Status:` line (`:3`) is
not extended.

Every `lib/` and `test/` cite below was read at `main` `4508edd` and is
written anchor first, line second; a later reader re-locates by the anchor
and not by the number. The tests named below are in
`test/statifier_blocks/graph_test.exs`.

### Each section, and where it reads today

| Section | Read at `4508edd` |
|---|---|
| U1, no host must pass `:datamodel` (`:895-897`) | `StatifierBlocks.Compiler.compile/3` (`compiler.ex:508`) takes `:datamodel` among its options and no clause refuses a compile for its absence: the tests' `defp compile!/2` fails a test unless the compile answers `{:ok, %Compiled{}}`, and each of the three tests named in the U3 row below compiles a parent through it without `:datamodel`. Neither `Graph` function answers an `:error` for the absence; U3's finding is a `:warning` |
| U2, `unresolved` on every reference (`:899-907`) | `@type child_reference` (`compiled.ex:80`) carries `unresolved`, typed `String.t()` or `nil`, and its doc states U2's cases. The private `interface/2` (`compiler.ex:3276`) takes the declarations as `:no_datamodel` when `Keyword.get(opts, :datamodel)` is `nil`. The private `reference/3`'s `Subchart` clause (`compiler.ex:3308`) sets `unresolved: nil`; its `FanOut` clause (`compiler.ex:3321`) sets it from the private `unresolved/2`, which answers the trimmed name for a non-blank binary under `:no_datamodel` (`compiler.ex:3365`) and `nil` otherwise (`compiler.ex:3372`). The private `required_members/2` reads the inline arm first (`compiler.ex:3342`) and answers `[]` for a name under `:no_datamodel` (`compiler.ex:3348`). The tests "a collect_type name compiled without :datamodel is marked unresolved, and with it is not" and "the inline arm and a blank collect_type are never marked unresolved" pin it |
| U3, a `:warning` in both directions (`:909-922`) | `check/2` (`graph.ex:112`) and `consumers_broken/2` (`graph.ex:149`) judge each pair through the private `pair/3` (`graph.ex:175`). For a reference whose `unresolved` is a binary (`graph.ex:185`) it builds one finding through the private `finding/4` (`graph.ex:211`) with `severity: :warning`, source `:graph` and anchor `{:config, block_id, "collect_type"}`, in place of the key rule; the outcome rule beside it is unchanged. The forward message (`graph.ex:226`) and the reverse one (`graph.ex:242`) each name the type name and say the keys read are unchecked because it "names a type that is not resolvable without :datamodel"; the reverse one names the parent, and `consumers_broken/2` pairs each finding with the parent's document id. In `check/2` a child answered `{:error, :not_published}` yields the private `unpublished/1`'s finding alone (`graph.ex:123`). The tests "a read left unchecked without :datamodel is a warning on the collect_type field", "a read left unchecked without :datamodel is a warning paired with the parent" and "an unpublished child of an unresolved reference is the chart error alone" pin it |
| with `:datamodel` nothing changes (`:924-926`) | the test "with :datamodel a named collect_type's keys are checked as before" asserts no finding when every key the datamodel marks required is one the child declares, and one `:error` and no `:warning` when the datamodel requires one the child does not; the last assertion of "a read left unchecked without :datamodel is a warning paired with the parent" asserts no finding in the reverse direction |
| What this changes above (`:930-945`) | `StatifierBlocks.Graph`'s moduledoc, under "The findings", says every finding is an `:error` but the one `:warning`; the `:graph` entry of `StatifierBlocks.Finding`'s `@type source` documentation reads "at `:error` but for one `:warning`" (`finding.ex:75`) |
| the worked example (`:949-960`) | the tests above build it: a parent from `defp registration/1` with `cards: "library.card_receipt"`, the `core.map` block `blk_CARDS`, the child `library_card_issue`, the parent id `patron_registration`, and `@card_receipt_datamodel` declaring `card_number` and `branch` required. Each result the example states for the code as amended is an assertion of the tests named in the rows above; its closing sentence, what both functions returned before this amendment, describes the earlier code and no test asserts it |
| Consequences (`:974-979`) | as U2 and U3 above; `changelog.d/sb-kndj.md`, under "Changed", not yet promoted, records the change for a host |

Every record cite the Amendment makes reads at `4508edd` as the Amendment
quotes it: of this file `:578-580`, `:580`, `:641`, `:703` and `:722`; of
`docs/adr/0004-compiler-provenance.md` `:4221` and `:4252`; and of
`docs/adr/0005-liveview-editor.md` `:2573` and `:12344`.

### Sentences that name their own status

They are met here, not edited.

- The status line says the drafting request "also carries the
  implementation" (`:859-860`). That implementation is on `main`; the table
  above is where it reads.

### Sentences that no longer hold as written, and the records that name the change

None reverses what the Amendment decides.

- **The Context's code cites, read at `1d0d873` (`:885-890`).** The private
  `required_members/2`'s name clause moved with the implementation from
  `compiler.ex:3330` to `compiler.ex:3350`; `Environment.declarations/1`
  (`environment.ex:489`) has not moved.
- **The Context's "A host that omits the option therefore gets a key check
  that looks complete and is not" (`:890-891`).** It described the code
  before this date; U3 itself changes the answer, read above.
- **`ADR-0005`'s clause `11y`, "always at `:error`"
  (`docs/adr/0005-liveview-editor.md:12344`).** That record is not edited.
  The third bullet of "What this changes above" (`:937-943`) is where the
  `:warning` a `:graph` finding may now carry is recorded, and this flip
  accepts it there.

### Sentences stated exactly

- **"as A5 leaves every `:graph` rendering undecided" (`:967-968`).** The
  dated Note just above says which paragraph leaves it undecided
  (`:687-697`).

Filed with `sb-qiox`.
