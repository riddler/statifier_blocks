# ADR-0013: A fan-out child's summary is typed by the parent's declaration, with an optional child-side one and a dormant agreement check

Status: proposed (2026-09-06, drafted for `sb-57yc` under the operator's
campaign-034 grant and finished under campaign-SF035's, recording
campaign-033's ruling `RQ-033-19` B, campaign-034's rulings `RQ-034-2`,
`RQ-034-14` and `RQ-034-15` b, and campaign-SF035's `RQ-SF035-1`, all of
2026-09-06). The labelled form is ADR-0009's, at
`docs/adr/0009-fan-out-block-type.md:710`, rather than ADR-0012's bare
"recording the ruling of <date>": this record carries five rulings from three
campaigns and one date does not tell them apart. It merges at proposed under
the campaign invariant, like every other record filed with it; flipping it
to accepted is a separate request through the same `docs/adr/` gate, after
`sb-nqfd` has built it.

Decisions 3 and 5 below are the campaign-SF035 rewrite. ADR-0009's Note of
2026-09-06 (`docs/adr/0009-fan-out-block-type.md:891-965`) merged while this
record's first draft was under review and fixed what one collected element is:
an envelope, not the child's answer. `RQ-034-15` b ruled that this record is
rewritten against that Note rather than held, and the two decisions below say
so where an earlier draft said otherwise.

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
(`lib/statifier_blocks/core/map.ex:353-359`; decision 4's table at `:183`
declares it `assign_to`, and the Note of 2026-09-05 records the four fields
that shipped instead). Its declared write is
`{:path, %{writes: {:list, :unknown}}}`.

**ADR-0011 decision 12 says why the element is unknown, and names this record's
question.** `docs/adr/0011-typed-environment.md:520-535`: `collect`'s `T` is
`{:list, :unknown}` because "the shipped child recipe emits the outcome name
and nothing else, so a declared item type would be a claim about bytes that are
not there", and "whether a child chart may declare what its `donedata` carries
is the open question this leaves". ADR-0009's Note of 2026-09-06
(`docs/adr/0009-fan-out-block-type.md:714`, the sentence at `:754`) leaves the
same question on its decisions 5 and 6 and names `sb-pg91` as carrying it.
This record answers it.

**A collected element is an envelope, and the child's answer sits inside it.**
ADR-0009's Note of 2026-09-06
(`docs/adr/0009-fan-out-block-type.md:891-965`) records what the shipped
handler already writes, per item, as a map with string keys: `"index"`, and
`"status"` - one of `"completed"`, `"failed"`, `"cancelled"` - and then either
the child's `"donedata"` on a completed child, or `"failure"` (a map with
`"reason"`, `"attempts"` and `"detail"`, `st-ADR-0068`'s three keys) on a
failed one, or nothing further on a cancelled one (the table at `:921-925`
and the sentence at `:927-929`). A child whose chart settles in a
failure-classed final is stored `failed`, and the driver answers the parent's
invocation with `{:failed, reason: <the run's failure>}` **rather than with
donedata** (`:915-917`). Two things follow for this record, and both are
written into the decisions rather than left to a reader: what a parent
declares is what one element's `"donedata"` member holds, not what the element
holds; and a
declared field never reaches the parent from a child that failed, because
there is no donedata on that arm at all.

**The bytes that are not there are C1's.** ADR-0004's amendment C1
(`docs/adr/0004-compiler-provenance.md:1262-1287`) has a document compiled for
use as a child emit one top-level `<final>` per root-block outcome, carrying
the outcome name as done data and, since the campaign-033 failure seam, the
reserved `statifier_persistence:run_status` param on a failure-classed one
(the key is `@run_status_key` at `lib/statifier_blocks/compiler.ex:263-264`,
minted by `run_status_param/0` at `:1443-1444` and appended at `:1423-1425`).
Two params, both
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
`statifier_datamodel` (`mix.exs:143`, `~> 0.3`; `mix.lock:31`, 0.3.0 resolved)
owns type expressions: `t:StatifierDatamodel.Types.t/0` is a declared name, one
of the nine its set is closed at, an opaque string, or `:unknown`;
`Types.parse/2` reads a document's spelling into one, and `Types.satisfies?/3`
and `Types.satisfies/3` are the read check
(`deps/statifier_datamodel/lib/statifier_datamodel/types.ex:155`, `:211`,
`:266`). The public readers of a declaration are two:
`Declarations.from_document/1` builds a document's declarations map, and
`Declarations.fetch/2` resolves one name in it
(`deps/statifier_datamodel/lib/statifier_datamodel/declarations.ex:108`,
`:134`). A declaration's ordered `fields` are read off the map `fetch/2`
answers rather than through a function of their own - `fields/2` in that
module is private (`:179`). This record adds no type grammar; it says which
spellings go where, and where the spelling it needs is another package's to
define - the inline shape decision 5 rests on - it cites that package's record
rather than writing a second grammar here.

Two things moved in `statifier_datamodel` 0.3.0, and neither moves this
record's premise. That package's own decision 3, as amended 2026-09-06, lets a
datamodel entry's `type` or `item_type` **name a declaration**; and
`Index.path_types/1` projects an entry into the expression language's six
kinds, leaving a declared name out of that projection
(`deps/statifier_datamodel/lib/statifier_datamodel/index.ex:417-430`;
`scalar_kind/1`'s catch-all answers `nil` at `:542`).
Both are about what a document says about **its own** paths. The parent's
compiler still cannot read the child's document, which is the premise the next
paragraph states and the one every decision below rests on.

## Decision

**1. `core.map` declares what a collected element's `"donedata"` holds, in a
new optional config field spelled in `statifier_datamodel`'s vocabulary.**

The field is `collect_type`, optional, with an empty default, and it is
meaningful only when `collect` is set. It names the type of the child's
answer - the `"donedata"` member of the envelope decision 5 fixes - and not
the type of an element, which is the envelope itself and is the same on every
`core.map`. Its value is **one** spelling: the
stored text is a type **name**, read by `StatifierDatamodel.Types.parse/2`
against the parent document's declarations. Normally that is
`{:declared, name}` for a name the datamodel document's `types` key declares;
a scalar spelling and an opaque string are admitted too, because `parse/2` is
total and admits them.

Its `config_schema/1` field type is the existing **`:string`**. ADR-0002
decision 7's set stays closed at the eight members declared today
(`lib/statifier_blocks/block_type.ex:149-157`), and no ninth is added here.

**An inline shape is not admitted by this record.** The `payload` amendment
accepted on 2026-09-06 took this same split for this same reason - "the
declared-name arm gets a field, and its type is `:string`", "the inline-shape
arm gets no field type here, and none is invented for it", under a section
whose closing sentence is "**No ninth field type is added by it**"
(`docs/adr/0002-block-type-behaviour.md:4108`, `:4121-4122`, `:4126`,
`:4133`). `collect_type` is the second field in this package to want
`statifier_datamodel`'s vocabulary, and it takes the shape the first one took
rather than inventing a second.

The inline arm for **this field** is deferred **by name**, to campaign-SF035's
typed-shapes theme, as four things that are only worth deciding together: a
`{:type_expr, opts}` member of ADR-0002 decision 7's field-type set, an
inline-shape inhabitant of `StatifierBlocks.Environment`'s `type_expr()`,
the editor control that renders one, and the migration of ADR-0002's `payload`
field onto the same spelling. Each on its own is a partial answer, and
`payload` is already waiting for the whole one. `sb-268w` carries the
migration of both fields to `{:type_expr, opts}`, and a document storing a
string reads as the name arm unchanged when it lands; until then
`collect_type`'s field type is `:string` and nothing here changes that.

The second of those four is not only deferred here: decision 5 **needs** it.
The environment entry that decision fixes is a structure, and
`type_expr()` cannot spell a structure today. That inhabitant is
`statifier_datamodel`'s to define and this package's to consume - the
inline-shape amendment to `sd-ADR-0001` (`statifier_datamodel`, proposed,
campaign-SF035 ruling `RQ-SF035-1`), which `sb-myt1` cites into ADR-0011's
decision 1 without respelling it. This record does the same: it says which
members the envelope has and which are required, and it spells none of the
grammar.

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
(`chart`, `lib/statifier_blocks/core/map.ex:332-338`) and cannot resolve it, so
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
        type: StatifierDatamodel.Types.t()
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
`config_schema/1` carry apply unchanged - `summary/1` is where they are
restated in those words (`lib/statifier_blocks/block_type.ex:598-601`), and
`outcomes/1` states the same three as its stability rule (`:527-531`): it is a
**pure function of `config`**, it is **total** for any config
`validate_config/1` accepts, and it **never raises**.

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
(`lib/statifier_blocks/compiler.ex:1164`, `:1169`); both are shipped, and a
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
not of an outcome, and the compiler has no other information at the point it
mints them.

**They do not thereby reach the parent from a failed child.** ADR-0009's Note
of 2026-09-06 records that a child run whose chart settles in a
failure-classed final is stored `failed` and that the driver answers the
parent's invocation with `{:failed, reason: <the run's failure>}` rather than
with donedata (`docs/adr/0009-fan-out-block-type.md:915-917`). So on that arm
the element carries `"status" => "failed"` and a `"failure"` map and no
`"donedata"` key at all (`:921-925`), and the declared fields, emitted or not,
are not in it. The parent reads the envelope's `"failure"` arm for a failed
child and its `"donedata"` arm for a completed one; decision 5's table is
where that is typed.

The emission is still on every final rather than on the completed ones only,
and the reason is byte determinism, not reachability: `donedata_type/1` is a
pure function of the root block's config (decision 2) and the compiler classes
outcomes, not runs. A final whose params are never read across the invoke
boundary costs the bytes of the params in the compiled document and nothing
else, and a document compiled for use as a child is also a document a host may
run directly, where its `<donedata>` is read by whoever invoked it.

This widens ADR-0004's C1, which today has the final carry the outcome name and
nothing else. `sb-jvz3` carries that amendment.

**4. Agreement between the parent's declaration and the child's is checked
wherever both documents are in hand, and is dormant at the parent's compile.**

The check is `StatifierDatamodel.Types.satisfies?/3`, with the *child's*
declaration as `held` and the *parent's* as `expected` - sd's own read check,
in its own direction, because the parent is the reader.

Both of that function's type arguments are
`t:StatifierDatamodel.Types.t/0`, and its covering step is *a record read as a
shape* between two `{:declared, _}` names over one declarations map
(`deps/statifier_datamodel/lib/statifier_datamodel/types.ex:309-324`). So the
check is spelled: take the parent document's declarations
(`Declarations.from_document/1`); add the child's `donedata_type/1` to that map
as one more declaration, of kind `record`, under a synthesized name, one field
per entry with `name` and `type` as declared and `required?: true`; and ask
`satisfies?/3` for `{:declared, synthesized}` against the parent's
`collect_type` as `Types.parse/2` reads it. The map is built for the question
and discarded with the answer; neither document is written to.

The projected fields are `required?: true` rather than optional, because
decision 3 emits every entry of `donedata_type/1` on every top-level final:
the child promises each one, and an optional held field satisfies no required
one in sd's check
(`deps/statifier_datamodel/lib/statifier_datamodel/types.ex:337`, the rule
stated in the comment at `:334-336`).

One consequence of sd's covering step is worth stating rather than leaving to
be discovered. It answers `:covers` only where the *expected* side is a
declaration of kind `shape`; two `record` names that are not the same name are
`:not_assignable` by construction. So decision 4's advisory is raised only
where the parent's `collect_type` names a **shape**. A `collect_type` naming a
`record` is dormant in a second sense: the answer is `:not_assignable`
whatever the child declares, so it is evidence about how sd spells nominal
typing and not evidence of drift, and this record declines to render it as an
advisory. Whether sd should decide a record against a record is
`statifier_datamodel`'s own question, named in the deferred list below.

Four states, and each is decided rather than incidental:

| Parent declares | Child declares | What happens |
|---|---|---|
| no | no | nothing. `collect` is `{:list, :unknown}`, which is ADR-0011 decision 12 unchanged |
| yes | no | the parent's declaration types `collect` (decision 5). No check runs; there is nothing to disagree with |
| no | yes | the child's declaration produces the params of decision 3, and `collect` stays `{:list, :unknown}` at the parent. The bytes are richer; the parent's typing is not |
| yes | yes | **the parent's wins for typing**, and the pair is checked as above wherever both documents are in hand |

The parent's winning is campaign-034's second-order ruling `RQ-034-2`, and it
follows from decision 1's reason: the parent's compile has the parent's document and
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

**5. `collect` types as `{:list, <the ADR-0009 envelope>}`, and the parent's
declaration types the envelope's `"donedata"` member.**

An element is not the child's answer. ADR-0009's Note of 2026-09-06 fixes it
as a string-keyed map (`docs/adr/0009-fan-out-block-type.md:921-929`), so the
declaration of decision 1 sits one level below the element and
`{:list, <the declared name>}` - which an earlier draft of this record wrote -
would be a wrong environment entry. ADR-0011 decision 12's `{:list, :unknown}`
becomes a reference to the envelope rather than to a name.

The envelope, as an inline shape, spelled by member name and requiredness only
(the grammar is the `sd-ADR-0001` amendment's, cited in decision 1 and not
respelled here):

| Member | Required | Type |
|---|---|---|
| `"index"` | yes | `integer` |
| `"status"` | yes | `string` - one of `"completed"`, `"failed"`, `"cancelled"` |
| `"donedata"` | no | the parent's `collect_type` as `Types.parse/2` reads it, or `:unknown` when there is none |
| `"failure"` | no | a shape of `"reason"`, `"attempts"` and `"detail"` - `st-ADR-0068`'s three keys, as ADR-0009's Note carries them |

`"donedata"` and `"failure"` are optional because no element carries both and
a cancelled element carries neither; `"index"` and `"status"` are required
because every element carries both, on all three arms. `"status"` is typed as
a string rather than as a three-member enumeration because
`t:StatifierDatamodel.Types.t/0` has no enumeration member
(`deps/statifier_datamodel/lib/statifier_datamodel/types.ex:82-86`) and this
record invents no grammar. A document's `one_of` enumerations are that
package's index talking about its own paths, not a type expression a field
can be given. The three values are named here so a reader of the type knows
them, and ADR-0009's Note is where they are decided.

`core.map`'s environment contribution - ADR-0011 decision 2's rule for a
`{:path, %{writes: T}}` field - is that envelope in every case:

| `collect_type` | The environment entry at `collect`'s path |
|---|---|
| absent or empty | `{:list, <envelope>}`, its `"donedata"` member `:unknown` |
| a name (a declaration, a scalar, or an opaque string) | `{:list, <envelope>}`, its `"donedata"` member that name |

Both rows are richer than what ships today, and the first one is richer with
no declaration at all: a block after a `core.map` learns that an element has
an index and a status and how a failure is shaped, whether or not the author
declared anything. That is the honest reading of ADR-0009's Note, which
records bytes the handler already writes.

**This entry needs the inline-shape inhabitant of `type_expr()`, and that is
the sequencing constraint of the whole record.** `Environment`'s `type_expr()`
is a *spelling* today - a string, `:unknown`, or a list of one of those
(`lib/statifier_blocks/environment.ex:93`) - and cannot carry a structure. The
inhabitant is `sb-myt1`'s amendment to ADR-0011 decision 1, citing the
inline-shape amendment to `sd-ADR-0001`. Until it lands the shipped entry
stays ADR-0011 decision 12's `{:list, :unknown}`, unchanged and not wrong,
because a spelling that cannot be written is not written; `sb-nqfd` builds
this decision after `sb-myt1` and not before. Widening `type_expr()` reaches
every field with a `writes` key and not only this one, which is why it is
ADR-0011's decision and not this record's.

**6. The payload discipline is `N` times the declared summary's size, and the
cap stays the host's.**

ADR-0009 decision 7 (`docs/adr/0009-fan-out-block-type.md:386`) states the cost
as per-step rather than per-run: the collected list lives in the parent's
datamodel and is serialized on every persisted step for the rest of the run.
This record makes the multiplicand nameable. Before it, "the child chart decides
the size of its own answer" was guidance a host could only follow by reading the
child; after it, the size is the declared summary's, and it is **`N` times the
declared summary's size** where `N` is the length of `items`.

The envelope of decision 5 adds a constant per element on top of that - an
index, a status string, and, on a failed element, `st-ADR-0068`'s three keys -
and it is there whether or not anything is declared. It is not what this
decision makes nameable, and it is not new: the shipped handler already writes
it. What decision 1 makes nameable is the multiplicand that the author
controls.

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
empty default - an absent key reads as its default, as
`docs/adr/0001-block-document-schema.md:550-551` puts it for the envelope's own
optional key - and
`donedata_type/1` is a new optional callback that no shipped type exports.
A document declaring neither is every document that exists today.

**The environment entry changes for every `core.map` that writes `collect`,
declared or not.** Decision 5's envelope replaces ADR-0011 decision 12's
`{:list, :unknown}` on documents that declare nothing as well as on documents
that declare something, because the envelope is what the shipped handler
writes and the constant was only ever a statement about what this package had
not looked at. A consumer that read `{:list, :unknown}` and branched on it -
the editor's expression surface is the one that exists - reads a list of a
shape instead, which is more information and not different information. No
compiled bytes move with it.

**This record cannot be built before the typed-shapes theme.** Decision 5's
entry is unspellable until `type_expr()` admits an inline shape (`sb-myt1`,
citing `statifier_datamodel`'s amendment). That is a sequencing consequence
and not a hidden dependency: `sb-nqfd` builds this record and is ordered
behind `sb-myt1` for it. Decisions 1, 2, 3, 4 and 6 have no such constraint.

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
costs a wrong `"donedata"` member on the envelope of decision 5 rather than
wrong bytes.

**The editor renders `collect_type` as a text field, and a better control is a
follow-up.** The field's type is `:string`, so ADR-0005 decision 9's control
table gives it a single-line text input
(`docs/adr/0005-liveview-editor.md:336-349`), with no candidate list and no
advisory of its own. That is the affordance ADR-0002's `payload` field takes
under the amendment this record follows, and it is enough for a value that is
a name the author already wrote in the datamodel document. A datalist of the
declared type names - the editor offering what `Declarations.from_document/1`
found - is named here as a follow-up and is **not decided**: which control a
declared-name `:string` deserves is ADR-0005's question, and it reaches
`payload` and `collect_type` together rather than one of them alone.

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
        type: StatifierDatamodel.Types.t()
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

`core.map`'s new field, as decision 1 fixes it. `config_schema/1` returns six
entries today (`lib/statifier_blocks/core/map.ex:322-372`), so the new field is
the **sixth**, inserted after `collect` and before `on`:

```elixir
%{
  key: "collect_type",
  type: :string,
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
(`lib/statifier_blocks/compiler.ex:1421-1431`, the list itself at
`:1423-1425`; the plural `completion_finals/4` that calls it is `:1361-1374`,
with its second clause at `:1378`).

The agreement check, as a function of the two declarations rather than of the
two documents:

```elixir
@spec agrees?(StatifierDatamodel.Declarations.t(), [donedata_field()], term()) ::
        StatifierDatamodel.Types.reason()
```

- the first argument is the **parent's** declarations, because the parent's
  `collect_type` is what is being satisfied;
- the second is the child's `donedata_type/1`;
- the third is the parent's `collect_type` spelling, as stored;
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

Its `kind` is `shape` and not `record`, which is what makes decision 4's
advisory reachable at all: sd's covering step reads a record as a shape, so
the parent's expectation has to be spelled as one.

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
| the parent's compile | nothing (decision 4 is dormant) | `results` is `{:list, <envelope>}` in the environment, the envelope's `"donedata"` member `cards.chunk_result`, from `collect_type` alone |
| the editor, child loaded | the child's projection satisfies `cards.chunk_result` | `:covers` - both required fields are present as integers, so no advisory |
| the editor, after someone renames the child's `declined` field to `refused` | the same check | `{:missing, ["declined"]}` - a `:warning` on the `collect_type` field, and the parent still compiles to the same bytes |

What one element of `results` holds, on each of the three arms ADR-0009's Note
fixes:

```json
{"index": 7, "status": "completed",
 "donedata": {"authorized": 41, "declined": 3}}

{"index": 8, "status": "failed",
 "failure": {"reason": "invoke_refused", "attempts": 3, "detail": {}}}

{"index": 9, "status": "cancelled"}
```

The declared `cards.chunk_result` types the first one's `"donedata"` and
appears nowhere on the other two. A block after the `core.map` that wants the
counts reads `"status"` first, which is decision 5's table read as code.

The cost, by decision 6: a day of 400 chunks costs 400 two-integer maps in the
parent's datamodel, inside 400 envelopes, serialized on every persisted step
until the run ends. A root type that had declared the whole capture list
instead would cost 400 of those, which is the multiplication the declaration
makes visible in one file; the envelopes are there either way.

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
  `config_schema/1`'s new field (decision 4), for the typing of an element's
  `"donedata"` member (decision 5 - the element's own shape is already
  recorded by that record's Note of `:891`, and nothing here moves it), and
  for this record's decision 6 naming decision 7's multiplicand. The Note of
  2026-09-06 at `:714` names this question as that record's own open one and
  points at `sb-pg91` (`:754`); it is not that record's closing Note - six
  later Notes follow it, at `:761`, `:803`, `:860`, `:891`, `:1104` and
  `:1134`, and an amendment at `:967`. The Note at `:891` is decision 5's
  premise, and `sb-pg91` closes as folded when this record lands.
- **ADR-0011 decision 12** (`docs/adr/0011-typed-environment.md:520-535`),
  whose `{:list, :unknown}` becomes decision 5's envelope. Its sentence "whether a
  child chart may declare what its `donedata` carries is the open question this
  leaves" is answered here, and its deferred list loses that entry.

## Deferred questions, named rather than guessed

- **The inline-shape arm, split into the half this record needs and the half
  it defers.** The `type_expr()` inhabitant is **not** deferred: decision 5
  needs it, it is `sb-myt1`'s amendment to ADR-0011 decision 1, and it cites
  the inline-shape amendment to `sd-ADR-0001` rather than respelling it.
  Three things are deferred, and only `collect_type`'s own spelling is at
  stake in them: a `{:type_expr, opts}` member of ADR-0002 decision 7's
  field-type set, the editor control that renders one, and the migration of
  ADR-0002's `payload` field onto the same spelling - `sb-268w` carries the
  migration of `payload` and `collect_type` together. Those three are
  ADR-0002's and ADR-0005's decisions; none of them is made here.
- **Should `statifier_datamodel` decide a `record` against a `record`?**
  Decision 4's advisory is raised only where the parent's `collect_type` names
  a `shape`, because sd's covering step is a record read as a shape and
  nothing else
  (`deps/statifier_datamodel/lib/statifier_datamodel/types.ex:309-324`).
  Whether nominal typing should also decide two records is that package's
  question, on its own ADR-0001, and nothing here asks for it.
- **Which control a declared-name `:string` deserves.** A datalist of the
  names `Declarations.from_document/1` found would serve `collect_type` and
  ADR-0002's `payload` alike, and neither has one today. ADR-0005's question,
  named here rather than taken.
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

---

## Note (2026-09-06): `collect_type`'s field type stays `:string` until `sb-268w`

A dated Note rather than an amendment: no decision above this line moves, and
the Note records where one of them stops rather than changing what it says.

Decision 1 fixes `collect_type`'s `config_schema/1` field type as the existing
`:string`, carrying a declared **name**, and ADR-0002 decision 7's set stays
closed at eight (`lib/statifier_blocks/block_type.ex:149-157`). That is
campaign-034's ruling `RQ-034-14` a and it stands unchanged through the
campaign-SF035 rewrite of decisions 3 and 5: the envelope of decision 5 is a
fact about the environment's type expressions, not about what an author types
into a config field, and the two move independently.

`sb-268w` migrates `collect_type` and ADR-0002's `payload` together to
`{:type_expr, opts}` when the typed-shapes theme has settled the field type,
the editor control and the inhabitant; a stored string reads as the name arm
unchanged when it does. Until then a `collect_type` that wants an inline
shape has no spelling, and that is the state this record leaves.

## Note (2026-09-06): eight `block_type.ex` cites, repointed at the lines they mean

A dated Note rather than an amendment. No decision above this line moves, no
statement above this line is wrong, and nothing this record decides changes:
what is corrected is where eight citations **point**, after `sb-1c7g` grew
`lib/statifier_blocks/block_type.ex` above `palette_entry/0` (commit
`f3e737f`) while this record's own request was open. Every claim those
citations support was true when it was written and is true now; the line
numbers drifted by eleven and the sentences did not.

The correction is by addition rather than in place, which is this campaign's
term for a record on `main` - amend-by-addition, zero removed lines - and which
`ADR-0002`'s Note of this date states as the reason a known long line was left
standing (`docs/adr/0002-block-type-behaviour.md:4838-4840`). It matters twice
over here: `ADR-0002` cites **this record** by line number, at `:143-144`
(`docs/adr/0002-block-type-behaviour.md:4825-4830`), so an in-place edit above
that point would move the lines another record on `main` names. This Note sits
below everything and moves nothing.

| Where in this record | What it cites | Printed | Reads today |
|---|---|---|---|
| `:225` | the three rules `summary/1` restates | `:598-601` | `:609-612` |
| `:226` | `outcomes/1`'s stability rule | `:527-531` | `:538-542` |
| `:239` | `palette_entry/0`'s `@callback` | `:509` | `:520` |
| `:239` | `outcomes/1`'s `@callback` | `:537` | `:548` |
| `:239` | `failure_outcomes/1`'s `@callback` | `:570` | `:581` |
| `:239` | `summary/1`'s `@callback` | `:609` | `:620` |
| `:240` | the `@optional_callbacks` list | `:611-617` | `:622-628` |
| `:245` | `summary/1` as the card's second line | `:609` | `:620` |

Each was read off `main` at `7cb3d28`. The eight are one drift and not eight:
every one of them sits below `palette_entry/0`, and every one moved by the same
eleven lines.

**Four cites in this record are checked and did not move**, and they are listed
so a reader knows the table above is the whole of it: decision 7's closed
field-type set at `:136` and `:790` is still
`lib/statifier_blocks/block_type.ex:149-157`, and the eight `@callback` lines
this record names above `palette_entry/0` across `:238-239` - `:252`, `:330`,
`:338`, `:345`, `:374`, `:382`, `:389`, `:424` - are each still what they say. `sb-1c7g`'s growth was
entirely below `:424` and entirely above `:509`.

The count of declared callbacks this record states - twelve today, this
record's the thirteenth (`:234-242`) - is unchanged by the repointing, and the
`ADR-0002` Note filed with this one restates it there against the same tip.

This Note carries no `Status:` line, which is the convention for a Note in this
family, as `ADR-0002`'s Note of this date states in as many words
(`docs/adr/0002-block-type-behaviour.md:4851-4854`). The record's head status
is untouched and stays `proposed`; `sb-upv0` flips it.

Filed with `sb-jvz3`, as folded residue from `sb-57yc`; campaign-SF035.

## Note (2026-09-06): decision 1's `collect_type` is a `{:type_expr, opts}` field now, and admits the inline arm

A dated Note rather than an amendment, and this record's convention for one:
by addition, zero removed lines, no `Status:` line of its own. No decision
above this line moves. Decision 1 still says the parent declares what one
child's answer holds and that the declaration is the **parent's**; decision 4's
agreement check is still dormant; decision 5's table still types `"donedata"`
by `collect_type` and nothing else; and an absent or empty `collect_type` is
still what every stored document has. What this Note records is that the field
now has **two ways** to say the thing decision 1 always asked it to say.

**What the record deferred, and where it landed.** Decision 1 chose the name
arm and left the second one to be decided with three other things it named
together (`:148-157`): a field type that describes a shape, an inhabitant of
`StatifierBlocks.Environment`'s `type_expr()` that is one, an editor control
that renders one, and the migration of `ADR-0002`'s `payload` onto the same
spelling. All four have landed. `ADR-0002`'s Amendment of 2026-09-06 at
`docs/adr/0002-block-type-behaviour.md:4957` added `{:type_expr, opts}` as the
ninth member of decision 7's set and named this field in its clause 7 table
(`:5201-5206`); its clause 8 fixes what a stored string means (`:5214-5220`).
This Note is the half of that clause that belongs here.

**The spelling.** `collect_type` is declared `{:type_expr, %{arms: [:name,
:inline]}}` (`lib/statifier_blocks/core/map.ex:464-465`). The name arm is a
JSON string, resolved through `StatifierDatamodel.Types.parse/2` exactly as
decision 1 wrote it. The inline arm is a JSON list of `"name"` / `"type"` /
`"required?"` objects, read into `{:shape, members}` by
`StatifierBlocks.Environment.inline_shape/1`
(`lib/statifier_blocks/environment.ex:522-529`). The two are told apart by the
stored JSON type alone: a string is never a member list, and no tag key is
read.

**Decision 5's table is unchanged and gains a reading.** `"donedata"` is still
typed by this block's `collect_type` and by nothing else, and still `unknown`
when there is none. What the second arm adds is that the type it carries may
now be a shape written where the field is rather than a name looked up
elsewhere - the envelope is a shape either way, and an inline `collect_type` is
simply a shape one level inside another
(`lib/statifier_blocks/core/map.ex:406-422`).

**Decision 1's "no findings of its own" holds, with the same care.**
`Types.parse/2` is total over any spelling and
`Environment.inline_shape/1` is total over any list, so neither arm produces a
finding this module could write. What is left - bytes that are neither arm -
is refused once, by the shared check every `{:type_expr, opts}` field consults
(`StatifierBlocks.BlockType.type_expr_findings/2`,
`lib/statifier_blocks/block_type.ex:980`), rather than by a clause this block
type re-implements. That is a check on the field's **value**, not on what the
name resolves to: a name the datamodel document does not declare is still not a
finding, which is the permissiveness decision 1 chose and this Note does not
narrow.

**Decision 4's dormant check reads the arm the parent wrote.** `agrees?/3`
takes the `collect_type` spelling as stored, so it now reads a member list into
an inline shape before asking `statifier_datamodel`'s read check
(`lib/statifier_blocks/block_type.ex:885-917`). Nothing else about the check
moves: it is still not a compile finding, still changes no compiled byte, and
still answers only where both documents are genuinely in hand. The consequence
decision 4 records - that the covering step answers `:covers` only against a
`shape`, so a `collect_type` naming a `record` is `:not_assignable` whatever
the child declares - now has a second reading beside it: an inline
`collect_type` **is** a shape, so it covers where a name of kind `record` could
not.

**No stored document changes, and no byte moves.** A `collect_type` holding
text is the name arm: the same bytes, the same resolution, the same findings.
`ADR-0001`'s `schema_version` stays at `1`, no `migrate_config/2` is called for
the field, and the field still produces no compiled output at all - which
`StatifierBlocks.Core.TypeExprMigrationTest` asserts byte for byte, beside the
corpus `StatifierBlocks.Compiler.ByteCorpusTest` pins against goldens captured
before any of this.

The record's head status is untouched and stays `proposed`; the flip is its
own gated request.

Filed with `sb-268w`, campaign SF035's Lane A.
