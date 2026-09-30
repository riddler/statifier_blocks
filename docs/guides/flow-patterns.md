# Flow patterns

This guide shows you how to build shapes a workflow commonly needs out of the
core block types. Each pattern is a section of its own: the shape, a complete
document you can copy, what Describe and the Map show for it, what a host sees
when it runs, and where a simpler block does the same job.

Every document on this page is a fixture under
[`test/fixtures/documents/flow_patterns/`](../../test/fixtures/documents/flow_patterns/),
quoted here byte for byte, and
[`test/statifier_blocks/flow_patterns_guide_test.exs`](../../test/statifier_blocks/flow_patterns_guide_test.exs)
compiles and runs each one on the current release under the core palette
(`StatifierBlocks.Palette.core/0`).

## Patterns

- [A step that must finish within a bound, or the flow continues](#a-step-that-must-finish-within-a-bound-or-the-flow-continues)
- [A branch whose outcome may be both arms](#a-branch-whose-outcome-may-be-both-arms)
- [Park until an interrupt fires or the deadline expires](#park-until-an-interrupt-fires-or-the-deadline-expires)

## A step that must finish within a bound, or the flow continues

Use this when one step may take too long and the flow should move on without
it rather than stop: the step is bounded, and at the bound the flow fails open.

The example is a library hold. A patron's hold is placed, the desk has one day
to confirm it, and the loan is checked out whether or not the confirmation
arrived.

### The shape

Put the step in a `core.group`, and put the core `"deadline"` recipe on that
group. The recipe is two ordinary core blocks
(`StatifierBlocks.Core.DeadlineRecipe`):

- a `core.send` carrying the deadline event and a `delay`, at index 0 of the
  group's `body`, so the timer starts when the group starts; and
- a `core.on_event` naming the same event on the same group's `interrupts`
  rail.

Set the handler's `outcome` to `abandon`. An abandon leaves the group for
good, and the group then finishes as `done`, exactly as it does when its body
completes (`StatifierBlocks.Core.Emit.interruptible/2`). The step after the
group runs either way, which is what makes the bound fail open. The other
outcome, `resume`, re-enters the group instead of leaving it
(`StatifierBlocks.Core.OnEvent`, "The `outcome` values"), so it does not
continue the flow.

### Put the pair down in the editor

1. Select a position inside the group's `body`.
2. Pick **Deadline** from the palette's **Structure** group.
3. Set the send's `delay` to the bound, here `1d`.

`StatifierBlocks.Core.DeadlineRecipe.insert/2` writes both halves in one
gesture: the send at the head of the group's `body` with a default `delay` of
`1h` (`default_delay/0`), and the handler at the end of the `interrupts` rail
with the `abandon` outcome its schema defaults to. It names the event itself,
`deadline.` followed by the last eight characters of the send's block id, and
writes the same name into both halves.

The recipe only works inside a block with an `interrupts` rail, which in the
core vocabulary is `core.group` and `core.resumable_group`. Armed anywhere
else, `insert/2` answers `{:error, {:no_interrupts_slot, id}}` and writes
nothing. A pair you build by hand is recognised the same way: `members/2`
claims any `core.send` with an `event` and a `delay` in a group's `body` whose
event a `core.on_event` on that group's rail also names, so the editor can
take both halves out in the one gesture they went in as.

### The document

The step is a `core.await` for `hold.confirmed`. The deadline event is named
by hand here, `deadline.hold_confirm`, so the example reads well; the recipe's
generated name works the same way.

```json
{
  "schema_version": 1,
  "id": "bdoc_01JHOLDCONFIRM",
  "revision": 1,
  "metadata": {"name": "Hold confirmation, bounded"},
  "accepts": ["hold.confirmed"],
  "root": {
    "id": "blk_ROOT", "type": "core.sequence", "type_version": 1,
    "slots": {"body": [
      {"id": "blk_PLACE", "type": "core.send", "type_version": 2,
       "config": {"event": "hold.placed"}},
      {"id": "blk_CONFIRM", "type": "core.group", "type_version": 1,
       "slots": {
         "body": [
           {"id": "blk_TIMER", "type": "core.send", "type_version": 2,
            "config": {"event": "deadline.hold_confirm", "delay": "1d"}},
           {"id": "blk_WAIT", "type": "core.await", "type_version": 1,
            "config": {"event": "hold.confirmed"}}
         ],
         "interrupts": [
           {"id": "blk_EXPIRE", "type": "core.on_event", "type_version": 1,
            "config": {"event": "deadline.hold_confirm", "outcome": "abandon"}}
         ]
       }},
      {"id": "blk_LEND", "type": "core.send", "type_version": 2,
       "config": {"event": "loan.checked_out"}}
    ]}
  }
}
```

It compiles under the core palette with no finding. These are the lines of
the compiled chart that carry the pattern. The group arms the deadline when
its body starts:

```xml
<send delay="1d" event="deadline.hold_confirm" id="s_blk_TIMER__send"/>
```

The handler raises the group's abandon event when the deadline arrives:

```xml
<transition event="deadline.hold_confirm" target="s_blk_EXPIRE__o_done"><raise event="statifier_blocks.interrupt.abandon.s_blk_CONFIRM"/></transition>
```

The group takes the abandon to its own `done`, and the root sequence moves on
when the group is done:

```xml
<transition event="statifier_blocks.interrupt.abandon.s_blk_CONFIRM" target="s_blk_CONFIRM__o_done" type="internal"/>
<transition event="done.state.s_blk_CONFIRM" target="s_blk_LEND" type="internal"/>
```

The body cancels the timer when it is left, however it is left
(`StatifierBlocks.Compiler.Cancels`):

```xml
<onexit><cancel sendid="s_blk_TIMER__send"/></onexit>
```

### What Describe and the Map show

The Describe outline (`StatifierBlocks.Describe.render/2`) reads the two
halves as:

```text
In 1 day, send deadline.hold_confirm
When deadline.hold_confirm, abandon
```

and the flow around them as:

```text
After Run interruptible steps (done), Send loan.checked_out
On deadline.hold_confirm, When deadline.hold_confirm, abandon abandons the group
In 1 day, deadline.hold_confirm reaches When deadline.hold_confirm, abandon
```

The Map (`StatifierBlocks.Map.graph/2`) draws the handler's interrupt edge
leaving the group (`"to" => "exit"` in `StatifierBlocks.Map.interrupts/1`)
and a timer edge from the send to the handler carrying the event and the
`1d` delay (`StatifierBlocks.Map.timers/1`).

### What a host sees at the bound

When the group starts, the chart asks the host for a delayed send of
`deadline.hold_confirm` a day out, and parks in the await. Then one of two
things happens, and the host sees the same result from both:

- **The confirmation arrives in time.** The await finishes, the group
  finishes as `done`, the timer is cancelled, and the chart sends
  `loan.checked_out`.
- **The day passes.** The deadline event arrives, the handler abandons the
  group, the group finishes as `done`, and the chart sends
  `loan.checked_out`.

Neither path raises, refuses or reports a finding: the bound is an ordinary
way for the group to finish. A `core.group` declares no outcomes of its own,
so the step after it cannot tell the two paths apart. When the flow needs to
know which one happened, use the `core.await` below, which declares both.

### When `core.await`'s own timeout is the shorter answer

When the bounded step is itself a wait for one event, as it is here, you do
not need the group. `core.await` takes an optional `timeout`, and ends at one
of two declared outcomes, `received` or `timed_out`
(`StatifierBlocks.Core.Await.outcomes/1`). Put this block where the group
was:

```json
{"id": "blk_WAIT", "type": "core.await", "type_version": 1,
 "config": {"event": "hold.confirmed", "timeout": "1d"}}
```

The step after it runs on either outcome, so the flow fails open the same way:

```text
After Wait for hold.confirmed, giving up after 1d (received, timed_out), Send loan.checked_out
```

The await's timer is cancelled by the enclosing scope when the await is left,
so it leaves nothing behind either (`StatifierBlocks.Core.Await`, "The
deadline's timer cannot outlive the await").

Reach for the group and the deadline recipe instead when the bounded step is
more than one wait: several steps in a row, a step that does work rather than
waits, or a body that other interrupt rules also guard.

## A branch whose outcome may be both arms

Use this when a flow has two or more optional steps and any of them, all of
them or none of them may apply: do this, and also that, each when it is
asked for.

The example is a parcel delivery notice. Before the parcel goes out for
delivery, the recipient is told by message, by a posted card, by both or by
neither, as they asked. The card lane waits until the card is posted; the
message lane does not wait for it.

### The shape

Put a `core.parallel` where the choice would go, with one lane per optional
step, and leave its `complete` at `"all"`, the default. Inside each lane put
a `core.branch` with one arm: the arm's condition is that lane's guard, the
arm holds the step, and `otherwise` stays empty.

Each lane then decides for itself. A lane whose guard holds runs its step. A
lane whose guard does not hold takes the empty `otherwise`, which finishes
the branch at once (`StatifierBlocks.Core.Branch.emit/2`), so the lane is
done without doing anything. With `complete` at `"all"` the parallel is done
when every lane is done (`StatifierBlocks.Core.Parallel`, "`complete`: when
the block is done"), and the step after it runs then.

### The document

```json
{
  "schema_version": 1,
  "id": "bdoc_01JPARCELNOTICE",
  "revision": 1,
  "metadata": {"name": "Delivery notice, by message and by card"},
  "accepts": ["notice.card_posted"],
  "datamodel": [
    {"id": "wants_message", "description": "The recipient asked for a message."},
    {"id": "wants_card", "description": "The recipient asked for a posted card."}
  ],
  "root": {
    "id": "blk_ROOT", "type": "core.sequence", "type_version": 1,
    "slots": {"body": [
      {"id": "blk_NOTICE", "type": "core.parallel", "type_version": 1,
       "config": {"lanes": ["message", "card"], "complete": "all"},
       "slots": {
         "lane_message": [
           {"id": "blk_IF_MESSAGE", "type": "core.branch", "type_version": 1,
            "config": {"arms": [{"slot": "arm_asked", "cond": "wants_message"}]},
            "slots": {"arm_asked": [
              {"id": "blk_MESSAGE", "type": "core.send", "type_version": 2,
               "config": {"event": "notice.message_sent"}}
            ]}}
         ],
         "lane_card": [
           {"id": "blk_IF_CARD", "type": "core.branch", "type_version": 1,
            "config": {"arms": [{"slot": "arm_asked", "cond": "wants_card"}]},
            "slots": {"arm_asked": [
              {"id": "blk_CARD", "type": "core.send", "type_version": 2,
               "config": {"event": "notice.card_requested"}},
              {"id": "blk_POSTED", "type": "core.await", "type_version": 1,
               "config": {"event": "notice.card_posted"}}
            ]}}
         ]
       }},
      {"id": "blk_DELIVER", "type": "core.send", "type_version": 2,
       "config": {"event": "parcel.out_for_delivery"}}
    ]}
  }
}
```

The two conditions read the recipient's answers, `wants_message` and
`wants_card`, which the document declares in its `datamodel` and a host
supplies when the execution starts. It compiles under the core palette with
no finding. These are the lines of the compiled chart that carry the
pattern. Each lane's branch tests its guard, and when the guard does not hold
goes straight to its own `done`:

```xml
<transition cond="wants_message" target="s_blk_MESSAGE"/><transition target="s_blk_IF_MESSAGE__o_done"/>
```

A lane is done when its branch is:

```xml
<transition event="done.state.s_blk_IF_CARD" target="s_blk_NOTICE__done_lane_card" type="internal"/>
```

The parallel is done when every lane is, and the root sequence moves on when
the parallel is done:

```xml
<transition event="done.state.s_blk_NOTICE__run" target="s_blk_NOTICE__o_done" type="internal"/>
<transition event="done.state.s_blk_NOTICE" target="s_blk_DELIVER" type="internal"/>
```

### What Describe and the Map show

The Describe outline (`StatifierBlocks.Describe.render/2`) reads the parallel
and each lane's branch as:

```text
Run 2 lanes at the same time (all of)
Decide: When "asked", otherwise (one of)
```

and the flow around them as:

```text
After Run 2 lanes at the same time (done), Send parcel.out_for_delivery
The branch: when wants_message, Send notice.message_sent
The branch: when wants_card, Send notice.card_requested
The branch: otherwise, the end of the branch
```

The Map (`StatifierBlocks.Map.graph/2`) draws the parallel as one block
holding a slot per lane, titled `message` and `card`, and inside each lane
the branch with its `When "asked"` arm, its empty `Otherwise` and its empty
`Cannot be decided`.

### What a host sees

The host starts the execution with the recipient's two answers in the
datamodel. What it sees next depends on them:

- **Both asked.** The chart sends `notice.message_sent` and
  `notice.card_requested` and waits for `notice.card_posted`. When the card
  is posted it sends `parcel.out_for_delivery`.
- **Only the message.** The chart sends `notice.message_sent` and then
  `parcel.out_for_delivery`, with nothing to wait for.
- **Only the card.** The chart sends `notice.card_requested`, waits for
  `notice.card_posted`, and then sends `parcel.out_for_delivery`.
- **Neither.** The chart sends `parcel.out_for_delivery` and nothing else.

### How this differs from one branch

A `core.branch` takes one arm. Its arms are tried in order and the first
whose condition holds is the one that runs, as the palette entry says: "Takes
the first arm whose condition holds, or otherwise."
(`StatifierBlocks.Core.Branch.palette_entry/0`). So a branch with
a message arm and a card arm sends only the message to a recipient who asked
for both. Put this block where the parallel was to see it:

```json
{"id": "blk_NOTICE", "type": "core.branch", "type_version": 1,
 "config": {"arms": [{"slot": "arm_message", "cond": "wants_message"},
                     {"slot": "arm_card", "cond": "wants_card"}]},
 "slots": {"arm_message": [{"id": "blk_MESSAGE", "type": "core.send", "type_version": 2,
                            "config": {"event": "notice.message_sent"}}],
           "arm_card": [{"id": "blk_CARD", "type": "core.send", "type_version": 2,
                         "config": {"event": "notice.card_requested"}}]}}
```

With both answers `true` the chart sends `notice.message_sent` and then
`parcel.out_for_delivery`, and no card is requested.

A branch with one arm is the right block for a single optional step: it is
exactly one lane of this pattern on its own. Two one-arm branches in a row
also take both steps, but the second starts only when the first is done. Put
the card's branch first and a recipient who asked for both hears nothing by
message until the card is posted; the parallel starts both lanes together, so
the message goes out at once. When no optional step waits for anything, the
branches in a row and the parallel send the same events, and either shape
does the job.

## Park until an interrupt fires or the deadline expires

Use this when the flow should sit still until something happens to it or a
length of time runs out, whichever comes first, and there is no one event
it is waiting for: several things may end the wait, and when none of them
does, the deadline does.

The example is a library hold shelf. A patron's hold is ready, and the item
sits on the hold shelf for seven days. The patron may collect it, may cancel
the hold, or may ask for more time; if seven days pass with none of those,
the shelf is cleared anyway.

### The shape

Put a `core.group` where the flow should park. Its `body` is one
`core.wait` whose `duration` is the deadline, and its `interrupts` rail
carries a `core.on_event` for each event that may really arrive.

The wait is the deadline. It sends its own delayed event when it starts
and finishes when that event arrives (`StatifierBlocks.Core.Wait.emit/2`),
so the body completes when the time runs out and the group finishes as
`done`. Each handler names one of the real events. A handler whose
`outcome` is `abandon` leaves the group for good, and the group finishes
as `done` then too (`StatifierBlocks.Core.Emit.interruptible/2`). A
handler whose `outcome` is `resume` starts the group again from its first
step (`StatifierBlocks.Core.Group.emit/2`), which is the wait, so the
deadline starts over at its full length.

Nothing in the document names an event nobody sends. `core.await` would
need one: its `event` is required (`StatifierBlocks.Core.Await`), and a
flow with no single event to wait for would have to invent one only for
the await to hold on.

### The document

```json
{
  "schema_version": 1,
  "id": "bdoc_01JHOLDSHELF",
  "revision": 1,
  "metadata": {"name": "Hold shelf, until collected or cancelled"},
  "accepts": ["hold.collected", "hold.cancelled", "hold.extended"],
  "root": {
    "id": "blk_ROOT", "type": "core.sequence", "type_version": 1,
    "slots": {"body": [
      {"id": "blk_READY", "type": "core.send", "type_version": 2,
       "config": {"event": "hold.ready"}},
      {"id": "blk_SHELF", "type": "core.group", "type_version": 1,
       "slots": {
         "body": [
           {"id": "blk_SHELVED", "type": "core.wait", "type_version": 2,
            "config": {"duration": "7d"}}
         ],
         "interrupts": [
           {"id": "blk_COLLECTED", "type": "core.on_event", "type_version": 1,
            "config": {"event": "hold.collected", "outcome": "abandon"}},
           {"id": "blk_CANCELLED", "type": "core.on_event", "type_version": 1,
            "config": {"event": "hold.cancelled", "outcome": "abandon"}},
           {"id": "blk_EXTENDED", "type": "core.on_event", "type_version": 1,
            "config": {"event": "hold.extended", "outcome": "resume"}}
         ]
       }},
      {"id": "blk_CLEAR", "type": "core.send", "type_version": 2,
       "config": {"event": "hold.shelf_cleared"}}
    ]}
  }
}
```

It compiles under the core palette with no finding. These are the lines of
the compiled chart that carry the pattern. The wait arms the deadline when
the group starts:

```xml
<send delay="7d" event="statifier_blocks.wait.blk_SHELVED" id="s_blk_SHELVED__send"/>
```

A collection raises the group's abandon event, and a request for more time
raises its resume event:

```xml
<transition event="hold.collected" target="s_blk_COLLECTED__o_done"><raise event="statifier_blocks.interrupt.abandon.s_blk_SHELF"/></transition>
<transition event="hold.extended" target="s_blk_EXTENDED__o_done"><raise event="statifier_blocks.interrupt.resume.s_blk_SHELF"/></transition>
```

The group goes to its own `done` when its body finishes or when it is
abandoned, and back into its run when it is resumed:

```xml
<transition event="done.state.s_blk_SHELF__body" target="s_blk_SHELF__o_done" type="internal"/>
<transition event="statifier_blocks.interrupt.abandon.s_blk_SHELF" target="s_blk_SHELF__o_done" type="internal"/>
<transition event="statifier_blocks.interrupt.resume.s_blk_SHELF" target="s_blk_SHELF__run" type="internal"/>
```

The root sequence moves on when the group is done:

```xml
<transition event="done.state.s_blk_SHELF" target="s_blk_CLEAR" type="internal"/>
```

The body cancels the wait's timer when it is left, however it is left
(`StatifierBlocks.Compiler.Cancels`):

```xml
<onexit><cancel sendid="s_blk_SHELVED__send"/></onexit>
```

### What Describe and the Map show

The Describe outline (`StatifierBlocks.Describe.render/2`) reads the wait
and the three handlers as:

```text
Wait 7d
When hold.collected, abandon
When hold.cancelled, abandon
When hold.extended, resume
```

and the flow around them as:

```text
After Run interruptible steps (done), Send hold.shelf_cleared
Wait 7d (done) ends the group
On hold.collected, When hold.collected, abandon abandons the group
On hold.cancelled, When hold.cancelled, abandon abandons the group
On hold.extended, When hold.extended, resume resumes the group
```

The Map (`StatifierBlocks.Map.graph/2`) draws an interrupt edge for each
handler (`StatifierBlocks.Map.interrupts/1`): the two abandons leave the
group (`"to" => "exit"`) and the resume goes back into its body
(`"to" => "body"`). It draws no timer edge: that edge joins a delayed
`core.send` to the rule its event reaches (`StatifierBlocks.Map.timers/1`),
and here the deadline is the wait's own duration.

### What a host sees

The chart sends `hold.ready`. When the group starts, the chart asks the
host for a delayed send seven days out, and parks. Then one of these
happens:

- **The patron collects the item.** The handler abandons the group, the
  timer is cancelled, and the chart sends `hold.shelf_cleared`.
- **The patron cancels the hold.** The same: the group is abandoned, the
  timer is cancelled, and the chart sends `hold.shelf_cleared`.
- **Seven days pass.** The wait finishes, the group finishes as `done`,
  and the chart sends `hold.shelf_cleared`.
- **The patron asks for more time.** The handler resumes the group: the
  timer is cancelled, a new delayed send seven days out is asked for, and
  the chart parks again.

None of these raises, refuses or reports a finding. As in the first
pattern, a `core.group` declares no outcomes of its own, so the step after
it cannot tell a collection from a cancellation from the deadline: two
abandoning handlers on one rail are indistinguishable downstream
(`StatifierBlocks.Core.Await`, "Why this is a type rather than an
arrangement"). When the flow needs to know, and there is one event to
tell apart, use the `core.await` below.

A `core.resumable_group` in the group's place parks the same way. Its body
here is the one wait, so resuming where it left off re-enters the wait,
and the wait asks for its full seven days again when it is entered.

### When the event does exist: `core.await` with a `timeout`

When the flow is waiting for one event, and not only for whatever may
interrupt it, that event exists and `core.await` names it. Its optional
`timeout` is the deadline, and it ends at one of two declared outcomes,
`received` or `timed_out` (`StatifierBlocks.Core.Await.outcomes/1`), so
the step after it can tell the two apart. If collecting the item were the
only thing that could end the hold, this block in the group's place would
do the job:

```json
{"id": "blk_COLLECT", "type": "core.await", "type_version": 1,
 "config": {"event": "hold.collected", "timeout": "7d"}}
```

```text
After Wait for hold.collected, giving up after 7d (received, timed_out), Send hold.shelf_cleared
```

It is the shorter answer the first pattern ends with, for the same
reason. Reach for the group and the wait when there is no such event, or
when several events may end the park.
