# ADR-0011: Nothing flows between adjacent blocks - a pre-order walk carries an environment from datamodel path to type, and a block declares what it reads and writes there

Status: accepted (2026-09-06, drafted for `sb-kcdw` under the operator's
campaign-032 grant). It merges at proposed under that campaign's invariant,
like every other section filed with it; flipping it to accepted is a separate
request through the same `docs/adr/` gate, and `sb-ok9s` carries it.

[Note 2026-09-06, `sb-ok9s`: the paragraph above is the record as it was
drafted, and it is left standing rather than rewritten. The status word is
now `accepted`; this is the separate request that sentence points at, and
the Note at the foot of this record carries what the flip verified.]

## Context

ADR-0003 answered the question ADR-0002 handed it - which block types may
appear in which slots - with two mechanisms rather than one. Kind tags decide
the structural half, and they have held: `:step`, `:interrupt_handler` and
`:draft_shelf` are declared on both sides of every placement and compared by
intersection, and nothing below disturbs them. The data-flow half is the one
this record reopens. It is decision 4's seam: "adjacency within a slot is
sequencing, so the data-flow question at position `{parent, slot, index}` is a
question about the block at `index - 1`", with the block at `index - 1`
handing a `produces` type to the block at `index` through its `consumes`.

**The seam describes a hand-off the package does not emit and the engine does
not have.** Every value a shipped `core.*` block produces is written to a
datamodel path, by name, and every value one reads is read from a datamodel
path, by name. `core.assign` writes its `path`
(`lib/statifier_blocks/core/assign.ex:73-79`). `core.subchart` writes
`assign_to`, a `{:path, %{}}` field since `sb-2ym4`
(`lib/statifier_blocks/core/subchart.ex:250-256`). `core.map`
writes `collect`, and its own record says the block's outcome "says only
whether the fan-out as a whole succeeded" so a reader takes "the collected
list with a `core.branch` after the block"
(`lib/statifier_blocks/core/map.ex:68-70`). `core.on_event`'s `capture` writes
one datamodel path per pair, on the interrupt transition
(ADR-0002's Note of 2026-09-05). The compiled SCXML carries `<assign>`
elements and `<data>` roots; it carries no channel from one state to the next
along which a `produces` could travel. An author who puts a step after
`core.assign` and reads what it wrote is not reading the previous block's
output. They are reading a path.

Three things have shipped since ADR-0003 that make the alternative cheap
rather than speculative.

**The path became a field type.** ADR-0002's amendment of 2026-09-05 gave
decision 7's closed field-type set an eighth member, `{:path, opts}`, and was
explicit that `opts` "carries no defined key today ... so that what a control
needs can arrive without widening the set a second time". A read signature and
a write signature are exactly what a consumer needs and exactly what that
tuple was left open for.

**The declared-path set became a real set with real types.** ADR-0006 gave the
datamodel document three scopes of typed entries and one total projection to
the declared paths; ADR-0005's 11k made that set the union of three
declarations; ADR-0005 clause 11e already turns a path outside the set into an
`:info` finding. So the editor and the compiler already agree on which paths
exist and what scalar type each one holds. What neither could say is what a
path holds *at a position in the document*, which is the only question a
data-flow check was ever asking.

**The document moved, and grew a `types` key.** `statifier_datamodel`'s
`sd-ADR-0001` re-homes ADR-0006's document, adds `date` to the scalar set
(nine, not eight), and adds a fourth top-level key, `types`: named `record` and
`shape` declarations with ordered, typed fields. Its decision 8 defines one
read check over them - nominal identity, plus a record satisfying a shape when
its fields cover the shape's required set - and says in as many words that
there is "no record-into-record structural widening, no union, no inference,
and no fifth step". That is a relation this package can consume without owning
one, which is what ADR-0003's second force ("this package must not grow a type
system") asked for and could not get in 2026-08.

**What this record has to answer**, and nothing wider: what the data-flow
check is a check *on* now that the seam is gone; what carries the answer
through a document; what a read and a write are declared with; what a
disagreement between two arms of a branch means; what severity an unsatisfied
read has; what happens to `consumes` and `produces`; and where the answer is
rendered. It builds nothing here: there are no `lib/` changes in this record's
own pull request, and the beads named throughout are what build it.

## What this record supersedes, and what it leaves standing

This record **supersedes five of ADR-0003's nine decisions**, by name and
number, and the supersession is stated here rather than by editing that
record. Nothing above ADR-0003's own text is removed; a dated Note there
points at this record and says which decisions it reaches.

| Superseded | ADR-0003's heading, verbatim |
|---|---|
| decision 1 | "A type expression is an opaque string, and the default relation is string identity." |
| decision 2 | "`io(config)` returns one map with three keys, and it is the whole declaration surface." |
| decision 4 | "Data-flow assignability runs on the seam between adjacent siblings, and inbound type is computed by walking, never stored." |
| decision 5 | "`:unknown` is permissive, in both positions." |
| decision 6 | "Widening is a host-supplied module on the palette, and it can only widen." |

Four of ADR-0003's decisions **stand exactly as written** and are named so
that nobody has to check. Decision 3, kind tags and `slot_accepts`, is
untouched in every clause, and so are the two amendments that extend it - the
2026-08-29 reason vocabulary on decision 8 (which decision 8 below adds one arm
to rather than rewriting) and the 2026-08-31 `:draft_shelf` amendment, whose A2
"the data-flow walk does not enter the shelf" is carried forward by decision 1
below with the shelf's fragments starting from an empty environment instead of
from `:unknown`. Decision 7's local/global split between the editor's
per-edit question and validation's whole-document authority stands, though
decision 1 below changes which set of positions "local" covers. Decision 8's
finding standing is unchanged and its `{:kind_not_admitted, ...}` tuple gains
no member; its `{:type_mismatch, ...}` tuple gains one, the path the read was
checked at, per decision 8 below. Decision 9's three deferrals stand.

The superseded decisions are not all superseded in the same direction, and it
is worth saying which is which before the decisions below. Decisions 1 and 5
are superseded by **relocation**: opaque-string identity and permissive
`:unknown` are both still the rule, but they are `sd-ADR-0001` decision 8's
rule now, defined once in the package that owns the document rather than here.
Decision 2 is superseded by **replacement**: `io/1` keeps its map and its
optionality, and two of its three keys change meaning. Decision 4 is superseded
by **replacement**: the seam is not where the question lives. Decision 6 is
superseded by **narrowing**: the host relation survives, and it runs last.

Four records are **amended by dated Note, additively, with no line removed**,
and each Note points here rather than restating a decision:

- **ADR-0006**, whose document this record now reads through `sd-ADR-0001`:
  the `types` key, the optional `required?` on a field, and `date` in the
  scalar set.
- **ADR-0002 decision 7**, whose `{:path, opts}` gains its first two keys,
  `expects` and `writes`, plus the `field_candidates` feed beside them.
- **ADR-0005**, for decision 9 below (declared labels in findings, and the
  environment on the Datamodel tab) and for the stale "seven field types"
  count its 2026-09-05 duration amendment's consequences still carry.
- **ADR-0009**, for decision 11 below, which decides two of the four fields
  its 2026-09-05 decision-4 Note deferred and leaves the other two deferred
  with a reason.

## Decision

### 1. The environment is a map from datamodel path to type, and the walk is pre-order

The data-flow check runs over one value, the **environment**: a map from a
datamodel path (the absolute dotted string `sd-ADR-0001` decision 7's
projection produces) to a type. A **type** is one of the nine scalars, the
`name` of a `record` or `shape` declaration, `{:list, type}`, or `:unknown`.
There is no other inhabitant, and this package mints none: every one of them
comes from the datamodel document or from a block's own declaration.

Validation walks the document **in pre-order** - `Document.blocks/1`'s order,
which is already the order ADR-0003's own seam listing used - carrying the
environment forward:

- the environment enters the root as the **seed** (decision 2);
- a block's **write signature** puts an entry, replacing whatever the path
  held;
- a block's **read signature** is checked against the environment *at the
  block's position*, before that block's own writes are applied;
- a container's slots each start from the environment as it reaches the
  container, and what they contribute is merged (decision 4) when the
  container's children are done;
- the walk does not enter a `core.drafts` shelf, per ADR-0003's 2026-08-31
  amendment A2, and each parked fragment is walked separately from an **empty**
  environment - the shelf's own rule, restated in this record's vocabulary:
  a fragment reads nothing as known because nothing put it there.

Three properties follow and each is the reason for a phrasing above. The walk
is **one pass, pure, and IO-free**, which is what ADR-0003's first force
demanded and what keeps the editor's pre-hover marking computable on mousedown.
The environment is **not stored in the document** - ADR-0003 decision 4 was
right about that and the reason is unchanged, it is a property of where the
document runs and not of the document. And a path is **last-write-wins by
position**, not accumulated: two blocks writing `cards.settlement` do not
produce a union, the second one's type is what the third block reads, which is
the same thing the compiled `<assign>` elements do at run time.

`:unknown` stays permissive in both directions, exactly as ADR-0003 decision 5
had it and for its adoption-curve reason, but the rule is now
`sd-ADR-0001` decision 8's first step rather than this record's own.

### 2. What seeds, what writes, what reads

**The seed** is the environment the root's first block sees. It comes from the
document's **entry block**: the first block of the root's `body` slot, when
its palette entry declares a subject (decision 6). The entry block's write
signature is applied before the walk begins, so the document opens with its
subject path holding its subject type and nothing else. A document whose first
block declares no subject seeds an empty environment, and every read in it is
a read of a path the environment does not hold - which decision 5 makes an
`:info` and not an error, so an untyped document validates exactly as it does
today.

**A write signature** is any of:

- a `{:path, %{writes: T}}` field: the block writes `T` at the path the
  field's value names;
- a `{:path, opts}` field with no `writes` key, and a `:string` field carrying
  `datamodel_path?: true`: the block writes `:unknown` at that path. The path
  becomes *known* without becoming *typed*, which is the honest reading of a
  declaration that says where but not what;
- `core.on_event`'s `capture`, one write per pair, at the pair's key.

**A read signature** is a `{:path, %{expects: T}}` field: the block reads the
path the field's value names and requires the environment to satisfy `T`
there.

Both signatures are declared on the field, not on the block, for the reason
ADR-0002 decision 7 gives for everything else on a field declaration: the
finding anchors on the field's `key` (ADR-0005 decision 11), so an author is
sent to the control they have to change rather than to a card. A block with
three path fields has three signatures, and they are independent.

`sb-xk1h` builds the two keys and `sb-u7zt` declares them across the `core.*`
vocabulary; `sb-v5a3` builds the walk.

### 3. The read check is `sd-ADR-0001` decision 8's, and this package defines no second one

Given a type `held` in the environment at a path and a type `expected` by a
read signature, the verdict is `StatifierDatamodel`'s `satisfies?/3`, decided
in that record's order:

1. either side unknown -> satisfied;
2. identity -> satisfied (the same declared name, the same scalar, or the same
   opaque string);
3. `held` names a `record` and `expected` names a `shape` -> satisfied when
   the record has a field of the same `name` for **every** field of the shape
   with `required?: true`, whose type satisfies the shape field's type under
   the same check;
4. otherwise -> not satisfied, and then and only then the palette's host
   relation (decision 6's survivor) is asked;
5. still not satisfied -> refused.

**Identity is nominal.** Two records with identical fields are two records. A
record is never read as another record by structure, there is no union, no
least-upper-bound, no inference beyond the four steps above, and no runtime
enforcement of any of it - the check is an authoring-time relation exactly as
ADR-0003 decision 9's first bullet said, and no SCXML carries a type.

**This package defines no `Compatibility` or `Coverage` module of its own.**
`sd-ADR-0001` decisions 9, 10 and 11 already define `breaks/2` (how a
redefinition narrows), `missing/3` (which required fields a map leaves
unfilled) and `path_types/1` (value kinds for an expression editor). A second
implementation here would be the divergence ADR-0003 decision 7's
one-function argument exists to prevent, one package boundary further out.
This package **calls** them; `sb-jzg1` takes the dependency and deletes the
document index and datamodel arms that moved.

**The host relation survives, narrowed.** ADR-0003 decision 6 put a widening
module on the palette and made the single most important property in that
record the fact that the host is consulted only after identity has failed, so
it can only widen and never narrow. That property is kept and the ordering is
strengthened: the host runs **last**, after step 3's record-into-shape
coverage as well as after identity. So the floor a host cannot lower is now a
higher floor than it was, monotonicity in the callback still holds, a buggy
host relation still degrades to extra permissiveness, and removing the module
still cannot invalidate a stored document. What is superseded in decision 6 is
its four-step order and its framing of the relation as the *only* widening
there is; what stands is every consequence that order was there to buy.

### 4. Arms merge per path by agreement, and there is nothing else

A `core.branch`'s arms, a `core.parallel`'s lanes, and any host container with
more than one slot in the flow each start from the environment that reached
the container and produce their own environment. What leaves the container is
the **per-path merge**:

- a path all arms hold at the same type keeps that type;
- a path some arms hold and others do not, or hold at a different type, is
  **`:unknown`**;
- a path no arm holds is absent, as it was.

An arm holding a path at `:unknown` agrees with nothing and disagrees with
nothing: the path drops to `:unknown`, which is what the second bullet already
says and is called out because it is the case a reader will check.

**That is the whole merge.** There is no join, no union, no least-upper-bound,
and no widening at a merge - the same refusal ADR-0003 decision 4 made for the
same reason, arriving at the same answer by a different route. ADR-0003 got
there by declaring `produces: :unknown` on the container; this record gets
there per path, which is strictly more information: a branch whose arms both
leave `cards.credit_txn` alone no longer blanks it out for everything
downstream, and a branch where one arm rewrites the subject drops that one
path and keeps the rest. That improvement is the practical reason this record
exists at all, and it is bought with no lattice.

[Note 2026-09-06, `sb-qrcn`: `ADR-0012` gives `core.branch` a third slot,
`undecided`, taken when an arm's condition produces predicator's `:undefined`
sentinel rather than `true` or `false`. That slot is one of the arms this
section speaks of, and this paragraph already answers what its environment is:
it starts from the environment that reached the container, and it leaves
through the per-path merge like every other arm. A condition that did not
decide says nothing about what any path holds, so nothing is added at the arm
and nothing here changes. A dated note rather than an amendment: no decision
above moves, and `ADR-0012` is proposed rather than accepted.]

Ordering inside a `core.parallel` is deliberately not modelled. Lanes are
concurrent; two lanes writing the same path is a document the author should
not have written, and the merge's answer for it - `:unknown` when they
disagree, the agreed type when they do not - is the only answer that does not
require this package to decide which lane ran second. Whether that shape is
worth an advisory is ADR-0005's findings layer's question and is named in the
deferred list.

### 5. An unsatisfied read is a validation `:error`; a path the environment does not hold stays an `:info`

Two failures look alike to an author and are not alike, and this record gives
them different severities on purpose.

**An unsatisfied read is a validation `:error`**, with the standing ADR-0003
decision 8 gave `{:type_mismatch, ...}`: the document still decodes (ADR-0001
decision 9) and still resolves, and it fails validation with the offending
block and field named. Somebody made two claims that cannot both be true - a
write said this path holds a card transaction, a read said it wants a
settleable thing, and the declarations say the first does not cover the second.
Nothing about that is advisory.

**A read of a path the environment does not hold stays the ADR-0005 clause 11e
`:info` advisory**, unchanged in severity, in wording, and in what feeds it.
Nobody has contradicted anybody: a host may simply not have declared the path
yet, which is 11f's own argument - the advisory is grounded in a claim somebody
actually made, and silence is not a claim. This is also what keeps the
adoption curve ADR-0003 decision 5 protected: a document whose palette declares
nothing produces no errors, only the advisories it already produced today.

The two are also produced at different times by different code, and that is
worth stating because it is what makes the split implementable: 11e's advisory
is about a path being outside the *declared set*, which is a document-wide
question the editor already answers; an unsatisfied read is about the
environment at a *position*, which only the walk knows.

### 6. `consumes` and `produces` become sugar over the subject path, which `palette_entry/0` names

ADR-0003 decision 2's `io/1` map keeps its shape, its optionality and its
purity. `kinds` and `slot_accepts` are untouched in every particular. The other
two keys change meaning:

**`consumes: T` is read as a read signature at the subject path. `produces: T`
is read as a write signature at the subject path.** They desugar before the
walk runs, and a block declaring both is a block that reads the subject and
then rewrites it, which is what a step in a pipeline is.

**The subject path is named by a `subject:` key on `palette_entry/0`**,
optional and additive. It is the second key on that map whose subject is the
document rather than the card - `singleton` (ADR-0005 clause 10z) is the first,
and it is the precedent this one follows. The key is read from the **entry
block's** palette entry: the first block of the root's `body` slot, whose
palette entry names the path the document's subject lives at.

**A document with no entry block has no subject, and the sugar is inert.** No
subject path means `consumes` and `produces` desugar to nothing at all - not to
a read of `nil`, not to a write at `""`, and not to a finding. A palette that
uses the sugar in a document that has no entry block is quiet, which is the
same permissive default `io/1` has had since ADR-0003 and the reason the sugar
can be shipped without migrating a single existing palette.

Why sugar rather than deletion. Every `consumes`/`produces` declaration written
against ADR-0003 says something true about the block that carries it, and in a
one-subject document - which is what the card-processing and signup documents
are - the seam reading and the subject-path reading give the same verdict for
every seam. Deleting the keys would throw away a correct declaration to make a
point about a mechanism. Desugaring keeps the declaration and moves what it is
a claim *about*.

### 7. The document's declaration table

A consumer of this record reads the declaration shape from `sd-ADR-0001`
decision 5, not from a paraphrase. It is reproduced here because this record's
decision 3 turns on the exact fields, and a reader should not have to open two
repositories to check one.

A **declaration** carries:

| Key | Required | Meaning |
|---|---|---|
| `name` | yes | the declared name, unique across the list; a dotted string is admitted (`cards.credit_txn`) and carries no path meaning |
| `kind` | yes | `record` or `shape` |
| `label` | yes | the human-readable name a pane renders |
| `fields` | yes | an ordered list of field maps |
| `note` | no | prose for a reader; carries no contract |

A **field** carries `name` (unique among its siblings), `type`, and the
optional boolean `required?` (default `false`), plus optional `label`, `note`
and `one_of`. A field's `type` is one of the nine scalars or the `name` of
another declaration; a `list` field carries `item_type` under the same rule.
Declarations may reference each other, and a reference to a name the list does
not declare normalizes to unknown rather than failing admission.

The nine types are `string`, `integer`, `decimal`, `boolean`, `datetime`,
`duration`, `date`, `object`, `list`. `date` is the widening `sd-ADR-0001`
decision 4 made over ADR-0006's eight, and it is a distinct type rather than a
`datetime` because the expression language distinguishes them.

Two properties of that table this record depends on. `types` **contributes no
paths** (`sd-ADR-0001` decision 7): a declared name is not a path and a
declaration's field is not a path, so nothing here widens the set ADR-0005
clause 11e reads. And a declaration is admitted by a **total normalizer**: a
half-written declaration declares nothing rather than raising, so a walk over a
document with a broken `types` list produces `:unknown` and not an exception.

### 8. `:shape_not_satisfied` joins the reason vocabulary, beside `:not_assignable`

ADR-0003's 2026-08-29 amendment gave a seam five reason arms explaining *how*
it came out, distinct from *whether*. The vocabulary survives this record and
gains **one arm**:

- **`:shape_not_satisfied`** - the environment holds a record at the path, the
  read expects a shape, and the record does not cover the shape's required
  set. `sd-ADR-0001` decision 8's `satisfies/3` returns `{:missing, [names]}`
  for exactly this case, and the arm carries those names so a message can say
  which required fields are absent without re-deriving them.

`:not_assignable` keeps its meaning for every other refusal - both sides typed,
identity failed, coverage did not apply or did not hold, and the host relation
did not widen. `:source_untyped`, `:target_untyped` and `:both_untyped` keep
theirs, read against the environment's entry rather than a sibling's
`produces`. `{:fixable_by, block_id}` keeps its: the block whose write
signature put the offending type at the path is the declaration an author would
change, and under this record that block is findable by name rather than by
adjacency, which makes the arm more useful than it was.

ADR-0003 decision 8's `{:kind_not_admitted, ...}` tuple is unchanged.
`{:type_mismatch, block_id, upstream_ref, produced, consumed}` is the tuple an
unsatisfied read produces, with `upstream_ref` naming the block whose write
signature the read disagrees with, or `:slot_entry` when the seed is what it
disagrees with - and it **gains one member, the datamodel path the read was
checked at**.

The path is added rather than left to be re-derived because under this record
it cannot be re-derived. Decision 8's tuple was complete when a seam was a pair
of adjacent blocks and the disagreement was about the seam itself; the same
disagreement is now about a named path, a block may carry several read
signatures on several paths, and a message that says which two types
disagreed without saying where is a message an author cannot act on. It is the
one member the tuple gains, and `{:kind_not_admitted, ...}` gains none: a
structural refusal is about a slot and has no path to name.

### 9. The environment reaches the author in two places, and both are ADR-0005's to shape

This record fixes what the environment makes available; how it is drawn stays
ADR-0005's, and `sb-sy0q` builds both surfaces.

**Findings carry the declared label.** A finding about a path names the
declaration's `label` - the human-readable name a pane renders, required on
every declaration and on every entry - rather than only the dotted path, so an
author reads "the settlement step wants a Settleable" instead of a path they
have to look up.

**The Datamodel tab lists the environment at the selected block.** The drawer's
fifth package tab, `:datamodel` (`lib/statifier_blocks/shell.ex:175`), is
today a read-only view over the datamodel document. It gains the answer to
"what is known here": the paths the environment holds at the selected block's
position, with their types. That is the one question the tab could not answer
before this record, because before this record nothing computed a per-position
answer.

Neither surface changes a verdict, and neither produces a finding of its own.

### 10. `core.on_event`'s capture is authored as a repeated two-control row, and its targets are write signatures

ADR-0002's Note of 2026-09-05 gave `core.on_event` an optional `capture` map -
key a datamodel path written, value a path inside `_event.data` read - and
recorded that `config_schema/1` declares **no field** for it, because decision
7's field-type set has no member describing a map. It left the authoring
surface open. This record closes it, and closes the two consequences that
followed it.

**The control is a repeated two-control row**, one row per pair: a
`{:path, opts}` control for the target and a source-path control for the
`_event.data` key. It is not a new field type. A map field type would be a
member of decision 7's closed set whose whole content is a spelling of a
repetition the schema can already express, and the closed set exists so the
editor can draw every member - a map is the member it draws worst.

**The source control's candidates come from `fixtures/0`.** ADR-0005's Note of
2026-09-05 on decision 9 already makes a fixture value the hint drawn beside a
field. A handler's fixture payload is the only place in the package that knows
what an event of that name actually carries, so it is where a source-key
candidate list comes from. With no fixture, there are no candidates and the
control is a plain text input, which is what the `{:path, opts}` amendment
already says about a path control with no datamodel.

**A capture's target paths are write signatures** (decision 2), which closes
the third gap: those paths reach ADR-0005 clause 11e's declared-path advisory
through the same mechanism as every other datamodel path, rather than being
invisible to the pass that covers all the others. They are written on the
interrupt path, so a block after the group sees them - the handler fired or it
did not, and a path only one arm of that choice holds is `:unknown` by decision
4, which is the correct answer and not a special case.

`sb-xk1h` builds the control and the advisory visibility.

### 11. `core.map` keeps `item_as` and `index_as`; `max_concurrency` and `params` stay deferred

ADR-0009's Note of 2026-09-05 on decision 4 deferred four declared fields
rather than dropping them, and said each is "still live" with "somewhere it
would be decided". Two of them are decided here, because the walk is what
needed them; two are not, and the reason each is not is recorded rather than
left implicit.

**`item_as` and `index_as` are kept, with the defaults `item` and `index`.**
They are the names a child sees its item and its position under, and under this
record they are the names the **walk binds inside the fan-out body**: a block
in the body that reads `item` is reading a path the environment holds, put
there by the fan-out rather than by any block. Without them the body has no
vocabulary for the thing it is iterating over, and a walk that cannot name the
item cannot check a single read inside a fan-out body. That is the "somewhere
it would be decided" the Note pointed at, and this is it.

**`max_concurrency` stays deferred**, on its own Note's argument sharpened by
what has since landed: the scheduler honours no hint below the queue bound, so
a block-level field would be a hint to a runtime that already has the number.
A field that cannot change an outcome is a field an author would reasonably
expect to change one.

**`params` stays deferred**, and this record adds a reason its Note did not
have: a `params` member sends literal values to every child, and this record
makes the values a handler reads path-literals. Two spellings of "what the
child gets", one by path and one by value, in one declaration surface, is a
collision worth deciding on purpose rather than by shipping.

Neither is dropped here. Dropping either is still a decision about ADR-0009's
declaration surface and still that record's to make.

### 12. `core.map`'s `collect` is a list whose items are unknown

`core.map` writes `collect` (decision 2's rule for a `{:path, %{writes: T}}`
field), and the `T` it writes is `{:list, :unknown}`: the assembled answer is a
list, dense and in item-index order per ADR-0009 decision 5, and this record
says nothing about what one element of it holds.

It says nothing because the shipped child recipe emits the outcome name and
nothing else, so a declared item type would be a claim about bytes that are not
there. A block after a `core.map` therefore knows it is looking at a list -
which is more than it knew before this record - and knows nothing about an
element, which is exactly true.

**Whether a child chart may declare what its `donedata` carries is the open
question this leaves**, and it is named in the deferred list below rather than
answered. `sb-u7zt` types `collect` as this decision states it.

### 13. `core.subchart`'s `assign_to` admits a dotted path

`core.subchart`'s `assign_to` migrated to `{:path, %{}}`
(`lib/statifier_blocks/core/subchart.ex:250-256`) and now offers dotted
datamodel paths as candidates, while `check_assign_to/2` still refuses anything
that is not a bare lowercase identifier
(`lib/statifier_blocks/core/subchart.ex:291-300`). A control that offers what
its own validation refuses is a defect either way round, so which way to fix it
is a decision rather than a repair.

**It is resolved by admitting the dotted path: the validation widens to match
the candidates the field already offers.** The evidence is this package's own
emission. ADR-0002's G5 row records what `core.subchart` declares and G5a
hands the emitted bytes to ADR-0004; neither states a constraint on what an
`<assign>` location may be: the bare-identifier rule is
`Config.identifier?/1`'s (`lib/statifier_blocks/core/config.ex:37`), reached
for this field by `check_assign_to/2` (`:291-300`) and by the emission's own
`assign/1` (`:604-618`). Meanwhile `core.assign` - the type whose entire job
is writing one datamodel path - accepts any non-empty path with no whitespace
(`lib/statifier_blocks/core/assign.ex:96-102`), emits it verbatim as
`<assign location="...">`, and its own moduledoc's worked example is a dotted
location (`:146`). A subchart's outcome is written by the same element to the
same datamodel, so one of the two rules is wrong, and it is not the one with
the dotted example in it.

The widening reaches **both** of those sites in `core/subchart.ex` and not
one: the emission repeats the refusal because `emit/2` has to answer for a
config `validate_config/1` would have rejected. `sb-xk1h` implements both, and
the candidates and the validation agree afterwards.

**It reaches nothing else, and the rest is named rather than swept up.** The
identical `defp assign(location)` refusal on an `<assign>` location stands
unchanged in `core.invoke` (`lib/statifier_blocks/core/invoke.ex:299`) and in
`StatifierBlocks.InvokeStep` (`lib/statifier_blocks/invoke_step.ex:430`), and
`core.map`'s `collect` carries its own
(`lib/statifier_blocks/core/map.ex:188`, `:300-308`), and `collect`'s emission
is ADR-0009's rather than this decision's. This decision was ruled about
`core.subchart`'s `assign_to`, and widening three more fields on the strength
of one field's argument is the sweep a record should not make by implication.
Whether the four should agree is in the deferred list, so that the next reader
finds it named rather than finds it by hitting it.

### 14. No cardinality on a seam

A list at a path is the datamodel document's own `list`, declared with its
`item_type` there. Nothing in this record puts a cardinality on a read or a
write: there is no "expects many", no "produces one per item", and no arity
relation between two blocks. A block that writes a list writes `{:list, T}` at
a path, and a block that reads it declares `{:list, T}` and is checked by the
same `satisfies?/3` as everything else.

This is stated because a flow-sensitive walk over a fan-out is exactly where a
cardinality seam would be reinvented, and reinventing it is the type system
ADR-0003's second force refused, arriving by the back door.

## Worked shape

One card-processing document, in the canonical domain. The datamodel document
declares two paths and, under `types`, two records and one shape. It carries
`scopes` because `sd-ADR-0001` decision 6's `index/1` admits a map carrying a
list under `"scopes"` and returns `nil` for anything else - a document that
declared only `types` would not be a document:

```json
{
  "version": 1,
  "scopes": [
    {"scope": "global", "label": "Global", "entries": []},
    {
      "scope": "local",
      "label": "This run",
      "entries": [
        {"name": "current_txn", "path": "cards.current_txn", "type": "object", "label": "Current transaction"},
        {"name": "settlement", "path": "cards.settlement", "type": "object", "label": "Settlement"}
      ]
    },
    {"scope": "event", "label": "Event", "entries": []}
  ],
  "types": [
    {
      "name": "cards.credit_txn",
      "kind": "record",
      "label": "Credit card transaction",
      "fields": [
        {"name": "amount_minor", "type": "integer", "required?": true},
        {"name": "currency", "type": "string", "required?": true},
        {"name": "authorized_at", "type": "datetime"},
        {"name": "expires_on", "type": "date"}
      ]
    },
    {
      "name": "cards.settlement",
      "kind": "record",
      "label": "Settlement",
      "fields": [
        {"name": "amount_minor", "type": "integer", "required?": true},
        {"name": "currency", "type": "string", "required?": true},
        {"name": "settled_on", "type": "date", "required?": true}
      ]
    },
    {
      "name": "Settleable",
      "kind": "shape",
      "label": "Settleable",
      "fields": [
        {"name": "amount_minor", "type": "integer", "required?": true},
        {"name": "currency", "type": "string", "required?": true}
      ]
    }
  ]
}
```

The two artifacts say different things about the same path and that is the
point. The `scopes` entry says `cards.current_txn` **exists**, which is what
ADR-0005 clause 11e's advisory reads and all it reads; its `type` there is the
scalar `object`, because `sd-ADR-0001` decision 6 normalizes an entry `type`
outside the closed nine to `nil`. The **environment's** type at that path comes
from a block's declaration, not from the entry: the document's entry block's
palette entry declares `subject: "cards.current_txn"` and its `io/1` declares
`produces: "cards.credit_txn"`. So the seed is:

    %{"cards.current_txn" => "cards.credit_txn"}

Then, in order:

1. **`core.assign`** writing `cards.current_txn.authorized_at`. Its `path`
   field is a `:string` carrying `datamodel_path?: true`
   (`lib/statifier_blocks/core/assign.ex:73-79`), which decision 2 reads
   exactly as a `{:path, opts}` with no `writes` key: the environment gains
   that path at `:unknown` - known, untyped - and nothing is refused.
2. **A settle step**, a host block type whose `subject` field is
   `{:path, %{expects: "Settleable"}}` pointing at `cards.current_txn`. The
   environment holds `cards.credit_txn` there; the read check reaches step 3;
   `cards.credit_txn` has `amount_minor` and `currency`, which is the whole of
   `Settleable`'s required set. **Satisfied by coverage**, and the host
   relation is never asked. The step's `assign_to` is
   `{:path, %{writes: "cards.settlement"}}` at `cards.settlement`, so that path
   is now typed.
3. **A `core.branch` whose arms agree.** One arm posts a receipt, the other
   sends a notification; neither writes `cards.current_txn`. Both arms leave
   the path at `cards.credit_txn`, the merge keeps it, and a step after the
   branch that expects `Settleable` still passes. Under ADR-0003 decision 4
   this block would have produced `:unknown` and everything downstream would
   have been unchecked.
4. **A `core.branch` where one arm rewrites the subject.** A retry arm assigns
   a fresh `cards.credit_txn` and a fallback arm writes a
   `cards.settlement` there instead. The two arms disagree at
   `cards.current_txn`, the merge drops it to `:unknown`, and a step after the
   branch expecting `Settleable` is **satisfied by step 1 of the read check**
   and refuses nothing. That is decision 3's permissiveness doing its job:
   the walk lost information and says so by being quiet, rather than by
   guessing.

Two refusals for contrast. A step expecting `Settleable` at a path the
environment holds as `string` is `{:type_mismatch, ...}` with reason
`:not_assignable`, a validation `:error`. A step expecting a shape whose
required set includes `settled_on` at a path holding `cards.credit_txn` is the
same tuple with reason `:shape_not_satisfied` carrying `{:missing,
["settled_on"]}`. A step reading `signup.email` in a document that never wrote
it, in a palette whose datamodel never declared it, is ADR-0005 clause 11e's
`:info` and nothing else.

## Consequences

- **A typed pipeline survives a branch.** This is the practical gain and it is
  the reason to take the record: ADR-0003's containers blanked everything
  downstream to `:unknown`, and a per-path merge blanks only the paths the arms
  actually disagree about. A document whose branches leave the subject alone
  stays checked to its last block.
- **A document whose palette declares nothing behaves exactly as it does
  today.** Every signature is optional, the seed of a subject-less document is
  empty, `:unknown` is permissive both ways, and an unheld path is an `:info`.
  There is no version bump, no migration, and no document in existence that
  validates differently on the day the walk ships without a palette declaring
  something first.
- **The verdict set grows in one direction only.** Errors are new refusals of
  reads that were previously unchecked, never new acceptances: nothing this
  record admits was refused before. A host adopting signatures one palette
  entry at a time gets strictly more checking with each one, which is ADR-0003
  decision 5's adoption curve unchanged.
- **This package takes a dependency it did not have.** `sb-jzg1` adds
  `statifier_datamodel`, deletes the moved document index and the datamodel
  arms, and `sb-i9sx` re-pins it once that package publishes. The direction is
  one-way by construction: `statifier_datamodel` depends on nothing in the
  family.
- **`StatifierDatamodel.Declarations` and `StatifierBlocks.Declarations` are
  two different things and neither is renamed.** The one here is the
  declarations panel's arithmetic over the block document's own `datamodel`
  key (ADR-0005's amendment of 2026-09-01); the one there is the datamodel
  document's `types` list. Cite either in full; a bare "Declarations" in this
  package's prose means this package's.
- **A partially typed palette still permits what a fully typed one would
  catch**, exactly as ADR-0003's consequences said, and for the same reason.
  What changes is that the untyped part is now visible: the Datamodel tab shows
  a path at `:unknown` where a typed palette would have shown a name.
- **Five records carry a dated Note and none loses a line** - ADR-0003's is
  the supersession pointer and the other four are the amendments. ADR-0003 keeps
  every word of its superseded decisions, and a reader who lands on decision 4
  finds the Note before they find the seam.
- **The host relation is used less and is worth more.** It is asked only after
  coverage has failed, so a host that was widening records into shapes by hand
  can delete that half of its module and keep the half only it can know.

## Deferred questions, named rather than guessed

- **What a fan-out child's `donedata` may declare.** Decision 12 types
  `collect` as `{:list, :unknown}` because the shipped child recipe emits the
  outcome name and nothing else. Whether a child chart may declare what its
  answer carries - a datamodel path list on the `child_use` recipe, or the
  child's own declared collect fields - is ADR-0009 decisions 5 and 6's
  question and is not answered here. `sb-pg91` carries it; it is the one
  question decision 12 explicitly names.
- **The empty fan-out, at the layer below.** This record's own layer has no
  question here, and it is worth saying so rather than leaving a reader of
  decision 12 to wonder what `{:list, :unknown}` means when the list is empty.
  ADR-0009 decision 8 already answers it: "**Which is why an empty list is not
  a refusal.** `items` resolving to `[]` is a successful fan-out over nothing:
  zero children start, the accumulated list is written as `[]`, and the block
  takes `done` immediately." That empty list is a `{:list, :unknown}` like any
  other and nothing downstream changes. What is open is one layer down, where
  a runtime disagrees with that record: `statifier_oban`'s fan-out refuses an
  empty items list on the invocation's error route, and who answers `N = 0` on
  the settlement side is undecided. Neither is this repository's to settle;
  `sb-kha0` carries it.
- **The other three bare-identifier refusals on an `<assign>` location.**
  Decision 13 resolves `core.subchart`'s `assign_to` and deliberately reaches
  neither `core.map`'s `collect` (whose emission is ADR-0009's) nor the
  identical refusals in `core.invoke` and `StatifierBlocks.InvokeStep`.
  Whether all four should agree is a question for whoever next touches those
  records, and it is a question about consistency rather than about
  correctness: each refusal is sound on its own today.
- **Two `core.parallel` lanes writing one path.** Decision 4's merge answers
  it without needing to know which lane ran second, and whether the shape
  deserves an advisory of its own is ADR-0005's findings layer's call.
- **Dropping `max_concurrency` or `params`.** Decision 11 keeps both deferred
  with a reason. Dropping either is still a decision about ADR-0009's
  declaration surface.
- **Whether a host may declare its own `record` or `shape` types.** The
  declarations live in the datamodel document, which a host supplies, so in one
  sense the answer is already yes. Whether a palette entry may declare a type
  the document does not is a different question, it has no consumer today, and
  nothing above depends on the answer.

## Note (2026-09-06): what the flip verified, and seven readings the code settles

A dated note rather than an amendment. Nothing this record decides changes
here: every decision above stands in the words it was accepted in, no clause
gains or loses a member, and the deferred list is untouched. What this records
is the check the flip from proposed to accepted ran - every decision read
against `main` as it stands after the beads that built them - and the seven
places where a reader of the record and a reader of the code would otherwise
come away with different answers.

The record was drafted before any of it was built. `sb-jzg1` took the
dependency, `sb-v5a3` built the walk, `sb-u7zt` declared the write signatures
across the `core.*` vocabulary, `sb-xk1h` built the two `{:path, opts}` keys
and the capture control, and `sb-sy0q` built the two surfaces of decision 9.
Decisions 1 through 8 and 10 through 14 hold as written; decision 9 holds and
is now built rather than promised. The readings below are the residue.

**1. Decision 2's seed and decision 1's read order, at the entry block's own
position.** Decision 2 says the entry block's write signature "is applied
before the walk begins", and decision 1 says a block's reads are checked
"before that block's own writes are applied". Both cannot hold at the entry
block's own position. The code resolves it in decision 1's favour and the
resolution is the honest one: `Environment.seed/3` puts `ctx[:entry_type]` at
the **subject path only**, and the entry block's own writes land through the
walk like every other block's, so the entry block does not read what it is
about to write. Decision 2's sentence describes what every position *after*
the entry block sees, which is what it was written to describe.

**2. Decision 2's write rule reads narrower than its literal words.** Decision
2 says a write signature is "a `{:path, opts}` field with no `writes` key".
Read literally that reaches a read-only `{:path, %{expects: T}}` field and
would blank the very path that field checks. The code reads
expects-without-writes as a **read only**: `Environment.writes?/1` answers
`false` for a field carrying `expects` and no `writes`, `true` for one
carrying neither, and `written_type/1` supplies `:unknown` for the latter. The
same reading is what `t:StatifierBlocks.BlockType.path_opts/0` documents in
as many words: "A field declaring `expects` and no `writes` is a read and not
also a write." Decision 2's rule is to be read as "no `writes` key **and** no
`expects` key".

**3. Decision 4 is silent on an empty slot, and the code says an empty slot
contributes no arm.** A container's empty slot is rejected before the merge
rather than merged as an arm holding nothing (`Environment.arms/5`). Counting
one would blank every `core.branch` on its empty `otherwise` slot, which is
the opposite of what decision 4's per-path merge exists to buy. This is a
clarification of a case decision 4 does not address, not a change to the merge
rule it states.

**4. Decision 11's two fields are declared on `core.foreach`, not
`core.map`.** The heading says "`core.map` keeps `item_as` and `index_as`",
and on `main` those two fields are declared, validated and defaulted in
`lib/statifier_blocks/core/foreach.ex`; `core.map` declares neither. `core.map`
also has no `body` slot - `slots/1` returns `on_done` and `on_error` only - so
the binding decision 11 describes could not reach a `core.map`'s children even
if the fields were declared there. The walk's binding is declaration-driven
rather than type-named (`Environment.fan_out_bindings_for/4` fires for a block
declaring a datamodel-path `items` field **and** carrying a `body` slot), so
`core.foreach` binds today and `core.map` does not. `sb-otpv` carries the gap.

Two smaller readings inside the same decision. `index_as`'s schema `default:`
is the empty string, not `"index"`; the record's `"index"` is the **walk's**
default, applied by `Environment.name/3` when the config carries no name - so
the record's defaults are the names a child actually sees, which is what
decision 11 claims, arrived at one layer further in. And `core.placeholder`
reaches `produces: :unknown` through the `use StatifierBlocks.BlockType`
default `io/1` rather than by declaring it, which is decision 6's inert-sugar
case doing its job.

**5. Decision 10's control shipped as described, with one detail the record
does not name.** The capture row is a repeated two-control row, one row per
pair, with **one trailing blank row** that adds a pair when it is filled and
**no add or remove events**. That is the shape a repetition takes when the
schema already expresses it, and it is why decision 10 could close the
authoring surface without adding a map field type.

**6. Decision 13 shipped, and the sentence describing the defect it fixes is
now historical.** The record's decision 13 describes `check_assign_to/2` as
still refusing anything that is not a bare lowercase identifier. That refusal
is gone: both sites in `core/subchart.ex` - the validation and the emission -
now ask `StatifierBlocks.Core.Config.datamodel_path?/1`, the same predicate
`core.assign` uses, so the candidates and the validation agree exactly as
decision 13 requires. The three other bare-identifier refusals the decision
deliberately did not reach are still in place, still deferred, and `sb-3j9u`
carries whether the four should agree.

**7. The file and line citations throughout this record point at the files as
they stood when it was drafted, and the beads that implemented it moved
them.** The record's argument does not depend on a line number, so no citation
is rewritten here; a reader following one should search for the function
rather than the line. Three citations still resolve exactly -
`lib/statifier_blocks/shell.ex:175` for the drawer's fifth tab,
`lib/statifier_blocks/core/invoke.ex:299` and
`lib/statifier_blocks/invoke_step.ex:430` for two of the three deferred
refusals - and `lib/statifier_blocks/core/map.ex:68-70` still carries the
`collect` sentence quoted from it. The rest have drifted: the `path` field
cited at `core/assign.ex:73-79` is at `:67-73`, its rule at `:89`;
`core/subchart.ex`'s `assign_to` field is at `:260-265`, `check_assign_to/2`
at `:306-316`, and the emission's `assign/1` at `:622-634`;
`core/config.ex:37` is `identifier?/1` at `:40`, beside the
`datamodel_path?/1` reading 6 names at `:54`; `core.map`'s `collect`
refusal, cited at `core/map.ex:188` and `:300-308`, is `@collect_message` at
`:199` with `check_collect/2` at `:311-319`; and the dotted `<assign>` example
decision 13 quotes from `core/assign.ex:146` is at `:139`.

Decision 12 is the one claim worth stating positively because it is easy to
miss in the schema: `core.map`'s `collect` field is declared
`type: {:path, %{writes: {:list, :unknown}}}`, exactly as decision 12 says.

## Note (2026-09-06): two of the three deferred `<assign>` refusals are resolved, and the third is another record's

A dated note rather than an amendment. Every decision above stands in the
words it was accepted in, and no clause gains or loses a member. What this
records is that the deferred question named above as "**The other three
bare-identifier refusals on an `<assign>` location**" has been answered for
two of the three, in the direction decision 13 already argued for, and that
the third is deliberately left where it is.

**What moved.** `core.invoke`'s `assign_to` and
`StatifierBlocks.InvokeStep`'s now read
`StatifierBlocks.Core.Config.datamodel_path?/1` at both of their sites - the
`validate_config/1` check and the emission that has to answer for a config
that check would have rejected - which is exactly the pair decision 13
widened in `core/subchart.ex`. Decision 13's argument reaches them without
being widened itself: the three write the same `<assign location="...">`
element into the same datamodel that `core.assign` writes any non-empty
whitespace-free path through, and one element writing one datamodel cannot
carry two rules about what a location may be. `sb-r313` implements it.

**What did not, and why it is not this record's to move.** `core.map`'s
`collect` keeps the bare-identifier rule. It is the one of the four whose
grammar an accepted decision states outright: `ADR-0009` decision 4 says
"`assign_to` keeps the one grammar it already has: a bare lowercase
identifier ... There is no per-item path grammar and no dotted form", of the
field that ships as `collect`. Widening it is that record's amendment to
make, on that record's own argument, and doing it here on the strength of
this record's would be the sweep by implication decision 13 declined to
make. So the deferred question above closes for two members and stays open
for one, with the owner named rather than left to be found: `sb-3j9u` closes
as folded into `sb-r313`, and whoever reopens `collect` reopens `ADR-0009`.

**Two readings of this record's Note of 2026-09-06 are historical as of
`sb-r313`.** Reading 6 says "The three other bare-identifier refusals the
decision deliberately did not reach are still in place, still deferred":
two of the three are no longer in place. Reading 7 lists
`lib/statifier_blocks/core/invoke.ex:299` and
`lib/statifier_blocks/invoke_step.ex:430` among the citations that "still
resolve exactly", "for two of the three deferred refusals": neither
refusal exists at those lines any more, and neither line holds one now.
Each of the two types instead reaches
`StatifierBlocks.Core.AssignLocation` twice - once from
`validate_config/1`'s check and once from `emit/2`'s re-check - which is
reading 7's own advice arriving in practice: search for the name, not the
number.

**A second thing followed, and it is the reason the bead was filed as a
bug.** `core.invoke`'s `assign_to` was declared `type: :string` with no
`datamodel_path?` key while the block emitted an `<assign>` from it, so a
path the block really wrote was invisible to decision 2's write signature
and to `ADR-0005` clause 11e's advisory. The field is now `{:path, %{}}`,
so the walk reads it as a write of `:unknown` at that path like every other
untyped path field, and the editor offers the host's declared paths as
candidates on it. Nothing about decision 2 changes; a declaration that was
missing from its input is now in it. The census this adds a member to lives
in `ADR-0002`'s Note of 2026-09-06, and that record carries the
corresponding note.

## Note (2026-09-06): decision 11's two names ship on `core.map`, and they bind nothing this walk can see

A dated note rather than an amendment. Every decision above stands in the
words it was accepted in, no clause gains or loses a member, and the deferred
list is untouched. What this records is how decision 11 was built, because the
record's sentence "the names the walk binds inside the fan-out body" turned
out to describe a shape `core.map` does not have, and the resolution is worth
writing down rather than leaving to be inferred from the module.

**What the gap was.** Reading 4 of this record's Note of 2026-09-06 recorded
it: the two fields were declared on `core.foreach` and not on `core.map`, and
`core.map` carries no `body` slot, so the walk's binding - which fires for a
block declaring a datamodel-path `items` field **and** a slot called `body` -
reached the loop and not the fan-out. Two ways out were open. `core.map` could
gain a `body` slot, and the binding would then reach it with no change to
`StatifierBlocks.Environment` at all; or the fields could be declared without
one, and the walk left alone.

**The body slot is not available to take, and that decides it.** `ADR-0009`
decision 3 says "a per-item chart, not a per-item body" and gives the reason
in the same paragraph: an inline `body` slot "was considered and is not
built", because it needs a rule for what a compiled-out-of-line subtree's
identity is, how `ADR-0004`'s provenance map addresses a position inside it,
and how a document with no document id is pinned. None of those is answered by
an accepted record. Adding the slot here to make a binding fall out for free
would decide all three by implication, on the strength of a convenience, which
is the sweep decision 13 declined to make in the other direction.

**So the names ship declared and emitted, and the walk is unchanged.**
`core.map` declares `item_as` (default `item`) and `index_as` (no default
name, the author's or nothing), validates each as a bare lowercase identifier,
refuses the two sharing one name, and carries both into the one `<invoke>` as
`<param>` literals beside `items` - which is the param list `ADR-0009`
decision 3 describes in as many words. Nothing in `StatifierBlocks.Environment`
changes: a `core.map`'s contribution to the environment stays the `collect`
write of decision 12, and the two names are bound by the handler inside a
child run, one document away from anything this walk can check. `item_as` is
read through its default, so a document stored before the field existed
validates as it did.

That is the honest reading of decision 11 for this type, and it is narrower
than the decision's own sentence: the walk binds the two names inside a
fan-out **body**, and the type that has one is `core.foreach`. On `core.map`
the same two names are authoring state for the child's vocabulary, checked
here and bound elsewhere. Decision 11's claim that they are "the names a child
sees its item and its position under" is exactly what ships; the clause about
where the walk binds them is what only `core.foreach` satisfies, and reading 4
above already said so.

**Two sentences elsewhere are historical as of this bead.** Reading 4 of the
Note of 2026-09-06 says "`core.map` declares neither": it declares both now,
and the rest of that reading - no `body` slot, so the binding does not reach
it - is still exactly true and is now true on purpose. And `ADR-0009`'s Note
of 2026-09-05 says of these two fields "Nothing in the shipped emission
carries them, so a child chart today reads whatever the fan-out handler passes
it": the emission carries both, and what the handler passes a child is now the
author's word rather than the handler's convention. Saying so on that record,
where its own declaration-surface table and `ADR-0002`'s row for this type
also stand to be brought up to date, is that record's Note to write and not
this one's.

`sb-otpv` implements it.

## Amendment (2026-09-06): decision 12's `{:list, :unknown}` becomes a reference into the parent's declaration

**Status: accepted (2026-09-06, campaign SF035, bead `sb-jvz3`, recording
campaign-034's ruling `RQ-034-2`).** A decision record merges at proposed under
the campaign invariant; flipping it to accepted is a separate gated request
through the same `docs/adr/` gate, and `sb-upv0` carries it. Additive: decision
12 stands as accepted, and no text above this line is edited by this section.

An amendment rather than a Note, and this record's first: the three dated
sections above are all Notes. Two of them open by saying that "the deferred
list is untouched" (`:785`, `:950`), and the third records that two of the
three parts of one deferred question have been answered "in the direction
decision 13 already argued for" (`:891-896`) - so touching the deferred list
is not by itself what makes a section an amendment, and this section does not
rest on that. What makes this one an amendment is the test the sibling records
apply: decision 12 states the type it writes in as many words, and this
section states it differently. That is the form those records use for the same
case
(`docs/adr/0009-fan-out-block-type.md:967-972`,
`docs/adr/0002-block-type-behaviour.md:2761`): a `## Amendment` heading with a
`Status:` line, additive, nothing above it edited.

An amendment **narrowly**, and the scope is worth stating before the decision.
Two other sections of this record move in campaign SF035 and neither moves
here: `sb-myt1` amends **decision 1** for the inline-shape inhabitant of
`type_expr()` (campaign-SF035 ruling `RQ-SF035-1`, the arm `sd-ADR-0001`'s
amendment spells) and for seeding declared path types from the datamodel index
where the document wrote nothing (campaign-SF035 ruling `RQ-SF035-15`), and
`sb-c9b6` files its own Note. This
section writes only what `ADR-0013` needs of decision 12 and states its
dependence on `sb-myt1`'s work rather than doing any of it.

### What is decided

Decision 12 types `core.map`'s `collect` as `{:list, :unknown}` and says "this
record says nothing about what one element of it holds" (`:524-525`). It now
says something, and the something is **not** the declared summary: an element
is an **envelope**, and the declaration sits one level inside it.

`ADR-0009`'s Note of 2026-09-06
(`docs/adr/0009-fan-out-block-type.md:891`, the table at `:921-925` and the
sentence at `:927-929`) reads the shipped fan-out handler and fixes what one
collected element is - a string-keyed map with `"index"` and `"status"`, plus
`"donedata"` on a completed child, `"failure"` on a failed one, and neither on
a cancelled one. `ADR-0013` decision 5 types that envelope and puts the
parent's declaration on its `"donedata"` member. So decision 12's `T` becomes:

| `core.map`'s `collect_type` | The environment entry at `collect`'s path |
|---|---|
| absent or empty | `{:list, <the envelope>}`, its `"donedata"` member `:unknown` |
| a name (a declaration, a scalar, or an opaque string) | `{:list, <the envelope>}`, its `"donedata"` member that name |

The envelope's members, requiredness and member types are `ADR-0009`'s
amendment of this date, filed with this section; they are not respelled here
and this record decides none of them. `collect_type` is `ADR-0013` decision 1's
new optional `core.map` field, carrying a type **name** read by
`StatifierDatamodel.Types.parse/2` against the parent document's declarations.
Decision 2's rule for a `{:path, %{writes: T}}` field is what puts the entry
there and is unchanged; only the `T` moves.

**Both rows are richer than what ships**, and the first is richer with no
declaration at all: a block after a `core.map` learns that an element has an
index and a status and how a failure is shaped, whether or not the author
declared anything. That is the honest reading of a Note that records bytes the
handler already writes, and it is why this amendment reaches every document
rather than only the declaring ones. Nothing about a stored document changes
otherwise and no compiled bytes move: `collect_type` produces none.

**Decision 12's reason is superseded, and its sentence is quoted so the
supersession is met where the sentence is.** It says the element is unknown
because "the shipped child recipe emits the outcome name and nothing else, so a
declared item type would be a claim about bytes that are not there"
(`:527-529`). Two things falsify it from this date: the envelope's `"index"`
and `"status"` were always there and this record had not looked, and
`ADR-0013` decisions 2 and 3 put the child's declared fields into the bytes
through an optional `donedata_type/1` callback and the `<donedata>` params
`ADR-0004`'s amendment of this date emits. The claim is no longer about bytes
that are not there. The rest of decision 12 stands: the list is still dense and
still in item-index order per `ADR-0009` decision 5, and a block after a
`core.map` still knows exactly what is true and no more.

### The deferred entry this closes, and the one sequencing constraint

The first entry of the deferred list - "**What a fan-out child's `donedata` may
declare**" (`:743-749`), which decision 12 explicitly names and which
`sb-pg91` carries - is answered by `ADR-0013` and loses its place from this
date. `sb-pg91` closes as folded with that record. The other five entries are
untouched, including decision 13's, which `ADR-0009`'s amendment at `:967`
and this record's Note at `:889` moved on their own terms.

**This entry is not spellable until decision 1's `type_expr()` admits an
inline shape**, and that is a sequencing constraint rather than a hidden
dependency. `type_expr()` today is a spelling - a string, `:unknown`, or a
list of one of those (`lib/statifier_blocks/environment.ex:93`) - and cannot
carry a structure, which is exactly what an envelope is. The inhabitant is
`sb-myt1`'s amendment to decision 1, citing the inline-shape amendment to
`sd-ADR-0001` in `statifier_datamodel` rather than respelling its grammar;
widening `type_expr()` reaches every field with a `writes` key and not only
this one, which is why it is decision 1's and not decision 12's. Until it
lands the shipped entry stays `{:list, :unknown}`, unchanged and not wrong -
a spelling that cannot be written is not written - and `sb-nqfd` builds this
amendment after `sb-myt1` rather than before.

A consumer that read `{:list, :unknown}` and branched on it - the editor's
expression surface is the one that exists - reads a list of a shape instead,
which is more information and not different information.

Filed with `sb-jvz3`, against `ADR-0013` as merged (PR 319, `b90d40e`);
campaign-SF035, from campaign-034's ruling `RQ-034-2`. `sb-nqfd` builds it,
behind `sb-myt1`.

## Note (2026-09-06): decision 1's walk now runs on a partially-configured document, and a block whose config was refused contributes nothing to it

`RQ-SF035-2`, taken by the operator with the campaign-SF035 walk, changes
when the compiler asks for this walk. Until now the Structure stage ran only
after the Config stage had passed, so every block the walk met carried a
config `validate_config/1` had accepted. From `sb-c9b6` the two stages report
together (`ADR-0004`'s Note of this date amends decision 10's "first failing
stage" sentence, which is where that sequencing was recorded), so this walk
is now also asked about documents in which one or more blocks have a
`:config` finding standing against them.

Decision 1 is not restated by this. The walk is the same walk - pre-order,
one pass, pure, last-write-wins by position, arms merged per decision 4, the
shelf not entered - and the environment's inhabitants are the same four. What
this Note adds is what such a block contributes to it, which decision 1 had
no occasion to say because such a block could not reach the walk.

**A block whose config the Config stage refused contributes nothing.** Its
read signature is not checked and its write signature puts no entry, so the
path it claimed to write holds whatever it held before the block. The walk
continues past it: its siblings are walked in the same pre-order, its slots
are still descended, and a child of it is treated on its own terms, because a
child's config is its own and was accepted or refused on its own.

The reason is decision 2's, read one step further. A write signature is not a
property of a block type; it is read off the block's **config** - the path a
`{:path, %{writes: t}}` field names and the type the declaration gives it.
When that config is the one the compiler has just refused, the signature is
derived from a value nobody has agreed is well-formed. Applying it would put
an entry in the environment on the strength of a refused config, and the next
block's read would then be checked - and quite possibly satisfied - against a
type nobody declared. Decision 5 makes an unsatisfied read an `:error`, so
that is not a cosmetic difference: it decides whether the document refuses.
Leaving the entry out is the answer that says only what is known.

Skipping is by **block id**, and it is an absence of one block's
contribution rather than a shortened walk. The mechanism is a `:skip_blocks`
key on the walk's context (`lib/statifier_blocks/environment.ex`, the
`context/0` typedoc and `through/5`), which
`StatifierBlocks.Assignability.validate/3` reads for the same set so that the
findings it reports and the environment it reports them against agree. The
key is caller-supplied and the compiler is the only caller that sets one; the
editor's queries - `check/5`, `valid_targets/4`, `Environment.at/4` - pass no
skip set and are unchanged in every particular.

The property that keeps this from touching anything already shipped: for a
document with no `:config` finding the skip set is empty, and an empty skip
set makes every clause above a no-op. Such a document's environment, at
every position, is the one decision 1 has always described. The compiler's
byte corpus (`test/statifier_blocks/compiler/byte_corpus_test.exs`, still
pinned to the 0.21.0 goldens) is green unchanged, which is that property
cashed rather than asserted.

Nothing in decisions 2 through 14 is amended. In particular decision 3's read
check is untouched - the question of *whether* a held type satisfies an
expected one is `sd-ADR-0001` decision 8's and this Note does not go near it;
only the question of what the environment holds at a path is narrowed, and
only for a block the compiler has already refused.

Filed with `sb-c9b6`, campaign-SF035, from the walk's ruling `RQ-SF035-2`
(which also folds `sb-lvh1`). `sb-myt1`'s amendment to decision 1 - the
inline-shape arm of `type_expr()` - is a separate and later change to this
same decision and does not interact with this one: one narrows what the walk
carries for a refused block, the other widens what a type may spell.

## Amendment (2026-09-06): decision 1's type expression admits an inline shape, and the environment seeds the declared path types the document has not written

**Status: accepted (2026-09-06, campaign SF035, bead `sb-myt1`, recording the
walk's rulings `RQ-SF035-1` and `RQ-SF035-15`).** A decision record merges at
proposed under the campaign invariant; flipping it to accepted is a separate
gated request through the same `docs/adr/` gate, and `sb-wzoa` carries it.
Additive: no text above this line is edited by this section, and both parts
grow decisions 1 and 2 rather than taking anything away from a document
already written.

An amendment rather than a Note, by the test the sibling records apply and the
section above applied to decision 12: decision 1 states the type vocabulary in
as many words - "one of the nine scalars, the `name` of a `record` or `shape`
declaration, `{:list, type}`, or `:unknown`. There is no other inhabitant"
(`:141-143`) - and part 1 states it differently; decision 2 states the seed in
as many words - "the document opens with its subject path holding its subject
type and nothing else" (`:182-183`, restated at
`lib/statifier_blocks/environment.ex:242`) - and part 2 states it
differently. Two decisions move, so the section is numbered, and each part
names what it leaves standing.

The two parts are independent of each other and both are `sb-1jcr`'s to build.
They are filed together because they are one ruling pair from one walk and
because they meet in one function: the seed is where a declared type first
enters the environment, and an inline shape is one of the types it may be.

### 1. `type_expr()` admits an inline shape, and the arm is `sd-ADR-0001`'s

Decision 1's type vocabulary gains **one inhabitant**, the inline, unnamed
shape that `sd-ADR-0001`'s amendment of this date defines - its section
"Amendment (2026-09-06): a type expression admits an inline, unnamed shape
beside a declared name" in `statifier_datamodel`, accepted on the operator's
same-walk ruling `RQ-SF035-1`, its code on that package's `main` in `3116a72`.
That amendment's arms (a) through (e) are the arm's whole definition: the
spelling `{:shape, [member()]}` with a member's three keys, member-set-wise
identity rather than term equality, construction by a consumer with no
document syntax to write one, the member-wise step the read check gains and
its per-variant table, and the three things an unnamed shape cannot do. **This
record cites that section and respells none of it**, for the reason decision 3
already gives for the read check: the grammar and the check are that package's
and this one defines no second copy.

So decision 1's sentence reads, from this date: a type is one of the nine
scalars, the `name` of a `record` or `shape` declaration, an inline shape as
`sd-ADR-0001`'s amendment spells it, `{:list, type}`, or `:unknown`. The
`{:list, type}` arm recurses over the new one without further comment, so a
list of inline shapes is sayable and is what part 1's third consumer below
needs.

**Decision 1's provenance sentence is the one thing that moves with it.** It
says "this package mints none: every one of them comes from the datamodel
document or from a block's own declaration" (`:143-144`). An inline
shape has no document syntax (`sd-ADR-0001`'s arm (c)), so it cannot come from
the document, and the value that motivates the arm here is not written on a
block either: the fan-out envelope is assembled by this package from
`ADR-0009`'s reading of the shipped handler and typed by `ADR-0013` decision
5. The sentence therefore gains a third source and stops being a claim that
this package mints nothing: **an inline shape may also be one this package
assembles from a record's own decision**, and the envelope is today the only
such value. It is a narrow widening and deliberately so - a type expression
this package assembles has to be traceable to a record that decided its
members, and an inline shape invented at a call site is not what this arm is
for.

**Every consumer of the type vocabulary, and what the arm reaches in it:**

| Consumer | Where | What the arm reaches |
|---|---|---|
| The spelling itself | `t:StatifierBlocks.Environment.type_expr/0` (`lib/statifier_blocks/environment.ex:93`), and its second name `t:StatifierBlocks.BlockType.path_type/0` (`lib/statifier_blocks/block_type.ex:159-166`) | One definition and one edit: `block_type.ex` is that typespec under a second name rather than a second definition, and its prose sentence names the same inhabitants |
| The read check | Decision 3, which is `StatifierDatamodel`'s `satisfies/3` and `satisfies?/3` reached through `StatifierBlocks.Assignability` | Nothing to decide: the member-wise step and its refusals are `sd-ADR-0001`'s arm (d), and decision 3's "this package defines no second one" is why |
| The expected/held pair a refusal reports | `t:StatifierBlocks.Assignability.finding/0`'s `:type_mismatch`, whose `produced` and `consumed` members are `type_expr()` (`lib/statifier_blocks/assignability.ex:116-117`) | Both members may hold an inline shape. The tuple **does not grow**: the member decision 8 added is the path, and this arm adds none |
| `core.map`'s `collect` | Decision 12 as amended by the section above, over the `ADR-0009` envelope whose `"donedata"` member `ADR-0013` decision 5 types | The inhabitant that section is waiting on. It says the entry "is not spellable until decision 1's `type_expr()` admits an inline shape" (`:1100-1101`); this part is that inhabitant, `sb-nqfd` builds the entry, and neither the envelope's members nor its requiredness is decided here |
| The editor's typed cells and the expression surface | `StatifierBlocks.Datamodel.path_types/1` (`lib/statifier_blocks/datamodel.ex:572-576`), wrapping `StatifierDatamodel.Index.path_types/1`, reaching the editor through `declared_path_types/1` (`lib/statifier_blocks/editor.ex:1970-1972`) and `Editor.Field`'s `path_types` attribute (`lib/statifier_blocks/editor/field.ex:367-371`) | A projected entry may carry one. What the surface draws for it is `ADR-0005`'s, per decision 9, and `sui-9pj` follows in `statifier-ui` |

The code is `sb-1jcr`'s. Until it lands nothing spells an inline shape and
every consumer above behaves exactly as it does today, which is the same
sequencing the section above states for `sb-nqfd`.

### 2. The environment seeds the declared path types the document has not written, and a written type wins

**What decision 1 says and what it costs.** The environment is what the
document has written on the way to a position: a block's write signature puts
an entry, the seed is decision 2's entry-block subject, and nothing else puts
anything anywhere. `sb-y4i7` (PR 327, `259b6dc`) read that against the
declaration-typed scope entry `sd-ADR-0001`'s `sd-wj1` amendment added and
found the two halves of this package disagree: the projection reaches
`StatifierBlocks.Datamodel` - `declared_paths/1`, `candidates/3`,
`path_types/1` and `declared_view/3` all go through `StatifierDatamodel.Index`
and get the projected members for free - and it does **not** reach the
`Environment`, whose sole reader of `ctx[:datamodel]` is `declarations/1`
(`lib/statifier_blocks/environment.ex:323-331`) and reads it for its
declarations alone. A path the host declared and no block wrote is therefore a
completion candidate with a type in the Datamodel tab and an absent entry in
the walk, and a read at it is decision 5's `:info` however precisely the host
typed it. That is not a property anybody decided; it is decision 1's sentence
reaching a case it was written before.

**Decided: the seed carries the document's declared path types.** Before the
walk begins, the environment holds an entry at every path
`StatifierDatamodel.Index.path_types/1` projects from `ctx[:datamodel]` - the
same projection `StatifierBlocks.Datamodel.path_types/1` wraps and the editor
already draws - at the type it projects. Decision 2's entry-block subject is
applied over that, and the walk then runs exactly as decision 1 describes.

**A type the document writes wins**, by position and with no new rule: a
seeded entry is an entry like any other, so decision 1's last-write-wins is
what settles the disagreement, and a block writing `cards.settlement` replaces
what the declaration seeded there for every position after it. Per path:

| At a path | The environment holds, at a position |
|---|---|
| Declared, and no block wrote it before this position | The declared type, marked as seeded |
| Declared, and a block wrote it before this position | What that block wrote (decision 1's last-write-wins, unchanged) |
| Not declared, and a block wrote it | What that block wrote |
| Neither | No entry, and a read there is decision 5's `:info` |

**Seeded entries are marked.** The environment already carries, per entry, the
block that wrote it - `t:StatifierBlocks.Environment.annotated/0` (`:103`),
whose second member is a `Block.id()` or `:slot_entry`, and which is what
decision 8's `upstream_ref` names. A seeded entry's writer is neither: it is
the datamodel document. That member gains **one inhabitant, `:declaration`**,
so a finding can say the type it disagreed with came from the host's
declaration rather than from a block, and `:type_mismatch`'s `upstream_ref`
admits it beside `:slot_entry`. Two consequences are worth stating because
they are what the marking is for. `{:fixable_by, block_id}` does not apply to
such a finding - there is no block whose declaration an author would change,
and the change is to the datamodel document - and a message can say *which*
of the two sources typed the path, which is the difference between "your
block writes the wrong type here" and "the host declares this path as
something else".

**What this does not change.** Decision 3's read check is untouched: whether a
held type satisfies an expected one is `sd-ADR-0001` decision 8's question and
seeding does not go near it. Decision 4's merge is untouched: a seeded entry
is present and identical in every arm of a container, so it agrees with itself
and merges to itself. Decision 2's write and read signatures are untouched -
this section adds no signature and no block declares a seed. The `:skip_blocks`
narrowing the Note above adds is untouched and does not interact: it removes a
refused block's own writes, and a seeded entry was put there before any block
was walked. And the shelf's rule stands as decision 1 states it - a parked
fragment is walked from an **empty** environment, which is the shelf's own
rule about what a fragment may assume, and a fragment assumes no more of the
host's declarations than it assumes of its neighbours.

**Two sentences of decision 2 are superseded, and they are quoted so the
supersession is met where they are.** "A document whose first block declares
no subject seeds an empty environment" and "every read in it is a read of a
path the environment does not hold - which decision 5 makes an `:info` and not
an error, so an untyped document validates exactly as it does today"
(`:183-187`). From this date the first holds only where no datamodel document
is supplied, and the second holds only for a path the datamodel does not
declare. **This is a behaviour change and the honest reading of it is that a
document can now refuse where it advised**: a read at a declared path whose
declared type does not satisfy the read was an `:info` and becomes decision
5's `:error`. That is the ruling's point rather than a side effect - a host
that took the trouble to declare a path said what is there, and a document
disagreeing with it is wrong in the same way it is wrong when it disagrees
with a block - but it means a stored document that validated may stop
validating when its host supplies a datamodel, and it is why `sb-1jcr` is a
minor-version change rather than a patch. A caller that supplies no
`:datamodel` seeds nothing new and is unaffected in every particular; today
that is every caller that has no document to read, the compiler and the editor
both supplying one when they have it (`lib/statifier_blocks/compiler.ex:682`
and `lib/statifier_blocks/editor.ex:1922-1923`).

**`RQ-SF035-15` is where this was decided**, taken by the operator with the
campaign-SF035 walk on `sb-g6me`'s question, which `sb-y4i7` raised and
declined to answer on the grounds that seeding declared path types is a record
question and not a bead's. It was right; this is the record answering it.
`sb-g6me` closes as folded with this section.

Filed with `sb-myt1`, campaign SF035, from the walk's rulings `RQ-SF035-1` and
`RQ-SF035-15`, against `sd-ADR-0001`'s inline-shape amendment as merged in
`statifier_datamodel` and against this record as `sb-jvz3` and `sb-c9b6` left
it. `sb-1jcr` builds both parts; `sb-wzoa` flips this section.

## Note (2026-09-06): what the flip of decision 12's amendment checked, and its sequencing sentence met

`sb-upv0` is the separate gated request the amendment of this date on decision
12 names in its own status paragraph (`:1012-1016`), and it has flipped that
section's `Status:` word from `proposed` to `accepted`. That word is the only
text the flip changes in this record. This Note is by addition, sits at the
foot so that no line a sibling record cites moves, and carries no `Status:`
line of its own.

The flip is narrow in exactly the way the amendment is: it reaches **that
section only**. The Note of this date filed with `sb-c9b6` carries no
`Status:` line and nothing on it is flipped. `sb-myt1`'s amendment to decision
1 keeps its own status and its own request, `sb-wzoa`, as its closing sentence
says.

**The sequencing sentence is met rather than falsified.** The amendment says
the entry "is not spellable until decision 1's `type_expr()` admits an inline
shape", that `type_expr()` "today is a spelling - a string, `:unknown`, or a
list of one of those (`lib/statifier_blocks/environment.ex:93`) - and cannot
carry a structure", and that "until it lands the shipped entry stays
`{:list, :unknown}`". It landed. `type_expr()` reads
`String.t() | :unknown | {:list, type_expr()} | {:shape, [member()]}`
(`lib/statifier_blocks/environment.ex:104`, `member()` at `:107`), built from
a stored member list by `inline_shape/1` (`:522-529`), and `sb-1jcr` (PR 355,
`d804062`) is the request that put it there under `sb-myt1`'s amendment. The
sentence named that sequencing as a constraint and the constraint is
discharged; the cite it carries moved from `:93` to `:104`. Every cite in this
Note was read off `main` at `94d1990`. The `0.23.0` release prep
(`081e426`) landed on `main` while this flip was open; it changes two version
strings one line for one line and moves no line this Note cites.

**Both rows of the amendment's table are what ships.** `core.map` types
`collect` as `{:path, %{writes: {:list, envelope(config)}}}`
(`lib/statifier_blocks/core/map.ex:456-462`), the envelope is assembled at
`:405-414`, and its `"donedata"` member is `:unknown` on an absent or empty
`collect_type` and the declared type otherwise (`:416-422`) - the second row
now reachable by an inline shape as well as by a name, which is `ADR-0002`'s
Amendment of 2026-09-06 on decision 7, the `{:type_expr, opts}` field type
(`docs/adr/0002-block-type-behaviour.md:4957`), and `ADR-0013`'s Note filed
with `sb-268w`, not this record's to restate. Decision 2's rule is what puts
the entry there and is untouched; only the `T` moved, exactly as the amendment
says.

**No compiled bytes move**, which the corpus pins
(`test/statifier_blocks/compiler/byte_corpus_test.exs`): `collect_type`
produces none.

**The read cites resolve unmoved**: decision 12 at `:520` with its quoted
sentences at `:522-525` and `:527-529`, the deferred entry this closes at
`:743-749`, the two Notes that open on the untouched deferred list at `:785`
and `:950`, and the Note at `:889-896`. `ADR-0009` `:891`, `:921-925` and
`:927-929` still carry the envelope this decision now references.

Filed with `sb-upv0`, campaign SF035's Lane A.

## Note (2026-09-07): `sb-myt1`'s amendment is **not** flipped - one sentence of part 2 does not hold against the code - and four cites are corrected

`sb-wzoa` is the separate gated request the Amendment of 2026-09-06 on decision
1 and decision 2 (`:1186`) names in its closing sentence. It has **not** flipped
that section's `Status:` word, which still reads `proposed`. This Note records
why, and takes four corrections owed to that section and to the section above
it. It is by addition, sits at the foot so that no line a sibling record cites
moves, and carries no `Status:` line of its own. Nothing above this line is
edited by it, and this request changes no text in this file.

Every line below is a census taken on `main` at `f750b3b`, with
`deps/statifier_datamodel` resolved at `0.4.0`; it is dated to this Note and is
to be re-counted by a later reader rather than trusted.

### 1. Why part 2 is not flipped: the projection its *Decided* paragraph names is not the projection the seed reads

Part 2's deciding sentence says the environment "holds an entry at every path
`StatifierDatamodel.Index.path_types/1` projects from `ctx[:datamodel]` - the
same projection `StatifierBlocks.Datamodel.path_types/1` wraps and the editor
already draws - at the type it projects".

That is not what `sb-1jcr` built and it is not what the rest of part 2 asks
for. `StatifierBlocks.Environment.declared_seed/1`
(`lib/statifier_blocks/environment.ex:781-787`) reads
`StatifierDatamodel.Index.entries/1` and takes each entry's **declared type**,
through `seeded_entry/1` (`:789-795`) and `declared_spelling/1` (`:801-808`).
`Index.path_types/1` is a different projection with a different job: it answers
the expression language's **value kinds**, so `integer` and `decimal` both come
back `:number`, a drawable `one_of` wins over the entry's type, and an
`object`, a declaration-typed entry, a list with no usable `item_type` and an
untyped entry are all **absent from its map**
(`deps/statifier_datamodel/lib/statifier_datamodel/index.ex:380-439`). The two
therefore disagree about **which paths** carry a seeded entry and about **what
type** each carries.

Part 2's own decision table says the other thing - "Declared, and no block
wrote it before this position | The declared type, marked as seeded" - and so
does the code's own restatement of decision 2, "every path `ctx[:datamodel]`
declares, at the type it declares there" (`:263-273`). So the section is
internally inconsistent about the one question, and the sentence a reader would
cite is the one that does not hold.

**Which of the two the record should say is an open question and not this
request's to settle**, and it has no bead of its own: the campaign's records
bead `sb-m9eq` reaches this section from a different direction and covers only
part of it. That bead asks where a seeded type enters along the **walk** -
at every position, or from the root forward up to the first write at the path -
because a position-independent seed erases the only place a blanket refusal and
a write-following refusal are distinguishable in the reference embedder's drop
verdict. Its second symptom is this one: it also records that a path declared
as a bare `object` refuses a record read, which is a path `path_types/1` would
not have projected at all and `entries/1` seeds as `"object"`. **The projection
question is therefore adjacent to `sb-m9eq` rather than asked by it**, and both
belong to whoever settles that bead.

Correcting the citation in place is not open to this request either, and that
is the whole reason the flip is held rather than cured. The section says one
thing in its deciding sentence and another in its table; repointing the
sentence would pick which of the two wins, and picking is a decision this
record has not taken. What a flip may do is verify a record against `main` and
move a status word - the practice the Note at `:1362` names in its own heading,
"what the flip of decision 12's amendment checked" - and it does not extend to
settling a decision the section left in two minds. So part 2 stays at
`proposed`, and part 1 stays with it: the two parts share one `Status:` line and
this Note splits no section.

Nothing else in part 2 failed. The seed is applied **once, before the walk**,
in `seed_annotated/3` (`:759-762`) reached from `annotated/4` (`:185-206`) and
`seed/3` (`:298-301`), and nowhere else in `lib/`; decision 2's entry-block
subject is applied over it (`subject_seed/3`, `:764-770`); a block's write
replaces a seeded entry for every position after it by decision 1's
last-write-wins and by no new rule; a parked fragment is still walked from an
empty environment (`slot_start/4`, `:627-634`); and `annotated/0`'s writer
member carries the `:declaration` inhabitant the section adds
(`:125-127`), which `t:StatifierBlocks.Assignability.upstream_ref/0` admits
beside `:slot_entry` (`lib/statifier_blocks/assignability.ex:112`).

Part 1 held in every particular checked: `type_expr/0` admits `{:shape,
[member()]}` with `member/0` beside it (`:104`, `:107`), `inline_shape/1`
builds the term from a stored member list (`:521-529`), the `:type_mismatch`
tuple did **not** grow (`lib/statifier_blocks/assignability.ex:126-127`), and
`t:StatifierBlocks.BlockType.path_type/0` is still that typespec under a second
name (`lib/statifier_blocks/block_type.ex:163-176`).

### 2. The two `editor.ex` cites in part 2 have moved twice

Part 2 cites `assignability_context/1` at `lib/statifier_blocks/editor.ex:1922-1923`
and `declared_path_types/1` at `:1970-1972`. `sb-pm3k` (`1721a31`) shifted both
by 66, and `sb-btvx` and `sb-1jcr` moved them again. They read today at
`:2053-2055` and `:2113-2116`.

### 3. Part 2's `Index.path_types/1` citation is wrong wherever it appears

Item 1 above is the deciding instance. The same citation carries into part 1's
consumer table, where the editor's typed cells are described as reaching
`StatifierDatamodel.Index.path_types/1` through
`StatifierBlocks.Datamodel.path_types/1`. **That one is correct** - the editor's
cells really do read the value-kind projection
(`lib/statifier_blocks/datamodel.ex:572-578`, reached at
`lib/statifier_blocks/editor.ex:2113-2116`) - and it is the seed, not the
editor, that reads something else. The two halves of this package draw
different projections of one index, which is the substance `sb-m9eq` has to
settle.

### 4. Decision 12's `collect_type` table has no inline row

The amendment of 2026-09-06 on decision 12 - accepted by `sb-upv0` - gives
`collect_type` two rows, "absent or empty" and "a name (a declaration, a
scalar, or an opaque string)" (`:1057-1060`). The field now admits a third arm:
`ADR-0002`'s Amendment of 2026-09-06 on decision 7 declares `collect_type` as
`{:type_expr, opts}` with both arms, its clause 1 names the inline shape as an
arm of its own, and `core.map` declares it that way
(`lib/statifier_blocks/core/map.ex:463-469`). The section anticipated exactly
this at `:1100-1106`, which is why the gap is a missing row and not a changed
decision.

**Read the table as carrying a third row**, by addition and with no word of the
two above it changed:

| `core.map`'s `collect_type` | The environment entry at `collect`'s path |
|---|---|
| an inline shape (`sd-ADR-0001`'s `{:shape, [member()]}`, per `ADR-0002` decision 7 as amended, clause 1) | `{:list, <the envelope>}`, its `"donedata"` member that shape |

The code already reads it that way: the envelope's `"donedata"` member is
`:unknown` on an absent or empty `collect_type` and the declared type
otherwise, whichever arm the stored bytes are
(`lib/statifier_blocks/core/map.ex:394-422`). Recording the row here rather
than at `:1060` is the reason the record gives elsewhere for not editing a
merged section in place: adding a row adds words, which puts it outside the
formatting-only exemption, and amendments here are additive.

### 5. Cites in `sb-myt1`'s amendment that drifted under the code

| Written in the amendment | Reads today |
|---|---|
| `lib/statifier_blocks/environment.ex:93` (`type_expr/0`) | `:104` |
| `lib/statifier_blocks/environment.ex:103` (`annotated/0`) | `:125-127` |
| `lib/statifier_blocks/environment.ex:242` (decision 2's seed sentence restated) | `:263-273` |
| `lib/statifier_blocks/environment.ex:323-331` (`declarations/1`) | `:361-371` |
| `lib/statifier_blocks/block_type.ex:159-166` (`path_type/0`) | `:163-176` |
| `lib/statifier_blocks/assignability.ex:116-117` (`:type_mismatch`'s two type members) | `:126-127` |
| `lib/statifier_blocks/datamodel.ex:572-576` (`path_types/1`) | `:572-578` |
| `lib/statifier_blocks/editor.ex:1922-1923` (`assignability_context/1`) | `:2053-2055` |
| `lib/statifier_blocks/editor.ex:1970-1972` (`declared_path_types/1`) | `:2113-2116` |
| `lib/statifier_blocks/editor/field.ex:367-371` (the `path_types` attribute) | `:419-427` |
| `lib/statifier_blocks/compiler.ex:682` (the compiler supplying `:datamodel`) | `:837-845` |

### What this Note does not do

- **It flips nothing.** The amendment at `:1186` still reads
  `Status: proposed`, and `sb-wzoa` remains the request that carries its flip.
- **It settles neither the projection question nor `sb-m9eq`**, and adds no
  rule about which paths a seed reaches or where along the walk one enters. It
  records that the section says one thing in its deciding sentence and another
  in its table, and that the code follows the table.
- **It edits no clause and moves no line.** Every correction above is a reading,
  recorded here.

Filed with `sb-wzoa`, campaign SF035's Lane A.

## Note (2026-09-07): seeding is root-forward, the seed reads `Index.entries/1` and each entry's declared type, and a bare `object` is nominal

`RQ-SF035-24` asked two questions of this record and was ruled by the operator
on 2026-09-07 as `RQ-SF036-0a` and `RQ-SF036-0b`. This Note records the ruling.
It sits at the foot so that no line a sibling record cites moves, it edits no
clause, it removes no line, and it carries no `Status:` line of its own. The
one sentence it supersedes is named below and left standing where it is.

Every line cite below is a reading of `main` at `b71740c`, with
`deps/statifier_datamodel` resolved at `0.4.0`, and is to be re-counted by a
later reader rather than trusted.

### 1. Position: seeding is root-forward, and the question was moot as worded

The question was whether a seeded declared type enters the environment at
**every** position or only **from the document root forward, up to the first
write at that path**. It is the second, and this record already said so twice
before the question was asked.

The per-path table in part 2 of the Amendment of 2026-09-06 (`:1295-1300`)
reads, in its first two rows:

| At a path | The environment holds, at a position |
|---|---|
| Declared, and no block wrote it before this position | The declared type, marked as seeded |
| Declared, and a block wrote it before this position | What that block wrote (decision 1's last-write-wins, unchanged) |

"Before this position" is the root-forward rule stated per position, and it is
decision 1's last-write-wins doing the work rather than a rule of its own. The
`seed/3` moduledoc says the same in prose - "a block writing a path replaces
what the declaration seeded there for every position after it"
(`lib/statifier_blocks/environment.ex:279-282`) - and the walk implements it by
having nothing to implement: a seeded entry is an entry, the walk is pre-order,
and a later write replaces it from its own position onward.

**Decided: nothing changes.** No position rule is added, amended, or removed;
no walk code changes. The existential-over-positions drop verdict this record
describes keeps the shape it has, because a blanket refusal and a
write-following refusal stay distinguishable exactly as before: a declaration
seeds a path from the root, a write at that path replaces it from the write
onward, and the two are different sets of positions.

**Why the question arose, and what actually differed.** It arose from a read
that was refused where the reader expected it to be admitted, in the reference
embedder's card-processing fixture. That fixture declares the **path**
`cards.settlement` with `"type": "object"` while its receipt step reads the
**record** named `cards.settlement`, which the same fixture also declares. The
seed therefore held `"object"` at that path from the root forward, the receipt
step's read expected `"cards.settlement"`, and the check refused it. No
position was involved: the refusal is the same at every position, because
nothing in that flow writes `cards.settlement` at all. What is wrong is the
fixture's declaration, not the seeding rule, and the fixture is what changes -
in `statifier_examples`, under `se-yag`.

### 2. Projection: the seed reads `Index.entries/1` and each entry's declared type

Part 2's deciding sentence (`:1283-1288`) says the environment "holds an entry
at every path `StatifierDatamodel.Index.path_types/1` projects from
`ctx[:datamodel]` - the same projection `StatifierBlocks.Datamodel.path_types/1`
wraps and the editor already draws - at the type it projects". The Note of
2026-09-07 above (`:1417`) recorded that this is not what the code does and
held the flip on it.

**Decided: the code is right and the sentence is superseded.** The seed reads
`StatifierDatamodel.Index.entries/1` and takes each entry's **declared type**.
`StatifierBlocks.Environment.declared_seed/1`
(`lib/statifier_blocks/environment.ex:781-787`) is that read, and
`declared_spelling/1` (`:801-808`) is the spelling: a declaration name stays
its name, a scalar becomes its own atom spelled out, a list carries its item
type, and an entry the index cannot name a type for contributes nothing.

The superseded sentence is left where it stands, unedited. It is superseded
because `path_types/1` answers a different question. It projects **value
kinds** for a renderer - `integer` and `decimal` both become `:number`, an
enumeration wins over the type, and `object`, a declaration-typed entry and an
untyped entry each contribute **no path at all**
(`Index.path_types/1` over `value_kind/1` and `scalar_kind/1`). Those dropped
entries are precisely the ones the seed exists to carry: a path declared as a
record is the case the read check has the most to say about, and a path
declared as `object` is the case that produced the question in section 1. A
seed built from `path_types/1` would hold neither.

The two halves of this package therefore draw two projections of one index on
purpose, and the comment above `declared_seed/1` that claimed they cannot drift
apart (`:772-775`) is corrected in the same request that carries this Note. The
Datamodel tab and the editor's typed cells keep reading
`StatifierBlocks.Datamodel.path_types/1` (`lib/statifier_blocks/editor.ex:2113-2116`),
because a renderer wants kinds; the walk keeps reading `entries/1` and the
declared type, because a check wants names.

This releases `sb-wzoa`: with the deciding sentence superseded rather than
contradicted, the Amendment of 2026-09-06 on decision 1 and decision 2
(`:1186`) is flippable, and `sb-wzoa` remains the separate gated request that
flips it.

### 3. A bare `object` is nominal, and does not cover a read of a declared record

**Decided: a path declared `object` holds the type `object` and nothing more.**
It is a name like any other name, and it satisfies a read only where decision 8
of `sd-ADR-0001` says a name satisfies one - by identity, or by a record
covering a shape's required set. `object` names no declaration, so it covers no
shape; it is not equal to any record name, so it satisfies no record read; and
it is not unknown, so it is not permissive either. There is no structural arm
in that check, and this record adds none.

This is not a widening this package could add on its own account. Decision 3 of
this record already says the read check is `sd-ADR-0001` decision 8's and that
this package defines no second one. `sd-y3l` lands the matching Note against
decision 8 in `statifier_datamodel`, saying the same thing from that side.

**Worked example, in the card-processing domain.** A datamodel document
declares a record `cards.settlement` with `amount_cents`, `currency` and
`settled_on`, and declares the path `cards.settlement` as `object`. A receipt
step reads `cards.settlement` expecting the record.

| Held at `cards.settlement` | Read expects | Verdict |
|---|---|---|
| `"object"` (the path declared bare) | `"cards.settlement"` | Not satisfied - decision 8 step 4. `object` is not the same name, and names no record whose fields could cover anything |
| `"cards.settlement"` (the path declared at the record) | `"cards.settlement"` | Satisfied - decision 8 step 2, identity |
| No entry (the path not declared) | `"cards.settlement"` | No entry to check: decision 5's `:info` |

The middle row is what the reference fixture means to say, which is why the
fixture is what `se-yag` changes.

### What this Note does not do

- **It flips nothing.** The Amendment at `:1186` still reads `Status: proposed`
  and `sb-wzoa` still carries its flip.
- **It removes and moves nothing.** The superseded sentence at `:1283-1288`
  stands where it is; this Note says it is superseded and why.
- **It changes no walk behaviour.** The only code in the request that carries
  it is the corrected comment above `declared_seed/1`.

Filed with `sb-m9eq`, campaign SF036's Lane X. `sb-wzoa` flips the Amendment
this releases; `se-yag` edits the card-processing fixture; `sd-y3l` lands the
matching Note on `sd-ADR-0001` decision 8.

## Note (2026-09-07): `sb-myt1`'s amendment is flipped to accepted, as read with the Note of 2026-09-07 that supersedes one sentence of its part 2

The Amendment of 2026-09-06 on decision 1 and decision 2 (`:1186`) reads
`Status: accepted` from this date. `sb-wzoa` is the separate gated request that
section's own status paragraph names, and this Note is what the flip checked.
It is by addition, sits at the foot so that no line a sibling record cites
moves, edits no clause, and carries no `Status:` line of its own. The only
line the request removes is the one the status word is on, which is the shape
`sb-upv0` and the flip of decision 7's amendment in `ADR-0002` both took.

No marker is added beside the status paragraph, because nothing in it is
falsified by the flip: it says a record of that campaign merges at proposed and
that flipping it is a separate gated request `sb-wzoa` carries, and both
sentences are as true after the flip as before. The sentences elsewhere in this
file that name the section's status are met in section 3 below, where they
stand.

Every line cite below is a census taken on `main` at `495e8b0`, with
`deps/statifier_datamodel` resolved at `0.4.0`. It is dated to this Note and is
to be re-counted by a later reader rather than trusted.

### 1. What released the hold, and what the flip accepts

The Note of 2026-09-07 above (`:1417`) held this flip on one sentence: part 2's
deciding paragraph (`:1283-1288`) says the environment holds an entry at every
path `StatifierDatamodel.Index.path_types/1` projects, and the code reads
`StatifierDatamodel.Index.entries/1` and each entry's declared type. The
section said one thing in that sentence and another in its own table, and
picking between them was a decision, not a re-cite, so the flip did not
proceed.

The operator took that decision on 2026-09-07 as `RQ-SF036-0b`, and the second
Note of that date above (`:1577`) records it: **the code is right and the
sentence is superseded**, the seed reads `entries/1` and the declared type, the
superseded sentence is left standing where it is, and the two halves of this
package draw two projections of one index on purpose. That Note closes with
the sentence that releases this request.

**So the flip accepts this section as read with that Note.** Part 2's deciding
sentence is not repointed, not reworded and not removed: it stands at
`:1283-1288`, superseded rather than corrected, and a reader who reaches it
reads the Note of 2026-09-07 with it. The section's decision table
(`:1295-1300`) and the code's own restatement of decision 2
(`lib/statifier_blocks/environment.ex:263-273`) are what the accepted decision
says, and they agreed with the code before this flip and agree with it now.

`RQ-SF036-0a` was ruled on the same date and changed nothing here: seeding is
root-forward, which is what the first two rows of the table already said.

### 2. What else the flip verified against `main`

Part 1 held in every particular checked.
`t:StatifierBlocks.Environment.type_expr/0` admits `{:shape, [member()]}` with
`member/0` beside it
(`lib/statifier_blocks/environment.ex:104`, `:107`); `inline_shape/1` builds
the term from a stored member list (`:521-529`);
`t:StatifierBlocks.BlockType.path_type/0` is still that typespec under a
second name and its prose names the inline arm and the assembled envelope as
its third source (`lib/statifier_blocks/block_type.ex:163-176`); the
`:type_mismatch` tuple did **not** grow
(`lib/statifier_blocks/assignability.ex:126-127`); and the editor's typed cells
still read the value-kind projection
(`lib/statifier_blocks/datamodel.ex:572-578`, reached at
`lib/statifier_blocks/editor.ex:2098-2101`), which is the one place part 1's
consumer table cites `path_types/1` correctly.

Part 2 held in every particular except the superseded sentence. The seed is
applied once, before the walk, in `seed_annotated/3` (`:760-763`) reached from
`annotated/4` (`:185-206`) and `seed/3` (`:298-301`), and nowhere else in
`lib/`; decision 2's entry-block subject is applied over it (`subject_seed/3`,
`:765-771`); a block's write replaces a seeded entry for every position after
it by decision 1's last-write-wins and by no new rule
(`seed/3`'s moduledoc, `:279-282`); a parked fragment is still walked from an
empty environment (`slot_start/4`, `:627-634`); `t:.../annotated/0`'s writer
member carries the `:declaration` inhabitant the section adds (`:125-127`),
which `t:StatifierBlocks.Assignability.upstream_ref/0` admits beside
`:slot_entry` (`lib/statifier_blocks/assignability.ex:112`); and the two
callers that supply `:datamodel` still supply it
(`lib/statifier_blocks/compiler.ex:837-845`,
`lib/statifier_blocks/editor.ex:2038-2040`).

One sentence of part 2 is a reading of the state **before** `sb-1jcr` built the
seed, and is met rather than falsified: it says the environment's "sole reader
of `ctx[:datamodel]` is `declarations/1`". That was true when the section was
drafted and is the property the section exists to change; today
`declared_seed/1` reads it too (`:788-794`), which is the section's own
decision in force. The sentence describes the case for the amendment, not the
state it leaves behind.

### 3. Sentences of the two Notes above that this flip dates

Both Notes of 2026-09-07 above are dated records of the state at their date and
neither is edited here. Three of their sentences are met by this flip where
they stand:

| Where | What it says | How the flip meets it |
|---|---|---|
| `:1480` | part 2 "stays at `proposed`, and part 1 stays with it: the two parts share one `Status:` line" | The shared `Status:` line is what this request flips, and it flips both parts together, which is what that sentence asks for |
| `:1566-1567` | "It flips nothing. The amendment at `:1186` still reads `Status: proposed`, and `sb-wzoa` remains the request that carries its flip" | True of that Note, which flipped nothing. `sb-wzoa` is this request, and it has now carried the flip |
| `:1703` | "It flips nothing. The Amendment at `:1186` still reads `Status: proposed` and `sb-wzoa` still carries its flip" | The same, of the Note of 2026-09-07 that released the hold |

### 4. Cites that moved again since the census of 2026-09-07

The census in the Note at `:1417` was taken at `f750b3b`. Two commits have
moved lines under it since: `4b0520e` rewrote the comment above
`declared_seed/1` (prose only, no behaviour), and `495e8b0` shortened
`editor.ex`. The rows that moved:

| Read at `f750b3b` | Reads at `495e8b0` |
|---|---|
| `lib/statifier_blocks/environment.ex:759-762` (`seed_annotated/3`) | `:760-763` |
| `lib/statifier_blocks/environment.ex:764-770` (`subject_seed/3`) | `:765-771` |
| `lib/statifier_blocks/environment.ex:781-787` (`declared_seed/1`) | `:788-794` |
| `lib/statifier_blocks/environment.ex:789-795` (`seeded_entry/1`) | `:796-802` |
| `lib/statifier_blocks/environment.ex:801-808` (`declared_spelling/1`) | `:808-814` |
| `lib/statifier_blocks/editor.ex:2053-2055` (`assignability_context/1`) | `:2038-2040` |
| `lib/statifier_blocks/editor.ex:2113-2116` (`declared_path_types/1`) | `:2098-2101` |

Every other row of that census still reads where it says it reads.

### What this Note does not do

- **It settles nothing new.** The projection question was settled by the second
  Note of 2026-09-07 above (`:1577`) under `RQ-SF036-0b`; this Note flips
  a status word on the strength of that settlement and decides nothing itself.
- **It edits no clause and removes no line but the status word.** The
  superseded sentence at `:1283-1288` stands, and both Notes above stand.
- **It changes no code.** The request that carries it touches this file only.

Filed with `sb-wzoa`, campaign SF036's Lane X. `sb-vjjl` is the next request on
this record.
