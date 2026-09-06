# ADR-0009: Durable fan-out is a new block type, `core.map`, compiling to one invocation whose handler starts N children

Status: accepted (2026-09-01, campaign-026; unqualified direction-agent
verdict on the second review, after one cure)

## Context

ADR-0008 decision 6 named a seam and refused to build it: *"One invocation
mapping to N children is a seam this design leaves room for and does not
build."* It said what was missing in as many words - "not machinery but
decisions - what block type expresses fan-out, and what aggregation policy
turns N answers into one outcome" - and it said the walk should happen against
working single-child machinery. That walk has now happened. This record is its
output.

Three things were settled before it, and this record implements them rather
than reopening any of them.

**The durable single-child machinery exists and is designed.** The operator's
`DS-a` to `DS-h` rulings (2026-08-31, recorded on `sb-2i04` and its mirror
`sp-nt8`) fixed the mechanism: a child start is a pending dispatch on the async
seam, the completion comes home through the seam's public `done.invoke` and
failure doors, there is no bespoke parent-child channel, the linkage lives in
run metadata with a mandatory chart-identity pin, and cancel cascades while
retaining records under a distinct terminal status with late completions
dropped idempotently. `DS-f` is the ruling that deferred fan-out to this walk.
ADR-0008 states the handler half of all of that, and `sp-ADR-0008` states the
linkage and stepping half.

**The question of whether `core.foreach` could carry it is closed.** `sb-7em`
carried the open half of that question since campaign-015. The operator's
campaign-026 ruling `R26-2` answers it: `core.foreach` stays synchronous and
SCXML-faithful, and durable fan-out is a **new block type**. This record is
where that answer is written down, and `sb-7em` is answered on its face by it.
The substantive reason is in decision 1.

**The aggregation and accumulation vocabulary is ruled, not open.** Campaign
026's `R26-3` fixes the aggregation vocabulary at `all` and `first_error` with
`quorum` reserved and unbuilt; `R26-4` fixes accumulation at one author-named
datamodel location, list-ordered by item index, with errors in place; `R26-5`
widens the linkage to an ordered set (`sp-ADR-0008`'s amendment, bead `sp-3n2`);
`R26-6` puts the concurrency bound in the runtime with a block-level hint the
runtime clamps (`sob-djz`'s record). This record states the halves of those that
are this package's - what the author writes and what the compiler emits - and
cites the other two repositories for the halves that are theirs, per the
umbrella's contract-ownership rule.

**What this record therefore has to answer**, and nothing wider: what block type
expresses fan-out, what it declares, what it compiles to, what the author writes
to choose an aggregation policy and to name where the answers land, and what
discipline the accumulated payload is under when N is large.

**What this record does not do is build any of it.** Campaign 026's ruling
`R26-1` defers the implementation to a later campaign. There are no `lib/`
changes here and no row is added to ADR-0002 decision 10's vocabulary table -
that table records fifteen types (G11, which supersedes G8's count) and
`StatifierBlocks.Palette.core_types/0` now registers the same fifteen
(`lib/statifier_blocks/palette.ex:87-104`, since `sb-uag7` landed the two
modules G11 was still waiting on), and they should go on agreeing until the
code lands.

## Decision

### 1. Fan-out is a new block type, and `core.foreach` is untouched

**`core.foreach` stays exactly what it is**: a container whose body runs once
per item of a datamodel list, compiled to a plain Appendix D loop - a snapshot
of the list, a cursor, an inner head that binds the item, a body, and an
internal loop-back transition (ADR-0002 G6, ADR-0004's F1 to F6). It is
synchronous, it is SCXML-faithful, and the body's states exist once however long
the list is. Nothing in this record changes one byte of it, one callback of it,
or one field of its config schema.

That is not a concession; it is the reason a second type is needed. SCXML's own
`foreach` is a sequential, in-macrostep construct, and `core.foreach` is a
faithful realisation of it. Fan-out is the opposite shape in every respect that
matters: N children run **concurrently**, each is its own durable run that may
outlive the process that started it, and the parent reaches quiescence and waits
rather than iterating. Making one type mean both - by a config flag, by a
`durable: true` key, by a slot that behaves differently when the host wires a
different handler - would put a property that changes the *execution model* on
the same footing as a property that changes a label. ADR-0008 decision 1
rejected exactly that shape for exactly that reason on the handler side ("a flag
that sometimes made it write to storage would make that property conditional on
a value, which is the same as not having it"), and the argument transfers
without weakening.

There is a second reason, specific to the authoring surface. A `core.foreach`
body is *blocks*, compiled into the parent chart. A fan-out child is a *chart*,
resolved by document id and started as its own run. Those are different things
for an author to point at, they are validated differently, and they fail
differently. One type that meant blocks under one flag and a document id under
another would not be one type.

**This answers `sb-7em`.** That bead asked two ADR-level questions raised by
`sb-i61`: whether sibling `core.foreach` blocks binding the same
`item_as`/`index_as` should share a compiler-owned root, and where the
host-declared items source is declared. The first is answered by this record
only in the sense that it removes the pressure that made it urgent - the racing
case it worried about was "safe in sequence, a race in parallel lanes", and
`core.foreach` is now settled as never the parallel one, so its two
compiler-owned roots (G6a) stay per-block and unshared, which is what upstream
`{:duplicate_id}` already enforces. The second question - an author-facing
declaration of the items source - is not this record's and is not answered here;
it belongs to ADR-0006's declared-path set and ADR-0005 11e's advisory, and it
applies to `core.map`'s `items` field exactly as it applies to
`core.foreach`'s and `core.assign`'s. `sb-7em`'s durable-fan-out half is
answered; its declaration half was never fan-out's to answer.

### 2. The type is named `core.map`

The working name is adopted as the name. `R26-2` left the naming to this record;
this is the decision.

`map` says what the block means to the author's data: one item in, one answer
out, per item, with the answers collected in order. That collection is not
incidental - it is decision 4, the whole visible result of running the block -
and `map` is the one short word that already implies it.

The alternatives considered:

* **`core.fanout`** names the mechanism rather than the meaning. It says that N
  things start and says nothing about what comes back, which leaves the ordered
  result list unnamed by the type that produces it.
* **`core.parallel_foreach`** collides twice in three words. `core.parallel`
  already means static named lanes, declared at authoring time (ADR-0002
  decision 10, G7); `core.foreach` already means the synchronous loop this
  record just finished separating fan-out from. A name built out of both
  invites the reader to assume it is a variation on either.
* **`core.each_chart`** and similar were considered and are worse than
  `core.subchart` at saying "subchart", which is the thing it would be trying
  to say.

**The name is engineer-facing and the palette label is not.** ADR-0002 decision
1 names types by string and the palette owns the human text; a `map` that reads
as jargon to a non-engineer author is a palette-entry problem with a
palette-entry fix, and the label the implementation should ship is of the form
"Run a chart for every item", not "Map". This is worth stating because the
naming objection to `map` is real and the answer to it is not to rename the
type.

### 3. It compiles to **one** `<invoke>`, and the handler is what fans out

A compiled `core.map` is a compound state whose inner state carries exactly
**one** `<invoke>`, with an `id` of the block id, a `src` carrying the per-item
chart's document id verbatim, and a constant `type` from `invoke_type/0`. It is
one invocation in `active_invocations`, one entry in the parent's persisted
position, one `done.invoke.<block id>` transition and one
`error.communication.invoke.<block id>` route. The compiled bytes do not scale
with N and cannot: N is a runtime value read out of the datamodel, and the
compiler never sees it.

**The invoke type is a new constant**, in the shape `core.subchart`'s is - one
definition site, returned by `invoke_type/0`, not a config field - because which
handler starts children is deployment state rather than authoring state
(`st-ADR-0051`). It is a *different* string from
`"statifier_blocks:subchart"`: a host that has wired a single-child subchart
handler has not thereby wired a fan-out handler, and a document that reached
such a host should fail to find a handler rather than silently start one child.
The spelling is the implementation bead's, in the same `namespace:name` grammar
`StatifierBlocks.Core.Config` already owns.

**The `<param>` list carries the list, not N copies of an item.** The compiled
params carry the `items` datamodel path once, plus the author's `item_as` and
`index_as` names and any literal params, and the handler is what evaluates the
list and binds one item to each child. That is the precise content of "one
invoke whose handler fans out", and it is what keeps ADR-0004 decision 6's byte
determinism intact: the same document compiles to the same bytes whether it will
run over three items or three thousand.

**A per-item chart, not a per-item body.** `core.map` names a chart by document
id, as `core.subchart` does, and each child is a run of that chart. An inline
`body` slot - blocks compiled into a child document at compile time - was
considered and is not built. It is a genuinely attractive authoring shape and it
is a strictly larger design: it needs a rule for what a compiled-out-of-line
subtree's identity is, how ADR-0004's provenance map addresses a position inside
it, and how the chart-identity pin `DS-b` makes mandatory is computed for a
document that has no document id. None of those is answered by any accepted
record, so building it here would be guessing. It is named as a possible later
addition and deliberately not decided, in the same posture ADR-0008 decision 6
took toward this record.

### 4. The declaration surface

The type is written on ADR-0007 decision 1's `use StatifierBlocks.BlockType`
layer, and it declares:

| Callback | Value |
|---|---|
| `slots/1` | one `zero_or_one` slot per outcome, named `on_<outcome>`, `on_done` then `on_error`, with `slot_style: %{"on_error" => :failure}` |
| `outcomes/1` | `[{"done", "Done"}, {"error", "Error"}]`, fixed, not config-derived |
| `invoke_type/0` | the constant of decision 3 |
| `current_version/0` | `1` |
| `io/1` | `%{kinds: [:step], produces: :unknown, slot_accepts: %{"on_done" => [:step], "on_error" => [:step]}}` |

`config_schema/1` declares, in order:

| Key | Type | Required | Notes |
|---|---|---|---|
| `chart` | `:string` | yes | the document id of the chart run once per item; `src` carries it verbatim, as ADR-0004 R1 has it for `core.subchart` |
| `items` | `:string` | yes | `datamodel_path?: true`, the list to run over, exactly as `core.foreach`'s `items` |
| `item_as` | `:string` | yes | default `"item"`, the name the child sees its item under |
| `index_as` | `:string` | no | the name the child sees its position under, when the author wants one |
| `assign_to` | `:string` | no | decision 5's single accumulation location |
| `aggregate` | `{:select, ...}` | no | decision 6's policy, default `"all"` |
| `max_concurrency` | `:integer` | no | decision 7's hint |
| `params` | `:string` | no | literal params sent to every child, `core.subchart`'s field unchanged |

The field vocabulary is deliberately `core.foreach`'s (`items`, `item_as`,
`index_as`) and `core.subchart`'s (`chart`, `assign_to`, `params`) rather than a
third set of names for the same three ideas. An author moving a synchronous loop
to a durable fan-out should be changing the block type and the `chart` field,
not relearning what the list field is called.

**`assign_to` keeps the one grammar it already has**: a bare lowercase
identifier, validated by the shared `check_assign_to`, refused with the same
finding text `core.invoke` and `core.subchart` produce today. There is no
per-item path grammar and no dotted form; decision 5 is why.

**The outcome set is fixed at two, and this is a real decision rather than a
default.** `core.subchart` takes its outcomes from the child chart, because one
child reports one outcome and an author can branch on it. N children report N
outcomes, and there is no meaning to be had by joining them into one branch
target - "seven said `approved` and one said `declined`" is data, not control
flow. So the per-child outcomes go where data goes (decision 5) and the block's
own outcome says only whether the fan-out as a whole succeeded. An author who
wants to branch on the answers reads the accumulated list with a `core.branch`
after the block, which is the same shape any other datamodel-driven decision
has.

*[Note added 2026-09-05, with `sb-7haw` under campaign-031, after `sb-kqno`
landed `StatifierBlocks.Core.Map` (PR 281, `a852429`). The shipped
`config_schema/1` is **four fields**, not the eight this table declares, and
two of the four are spelled differently. This Note records the shipped
surface and what became of the rest; the table above is not edited, per this
record family's amendment convention, and it remains the reading of what was
proposed on 2026-09-01.

**What ships, in declaration order:** `items` (`{:path, %{}}`, required),
`chart` (`:string`, required), `collect` (`{:path, %{}}`, optional), `on`
(`{:select, ...}` over `all` and `first_error`, optional, default `"all"`).
ADR-0002's G15 of this date is the row, read off the module.

**`collect` is this table's `assign_to`, and `on` is its `aggregate`.** The
ideas are decision 5's and decision 6's unchanged - one author-named
accumulation location, and the two-word policy with `quorum` reserved - and
only the spellings moved. Two things moved them. `assign_to` was chosen here
as `core.subchart`'s word, but this field is now declared with the `{:path,
opts}` field type ADR-0002's 2026-09-05 amendment on decision 7 added, which
did not exist when this table was written; `collect` says what the block does
with the answers rather than borrowing a name whose grammar it now only
partly shares, and it keeps the same finding text so an author meets one
complaint and not two. And `on` is the operator's campaign-031 amendment
`RQ-031-4`, option (b): the scheduler that fans out **reads the policy off
the `on` param verbatim**, so the authored word and the param name are the
one word the runtime keys on, with no translation step between the record's
vocabulary and the wire. Decision 6's permitted set is untouched by either
move, and refusing everything outside it is still what reserves `quorum`.

**Four declared fields are DEFERRED, not dropped.** `item_as`, `index_as`,
`max_concurrency` and `params` are not in the shipped surface. Deferring them
is what this Note records; **dropping** any of them would be a decision about
this record's declaration surface, and this Note does not make it. Each is
still live, and each has somewhere it would be decided:

- `item_as` and `index_as` are the names a child sees its item and its
  position under. Nothing in the shipped emission carries them, so a child
  chart today reads whatever the fan-out handler passes it, which is the
  handler's contract rather than this one's.
- `max_concurrency` is decision 9's hint. Campaign 031's ruling `D31-9` puts
  the bound itself in the fan-out runtime as a configuration key, refused at
  runtime on the ordinary error route, and says a block-level hint is clamped
  rather than honoured below the queue limit - so a field here would be a
  hint to a runtime that already has the number, and the shape it should take
  is worth deciding beside that runtime rather than ahead of it.
- `params` is `core.subchart`'s field unchanged, and its absence here is the
  narrowest of the four: it is literal params sent to every child, and the
  shipped `<param>` list carries only the four fields above.

A later bead decides each, on this record, against the runtime as it then
stands. Until one does, the table above declares them and the module does not,
and a reader who finds that gap is looking at this Note and not at drift.

Filed with `sb-7haw`, campaign-031, from `sb-kqno`'s two recorded residues.]*

### 5. Answers accumulate in one author-named location, ordered by item index

`assign_to` names **one** datamodel location, and the whole result of the block
is written there: a list, one element per item, in **item index order**, dense -
its length is the length of `items`, always, including when a child failed and
including when `first_error` cancelled the rest.

Four properties follow, and each is chosen rather than incidental.

**Order is by item index, never by completion order.** Children complete in
whatever order the runtime and the work give them, and that order is not
reproducible across a restart, a redeploy or a change of concurrency bound. If
the stored list followed it, the same chart over the same input would produce
different bytes on different days, and a provenance-addressed position or a
replayed trace would mean something different each time. Ordering by index makes
the result a function of the input.

**Errors sit in place.** A child that failed occupies its own index, carrying
the `st-ADR-0068` shaped failure - `reason`, `detail`, `attempts` where it
applies - rather than being omitted or collapsed to `nil`. Omitting it would
break the density guarantee and silently shift every later item's position;
`nil` would be indistinguishable from a child that legitimately answered
nothing. An author reading index 4 gets item 4's fate, whichever fate it was.

**Under `first_error`, cancelled siblings occupy their indices too**, carrying
the distinct terminal status `DS-c` requires rather than an error of their own -
a cancelled child did not fail, it was stopped, and a reader that cannot tell
those apart cannot tell a failing input from a fast failure elsewhere in the
batch. The exact spelling of that status is `sp-ADR-0008`'s, and this record
does not mint one.

**The write happens once, at the invocation's completion.** `assign_to` is
written on the success transition, in the shape ADR-0007 decision 2 already
describes for a leaf step - the answer is only an answer when the call answered.
There is no incremental write as each child lands. Writing incrementally was the
obvious alternative and it loses on three counts: it turns one datamodel write
into N, each of which is a step the parent has to be woken for and a position
that has to be persisted; it makes the intermediate states of the location
observable and therefore something an author might reasonably build on; and it
gives the ordering guarantee above nothing to stand on, because a partially
filled list has to encode "not yet" for every index that has not landed.

### 6. Aggregation is `all` or `first_error`, and `quorum` is reserved

`aggregate` takes one of two values today. The default is `"all"`, and it is
the default because it is the policy that discards nothing.

**`all`** waits for every child to settle. Every index in the accumulated list
gets its child's answer or its child's error, and the block then takes its
`done` outcome. A child failing does **not** cancel its siblings and does not
by itself route the block to `error`: the failure is data at its index, and the
author decides what a batch with three failures in it means, because only the
author can. The block's `error` outcome under `all` is reserved for a failure
of the fan-out itself - decision 8's refusals - and reaching it means no useful
list exists rather than that some children failed.

The alternative reading of `all` - "all must succeed, or the block errors" -
was considered and rejected. It is expressible in the accepted shape (branch on
the list) and it is not recoverable from the rejected one: a block that routes
to `error` on the first failure while still waiting for the rest has to decide
what to do with the answers that arrive afterwards, and a block that routes to
`error` after waiting for all of them has thrown away which ones succeeded
unless it also writes the list, in which case it is this decision plus a branch.

**`first_error`** is the policy for a batch where one failure makes the rest
worthless. The first child to fail causes the remaining live siblings to be
cancelled through the `DS-c` cascade - retained records, the distinct terminal
status, recursion through the children's own children, nothing deleted, late
completions dropped idempotently - and the invocation answers through the
seam's failure door, so the block takes its `error` outcome and the `on_error`
slot runs. The accumulated list is still written and still dense: the failing
index carries its error, completed indices carry their answers, and cancelled
indices carry the cancelled status. An `on_error` slot that cannot see how far
the batch got is much less useful than one that can.

"First" is by **failure arrival**, not by index. Two children failing near
simultaneously is a race the runtime resolves, and the record does not pretend
otherwise: which of them is recorded as the cause is whichever the runtime
observed first, and the other is recorded at its own index as the failure it
was, not as a cancellation. What is guaranteed is that exactly one failure
routes the outcome and that no completed answer is discarded.

**`quorum` is reserved, named, and not built.** The shape it would take is
clear enough to name and not clear enough to decide: it needs a threshold, a
spelling for that threshold (a count, a fraction, or both), a rule for what
happens to the children still running when the threshold is met, and a rule for
what the accumulated list contains for indices that had not landed. None of
those is ruled, and guessing one to have a third value in the select is how a
vocabulary gets a value nobody meant. What the record does reserve is the
**word**: `validate_config/1` refuses any `aggregate` outside `["all",
"first_error"]` with a finding naming the two permitted values, so no host can
establish a private meaning for `quorum` in the interval, and the value is free
when its own walk happens.

**The key is read through its default**, in `core.parallel`'s G7a shape: an
absent `aggregate` reads as `"all"` everywhere, so a stored block written before
the key existed - or written by an author who never opened the field - compiles
identically. A stored `null` is not an absent key and is refused (ADR-0001
decision 6), as `core.parallel`'s `complete` is.

### 7. The payload discipline for large N

This is the section `R26-4` asks for, and it exists because the accumulated
list has a cost profile a single `assign_to` does not.

**The cost is per-step, not per-run.** The list lives in the parent's
datamodel, and the parent's datamodel is part of the machine state that is
serialized on every persisted step for the rest of the run. A batch of a
thousand children each answering a two-kilobyte object is a two-megabyte
datamodel that is written again every time the parent moves, long after the map
block finished. That is the discipline's whole motivation, and an author who
knows only that "the answers are collected" will not derive it.

The discipline, in the order it should be applied:

1. **The child chart decides the size of its own answer.** The element stored at
   an index is the child's outcome payload - its `<donedata>` - as it stands,
   not a transcript of the child's run. Keeping that payload to what the parent
   actually needs is the one lever that scales, because it multiplies by N. A
   child that answers `%{"status" => "approved", "ref" => "..."}` costs a
   thousandth of one that answers its whole datamodel, and the record's guidance
   to a host is to treat a map child's outcome as an API response rather than as
   a dump.
2. **An error element is a reason, not a diagnosis.** Errors in place carry the
   `st-ADR-0068` `reason`/`detail` shape; `detail` is a JSON-shaped map, and the
   place for a stack, a request body or a provider transcript is the host's
   telemetry, which already carries it, and not N copies in the parent's
   datamodel.
3. **`assign_to` is optional and omitting it is supported.** A fan-out whose
   answers the parent does not need - the children write their own results
   somewhere durable, and the parent only needs to know they finished - declares
   no `assign_to` and accumulates nothing. Nothing else about the block changes:
   the aggregation policy still governs the outcome, and `first_error` still
   cascades. This is the cheapest correct shape for a large batch and it should
   be the documented first suggestion when N is large, not an afterthought.
4. **A cap, if measurement forces one, belongs at the runtime.** This record
   sets no numeric limit, because there is no honest place to put one: the
   compiler cannot know N, and a limit expressed in the block would be a
   deployment property written into a document (which is exactly what decision 7
   says such properties must not be). If a bound is needed, it is the runtime's
   to enforce and to refuse against, and its refusal is a failure of the
   invocation carried on the ordinary error route - not a compile finding and
   not a validation finding.
5. **`sensitive?` applies unchanged, and there is no per-item exception.** If
   the answers are sensitive, the location holding N of them is sensitive
   (ADR-0002 decision 7's key and the secrets rule behind it). A list is not
   less sensitive than its elements, and nothing in this record creates a
   category of data that escapes that declaration.

**No compression, no truncation, no spill.** Each is a plausible mitigation and
each would make the stored value something other than what the author asked for,
which is the one property decision 5 exists to preserve. A datamodel location
that sometimes holds the answers and sometimes holds a truncated summary of them
is worse than one that is too big, because the second failure is visible.

### 8. Refusals: ADR-0008's four, plus exactly one that is this handler's

The fan-out handler is a different handler from ADR-0008's, and this record does
not touch ADR-0008's set. That set is four, closed, and stays four for the
single-child durable subchart handler.

The fan-out handler reuses those four verbatim, because it resolves and compiles
a chart by exactly the same shared contract (ADR-0008 decision 2), and adds
exactly one of its own:

| Reason | When | New here |
|---|---|---|
| `unknown_document` | the resolver answered `:error`, or `src` was not a binary | no |
| `child_compile_findings` | the per-item chart resolved and did not compile | no |
| `cycle_refused` | the resolver answered `{:cycle, path}` | no |
| `child_run_creation_failed` | creating a child run did not succeed | no |
| `items_not_a_list` | `items` resolved to something that is not a list | **yes** |

The set is closed at five for this handler.

**Why `items_not_a_list` is needed and is not one of the four.** It is the one
failure that is neither about the chart nor about storage: the author named a
datamodel path, the path resolved, and what came back was a map, a string or
nothing. Folding it into `unknown_document` would say the chart is missing,
which is false. Leaving it out would mean a fan-out over a non-list either
crashes the parent's step or quietly starts zero children and reports success,
and the second is much the worse of the two - a batch that silently did nothing
is indistinguishable from a batch that had nothing to do.

**Which is why an empty list is not a refusal.** `items` resolving to `[]` is a
successful fan-out over nothing: zero children start, the accumulated list is
written as `[]`, and the block takes `done` immediately. That is the arithmetic
answer and it is also the useful one - a workflow that maps over a list that
happened to be empty this time has not failed.

**`child_run_creation_failed` under a partial fan-out.** N children start; child
k may fail to be created after k-1 succeeded. This is not a refusal of the
invocation, because the invocation has already partly happened, and it is
handled by the aggregation policy exactly as a child failure is: under `all`, it
occupies index k as an error and the batch continues; under `first_error`, it
cancels the live siblings and routes `error`. The refusal reason is reserved for
the case where the invocation could not start at all. Whether creating children
is all-or-nothing within a batch is `sob-djz`'s and `sp-ADR-0008`'s to say, not
this record's; this record only fixes what the block does with either answer.

**The carrier is the path's, not the handler's.** As ADR-0008 decision 5 has it:
the durable path's failing arm produces
`error.communication.invoke.<block id>`, with `st-ADR-0068`'s payload, caught by
the block-level `on_error` transition through SCXML's descriptor prefix rule,
because the `<invoke>` carries `id=<block id>`. Same mechanism, one more string.

### 9. Concurrency is the runtime's, with a hint the runtime clamps

Per `R26-6`. `max_concurrency` on the block is a **hint**. The runtime owns the
actual bound, the runtime clamps the hint to it, and the host wins every
disagreement. A hint above the runtime's bound is clamped down silently rather
than refused; a hint below it is honoured; an absent hint means the runtime's
own default.

The reason is that how many children may run at once is a property of the
deployment - queue capacity, database connections, downstream rate limits, what
else is running tonight - and not of the workflow. The same document is correct
at concurrency 1 and at concurrency 200, and an author who wrote 200 into a
document has written a fact about one cluster into an artefact that outlives it.
What the author does legitimately know is the *shape* of the work - that these
children are expensive, or that the downstream tolerates little parallelism -
and that is what a hint expresses.

The compiler validates the hint's **shape** and nothing else: a positive
integer, or absent. It does not compare it to anything, because there is nothing
in the document to compare it to.

**The batching contract is `sob-djz`'s record and is not restated here.** How
child starts are batched onto the queue, how the bound is enforced across a
batch, and what happens to a batch spanning a restart are `statifier_oban`'s to
decide and to state. This record's only dependency on it is the guarantee above:
whatever the batching does, the accumulated list is ordered by item index, so
batching may reorder execution freely without reordering results.

### 10. Linkage: the ordered set is `sp-ADR-0008`'s amendment

Per `R26-5`, and cited rather than restated. `sp-ADR-0008`'s amendment (bead
`sp-3n2`) widens an invocation's linkage to an ordered set of child run ids with
per-child status, adds the item index to child run metadata, and reads the
single-child case as the N=1 degenerate one. Storage and stepping are
`statifier_persistence`'s contract, per the umbrella's ownership rule.

This record depends on exactly one thing from it, and states the dependency so
that a reader knows why the amendment matters here rather than only there: **the
item index reaches the child's own metadata.** That is what makes decision 5's
index ordering recoverable when completions arrive out of order, across a
restart, from a process that did not exist when the child started - the index is
not held in memory anywhere and does not need to be, because it is durably on
the child.

Nothing else about the linkage is this record's, and the mandatory
chart-identity pin (`DS-b`, ADR-0004 R2), the cancel semantics (`DS-c`), and the
nesting posture (`DS-e`, which applies to a map child exactly as it does to a
subchart child) are cited as they stand.

### 11. What this record does not change

* **`core.foreach`.** Decision 1. Not one callback, not one config key, not one
  compiled byte, and its two compiler-owned roots (G6a) stay per-block.
* **`core.subchart`.** Its row (G5), its emission (ADR-0004 C1 to C3), its
  author-declared outcome set, and its invoke type constant are all unchanged.
  `core.map` is a sibling of it, not a mode of it, for decision 1's reasons
  applied one level down.
* **ADR-0008's handler.** Its shape, its purity argument, its instruction, and
  its four-reason closed set are untouched; decision 8's fifth reason belongs to
  a different handler, and the in-memory `StatifierBlocks.Runtime.Subchart`
  gains nothing at all.
* **The two-registry seam.** ADR-0002 decision 2 holds: `core.map` **names** an
  invoke type and runs nothing. A fan-out handler, when it is written, is a
  module under `StatifierBlocks.Runtime.*` per ADR-0007's 2026-08-31 note, on
  the running side of the line, resolving no block type and appearing in no
  palette.
* **The effect vocabulary and chart identity.** Both are `statifier-ex`'s. This
  record mints no instruction, no event name and no identity rule, and cites
  `st-ADR-0051`, `st-ADR-0052` and `st-ADR-0068` rather than restating them.
* **ADR-0002 decision 10's table.** No row is added. The table records fifteen
  types (G11, which supersedes G8's thirteen), and
  `StatifierBlocks.Palette.core_types/0` registers the same fifteen
  (`lib/statifier_blocks/palette.ex:87-104`) now that `sb-uag7` has landed the
  `core.drafts` and `core.placeholder` modules G11 recorded the table as
  running ahead of. They should still agree the day after this record is
  accepted. `core.map`'s row would be the **sixteenth**, and it is an ADR-0002
  amendment that lands with the implementation - the implementation bead's to
  write, not this record's.
* **ADR-0006 and ADR-0005 11e.** `core.map`'s `items` carries
  `datamodel_path?: true` and is subject to the declared-path advisory on
  exactly the terms every other datamodel path is. This record neither widens
  nor narrows that advisory.

## Consequences

**Two block types now look similar and mean different things, and the palette
has to say so.** `core.foreach` and `core.map` both take a list and both do
something per item, and an author scanning a palette will see two cards that
rhyme. The mitigation is in the palette entry and the card's second line
(ADR-0002 amendment H): the difference an author needs is "runs the blocks
inside it, one item at a time" against "runs another chart for every item, all
at once", and that sentence has to be in the palette rather than only in this
record. Getting it wrong is a real authoring hazard and it is a documentation
fix, not a design one.

**Durability is again a property of the host's wiring.** As ADR-0008's first
consequence has it for subcharts: the same document, compiled to the same bytes,
does what the host's registered handler does. A host that has wired no fan-out
handler gets an unresolved invoke type, which is the correct and visible
failure. A host that wires a fan-out handler that runs children in-process gets
a fan-out that does not survive a restart, which is legal, is sometimes what a
test wants, and is not what a durable deployment should have.

**The accumulated list is a new way for a chart to get large, and the record
says so out loud.** Decision 7 is unusually prescriptive for this repository's
records, and deliberately: every other datamodel write in the `core.*`
vocabulary is bounded by what an author typed, and this one is bounded by a
runtime list length. A host that adopts fan-out without reading decision 7 will
find out about it from a serialization cost weeks later, which is the worst
possible place to learn it.

**`sb-7em` is answered and closes on this record's acceptance.** It is not
closed by this record's author; the campaign's conductor owns that, and the bead
carries no mirror.

**This record, `sp-ADR-0008`'s amendment and `sob-djz`'s batching record have to
be read together.** Each is incomplete alone: this one says what the author
writes and what the compiler emits, the second says how N children are linked
and stepped, the third says how their starts are batched and bounded. That
split follows the umbrella's contract-ownership rule and it follows the
precedent ADR-0008 and `sp-ADR-0008` already set for single-child.

**Nothing here is implemented.** Campaign 026's `R26-1` defers the
implementation, and this record carries no `lib/` change, no test, and no
palette registration. What it produces is a design that a later campaign can
build from without another rulings walk, and a set of decisions that are
answerable against working single-child machinery - which is the condition
ADR-0008 decision 6 set for having this walk at all.

---

## Note (2026-09-05): decision 7 above Tier A - the batch is the unit

A dated note rather than an amendment. Decision 7 is unchanged in every clause:
the five-step discipline stands in the order it gives, clause 4 still puts a
cap at the runtime rather than in the document, and "no compression, no
truncation, no spill" still holds. What this records is the direction taken by
the 2026-09-05 scale walk (campaign-031 ruling `D31-9`) for the range decision
7 does not reach - what an author does when N is large enough that a chart run
per item is the wrong unit of work.

**Two tiers, and this record specifies the first of them.** Call the design
this record specifies **Tier A**: one chart run per item, one element per item
in the accumulated list, up to a bound the runtime enforces. It is the right
shape for exactly as long as a per-item run earns its cost - the item waits on
something, branches on an answer, or has to be separately observable and
resumable. **Tier B** is what happens above that bound, and the direction taken
is that it is not a bigger Tier A.

**Above Tier A the batch is the unit.** Tier B is expressed in the vocabulary
this record already has, not in a second block type: the author writes
`core.map` over **chunk descriptors** - one item per chunk rather than one per
row - and each child invokes a single bulk data-plane handler for its whole
chunk. Everything this record decides applies to that document unchanged; N is
the number of chunks, and the accumulated list decision 5 orders by item index
is one element per chunk. A row inside a chunk that turns out to need what Tier
A gives - it waits, or it branches - is **promoted**: that row becomes a run of
its own on Tier A's terms, and the rest of its chunk stays in the bulk path.
Promotion is the exception the shape pays for, not the default; a design in
which most rows promote has chosen the wrong tier rather than found a defect in
this one.

**The boundary rule, in one sentence: the chart orchestrates batches, the data
plane processes rows.** A row that only needs computing does not need a run,
because a run buys durability, observability and resumability at the per-step
serialization cost this section opens on, and computing a row needs none of the
three. A
chart earns its place where the work has to *wait*, be *resumed*, or be
*branched on*, and that is a property of batches at Tier B and of items at Tier
A. The rule is what decides which tier a workload belongs in, and it is
deliberately about the shape of the work rather than about a number.

**Tier A's bound is enforced at runtime only, and the compiler validates
nothing about N.** Clause 4 says a cap, if measurement forces one, belongs at
the runtime; the scale walk fixes it there and nowhere else. It is a
configuration key of the fan-out runtime, whose batching record is `sob-djz`,
with a default of 1,000, and exceeding it fails the invocation on the ordinary
error route - the `error.communication.invoke.<block id>` route decision 3
names - rather than producing a compile finding or a validation finding. This
package's side is unchanged and validates nothing about N, because it cannot
see N: decision 3 has the compiled `<param>` list carry the `items` datamodel
path **once** rather than the list, and decision 4's `config_schema/1` declares
`items` as a `:string` with `datamodel_path?: true`, so the value a bound would
apply to exists only at runtime, where the handler evaluates the path. That is
the same reason clause 4 gives for setting no numeric limit in this record, and
the scale walk does not change it - it only says where the number that clause 4
declined to write now lives.

Filed with `sb-uxko`, campaign-031 ruling `D31-9`.

---

## Note (2026-09-05): decision 7's discipline - `items` are descriptors

A dated note rather than an amendment. Decision 7's five clauses are unchanged
and stand in the order given. This adds one sentence to the discipline, from
the same 2026-09-05 scale walk (campaign-031 ruling `D31-9`).

**`items` are descriptors - ids, ranges, chunk handles - never row payloads.**

It is this section's opening cost argument - "the cost is per-step, not
per-run" - applied to the question rather than to the answer. The list `items`
resolves to is read out of the parent's datamodel, and the parent's datamodel
is serialized on every persisted step for the rest of the run, so a fan-out
over ten thousand order ids costs what ids cost and a fan-out over ten thousand
order records costs what records cost - for the whole life of the parent, not
for the duration of the map block. A child that is handed an id
resolves it to the row it needs at the point of use, where the cost is per
child and transient; a child that is handed the row saves that lookup and
charges the parent for it forever. The discipline is the same one clause 1
states for the outcome payload, and it belongs on both ends of the block for
the same reason.

It is also what makes the Tier B reading in the note above expressible in this
record's existing fields rather than in a new one: a chunk handle is a
descriptor, so "`core.map` over chunk descriptors" needs nothing from decision
4's declaration surface that a descriptor list does not already satisfy.

Filed with `sb-uxko`, campaign-031 ruling `D31-9`.

---

## Note (2026-09-06): decision 4, two of the four deferred fields are decided, and two stay deferred

A dated Note rather than an amendment: decision 4's declaration surface is
unchanged in what the module declares today, no line above is edited, and the
2026-09-05 Note that deferred four fields keeps every word. What this Note
records is that two of the four now have the record the earlier Note said each
was owed, and that the other two are still deferred for reasons worth writing
down.

That Note deferred `item_as`, `index_as`, `max_concurrency` and `params`, said
deferring was not dropping, and said each had "somewhere it would be decided".

**`item_as` and `index_as` are decided in `ADR-0011` decision 11: kept, with
the defaults `item` and `index`.** The somewhere turned out to be the typed
environment. `ADR-0011`'s walk binds the two names **inside the fan-out body**,
so a block in the body that reads `item` reads a path the environment holds,
put there by the fan-out rather than by any block. Without them the body has no
vocabulary for what it is iterating over, and a walk that cannot name the item
cannot check a read inside a body at all. That record does not change what the
handler passes a child; it names what the walk knows.

**`max_concurrency` stays deferred**, on this record's own argument: campaign
031's ruling on the fan-out runtime put the bound in the runtime as a
configuration key and clamps a block-level hint below the queue limit, so a
field here would be a hint to a runtime that already has the number.

**`params` stays deferred**, with one reason added to the narrowness the
earlier Note gave it: `ADR-0011` makes the values a handler reads path
literals, so a `params` member sending literal values to every child would put
two spellings of "what the child gets" into one declaration surface. That
collision is worth deciding on purpose rather than by shipping.

Neither is dropped. Dropping either is still a decision about this record's
declaration surface and still this record's to make.

Two further facts about this record that `ADR-0011` states and does not change.
`collect` is typed there as `{:list, :unknown}` - a list, dense and in
item-index order per decision 5 - because the shipped child recipe emits the
outcome name and nothing else; whether a child chart may declare what its
`donedata` carries is left as this record's open question, on decisions 5 and 6,
and `sb-pg91` carries it. And `collect`'s bare-lowercase-identifier refusal is
deliberately **not** reached by `ADR-0011` decision 13, which resolves only
`core.subchart`'s `assign_to`; whether the two fields should agree is named
there as a deferred question rather than answered.

---

## Note (2026-09-06): decision 8 stands - the empty fan-out succeeds over nothing

A dated Note rather than an amendment. Decision 8 is unchanged in every clause:
the refusal set for this handler is still closed at five, `items_not_a_list` is
still the one reason that is this handler's own, and the paragraph above that
opens "Which is why an empty list is not a refusal" keeps every word. What this
Note records is that the question of whether that paragraph was right was
asked, and answered in its favour.

**The question.** `sb-kha0` asked, on 2026-09-05, whether `items` resolving to
`[]` is answered or refused, and by whom - because the shipped fan-out
invocation in `statifier_oban` refuses it on the invocation's error route while
this decision says it succeeds. The two layers disagreed, and an accepted record
disagreeing with shipped code is a defect in one of them rather than a matter of
taste.

**The answer, taken by the operator on 2026-09-06 as campaign-033 ruling
`RQ-033-4`: this decision wins.** `items` resolving to `[]` is a successful
fan-out over nothing, exactly as the paragraph above has it - zero children
start, the accumulated list is written as `[]`, and the block takes `done`
immediately. There is no refusal reason for an empty list, and the refusal set
stays the five this decision closes it at. The reasoning is the paragraph's own
and is not restated here.

**The runtime half is `sob-as0` in `statifier_oban`**, which drops the refusal
arm, updates the handler's documentation of what it refuses, and adds a case
for an empty `items` that assembles the empty list and completes. This
package's side needs no change, and this Note carries no `lib/` change: nothing
here declares anything about the length of `items`, because the compiled
invocation carries the `items` datamodel path once rather than the list
(decision 3, as the 2026-09-05 Tier A Note above restates), so the length
exists only at runtime where the handler evaluates the path.

**One thing this Note does not decide.** Decision 4 fixes this block's outcome
set at two, `done` and `error`, not config-derived, and the campaign-033 bead
`sb-napt` proposes a failure-classed outcome that would reach that decision.
Whether it does, and what it would change here, is that bead's record to write
and not this one's.

Answers `sb-kha0`. Filed with `sb-xwhj`, campaign-033 ruling `RQ-033-4`; the
runtime half is `sob-as0`.

## Note (2026-09-06): decision 4's outcome set stays two, and `error` becomes failure-classed

A dated Note rather than an amendment, and the answer to the question the Note
above this one left open in as many words: "Decision 4 fixes this block's
outcome set at two ... and the campaign-033 bead `sb-napt` proposes a
failure-classed outcome that would reach that decision. Whether it does, and
what it would change here, is that bead's record to write." This is that
record's entry, and the answer is that decision 4 is unchanged in every clause.

**The outcome set is still two, and still fixed.** `outcomes/1` returns
`[{"done", "Done"}, {"error", "Error"}]`, not config-derived, and no third
outcome appears. Decision 4's sentence that "the outcome set is fixed at two,
and this is a real decision rather than a default" keeps every word, and so
does the paragraph behind it: N children still report N outcomes, joining them
into one branch target still has no meaning, and "seven said `approved` and one
said `declined`" is still data rather than control flow.

**What is new is a class, not an outcome.** `StatifierBlocks.Core.Map` now
also exports `failure_outcomes/1`, the optional callback ADR-0002's Note of
this date records, returning `["error"]`. It says of an outcome that already
exists that reaching it means the block finished badly. The whole of its
effect is one compiled byte span, described in ADR-0004's Note of this date:
when a `core.map` is a document's **root** block, that document's top-level
`<final>` for `error` carries a reserved `<donedata>` `<param>` a durable
stepper reads to decide the run failed. Nothing about the block's own
compilation inside a parent chart changes, and nothing about a nested
`core.map` changes at all.

**Decision 5 is untouched, and `collect` still holds data.** The alternative
considered and not taken was to let a failed child reach control flow - to
grow the outcome set, or to route per-child failure somewhere other than the
accumulated list. Decision 4's reasoning refuses both and this Note follows
it: the per-child answers stay in `collect`, one element per item in index
order, dense, errors sitting at their own index in the `st-ADR-0068`
`reason`/`detail` shape decision 7 clause 2 gives them. An author who wants to
branch on which children failed reads that list with a `core.branch` after the
block, exactly as decision 4 already tells them to. The class answers a
different question - *did the fan-out as a whole end badly* - which is the
question the block's own `error` outcome was already the answer to.

**Decision 6's aggregation policy decides which outcome is reached, and this
Note adds no rule to it.** `all` and `first_error` still govern whether a batch
with a failed child takes `done` or `error`; the class only says what taking
`error` means to a stepper.

**Decision 8 is untouched**, including the empty-list paragraph and the Note
above that reaffirmed it. An empty fan-out still succeeds over nothing and
takes `done` immediately, so it never reaches the failure-classed outcome -
the two campaign-033 rulings agree rather than collide.

**Decision 7 is untouched.** No payload grows: the reserved param is one fixed
attribute on one final of the parent document, not a per-item cost, and
it multiplies by nothing.

Filed with `sb-napt`, mirrored with `sp-n8g` in `statifier_persistence`;
campaign-033 ruling `RQ-033-3`.

## Note (2026-09-06): decision 4's `item_as` and `index_as` reach the shipped emission, so one sentence of the 2026-09-05 deferral is historical

A dated Note rather than an amendment, and it edits nothing above this line. It
decides nothing the Note of 2026-09-06 above ("two of the four deferred fields
are decided") did not already decide; what it adds is that the pair is now
**declared and emitted** rather than only named in `ADR-0011`, and that one
sentence written while they were neither is now a statement about the past.

`sb-otpv` gave `StatifierBlocks.Core.Map` an `item_as` field (`:string`,
default `item`) and an `index_as` field (`:string`, optional), each refused
unless it is a bare lowercase identifier, and the emitted `<invoke>` carries
`item_as` as a `<param>` always - through its default when the author sets
nothing - and `index_as` as one only when the author declares it.

The sentence is the deferral bullet for the pair, in the 2026-09-05 block
beneath decision 4 (`:266-269`): "Nothing in the shipped emission carries them,
so a child chart today reads whatever the fan-out handler passes it, which is
the handler's contract rather than this one's." True when written, and now
historical on both halves - the emission carries them, and what a child sees
its item and its position under is this record's declaration rather than the
handler's private convention. Decision 3 is why they are params and nothing
else: the `<param>` list is the handler's whole input. `ADR-0002`'s G15 row and
the Note beneath it read the shipped declaration, and that Note of this date
records the six-field count.

`max_concurrency` and `params` are untouched by this and stay deferred exactly
as the Note above leaves them, on the reasons it gives each. Deferring is still
not dropping.

Filed with `sb-uewa`, folding `sb-z4vz`; campaign-034 ruling `RQ-034-6`.

## Note (2026-09-06): what `collect` holds for a child that ends in a failure-classed final, and where a nested `core.map` failure goes

A dated Note rather than an amendment. Decision 4's outcome set is still two
and still fixed, decision 5's `collect` is still one dense element per item in
item-index order, decision 6's two policies still decide which outcome the
block reaches, and decision 8's empty fan-out still succeeds over nothing. The
Note of this date filed with `sb-napt` said all four, and this one repeats none
of the reasoning.
What is recorded here is the answer to the question campaign 033 left deferred -
what the shipped fan-out writes into `collect` for a child whose own run ended
badly - and one sentence about where a nested `core.map`'s `error` now goes,
from ADR-0002's amendment of this date.

**The question.** `sb-napt` classed this type's `error` outcome as a failure
and left a verification item behind it: a child chart that now settles in a
failure-classed final is a child run the durable stepper marks failed, and
nothing in this record said what the batch's accumulated list carries at that
child's index. Decision 5 says errors sit at their own index in the
`st-ADR-0068` `reason`/`detail` shape, decision 7 clause 2 says the same, and
whether the shipped code agreed was not checked.

**It agrees, and this is what it writes.** Read off
`statifier_persistence`'s `Driver` on 2026-09-06. A child run whose chart
settles in a failure-classed final is stored with status `failed` - that is
`statifier_persistence`'s ADR-0008 amendment of the same date - and the driver
answers the parent's invocation with `{:failed, reason: <the run's failure>}`
rather than with donedata. The assembled list is dense over
`0..child_count - 1`, and the entry at a failed child's index is a map with
string keys:

| Key | Value |
|---|---|
| `"index"` | the item's index, as for every other entry |
| `"status"` | `"failed"` |
| `"failure"` | a map with `"reason"`, `"attempts"` and `"detail"` - `st-ADR-0068`'s own three keys |

A child that completed carries `"status" => "completed"` and its `"donedata"`
instead, and a child `first_error` cancelled before it started - or cancelled
mid-flight - carries `"status" => "cancelled"` and nothing else. So a reader of
`collect` distinguishes the three terminal fates by one key, and reads a failed
item exactly as they read a failed single invocation, which is decision 5's
sentence and decision 7 clause 2's shape both honoured. **No runtime bead is
filed**: the shipped handler is right, and this Note is the record catching up
to it rather than the other way round.

Two things follow that are worth writing down because a reader will ask.
`"failure"` is a map rather than the `reason` string alone, which is what makes
a `core.branch` after the block able to distinguish a refused call from an
exhausted retry without a second read. And a failure-classed child does **not**
by itself decide the block's own outcome: decision 6's `all` and `first_error`
still do, unchanged, and an `all` batch with one failed child still reaches
`done` with that child's failure sitting in the list. The class says what
reaching `error` means, never when it is reached.

**Where a nested `core.map`'s `error` goes.** The Note of this date filed with
`sb-napt` said the class changes one thing and only for a document whose root
block is a `core.map`. From ADR-0002's amendment of this date that is no longer
the whole of it: a `core.map` **below** the root whose `on_error` slot is empty
now reaches the document's own failed final too. Two halves of that amendment
make it so - its section 2, which emits this type's `error` final whether or
not the `on_error` slot is occupied, so the block raises
`done.outcome.<state id>.error` in the empty case at all; and its section 4,
which catches that event on the root block's state under `child_use: true` or
`terminate: true`.
Neither half alone would reach a nested batch. A `core.map` whose `on_error`
slot is occupied is handled and reaches nothing - the author said what happens
when the batch ends badly and it happens. Nothing in this record changes with
it: the outcome set is still two, `collect` still holds the same list, and the
block's own compilation inside a parent chart is untouched. What changed is
only what the enclosing **document** does when nobody caught the block's
`error`.

Filed with `sb-ii2k`, campaign-034 rulings `RQ-034-1` and `RQ-034-13`; the code
is `sb-hxs5`, and ADR-0002's amendment of this date is where the propagation
rule is stated.

## Amendment (2026-09-06): decision 4, `collect` admits a dotted datamodel path through the shared location helper

**Status: proposed (2026-09-06, campaign 034, bead `sb-pxkf`).** A decision
record merges at proposed under campaign 034's invariant; flipping it to
accepted is a separate gated request. Additive: decision 4 stands as accepted,
and no text above this line is edited by this section.

An amendment rather than a Note, because decision 4 decides this field's
grammar in as many words and this record now decides it differently. Nothing
above this line is edited. Decision 4's sentence - "**`assign_to` keeps the one
grammar it already has**: a bare lowercase identifier, validated by the shared
`check_assign_to`, refused with the same finding text `core.invoke` and
`core.subchart` produce today. There is no per-item path grammar and no dotted
form; decision 5 is why" - keeps every word, and this amendment supersedes its
"no dotted form" clause for this field by addition. The per-item half of that
sentence is untouched and stays refused.

**What is decided.** The accumulation field - `assign_to` in decision 4's
table, `collect` in the shipped surface the 2026-09-05 Note beneath it records
- accepts a **dotted datamodel path**, in exactly the grammar the other three
`<assign location="...">` fields this package writes already accept:
`core.invoke`'s `assign_to`, `StatifierBlocks.InvokeStep`'s `assign_to`, and
`core.subchart`'s `assign_to`. That grammar is
`StatifierBlocks.Core.Config.datamodel_path?/1` - a non-empty string carrying
no whitespace, the predicate `core.assign` reads for the location it writes -
and it is reached through `StatifierBlocks.Core.AssignLocation`, the helper
`sb-r313` introduced to hold the one refusal shape behind all four fields. A
bare lowercase identifier is still a valid `collect`, because every bare
lowercase identifier is already a datamodel path: this widens the field and
refuses nothing it accepted before.

**Both of this field's sites move, not one.** `check_collect/2` and the
emission's own `collect/1` in `StatifierBlocks.Core.Map` each call
`AssignLocation` with `Config.identifier?/1` today, and they read one rule so
that the two cannot disagree - `emit/2` has to answer for a config
`validate_config/1` would have rejected. What changes is the predicate passed
at both call sites and the finding text that goes with it; the helper itself is
unchanged, which is what it was extracted for.

**Why decision 5 does not forbid it.** Decision 4's sentence gives one reason
for the narrow grammar and names decision 5 as the argument, so the amendment
owes an answer to decision 5 rather than to the sentence. Decision 5 is about
**per-item** locations: the per-child answers are one dense list in item-index
order, written once to one author-named place, rather than N writes an author
addresses one at a time. That argument is untouched here. A dotted `collect` is
not a per-item path; it is the parent's single write location, one `<assign>`
to one place - exactly the write decision 5 describes - and all this amendment
says is that the one place may be `cards.answers` and not only `answers`.
Decision 5 forbids N locations; it says nothing about how deep the one location
is.

**Why it is decided this way round rather than the other.** `collect` is
declared with ADR-0002 decision 7's `{:path, opts}` field type, carrying
`writes: {:list, :unknown}`, so the editor already offers the host's declared
datamodel paths as candidates on it - dotted ones among them - while the
validation refused everything but a bare identifier. `ADR-0011` decision 13
named that shape in as many words for `core.subchart`'s `assign_to`: "A control
that offers what its own validation refuses is a defect either way round, so
which way to fix it is a decision rather than a repair." It resolved
`core.subchart`'s by widening the validation to match the candidates, and it
deliberately did not reach this field, saying so - "`collect`'s emission is
ADR-0009's rather than this decision's", and "[w]hether the four should agree is
in the deferred list". This amendment is this record making that decision for
its own field, in the same direction and for the same reason: the same
`<assign>` element writes the same datamodel, so there is one location rule to
have, and the rule with the dotted worked example in it is the one that is
right.

**What does not change.** The outcome set is still two and still fixed.
Decision 5's list is still dense, one element per item, in item-index order,
and this amendment says nothing about what one element of it holds. Decision
6's two policies still decide which outcome the block reaches. Decision 8's
empty fan-out still succeeds over nothing. A blank `collect` is still the
author declining to accumulate, which is `AssignLocation`'s first clause rather
than this field's rule at all. And this reaches `collect` and nothing else:
what a child chart may declare its `donedata` carries, decision 5's element
union, and decision 7's cost rule are each named elsewhere and are not decided
here.

Filed with `sb-pxkf`, campaign-034 ruling `RQ-034-5`, split from `sb-jvz3` by
ruling `RQ-034-15`; it folds `sb-h6qt`'s half of the question. The code is
`sb-cjou`.

## Note (2026-09-06): the 2026-09-05 bracketed Note's two clauses about `collect`'s grammar are historical

A dated Note rather than an amendment: it decides nothing, edits nothing, and
records only that two clauses written on 2026-09-05 describe a state of affairs
the Amendment above has ended. The bracketed Note beneath decision 4 keeps
every word.

That Note explains the rename from `assign_to` to `collect` and says of it:
"`collect` says what the block does with the answers rather than borrowing a
name whose grammar it now only partly shares, and it keeps the same finding
text so an author meets one complaint and not two."

**"only partly shares" is historical, and now shares fully.** It was written
when this field's rule was `identifier?/1` and `core.subchart`'s `assign_to`
was too, so the two grammars were the same rule under two names and the
partial sharing was about the field types rather than the validation. After
`ADR-0011` decision 13 and `sb-r313` the three `assign_to` fields read
`datamodel_path?/1` and this one did not, which made the sharing genuinely
partial for the first time. After the Amendment above all four read one
predicate, and the grammar is shared entirely.

**"keeps the same finding text" is historical in the same shape, and comes
back true.** It was true on 2026-09-05, went false on 2026-09-06 when three of
the four fields widened and this one's message stayed behind, and is true again
once this field's message names a datamodel path as theirs do. The clause's
reason - an author meets one complaint and not two - is why the text moves with
the rule rather than staying put.

Filed with `sb-pxkf`, campaign-034 ruling `RQ-034-5`.

## Note (2026-09-06): the deferred-question half of this record's Note on `ADR-0011` decision 13 is answered

A dated Note rather than an amendment, on one sentence of the Note of this date
that decided two of decision 4's four deferred fields. That Note keeps every
word; this one records that half of its last sentence has since been answered,
in this record, on the same day.

The sentence: "And `collect`'s bare-lowercase-identifier refusal is
deliberately **not** reached by `ADR-0011` decision 13, which resolves only
`core.subchart`'s `assign_to`; whether the two fields should agree is named
there as a deferred question rather than answered."

**Its first half stands unchanged.** `ADR-0011` decision 13 still resolves
`core.subchart`'s `assign_to` and still reaches nothing else, and that record's
decision to name the other three rather than sweep them up is still the right
reading of it.

**Its second half is historical.** The question of whether the two fields
should agree is no longer deferred: the Amendment above answers it, and the
answer is that they agree. It is answered here rather than in `ADR-0011`
because that is where the sentence said it belonged - `collect`'s grammar is
this record's decision to make - and it is answered in the direction decision
13 argued for, on this record's own reading of its decision 5.

Filed with `sb-pxkf`, campaign-034 ruling `RQ-034-5`.
