# ADR-0013: A fan-out child's summary is typed by the parent's declaration, with an optional child-side one and a dormant agreement check

Status: proposed (2026-09-06, drafted for `sb-57yc` under the operator's
campaign-034 grant, recording the rulings `RQ-033-19` B and `RQ-034-2` of
2026-09-06). It merges at proposed under that campaign's invariant, like every
other record filed with it; flipping it to accepted is a separate request
through the same `docs/adr/` gate, after `sb-nqfd` has built it.

This record decides only what is written below. The four amendments it needs
in the records it widens - ADR-0002's callback surface, ADR-0004's C1,
ADR-0009's decisions 4, 5 and 7, and ADR-0011's decision 12 - are `sb-jvz3`'s,
and they are named in "What this record owes the accepted records" rather than
made here. A proposed record does not reach into an accepted one.

## Context

**`core.map` collects N answers and nothing says what one of them holds.**
ADR-0009 decision 5 (`docs/adr/0009-fan-out-block-type.md:286`) has the whole
result of the block written to one author-named location as a dense list in
item-index order. The shipped field is `collect`
(`lib/statifier_blocks/core/map.ex:348-354`; decision 4's table at `:183`
declares it `assign_to`, and the Note of 2026-09-05 records the four fields
that shipped instead). Its declared write is
`{:path, %{writes: {:list, :unknown}}}`.

**ADR-0011 decision 12 says why the element is unknown, and names this record's
question.** `docs/adr/0011-typed-environment.md:520-536`: `collect`'s `T` is
`{:list, :unknown}` because "the shipped child recipe emits the outcome name
and nothing else, so a declared item type would be a claim about bytes that are
not there", and "whether a child chart may declare what its `donedata` carries
is the open question this leaves". ADR-0009's own closing Note
(`docs/adr/0009-fan-out-block-type.md:754-758`) leaves the same question on its
decisions 5 and 6 and names `sb-pg91` as carrying it. This record answers it.

**The bytes that are not there are C1's.** ADR-0004's amendment C1
(`docs/adr/0004-compiler-provenance.md:1262-1287`) has a document compiled for
use as a child emit one top-level `<final>` per root-block outcome, carrying
the outcome name as done data and, since the campaign-033 failure seam, the
reserved `statifier_persistence:run_status` param on a failure-classed one
(`lib/statifier_blocks/compiler.ex:255-256`, `:1367-1379`). Two params, both
compiler-minted, neither of them the child's answer. The 2026-09-05 Note at
`docs/adr/0004-compiler-provenance.md:1707-1712` says the sibling it adds "does
not widen C1"; this record does widen it, and says so.

**The parent's compiler cannot look.** A block type cannot read the document it
references: `emit/2` is a pure function of its block and its context, and the
context deliberately carries no palette and no other document
(`lib/statifier_blocks/core/subchart.ex:47-52`). That is the same reason
`core.subchart` has the author declare the child's outcomes in a config field
rather than reading them off the chart, and it is why the answer to "what does
one collected element hold" cannot be *derived* at the parent's compile. It has
to be *declared*, on one side or the other, and the two sides are in different
documents that are rarely in one process at one time.

**The vocabulary already exists and is not this package's.**
`statifier_datamodel` (`mix.exs:134`, `~> 0.1`; `mix.lock:31`, 0.1.0 resolved)
owns type expressions: `t:StatifierDatamodel.Types.t/0` is a declared name, one
of the nine scalars the set is closed at, an opaque string, or `:unknown`;
`Types.parse/2` reads a document's spelling into one, and
`Types.satisfies?/3` and `Types.satisfies/3` are the read check
(`deps/statifier_datamodel/lib/statifier_datamodel/types.ex:142`, `:198`,
`:232`); `Declarations.fetch/2` resolves a name the document's `types` key
declares and `Declarations.fields/2` reads a declaration's ordered fields
(`deps/statifier_datamodel/lib/statifier_datamodel/declarations.ex:134`,
`:178`). This record adds no type grammar; it says which existing
spellings go where.

## Decision

**1. `core.map` declares the element type of `collect`, in a new optional
config field spelled in `statifier_datamodel`'s vocabulary.**

The field is `collect_type`, optional, with an empty default, and it is
meaningful only when `collect` is set. Its value is one of two spellings:

| Spelling | Read by | Means |
|---|---|---|
| a string | `StatifierDatamodel.Types.parse/2` against the document's declarations | the element is of that type - normally `{:declared, name}` for a name the datamodel document's `types` key declares, and a scalar or an opaque string are admitted because `parse/2` admits them |
| a list of field maps in the `types` entry's own `fields` spelling | `StatifierDatamodel.Declarations.fields/2` | the element is an **anonymous shape** with those fields, checked exactly as a named one is |

An absent or empty `collect_type` is what every stored document has today and
means what ADR-0011 decision 12 says: the element is `:unknown`. Nothing about
such a document changes.

The field is a **type**, never a path and never an expression. It does not gain
`datamodel_path?`, it is not read through `AssignLocation`, and its findings are
about the spelling only: a string naming neither a declaration nor a scalar nor
a plausible opaque string is not a refusal here, because `Types.parse/2` is
total and answers `{:opaque, s}` - the same permissiveness ADR-0006 and
ADR-0011 already chose, where what the document does not say is not thereby
wrong.

The declaration is the **parent's** because the parent is the document that is
being compiled. A `core.map` block names its child chart by document id
(`chart`, `lib/statifier_blocks/core/map.ex:327-333`) and cannot resolve it, so
the parent-side declaration is the only one that is always in hand where
`collect`'s environment entry is computed.

**2. A root block type may declare what its document's `<donedata>` carries,
through a new optional `BlockType` callback, `donedata_type/1`.**

`StatifierBlocks.BlockType` declares:

```elixir
@callback donedata_type(Block.config()) :: [donedata_field()]
```

with

```elixir
@type donedata_field :: %{
        name: String.t(),
        path: String.t(),
        type: StatifierDatamodel.Types.t() | :unknown
      }
```

- `name` is the `<param>` name the field is emitted under. It is a bare
  lowercase identifier in the shape every other `<param>` name this package
  mints has, and it may be neither `outcome` nor
  `statifier_persistence:run_status` - those two are the compiler's, reserved
  by C1 and by the failure seam, and a declaration that collides with either is
  an `:invalid_donedata_field` Emit finding against the root block rather than
  a silently shadowed param.
- `path` is the datamodel path the value is read from at the child's own
  runtime. The `<param>` is emitted with `expr` set to that path, which is what
  makes the declaration produce bytes at all.
- `type` is the field's type in `statifier_datamodel`'s vocabulary, and it is
  the half decision 4 compares.

The callback is **optional**, and a type that does not export it declares
nothing, which is where every shipped `core.*` type stays. It is resolved
through a `BlockType.donedata_type/2` on this module, the way `outcomes/1` and
`failure_outcomes/1` are - `Code.ensure_loaded?/1` plus
`function_exported?/3`, defaulting to `[]`. The three rules `slots/1` and
`outcomes/1` carry apply unchanged: it is a **pure function of `config`**, it
is **total** for any config `validate_config/1` accepts, and it **never
raises**.

Order is declaration order and is never sorted, for ADR-0004 decision 6's
reason: the params serialize in the order this callback returns them, so
reordering the list moves compiled bytes.

This is the **thirteenth** callback on `StatifierBlocks.BlockType`, not the
twelfth. Twelve are declared today - `slots/1`, `config_schema/1`,
`validate_config/1`, `current_version/0`, `emit/2`, `io/1`, `migrate_config/2`,
`fixtures/0`, `palette_entry/0`, `outcomes/1`, `failure_outcomes/1`, `summary/1`
(`lib/statifier_blocks/block_type.ex:252`, `:330`, `:338`, `:345`, `:374`,
`:382`, `:389`, `:424`, `:509`, `:537`, `:570`, `:609`), seven of them optional
(`:611-617`). ADR-0002 decision 5's table still reads "nine callbacks, five
required" (`docs/adr/0002-block-type-behaviour.md:109-121`), which is what makes
the count worth stating here rather than counting from the record.

The name is `donedata_type/1` and not `summary/1` or `child_summary/1` on
purpose. `summary/1` is the card's second line (`:609`) and
`Context.child_summary()` is the compiler's resolved-child record
(`lib/statifier_blocks/compiler.ex:1116`, `:1121`); both are shipped, and a
third meaning of "summary" on the same behaviour would be a collision an author
has to disambiguate by reading two records.

**3. The `child_use` final emits the declared fields as `<donedata>` params,
after the params the compiler already mints.**

Compiling with `child_use: true`, each top-level `<final>` carries, in this
order:

1. `<param name="outcome" expr="'<outcome>'"/>` - C1's, unchanged;
2. the reserved `statifier_persistence:run_status` param, on a failure-classed
   outcome only - the failure seam's, unchanged;
3. one `<param name="<name>" expr="<path>"/>` per entry of the root type's
   `donedata_type/1`, in declaration order.

The declared fields go **after both** compiler-minted params rather than
between them, so that a document that declares nothing compiles to the bytes it
compiles to today and a failure-classed final does not have its two existing
params reordered. The ruling's phrase "after the outcome param" is satisfied by
either position; byte stability picks this one.

The fields are emitted on **every** top-level `child_use` final, including a
failure-classed one, because the declaration is a property of the document and
not of an outcome. What a path holds when a child finished badly is the child's
business; the parent reads the element it was given.

This widens ADR-0004's C1, which today has the final carry the outcome name and
nothing else. `sb-jvz3` carries that amendment.

**4. Agreement between the parent's declaration and the child's is checked
wherever both documents are in hand, and is dormant at the parent's compile.**

The check is: the child's `donedata_type/1` projected as an anonymous shape -
one field per entry, `name` and `type` as declared, every field `required?:
false` - satisfies the parent's `collect_type` under
`StatifierDatamodel.Types.satisfies?/3`, with the *child's* projection as
`held` and the *parent's* declaration as `expected`. That is sd's own read
check, in its own direction: the parent is the reader.

Four states, and each is decided rather than incidental:

| Parent declares | Child declares | What happens |
|---|---|---|
| no | no | nothing. `collect` is `{:list, :unknown}`, which is ADR-0011 decision 12 unchanged |
| yes | no | the parent's declaration types `collect` (decision 5). No check runs; there is nothing to disagree with |
| no | yes | the child's declaration produces the params of decision 3, and `collect` stays `{:list, :unknown}` at the parent. The bytes are richer; the parent's typing is not |
| yes | yes | **the parent's wins for typing**, and the pair is checked as above wherever both documents are in hand |

The parent's winning is the second-order ruling of `RQ-034-2` and it follows
from decision 1's reason: the parent's compile has the parent's document and
never the child's, so a typing that depended on the child's declaration would
be a typing that is available in the editor and absent in the compiler. A type
that changes with who is looking is worse than one that is only ever the
author's word.

**The check is dormant at the parent's compile.** It is not an Emit finding, it
is not a validation finding, and its absence is not a warning. A `core.map`
whose `collect_type` disagrees with its child's `donedata_type/1` compiles to
exactly the bytes it would compile to if they agreed. The check runs where both
documents are genuinely in hand:

- the editor, with the child document loaded beside the parent - an ADR-0005
  findings-layer advisory, at `:warning`, on the `collect_type` field;
- a host that holds a document set and wants to check it before publishing.

It is dormant rather than absent because the alternative is a compile that
fails on a document the compiler cannot read, which is a refusal an author
cannot act on and a build that breaks when an unrelated document changes.

**5. `collect` types as `{:list, T}`, where `T` is the parent's declaration and
`:unknown` when there is none.**

ADR-0011 decision 12's `{:list, :unknown}` becomes a reference to this record
rather than a constant. `core.map`'s environment contribution - decision 2's
rule for a `{:path, %{writes: T}}` field - is:

| `collect_type` | The environment entry at `collect`'s path |
|---|---|
| absent or empty | `{:list, :unknown}` |
| a string naming a declaration or a scalar | `{:list, <that spelling>}` |
| an anonymous shape (decision 1's second spelling) | `{:list, :unknown}` |

The third row is a real limitation and not an oversight. `Environment`'s
`type_expr()` is a *spelling*: a string, `:unknown`, or a list of one of those
(`lib/statifier_blocks/environment.ex:93`). An anonymous shape has no spelling,
so it cannot be carried in the environment without widening that type, and
widening it is ADR-0011's decision and not this record's. An author who wants
the element type to flow to the blocks after the `core.map` declares a **named**
type in the datamodel document and names it here; the anonymous spelling buys
the agreement check of decision 4 and the params of decision 3, and does not
buy environment typing. The deferred question below names the widening.

**6. The payload discipline is `N` times the declared summary's size, and the
cap stays the host's.**

ADR-0009 decision 7 (`docs/adr/0009-fan-out-block-type.md:386`) states the cost
as per-step rather than per-run: the collected list lives in the parent's
datamodel and is serialized on every persisted step for the rest of the run.
This record makes the multiplicand nameable. Before it, "the child chart decides
the size of its own answer" was guidance a host could only follow by reading the
child; after it, the size is the declared summary's, and it is **`N` times the
declared summary's size** where `N` is the length of `items`.

Two consequences, and the second is the operative one:

- A declaration is the cheapest place to see the cost. A root type that
  declares two integers costs two integers per item; one that declares a record
  with thirty fields costs thirty. The declaration is in one file and the review
  of it is a review of the whole batch's datamodel footprint.
- **The cap is still the host's and this record sets no number**, exactly as
  ADR-0009 decision 7's fourth clause has it: the compiler cannot know `N`, and
  a limit written into a document would be a deployment property in a document.
  What this record adds is that a host enforcing a cap now has a compile-time
  quantity to enforce against - the declared summary's field count and types -
  rather than only a runtime measurement of what the children happened to
  return. The refusal remains the runtime's, carried on the ordinary error
  route, not a compile finding.

Decision 7's other clauses are untouched: an optional `collect` that is simply
omitted is still the cheapest correct shape for a large batch, `sensitive?`
still applies to the location holding `N` answers, and there is still no
compression, no truncation and no spill.

## Consequences

**The change is additive and the release is a minor one.** No stored document
compiles to different bytes: `collect_type` is a new optional field with an
empty default (ADR-0001 decision 6's absent-key reading), and
`donedata_type/1` is a new optional callback that no shipped type exports.
A document declaring neither is every document that exists today.

**A root block type becomes a thing an author designs, not only a thing a
document has.** Until now the root block of a document compiled for use as a
child was ordinary; the only thing that made it a root was where it sat. It now
carries the document's outward-facing contract, which is a genuinely new role
for a block type and the reason decision 2 puts the declaration on the type
rather than on the document. A host that publishes a fan-out child chart will
find itself writing a block type for its root purely to declare
`donedata_type/1`, and that is the intended shape: the type is the versioned,
registered thing (ADR-0002 decision 8's `current_version/0`), and the contract
should move with it.

**Two declarations of one fact can drift, and this record chooses to let them.**
Decision 4 is dormant at compile, so a parent and a child can disagree for as
long as nobody opens them together. That is a deliberate trade against the
alternatives: a compile that reads the child (impossible, per Context), a
compile that refuses without reading it (a refusal on no evidence), or one
declaration only (which forces either the parent to guess or the compiler to
resolve). Drift is visible in the editor and at a host's publish check, and it
costs a wrong element type in the environment rather than wrong bytes.

**An anonymous shape does not reach the environment.** Decision 5's third row is
the price of not widening ADR-0011's `type_expr()` from this record. An author
who declares an inline shape and then expects a `core.branch` after the
`core.map` to see the fields will find `:unknown`, which is permissive rather
than wrong, but is less than the declaration implies. The editor should say so
where it renders `collect_type`; naming the field's two spellings apart is
ADR-0005's call.

**The failure seam and this record share a `<donedata>` and do not interact.**
The reserved `statifier_persistence:run_status` param is minted by the compiler
on a failure-classed final and read by a durable stepper; a declared field is
minted from the author's path and read by the parent. Decision 2's reserved-name
refusal is what keeps them apart, and decision 3's ordering is what keeps the
first one's bytes stable.

**Nothing here touches the wire format, the trace, or the invoke boundary's
version.** The `<donedata>` element is SCXML's channel and it is already
carrying params; this record adds params to it and adds no type to any wire
format.

## The contract as typespecs

The new callback and its declaration type, as decision 2 fixes them:

```elixir
@typedoc """
One field a document's `<donedata>` carries beside the params the compiler
mints: the `<param>` name, the datamodel path its `expr` reads, and the
field's type in `statifier_datamodel`'s vocabulary.
"""
@type donedata_field :: %{
        name: String.t(),
        path: String.t(),
        type: StatifierDatamodel.Types.t() | :unknown
      }

@callback donedata_type(Block.config()) :: [donedata_field()]

@optional_callbacks io: 1,
                    migrate_config: 2,
                    fixtures: 0,
                    palette_entry: 0,
                    outcomes: 1,
                    failure_outcomes: 1,
                    summary: 1,
                    donedata_type: 1
```

The resolver every consumer reads it through, in `failure_outcomes/2`'s shape:

```elixir
@spec donedata_type(module(), Block.config()) :: [donedata_field()]
def donedata_type(module, config)
```

`core.map`'s new field, as decision 1 fixes it - the seventh entry of
`config_schema/1` (`lib/statifier_blocks/core/map.ex:317-366`), after
`collect` and before `on`:

```elixir
%{
  key: "collect_type",
  type: :type_expr,
  label: "Each answer is a",
  required?: false,
  default: ""
}
```

`emit/2` keeps its signature on both types. `core.map`'s gains nothing at all -
`collect_type` produces no bytes, only an environment entry (decision 5) and an
editor advisory (decision 4). `StatifierBlocks.Compiler`'s `child_use` path
gains decision 3's third group of params, appended to the list
`completion_final/4` already builds
(`lib/statifier_blocks/compiler.ex:1367-1379`).

The agreement check, as a function of the two declarations rather than of the
two documents:

```elixir
@spec agrees?(StatifierDatamodel.Declarations.t(), [donedata_field()], term()) ::
        StatifierDatamodel.Types.reason()
```

- the first argument is the **parent's** declarations, because the parent's
  `collect_type` is what is being satisfied;
- the second is the child's `donedata_type/1`;
- the third is the parent's `collect_type` spelling;
- the answer is sd's own `t:StatifierDatamodel.Types.reason/0`, so a consumer
  that renders why a pair disagrees renders sd's reason and not a second
  vocabulary of this package's.

## Worked shape: a card-processing chunk that answers with its counts

A settlement batch. The parent runs one child chart per chunk of a day's
captures and wants the counts back; the child chart's root block type is the
host's `myapp:settlement_chunk`.

The datamodel document declares the summary once, under `types`:

```json
{"name": "cards.chunk_result",
 "kind": "shape",
 "label": "Chunk result",
 "fields": [{"name": "authorized", "type": "integer", "required?": true},
            {"name": "declined", "type": "integer", "required?": true}]}
```

The child's root block type declares what its `<donedata>` carries:

```elixir
@impl true
def donedata_type(_config) do
  [%{name: "authorized", path: "cards.chunk.authorized", type: :integer},
   %{name: "declined", path: "cards.chunk.declined", type: :integer}]
end
```

The parent's `core.map` declares what it expects an element to be:

```
core.map
  items:        cards.day.chunks
  chart:        bdoc_01JWIZ
  item_as:      chunk
  collect:      results
  collect_type: cards.chunk_result
  on:           all
```

The child compiled with `child_use: true`, on its `done` outcome:

```xml
<final id="s_root_done">
  <donedata>
    <param expr="'done'" name="outcome"/>
    <param expr="cards.chunk.authorized" name="authorized"/>
    <param expr="cards.chunk.declined" name="declined"/>
  </donedata>
</final>
```

and on a failure-classed `error` outcome, with the reserved param keeping its
place:

```xml
<final id="s_root_error">
  <donedata>
    <param expr="'error'" name="outcome"/>
    <param expr="'failed'" name="statifier_persistence:run_status"/>
    <param expr="cards.chunk.authorized" name="authorized"/>
    <param expr="cards.chunk.declined" name="declined"/>
  </donedata>
</final>
```

Three readings of the same pair of documents:

| Where the pair is | What is checked | What follows |
|---|---|---|
| the parent's compile | nothing (decision 4 is dormant) | `results` is `{:list, "cards.chunk_result"}` in the environment, from `collect_type` alone |
| the editor, child loaded | the child's projection satisfies `cards.chunk_result` | `:covers` - both required fields are present as integers, so no advisory |
| the editor, after someone renames the child's `declined` field to `refused` | the same check | `{:missing, ["declined"]}` - a `:warning` on the `collect_type` field, and the parent still compiles to the same bytes |

The cost, by decision 6: a day of 400 chunks costs 400 two-integer maps in the
parent's datamodel, serialized on every persisted step until the run ends. A
root type that had declared the whole capture list instead would cost 400 of
those, which is the multiplication the declaration makes visible in one file.

## What this record owes the accepted records

Four accepted records read differently once `sb-nqfd` has built this one. They
are not edited here; `sb-jvz3` carries all four as one amendments request
through the same `docs/adr/` gate, citing this record.

- **ADR-0002 decision 5's callback surface**
  (`docs/adr/0002-block-type-behaviour.md:109-121`), which reads "nine
  callbacks, five required" and lists nine. Twelve are declared today and this
  record adds the thirteenth. The Note of 2026-09-06 at `:3832` is the
  precedent for how a new optional callback is recorded there.
- **ADR-0004's amendment C1**
  (`docs/adr/0004-compiler-provenance.md:1262-1287`), which has the `child_use`
  final carry the outcome name as done data. Decision 3 widens it, and the Note
  at `:1707-1712` that says its sibling "does not widen C1" is what makes the
  widening worth stating rather than assuming.
- **ADR-0009 decisions 4, 5 and 7**
  (`docs/adr/0009-fan-out-block-type.md:183`, `:286`, `:386`), for
  `config_schema/1`'s new field, for what one accumulated element now holds,
  and for decision 6's naming of the multiplicand. ADR-0009's closing Note at
  `:754-758` names this question as its own open one and points at `sb-pg91`;
  that bead closes as folded when this record lands.
- **ADR-0011 decision 12** (`docs/adr/0011-typed-environment.md:520-536`),
  whose `{:list, :unknown}` becomes decision 5's table. Its sentence "whether a
  child chart may declare what its `donedata` carries is the open question this
  leaves" is answered here, and its deferred list loses that entry.

## Deferred questions, named rather than guessed

- **Should `Environment`'s `type_expr()` carry an anonymous shape?** Decision
  5's third row says an inline `collect_type` types `collect` as
  `{:list, :unknown}` because a shape has no spelling
  (`lib/statifier_blocks/environment.ex:93`). Widening the type to carry a
  structural entry is ADR-0011's decision, it reaches every field with a
  `writes` key and not only this one, and it is not made here.
- **Should a `core.subchart` declare the same thing?** One child answers one
  `<donedata>`, and `assign_to` writes it to one location that ADR-0011
  decision 13 is already reopening. The same parent-side field would type it,
  and the same child-side callback already produces the bytes - decision 2 is
  written on `BlockType` rather than on `core.map` for that reason. Whether
  `core.subchart` gains the field is ADR-0009's and ADR-0011's question
  together, and it has no consumer today.
- **Should `donedata_type/1`'s `path` admit an expression rather than a path?**
  It is emitted as a `<param>`'s `expr`, so an expression would work
  mechanically, and `core.subchart`'s `params` field already sends literal
  params. A path is chosen here because it is checkable against the child's own
  datamodel document and an expression is not. Whether the wider form is worth
  the loss is a later question.
- **Is a `collect_type` on a `core.map` with no `collect` worth a finding?**
  Such a declaration types nothing and is dead. That is an ADR-0005
  findings-layer advisory at `:info`, in the shape several already deferred
  there have, and no finding is decided here.
- **What does a host do with a declared summary that the runtime's cap
  refuses?** Decision 6 leaves the cap where ADR-0009 decision 7 put it, at the
  runtime, and the refusal on the ordinary error route. Whether a host wants to
  refuse at publish time instead, using the declared size, is a host question
  this record makes answerable and does not answer.
