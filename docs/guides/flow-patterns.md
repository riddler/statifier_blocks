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
