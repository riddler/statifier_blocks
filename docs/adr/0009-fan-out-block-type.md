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
