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
