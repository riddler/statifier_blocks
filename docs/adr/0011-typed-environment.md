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

**One reading the code now settles that this record's Note of 2026-09-06
had the other way round.** That Note's reading 6 says "The three other
bare-identifier refusals the decision deliberately did not reach are still
in place, still deferred". Two of the three are no longer in place; the
sentence is historical as of `sb-r313` and the citations beside it -
`lib/statifier_blocks/core/invoke.ex:299` and
`lib/statifier_blocks/invoke_step.ex:430` - now land on the shared helper's
call sites rather than on a refusal of their own.

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
