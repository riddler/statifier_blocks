# ADR-0010: A clock interrupt is a delayed `core.send` at the head of a group's body caught by a `core.on_event` on its rail, and there is no `core.timeout`

Status: accepted (2026-09-02, campaign-026; direction-agent verdict on the
second review, after one cure, with the `RQ-026-6` ruling recorded in the
note below)

## Context

The editor spike carries a proposed core type that does not exist in the
package: `core.timeout`, "an interrupt rule that fires once a duration has
elapsed", declared with an `after` duration, an `outcome` of `abandon` or
`resume`, an optional `cond`, and `kinds: ["interrupt_handler"]` and nothing
else (`spike/js/proposed-core.js:736-896`). Its own header states the case for
it in one sentence: "`core.on_event` catches an event; nothing caught the
clock" (`spike/README.md:845-848`).

The proposal has a history. ADR-0002's 2026-08-28 amendment, section D3,
already refused the same shape once, when it was spelled as the demo host type
`myapp.timeout_rule`: the two demo types were "held back because the interrupt
rail covered their demo use cases: a guarded event handler and a timeout rule
are `core.on_event` and `core.wait` inside a group's `interrupts` slot, with
the guard as a condition, and promoting them would put two types into the core
vocabulary whose whole content is a spelling of an arrangement the vocabulary
already expresses" (`docs/adr/0002-block-type-behaviour.md:952-961`). Half of
D3 has since been made concrete rather than overturned: the 2026-08-31 note gave
`core.on_event` the optional `cond` D3's sentence had already assumed, and says
so about itself - "this note makes D3's sentence true rather than aspirational"
(`docs/adr/0002-block-type-behaviour.md:2009-2017`). D3's refusal of
`myapp.guarded_on_event` stands; what changed is that the arrangement it pointed
at now exists in the shipped types. The clock half was never revisited, and
`spike/js/proposed-core.js` reopened it from the other side under bead `sb-0o4`,
which is why this question is still open and why D3 alone does not close it.

Two things happened after D3 that change the evidence rather than repeat it.

**The vocabulary grew `core.send`.** ADR-0002's 2026-08-29 amendment (G2)
admitted a leaf that names an event and says *when* - `event`, plus an optional
`delay` duration - and the type's own record is explicit that a delayed send
"goes on the *external* queue, outlives the step that armed it, has to survive
a restart, and is turned into a durable timer by infrastructure outside the
interpreter" (`lib/statifier_blocks/core/send.ex:12-22`). D3's answer named
`core.wait`, which is the wrong half of the pair: a wait keeps the chart live
for its duration, so "interrupt this group after fifteen minutes, whatever it
is doing" genuinely was not what a wait said. A delayed send is a different
thing. It arms and completes in the same macrostep
(`lib/statifier_blocks/core/send.ex:24-30`), which is exactly what a deadline
wants.

**The first embedder ran the port.** `statifier_examples` ported the spike's
card-processing document onto the shipped vocabulary and spelled the
authorization deadline as the pair: a `core.send` with `"event":
"card.authz_timed_out", "delay": "15m"` at the head of the group's `body`
(`priv/fixtures/card_processing.json:99-108`), and a `core.on_event` on the same
group's `interrupts` rail listening for `card.authz_timed_out` with a `cond` and
`"outcome": "abandon"` (`priv/fixtures/card_processing.json:331-342`). That
fixture's own description records the port as a port
(`priv/fixtures/card_processing.json:7`). It cost one block - 46 to 47 - and no
change anywhere else. The 2026-08-31 operator note on `sb-j2o` records the
result: the two-block spelling shipped, is durable, and is what the demo
narrates, while the vocabulary question "still deserves its own sitting". This
record is that sitting.

**What this record has to answer**, and nothing wider: whether a first-class
clock interrupt joins the `core.*` vocabulary under ADR-0002 decision 10, or
the two-block arrangement is the intended spelling; what makes the arrangement
correct rather than merely available; and what happens to the spike descriptor
either way. It builds nothing: there are no `lib/` changes here.

## Decision

### 1. No `core.timeout`. The pair is the spelling

A clock interrupt on a `core.group` or a `core.resumable_group` is written as
**two blocks**:

- a `core.send` carrying the deadline event and a `delay`, placed as the
  **first block of the group's `body` slot**; and
- a `core.on_event` on that same group's `interrupts` slot, naming the same
  event, with the `outcome` and the optional `cond` the author wants.

Both group types carry the pair, but they do not behave identically once a
`resume` handler is involved: decision 3 works out the difference, and the
`core.resumable_group` case has an edge sharp enough that this record defers it
rather than blessing it.

No row is added to ADR-0002 decision 10's vocabulary table. That table records
fifteen types (G11), `StatifierBlocks.Palette.core_types/0` registers the same
fifteen (`lib/statifier_blocks/palette.ex:87-104`), and this record leaves both
counts where they are.

The admission criterion is D3's - decision 10 proper states none, and section
D's D3 is where the vocabulary's own test is written down: a type
whose whole content is a spelling of an arrangement the vocabulary already
expresses does not join the vocabulary. The test is not whether the author
would enjoy one card more than two; it is whether the type expresses something
the arrangement cannot. This one does not, and decision 2 through 4 shows why
below.

The contrast that makes the criterion legible is ADR-0009. Durable fan-out
became a new type, `core.map`, because *no* arrangement of the fifteen
expressed it - it needed one invocation whose handler starts N children, a
mechanism that exists nowhere in the vocabulary. A clock interrupt needs no
mechanism at all beyond the two types already shipped.

### 2. The two spellings compile to the same SCXML on the abandon path, and differ on resume

The spike descriptor's own compile sketch says what `core.timeout` would emit:
"a delayed send on entry to the group plus a transition on its arrival"
(`spike/js/proposed-core.js:782-784`). On the abandon path - a deadline that
fires, or a group that completes or is abandoned before it does - that is what
the pair already emits, element for element.

**The equivalence is narrower than "element for element" everywhere, and the
difference is worth stating rather than glossing.** The sketch arms its send on
the *group state's* `<onentry>`; the pair arms it in the `<onentry>` of the
body region's first step. Those two are the same until a `resume` handler
fires, and decision 3 works out what happens then - three behaviours, not one.
So this decision claims equivalence on the abandon path and claims nothing on
the resume path. That is enough for decision 1, because D3's criterion asks
whether the arrangement expresses the thing, not whether a hypothetical type
would have expressed it identically.

The send block's emission is a compound state whose `<onentry>` holds
`<send delay="15m" event="card.authz_timed_out" id="s_blk_..._send"/>` and whose
`initial` points straight at its `<final>`, because arming is instantaneous
(`lib/statifier_blocks/core/send.ex:215-231`). As the first child of the group's
`body`, that state is entered when the body region is entered, so the deadline
starts when the group starts. The handler's emission is a **watcher state**
whose transition fires on the author's event, guarded by the `cond` when one is
set, and whose executable content raises an interrupt-protocol event -
`statifier_blocks.interrupt.abandon` or `...resume`, per the handler's `outcome`
(`lib/statifier_blocks/core/on_event.ex:286-300`, `:324-326`;
`lib/statifier_blocks/core/emit.ex:68-69`). The **group's own state** is what
carries the transitions on those protocol events: to its `<final>` for
`abandon`, and to `history_id || run` for `resume`
(`lib/statifier_blocks/core/emit.ex:256-259`). The handler names what should
happen; the group is where it happens. That split is why decision 3's three
resume behaviours belong to the group type rather than to the handler.

A new type that emits the bytes an existing arrangement already emits buys the
author one card and buys the compiler a second code path to keep in agreement
with the first. Under ADR-0004 decision 2 - one block, one state - it would
also be a single block emitting a construct that spans two scopes, which is
the shape decision 4 keeps out of a block type's reach.

### 3. The timer's lifetime on the abandon path is correct for free; on resume it is per-type and one case is sharp

The abandon path is the strongest evidence and it is the part a taste argument
would miss. `StatifierBlocks.Compiler.Cancels` emits `<cancel sendid="..."/>` in the
`<onexit>` of the **nearest enclosing scope state** of whichever block armed the
send, reading the send id back through `StateId.unstate_id/1`
(`lib/statifier_blocks/compiler/cancels.ex:1-63`). For an interruptible group
that scope is the body *region*: the record says so in as many words, and says
why - "abandoning the group takes an *internal* transition to the group's own
final, which exits the body region without exiting the group"
(`lib/statifier_blocks/compiler/cancels.ex:21-27`).

So on every path that leaves the body, the pair already has the lifetime a rail
rule wants, with nothing authored and nothing special-cased:

- the group completes normally: the body region is exited, the deadline send is
  cancelled, no stale timer fires;
- an unrelated interrupt on the rail abandons the group: the body region is
  exited, the deadline send is cancelled;
- the deadline itself fires: the handler's transition abandons or resumes the
  group per its `outcome`.

**The `resume` path is where the free answer runs out.** The spike descriptor
flags "what the timer does when a `resume` outcome re-enters the group it just
left" as a Phase-B question (`spike/js/proposed-core.js:785-787`), and the pair
does not answer it with one behaviour. It has two, decided by which group type
the rail sits on, and the sketch's own type would have had a third. An earlier
draft of this record claimed the pair "answers it structurally"; it does not,
and the three behaviours are these.

`Emit.guarded/4` wires a resume handler as an **internal** transition on the
group's own state, targeting `history_id || run` - the `<parallel>` holding the
body and rail regions when there is no history, the `<history>` inside the body
region when there is
(`lib/statifier_blocks/core/emit.ex:256-259`, `:244`, `:274-279`). The target is
a descendant of the group state in both cases, so the transition's domain is the
group state: the **body region is exited and re-entered**, and the group state
itself never is.

1. **`core.group` (no history): the clock restarts.** The body region is exited,
   so `Cancels` fires and the armed deadline is cancelled; re-entry is at the
   region's `initial`, which is the head `core.send` state, so a fresh deadline
   is armed. Each resume gives the group another full `delay`.
2. **`core.resumable_group`: the clock is gone.** The body region is exited, so
   the deadline is cancelled exactly as above - but the history restores the
   step that was interrupted rather than the region's initial
   (`lib/statifier_blocks/core/resumable_group.ex:95-99`: "the body re-enters
   where it left off instead of restarting"), and the head `core.send` state is
   not among the states history recorded. Nothing re-arms it. **After the first
   resume, a resumable group with a deadline pair has no deadline at all.** That
   is the sharp edge in this decision, and it is stated rather than discovered.
3. **The sketch's `core.timeout`: the clock keeps running.** Armed on the group
   state's `<onentry>` and cancelled from the group state's `<onexit>`, and an
   internal resume exits neither, so the original deadline survives the resume
   untouched and fires at its original moment. (That is also the exact bug
   `Cancels` records having fixed for the group case - "a cancel on the group's
   `<onexit>` never fired for it", `lib/statifier_blocks/compiler/cancels.ex:21-27`.)

**What this record decides about the three.** Behaviour 1 is recorded as the
intended semantics of a deadline pair: a resume that re-runs the body from the
top gets a fresh deadline, which is the reading an author of a restarting group
would expect. Behaviour 2 is **not** blessed here - "the deadline is gone after
a resume" is a semantics an operator should rule on rather than a record should
adopt by describing it, so it goes to the deferred list below, with this
paragraph as the statement of what the code does today. Behaviour 3 is nobody's
until a `core.timeout` exists, and decision 1 means it will not.

None of this disturbs the refusal. If anything it sharpens the criterion: a
first-class `core.timeout` would have had to decide all three of these in a
record, for everyone, before anyone had asked - and its sketch silently picks
the one the compiler already treats as a defect.

### 4. Durability is upstream's and is unaffected either way

The delayed send leaves the interpreter as `Statifier.Effect.SendDelayed` and
is turned into a durable timer by a host effect interpreter -
`statifier-ex docs/durable-timers.md`, `st-ADR-0054` and `st-ADR-0059` for the
per-execution ordinal, with `statifier_oban` the shipped one. This package
mints no timers and knows of none
(`lib/statifier_blocks/core/wait.ex:22-23` says the same for `core.wait`).

Nothing in this decision asks upstream for anything: no new effect, no new
event kind, no change to the invoke or timer contracts. That is checked
deliberately, because a vocabulary decision that turned out to need a
statifier-ex or statifier_oban contract change would not have been this
repository's to make (the umbrella's contract-ownership rule, `CLAUDE.md`).
It does not, so it is.

### 5. The two blocks are coupled by an event name, which is the family rule

Nothing in the document ties the send to the handler; they name the same
string. That is not an oversight of this decision, it is D2's rule applied
again: "the send-to-catch relationship is deliberately not an edge in the
document but two blocks naming the same string, with the enclosing group's rail
as where the catch lives", protecting the invariant that a port pointing at the
handler it wakes "would have been the first hand-drawn edge in a document, and
a cross-subtree one at that" (`docs/adr/0002-block-type-behaviour.md:938-946`;
umbrella D13; ADR-0001's tree invariant).

`core.raise` and `core.on_event` are already coupled exactly this way and have
been since the vocabulary had a rail. A deadline is the same relationship with
a delay attribute on one end. Making the clock case a single block while the
event case stays a pair would leave the vocabulary saying that one of its two
send-to-catch relationships deserves an edge and the other does not.

### 6. What the pair costs, stated rather than dodged

Three real costs, none of them an expressiveness gap:

1. **The rule is split across two panes.** The deadline reads as a step in the
   body and a handler on the rail, and an author scanning the rail alone sees
   the catch without the arm.
2. **"First in the body" is a convention, not a check.** A `core.send` placed
   third in the body arms its deadline only once the first two steps are done,
   which is a different chart from the one the author probably meant. Nothing
   refuses it, and nothing should at the type level - `validate_config/1` is
   handed a config, not a document (ADR-0002 decision 7).
3. **A typo in either event name is silent.** The send arms an event nothing
   catches, or the handler waits for an event nothing sends.

All three are **document-level advisory findings**, which is a layer that
exists and is not the vocabulary. They belong with the declaration-advisory
work rather than here, and this record files them as such rather than
answering them: a "deadline pair" advisory that recognises a delayed
`core.send` whose event a `core.on_event` on an enclosing group's rail names,
and warns when the names do not match, when the send is not the head of the
body, or when either half stands alone. Nothing in decision 1 blocks that
work, and none of it requires a type.

### 7. The spike descriptor is annotated, not deleted

`spike/js/proposed-core.js` is a proposals file inside a directory whose README
opens "Status: exploratory. This is a laboratory, not the product" and states
"Where this directory and an accepted ADR disagree, the ADR is the contract and
the spike is an experiment that has not been written up yet"
(`spike/README.md:1-26`). The descriptor's own header asks the question this
record answers: "Whether any of this earns an ADR-0002/0004 amendment is a
Phase-B finding" (`spike/js/proposed-core.js:57-58`). So the file is one this
record may write into.

It is annotated rather than removed. The descriptor is now the evidence for a
*refused* proposal, which is worth more kept than deleted, and two live things
read it: `spike/dev/selftest.html` runs suites over it, and
`spike/fixtures/documents/card-processing.json` still authors its 15-minute
deadline on it. Deleting the descriptor would mean rewriting a fixture document
and its replay fixtures to say something the spike has no shipped type for,
which is a change of a different size from a record and would make the spike a
worse laboratory, not a better one. The annotation is a dated pointer to this
record at the descriptor and at the matching `spike/README.md` section, saying
that the proposal was answered and how.

If a later campaign tidies the spike onto the shipped vocabulary wholesale -
the file header already contemplates a tidy - removing the descriptor then is
consistent with this record and needs no amendment to it.

## Consequences

- The core vocabulary stays at fifteen types. ADR-0002 decision 10's table and
  `StatifierBlocks.Palette.core_types/0` are both untouched, and they go on
  agreeing.
- No `lib/` change, no compiler change, no palette entry, no migration, and no
  document in existence compiles to different bytes than it did before this
  record.
- The idiom now has a name and a home. "Deadline pair" is citable, and a bead
  that wants the editor to help with it - a palette recipe that inserts both
  blocks at once, a card that reads them as one rule, an advisory - can cite
  decision 6 rather than reopening decision 1.
- `sb-0o4`'s proposal is answered on its face. The spike descriptor stays as
  the record of what was proposed and why it was not taken.
- D3's clock half is now decided on current evidence rather than standing on a
  2026-08-28 argument whose named alternative (`core.wait`) has since been
  superseded by a better one (`core.send` with a `delay`). D3's event half was
  already made true rather than aspirational by the 2026-08-31 `cond` note, and
  D3's refusal of `myapp.guarded_on_event` stands; this record does not disturb
  either.
- **A resumable group with a deadline pair loses its deadline on the first
  resume**, per decision 3's behaviour 2. That is a real behavioural fact this
  record surfaces rather than creates, it is deferred rather than blessed, and
  a reader who takes decision 1 as "the pair covers every group" without
  reading decision 3 will get it wrong.
- An author still has to place the send first. The convention is written down
  here and nothing enforces it until the advisory in decision 6 exists, which
  is the one place this decision is worse for an author than a first-class type
  would have been.

## Deferred questions, named rather than guessed

- **What a deadline should mean on a `core.resumable_group` after a resume.**
  Decision 3's behaviour 2: the code cancels the armed send when the body region
  is exited and history re-enters the interrupted step rather than the head
  `core.send`, so the group runs on with no deadline. Three answers are
  available - accept it as intended, have the author arm the deadline outside
  the group so the resume never touches it, or make it an advisory finding when
  a deadline pair and a `resume` handler share a resumable group. This record
  states what happens and does not pick. **No shipped document exercises the
  case**: the examples host's `blk_cp_authz` is a plain `core.group` whose rail
  carries only `abandon` handlers
  (`priv/fixtures/card_processing.json:331-342`), so nothing would have caught
  this at runtime either.
- **The deadline-pair advisory** (decision 6): its findings, their severity,
  and whether "the send is not the head of the body" is a warning or silence.
  ADR-0005's findings layer and the declaration-advisory work own it.
- **A two-block palette insertion.** Whether the editor offers "deadline" as
  one palette action that inserts both blocks is an ADR-0005 question, not a
  vocabulary one. It is the cheapest available answer to cost 1 and it is not
  decided here.
- **One spelling of "duration" across a step and a rule.** The spike flagged
  `after` versus `duration` as a naming question
  (`spike/js/proposed-core.js:763-768`). This decision makes it moot for the
  clock interrupt - the pair uses `core.send`'s `delay` - and it stays open for
  any future type that names a duration.
- **What a clock interrupt means on a rail whose group is a `core.foreach`
  body or a `core.parallel` lane.** The Cancels record already fixes the
  lifetime for a lane child
  (`lib/statifier_blocks/compiler/cancels.ex:27-35`); whether the resulting
  chart is what an author expects has not been walked and no document
  exercises it.
---

## Note (2026-09-02): `RQ-026-6` answers the resumable-group deadline, and it is an advisory

A dated note rather than an amendment: it does not change what this record
decides, it records the operator's answer to the one question the record
deliberately left open.

The deferred list's first entry asked what a deadline should mean on a
`core.resumable_group` after a resume - decision 3's behaviour 2, where the body
region's exit cancels the armed head `core.send` and the history re-entry
restores the interrupted step rather than the region's initial, so nothing
re-arms and the group runs on with no deadline. The record named three possible
answers and picked none.

**The ruling is option (c): an advisory finding, not a new arming convention.**
Where a document places a delayed `core.send` at the head of a
`core.resumable_group`'s `body` **and** that group's `interrupts` rail carries a
`core.on_event` whose `outcome` is `resume`, the ADR-0005 findings layer raises
an **advisory** - a warning, not a refusal - stating the consequence and the two
escapes available to the author: arm the deadline outside the group, or use a
plain `core.group`. The finding stays silent for a `core.group` and for a rail
with no resume handler.

What the ruling deliberately does *not* do is change the compiled bytes or the
authoring convention. Decision 1's "first block of the group's `body` slot"
stands unaltered for both group types, decision 3's behaviours 1 and 2 stay
exactly as described, and no block type gains a key. The sharp edge is surfaced
where an author will see it rather than designed away, which keeps the SCXML the
pair emits the SCXML the vocabulary already emitted.

`sb-dj1p` carries the work, filed 2026-09-02 as a campaign-027 candidate and
not scheduled here. Its acceptance criteria are that the finding fires on
exactly that shape and is sabotage-tested, that it stays silent for `core.group`
and for rails without a resume handler, and that this note names it - which it
now does.

**The deferred-list entry this answers is left in place rather than deleted**,
and this note supersedes it. A deferred question that vanishes from a record
reads as one that was never asked; the entry is the question, and this is the
answer to it.

---

## Note (2026-09-02): the deadline spelling's duration is `core.send`'s `delay`, and the cross-type spelling question stays deferred

The same shape as the `RQ-026-6` note above - a dated note, not an amendment.
It does not change what this record decides; it says which of the deferred
list's questions the record already answered in passing, and why the rest of
that entry stays open.

The deferred entry is "One spelling of 'duration' across a step and a rule",
which carried the spike's flag that `after` and `duration` were two names for
one field type (`spike/js/proposed-core.js:763-768`). Two of its three parts
are settled by what is already shipped and by decision 1, and nothing new is
decided here:

- **The shipped vocabulary spells a duration two ways, and the two mean
  different things.** `core.wait` takes `duration`
  (`lib/statifier_blocks/core/wait.ex:48`) - how long the step itself takes.
  `core.send` takes `delay` (`lib/statifier_blocks/core/send.ex:125`), "the
  vocabulary's first optional duration" (`lib/statifier_blocks/core/send.ex:77`)
  - when the event fires. That is the same step-versus-rule distinction the
  spike drew when it argued for `after`, answered by keys that already exist
  rather than by a third one.
- **The deadline spelling therefore names its duration `delay`.** Decision 1
  makes a clock interrupt a delayed `core.send` at the head of the group's
  `body`, so the deadline's duration is that send's `delay`, in either of the
  stored forms `core.send` already accepts. No block type gains a key, and
  `after` does not enter the vocabulary, because the type that would have
  carried it does not.

**What stays deferred is the third part**: whether a future type that names a
duration must reuse one of the two shipped spellings rather than coin its own.
The reason it stays deferred is that no such type is proposed. Picking a
spelling for a type nobody has asked for would be a decision, and this note is
a prose rider (`sb-xhw8`) whose scope stops short of moving one; the record
that proposes the type is where the question belongs.

No bead owns that remaining half. Filing one is outside this rider's scope, so
the deferred-list entry above is left in place and is the standing owner of the
question, the way the `RQ-026-6` note left its own entry standing.

---

## Note (2026-09-05): the deadline's `delay` is stored in one grammar, and "either of the stored forms" is scoped to its date

A dated Note, the same shape as the two above it. Nothing this record decides
moves: decision 1's pair stands, a clock interrupt is still a delayed
`core.send` at the head of the group's `body`, the deadline's duration is still
that send's `delay`, no block type gains a key, and no line above this one is
edited.

The sentence this Note scopes is in the 2026-09-02 note immediately above, in
its second bullet: the deadline's duration is that send's `delay`, "in either
of the stored forms `core.send` already accepts". That described the shipped
vocabulary on the day it was written. It no longer describes what a
`:duration` field accepts, and the reason is a decision taken in another
record rather than anything this one changed.

### What moved, and where it was decided

ADR-0005's amendment of 2026-09-05 to its decision 9 - clauses 9a through 9e,
merged at **proposed**, under bead `sb-8acm` - reverses the clause that kept an
older, calendar-style duration spelling accepted beside the expression
language's. It reverses it on a fact rather than a preference: the operative
argument for keeping that spelling was that documents already written hold it,
and the sweep found no author-written document that does. Clause 9a is the
operative one here - a `:duration` field reads one grammar, the expression
language's, and a value that grammar does not parse is a format finding.
Clause 9c is why there is no second stored form left to name: the intermediate
canonical spelling the 2026-08-29 arrangement compiled through has no reader
any more, so the stored string is parsed and rendered straight to the
attribute the engine reads.

ADR-0002 carries the reach into the `core.send` row. Its dated Note of
2026-09-05 supersedes **G2a**'s middle clause by reference, so a present
`delay` is accepted in one spelling and a value in any other is refused like
any other unparseable string. Decision 7's closed field-type set is untouched
by that, and `delay` is still an optional `:duration` field holding a string.

**The code has landed.** `sb-4r1p` implemented the pivot and 0.17.0 shipped
it: a `:duration` field is validated against that one grammar and every other
spelling is a format finding, and the module both `:duration` fields go
through - `lib/statifier_blocks/core/duration.ex` - says as much in its own
moduledoc. So the earlier sentence is not waiting on an acceptance to go
stale; it is stale as of that release, which is why this Note is dated rather
than conditional.

### How to read the sentence

Read "in either of the stored forms `core.send` already accepts" as a
statement about 2026-09-02, and read the rule from this date as: the
deadline's `delay` is stored in the one form `core.send` accepts, a duration
string in the expression language's grammar. Everything else in that bullet
stands exactly as written - `core.wait`'s `duration` and `core.send`'s `delay`
are still two keys drawing the step-versus-rule distinction, the deadline's
duration is still the head send's `delay`, no block type gains a key, and
`after` does not enter the vocabulary. The bullet's bytes are not edited: a
record's history is not edited, and this section supersedes from below, the
way ADR-0005's clause 9 says its own earlier prose is superseded.

### What this Note does not do

- It does not touch **decision 1**, or any other decision in this record.
  Which grammar a stored duration is written in was never something this
  record decided. It decided that the deadline *is* a `delay`, and it still
  is.
- It does not reopen **the third part of the deferred entry** the 2026-09-02
  note left standing - whether a future type that names a duration must reuse
  one of the two shipped spellings rather than coin its own. That question is
  about which *key* a new type names, not which grammar a value is written in,
  and no such type is proposed. The deferred-list entry above stays its
  standing owner, exactly as that note left it.
- It does not reach the **`RQ-026-6` note** above it. That note answers what a
  deadline means on a `core.resumable_group` after a resume, and it says
  nothing about how a duration is spelled; `sb-dj1p` still owns its advisory.
- It does not restate the grammar. Which strings parse, how a fraction
  expands, how a repeated unit accumulates and what the calendar-approximating
  units mean are `Predicator.Duration`'s to define, exactly as ADR-0005 clause
  9e leaves them.

Filed with `sb-pctm`, campaign-030's fill lane D.
