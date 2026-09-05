# ADR-0001: The block document is a tree of typed blocks with named slots

Status: accepted (2026-08-26); fetch_path/2 doc line amended (2026-08-27); document datamodel declaration key amendment, decision 11 (accepted 2026-08-31)

## Context

This package upstreams the headless core of a block authoring experience:
a host builds workflows out of a palette of blocks, and the block document
is compiled one-way into SCXML that `statifier` runs. The block document is
authoritative; SCXML is generated. There is no reverse edge, so the document
schema is the thing hosts store, migrate, diff, and version - it outlives
every compiler and every editor built on it.

Three forces bind the shape of that document.

**The engine's document is a tree.** SCXML nests: compound states contain
states, `<parallel>` contains regions, `<history>` is a child of the state
it remembers, and a transition on a compound state interrupts everything
beneath it. Statifier ports that faithfully - `lib/statifier/document.ex`,
`lib/statifier/machine/state.ex`, and the Appendix-D interpreter
(st-ADR-0002) all speak in terms of nested states and their descendants. A
flat list of steps with edges between them is a different data structure
that would have to be re-derived into a tree at every compile, and the
derivation would be lossy in exactly the places statecharts earn their keep
(hierarchy, regions, history, interrupts).

**Expressiveness has to arrive by nesting, not by re-architecture.** The
first structural blocks a host needs are a sequence and a branch. The next
ones - parallel lanes, a resumable group, a wait, an interrupt rule on a
group - are the ones that make the difference between a step runner and a
statechart. If the schema is a tree of typed blocks with named slots from
day one, every one of those arrives as a new block type over an unchanged
document schema. If it is not, each arrives as a schema migration and an
editor rewrite.

**The document is stored by a multi-tenant host embedding the engine.** It
lives in the host's database, is edited concurrently, is reviewed by humans
in diffs, and is loaded back by code that must not trust its bytes. That
rules out Elixir-only, opaque, or atom-minting encodings, and it makes a
deterministic canonical form worth paying for: the compiler (sb-iwz) needs
a stable document identity to promise deterministic state ids, and the
family already establishes content-hash identity as the way that is done
(st-ADR-0052).

This record fixes the document's shape and its serialization. It
deliberately stops at the point where a block type's own contract begins:
what a block type declares, how a slot's contents are type-checked, how the
tree becomes SCXML, and how the editor mutates it are ADRs of their own
(sb-5n0, sb-7rx, sb-iwz, sb-w50). This ADR only guarantees that the
document shape can host them.

## Decision

**1. A document is a single tree of blocks, rooted in one block.** Every
document has exactly one root block, conventionally a `core.sequence`, so
tree invariants are uniform and no code has to special-case a forest. A
block appears in exactly one place: the structure is a tree, not a DAG, and
there is no sharing or referencing of one block from two parents. Reuse is
by copy - which mints new ids (decision 3) - because SCXML has no sharing
either, and admitting it here would only defer the copy to compile time,
where it would have to rewrite ids and break provenance.

**2. A block is `{type, id, config, slots}` and nothing else.**

- `type` names the block type (decision 4).
- `id` is the block's stable identity within the document (decision 3).
- `config` is a JSON map the block type owns and this layer never
  interprets (decision 6).
- `slots` maps slot names to ordered lists of child blocks (decision 5).

No field is added for layout, selection, collapse state, validation
results, generated SCXML, or the provenance map. Every one of those is a
function of the document plus a block-type registry, and a derived value
stored in the document is a derived value that can be wrong. The document
is the minimum that must round-trip.

**3. Block ids are stable, opaque, document-unique, and never reused.** An
id is minted once when a block is inserted and travels with the block for
the rest of its life: moving a block between slots, reordering it, or
editing its config all preserve it. Duplicating a block mints a new id.
Deleting a block retires its id permanently within that document. Ids are
`blk_`-prefixed UXIDs, following the family's identifier convention
(st-ADR-0008); this layer treats them as opaque strings and never parses
them.

The stability rule is what makes everything downstream possible: the
compiler's provenance map keys on block ids (sb-iwz), so a document edited
in one place must not renumber the state ids generated for every other
block. The no-reuse rule is what keeps a provenance map or a diagram
captured against an older revision from silently aliasing a different block.

An id is meaningful only inside its document. Anything that names a block
from outside carries the document id alongside it.

**4. A block type is referenced by a namespaced string name, not a
module.** `"core.sequence"`, `"core.branch"`, `"myapp.authorize"`. The
document must survive a host renaming or moving the module that implements
a palette entry, and an encoded Elixir module name in stored bytes makes a
refactor a data migration. The `core.*` namespace is reserved for the block
types this package ships; a host embedding the engine namespaces its own
palette. Resolving a name to an implementation is the registry's job
(sb-5n0).

Each block also carries `type_version`, a positive integer the block type
owns. This layer never compares it to anything; it exists so that a block
type changing the shape of its own `config` can find and migrate the nodes
it needs to, without every such change becoming a bump of the document
schema version.

**5. Slots are named, ordered, declared by the block type, and may be
parameterized by config.** A slot has a name (a string), and its contents
are a list of blocks whose order is semantically meaningful - adjacency
within a slot is sequencing, which is why the editor needs no explicit
wiring between steps.

Slots are *named* rather than a single anonymous children list because a
block frequently has children with different meanings. A group's `body` and
its `interrupts` are the motivating case: both are lists of blocks nested
inside the same group, and they compile to entirely different things (the
group's contents versus transitions out of the group). One children list
would force that distinction into config or into positional convention.

The set of slot names a block carries is declared by its block type *given
that block's config*, not statically. A branch has one slot per arm plus
`otherwise`; a parallel block has one slot per lane; both are numbers the
author chooses. The document representation stays uniform regardless -
`slots` is always a map of name to list - and the arity a block type
declares for a slot (exactly one child, any number) is a validation rule
applied against that uniform shape, never a change to it.

A block's position is therefore fully described by `{parent block id, slot
name, index}` - its *path*. Paths are derived by walking the tree; they are
never stored, because unlike ids they change under ordinary edits.

Renaming a slot is a breaking change to that block type's contract and
requires the type to migrate its own documents, exactly like a config shape
change.

**6. `config` is opaque here, JSON-shaped, and never atom-minting.** This
layer validates that `config` is a map of string keys to JSON values and
nothing more; what those values must be is the block type's config schema
(sb-5n0). Decoding a document never calls `String.to_atom/1`, constructs no
structs from the wire, and admits no funs, pids, refs, or tuples - a
document is untrusted input from this layer's point of view.

Canonical form additionally forbids floats in config. A number is an
integer; anything fractional is carried as a string, as durations already
are. This is not a data-model opinion, it is what makes decision 8's
byte-identical canonical form achievable without a floating-point
formatting contract.

**7. Two independent version axes, and a third that is not this layer's.**

- `schema_version` on the document is the version of *this ADR's envelope*
  - the node shape, the slot representation, the canonical encoding rules.
  It starts at `1` and bumps only when this record is amended in a way that
  changes bytes. It is not a version of anyone's palette.
- `revision` on the document is the host's monotone editing revision of
  that particular document, incremented on each saved edit. It gives the
  editor optimistic concurrency and gives a compiled artifact something to
  name.
- `type_version` per block (decision 4) is the block type's own axis.

`metadata` is a JSON map for host-owned document annotations - a name, a
description, timestamps the host wants inside the document rather than
beside it. This layer neither reads nor requires any key in it.

**8. JSON is the canonical form, and the canonical encoding is
deterministic.** Not Erlang term format: the document is stored, diffed,
reviewed, and potentially read by non-Elixir tooling in the host, and an
opaque blob forecloses all of that. The encoding rules are:

- object keys sorted by their UTF-8 bytes;
- no insignificant whitespace;
- empty slots omitted rather than encoded as `[]` (a missing slot reads
  back as an empty list);
- empty `config` and `metadata` omitted;
- no floats (decision 6).

Two encodes of equal documents are therefore byte-identical, which makes
`:crypto.hash(:sha256, canonical_json)` a usable **document identity**.
That identity is what the compiler will build its determinism guarantee on;
how it relates to the engine's own chart identity (st-ADR-0052) is
sb-iwz's decision, not this one.

The round-trip law this schema is held to: for every valid document `d`,
`decode(encode(d)) == d`, and `encode(decode(encode(d))) == encode(d)`.

**9. Decoding is structural and registry-free.** `from_json/1` validates
the envelope and the tree - version, node shape, id uniqueness, slot value
shapes - and never consults the block-type registry. A document whose
palette entry a host has since removed still decodes, because refusing to
load a document is a far worse failure than showing an author an
unresolvable block. Unknown types surface at resolution and compile time,
with their own errors, in sb-5n0 and sb-iwz.

Refusals are typed and total, following the shape upstream already
establishes for loading untrusted persisted bytes (`Statifier.Position.from_binary/2`,
st-ADR-0052; sp-ADR-0003 decision 4): an ordered check, one error arm per
distinguishable cause, nothing rescued to a default and nothing raised.

**10. The core structural vocabulary this schema must host.** These are the
block types this package ships. Their contracts belong to sb-5n0 and their
SCXML emission to sb-iwz; they are named here only as the load the schema
is designed to carry, and each is listed with the schema feature it exercises.

| Block type | Slots | Schema feature it needs |
|---|---|---|
| `core.sequence` | `body` | ordered slot contents as sequencing; nesting as hierarchy |
| `core.branch` | one per arm, plus `otherwise` | config-parameterized slot sets (decision 5); conditions live in `config` as predicator expressions (st-ADR-0004) |
| `core.parallel` | one per lane | config-parameterized slot sets; sibling slots with no ordering between them |
| `core.wait` | none | a leaf block whose whole meaning is `config` |
| `core.resumable_group` | `body` | a group whose `config` carries a history mode; identical shape to `core.sequence` |
| interrupt rules | `interrupts` on a group | a *second, differently-meaning* slot on the same block - the reason slots are named |

Interrupt rules are deliberately not a block type of their own that wraps a
group. They are handler blocks in the group's `interrupts` slot, each
carrying its trigger in `config`, because that is the arrangement that
matches what they compile to: transitions on the group's state, which is
also the arrangement an author reads as "these can interrupt this".

## Consequences

- Adding hierarchy, lanes, history, waits, and interrupts to a host's
  palette does not touch the document schema. The `schema_version` axis
  should stay at `1` across the whole first phase of this package's life;
  if it moves early, this record was wrong.
- The compiler and the editor both get to assume a tree with stable ids:
  provenance keys on ids (sb-iwz), and every editor drag reduces to a
  move/insert/delete on `{parent id, slot name, index}` that is testable
  without a browser (sb-w50).
- A content hash over the canonical form gives documents an identity in the
  same style as the engine's chart identity, which is what the one-way
  compile needs to be reproducible.
- Storing no derived data means the host must recompute the provenance map,
  validation results, and layout on load. That is the intended trade: they
  are cheap, and a stale one is a correctness bug.
- Forbidding floats in `config` is a real constraint on block-type authors.
  A block type needing fractional numbers carries them as strings and
  parses them in its own schema.
- Because decoding never resolves types, a host can open, diff, and store a
  document containing blocks it cannot render. The editor has to have an
  unresolvable-block presentation; that is sb-w50's problem, and this
  record creates it on purpose.
- Tree-only means no shared subtrees. A host wanting a reusable sub-workflow
  gets it by some future mechanism that expands to a copy at authoring or
  compile time, not by a reference in the document.

## The schema as typespecs

```elixir
defmodule StatifierBlocks.Block do
  @moduledoc "One node of a block document."

  @typedoc "Any value expressible in canonical JSON. Note: no floats."
  @type json ::
          nil
          | boolean()
          | integer()
          | String.t()
          | [json()]
          | %{optional(String.t()) => json()}

  @typedoc ~S(Document-unique, stable, never reused. `"blk_" <> uxid`.)
  @type id :: String.t()

  @typedoc ~S(Namespaced block-type name, e.g. `"core.branch"`, `"myapp.authorize"`.)
  @type type_name :: String.t()

  @type slot_name :: String.t()

  @typedoc "Owned and interpreted by the block type; opaque to this layer."
  @type config :: %{optional(String.t()) => json()}

  @type t :: %__MODULE__{
          id: id(),
          type: type_name(),
          type_version: pos_integer(),
          config: config(),
          slots: %{optional(slot_name()) => [t()]}
        }

  defstruct [:id, :type, type_version: 1, config: %{}, slots: %{}]
end

defmodule StatifierBlocks.Document do
  @moduledoc "A block document: one tree, one envelope."

  alias StatifierBlocks.Block

  @typedoc ~S(`"bdoc_" <> uxid`.)
  @type id :: String.t()

  @type t :: %__MODULE__{
          schema_version: pos_integer(),
          id: id(),
          revision: non_neg_integer(),
          root: Block.t(),
          metadata: %{optional(String.t()) => Block.json()}
        }

  defstruct [:id, :root, schema_version: 1, revision: 0, metadata: %{}]

  @typedoc "Derived, never stored. Identifies a position, not a block."
  @type path :: [{Block.id(), Block.slot_name(), non_neg_integer()}]

  @doc "Canonical JSON per ADR-0001 decision 8. Deterministic."
  @spec to_json(t()) :: binary()

  @doc "SHA-256 over `to_json/1`. Stable document identity."
  @spec content_hash(t()) :: binary()

  @doc """
  Structural decode. Never consults the block-type registry
  (ADR-0001 decision 9); unknown `type` names decode successfully.
  """
  @spec from_json(binary()) ::
          {:ok, t()}
          | {:error, :not_a_block_document}
          | {:error, {:unsupported_schema_version, pos_integer()}}
          | {:error, {:duplicate_block_id, Block.id()}}
          | {:error, {:malformed_block, Block.id() | nil, term()}}
          | {:error, {:malformed_envelope, term()}}

  @doc "Walks the tree; `:error` when the id is absent (amended 2026-08-27:
  the prose previously said `nil`, contradicting this spec; the spec was
  always the normative content of this section and the shipped function
  follows it - the root answers `{:ok, []}`)."
  @spec fetch_path(t(), Block.id()) :: {:ok, path()} | :error
end
```

## Worked example

A published workflow in a multi-tenant host embedding the engine. It
authorizes a card transaction, branches on whether the account's remaining
budget covers the amount, and on the approved arm runs two lanes
concurrently - a capture, and a wait followed by a receipt notification.
The branch sits inside a resumable group carrying one interrupt rule, so a
cancellation event tears the whole group down and the group resumes where
it left off when re-entered.

```
core.sequence                           blk_01J...ROOT
└─ body
   ├─ myapp.authorize                   blk_01J...AUTH  (invoke myapp:authorize)
   └─ core.resumable_group              blk_01J...GRP   (history: deep)
      ├─ body
      │  └─ core.branch                 blk_01J...BR    (arms: ["approved"])
      │     ├─ arm_approved
      │     │  └─ core.parallel         blk_01J...PAR   (lanes: ["capture", "receipt"])
      │     │     ├─ lane_capture
      │     │     │  └─ myapp.capture   blk_01J...CAP
      │     │     └─ lane_receipt
      │     │        ├─ core.wait       blk_01J...WAI   (PT48H)
      │     │        └─ myapp.notify    blk_01J...NOT
      │     └─ otherwise
      │        └─ myapp.notify          blk_01J...NO2
      └─ interrupts
         └─ myapp.on_event              blk_01J...INT   (myapp.cancelled)
```

The canonical form, re-indented here for reading - the encoder emits it
with sorted keys and no whitespace, and the ids are abbreviated:

```json
{
  "datamodel": [
    {"description": "What the card's budget has left before this authorization.", "id": "budget_remaining"},
    {"description": "The amount being authorized.", "id": "amount"}
  ],
  "id": "bdoc_01JDOC",
  "metadata": {"name": "Card authorization"},
  "revision": 17,
  "root": {
    "id": "blk_ROOT",
    "slots": {
      "body": [
        {
          "config": {"invoke_type": "myapp:authorize", "timeout": "PT30S"},
          "id": "blk_AUTH",
          "type": "myapp.authorize",
          "type_version": 2
        },
        {
          "config": {"history": "deep"},
          "id": "blk_GRP",
          "slots": {
            "body": [
              {
                "config": {"arms": [{"cond": "budget_remaining > amount", "slot": "arm_approved"}]},
                "id": "blk_BR",
                "slots": {
                  "arm_approved": [
                    {
                      "config": {"lanes": ["capture", "receipt"]},
                      "id": "blk_PAR",
                      "slots": {
                        "lane_capture": [
                          {
                            "config": {"invoke_type": "myapp:capture"},
                            "id": "blk_CAP",
                            "type": "myapp.capture",
                            "type_version": 1
                          }
                        ],
                        "lane_receipt": [
                          {
                            "config": {"duration": "PT48H"},
                            "id": "blk_WAI",
                            "type": "core.wait",
                            "type_version": 1
                          },
                          {
                            "config": {"invoke_type": "myapp:notify"},
                            "id": "blk_NOT",
                            "type": "myapp.notify",
                            "type_version": 1
                          }
                        ]
                      },
                      "type": "core.parallel",
                      "type_version": 1
                    }
                  ],
                  "otherwise": [
                    {
                      "config": {"invoke_type": "myapp:notify"},
                      "id": "blk_NO2",
                      "type": "myapp.notify",
                      "type_version": 1
                    }
                  ]
                },
                "type": "core.branch",
                "type_version": 1
              }
            ],
            "interrupts": [
              {
                "config": {"event": "myapp.cancelled", "outcome": "abandon"},
                "id": "blk_INT",
                "type": "myapp.on_event",
                "type_version": 1
              }
            ]
          },
          "type": "core.resumable_group",
          "type_version": 1
        }
      ]
    },
    "type": "core.sequence",
    "type_version": 1
  },
  "schema_version": 1
}
```

[Correction 2026-09-02, sb-12qm: the listing above is re-printed from the
shipped fixture, `test/fixtures/documents/worked_example.json`, which is the
document `StatifierBlocks.DocumentFixtures.worked_example/0` builds and the
encoder and decoder are checked against. It previously carried no
`datamodel` key. The fixture gained one on 2026-08-31 (`sb-vjeg`, PR 191) -
`budget_remaining` and `amount`, the two roots this example's own branch
guard reads, declared through decision 11's document `datamodel` key - and
this listing did not follow. Nothing else in the printed document moves:
every other byte is the fixture's, `revision` is still 17 and
`schema_version` still 1, and the decisions the example is chosen to
demonstrate, listed below, are unchanged. The drift was illustrative only -
no test compares this listing with the fixture, and the document printed
here was valid either way - which is why it is corrected in place.]

What this example is chosen to demonstrate:

- **Nested groups.** `core.resumable_group` contains a `core.branch` which
  contains a `core.parallel` which contains a `core.sequence`-shaped lane.
  Depth arrives with no schema change; `blk_WAI` and `blk_NOT` sit adjacent
  in `lane_receipt` and are therefore sequential, with no wiring recorded.
- **Config-parameterized slots (decision 5).** `blk_BR` has slots
  `arm_approved` and `otherwise` because its config declares one arm;
  `blk_PAR` has `lane_capture` and `lane_receipt` because its config declares
  two lanes. Neither slot set is knowable from the type name alone.
- **Named slots earning their keep (decision 5).** `blk_GRP` carries `body`
  and `interrupts`. Both are lists of blocks under the same parent; they
  mean entirely different things, and no positional convention would say so.
- **Omission in canonical form (decision 8).** Leaf blocks carry no `slots`
  key at all rather than `"slots": {}`; the branch's arm slots that a
  second arm would add are simply absent.
- **Opacity of config (decision 6).** `"cond": "budget_remaining > amount"` is a predicator
  expression and `"duration": "PT48H"` is an ISO-8601 duration. This layer
  sees two strings. Note also that the 48 hours is *not* `48.0` - decision
  6's no-floats rule is why durations are strings here rather than numbers.
- **Registry-free decode (decision 9).** Every `myapp.*` block decodes
  structurally without this package knowing anything about the host's
  palette.

Round-tripping it is the acceptance property: decode the bytes above,
re-encode, and the bytes are identical; the decoded document equals the
document that produced them.

## Amendment (2026-08-31): decision 11 - the document declares its own `<data>` roots

**Status: accepted (2026-08-31, UNQUALIFIED direction-agent verdict, PR 188),
implementing bead `sb-ao6l`.** Drafted 2026-08-31 as a proposed amendment. Additive; nothing
above this line is edited, no accepted decision changes, and the header line's
status history is the conductor's to extend.

One label note before anything else. This decision letters its clauses
11a-11i, and ADR-0005's decision 11 letters its own clauses 11a-11j. Clause
labels scope to the record that mints them - that is already the family's
practice, which is why ADR-0004's F6 and P1 collide with nothing - so a bare
`11e` in this record means this record's, every citation of ADR-0005's clauses
below carries that record's name, and prose elsewhere in this repository that
writes a bare `11e` continues to mean ADR-0005's, exactly as it did when
written.

### What forces the amendment

ADR-0004's Note (2026-08-29), "where a `<data>` root declaration lives - the
`:declare` compile option", closed with two named follow-ups, "neither taken
here". The first, verbatim:

> **a document-level key**, under ADR-0001, if authors need to declare roots in
> the editor rather than the host declaring them at publish time. That is a
> schema change with a hash consequence, and it is ADR-0001's to make.

This amendment takes that follow-up and makes that change, under
campaign-022 ruling R3 and the ruling recorded on `sb-7moq` (2026-08-31):
"Documents should absolutely gain a rich declaration surface."

The forcing case is that note's own gap, seen from the author's side. Against
a strict engine an `<assign>` to an undeclared location and a `cond` reading
an undeclared id both raise `error.execution`, and the only declaration
surfaces today are the compile call (`:declare`) and a block that binds a name
for its own purposes (`core.foreach`'s `item_as`/`index_as`). A document whose
guards read a root no block binds cannot say so anywhere in the tree the
author edits: the requirement travels out of band, to every host, forever.
The note argued, correctly, that a host's declaration is "a property of the
*deployment*, not of the tree an author edits". But a declaration has a second
half the note did not have to face: the roots without which the document's own
expressions are nonsense on *every* host are a property of the document, and a
property of the document belongs in the bytes the author edits, the hash
covers, and a reviewer diffs. This amendment records that half and only that
half. The deployment half stays exactly where the note put it, and 11f below
is what keeps the two halves composable rather than competing.

### 11a. A new optional top-level envelope key, `datamodel`: an ordered list of declaration entries

The envelope of decision 7 gains one optional key, `datamodel`, an ordered
**list** of declaration entries. Absent reads as `[]`, exactly as a missing
slot reads back as an empty list under decision 8.

A list and not a map, because the order is load-bearing: it is the emission
order of the document's `<data>` elements within the chart's single
`<datamodel>`, and a list carries that order into the canonical bytes without
inventing a sort no guard reads. (Decision 8 sorts *object keys*; it says
nothing about list elements, and slot contents already rely on that - "empty
slots omitted", order preserved.)

The key sits on the envelope beside `metadata`, not on any block, because it
is a claim the whole document makes about the data its guards and assigns
address. No single block owns the claim - the root least of all, since the
root is an ordinary `core.sequence` whose config is its block type's - and a
claim stored on a block would move or vanish under ordinary tree edits that
change nothing about what the document reads.

In memory the field is `datamodel: [entry]` on `%StatifierBlocks.Document{}`,
defaulting to `[]`, where an entry is a small struct,
`%StatifierBlocks.Document.DatamodelEntry{id, expr, description}` - the
`%Block{}` precedent, not the `metadata` one: like a block, an entry has a
fixed shape this record owns, and a struct is what makes that shape a
compile-time fact. Decision 6's no-atom-minting rule is satisfied the way
`%Block{}` already satisfies it: the decoder builds the struct by literal
syntax over explicitly extracted string keys, and no key read from the wire
ever becomes an atom. An absent `expr` or `description` is `nil` on the
struct and an omitted key in the bytes (11d).

### 11b. An entry is `{id, expr, description}` and nothing else

- **`id`** - required. A bare lowercase identifier,
  `~r/\A[a-z][a-z0-9_]*\z/` - the same rule the `:declare` compile option
  applies and the same rule `core.invoke` applies to `assign_to`, because
  predicator's grammar is what both ends of the declaration have to agree on,
  and a third spelling of the rule would be a third place for it to drift.
- **`expr`** - optional. Absent (the root reads as `undefined` until
  something assigns it) or a non-empty string written verbatim into the
  emitted `<data expr="...">` attribute. The key is named `expr` and not
  `initial` deliberately: it is one word for one thing across the compile
  option, this key, and the SCXML attribute it becomes, and a reader moving
  between the three should never wonder whether two words name two behaviours.
  Run creation still wins over `expr` (SCXML 5.3.2) - a run seeded with a
  value for the id starts from that value. That is the engine's behaviour,
  unchanged and not this record's to touch.
- **`description`** - optional, a non-empty string, prose for a reader. Never
  compiled, never in the emitted SCXML, and it carries no contract - the same
  stance ADR-0006 takes for its `note` key ("prose for a reader; carries no
  contract"). It *is* in the canonical bytes (11d), and that has a
  consequence 11d states out loud.

No `type`, no `label`, no `one_of`, no `sensitive?`. Every one of those words
is already spoken for by ADR-0006's entry shape, and admitting any of them
here would grow a second, thinner datamodel vocabulary beside ADR-0006's -
the precise outcome that record's cross-check section exists to prevent. 11g
draws the line in full.

### 11c. Ids are unique within the key, structurally

A repeated id is `{:malformed_envelope, {:datamodel, {:duplicate_id, id}}}`
from the structural validation pass (`StatifierBlocks.Validation`, surfaced
through `from_json/1` and `Document.to_json/1`'s boundary) - the envelope's
analogue of decision 3's document-unique block ids.

This is where the document deliberately differs from the compile option. The
option's repeated id is an Emit-stage refusal (ADR-0004's note: "an id the
option lists twice ... refused as an Emit-stage finding against the root
block"), because there is no stored artifact to call invalid - the option
exists only inside one compile call. The document *is* a stored artifact, and
its validity must not depend on a compiler ever being run: a host stores,
diffs, and migrates documents that are never compiled on that machine, and a
document that is invalid only when compiled is a document whose invalidity
hides in whichever deployment compiles last.

The rest of the entry grammar is enforced in the same pass and the same error
family, `{:malformed_envelope, {:datamodel, reason}}`: a non-list value, an
entry that is not a map, an entry key outside the three of 11b (shaped
`{:entry, index, reason}`, the index naming which entry), an `id` failing
the grammar, an `expr` or `description` present but not a non-empty string.
One check belongs to decode rather than validation, by decode's own stated
division ("checks only decode can make, because they concern bytes that were
never asked for"): an explicit JSON `null` for `expr` or `description` is
refused rather than read as absent, because after the struct is built `nil`
and absent are indistinguishable and only decode sees the difference.
Decision 8's canonical form spells absence by omission, so a `null` here is
a byte the encoder would never produce, and accepting it would silently
rewrite it away on the next encode.

### 11d. The key is in the canonical bytes and therefore in the document hash

Decision 8's rules apply unchanged and completely:

- an entry encodes as a JSON object with UTF-8-sorted keys;
- an absent `expr` or `description` is omitted, never encoded as `null`;
- an empty `datamodel` list is omitted entirely, exactly as empty `config`,
  `metadata`, and `slots` are;
- list order is preserved - it is the emission order (11a);
- the key participates in `content_hash/1` like every other envelope byte.

One consequence is worth stating rather than leaving to be discovered: two
documents differing only in a `description` are different documents with
different hashes and **byte-identical SCXML**. That is a second concrete
instance of the non-reversibility clause the compiler's determinism section
already carries - "Equal output does not imply equal input: a `metadata`-only
edit changes the document hash and produces identical SCXML"
(`StatifierBlocks.Compiler`'s moduledoc, under ADR-0004 decision 6) - which
is why that clause is not weakened by this key: it was already written for
exactly this shape of input.

### 11e. `schema_version` stays at 1, and decoding is tightened so that staying at 1 is safe

Decision 7's bump criterion is bytes, and no existing document's bytes move:
a document that declares nothing omits the key, so every document encoded
before this amendment encodes to the same bytes after it. By decision 7's own
sentence - `schema_version` "bumps only when this record is amended in a way
that changes bytes" - there is no bump to take.

But "no bump" is only honest if an old reader cannot silently destroy what a
new writer wrote, and decision 8's round-trip law has a live hole here that
this amendment must not widen. `StatifierBlocks.Decode` refuses an unexpected
key on a **block**, in its own words because "a key silently dropped here
would break `encode(decode(bytes)) == bytes` with no error to say so" - and
applies no such rule to the **envelope**. An envelope key a reader does not
know is today dropped in silence: decoded, discarded, and gone on the next
encode.

So decoding gains an explicit envelope-key allowlist mirroring the
block-level one - `datamodel`, `id`, `metadata`, `revision`, `root`,
`schema_version` - and an unrecognized envelope key becomes
`{:malformed_envelope, {:unexpected_key, key}}`. A reader too old for some
future envelope key then **refuses** rather than round-tripping a host's
declarations away; the failure is loud, at the boundary, and names the key.
Note this closes a defect that predates the amendment - no byte stream the
encoder ever produced trips it, since the encoder writes no key outside the
list - and closing it is what makes "no bump" a safety property rather than
merely a true statement.

### 11f. Precedence: the compile call leads, the document follows, the host wins a collision, and the author is told

In the chart's single `<datamodel>`, roots appear in exactly this order:

1. the `:declare` compile option's roots, in the order the option gives them;
2. the document's `datamodel` roots, in list order;
3. block-declared roots, in document order.

Mechanically this is ADR-0004's existing hoist with one more prepend: the
compiler prepends the host's declarations, then the document's, to the root
block's own children before `hoist/1` runs, and everything else - order,
provenance, F6's walk - follows from that placement rather than from new
machinery, exactly as the `:declare` note argued for the option alone.

**A root id declared both by the compile call and by the document is
host-wins.** The document's entry is dropped from the emission, and the
compile emits a warning that rides on the successful artifact
(`%Compiled{}.warnings`) - it is not an error, and it does not stop the
compile:

| | |
|---|---|
| Code | `:shadowed_document_root`, carrying the shadowed id |
| Stage | `:emit` |
| Severity | `:warning` |
| Attributed to | the root block |
| `config_key` | `nil` |
| `fault` | `:package`, by ADR-0004 decision 9's split |

One warning per shadowed id, so an author reading the artifact sees every
root their document declared that this deployment overrode.

Host-wins has to be argued, because refusing looks safer and is not. The
`:declare` note's own reasoning is that a host declaration is deployment
property: "the same document published against two hosts, or against one
host's two environments, declares what that host seeds". A host pinning an
`expr` for a root the document also declares is therefore a *deliberate
override* - the one document, two deployments, two seeds case - and refusing
it would make a host unable to pin a value for a document it did not write.
It would also make migration a flag day: a host moving a root from `declare:`
to the document (the direction 11i expects) could never have both surfaces
name the root during the transition, so every document and every deployment
would have to move in one release. A warning keeps the override possible and
the author informed, which is all the evidence supports.

This mirrors F6's duplicate-binding *discipline* - the same finding
vocabulary, the same anchoring on a block, the same fault split - without
borrowing F6's *severity*, and the difference is principled: F6 refuses an
author mistake that would silently overwrite a binding mid-run; this refuses
nothing, because nothing is silently wrong - the host meant it, the document
still compiles, and the warning says so.

A document root colliding with a **block-declared** root (a `core.foreach`
`item_as`, or any `<data>` a block emits) is unchanged: still F6's
`:duplicate_binding` **error** against that block, with its config key,
through the same hoist walk - because the document's roots are prepended
among the root block's children and every block therefore sits inside their
scope, which is exactly the geometry F6's walk already checks.

Fault, spelled out: the shadow warning carries no `config_key`, so ADR-0004
decision 9's split reads it `:package` - right for the same reason the
`:declare` option's own findings are `:package`: no document edit fixes what
a host's compile call declared. (The mechanical rule and the truth agree
here, but it is worth saying that the *cause* is an interaction between two
surfaces, not a bug; the warning's message should say which deployment
choice produced it.)

Provenance (ADR-0004 decision 5) stays total: a document-declared root's
bytes belong to no block, so they take the **root block**, as `<scxml>` and
the `<datamodel>` wrapper already do, with a role spelled **`:datamodel`** -
a leading colon, exactly as `:declare` is spelled, so that
`StateId.role?/1` rejects it and no role a block mints out of a state id can
ever equal it. No `config_key`, and nothing enters `by_state_id`, for the
same reasons the `:declare` note gives.

### 11g. The relationship to ADR-0006, which this amendment does not fork

Two different artifacts answer two different questions, and they must be told
apart in as many words:

- **ADR-0006's datamodel document** is the *host's* typed, three-scope
  description of the data universe an author writes conditions against. It is
  advisory, it never reaches the engine - in its own words, "the compiler
  does not read it, no SCXML carries it" - and its projection is the
  declared-path *set* that ADR-0005's 11e check consumes.
- **This record's `datamodel` key** is the *block document's* declaration of
  the roots it needs to **exist** at run time. It is compiled, it becomes
  `<data>` elements, and it is in the document hash.

"Is `card.brand` a thing at all, and of what type?" is ADR-0006's question.
"Does the root `signup` exist when this chart starts, and with what initial
value?" is this key's. The first is about a vocabulary; the second is about
storage.

What is shared, and stays shared - the same three items ADR-0006's
cross-check lists, because they are the family's, not either record's:

- **The word.** "Datamodel" means the same thing in both: the record a
  chart's conditions read. ADR-0006 describes one; this key declares roots
  in one.
- **The addressing.** Predicator's grammar, unextended. An entry `id` here is
  a bare root segment of the same paths ADR-0006's entries spell in full.
- **The type floor.** Decision 6's no-floats rule.

The correspondence, stated so no one has to re-derive it: an entry `id` here
is what ADR-0006's vocabulary calls a top-level `local`-scope entry's `path`
- a bare root segment, globally addressable as itself. Whether a
document-declared root should therefore **count as declared** for ADR-0005's
11e undeclared-path advisory is carried as an **open question, not decided
here**: ADR-0005's 11e is written against a set the host supplies ("The
input shape is not this record's to fix", its 11f), and widening what feeds
that set is ADR-0005's decision to take on ADR-0005's record.

Explicitly: this key adds no type, no scope, and no validation verdict, so
ADR-0006 decision 9's "advisory, never a gate" is untouched - nothing here
produces any finding about a path a document addresses but does not declare.

### 11h. What this key is not

- **Not a datamodel document.** 11g. One describes; this declares existence.
- **Not a typed schema.** An entry has no type; the value behind a root is
  whatever the chart and the host put there, under decision 6's grammar.
- **Not a validation surface.** It produces no finding about an undeclared
  path, ever. The strongest advisory anything may produce about one remains
  ADR-0005's 11e `:info`, fed by ADR-0006's projection, unchanged.
- **Not a place for a secret.** ADR-0002 decision 7's `sensitive?` rule and
  the compiler's sensitive-path refusal are unchanged, and this key gives a
  secret no new home - an `expr` is written verbatim into stored, hashed,
  reviewable bytes and then verbatim again into generated SCXML, which is
  precisely why this has to be said out loud rather than assumed.

### Worked fragment

A document declaring two roots, compiled with
`declare: [{"tenant", nil}, {"attempts", "10"}]`. The envelope, canonical
but re-indented (`datamodel` sorts first among the envelope's keys):

```json
{
  "datamodel": [
    {"description": "The signup under construction.", "id": "signup"},
    {"expr": "0", "id": "attempts"}
  ],
  "id": "bdoc_01JDOC",
  "revision": 3,
  "root": {"id": "blk_ROOT", "type": "core.sequence", "type_version": 1},
  "schema_version": 1
}
```

The emitted `<datamodel>`:

```xml
<datamodel>
  <data id="tenant"/>
  <data expr="10" id="attempts"/>
  <data id="signup"/>
</datamodel>
```

The host's roots lead in option order (`tenant`, then `attempts`); the
document's follow in list order, minus the shadowed entry (`signup`); and the
compile succeeds carrying one warning: `:shadowed_document_root` for
`attempts` - the document said `"0"`, this deployment said `"10"`, the host
won, and the artifact says so.

### 11i. Consequences

- The document hash moves for any document that adopts the key, so a host
  caching on ADR-0004 decision 6's triple `{document canonical bytes,
  palette, compiler version}` recompiles such a document once. By design:
  the declaration is in the bytes precisely so that the identity notices it.
- Adopting the key changes the generated SCXML (new `<data>` elements), so
  the chart's identity (st-ADR-0052) moves too, with everything a new chart
  revision implies for persisted positions. A host adopts before publishing,
  not between two runs of one document - the same discipline ADR-0004's
  `terminate` note records for its option.
- A host may now carry roots in the tree the author edits rather than in the
  publish call, which is what makes an editor able to show and edit them one
  day. **No editor surface is proposed here**; that is ADR-0005's, when
  taken.
- ADR-0004's note's second named follow-up - a declaring `core.declare`
  **block type** - is *not* taken and remains ADR-0002's to take. This key
  is an additional surface, not a replacement, exactly as that note says of
  both follow-ups: "Either one would be an additional surface, not a
  replacement: the hoist, determinism, provenance and F6 refusal are shared."
- The "only surface" sentence in `StatifierBlocks.Compiler`'s moduledoc
  (`lib/statifier_blocks/compiler.ex`, the `:declare` option's closing
  paragraph: "This is the compile call's declaration surface and the only
  one: the document has no key for it (ADR-0001) and no block type declares
  one") is now false, and the implementation stage rewrites it. It must now
  say: the compile call is the *host's* declaration surface and leads; the
  document carries its own under this decision, whose roots follow, with
  host-wins shadowing and the `:shadowed_document_root` warning; and no
  block type declares one.
- Old readers refuse new envelopes (11e) instead of silently rewriting them.
  A mixed-version fleet must upgrade readers before writers adopt the key -
  a real operational cost, accepted because the alternative is silent data
  loss with no error to say so.
- Validation, decode, and the canonical encoder all grow a clause; the
  round-trip law now covers the key; and the property tests that hold
  decision 8 to its word must generate documents with and without it.

### Alternatives considered

- **A map keyed by id instead of a list.** Rejected: the order of the
  emitted `<data>` elements has to come from somewhere, and a map either
  loses it or forces a sort. Sorted-by-id emission is an order nobody's
  guard reads and nobody's diff explains, and it would make "move this
  declaration first" - an authoring act with a visible meaning in the
  emitted chart - inexpressible.
- **Reusing ADR-0006's entry shape wholesale.** Rejected: it forks the
  vocabulary from the other end. ADR-0006's entries are typed, scoped,
  labelled, and advisory; this key is untyped and compiled. Importing
  `type`/`label`/`one_of` here would make this key a second datamodel
  document that also happens to emit bytes, and every future widening of
  ADR-0006 would have to be litigated twice.
- **A `core.declare` block type.** Rejected here and left to ADR-0002, which
  owns the type contract - and ADR-0004's note already carries the argument
  against a new declaration surface in the type contract
  (`DeclaredRoots`' case against a new `BlockType` callback). A declaration
  is also not a step: it has no position in the flow, and a block would give
  it one, inviting authors to reason about *when* a declaration happens when
  early binding means it happens before any state is entered.
- **Making the host-shadows-document collision an error.** Rejected: it
  removes the host's override, which is the whole point of the option (one
  document, two deployments, two seeds), and it makes the `declare:`-to-
  document migration a flag day, since no root could be named by both
  surfaces during the transition. F6's severity is for a silent mid-run
  overwrite; nothing here is silent.
- **Bumping `schema_version` to 2.** Rejected: decision 7's criterion is
  bytes, and no existing document's bytes change. A bump would make every
  existing document's version a lie about a key it does not carry, and would
  force every reader to handle two versions that differ in nothing those
  readers can observe. The reader-safety work the bump would be standing in
  for is done properly instead, by 11e's allowlist.

### What this amendment does not change

- Decisions 1 through 10, in any particular. The block shape (decision 2)
  gains nothing; the key is the envelope's.
- Decision 8's encoding rules or round-trip law - the key obeys both, and
  11e strengthens the law's enforcement at the envelope.
- The `:declare` compile option, its grammar, its refusals, or its findings
  (ADR-0004's note). It still leads; 11f only adds what follows it.
- F6's `:duplicate_binding`, its walk, or its severity for block-declared
  collisions.
- ADR-0006 in any word: its shape, its projection, its decision 9. 11g
  names the boundary; nothing crosses it.
- ADR-0002 decision 7's `sensitive?` rule and the sensitive-path refusal.
- The engine's run-creation-wins behaviour over `expr` (SCXML 5.3.2).

## Note (2026-09-05): decision 6, how the worked example spells a duration

A dated Note. No decision in this record moves, and the worked example's bytes
are not edited.

The change it reads against is **in flight**: ADR-0005's decision-9 amendment
of this date is proposed, on its own gate and under its own bead. What it
settles is that record's to state, and this Note neither depends on its text
nor speaks for it; it records how to read one sentence of the worked example
once that amendment is accepted.

Decision 6 says config is opaque to this layer, and forbids floats in it. Both
are unchanged. So is the point the worked example's decision-6 bullet is chosen
to demonstrate, and so is its reason: 48 hours is written as a string and not
as `48.0` precisely because of the no-floats rule, and that sentence is as true
today as when it was written.

What is superseded is narrower - the *illustrative* claim the same bullet makes
about how a duration is spelled. ADR-0005's proposed amendment of 2026-09-05
to its decision 9 reverses the clause that kept an older, calendar-style
spelling accepted in a `:duration` field, on the finding that no
author-written document holds one. Once it is accepted, a duration in block
config is written in the expression language's duration grammar: a duration
like `30s` or `1h30m`, and the example's 48 hours as something like `48h`.

Read the bullet's duration sentence, then, for the property it is there to
demonstrate. That property is opacity: this layer sees two strings, and which
grammar wrote either of them is not the schema's business. Read the spelling
inside it as the spelling of the day the example was written. The same holds
for the `timeout` value in the worked example's JSON above, and for the
duration shown in the tree diagram. Those bytes are this record's own and stay
exactly as they are. What they render is the document this package ships as
`test/fixtures/documents/worked_example.json`, and it is that fixture which
migrates on `sb-4r1p`; neither this schema nor decision 6 changes when it does,
and the example above it is not edited when it does either. The round-trip
acceptance property beneath the example is indifferent to the spelling: it is
about bytes surviving a decode and re-encode, whatever the bytes say.

Nothing else in decision 6, in the worked example, or anywhere above this line
is affected or edited. The 2026-08-31 amendment - the `datamodel` key and
decision 11 - is untouched here; what a declared entry of duration type means
is ADR-0006's subject, and `sb-b05e` recorded it there, on a request of its
own that has landed.

Filed with `sb-8acm`, campaign-029's Lane A.
