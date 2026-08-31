# ADR-0006: The datamodel document is a typed, three-scope declaration, and the declared-path set is its projection

Status: accepted (2026-08-29, unqualified direction-agent verdict under the operator campaign-015 gate grant, PR 101).
Every consumer named below is written against the declared-path *set*, which
already exists as an accepted contract (ADR-0005, 11f).

## Context

Two accepted records of 2026-08-29 depend on "the host-supplied datamodel" and
neither defines it, on purpose.

ADR-0002 decision 7's amendment admits an optional `datamodel_path?: true` key
on a field declaration, "declaring that the field's value is a path into the
host's datamodel". ADR-0005's amendment 11e checks such a field against that
datamodel and produces an `:info` finding for a path it does not declare, and
11f states the deferral in as many words:

> The input shape is not this record's to fix. The shipped editor takes an
> optional datamodel that normalizes to a set of declared paths, which is the
> whole contract this check needs; the typed, scoped datamodel *document* is a
> separate Proposed record (`sb-g8m`), and the declared-path set is derivable
> from it by one total function. This section is written against the set, so it
> holds under either.

This is that record. It owes exactly two things: the document shape, and the
function 11f promised.

**What exists today.** `spike/fixtures/datamodel.json` carries the shape the
spike's datamodel panel and condition editor read, and its own header says it
is unratified: "Not an ADR-0001 artifact: no accepted record defines a
datamodel document yet, so this shape is the spike's proposal". The spike held
it to one invariant, walked by hand in both directions when the fixtures were
written (sb-ajk): every datamodel path named in a `cond` in `documents/*.json`
resolves to an entry in it.

**What does not exist.** `StatifierBlocks.Predicates` has no declaration type to
reuse. Its `context()` type is a string-keyed map of *values*, and `context/1`
folds a `%{dotted_path => source_text}` map into one by evaluating each source
through predicator. A binding context says what a path is worth in one
situation; it never says which paths a host declares. "Reuse `Predicates`' type"
and "ratify the spike's typed shape" are two different acts, and only the second
one is available.

**Why now.** `sb-oiq` reserved the module name
`StatifierBlocks.Predicates.Datamodel` for a path/type index and deliberately
did not build it while nothing consumed a *type*. With 11e shipped, two
consumers exist - the editor's undeclared-path check (paths only) and the index
(types too) - and they must not read two different documents.

## The check against sui ADR-0006, done first

The ruling required this cross-check before proposing anything, so that the
family does not grow two datamodel vocabularies. It was done, and the answer is
that there is no shape here to adopt.

`sui-ADR-0006` (datasets and expression fixtures, accepted 2026-08-16) adds two
optional keys to statifier-ui's fixture bundle: **datasets**, "named, reusable
datamodel records - each a name ... mapped to an example datamodel for that
situation", and **expressions**, each a predicator source string plus an
`expect` map keyed by dataset name. It says of itself, under "What this decision
does not do":

> It does not add a schema language, for the same reasons as ADR-0003: datasets
> are examples, expectations are values, and a schema layer stays
> optional-later.

So the two records name different kinds of thing, and the distinction is the
same one sui-ADR-0006 already draws between a scenario and a dataset, taken one
level further:

| | `sui-ADR-0006` dataset | This record's document |
|---|---|---|
| Kind | an instance - one situation's values | a declaration - which paths exist and of what type |
| Cardinality | many per chart, named | one per host context |
| Answers | "what is `card.brand` here?" | "is `card.brand` a thing at all, and is it a string?" |
| Consumer | evaluation, truth tables, `expect` checks | completion, the 11e undeclared-path advisory, `sb-oiq`'s index |
| Owner | statifier-ui | statifier_blocks (below) |

**Adopting sui-ADR-0006's shape is not an available option**, because its shape
for a datamodel is "an example datamodel", left deliberately unschematized. A
record cannot adopt an abstention. The family does not grow a second vocabulary
because this record adds no second word for anything sui-ADR-0006 named: it
names a declaration, which sui-ADR-0006 explicitly declined to name.

**What is shared, and stays shared:**

- **The word.** "Datamodel" means the same thing in both records - the
  host-supplied record a chart's conditions read. A dataset is an example of
  one; this document is a description of one.
- **The addressing.** Dotted paths, written exactly as a condition writes them,
  read by the same predicator grammar in both packages. Neither package invents
  a path syntax.
- **The type floor.** No floats anywhere (ADR-0001 decision 6); money is integer
  minor units and a decimal is carried as a string. This record's type set
  respects it, so a dataset that is well-formed against this document is also a
  legal ADR-0001 value.

**The seam this opens, deliberately not taken here.** A sui dataset could be
checked against this document - well-formed when every path it binds is
declared and every value matches the declared type - which would give
sui-ADR-0006's `expect` machinery a second kind of executable check. That is a
statifier-ui decision about statifier-ui's loader, on a record this one does not
own, and it is carried as an open question rather than proposed.

## Decision

**1. A new record, not an amendment.** The datamodel document is not a claim any
existing record's subject covers. ADR-0002 is about block-type behaviour, and
the datamodel is not a block type's claim about itself - decision 7's amendment
is careful to say only that a *field* may point into a datamodel, and its own
consequences insist that "The schema is still not a validation language."
ADR-0005 is about the editor, and the document outlives it: `sb-oiq`'s index
is not an editor consumer. A lettered amendment section would also put a
Proposed status inside a record whose status line already carries four
accepted amendments,
which is exactly the reading hazard the amendment convention exists to avoid.

*On the number.* This is `sb-ADR-0006` and there is an unrelated
`sui-ADR-0006`. The `docs/adr/README.md` citation rule already handles it: "A
bare `ADR-NNNN` cites this repository's own records; a cross-repo citation
carries the owning repo's beads prefix". Skipping a number to dodge the
coincidence would break the next-number rule for a collision the convention
already resolves.

**2. statifier_blocks owns the datamodel document.** By the umbrella's
contract-ownership rule - the repository whose files change owns the decision -
every file that would change to add, read, or check this document is here: the
`datamodel_path?` annotation (ADR-0002 decision 7), the 11e check
(ADR-0005), the editor's datamodel assign and pane, and `sb-oiq`'s index.
Neighbours keep what they already own: statifier-ui owns datasets, the fixtures
contract, and the wire format; statifier-ex owns the engine's runtime datamodel
and the interpreter contract. **Nothing in this record reaches the engine.** The
document is an authoring-time declaration; the compiler does not read it, no
SCXML carries it, and no interpreter is asked to honour it.

**3. The shape.** A datamodel document is a map with two keys:

- `version` - an integer, starting at `1`.
- `scopes` - a list of exactly three scope maps, in order: `global`, `local`,
  `event`.

A **scope** carries `scope` (one of the three names), `label`, `description`,
and `entries`, a list of entry maps.

An **entry** carries four required keys - `name`, `path`, `type`, `label` - and
four optional ones:

| Key | Required | Meaning |
|---|---|---|
| `name` | yes | the entry's own key, unique among its siblings (see the open question on event-scope spelling) |
| `path` | yes | the full dotted string a condition writes, absolute and globally addressable |
| `type` | yes | one of the eight types below |
| `label` | yes | the human-readable name a pane renders |
| `fields` | no | for `object`: a list of entries, recursively, one nesting level deeper |
| `item_type` | no | for `list`: the type of an element |
| `example` | no | one example value, for panes and documentation |
| `note` | no | prose for a reader; carries no contract |
| `one_of` | no | a completion hint listing the values a host expects |

**4. Eight types, and no floats.** `string`, `integer`, `decimal`, `boolean`,
`datetime`, `duration`, `object`, `list`. `decimal` is carried as a string and
`datetime` and `duration` as ISO-8601 strings, per ADR-0001 decision 6, which
forbids floats so that decision 8's byte-identical canonical form stays
achievable. The set is **closed**, on the same reasoning ADR-0002 decision 7
gives for its field types: a closed set is what keeps the rendering table
finite. A ninth type is a widening amendment with a real member to name.

**5. Three scopes, because they differ in lifetime, not in kind.** `global` is
host-owned and the same for every run of every chart; `local` is chart-local,
one per run, written by the chart's own steps as it goes; `event` is the payload
of the event being handled. The distinction is what a pane groups by and what
tells an author whether a value will be there before the chart starts.

**Event entries carry the prefix in their own `path`.** An event entry's path is
`event.<event_name>.<field>` - the prefix is part of the stored path, not
something a consumer prepends. Only the entry matching the event in flight is
populated at runtime; declaration is static and describes all of them. This is
what keeps decision 6's function a projection rather than a rewriting, and it is
what makes every path in the document globally addressable by construction.

**6. The declared-path set, by one total function.** This is what 11f was
promised.

```elixir
@spec declared_paths(document()) :: MapSet.t(String.t())
def declared_paths(%{"scopes" => scopes}) do
  scopes
  |> Enum.flat_map(fn scope -> scope["entries"] end)
  |> Enum.flat_map(&entry_paths/1)
  |> MapSet.new()
end

defp entry_paths(entry) do
  [entry["path"] | Enum.flat_map(entry["fields"] || [], &entry_paths/1)]
end
```

In prose: **every entry contributes its own `path`, at every nesting depth, and
nothing else does.** An `object` entry contributes its own path *and*,
recursively, its fields'. A `list` entry contributes its own path only -
`item_type` names an element type, and no record decides an index syntax, so
there is no element path to contribute. Scope names contribute nothing, because
paths are already absolute; annotations, labels, examples and types contribute
nothing, because the codomain is a set of strings.

**Total, and what that claims.** The function is total over the documents this
record admits: the recursion is over a finite tree and terminates; every clause
returns a list for every admitted input; there is no error return and no partial
case. The empty-entry document projects to `MapSet.new()`, which is a different
value from `nil`: `nil` is *no datamodel supplied*, and at 11f the check does not
run at all. `MapSet.new()` is a host claim - the host supplied a datamodel and
declared nothing - so every `datamodel_path?: true`-annotated path in the
document is undeclared and earns its `:info` advisory. Only the `nil` case is
quiet. Neither is a failure, and the two stay distinguishable at the call site.
Totality is over *admitted* documents: a malformed input is a loader concern,
rejected before this function is reached, which is why the function has no
`{:error, _}` arm to explain.

**One direction only.** The document projects onto the set; the set does not
lift back to a document. That asymmetry is why the document is the artifact this
record proposes and the set is its image, not the other way round.

**7. The document is open to per-path annotations, in the boolean convention.**
`sb-4e0` is drafting, as a sibling section on ADR-0002 beside the decision-7
`datamodel_path?` sentence, the rule that secrets never enter a datamodel, with
a declared path carrying `sensitive?: true` to mark a value a host insists on
describing so the compiler can refuse it where it would leak. **That rule is not
drafted here and this record does not decide it.** What this record states is
only that the entry map is where such a flag lives, that it follows the same
optional-boolean convention as ADR-0002's `required?` and `datamodel_path?`, and
that decision 6's projection **deliberately drops it**: a consumer that needs to
know whether a path is sensitive reads the document, never the set. The
declared-path set is paths and nothing else, and a consumer that needs more than
paths is a consumer of this document.

**8. `version` is its own axis and stays at 1.** It versions this record's
envelope, and it is not ADR-0001's `schema_version` (the block document's), not
`revision` (the host's editing counter), and not `type_version` (a block type's).
Adding an optional key is not a bump, on the rule `sui-ADR-0006` adopts from
`sui-ADR-0005` for its sidecar: consumers ignore unknown keys, additive change
is not a version bump, and a bump means a consumer of the old version would
misread the file. A consumer that ignores a key it does not know misreads
nothing. ADR-0001 decision 7 sets the neighbouring rule for its own axes -
`schema_version` "bumps only when this record is amended in a way that changes
bytes" - and the two agree in effect here.

**9. Advisory, never a gate.** An undeclared path is **unknown, not wrong**.
This record adds no compile-time check, no validation verdict, and no refusal.
11e's `:info` finding is the strongest thing anything is permitted to do with a
path this document does not declare, and it changes no verdict by construction.
Any future refusal - `sb-4e0`'s is the one in flight - is its own record's
claim, argued there, and does not follow from this one.

### Worked shape

Credit-card processing, one entry per kind:

```json
{
  "version": 1,
  "scopes": [
    {
      "scope": "global",
      "label": "Global",
      "description": "Host-owned. The same for every run of every chart.",
      "entries": [
        {
          "name": "limits", "path": "limits", "type": "object", "label": "Limits",
          "fields": [
            {"name": "authorization_window", "path": "limits.authorization_window",
             "type": "duration", "label": "Authorization window", "example": "PT15M"}
          ]
        }
      ]
    },
    {
      "scope": "local",
      "label": "Chart-local",
      "description": "One per run. Written by the steps of the chart as it goes.",
      "entries": [
        {"name": "amount_cents", "path": "amount_cents", "type": "integer",
         "label": "Amount (minor units)", "example": 42350},
        {"name": "risk_reasons", "path": "risk_reasons", "type": "list",
         "item_type": "string", "label": "Risk reasons",
         "example": ["velocity", "new_device"]},
        {
          "name": "card", "path": "card", "type": "object", "label": "Card",
          "fields": [
            {"name": "brand", "path": "card.brand", "type": "string", "label": "Brand"},
            {"name": "last4", "path": "card.last4", "type": "string", "label": "Last four"}
          ]
        }
      ]
    },
    {
      "scope": "event",
      "label": "Event payload",
      "description": "The payload of the event being handled.",
      "entries": [
        {"name": "event.name", "path": "event.name", "type": "string", "label": "Event name"}
      ]
    }
  ]
}
```

`declared_paths/1` of that document is exactly:

```
limits, limits.authorization_window, amount_cents, risk_reasons,
card, card.brand, card.last4, event.name
```

Eight paths from five top-level entries: the two `object` entries contribute
themselves and their fields, the `list` contributes itself alone.

Signup wizard, for 11e's advisory: a host declares `signup.variant_id` and
`signup.step`; a `core.assign` block's `path` field, annotated
`datamodel_path?: true`, holds `signup.variant`. `"signup.variant"` is not in
`declared_paths/1`'s output, so the editor anchors one `:info` finding on that
block's `path` key. The author fixes the typo or extends the datamodel; nothing
is blocked either way, and the document compiles as it did before.

## Consequences

- 11f's promise is discharged in the only way that keeps 11e intact: the check
  keeps consuming a set, and gains a defined way to get one. A host that has
  only a set keeps working, because the set was always the contract; a host that
  has a document gets completion, types, labels and grouping as well.
- `sb-oiq` gets the record it was waiting for, and gets it as a *document*
  rather than as a shape reverse-engineered from a fixture. Its stated stance -
  an undeclared path is unknown, never wrong, and the index must not become a
  validation gate without a record saying so - is decision 9 here, so the two
  cannot drift.
- `spike/fixtures/datamodel.json` stops being an unratified proposal and becomes
  an instance of an accepted record. It is not edited by
  this record and does not need to be: the shape above is the shape it already
  carries. Its `_comment` header claim ("no accepted record defines a datamodel
  document yet") is now false, and correcting it
  belongs to whichever bead touches the spike next - `spike/` is not this bead's
  to edit.
- Two `ADR-0006`s now exist in the family, on unrelated subjects. The citation
  convention covers it, but any prose that says "ADR-0006" without a prefix in a
  cross-repo context is now ambiguous where it was merely unqualified before.
- The document is a second input the editor may or may not have, alongside the
  palette. 11f already accepted that shape of cost ("The check is conditional on
  an input, which is a shape no other finding has"); this record does not add a
  new one, but it does make the conditional input larger and therefore more
  worth caching than a set was.
- A closed type set means a host with a value this record cannot type - a
  binary, a geo point, an arbitrary map - either declares it as `object` with no
  fields, or does not declare it, and takes an `:info` advisory on every path
  under it. That is a real cost of decision 4, accepted for the finiteness the
  closed set buys, and the escape hatch is a widening amendment rather than a
  loophole.

## Alternatives considered

- **A lettered amendment section on ADR-0002.** The ruling admitted this as an
  option. Rejected on subject: decision 7 owns a *field's* claim about itself,
  and this document is the host's claim about its own data, which no decision in
  that record covers. It would also nest a Proposed section under a record whose
  status line already carries four accepted amendments.
- **An amendment on ADR-0005.** Rejected: the editor is one consumer of two, and
  the record would then own a contract its own 11f explicitly pushed out.
- **Adopt sui-ADR-0006's dataset shape as the declaration.** Rejected because
  there is nothing to adopt: that record's datasets are example *values* and it
  declines a schema layer in its own words. Reusing the key would give one word
  two meanings across two packages, which is precisely the second vocabulary the
  ruling asked to prevent.
- **Make the declared-path set the primary artifact, with the typed document a
  view of it.** Rejected: the projection runs one way. A set cannot produce
  types, labels, scopes or nesting, so this trades the artifact for its own
  image.
- **A flat `%{path => type}` map, no scopes.** Simpler, and it would satisfy
  `sb-oiq` alone. Rejected: it loses the lifetime distinction an author needs
  (is this value there before the chart starts?), loses labels and ordering the
  pane renders, and loses the recursive `fields` structure that makes an object
  and its members one entry rather than several unrelated rows.
- **Scope-qualified paths (`local:card.brand`).** Rejected: paths are already
  globally addressable, and qualifying them would give one value two names -
  one in the document and one in every condition an author writes.
- **`list` entries contributing an element path (`risk_reasons[]`).** Rejected
  as a vocabulary invented ahead of its consumer: no record decides an index or
  wildcard syntax, and predicator's grammar is not this record's to extend.

## Open questions carried, not resolved here

- **How `example` values spell the non-native types.** This record's examples
  follow ADR-0001 decision 6's config spelling - `"PT15M"` for a duration, an
  ISO-8601 string for a datetime - which is also what the spike fixture
  carries. `sui-ADR-0006` encodes expected values with the reserved
  `$`-prefixed shapes (`{"$duration": {...}}`, `{"$datetime": ...}`) inherited
  from `sui-ADR-0005`'s wire format. Both are defensible - `example` is
  documentation, not a wire value - but the family should not carry two
  spellings for one duration without saying so on purpose. Named here rather
  than decided, because the wire-format spelling is statifier-ui's to rule on.
- **Whether a sui dataset is validated against this document** (the seam in the
  cross-check above), and if so whether the loader or the consumer does it.
  statifier-ui's call, on its own record.
- **Whether `one_of` is a hint or a claim.** Carried here as a completion hint
  with no contract, matching the spike fixture's use on `fraud.verdict`. If a
  consumer ever wants to advise on a value outside the list, that is a decision
  about a second producer of findings, not a change to this shape.
- **Delivery.** Whether the document arrives as a behaviour callback, a JSON
  sidecar, or a plain editor assign. The editor's accepted contract is an assign
  (11f); statifier-ui's fixture bundle has a two-path convention (`sui-ADR-0003`)
  that a host might reasonably expect to mirror. Undecided, and nothing above
  depends on the answer.
- **Sibling annotations.** `sb-4e0`'s `sensitive?: true` rule, and where its
  section lands once this record's status settles. Decision 7 above says only
  that such a flag has a home and is dropped by the projection; the rule itself
  is that bead's to draw.
- **How an event entry spells its `name`.** The spike fixture writes both
  `name` and `path` with the prefix (`"name": "event.name"`), which reads
  against the sibling-key description above; a top-level `local` entry writes a
  bare segment for `name` and the same string for `path`. Either the event
  scope's `name` is the full prefixed string or it is the bare segment and only
  `path` carries the prefix. Nothing consumes `name` today - decision 6's
  projection reads `path` alone - so this is left where the fixture put it and
  named here rather than tidied silently.
- **Name collisions across scopes.** Paths are global, so a `local` entry named
  `event` would shadow the `event` scope's prefix. No fixture does this and no
  consumer would survive it; whether the document forbids it structurally or a
  loader lints it is left open, since both answers need a loader that does not
  exist yet.

## Note (2026-08-31): a second thing in this repository is now spelled `datamodel`

A dated note rather than an amendment, recorded for `sb-ao6l` under
campaign-022 ruling R3: nothing in this record changes, and the note exists
only because this record's cross-check section took on the job of keeping
the family's datamodel vocabulary countable.

ADR-0001's Amendment (2026-08-31), decision 11, adds an optional top-level
envelope key to the block document, and the key is named `datamodel`. The two
are told apart in one sentence each: **this record's datamodel document** is
the host's typed, three-scope, advisory description of the data universe an
author writes conditions against, which no compiler reads and no SCXML
carries; **ADR-0001's `datamodel` key** is the block document's own ordered
declaration of the `<data>` roots it needs to exist at run time, which is
compiled, emitted, and hashed. A description of a vocabulary versus a
declaration of storage; that amendment's 11g clause carries the full
reconciliation, including the correspondence (an entry `id` there is what
this record calls a top-level `local`-scope entry's `path`) and the open
question of whether such a root counts as declared for ADR-0005's 11e
advisory - which is ADR-0005's to answer, not this record's.

Nothing in this record changes: the shape, the projection, decision 9's
"advisory, never a gate", and every open question above stand exactly as
written.
