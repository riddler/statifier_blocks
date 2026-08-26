# ADR-0003: Assignability is opaque-string identity plus a host-supplied widening relation

Status: accepted (2026-08-26)

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
hosts genuinely do have widening: a host whose `myapp.contact` and
`myapp.lead` both satisfy the shape a generic notify step wants has a real
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
string identity.** `"record"`, `"score"`, `"myapp.contact"`. This package
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

A multi-tenant host embedding the engine, whose records widen: `myapp.lead`
and `myapp.contact` both satisfy anything that wants a bare `myapp.person`.
The host declares that once.

```elixir
defmodule MyApp.Blocks.Types do
  @behaviour StatifierBlocks.Assignability.Relation

  @widens %{
    "myapp.lead" => ["myapp.person"],
    "myapp.contact" => ["myapp.person"],
    "myapp.scored_lead" => ["myapp.lead", "myapp.person"]
  }

  @impl true
  def assignable?(produced, consumed),
    do: consumed in Map.get(@widens, produced, [])
end

palette = %StatifierBlocks.Palette{
  types: Map.merge(StatifierBlocks.Palette.core(), %{
    "myapp.enrich" => MyApp.Blocks.Enrich,
    "myapp.score" => MyApp.Blocks.Score,
    "myapp.notify" => MyApp.Blocks.Notify,
    "myapp.on_cancel" => MyApp.Blocks.OnCancel
  }),
  assignability: MyApp.Blocks.Types
}
```

Its palette entries declare what they are and what they move:

```elixir
# Takes a raw record, hands back a lead.
def io(_config), do: %{consumes: "myapp.record", produces: "myapp.lead"}      # enrich

# Takes a lead, hands back a scored lead.
def io(_config), do: %{consumes: "myapp.lead", produces: "myapp.scored_lead"} # score

# Takes anyone with contact details; produces nothing anyone downstream wants.
def io(_config), do: %{consumes: "myapp.person", produces: :unknown}          # notify

# Not a step at all.
def io(_config), do: %{kinds: [:interrupt_handler]}                           # on_cancel
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

Now the document from ADR-0001's worked example, with a `myapp.score` step
(`blk_SCR`) added after the enrich, and entry type `"myapp.record"` supplied by
the host in the context. Walking the `body` of the root sequence:

| Position | Inbound | Candidate consumes | Verdict |
|---|---|---|---|
| before `blk_ENR` | `"myapp.record"` (entry type) | enrich wants `"myapp.record"` | identity, step 2 |
| after `blk_ENR` | `"myapp.lead"` | score wants `"myapp.lead"` | identity, step 2 |
| after `blk_SCR` | `"myapp.scored_lead"` | notify wants `"myapp.person"` | **host widens**, step 4 |
| after `blk_SCR` | `"myapp.scored_lead"` | enrich wants `"myapp.record"` | no - `:type_mismatch` |
| inside `interrupts` | - | notify is `[:step]` | no - `:kind_not_admitted` |
| inside `interrupts` | - | on_cancel is `[:interrupt_handler]` | admitted |
| inside `body` | - | on_cancel is `[:interrupt_handler]` | no - `:kind_not_admitted` |

Reading the interesting rows:

- **The host relation widening, and only widening.** `"myapp.scored_lead"` ->
  `"myapp.person"` is not identity, so step 4 asks the host, which says yes.
  Delete `assignability: MyApp.Blocks.Types` from the palette and that one row
  flips to a mismatch while every other row is unchanged - the identity rows
  never reached the callback (decision 6).
- **Both directions of the structural gate.** The last three rows are the
  subsumption of ADR-0002 decision 10 in decision 3. The old special case gave
  only the third of them; kind tags give all three from two declarations.
- **`:passthrough` earning its keep.** `blk_GRP` is a `core.resumable_group`
  whose `body` ends in the branch, and the branch declares `produces:
  :unknown`, so everything after the group is unconstrained. Had the group's
  body ended in a scored lead instead, `{:passthrough, "body"}` would have
  carried `"myapp.scored_lead"` out past the group with no lattice and no
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
#=> {:error, [{:type_mismatch, "blk_EN2", "blk_SCR", "myapp.scored_lead", "myapp.record"}]}
```

The acceptance property for this record: those two calls consult one
implementation and one host relation, reached through one palette value, so
there is no arrangement of code in which the editor lights up a slot the
compiler would reject.
