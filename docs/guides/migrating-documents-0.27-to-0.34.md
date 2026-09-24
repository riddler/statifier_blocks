# Migrating a document from 0.27 to 0.34

This guide shows you how to move a block document written against
`statifier_blocks` 0.27 onto the outcome vocabulary 0.34 offers: a composite
that declares its own outcomes, an interrupt handler that names the outcome it
finishes with, and the `on_<name>` slots an author fills to say what happens
next.

Nothing here is required. A 0.27 document still compiles on 0.34, and the
rails it uses still mean what they meant. You migrate a document when you want
the enclosing body to act on **how** a composite finished, which 0.27 could
not express.

The worked pair is in
[`test/fixtures/documents/migrating_0_27_to_0_34/`](../../test/fixtures/documents/migrating_0_27_to_0_34/),
and
[`test/statifier_blocks/migrating_documents_guide_test.exs`](../../test/statifier_blocks/migrating_documents_guide_test.exs)
compiles every file in it on the current release.

## What keeps working unchanged

The rail vocabulary was not removed. Declared outcomes were added beside it
across 0.28 to 0.32, and a document that uses none of them compiles as it did:

- A `core.group`'s `interrupts` rail, and a `core.on_event` handler on it, work
  as before. The handler's `outcome` select still has exactly the two values
  `abandon` and `resume`, with `abandon` the default
  (`StatifierBlocks.Core.OnEvent.config_schema/1`).
- A handler with no `finish_as` finishes as `done`, and emits the bytes it
  emitted before the key existed (`StatifierBlocks.Core.OnEvent.outcomes/1`,
  and the moduledoc section "Naming the outcome this handler finishes with").
- A composite that declares no `outcomes` still answers its expansion root's
  outcomes and still compiles to its expansion in place. ADR-0002's Amendment
  of 2026-09-12, `C3`, is the rule.
- The `on_error` slots `core.invoke`, `core.map` and `core.subchart` declare
  outright are not affected by the declared-outcome amendments.

The before document in the fixture pair compiles on 0.34.0 to the same SCXML
it compiled to on 0.27.0.

## The limit you are migrating away from

On 0.27 a composite finishes as whatever its expansion root finishes as. A
screen whose root is a `core.group` therefore finishes as `done`, whether the
visitor verified their email or pressed Back, and the enclosing body cannot
tell the two apart.

`before.json` is that shape. Its screen, declared in `screen_before.json`,
waits for `email.verified` and carries a Back handler on its group's
`interrupts` rail:

```json
{
  "type": "core.on_event",
  "id_suffix": "back",
  "config": {"event": "registration.back_pressed", "outcome": "abandon"}
}
```

The step after the screen, `blk_INTERESTS`, is chained on the group's
completion, so it runs after Back as well as after verification:

```xml
<transition event="done.state.s_blk_VERIFY_body" target="s_blk_INTERESTS" type="internal"/>
```

## Step 1: declare the composite's outcomes

Add an `outcomes` list to the composite's declaration, naming every way it can
finish. On a data declaration the key is `"outcomes"`; on a `use
StatifierBlocks.Composite` module it is the `outcomes:` option. Both arrived in
0.28.0.

```json
"outcomes": ["received", "timed_out", "went_back"]
```

Each name must be one something in the expansion can raise. `received` and
`timed_out` are `core.await`'s own outcomes. `went_back` is raised by nothing
yet, so on its own this step is refused with an `:outcome_not_raisable`
finding at the Resolve stage, against the composite block. Step 2 is what
makes it raisable.

Name every completion you want to finish the composite. Since 0.30.0 a
declaring composite compiles to a state of its own, and a member completion
the list does not name does not finish it: the composite stays in that state. The test "an undeclared completion leaves the composite state resting",
in `test/statifier_blocks/composite/declared_outcomes_test.exs`, pins that.

The params do not change, so the block's stored `config` and `type_version`
do not change either, and no `"migrations"` step is needed.

## Step 2: name the outcome the handler finishes with

Give the Back handler a `finish_as`, beside the `outcome` select. The key
arrived in 0.31.0:

```json
{
  "type": "core.on_event",
  "id_suffix": "back",
  "config": {
    "event": "registration.back_pressed",
    "outcome": "abandon",
    "finish_as": "went_back"
  }
}
```

The handler still abandons its group first. It then finishes as `went_back`
rather than `done`, which is what makes the declared name raisable.
`screen_after.json` is the declaration after steps 1 and 2.

Three values of `finish_as` are refused by
`StatifierBlocks.Core.OnEvent.validate_config/1`, each as a finding on the
key:

- any name on a handler whose `outcome` is `resume`, because a resuming
  handler finishes nothing;
- `done`, because that is what a handler with no name already finishes as;
- a name that is not outcome-shaped, such as `Went Back`.

## Step 3: fill the `on_<name>` slots in the document

A declaring composite has one `on_<name>` slot per declared outcome, after any
pass-through slots its declaration names (`on_received`, `on_timed_out` and
`on_went_back` here). Each holds at most one block; put a `core.sequence`
there for several steps.

Move what should happen after each outcome into its slot. In `after.json` the
step that used to follow the screen moves into `on_received`, keeping its id,
and the Back work goes in `on_went_back`:

```json
"slots": {
  "on_received": [{"id": "blk_INTERESTS", "type": "core.assign", ...}],
  "on_went_back": [{"id": "blk_DETAILS", "type": "core.assign", ...}]
}
```

The block in a slot runs inside the composite's own state, before that
outcome's final. For `on_went_back`:

```xml
<transition event="done.outcome.s_blk_VERIFY_back.went_back" target="s_blk_DETAILS" type="internal"/>
<transition event="done.state.s_blk_DETAILS" target="s_blk_VERIFY__o_went_back" type="internal"/>
<final id="s_blk_VERIFY__o_went_back">
  <onentry><raise event="done.outcome.s_blk_VERIFY.went_back"/></onentry>
</final>
```

An empty slot, `on_timed_out` here, reaches the final directly.

The enclosing body still continues on the composite's completion, whichever
outcome it finished with. The composite still raises its own event,
`done.outcome.<composite state id>.<name>`, for anything that selects on the
outcome directly.

## What changes in the compiled chart

Migrating the declaration moves the compiled bytes of every document that
uses the composite, even before the document fills a slot: the composite
becomes a state with one `<final>` per declared name, and a named handler's
final moves from `<handler state id>__o_done` to `<handler state id>__o_<name>`.
Re-capture any stored compiled chart or pinned chart identity for those
documents.

The migration is one-way. On 0.27.0 the `after.json` document, compiled
against `screen_after.json`, compiles without a finding, but the `outcomes`
key and `finish_as` are ignored and the children of both `on_` slots are
dropped from the chart. Migrate a document only once every host that compiles
it is on 0.34.

## Shapes that are refused

Each of these is refused rather than compiled:

| You wrote | What you get | Since |
|---|---|---|
| a declared outcome nothing in the expansion raises | an `:outcome_not_raisable` finding at the Resolve stage, against the composite block | 0.28.0 |
| the same name twice in `outcomes` | the declaration is refused | 0.28.0 |
| a pass-through slot named `on_<name>` for a name the same declaration lists in `outcomes` | the declaration is refused; rename one of them | 0.30.0 |
| `finish_as` with `resume`, `finish_as: "done"`, or a name that is not outcome-shaped | a `validate_config/1` finding on `finish_as` | 0.31.0 |
| a slot on a composite block that its type does not declare, such as `on_went_back` on a composite whose declaration was not migrated | an `:undeclared_slot` finding at the Resolve stage, saying the slot's contents are dropped | 0.32.0 |
| a block in a pass-through or `on_<name>` slot whose id equals one the composite's expansion mints for its own members | a `:minted_id_collision` finding at the Resolve stage; give the block another id | 0.33.0 |

The `:undeclared_slot` row is the one to watch while migrating in two passes:
filling the slots before the declaration lists the outcomes is refused, not
ignored.

## For a composite written as a module

A `use StatifierBlocks.Composite` module takes the same list as the
`outcomes:` option. Since 0.32.0 a module may instead implement the optional
`declared_outcomes/1` callback, so that its outcomes follow each block's
config; a module that writes both is refused. A data declaration has only the
static `"outcomes"` list.

## Other changes between 0.27 and 0.34 that touch a stored document

These are not part of the outcome vocabulary, and each is in the
[CHANGELOG](../../CHANGELOG.md):

- 0.28.0: a `core.on_event` capture pair whose source is absent from the
  payload leaves its destination unwritten instead of writing `:undefined`,
  so a document that captures by a path compiles to a different chart; and
  the reserved `<donedata>` param on a failure-classed final is renamed.
- 0.33.0: a document may declare the events it accepts, as an `accepts` list.
  A document saved with a non-empty `accepts` cannot be read by 0.32.0 or
  earlier.

## Where the decisions are recorded

[ADR-0002](../adr/0002-block-type-behaviour.md) records each step, as the
Amendments of 2026-09-12 (`C1` to `C5`, declared outcomes), 2026-09-13 (`C6`,
the composite's own state, and `C7`, the `on_<name>` slots) and 2026-09-14
(`C8`, `finish_as`).
