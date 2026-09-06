# ADR-0003: Assignability is opaque-string identity plus a host-supplied widening relation

Status: accepted (2026-08-26); decision 8 amended (2026-08-29, operator acceptance after the campaign-014 direction-agent gate on PR 88)

## Context

ADR-0001 fixed the document as a tree of `{type, id, config, slots}` nodes
where adjacency within a slot *is* sequencing. ADR-0002 made the block type a
behaviour module resolved through a caller-supplied palette, declared nine
callbacks, and left `io/1` as an optional callback returning `term()` with the
note that this record owns its shape. This record fills that hole and answers
the one question ADR-0002 explicitly handed over: which block types may appear
in which slots.

Four forces bind the answer.

**The editor needs the answer before hover, not on hover.** The interaction
this whole package exists to support is drag-and-drop authoring, and the thing
that makes it feel like a tool rather than a guessing game is that every valid
drop target lights up the moment the drag starts. That is a demand on
*complexity and purity*, not on API surface: the verdict for every position in
the document has to be computable in one pass over the tree with no IO, so
the editor can compute the whole highlight set on mousedown. A relation that
required loading anything, or that had to be asked one hover at a time, would
push the editor back to hover-time validation and a drop that fails after the
author has already committed to it.

**This package must not grow a type system.** The moment a type expression is
a structure - a record shape, a union, a parameterized container - this
package owns a subtyping algorithm, a normal form, an inference rule for
containers, and a decade of edge cases, none of which are what it is for. But
hosts genuinely do have widening: a host whose `myapp.credit_card_txn` and
`myapp.debit_card_txn` both satisfy the shape a generic ledger step wants has a real
relation between them, and it is a relation only that host can know. The way
out is the one the family already uses for every other extension point: keep
the core rule trivial and total, and let the host supply the part only it can
know, as a value.

**Two different questions arrive wearing the same clothes.** "May this block
land in this slot" is asked once by the editor, but it decomposes into a
data-flow question (does the upstream step produce what this block consumes)
and a structural question (is an interrupt handler even the kind of thing that
belongs in a `body` slot). ADR-0002 decision 10 hit the second one head-on
with `core.on_event` and recorded it as a special-cased rule the core types
carry, explicitly deferring the general form here. Deciding whether one
mechanism covers both is this record's job, and the answer determines whether
that special case survives.

**Whatever this record decides, the compiler and the editor must run the same
code.** The failure mode to design against is an editor that permits a drop
the compiler later refuses, or greys out a slot the compiler would have
accepted. That is not a discipline problem to be solved by review; it is
solved by there being exactly one implementation and exactly one place the
host's contribution is registered, which both consumers are already passed.

## Decision

**1. A type expression is an opaque string, and the default relation is
string identity.** `"record"`, `"decision"`, `"myapp.card_txn"`. This package
parses type expressions, compares their parts, normalizes them, and infers
them: never. `assignable?(produced, consumed)` is `produced == consumed`,
which is decidable in constant time, obviously reflexive, obviously
transitive, and impossible to get subtly wrong.

Type expressions live in the same namespacing convention as block type names
(ADR-0001 decision 4) by convention only - this layer never splits on the dot.
The `core.*` block types declare no type expressions at all (decision 4).

**2. `io(config)` returns one map with three keys, and it is the whole
declaration surface.** ADR-0002 gave this record `io/1`'s return shape; the
structural question of decision 3 is answered inside that same return rather
than by extending ADR-0002's `slot_decl` tuple, so nothing in ADR-0002's
typespecs changes.

```elixir
%{
  kinds: [kind()],                         # what this block IS
  consumes: type_expr() | :unknown,        # what it wants inbound
  produces: type_expr() | :unknown | {:passthrough, slot_name()},
  slot_accepts: %{slot_name() => [kind()] | :any}
}
```

`io/1` stays optional and every key in the map is optional. An absent `io/1`,
or an absent key, means the permissive default of decision 5. A block type
declares only the parts it has an opinion about.

Purity carries over from ADR-0002 decision 4 with no amendment: `io/1` is a
pure function of config, which is what makes decision 8's one-pass
precomputation possible.

**3. Structural admission is kind tags, and it subsumes ADR-0002's special
case.** A `kind` is an atom naming what a block *is* for placement purposes.
This package defines two - `:step` and `:interrupt_handler` - and a host may
mint its own. A slot names the kinds it admits through `slot_accepts`, or
`:any`.

The verdict for placing block `B` in slot `S` of parent `P` is: `:any` admits
everything, otherwise `P`'s `slot_accepts[S]` and `B`'s `kinds` must intersect.

This is a strictly stronger mechanism than the rule ADR-0002 decision 10
recorded, in a way worth being explicit about, because it is the reason the
special case does not survive. ADR-0002 stated the constraint one-directionally
- `core.on_event` is valid only inside an `interrupts` slot - which leaves the
mirror-image error unstated: nothing there stops an ordinary step from being
dropped into `interrupts`, where it would compile to a transition with no
trigger. Kind tags close both directions with one declaration on each side:

```elixir
# core.on_event
def io(_config), do: %{kinds: [:interrupt_handler]}

# core.resumable_group
def io(_config),
  do: %{slot_accepts: %{"body" => [:step], "interrupts" => [:interrupt_handler]}}
```

**So: yes, the general mechanism subsumes the special case, and ADR-0002's
special-cased validation rule is withdrawn rather than kept alongside.** The
constraint is now carried by the same `io/1` declaration and evaluated by the
same function as every other placement question, so there is one code path for
the editor to highlight from and one finding vocabulary for it to render.

Two consequences of that subsumption are deliberate. A host writing its own
group type with an `interrupts` slot gets the constraint by declaring
`slot_accepts` - it does not have to know that `core.on_event` exists, and
`core.on_event` does not have to enumerate the group types it is allowed
inside, which is the coupling a child-side placement list would have created.
And a host with a genuinely different notion of interrupt handler mints its
own kind and its own group, with no change to this package.

Kinds are deliberately *not* type expressions and are deliberately not
ordered. There is no kind hierarchy, no kind widening, and no host callback
for kinds. They are an unordered tag set compared by intersection, because the
structural question is a small, closed, editorial one - it is asking whether
two things belong in the same box, not tracking data through a workflow - and
giving it a lattice would be building the type system this record refuses to
build, twice.

**4. Data-flow assignability runs on the seam between adjacent siblings, and
inbound type is computed by walking, never stored.** Adjacency within a slot
is sequencing (ADR-0001 decision 5), so the data-flow question at position
`{parent, slot, index}` is a question about the block at `index - 1`.

The **inbound type** of a position is defined:

- at `index > 0`: the `produces` of the sibling at `index - 1`;
- at `index == 0`: the **slot inbound** of `{parent, slot}`, which is the
  parent's own inbound type. A sequence's `body`, a branch's arms, and a
  parallel block's lanes all therefore start from whatever reached the
  container, which is what an author reads them as meaning, and it falls out
  of the definition rather than being special-cased per container;
- at the root: the **entry type**, supplied by the caller in the assignability
  context (decision 6), defaulting to `:unknown`. The entry type is not stored
  in the document - ADR-0001 decision 2 admits no field for it and decision 7
  keeps this layer out of `metadata` - because it is a property of where the
  host runs the workflow, not of the workflow.

`produces` resolves as: a type expression is itself; `:unknown` is `:unknown`;
`{:passthrough, slot}` is the `produces` of the last block in that slot, or,
when the slot is empty, the block's own inbound type. `:passthrough` exists so
that `core.sequence` can be transparent to type flow without this package
computing anything, and it terminates because the tree is finite and a
passthrough only ever descends.

There is no join, no union, and no least-upper-bound. `core.branch` and
`core.parallel` declare `produces: :unknown` rather than combining their arms'
or lanes' outputs, because combining them is precisely a type lattice - the
thing decision 1 exists to avoid. A host that wants a real answer downstream
of a branch declares an explicit `produces` on its own container type and
supplies the widening relation that makes it sound.

**5. `:unknown` is permissive, in both positions.** `:unknown` produced is
assignable to any `consumes`; any `produces` is assignable to `:unknown`
consumed. No `io/1` at all means `kinds: [:step]`, `consumes: :unknown`,
`produces: :unknown`, and `slot_accepts` `:any` for every slot - a block that
constrains nothing and is constrained by nothing.

The alternative - unknown as a bottom that satisfies nothing - was rejected
because it inverts the adoption curve. The `core.*` vocabulary declares no
type expressions and neither does a host's first palette entry, so a
restrictive default means the editor greys out every slot in the document
until a host has typed its entire palette, and the feature reads as broken
before it can read as useful. Permissive means assignability is a constraint a
host opts into one palette entry at a time, and every entry typed makes the
editor strictly more helpful than it was.

The cost is the honest one and it is stated in the consequences: a partially
typed palette silently permits a seam that a fully typed one would have
caught. That is the correct trade for an authoring aid; it is not the correct
trade for a runtime guarantee, and nothing in this record claims to be one.

**6. Widening is a host-supplied module on the palette, and it can only
widen.** ADR-0002 decision 2 made the palette the caller-supplied bundle that
every operation is already passed. The widening relation rides there:

```elixir
%StatifierBlocks.Palette{types: %{...}, assignability: MyApp.Blocks.Types}
```

Not `Application` env, not a named ETS table, not a behaviour registered at
boot - for the reasons ADR-0002 decision 2 gave and does not need to repeat.
The consequence that matters here is decision 7's: putting it on the palette
is what makes the editor and the compiler share one implementation *by
construction*, since both already take a palette and neither has any other
channel through which a different answer could arrive.

The relation is checked in a fixed order, and the order is the contract:

1. either side `:unknown` -> assignable (decision 5);
2. `produced == consumed` -> assignable (decision 1);
3. no `:assignability` module on the palette -> not assignable;
4. otherwise `module.assignable?(produced, consumed)`.

**The host callback is consulted only after identity has already failed, so it
can only ever widen the relation, never narrow it.** This is the single most
important property in this record. It means the default rule is a floor a host
cannot lower; it means removing or swapping the callback can never invalidate a
document that was valid without it; it means the set of valid drop targets is
monotone in the callback, so an editor can compute the identity-only set
eagerly and treat the callback as adding to it; and it means a buggy host
callback degrades to extra permissiveness, which surfaces as a runtime error in
the host's own step, rather than to a workflow the author cannot save.

`assignable?/2` is pure under ADR-0002 decision 4's rule, unchanged and for the
same reasons: it runs inside the editor's per-edit validation and inside a
compile that sb-iwz must make reproducible against a document hash.

Two algebraic properties are stated as expectations rather than enforced.
Reflexivity is *guaranteed* regardless of the host, because step 2 short-circuits
before the callback is reached. Transitivity is *not* required: this package only
ever compares directly adjacent pairs, never composes a chain, so a
non-transitive host relation still produces locally correct verdicts. Hosts
should want transitivity for their own sanity; nothing here breaks without it.

**7. Two consumers, one function, and the local/global split.** A single
function answers every placement question:

```elixir
Assignability.check(palette, document, target, candidate, ctx)
```

The editor and the compiler call it with the same palette and get the same
answer. What differs is *which seams they ask about*, and the difference is
exact rather than approximate:

- **A drag** changes exactly one seam for an insert: `(upstream -> candidate)`
  and `(candidate -> next sibling)` at the insertion point. Nothing upstream of
  it changes, and nothing downstream of the next sibling changes, because
  inbound type propagates strictly forward. So checking the insertion point is
  *complete* for an insert, not a cheap approximation of a whole-document check.
- **A move** changes the insertion seam plus one more: at the vacated position,
  the block before and the block after become adjacent. Three pairs, and again
  that is the exact set of seams whose verdict can have changed.
- **Validation** walks the whole document and checks every seam and every
  placement, and is the authority - the same relationship ADR-0002 decision 7
  set up between `config_schema/1` and `validate_config/1`, for the same
  reason: the cheap thing catches the easy case early, and exactly one thing is
  authoritative.

For an insert or a move the two agree by construction, which is what makes the
drag highlight trustworthy. They can diverge when the *document* changes
underneath, for instance when editing a block's config changes its `produces`,
which invalidates every seam downstream of it. That is an edit, not a drag, and
it retriggers whole-document validation - the same re-validation trigger
ADR-0002 decision 5 already established for config edits changing slot sets.

**8. Findings, and what refuses.** Assignability failures are validation
findings of exactly the same standing as ADR-0002 decision 6's arity findings:
a document violating one still decodes (ADR-0001 decision 9) and still
resolves, and fails validation with the offending block named.

```elixir
{:kind_not_admitted, block_id, parent_id, slot_name, kinds, accepts}
{:type_mismatch, block_id, upstream_block_id | :slot_entry, produced, consumed}
```

Both name the block the author has to look at and both carry enough to phrase a
message without re-deriving anything. Whether the compiler refuses to emit on
either of these, or emits and lets the runtime fail, is **sb-iwz's** decision -
it already owns the refusal set through unresolvable types (ADR-0002 decision
3), and splitting that authority would give a host two places to look. How the
editor renders a finding, what the drag highlight looks like, and whether an
invalid drop is blocked or permitted-and-flagged are **sb-w50's**.

**9. What this record does not decide.**

- **sb-iwz**: whether type mismatches block compilation, and whether type
  expressions appear anywhere in emitted SCXML or the provenance map. Nothing
  in this record requires them to; assignability is an authoring-time relation,
  and the emitted chart carries invoke types (ADR-0002 decision 10's consequence),
  not type expressions.
- **sb-w50**: all presentation. Highlighting, greying, drop blocking, finding
  copy, and whether a host's widened match is shown differently from an exact
  one.
- **The host**: what its type expressions mean. This package guarantees only
  that it compares them by identity and asks the host about the rest.

## Consequences

- The general mechanism replaces ADR-0002 decision 10's special case rather
  than sitting beside it. ADR-0002's table row for `core.on_event` and the
  paragraph beneath it should be re-read as "carried by `io/1`"; that editorial
  amendment to ADR-0002 is noted for whoever lands these two records, and is
  deliberately not made here.
- Because `io/1` is optional and every key in it defaults permissively, this
  record adds *zero* required work for a host writing its first palette entry,
  and the core vocabulary implements `io/1` only for the two blocks that carry
  a kind constraint. Assignability is a feature a host turns on gradually.
- A partially typed palette permits seams a fully typed one would catch. There
  is no way to detect "this host meant to type this and forgot", and this
  record does not add a lint for it. A host that wants completeness enforces it
  in its own palette tests.
- Since the host callback can only widen, a host can add, change, or delete its
  assignability module at any time without invalidating a stored document. This
  is what makes it safe to ship the relation as a value rather than versioning
  it.
- There is no join for branches and parallels, so a typed pipeline goes
  `:unknown` downstream of any core container that isn't a sequence. Hosts that
  care will write their own container types. This is a real limitation and it
  is the price of not owning a lattice; the day a host demonstrates it needs
  one, that is a new record, not a patch to this one.
- Kinds are an open set with two members shipped. A host minting kinds
  freely can fragment its own palette - two group types with incompatible
  interrupt kinds - and nothing here prevents that. The set is open because
  closing it would make this package the arbiter of every host's structural
  vocabulary, which is the thing ADR-0002 decision 2 refused for block types.
- The editor gets an O(positions) precomputation with no IO and no hover
  round-trip, which is the whole reason for the purity constraints above. A
  future change that made any part of this relation impure would break the
  interaction this package exists for.

## The relation as typespecs

```elixir
defmodule StatifierBlocks.Assignability do
  @moduledoc """
  May this block land in this slot? Answered by two independent gates -
  structural admission by kind tag, and data-flow compatibility by opaque
  string identity plus a host-supplied widening relation.

  One implementation, consulted by both the editor (sb-w50) and the compiler
  (sb-iwz), because both are passed the same palette (ADR-0003 decision 6).
  """

  alias StatifierBlocks.{Block, Document, Palette}

  @typedoc "Opaque to this package. Never parsed, split, or normalized."
  @type type_expr :: String.t()

  @typedoc ~S(Structural tag. `:step` and `:interrupt_handler` ship here; hosts may mint more.)
  @type kind :: atom()

  @typedoc "What a block produces to its next sibling. See ADR-0003 decision 4."
  @type produces :: type_expr() | :unknown | {:passthrough, Block.slot_name()}

  @typedoc "The return shape of `c:StatifierBlocks.BlockType.io/1`. Every key optional."
  @type io :: %{
          optional(:kinds) => [kind()],
          optional(:consumes) => type_expr() | :unknown,
          optional(:produces) => produces(),
          optional(:slot_accepts) => %{optional(Block.slot_name()) => [kind()] | :any}
        }

  @typedoc "Caller-supplied, not stored in the document (ADR-0003 decision 4)."
  @type context :: %{optional(:entry_type) => type_expr() | :unknown}

  @typedoc "A position, as ADR-0001 decision 5 defines one."
  @type target :: {Block.id(), Block.slot_name(), non_neg_integer()}

  @type finding ::
          {:kind_not_admitted, Block.id(), Block.id(), Block.slot_name(), [kind()],
           [kind()] | :any}
          | {:type_mismatch, Block.id(), Block.id() | :slot_entry, type_expr() | :unknown,
             type_expr() | :unknown}

  @doc """
  The one function both consumers call. `candidate` is an unplaced block or a
  block being moved; when it is already in the document, the seam it vacates is
  checked too (ADR-0003 decision 7).
  """
  @spec check(Palette.t(), Document.t(), target(), Block.t(), context()) ::
          :ok | {:error, [finding()]}

  @doc """
  Every position in the document this candidate may occupy. Pure, one pass,
  no IO - this is what the editor calls on mousedown so it can highlight
  before hover (ADR-0003 context).
  """
  @spec valid_targets(Palette.t(), Document.t(), Block.t(), context()) :: [target()]

  @doc "The authority: every seam and every placement in the document."
  @spec validate(Palette.t(), Document.t(), context()) :: :ok | {:error, [finding()]}

  @doc "Inbound type at a position. Derived by walking; never stored."
  @spec inbound_type(Palette.t(), Document.t(), target(), context()) ::
          type_expr() | :unknown

  @doc """
  The ordered relation of ADR-0003 decision 6. Reflexive regardless of the
  host, because identity short-circuits before the callback is reached.
  """
  @spec assignable?(Palette.t(), type_expr() | :unknown, type_expr() | :unknown) :: boolean()
end

defmodule StatifierBlocks.Assignability.Relation do
  @moduledoc """
  A host's widening relation. Consulted only after identity has failed, so an
  implementation can only widen, never narrow (ADR-0003 decision 6).

  Pure, under ADR-0002 decision 4.
  """

  @callback assignable?(
              produced :: StatifierBlocks.Assignability.type_expr(),
              consumed :: StatifierBlocks.Assignability.type_expr()
            ) :: boolean()
end
```

The `io/1` callback ADR-0002 declared as returning `term()` is thereby pinned:

```elixir
@callback io(Block.config()) :: StatifierBlocks.Assignability.io()
```

## Worked example

A multi-tenant host embedding the engine, whose card transactions widen:
`myapp.credit_card_txn` and `myapp.debit_card_txn` both satisfy anything
that wants a bare `myapp.card_txn`. The host declares that once.

```elixir
defmodule MyApp.Blocks.Types do
  @behaviour StatifierBlocks.Assignability.Relation

  @widens %{
    "myapp.credit_card_txn" => ["myapp.card_txn"],
    "myapp.debit_card_txn" => ["myapp.card_txn"],
    "myapp.settled_txn" => ["myapp.credit_card_txn", "myapp.card_txn"]
  }

  @impl true
  def assignable?(produced, consumed),
    do: consumed in Map.get(@widens, produced, [])
end

palette = %StatifierBlocks.Palette{
  types: Map.merge(StatifierBlocks.Palette.core(), %{
    "myapp.authorize" => MyApp.Blocks.Authorize,
    "myapp.settle" => MyApp.Blocks.Settle,
    "myapp.post_to_ledger" => MyApp.Blocks.PostToLedger,
    "myapp.on_chargeback" => MyApp.Blocks.OnChargeback
  }),
  assignability: MyApp.Blocks.Types
}
```

Its palette entries declare what they are and what they move:

```elixir
# Takes a transaction, hands back a card authorization.
def io(_config),
  do: %{consumes: "myapp.transaction", produces: "myapp.credit_card_txn"}   # authorize

# Takes a card authorization, hands back a settled transaction.
def io(_config),
  do: %{consumes: "myapp.credit_card_txn", produces: "myapp.settled_txn"}   # settle

# Takes any card transaction; produces nothing anyone downstream wants.
def io(_config), do: %{consumes: "myapp.card_txn", produces: :unknown}      # post_to_ledger

# Not a step at all.
def io(_config), do: %{kinds: [:interrupt_handler]}                         # on_chargeback
```

And the two core types that carry structure:

```elixir
# core.sequence - transparent to type flow, so a nested sequence does not
# blank out everything after it.
def io(_config), do: %{produces: {:passthrough, "body"}}

# core.resumable_group - the constraint ADR-0002 decision 10 special-cased.
def io(_config),
  do: %{
    produces: {:passthrough, "body"},
    slot_accepts: %{"body" => [:step], "interrupts" => [:interrupt_handler]}
  }
```

Now the document from ADR-0001's worked example, with a `myapp.settle` step
(`blk_STL`) added after the authorize, and entry type `"myapp.transaction"`
supplied by the host in the context. Walking the `body` of the root sequence:

| Position | Inbound | Candidate consumes | Verdict |
|---|---|---|---|
| before `blk_AUTH` | `"myapp.transaction"` (entry type) | authorize wants `"myapp.transaction"` | identity, step 2 |
| after `blk_AUTH` | `"myapp.credit_card_txn"` | settle wants `"myapp.credit_card_txn"` | identity, step 2 |
| after `blk_STL` | `"myapp.settled_txn"` | post_to_ledger wants `"myapp.card_txn"` | **host widens**, step 4 |
| after `blk_STL` | `"myapp.settled_txn"` | authorize wants `"myapp.transaction"` | no - `:type_mismatch` |
| inside `interrupts` | - | post_to_ledger is `[:step]` | no - `:kind_not_admitted` |
| inside `interrupts` | - | on_chargeback is `[:interrupt_handler]` | admitted |
| inside `body` | - | on_chargeback is `[:interrupt_handler]` | no - `:kind_not_admitted` |

Reading the interesting rows:

- **The host relation widening, and only widening.** `"myapp.settled_txn"` ->
  `"myapp.card_txn"` is not identity, so step 4 asks the host, which says yes.
  Delete `assignability: MyApp.Blocks.Types` from the palette and that one row
  flips to a mismatch while every other row is unchanged - the identity rows
  never reached the callback (decision 6).
- **Both directions of the structural gate.** The last three rows are the
  subsumption of ADR-0002 decision 10 in decision 3. The old special case gave
  only the third of them; kind tags give all three from two declarations.
- **`:passthrough` earning its keep.** `blk_GRP` is a `core.resumable_group`
  whose `body` ends in the branch, and the branch declares `produces:
  :unknown`, so everything after the group is unconstrained. Had the group's
  body ended in a settled transaction instead, `{:passthrough, "body"}` would
  have carried `"myapp.settled_txn"` out past the group with no lattice and no
  inference (decision 4).
- **Permissive `:unknown` (decision 5).** `core.branch` and `core.parallel`
  declare no types, so every position downstream of the branch accepts
  anything. A host that finds this too loose types its own container; this
  package will not guess.

The editor's drag, and the compiler's validation, both from the same palette:

```elixir
# Editor, on mousedown - the whole highlight set, one pass, before any hover.
StatifierBlocks.Assignability.valid_targets(palette, document, dragged, ctx)
#=> [{"blk_ROOT", "body", 0}, {"blk_ROOT", "body", 1}, {"blk_GRP", "body", 1}, ...]

# Compiler, before emitting - the authority over every seam.
StatifierBlocks.Assignability.validate(palette, document, ctx)
#=> {:error, [{:type_mismatch, "blk_AU2", "blk_STL", "myapp.settled_txn", "myapp.transaction"}]}
```

The acceptance property for this record: those two calls consult one
implementation and one host relation, reached through one palette value, so
there is no arrangement of code in which the editor lights up a slot the
compiler would reject.

---

## Amendment (2026-08-29): decision 8, a reason vocabulary for what a seam decided

**Status: accepted (2026-08-29, operator ruling: the campaign-014 direction-agent verdict on PR 88 was QUALIFIED on one claim in 8e, the text was corrected per that verdict and merged, and the operator accepted the section on 2026-08-29).** Drafted 2026-08-29 as a proposed amendment. Additive; decisions 1-9 stand as accepted
and no text above this line is changed by it. Nothing here alters a verdict,
a typespec above, or either finding tuple.

### Context

Decision 8 gives an assignability failure a finding and a shape:
`{:type_mismatch, block_id, upstream_ref, produced, consumed}`. That is enough
to *phrase* a message, which is what decision 8 says it is for, and it was
enough while the only consumer was a validation list.

It is not enough for the editor's side of decision 7. The pre-hover marking
that decision 7 exists to make trustworthy is per-slot (ADR-0005 decision 5),
and a slot that a drag leaves unmarked says only "not here". The author is
looking at a slot that refused and has nowhere to go: the finding that knows
why is attached to a document position the slot does not have, and the
document may not even contain the block yet. A hover affordance that could say
why has nothing to read.

There is a second gap, and it is the one decision 5's own consequences already
name: *"a partially typed palette permits seams a fully typed one would
catch."* That cost is stated in prose and is invisible in code. A host cannot
ask which of its seams passed because a type really matched and which passed
only because a block declared nothing, so a palette that is half typed looks
exactly like a palette that is fully typed and correct.

Both gaps want the same thing: a name for *how* a seam came out, distinct from
*whether* it came out. That is what this section proposes, and the whole of its
risk is in the word "distinct" - a vocabulary that quietly became a sixth
decision-6 step would be the type system decision 1 refuses to build, arriving
by the back door.

### Decision

**8a. Five arms, and they explain rather than decide.**

```elixir
@type reason ::
        :source_untyped
        | :target_untyped
        | :both_untyped
        | :not_assignable
        | {:fixable_by, Block.id()}
```

The classification is total over a seam, follows decision 6's own order, and
is computed *after* `assignable?/3` has already answered:

  1. both sides `:unknown` -> `:both_untyped`;
  2. produced `:unknown` -> `:source_untyped`;
  3. consumed `:unknown` -> `:target_untyped`;
  4. `assignable?/3` says yes -> **no reason at all**;
  5. refused, and the producing side is a block -> `{:fixable_by, block_id}`;
  6. refused, and the producing side is `:slot_entry` -> `:not_assignable`.

`:unknown` stays permissive in both positions, exactly as decision 5 has it.
The first three arms therefore sit on seams that were **admitted**, not
refused. This is the point on which the vocabulary either holds or does not,
so it is stated flatly: **no seam is admitted or refused differently for this
vocabulary existing.** The reason is a pure function of a verdict already
reached; nothing in the package branches on what it returns; and steps 1-3
cannot refuse because steps 1-3 describe passes.

Arm 4 having no name is deliberate. A seam that was really checked and really
matched has nothing to say, and giving it an arm would invite a caller to
render one.

**8b. Two refusing arms, split by decision 8's own tuple.** `producing_ref` is
exactly the third element of a `:type_mismatch`. So `{:fixable_by, block_id}`
names the block that finding already names - the declaration an author would
change - and `:not_assignable` is the case where that element is
`:slot_entry`: refused, with no block named to go and look at.

Deriving the split from the tuple rather than from a fresh walk buys the
property this record cares about most, and costs two things worth naming:

  * at a slot's index 0 the producing ref is `:slot_entry` by decision 4's
    definition of the slot inbound, so a refusal there reads `:not_assignable`
    even when the type reached that position from a real block through a
    container;
  * when the named block passes a type through (`{:passthrough, slot}`), the
    declaration to change is inside it rather than on it.

Both could be closed by tracing a type to the block that declared it. Neither
is, because that trace is a second walk producing a second answer, and a second
answer free to disagree with the finding the author is reading is the exact
failure decision 7 exists to prevent. One rule, one ref, one answer.

**8c. The reason rides beside the finding, not inside it.** Decision 8's two
tuples are unchanged - no element is added to either. A `:type_mismatch`
already carries its producing ref, its produced type and its consumed type, so
its reason is a projection of what it holds plus the palette. Stored, it would
be a second copy of a verdict those already determine, free to drift from them;
derived, it cannot be wrong while the finding is right.

`{:kind_not_admitted, ...}` gets no reason from this vocabulary. The structural
gate's reason is its own finding code, which names both kind sets, and decision
3 is emphatic that kinds are not types; a data-flow vocabulary answering for it
would be the lattice creeping back in. Where both gates refuse at once, the
structural one is the one reported - it is the first finding `check/5` emits,
and reporting the seam there would tell the author the second-most-interesting
thing that is wrong.

**8d. Three producers, and what each is for.**

  * `Assignability.seam_reason/4` - the classifier itself. Every other producer
    is this one applied to something.
  * `Assignability.finding_reason/2` - one finding's reason, 8c's projection.
    This is what the compiler-side consumer uses to render a message that says
    why rather than only what.
  * `Assignability.seam_reasons/3` - every seam in a document that has
    something to say, in pre-order. **This is the producer of the three untyped
    arms**, and it is what makes decision 5's stated cost queryable instead of
    merely admitted: a host auditing its own palette asks here and gets back
    the seams that passed without being checked. It is not part of validation,
    it emits no findings, and a document whose every seam answers
    `:source_untyped` is exactly as valid as one whose seams answer nothing.

**8e. What the editor may do with it, which is presentation and stays
sb-w50's.** ADR-0005 decision 5's granularity is per-slot, so a slot-level
reason exists only where the slot's gaps agree: each gap's reason is that of
its first finding, and the slot's is that value when every gap gave the same
non-nil one. Otherwise there is none, which is honest rather than lossy - a
slot refused for room, for the dragged block's own subtree, or for different
reasons at different gaps has no single true sentence, and picking one would be
picking arbitrarily.

A consequence worth stating rather than leaving to be found: which arms can
reach a slot, and by which path. A slot's *insertion* seams cannot agree on
`{:fixable_by, _}`: gap 0's producing side is the slot's own inbound
(`:slot_entry`) and gap `i`'s is the sibling at `i - 1`, so gaps name different
blocks by construction and the arm an insertion seam can carry to slot level is
`:not_assignable`. The *vacated* seam is different, and it is the per-slot path
for `{:fixable_by, _}`: a move that would break the seam it leaves behind
(`check/5`'s third seam - the block before the candidate's current position
against the block after it) yields the same `:type_mismatch` at every position
in the document, and its producing ref is that before-block. Every otherwise
accepting gap then agrees, so every such slot reads `{:fixable_by, id}` -
including slots in other parts of the tree, whose reason names a seam in the
*source* slot rather than in themselves. That is the correct sentence for the
author: the block cannot move anywhere until the declaration it is holding
together is changed, and the reason says which one. A gap that also refuses
on its own insertion seam takes that seam's reason instead (insertion seams
precede the vacated seam in `check/5`'s order), and the slot then reports what
its gaps agree on, or nothing. Nothing is lost; the finding still carries the
position-level answer in every case.

### Consequences

- Decision 8's finding vocabulary is unchanged, so every existing consumer,
  test and pattern match keeps working. This amendment adds functions and one
  type; it removes and rewrites nothing.
- The editor can darken a slot *and* say why, with the reason already in the
  markup at drag start. No hover round-trip, no client-side rule, no
  JavaScript - the same properties the purity constraints in this record's
  context section were written to protect.
- A host can now find its own untyped seams. That is the first mechanism in
  this package that addresses the partial-palette cost at all, and it does so
  without a lint, without a verdict, and without this package deciding what a
  complete palette is.
- Reasons are derived, so they cannot disagree with the findings they explain.
  The cost is recomputation - `finding_reason/2` re-runs `assignable?/3` for a
  seam already decided - which is bounded by the same pure, IO-free relation
  the editor already runs over every position at drag start.
- Two arms describe refusals and three describe admissions, which reads oddly
  for something introduced as a refusal vocabulary. It is the honest shape:
  under decision 5 an untyped side can never refuse, so an untyped arm can only
  ever explain a pass. A vocabulary in which all five refused would require
  narrowing `:unknown`, which is decision 5 reopened, and that is a new record.
- `{:fixable_by, _}` is weaker than it could be at a slot's first position and
  behind a passthrough. Closing either gap means tracing a type to its
  declaring block, which is a second walk and therefore a second answer; the
  day a host demonstrates it needs one, that is a new record, not a patch to
  this section.

## Amendment (2026-08-31): the `:draft_shelf` kind, and a slot the data-flow walk does not enter

**Status: accepted (2026-09-01), drafted for `sb-5h6q` under the operator campaign-024 grant; accepted on the gate's unqualified direction-agent verdict.** Additive; decisions 1
through 9 stand as accepted and no text above this line is edited by this
section. It is the assignability half of ADR-0002's amendment of this date,
which adds `core.drafts` and `core.placeholder` to that record's decision 10
under campaign-024 rulings R-a and R-b.

### What forces the amendment

Decision 3 says a kind names what a block *is* for placement purposes, and
decision 4 says adjacency within a slot is sequencing, so a position's inbound
type comes from the sibling before it. The drafts container is the first block
type for which the second sentence is false: its children are not adjacent to
each other in any sense the compiler reads, because ADR-0002's amendment of
this date, section G9a, removes the whole block from the flow before the
data-flow walk runs.

Two things follow and neither is derivable from the accepted text. What the
shelf declares (A1) and what happens inside it (A2).

### A1. `core.drafts` declares `kinds: [:draft_shelf]` and `slot_accepts: %{"body" => :any}`

`:draft_shelf` is the third kind this package defines, beside `:step` and
`:interrupt_handler`, and it is minted for the reason decision 3 gives for
having kinds at all: the structural question is whether two things belong in
the same box. A shelf belongs in exactly one box and a step belongs in
approximately all of them, so they are not the same kind.

The mechanism then does the work with no new rule. Every slot in the shipped
`core.*` vocabulary accepts `[:step]` or `[:interrupt_handler]` and none
accepts `:any`, so a block declaring only `:draft_shelf` is refused by every
one of them, in both directions, by the same intersection every other
placement question runs through. A host's own container declaring
`slot_accepts: [:step]` refuses it too, without that host knowing the type
exists - which is the coupling
decision 3's subsumption argument was written to avoid, arriving here
unchanged.

The mechanism reaches exactly as far as a declaration does, and no further. A
host container that declares no `io/1` at all takes decision 5's default,
which is `slot_accepts` `:any` for every slot, and `:any` admits everything -
including a shelf. That is not a gap in this section but the boundary of what
kinds can decide, and it is the second of the two cases ADR-0002's amendment
of this date, section G12, keeps as a Structure-stage rule.

`slot_accepts: %{"body" => :any}` is the other half and it is deliberately the
most permissive declaration this record admits. A shelf exists to hold a
fragment an author has not decided about yet. Refusing a fragment on the
grounds that it would not fit where it is not being placed would be this
record answering a question nobody asked, and it would refuse hardest exactly
the interrupt handlers and half-built containers an author most wants to park.
Decision 5's permissive reading of `:unknown` is the same argument at the
data-flow layer; this is it at the structural one.

**What the kind cannot say is G12's, not this record's.** That the root
block's `body` admits a `:draft_shelf` anyway, and that it admits at most one,
are a depth constraint and a cardinality constraint. Neither is an
intersection of a parent's `slot_accepts` with a child's `kinds`, so neither
is expressible here, and ADR-0002's amendment of this date puts both in the
Structure stage as findings under campaign-024 ruling R-b. Decision 3's claim
to subsume ADR-0002's placement special case is unaffected: it subsumed a
parent-type constraint, which these are not.

### A2. The data-flow walk does not enter the shelf, and every fragment starts from `:unknown`

Decision 4 defines a position's inbound type as the `produces` of the sibling
at `index - 1`, or the slot inbound at `index == 0`. Inside a `core.drafts`
body, that definition would answer, and its answer would be wrong in both
positions:

- Between two shelved fragments there is no seam. Their order is shelf order -
  what the author dropped where - and G9a fixes that the compiler never reads
  it as sequencing. Deriving one fragment's inbound type from the fragment
  above it on the shelf would make rearranging a shelf produce and clear
  findings, which is exactly the sequencing meaning the shelf is defined not
  to have.
- At `index == 0` the slot inbound would be the shelf's own inbound type, and
  the shelf has none: it declares no `consumes`, it is not in the flow, and
  nothing reaches it.

So: **the data-flow walk treats every direct child of a `core.drafts` body as
being at entry, with inbound type `:unknown`.** Under decision 5 `:unknown` is
assignable to any `consumes`, so no fragment is ever refused for the position
it holds on the shelf, and no fragment's position on the shelf ever produces a
finding.

**The walk still runs inside each fragment.** A parked fragment is a subtree,
its own internal seams are real sequencing, and they are checked exactly as
they would be anywhere else - starting from `:unknown` at the fragment's root,
which is what decision 4 already specifies for the entry position when the
caller supplies no entry type. That is the property that makes the shelf worth
having rather than a hole in the checker: an author who parks a three-block
fragment is told about a broken seam *inside* it while it is parked, and is
not told a second, meaningless thing about where on the shelf it sits.

**Structural checking is not suspended either.** Kind admission, slot arity
and `:undeclared_slot` run over shelved fragments as over everything else,
because `slot_accepts: :any` is a claim about what the shelf's own `body`
admits and says nothing about what a fragment's own slots admit. A parked
`core.group` still refuses an ordinary step in its `interrupts` slot.

### A3. `core.placeholder` declares no `io/1` at all

The marker type takes decision 5's permissive default in full: `kinds:
[:step]`, `consumes: :unknown`, `produces: :unknown`, and `slot_accepts` `:any`
for every slot, of which it has none. A gap goes wherever a step goes and
constrains neither neighbour.

Declaring anything narrower would be this record deciding what an author's
unwritten step was going to do, and the `{:fixable_by, _}` machinery the
2026-08-29 amendment added under 8a would then explain a refusal in terms of a
claim nobody made. `:unknown`
is the honest answer to "what does the step you have not written yet produce",
and decision 5's adoption-curve argument for `:unknown` being permissive rather
than a bottom is the same argument here: a marker that refused its own
neighbours would be a marker nobody placed.

### Consequences

- The shelf's admission rule costs one kind and no new mechanism. Every
  existing container, core and host alike, refuses a shelf today, on
  declarations that were already written for other reasons.
- The 2026-08-29 amendment's reason vocabulary is unchanged, and it is
  untouched here in the strongest sense: a `:draft_shelf` refused by a
  `[:step]` slot is a `{:kind_not_admitted, ...}` refusal, and section 8c
  states that those get no reason from the vocabulary at all - the structural
  gate's own finding code, naming both kind sets, is the whole explanation.
  Nothing is added to the vocabulary and no arm is amended.
- A host that wants its own shelf mints its own kind, its own container, and
  its own structure rule - or asks for this one to be widened, which
  ADR-0002's amendment of this date, section G12c, records is additive.
- The `:any` slot means a fragment can be parked in a state that could never
  be placed anywhere. That is the intended cost and it is bounded: the
  fragment is checked internally while parked, and the moment an author moves
  it into the flow the ordinary seam and kind rules decide it, with the same
  findings and the same reasons they would have given if it had been dropped
  there directly.

## Note (2026-09-06): ADR-0011 supersedes decisions 1, 2, 4, 5 and 6

A dated note rather than an amendment, and a pointer rather than a decision:
nothing in this record's text changes, no line above is edited, and every
superseded decision keeps every word it has. The note exists because a reader
who lands on decision 4 should find out here that a later record answers it,
rather than after implementing it.

`ADR-0011` records that every value a shipped block produces is written to a
datamodel path by name, so the data-flow question is not a question about the
sibling at `index - 1`. It replaces the seam with a pre-order walk carrying an
environment from datamodel path to type, and it names the five decisions of
this record it reaches, with their headings quoted, in its own "What this
record supersedes, and what it leaves standing" section:

- **decision 1**, the opaque string and string identity - superseded by
  relocation: identity is still the rule and it is `sd-ADR-0001` decision 8's
  rule, defined once in the package that owns the datamodel document.
- **decision 2**, `io(config)`'s three keys as the whole declaration surface -
  `kinds` and `slot_accepts` are untouched; `consumes` and `produces` become
  sugar over a subject path, and the declaration surface for reads and writes
  moves onto the field, as `{:path, %{expects: T}}` and `{:path, %{writes: T}}`.
- **decision 4**, the seam and the walked inbound type - superseded by
  replacement. The walk survives; what it carries does not.
- **decision 5**, `:unknown` permissive in both positions - superseded by
  relocation, for the same adoption-curve reason, as `sd-ADR-0001` decision 8's
  first step.
- **decision 6**, the host-supplied widening module - superseded by narrowing.
  The module stays on the palette and its one-way property is kept and
  strengthened: it now runs after record-into-shape coverage as well as after
  identity, so the floor it cannot lower is a higher floor than it was.

**Decisions 3, 7, 8 and 9 stand as accepted**, and so do both amendments
above. Decision 3's kind tags are untouched in every clause. The 2026-08-29
amendment's reason vocabulary keeps its five arms and gains a sixth,
`:shape_not_satisfied`, in `ADR-0011` decision 8; decision 8's two finding
tuples gain no member. The 2026-08-31 amendment's A2 - the data-flow walk does
not enter the shelf - is carried forward verbatim in effect, with a parked
fragment walked from an empty environment.
