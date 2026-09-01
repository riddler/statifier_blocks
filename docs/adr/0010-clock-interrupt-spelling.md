# ADR-0010: A clock interrupt is a delayed `core.send` at the head of a group's body caught by a `core.on_event` on its rail, and there is no `core.timeout`

Status: proposed (2026-09-01, campaign-026, bead `sb-j2o`)

## Context

The editor spike carries a proposed core type that does not exist in the
package: `core.timeout`, "an interrupt rule that fires once a duration has
elapsed", declared with an `after` duration, an `outcome` of `abandon` or
`resume`, an optional `cond`, and `kinds: ["interrupt_handler"]` and nothing
else (`spike/js/proposed-core.js:736-866`). Its own header states the case for
it in one sentence: "`core.on_event` catches an event; nothing caught the
clock" (`spike/README.md:845-866`).

The proposal has a history. ADR-0002's 2026-08-28 amendment, section D3,
already refused the same shape once, when it was spelled as the demo host type
`myapp.timeout_rule`: the two demo types were "held back because the interrupt
rail covered their demo use cases: a guarded event handler and a timeout rule
are `core.on_event` and `core.wait` inside a group's `interrupts` slot, with
the guard as a condition, and promoting them would put two types into the core
vocabulary whose whole content is a spelling of an arrangement the vocabulary
already expresses" (`docs/adr/0002-block-type-behaviour.md:952-961`). Half of
D3 has since been overturned on its merits and recorded: the guard did not stay
a host concern, and `core.on_event` grew an optional `cond` of its own
(ADR-0002's 2026-08-31 note, `docs/adr/0002-block-type-behaviour.md:1954-2048`).
The clock half was never revisited, and `spike/js/proposed-core.js` reopened it
from the other side under bead `sb-0o4`, which is why this question is still
open and why D3 alone does not close it.

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

No row is added to ADR-0002 decision 10's vocabulary table. That table records
fifteen types (G11), `StatifierBlocks.Palette.core_types/0` registers the same
fifteen (`lib/statifier_blocks/palette.ex:87-104`), and this record leaves both
counts where they are.

The admission criterion is decision 10's own and D3 states it plainly: a type
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

### 2. The two spellings compile to the same SCXML

The spike descriptor's own compile sketch says what `core.timeout` would emit:
"a delayed send on entry to the group plus a transition on its arrival"
(`spike/js/proposed-core.js:780-787`). That is what the pair already emits,
element for element.

The send block's emission is a compound state whose `<onentry>` holds
`<send delay="15m" event="card.authz_timed_out" id="s_blk_..._send"/>` and whose
`initial` points straight at its `<final>`, because arming is instantaneous
(`lib/statifier_blocks/core/send.ex:215-231`). As the first child of the group's
`body`, that state is entered when the body region is entered, so the deadline
starts when the group starts. The handler's emission is a transition on the
group's state, guarded by the `cond` when one is set, taking the group to its
final for `abandon` or re-entering it for `resume`
(`lib/statifier_blocks/core/on_event.ex:33-66`).

A new type that emits the bytes an existing arrangement already emits buys the
author one card and buys the compiler a second code path to keep in agreement
with the first. Under ADR-0004 decision 2 - one block, one state - it would
also be a single block emitting a construct that spans two scopes, which is
the shape decision 4 keeps out of a block type's reach.

### 3. The timer's lifetime is already correct, and it is correct for free

This is the strongest evidence and it is the part a taste argument would miss.
`StatifierBlocks.Compiler.Cancels` emits `<cancel sendid="..."/>` in the
`<onexit>` of the **nearest enclosing scope state** of whichever block armed the
send, reading the send id back through `StateId.unstate_id/1`
(`lib/statifier_blocks/compiler/cancels.ex:1-63`). For an interruptible group
that scope is the body *region*: the record says so in as many words, and says
why - "abandoning the group takes an *internal* transition to the group's own
final, which exits the body region without exiting the group"
(`lib/statifier_blocks/compiler/cancels.ex:21-27`).

So the pair already has the lifetime a rail rule wants, with nothing authored
and nothing special-cased:

- the group completes normally: the body region is exited, the deadline send is
  cancelled, no stale timer fires;
- an unrelated interrupt on the rail abandons the group: the body region is
  exited, the deadline send is cancelled;
- the deadline itself fires: the handler's transition abandons or resumes the
  group per its `outcome`.

The `resume` case is the one the spike descriptor left open - "what the timer
does when a `resume` outcome re-enters the group it just left" is flagged there
as a Phase-B question (`spike/js/proposed-core.js:785-787`). The pair answers it
structurally rather than by ruling: a `resume` re-enters the body region, which
re-enters the head `core.send` state, which arms a fresh deadline; the previous
one was cancelled on the way out. Whether re-arming is the *desired* semantics
in a given chart is the author's call, and under `core.resumable_group`'s
history mode it is a question the author can already see the answer to. A
first-class `core.timeout` would have had to decide this in the record, for
everyone, before anyone had asked.

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
  already overturned by the 2026-08-31 `cond` note; this record does not
  disturb that.
- An author still has to place the send first. The convention is written down
  here and nothing enforces it until the advisory in decision 6 exists, which
  is the one place this decision is worse for an author than a first-class type
  would have been.

## Deferred questions, named rather than guessed

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
