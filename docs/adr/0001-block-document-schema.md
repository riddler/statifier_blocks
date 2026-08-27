# ADR-0001: The block document is a tree of typed blocks with named slots

Status: accepted (2026-08-26)

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

  @doc "Walks the tree; `nil` when the id is absent."
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
