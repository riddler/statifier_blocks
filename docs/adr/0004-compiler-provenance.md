# ADR-0004: One block, one state - a deterministic compile carrying a provenance map

Status: accepted (2026-08-26)

## Context

ADR-0001 fixed the document: a tree of `{type, id, config, slots}` nodes with
stable, document-unique, never-reused block ids, canonically encoded so that
`:crypto.hash(:sha256, canonical_json)` is a usable **document identity**.
ADR-0002 fixed the extension seam: a block type is a behaviour module resolved
through a caller-supplied palette, every callback a pure function of its
arguments, with `emit/2` listed as required and its signature explicitly left
to this record.

Both records deferred four things here, and this record owes an answer to each:

- `emit/2`'s signature, the emit context, and the SCXML subtree representation
  (ADR-0002 decision 11);
- state-id generation and how emission is keyed back to block ids
  (ADR-0002 decision 11);
- how the document's identity relates to the engine's chart identity
  (st-ADR-0052), which ADR-0001 decision 8 left deliberately unrelated and
  named as this record's call;
- whether the compiler lints the two-registry gap ADR-0002's consequences
  named - a block type whose emitted invoke type has no handler registered
  under st-ADR-0051 fails at runtime with `error.execution`, not at authoring
  time.

Four forces shape the answers.

**The compile is one-way, and that is the whole point.** The block document is
authoritative; SCXML is generated; there is no reverse edge. Nothing parses
generated SCXML back into blocks, which frees the compiler to emit whatever
SCXML expresses a block's meaning best, with no obligation to preserve any
property that would make it re-readable. What it must preserve instead is
*correspondence*: which generated element came from which block. That is the
provenance map, and it is the only thing that has to survive the one-way trip.

**Validation should come free.** Statifier ships a strict four-stage pipeline -
`Statifier.Parser.parse/1`, `Statifier.Lowering.lower/2`,
`Statifier.Validator.validate/3`, `Statifier.Compiler.compile/1`, fronted by
`Statifier.compile/2` - whose validator runs twenty error checks against a
conformance corpus with a regression ratchet behind it (st-ADR-0006). A second
semantic validator written against block documents would be a second
implementation of the same rules that must agree with the first, and every
disagreement would surface as a document the editor accepts and the engine then
rejects. ADR-0002 decision 7 made exactly this argument for `config_schema/1`
versus `validate_config/1` at the field level; it applies with more force at the
chart level, where the rules are subtler and upstream's are already tested. So:
generate the SCXML, run it through the engine's own pipeline, and map the
findings back through provenance. This package validates *config* (ADR-0002) and
*structure* (ADR-0001, sb-7rx) and delegates every chart-semantic judgment.

**Determinism is a precondition, not a nicety.** A provenance map captured at
publish time is useless if recompiling an unchanged document produces different
state ids. A read-only diagram highlighting the active block during a run
depends on the running chart's state ids matching the map the host stored. And
st-ADR-0052 makes it sharper than that: chart identity is a hash of the SCXML
**source bytes**, so it is whitespace-sensitive, and two compiles of one document
that differ by a single space produce charts that refuse to interoperate. Byte
determinism is not a quality goal here, it is a correctness requirement of the
resume path. ADR-0001 decision 8 bought the input half with a canonical
encoding; this record owes the output half.

**Compilation has inputs the document hash does not cover.** The palette is a
caller-supplied value (ADR-0002 decision 2) and this package's emission logic is
code. A determinism claim naming only the document is false the first time a host
swaps a palette entry or upgrades this package. Whatever identity story this
record tells has to be honest about all three inputs.

## Decision

**1. Compilation is a total function of `{document, palette}` producing one
artifact.** No process state, no global registry, no IO, no clock - the same
purity ADR-0002 decision 4 imposed on the callbacks, imposed on the pipeline
that calls them. `Compiler.compile/3` returns `{:ok, %Compiled{}}` or
`{:error, [finding]}`, never raises, and never partially succeeds. The artifact
carries the generated SCXML, the provenance map, the compilation record
(decision 7), the emitted invoke types (decision 8), and any warnings.

Nothing in the artifact is written back into the document. ADR-0001 decision 2
forbade storing derived data in the document and named the provenance map
specifically; this record does not reopen it. A host stores the artifact beside
the document or recomputes it - both are correct, and decision 6 is what makes
them equivalent.

**2. One block compiles to exactly one state, and completion is signalled by
`done.state`.** This is the load-bearing decision of the record; most of the
rest follows from it.

Every block compiles to exactly one SCXML state element - atomic, compound,
`<parallel>`, or `<final>` as its block type chooses - whose id is
`state_id(block_id)` (decision 3). A block signals that it is finished by that
state reaching done in the SCXML sense: a compound state whose configuration
enters a `<final>` child raises `done.state.<state id>`, per the Appendix-D
semantics statifier ports literally (st-ADR-0002).

That convention is what makes `emit/2` composable. A structural parent needs to
know nothing about how its children are built - not their internal states, not
their events, not their datamodel usage. It needs two things computable from a
child's block id alone: the child's state id, and the `done.state.<state id>`
event it raises. `core.sequence` therefore emits a compound state whose children
are the child states, wired by transitions on `done.state.<previous child>`;
`core.parallel` emits a `<parallel>` whose regions wrap the lane children;
`core.branch` emits a compound state whose initial child is a transient state
carrying one conditional transition per arm. None of them reads a child's
emission.

The alternatives were considered and rejected. Letting a block emit an arbitrary
set of sibling states with a declared entry and exit would make provenance a
many-to-many relation and make the runtime lookup in decision 5 ambiguous.
Threading an explicit "next state" continuation through the context would make
every block's emission depend on its position in its parent, which destroys
decision 6's property that an unedited subtree compiles to unchanged bytes.
`done.state` is what SCXML already supplies for exactly this purpose.

A block type needing auxiliary states - a retry wrapper with a backoff holding
state - emits them as **children of its own state**, with ids minted through the
context's role minting (decision 3). They are inside the block's state, so they
are inside the block's provenance, and the parent above is unaffected.

**3. State ids are derived from block ids by a pure function, and every
generated state has one.**

```
state_id(block_id)       = "s_" <> block_id
state_id(block_id, role) = "s_" <> block_id <> "__" <> role
```

A block id is already stable, document-unique, opaque, and never reused
(ADR-0001 decision 3), so a state id derived from it inherits all of that for
free, and inherits it *per block* rather than per document. That is the property
that matters: editing one block's config, or inserting a block at the top of a
sequence, changes the ids of nothing else. A counter - `s1`, `s2`, `s3` in
traversal order - would renumber every state after an insertion point,
invalidating a stored provenance map, making a publish diff unreadable for a
human reviewer, and breaking any diagram captured against the previous revision.

`role` is a short, block-type-chosen local name for an auxiliary state, minted
through `Context.role_id/2` rather than by string concatenation inside the block
type, so the compiler owns the namespacing and can guarantee the properties
below. Roles match `~r/\A[a-z][a-z0-9_]*\z/`; the compiler refuses any other
role rather than emitting an id it cannot invert.

Three properties, and they are the acceptance tests for this decision:

- **Uniqueness.** Block ids are document-unique, a `blk_`-prefixed UXID contains
  no `__`, and roles cannot contain `__`, so no two generated ids collide
  whatever a block type does. This matters more than it looks: statifier's
  uniqueness check is over *all* `ID`-typed attributes in one set, so a
  generated state id colliding with a `<data id>` is as much a
  `{:duplicate_id, id}` error as two states colliding. The `s_` prefix keeps the
  two namespaces apart by construction.
- **Invertibility.** `state_id` is injective and `unstate_id/1` inverts it
  without consulting the provenance map. The map is the contract, but a human
  reading generated SCXML in a diff can still see which block a state came from.
- **Totality.** Every generated state carries an id. Statifier permits nameless
  states, but a nameless state is unnameable at the boundary:
  `Statifier.active_leaf_states/1` drops it, and `Statifier.Position.export/1`
  refuses the whole export with `{:error, {:unnameable_states, indexes}}`. Since
  the diagram-highlighting use case reads active leaf states and the persistence
  path exports positions, a nameless generated state would break both. This
  package emits none.

The `<scxml>` element's `name` attribute carries the document id and its
`initial` names the root block's state. No id in the generated chart comes from
anywhere but this function or an author's own config (decision 9).

**4. `emit/2` receives a block and a context, and returns an emission.** The
signature ADR-0002 decision 5 reserved:

```elixir
@callback emit(Block.t(), Context.t()) :: {:ok, Emission.t()} | {:error, [finding()]}
```

The compiler walks the document bottom-up: it resolves and migrates each block
through the palette (ADR-0002 decision 8), validates its config, recurses into
each declared slot in `slots/1` declaration order, and only then calls `emit/2`
with the children already compiled. The context carries what a block type is
entitled to know and nothing more:

- `block_id` and `state_id` - the block's own, precomputed;
- `children` - slot name to ordered list of child summaries, each carrying only
  `block_id`, `state_id`, and `done_event`. A child's emitted SCXML is *not* in
  the context. A parent that could read it would be a parent that could depend
  on it, and decision 2 exists to prevent that;
- `role_id/2` - the minting function from decision 3;
- `document_id` - for the rare type that names the document in a send target.

The palette is deliberately absent. A block type resolving another block type
would be a block type compiling its own children, which is the compiler's job,
and would make `emit/2`'s purity depend on a value it did not receive.

`Emission.t()` is a structural representation of one SCXML subtree - element
name, attributes, children, with executable content as nested elements - and not
a string. The compiler serializes it once, at the end, deterministically. A
block type building XML text would own escaping, namespace handling, and
attribute-value normalization (st-ADR-0043), all easy to get subtly wrong, none
of them a block-type author's business, and all of them - per st-ADR-0052's
whitespace sensitivity - able to change chart identity by accident.

`{:error, findings}` is an ordinary arm: a type that can validate its config but
still cannot compile some combination reports findings against its own block id
rather than raising.

**5. The provenance map is keyed two ways, because it answers two different
questions.** The brief names both, and they need different keys.

*Runtime highlighting* starts from a running session, whose active configuration
is a list of **state ids** (`Statifier.active_leaf_states/1`). So the map needs
`by_state_id: %{state_id => owner}`, and decision 3's totality is what makes it
complete.

*Error routing* starts from a `%Statifier.Validator.Error{}`, and this is where
the design has to follow upstream rather than wish. Upstream findings do **not**
carry an element reference field. They carry `{reason, message, location}`,
where `location` is a `%Statifier.Parser.Location{}` - 1-based line and column,
0-based byte offsets, exclusive end - and the offending ids ride *inside* the
closed `reason` tuple as data. Every diagnostic struct in the pipeline shares
that three-field shape.

So the map's second key is a **byte span over the generated SCXML**:
`spans: [{span, owner}]`, and mapping a finding is "the innermost span
containing `location.start_offset`". The compiler is the serializer, so it knows
every emitted element's span exactly; recording it costs one accumulator. This
key is strictly more general than an id-based one - it routes findings about
transitions, which have no id of their own in SCXML, and findings whose reason
tuple carries no id at all.

An `owner` is `{block_id, role_or_nil, config_key_or_nil}`. The role
distinguishes a block's own state from one it minted (decision 3). The config
key is populated for spans emitted verbatim from an author's config - a `cond`
built from an `:expression` field, a `<data id>` built from an `assign_to`
field - and decision 9 is what makes it load-bearing.

**The map is total over the emission.** Every span the compiler emits has an
owner; there is no unowned scaffolding. Chart-level elements belonging to no
particular block - the `<scxml>` element, the root datamodel - are attributed to
the **root block**, which ADR-0001 decision 1 guarantees exists. Totality is
what makes decision 9's mapping a total function rather than one with an
`:unmapped` arm every consumer must handle and none can act on. An unmapped span
is a compiler bug, and it is checkable as a property over the artifact.

The map serializes as JSON under ADR-0001 decision 8's canonical rules, so a host
can store it beside the SCXML, diff it, and read it from non-Elixir tooling. It
is not part of the document and carries no `schema_version` of its own; it is
versioned by the compilation record's compiler version.

**6. Determinism is guaranteed over a triple, and the guarantee runs one way
only.**

> For a fixed `{document canonical bytes, palette, compiler version}`, the
> generated SCXML is **byte-identical** and the provenance map is equal, on every
> machine and every run, forever.

All three inputs are named because all three are real. The document is covered by
ADR-0001 decision 8. The palette is a caller-supplied value whose entries are
modules whose `emit/2` is pure (ADR-0002 decision 4), so swapping a palette entry
changes a compile input even though the document did not move. The compiler
version is this package's, and any change to emission that moves bytes bumps it -
a release-discipline obligation this record creates on itself.

*Byte-identical* is the operative word, and st-ADR-0052 is why. Chart identity
hashes the source bytes, so indentation, attribute order, and empty-element
spelling are all identity-bearing. The serializer therefore fixes them: attributes
in sorted order, one canonical empty-element form, no incidental whitespace, and
no iteration over a bare map anywhere in the pipeline. Slots emit in `slots/1`
declaration order, which ADR-0002 decision 6 already made meaningful.

The guarantee is **not** reversible and must not be read as one. Equal output does
not imply equal input: a `metadata`-only edit changes the document hash and
produces identical SCXML, because `metadata` is not compiled. A host may use
"same triple" to skip a recompile, and may **not** use "same SCXML" to conclude
the document is unchanged.

**7. Document identity and chart identity are hashes of different artifacts;
the compiler computes the second and records the join.** This is the question
ADR-0001 decision 8 left open.

The first thing to get right is what chart identity actually is. Per
st-ADR-0052, `Statifier.Machine.Identity.of_source/2` is SHA-256 over the SCXML
**source bytes** - `"sha256:" <> lowercase hex` - carried alongside an optional
`:chart_name` and `:chart_version`, and stamped onto every `Machine` that
`Statifier.compile/2` produces. It is not a hash over a normalized chart.

That makes the relation concrete rather than mysterious. Document identity
hashes what an author *wrote*; chart identity hashes what the compiler
*generated*; and decision 6's determinism is the function between them:

```
document bytes + palette + compiler version  --compile-->  SCXML bytes
        |                                                       |
     sha256                                                  sha256
        v                                                       v
 document identity                                      chart identity
```

Three consequences follow, and they are the decision:

*The compiler computes chart identity rather than inventing one.* It calls
`Identity.of_source/2` on the bytes it just serialized - or equivalently reads
`Machine.identity/1` off the machine it already compiled in decision 9. There is
one implementation of that hash and it lives upstream. This package never
constructs an `%Identity{}` field-by-field.

*Neither identity is derived from the other, and neither should be.* Deriving
chart identity from the document hash would be hashing the wrong bytes: two
documents differing only in `metadata` generate identical SCXML and must get the
same chart identity, or a metadata edit would break resume for every running
session. Deriving document identity from chart identity is not even a function -
the mapping is many-to-one in exactly that case, so there is no inverse.

*`chart_version` stays `nil`, and `chart_name` carries the document id.*
`Identity.matches?/2` is struct equality across all three fields, and resume
(st-ADR-0060) refuses on `{:identity_mismatch, expected, actual}`. So putting the
document `revision` in `chart_version` would break resume on every save, and
putting the document hash there would break it on a metadata-only edit - which is
precisely the case decision 6 established as a non-event. The document id is
constant across revisions and is safe; the revision is not, and belongs in the
compilation record instead, where nothing compares it.

*The join is recorded, because the reverse direction is not computable.* What a
host actually needs is to take a running session, which names a chart identity,
and get back to the document and provenance map that explain it. Hashes do not
invert. So the compiler emits the join as a fact:

```
%CompilationRecord{
  document_id:      Document.id(),
  revision:         non_neg_integer(),
  document_hash:    binary(),     # ADR-0001 decision 8
  palette_hash:     binary(),     # decision 6's second input
  compiler_version: String.t(),   # decision 6's third input
  chart_identity:   Identity.t()  # st-ADR-0052, computed upstream
}
```

`palette_hash` is a digest over the sorted `{type_name, module, current_version}`
triples of the entries the compile actually resolved. It is not a cryptographic
commitment to those modules' behaviour - nothing short of hashing compiled beam
would be - and this record does not pretend otherwise. It exists so the common
cause of a surprising recompile, a host adding or swapping a palette entry, is
visible in the record instead of invisible. A host that changes an `emit/2`
without bumping `current_version/0` has moved a compile input without moving the
record; that is a palette-hygiene obligation on the host, stated here so it is
not discovered later.

The record is the artifact's primary key: given a session, look up by
`chart_identity` and get the document, the revision, and the map.

**8. The two-registry gap is surfaced as data, linted only on request, and never
a compile error.** ADR-0002's consequences named the gap and left it to this
record and sb-w50. The answer has three parts.

*The compiler always publishes what it emitted.* `%Compiled{}` carries
`invoke_types`, the sorted set of invoke type strings appearing in the generated
SCXML, and the provenance map resolves each back to the blocks that emitted it.
This part is unconditionally right, because it is a fact about the compile and
nothing else.

*The lint is optional and produces warnings.* `compile/3` accepts
`:known_invoke_types`, a set the caller believes will be registered. When
supplied, the compiler emits a warning naming the block id and the invoke type
for every emitted type absent from the set. When not supplied it emits nothing.
The finding is a warning, never an error, matching the tier upstream established
for its own validator (st-ADR-0033). Note the set the host would pass is exactly
`Map.keys(invoke_handlers)` from its `Statifier.Session` options - the same map
st-ADR-0051 turns into `Statifier.Invoke.Types` - so the comparison is over the
same strings the runtime classifier will use.

*It is not a compile error, and the reason is a lifetime mismatch, not
timidity.* st-ADR-0051 made the handler set **deployment state, supplied per
session and fixed for the session's lifetime**. The palette is authoring state,
supplied per operation. ADR-0002 decision 2 named that cadence difference
explicitly, and ADR-0002's consequences blessed the authoring server that never
runs a chart and therefore has no handler map at all. If a missing handler failed
the compile, that host could not compile, and this package would have made a
runtime concern a precondition of authoring. Worse, it would be *wrong* even
where a set is available: a host may compile in an authoring service and run in a
worker with a different registration, so any set handed to the compiler is one
deployment's belief, not ground truth. A warning is the strongest claim the
evidence supports.

The real fix is neither: it is the host comparing `invoke_types` against its
registration at **deploy time**, when it knows both. The compiler's job is to make
that a one-liner over a field it already published, and it does. Whether the
editor surfaces the mismatch live while authoring is a presentation decision over
data this record supplies, and it is **sb-w50's**.

**9. Chart-semantic validation is delegated entirely, and mapped findings are
split by whose fault they are.** The compiler serializes the emission, runs
`Statifier.compile/2` over it, and maps every resulting finding through
provenance. This package ships no reachability analysis, no transition-target
check, no id-uniqueness check, and no expression well-formedness check; adding one
later is a change to this decision. Upstream warnings are read off
`Machine.warnings/1`, which st-ADR-0033 made their only surfacing seam.

Mapping is total by decision 5: take the finding's `location.start_offset`, find
the innermost owning span, attach the block id, role, config key, and the block's
path (ADR-0001 decision 5) so the editor can reveal it in the tree without
walking the document. Upstream's `message` and severity survive verbatim, and
upstream's document-order sort survives as block-path order.

The split is the part worth stating carefully, because an earlier draft of this
record got it wrong. Chart-stage findings are of two kinds:

- **Structural findings are bugs in this package or in a host's block type,
  never the author's doing.** `{:unresolved_target, id}`,
  `{:initial_not_descendant, id, parent}`, `{:transition_count, owner, count}`,
  a malformed namespace: an author cannot express any of these, because the block
  vocabulary has no way to name them. Their owning span has `config_key: nil`.
  The block id says where the bug is, not where the author erred, and the editor
  should say so - "this cannot be fixed here" is the only honest message.
- **Content findings are the author's, and they carry a config key.** An
  `:expression` config field (ADR-0002 decision 7) is a predicator source string
  passed through verbatim into a `cond`; if it does not parse, upstream returns
  `%Statifier.Compiler.Error{}` with reason
  `{:expression_compile_error, owner_ref, source, %Predicator.Errors.ParseError{}}`.
  That is squarely the author's typo. Likewise two blocks whose `assign_to`
  fields collide produce a genuine `{:duplicate_id, id}` over `<data>` elements.
  These map to a block id **and a config key**, which is what lets the editor put
  the error on the field the author typed into rather than on the block as a
  whole.

Content findings get one refinement. The predicator parse error carries a span
within the expression string, and statifier ships `Location.resolve_span/3` to
compose such a span into an absolute document span. Running that composition
backwards through provenance yields an offset *within the author's config value*,
so the editor can underline the offending sub-expression inside the field. This is
the payoff for keeping spans rather than ids as the routing key, and it is
available for free.

An upstream **error** of either kind fails the compile; a warning does not, and
rides on `%Compiled{}`.

**10. Compile findings are ordered, typed, and always name a block.** The
pipeline stops at the first stage producing errors and reports every error from
that stage:

| Stage | Errors it can produce |
|---|---|
| Resolve | `:unknown_block_type`, `:block_type_too_new` (ADR-0002 decision 3) |
| Config | `validate_config/1` findings (ADR-0002 decision 7) |
| Structure | arity violations, `:undeclared_slot` (ADR-0002 decision 6); assignability (sb-7rx) |
| Emit | `emit/2` findings, `:invalid_role` (decision 3) |
| Chart | mapped statifier findings, both kinds (decision 9) |

Stopping at the first failing stage rather than accumulating across stages is
deliberate: a document with an unresolvable block type has no meaningful
structural check to run, and reporting a cascade of consequences beside the cause
is how an error panel becomes noise. Within a stage every finding is reported,
because those are siblings rather than consequences - the same collect-all
discipline upstream's validator applies within its own pass.

Every finding names a block. There is no chart-level finding without an owner;
decision 5's totality buys that, and it is what lets the editor render findings as
annotations on the tree with no fallback presentation.

**11. What this record does not decide.**

- **Assignability (sb-7rx)** owns `io/1`'s return shape and the compatibility
  relation. This record fixes only that assignability runs in the Structure
  stage, before Emit, and that its findings are shaped like the rest.
- **The editor (sb-w50)** owns how findings are presented, whether the
  two-registry mismatch is surfaced live, and how the provenance map drives
  highlighting in a read-only diagram.
- **Chart identity (st-ADR-0052)** and the **invoke-handler registry
  (st-ADR-0051)** are statifier-ex's. This record is a client of both and
  changes neither.
- **The document schema (ADR-0001)** is untouched. Nothing this record produces
  is stored in the document, and `schema_version` stays at `1`.

## Consequences

- The provenance map makes the one-way compile survivable. An author sees an
  error on the block they wrote even though it was found on generated SCXML by a
  validator that has never heard of blocks, and a read-only diagram highlights the
  active block by mapping `active_leaf_states/1` through `by_state_id`.
- Keying error routing on byte spans rather than element ids means the compiler
  must be the serializer and must record spans as it writes. That is a real
  constraint on the implementation - emission and serialization cannot be
  separated by a naive `to_string` - and it is the price of routing findings that
  carry no id at all.
- Deriving state ids from block ids makes generated SCXML readable in a diff by
  someone who knows the document. It also makes state ids long and ugly. That is
  the right trade for generated code nobody writes by hand, and it is why
  decision 3 keeps the derivation invertible: the ugliness buys something.
- "One block, one state" is a real constraint on block-type authors. A type
  wanting two sibling states must emit one state containing them. In every case in
  the core vocabulary that is what the type wanted anyway, but a host will
  eventually find a case where it chafes, and the answer is auxiliary states inside
  its own state, not an amendment.
- Because chart identity hashes source bytes, this package's serializer is now
  identity-bearing code. A stray formatting change is not cosmetic: it changes
  every chart's identity and invalidates every persisted position. This is the
  single sharpest edge in the record, and it is why the compiler version is a
  declared axis in decision 6 rather than an implementation detail.
- Because chart-semantic validation is delegated, this package inherits
  upstream's validator improvements for free and its regressions too. Upstream's
  regression ratchet (st-ADR-0006) is load-bearing for this package now, which is
  a dependency worth being explicit about. A new upstream error variant also
  arrives here unclassified, and decision 9's two-kind split means someone has to
  decide which kind it is - a small, recurring maintenance obligation.
- Because a structural finding is by construction a bug rather than an author
  error, the acceptance corpus for this package should drive every core block type
  through compile-and-validate. A structural finding at that tier is a failing
  test, not a diagnostic.
- The compilation record obliges a host to store something beside the document. A
  host storing only the document can still recompile to recover everything - the
  record is a cache key, not a source of truth - but it cannot answer "which
  document is this running session from" without a walk.
- Two registries remain two registries. This record does not unify them, and a
  host wiring `myapp.enrich` still does two things. What changed is that
  forgetting the second is now detectable from data the compiler publishes, at the
  moment the host actually knows the answer.

## The contract as typespecs

```elixir
defmodule StatifierBlocks.Compiler.Emission do
  @moduledoc "A structural SCXML subtree. Serialized by the compiler, never by a block type."

  @type t :: %__MODULE__{
          element: String.t(),
          attrs: %{optional(String.t()) => String.t()},
          children: [t()]
        }

  defstruct [:element, attrs: %{}, children: []]
end

defmodule StatifierBlocks.Compiler.Context do
  @moduledoc """
  What a block type is entitled to know when it emits (ADR-0004 decision 4).
  Deliberately excludes the palette and every child's emitted subtree.
  """

  alias StatifierBlocks.{Block, Document}

  @typedoc "A compiled child, reduced to what a structural parent needs."
  @type child :: %{
          block_id: Block.id(),
          state_id: String.t(),
          done_event: String.t()
        }

  @type t :: %__MODULE__{
          block_id: Block.id(),
          state_id: String.t(),
          document_id: Document.id(),
          children: %{optional(Block.slot_name()) => [child()]}
        }

  defstruct [:block_id, :state_id, :document_id, children: %{}]

  @doc ~S"""
  Mints an auxiliary state id inside this block's own namespace
  (ADR-0004 decision 3). `role` must match `~r/\A[a-z][a-z0-9_]*\z/`.
  """
  @spec role_id(t(), role :: String.t()) :: String.t()
end

defmodule StatifierBlocks.Provenance do
  @moduledoc """
  Which generated element came from which block. Total over the emission
  (ADR-0004 decision 5). Keyed two ways: by state id for runtime highlighting,
  by byte span for routing upstream findings, which carry a
  `%Statifier.Parser.Location{}` and no element reference.
  """

  alias StatifierBlocks.Block

  @typedoc "Byte offsets into the generated SCXML. Exclusive end, as upstream."
  @type span :: {start_offset :: non_neg_integer(), end_offset :: non_neg_integer()}

  @typedoc """
  `role` is `nil` for the block's own state, a role name for one it minted.
  `config_key` is set when the span was emitted verbatim from that config
  field, which is what makes a finding the author's rather than a bug.
  """
  @type owner :: %{
          block_id: Block.id(),
          role: String.t() | nil,
          config_key: String.t() | nil
        }

  @type t :: %__MODULE__{
          by_state_id: %{optional(String.t()) => owner()},
          spans: [{span(), owner()}]
        }

  defstruct by_state_id: %{}, spans: []

  @doc "Innermost span containing the offset. Total by decision 5."
  @spec owner_at(t(), offset :: non_neg_integer()) ::
          {:ok, owner()} | {:error, {:unmapped_offset, non_neg_integer()}}

  @doc "For mapping a running session's `Statifier.active_leaf_states/1`."
  @spec owner_of_state(t(), String.t()) :: {:ok, owner()} | :error

  @doc "Canonical JSON, ADR-0001 decision 8's rules. Deterministic."
  @spec to_json(t()) :: binary()
  @spec from_json(binary()) :: {:ok, t()} | {:error, term()}
end

defmodule StatifierBlocks.Compiler do
  @moduledoc "Deterministic one-way compile. Pure; no IO, no clock, no process state."

  alias StatifierBlocks.{Block, Document, Palette, Provenance}

  @type stage :: :resolve | :config | :structure | :emit | :chart

  @typedoc """
  `:package` findings are bugs here or in a host's block type; `:author`
  findings are the author's and carry a `config_key` (decision 9).
  """
  @type fault :: :package | :author

  @typedoc "Every finding names a block. There is no unowned finding (decision 10)."
  @type finding :: %{
          block_id: Block.id(),
          path: Document.path(),
          config_key: String.t() | nil,
          stage: stage(),
          severity: :error | :warning,
          fault: fault(),
          code: atom(),
          message: String.t()
        }

  @type compilation_record :: %{
          document_id: Document.id(),
          revision: non_neg_integer(),
          document_hash: binary(),
          palette_hash: binary(),
          compiler_version: String.t(),
          chart_identity: Statifier.Machine.Identity.t()
        }

  @type compiled :: %{
          scxml: binary(),
          provenance: Provenance.t(),
          record: compilation_record(),
          invoke_types: [String.t()],
          warnings: [finding()]
        }

  @typedoc """
  `:known_invoke_types` enables the optional two-registry lint (decision 8);
  a host passes `Map.keys(invoke_handlers)` from its session options.
  """
  @type option :: {:known_invoke_types, MapSet.t(String.t())}

  @doc """
  Total. Errors from the first failing stage only (decision 10); warnings ride
  on the artifact when the compile succeeds.
  """
  @spec compile(Document.t(), Palette.t(), [option()]) ::
          {:ok, compiled()} | {:error, [finding()]}

  @doc "State id derivation (decision 3). Injective; `unstate_id/1` inverts it."
  @spec state_id(Block.id()) :: String.t()
  @spec state_id(Block.id(), role :: String.t()) :: String.t()
  @spec unstate_id(String.t()) :: {:ok, {Block.id(), String.t() | nil}} | :error
end
```

## Worked example: a validator finding on generated SCXML routed back to a block

Take ADR-0001's worked example - the inbound-qualification workflow in a
multi-tenant host embedding the engine - and compile it. The relevant fragment,
re-indented for reading; the serializer emits it in one canonical form, because
st-ADR-0052 hashes these bytes. Every id is `state_id` over a block id from that
document, and the sequence's wiring is entirely `done.state` transitions
(decision 2):

```xml
<scxml datamodel="predicator" initial="s_blk_ROOT" name="bdoc_01JDOC" version="1.0">
  <state id="s_blk_ROOT" initial="s_blk_ENR">

    <state id="s_blk_ENR" initial="s_blk_ENR__running">
      <state id="s_blk_ENR__running">
        <invoke type="myapp:enrich"/>
        <transition event="done.invoke" target="s_blk_ENR__done"/>
      </state>
      <final id="s_blk_ENR__done"/>
    </state>
    <transition event="done.state.s_blk_ENR" target="s_blk_GRP"/>

    <state id="s_blk_GRP" initial="s_blk_BR">
      <state id="s_blk_BR" initial="s_blk_BR__choose">
        <state id="s_blk_BR__choose">
          <transition cond="score &gt; 80" target="s_blk_PAR"/>
          <transition target="s_blk_NO2"/>
        </state>
      </state>
      <transition event="myapp.cancelled" target="s_blk_ROOT__abandoned"/>
    </state>

  </state>
</scxml>
```

The `<invoke>` carries no `id`: statifier mints one as
`<state id>.inv_<counter>` from a `%MachineState{}` counter, and the transition
matches the `done.invoke` prefix descriptor rather than naming it, so the block
type never has to know what the engine minted.

The provenance map, abbreviated to its `by_state_id` half:

| state id | owner |
|---|---|
| `s_blk_ROOT` | `blk_ROOT`, role `nil` |
| `s_blk_ENR` | `blk_ENR`, role `nil` |
| `s_blk_ENR__running` | `blk_ENR`, role `running` |
| `s_blk_ENR__done` | `blk_ENR`, role `done` |
| `s_blk_BR__choose` | `blk_BR`, role `choose` |

and a few of the spans, which are what findings actually route through:

| span (bytes) | owner |
|---|---|
| the `<transition event="done.state.s_blk_ENR">` element | `blk_ENR`, role `nil`, key `nil` |
| the `cond="score &gt; 80"` attribute value | `blk_BR`, role `choose`, key `arms` |
| the `<transition event="myapp.cancelled">` element | `blk_INT`, role `nil`, key `nil` |

Two rows carry the record's weight. The transition wiring the sequence is
attributed to **`blk_ENR`, the child it leaves**, not to the sequence that
emitted it, because "what happens after the enrich step" is the fact an author
would recognise. And the interrupt transition on the group's state is attributed
to **`blk_INT`**, the handler block in the `interrupts` slot, even though it was
emitted while compiling `blk_GRP`. That is precisely why ADR-0001 decision 10
made interrupt rules blocks in a slot rather than config on the group: they emit
an element, so they can own one.

**A structural finding.** Suppose the host's `myapp.on_event` block type has a
bug and targets a state that does not exist - note `s_blk_ROOT__abandoned` above
is targeted but never emitted. `Statifier.compile/2` returns
`%Statifier.Validator.Error{reason: {:unresolved_target, "s_blk_ROOT__abandoned"}, location: %Location{start_offset: 612, ...}}`.
The compiler routes offset 612 to the innermost owning span:

```elixir
{:error, [
  %{
    block_id: "blk_INT",
    path: [{"blk_ROOT", "body", 1}, {"blk_GRP", "interrupts", 0}],
    config_key: nil,
    stage: :chart,
    severity: :error,
    fault: :package,
    code: :unresolved_target,
    message: ~s(transition target "s_blk_ROOT__abandoned" does not exist)
  }
]}
```

`fault: :package` is the actionable part. The editor renders this on the
interrupt rule inside the resumable group, and tells the author they cannot fix
it - the bug is in the block type, and no edit to the document will help.

**A content finding.** Now the author's own typo: the branch's arm condition is
`score > > 80`. That reaches upstream as
`%Statifier.Compiler.Error{reason: {:expression_compile_error, owner_ref, "score > > 80", %Predicator.Errors.ParseError{}}}`,
whose location resolves into the `cond` attribute's span. That span's owner
carries `config_key: "arms"`, so:

```elixir
%{
  block_id: "blk_BR",
  path: [{"blk_ROOT", "body", 1}, {"blk_GRP", "body", 0}],
  config_key: "arms",
  stage: :chart,
  severity: :error,
  fault: :author,
  code: :expression_compile_error,
  message: "unexpected `>`"
}
```

Same stage, same pipeline, opposite fault, and a config key the editor can focus.
Composing the predicator span through `Location.resolve_span/3` and back through
the owning span puts the caret on the second `>` inside the field the author
typed into.

**The two-registry lint.** The compile publishes what it emitted:

```elixir
{:ok, compiled} = Compiler.compile(document, palette)
compiled.invoke_types
#=> ["myapp:crm_push", "myapp:enrich", "myapp:notify"]
```

At deploy time the host - which by then knows its st-ADR-0051 registration -
compares. Or it asks the compiler to, by handing over the set it believes in:

```elixir
{:ok, compiled} =
  Compiler.compile(document, palette,
    known_invoke_types: MapSet.new(["myapp:enrich", "myapp:notify"])
  )

compiled.warnings
#=> [%{block_id: "blk_CRM", stage: :chart, severity: :warning, fault: :author,
#      code: :no_registered_invoke_handler,
#      message: ~s(no handler registered for invoke type "myapp:crm_push")}]
```

The compile **succeeds**. `blk_CRM` would raise `error.execution` at runtime
(st-ADR-0051 decision 1), and saying so at authoring time is worth a warning -
but the set handed in is one deployment's belief, and decision 8 is the argument
for why that is not enough to refuse a publish.

**The identity relation, end to end:**

```elixir
{:ok, compiled} = Compiler.compile(document, palette)

compiled.record.document_hash
#=> <<...>>                       # sha256 over canonical JSON (ADR-0001 d8)

compiled.record.chart_identity
#=> %Statifier.Machine.Identity{
#     content_hash: "sha256:9f2c...",   # over compiled.scxml, computed upstream
#     name: "bdoc_01JDOC",              # the document id (decision 7)
#     version: nil                      # deliberately nil, so resume survives a save
#   }

# A metadata-only edit moves one hash and not the other.
{:ok, renamed} = Compiler.compile(Document.rename(document, "Q3 inbound"), palette)
renamed.record.document_hash == compiled.record.document_hash   #=> false
renamed.scxml == compiled.scxml                                 #=> true
Statifier.Machine.Identity.matches?(
  renamed.record.chart_identity, compiled.record.chart_identity) #=> true
```

That last line is the whole argument for decision 7 in one expression: an author
renaming a workflow must not invalidate the positions of every session running
it.

And the determinism property, the acceptance test for decisions 3 and 6:

```elixir
{:ok, a} = Compiler.compile(document, palette)
{:ok, b} = Compiler.compile(document, palette)
a.scxml == b.scxml and a.provenance == b.provenance   #=> true

# An unrelated insertion far from blk_CRM leaves its state id alone.
{:ok, c} = Compiler.compile(Document.insert(document, "blk_ROOT", "body", 0, new), palette)
Map.has_key?(c.provenance.by_state_id, Compiler.state_id("blk_CRM"))   #=> true
```

What this example is chosen to demonstrate:

- **The acceptance property of this record.** A finding raised against generated
  SCXML, by a pipeline with no knowledge of blocks, arrives at the author as an
  annotation on one block with a path to it.
- **The fault split (decision 9).** Two findings from the same stage, one
  unfixable by the author and one that is their typo, distinguished by whether the
  owning span carries a config key.
- **`done.state` sequencing (decision 2).** The root sequence wires its children
  with one transition and reads none of their internals.
- **Attribution is a judgment, not a mechanism (decision 5).** The sequence's
  transition belongs to the child it leaves; the group's interrupt transition
  belongs to the handler block, not the group.
- **Identity is a relation, not an equation (decision 7).** A rename moves the
  document hash, leaves the SCXML byte-identical, and leaves every running session
  resumable.
