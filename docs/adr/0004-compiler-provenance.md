# ADR-0004: One block, one state - a deterministic compile carrying a provenance map

Status: accepted (2026-08-26); illustrations and option list amended (2026-08-27, operator rulings); decision 2 amended - outcome-tagged finals (accepted 2026-08-29, operator ruling); child-use compile and core.subchart routing amendment (2026-08-29, accepted under the operator campaign-015 direction-agent gate grant, PR 93); delayed-send cancel emission amendment (2026-08-29, accepted under the operator campaign-015 direction-agent gate grant, PR 95); core.foreach sequential loop amendment F1-F6 (2026-08-29, accepted under the operator campaign-015 direction-agent gate grant, PR 94); outcome_event/2 tagged-return ratification under 2e (2026-08-29, accepted under the operator campaign-015 direction-agent gate grant, PR 111)

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
within the expression string, and statifier ships `Location.resolve_span/4` to
compose such a span into an absolute document span. [Correction 2026-08-29,
sb-4kh: was `Location.resolve_span/3`. The resolved dependency, statifier
2.2.0, exports `Statifier.Parser.Location.resolve_span/4`
(`value_location, span, value, source`) and no `/3` - verified with
`function_exported?` against `deps/`. Stale cross-reference only; the
composition itself is sb-aal's work.] Running that composition
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
  host wiring `myapp.authorize` still does two things. What changed is that
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

  `:entry_type` (amended 2026-08-27) is ADR-0003 decision 4's caller-supplied
  context - the type flowing into the document's root. That record made the
  context caller-supplied without this record providing an arrival channel;
  this option is the arrival, not a second decision about what assignability
  means. Absent, assignability reads `:unknown` (permissive, ADR-0003 d5).
  """
  @type option ::
          {:known_invoke_types, MapSet.t(String.t())}
          | {:entry_type, Assignability.type_expr() | :unknown}

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

Take ADR-0001's worked example - the card-authorization workflow in a
multi-tenant host embedding the engine - and compile it. The relevant fragment,
re-indented for reading; the serializer emits it in one canonical form, because
st-ADR-0052 hashes these bytes. Every id is `state_id` over a block id from that
document, and the sequence's wiring is entirely `done.state` transitions
(decision 2):

```xml
<scxml datamodel="predicator" initial="s_blk_ROOT" name="bdoc_01JDOC" version="1.0">
  <state id="s_blk_ROOT" initial="s_blk_AUTH">

    <state id="s_blk_AUTH" initial="s_blk_AUTH__running">
      <state id="s_blk_AUTH__running">
        <invoke type="myapp:authorize"/>
        <transition event="done.invoke" target="s_blk_AUTH__done"/>
      </state>
      <final id="s_blk_AUTH__done"/>
    </state>
    <transition event="done.state.s_blk_AUTH" target="s_blk_GRP"/>

    <state id="s_blk_GRP" initial="s_blk_BR">
      <state id="s_blk_BR" initial="s_blk_BR__pick">
        <state id="s_blk_BR__pick">
          <transition cond="budget_remaining &gt; amount" target="s_blk_PAR"/>
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
| `s_blk_AUTH` | `blk_AUTH`, role `nil` |
| `s_blk_AUTH__running` | `blk_AUTH`, role `running` |
| `s_blk_AUTH__done` | `blk_AUTH`, role `done` |
| `s_blk_BR__pick` | `blk_BR`, role `pick` (amended 2026-08-27: this illustration said `choose`; the shipped role is `pick`) |

and a few of the spans, which are what findings actually route through:

| span (bytes) | owner |
|---|---|
| the `<transition event="done.state.s_blk_AUTH">` element | `blk_AUTH`, role `nil`, key `nil` |
| the `cond="budget_remaining &gt; amount"` attribute value | `blk_BR`, role `pick`, key `arm_approved` (amended 2026-08-27: the key is the arm's own slot name, what `config_schema/1` keys the field by, not the `arms` list) |
| the `<transition event="myapp.cancelled">` element | `blk_INT`, role `nil`, key `nil` |

Two rows carry the record's weight. The transition wiring the sequence is
attributed to **`blk_AUTH`, the child it leaves**, not to the sequence that
emitted it, because "what happens after the authorize step" is the fact an author
would recognise. And the interrupt transition on the group's state is attributed
to **`blk_INT`**, the handler block in the `interrupts` slot, even though it was
emitted while compiling `blk_GRP`. That is precisely why ADR-0001 decision 10
made interrupt rules blocks in a slot rather than config on the group: they emit
an element, so they can own one.

**A structural finding.** Suppose the host's `myapp.on_event` block type has a
bug and targets a state that does not exist - note `s_blk_ROOT__abandoned` above
is targeted but never emitted. `Statifier.compile/2` returns
`%Statifier.Validator.Error{reason: {:unresolved_target, "s_blk_ROOT__abandoned"}, location: %Location{start_offset: 637, ...}}`.
The compiler routes offset 637 to the innermost owning span:

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
`budget_remaining > > amount`. That reaches upstream as
`%Statifier.Compiler.Error{reason: {:expression_compile_error, owner_ref, "budget_remaining > > amount", %Predicator.Errors.ParseError{}}}`,
whose location resolves into the `cond` attribute's span. That span's owner
carries `config_key: "arm_approved"` - the arm's own slot name, the key an
editor anchors the finding to (amended 2026-08-27) - so:

```elixir
%{
  block_id: "blk_BR",
  path: [{"blk_ROOT", "body", 1}, {"blk_GRP", "body", 0}],
  config_key: "arm_approved",
  stage: :chart,
  severity: :error,
  fault: :author,
  code: :expression_compile_error,
  message: "unexpected `>`"
}
```

Same stage, same pipeline, opposite fault, and a config key the editor can focus.
Composing the predicator span through `Location.resolve_span/4` and back through
the owning span puts the caret on the second `>` inside the field the author
typed into.

**The two-registry lint.** The compile publishes what it emitted:

```elixir
{:ok, compiled} = Compiler.compile(document, palette)
compiled.invoke_types
#=> ["myapp:authorize", "myapp:capture", "myapp:notify"]
```

At deploy time the host - which by then knows its st-ADR-0051 registration -
compares. Or it asks the compiler to, by handing over the set it believes in:

```elixir
{:ok, compiled} =
  Compiler.compile(document, palette,
    known_invoke_types: MapSet.new(["myapp:authorize", "myapp:notify"])
  )

compiled.warnings
#=> [%{block_id: "blk_CAP", stage: :chart, severity: :warning, fault: :author,
#      code: :no_registered_invoke_handler,
#      message: ~s(no handler registered for invoke type "myapp:capture")}]
```

The compile **succeeds**. `blk_CAP` would raise `error.execution` at runtime
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
{:ok, renamed} = Compiler.compile(Document.rename(document, "Q3 authorization"), palette)
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

# An unrelated insertion far from blk_CAP leaves its state id alone.
{:ok, c} = Compiler.compile(Document.insert(document, "blk_ROOT", "body", 0, new), palette)
Map.has_key?(c.provenance.by_state_id, Compiler.state_id("blk_CAP"))   #=> true
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

## Amendment (2026-08-28): decision 2, outcome-tagged finals

**Status: accepted (2026-08-29, operator ruling).** Drafted 2026-08-28 as a
proposed amendment; the operator accepted it in full on 2026-08-29, including
the completion-event shape, the reserved `o_` role prefix, the
no-grandfathering migration stance, and the outcome/state wiring exclusion. It
amends decision 2's single-final emission and nothing else; every other
decision in the record stands as written, and no accepted text above has been
edited.

### What forces the amendment

The operator's 2026-08-28 ruling (umbrella `docs/decisions.md` D13) settled the
authoring model above this record: **outcome paths are slots, never ports; a
block has one inlet and one outlet; and each outcome compiles to a distinct
completion event.** Ports - several typed outputs with author-drawn edges - were
rejected because they break the tree invariant the editor rests on (connectors
are rendered, never authored), so a block with more than one way to finish
declares a *slot* per alternative path and the compiler is left owing an
emission for it.

Decision 2 as accepted does not supply one. It says a block signals completion
by its state reaching done, and `done.state.<state id>` names the state that
finished and nothing about *how* it finished. A `core.invoke` with an `on_error`
slot has two ways to finish, and under the accepted text both produce the same
event, so a parent cannot tell them apart and the question of what runs after a
failure path completes has no answer at all.

That gap is not hypothetical, and the spike recorded it rather than papering
over it. The fixture run `run_cp_invoke_error` in `spike/fixtures/runs.json`
walks the card-authorization document through a failed `myapp:authorize` call:
the `on_error` subtree parks the transaction and tells ops, and the run then
carries on to the next step in the enclosing sequence. The step that does so
carries this note in the fixture, verbatim:

> What happens once the on_error subtree finishes - whether the enclosing group
> carries on to the next step as it does here, and how that reconciles with
> ADR-0004's single-final emission - is undecided. This run assumes it does
> carry on, and says so rather than letting the assumption ride as a rendered
> fact.

This amendment is the answer that note is waiting for.

### 2a. A block type may declare outcomes; the default is exactly one

A block type declares an ordered list of outcome names. A type that declares
none has one outcome, named `done`, which is the case the accepted record
already describes: one final, one completion event, nothing to choose between.
Every existing `core.*` type is in that case and none of them changes meaning.

Outcome names match `~r/\A[a-z][a-z0-9_]*\z/`, the same shape as a role
(decision 3), and are declared in a fixed order so decision 6's byte
determinism survives. **Where the declaration surface lives is not this
record's call**: the `outcomes/1` callback, and how an outcome relates to the
slot that feeds it, belong to ADR-0002's own amendment (sb-0b0). This record
owns only what the compiler emits once the declaration exists.

### 2b. One `<final>` per declared outcome, minted through the context

Each declared outcome the block actually reaches compiles to its own `<final>`
child of the block's own state, with the id

```
outcome_id(block_id, outcome) = state_id(block_id, "o_" <> outcome)
                              = "s_" <> block_id <> "__o_" <> outcome
```

minted through `Context.outcome_id/2` rather than by string concatenation
inside the block type, for decision 3's reason. Outcome finals therefore live
in the role namespace decision 3 already established: they are auxiliary states
inside the block's own state, they inherit its uniqueness and invertibility
properties unchanged, and `unstate_id/1` still inverts them.

To keep the two kinds of auxiliary state distinguishable, **the compiler
reserves the role prefix `o_`**: `Context.role_id/2` refuses a role beginning
with `o_` with a `:reserved_role` finding, and `Context.outcome_id/2` is the
only way to mint one. Without the reservation an outcome final and a
hand-minted role could produce the same id and provenance could not say which
it was.

"One block, one state" is untouched. A block with four outcomes still compiles
to one state; what grew is the number of `<final>` children *inside* it, which
decision 2's own escape - auxiliary states inside the block's own state - always
permitted.

### 2c. The outcome rides on an event, not on the final's identity

`done.state.<state id>` is generated whichever final is entered, so the final's
identity is not observable to a parent. The tag has to travel as its own event:

```xml
<final id="s_blk_AUTH__o_error">
  <onentry><raise event="done.outcome.s_blk_AUTH.error"/></onentry>
</final>
```

The completion event of an outcome is `done.outcome.<state id>.<outcome>`, and
it is computable from the child's block id and the outcome name alone - which is
the composability property decision 2 exists to protect, extended rather than
weakened. A parent still reads none of its child's emission.

Three consequences worth stating, because each is a place to get it wrong:

- **A parent that does not care which outcome wires the prefix.** SCXML event
  descriptors match at token boundaries, so a transition on
  `done.outcome.s_blk_AUTH` matches every outcome of that block and no other
  block's. `core.sequence` uses exactly that and never learns an outcome name;
  a parent that *does* discriminate names the full event. This is the same
  prefix-descriptor idiom the accepted record already relies on for
  `done.invoke`.
- **A parent must not wire both `done.outcome.*` and `done.state.*` for one
  child.** Both are internal events and Appendix D queues the final's `onentry`
  content before the `done.state` it then generates, so in practice the outcome
  transition is offered first - but resting a semantic distinction on
  internal-queue ordering is a contract nobody should have to read the
  interpreter to understand. `done.state.<state id>` remains what it was: the
  "finished, do not care how" signal for a single-outcome child.
- **An outcome a block never reaches costs a parent nothing.** Because the
  wiring is an event and not a target, a parent may transition on an outcome
  whose final was never emitted; the transition simply never fires, and no
  `{:unresolved_target, _}` finding results. That is what lets `core.invoke`
  omit the error path entirely when its `on_error` slot is empty, exactly as the
  spike's `core.invoke` sketch describes, without the parent's wiring changing.

Two alternatives were considered and rejected. Carrying the outcome in
`<donedata>` and having the parent discriminate with a `cond` on `_event.data`
makes every structural parent's wiring depend on the datamodel language and
turns a routing decision into an expression evaluation. Emitting one final and
having the parent read the block's internal configuration reintroduces the
dependency decision 2 was written to forbid.

### 2d. The parent decides continuation; the block does not

This is the part `run_cp_invoke_error` was waiting on, and it follows from 2c
rather than being a separate choice.

The `on_error` subtree is compiled, like any slot child, as a state inside the
invoke block's own state. Its completion - an ordinary `done.state` on that
child - targets the block's **error-outcome final**. Entering that final raises
`done.outcome.<state id>.error`, and there the block's emission ends. The block
does not resume anything, does not re-enter its own body, and has no opinion
about what comes next.

What comes next is the enclosing parent's wiring and only that. In the fixture
the invoke is the last body child of a group, and the group transitions on the
prefix descriptor, so it finishes whichever way the authorization finished and
the run carries on to `blk_cp_outcome` by the ordinary completion chain above
it - which is precisely the behaviour the run assumed and flagged as an
assumption. A different parent
could route the error outcome somewhere else, or nowhere, and both are ordinary
wiring rather than special cases. Recovery flows shared across many outcome
paths are D13's designated escape hatch (a subchart/fragment-reference block),
not a reason to give a block continuation authority.

### 2e. What the context carries

Decision 4's child summary grows one field, and nothing else in the context
changes:

```elixir
@type outcome :: %{
        name: String.t(),
        state_id: String.t(),
        done_event: String.t()
      }

@type child :: %{
        block_id: Block.id(),
        state_id: String.t(),
        done_event: String.t(),
        outcomes: [outcome()]
      }
```

`done_event` keeps its accepted meaning - `done.state.<state id>` - so every
structural parent written against the accepted record still compiles and still
behaves identically for single-outcome children. `outcomes` is in declaration
order, always non-empty, and holds one entry for a type that declared none. A
child's emitted SCXML is still not in the context.

```elixir
@doc "Mints the final's id for one declared outcome. Injective; `unstate_id/1` inverts it."
@spec outcome_id(t(), outcome :: String.t()) :: String.t()

@doc "The completion event a parent wires on: `done.outcome.<state id>.<outcome>`."
@spec outcome_event(t(), outcome :: String.t()) :: String.t()
```

**Amended 2026-08-29 (operator ruling): `outcome_id/2` returns a tagged tuple.**
The sketch above writes `outcome_id/2` as returning a bare `String.t()`, which
cannot hold together with the rest of the record: 2f requires an
`:invalid_outcome` Emit finding for an outcome name failing the role shape, and
decision 1 forbids `emit/2` raising, so the refusal has to be reachable through
a return value. The shipped signature (landed by PR 73 / sb-wmw) is the one
this amendment ratifies:

```elixir
  @spec outcome_id(t(), String.t()) ::
          {:ok, StateId.t()} | {:error, {:invalid_outcome, Block.id(), String.t()}}
```

The `{:ok, _}` arm carries exactly the id the sketch names, so 2b's minting rule
and decision 3's injectivity are unchanged. Decision 1 keeps its no-raise rule
and 2f keeps the finding at the emit site; this is a correction to the sketch's
typespec, not a change of behaviour. `outcome_event/2` is outside this
amendment.

**Amended 2026-08-29 (operator ruling): `outcome_event/2` returns a tagged
tuple.** The sketch above writes `outcome_event/2` as a bare `String.t()` too,
and it cannot hold for the same reason: 2f requires an `:invalid_outcome` Emit
finding for an outcome name failing the role shape, and decision 1 forbids
`emit/2` raising, so that refusal also has to be reachable through a return
value. The shipped signature (landed by PR 73 / sb-wmw, in
`lib/statifier_blocks/compiler/context.ex`) is the one this amendment ratifies:

```elixir
  @spec outcome_event(t(), String.t()) ::
          {:ok, String.t()} | {:error, {:invalid_outcome, Block.id(), String.t()}}
```

The `{:ok, _}` arm carries exactly the event the sketch names -
`done.outcome.<state id>.<outcome>` - so 2c's wiring rule and 2d's
continuation rule are unchanged. Decision 1 keeps its no-raise rule and 2f
keeps the finding at the emit site; this is a correction to the sketch's
typespec, not a change of behaviour, and it settles the question the paragraph
above left open.

### 2f. Provenance, determinism, and findings

- **Provenance (decision 5) is unchanged and stays total.** An outcome final is
  owned by its block with `role: "o_" <> outcome` and `config_key: nil`; so is
  the `<raise>` inside it. Nothing new is unowned.
- **Determinism (decision 6) is unchanged in kind and moved in fact.** Outcomes
  serialize in declaration order, never from map iteration. But the default
  outcome's final id moves from the ad-hoc role a type used before - the
  accepted worked example's `s_blk_AUTH__done` - to `s_blk_AUTH__o_done`, so
  adopting this amendment moves bytes for every document and is a
  compiler-version bump under decision 6's third axis. That is the record's own
  release-discipline obligation coming due, not an exception to it.
- **Findings (decision 10) gain two Emit-stage codes**, both `fault: :package`
  and both named against the block whose type misbehaved: `:invalid_outcome`
  for an outcome name failing the role shape or declared twice, and
  `:reserved_role` for a `role_id/2` call in the `o_` namespace.
- **Decision 9 is untouched.** Chart-semantic validation stays delegated; an
  unreachable outcome final, if upstream ever warns about one, arrives here as
  an ordinary mapped warning.

### Worked example: the failed authorization, compiled

The fixture's failing step, in the shape this amendment proposes. In that
document `blk_cp_authorize` is a `core.invoke` whose `on_error` slot holds the
sequence `blk_cp_authz_error`, and it is the last body child of the group
`blk_cp_authz`. The invoke's own id is minted by the engine, so the failure
transition matches statifier-ex ADR-0068's `error.communication.invoke` by
prefix rather than naming it - the same reason the accepted example's
`done.invoke` transition does:

```xml
<state id="s_blk_cp_authorize" initial="s_blk_cp_authorize__running">

  <state id="s_blk_cp_authorize__running">
    <invoke type="myapp:authorize"/>
    <transition event="done.invoke" target="s_blk_cp_authorize__o_done"/>
    <transition event="error.communication.invoke" target="s_blk_cp_authz_error"/>
  </state>

  <!-- the on_error slot's child, compiled as any slot child is -->
  <state id="s_blk_cp_authz_error" initial="s_blk_cp_authz_park">
    <!-- park, then notify ops -->
  </state>
  <transition event="done.state.s_blk_cp_authz_error"
              target="s_blk_cp_authorize__o_error"/>

  <final id="s_blk_cp_authorize__o_done">
    <onentry><raise event="done.outcome.s_blk_cp_authorize.done"/></onentry>
  </final>
  <final id="s_blk_cp_authorize__o_error">
    <onentry><raise event="done.outcome.s_blk_cp_authorize.error"/></onentry>
  </final>

</state>

<!-- emitted by the enclosing group, on the child it leaves -->
<transition event="done.outcome.s_blk_cp_authorize" target="s_blk_cp_authz__o_done"/>
```

The last line is the whole of decision 2d in one element. The invoke's emission
ends at its error final; the enclosing group is what carries on, and it does so
whichever way the authorization finished because it wires the prefix descriptor
and never learns an outcome name. From there nothing is new: the group is a
single-outcome block, so its own completion travels as `done.state` up through
the branch arm to the root sequence, which moves the run to `blk_cp_outcome` -
the step the fixture takes next, now by an emission rather than by assumption.

The provenance rows are what decision 5 already prescribes:
`s_blk_cp_authorize__o_error` and the `<raise>` inside it are owned by
`blk_cp_authorize` with role `o_error`, and the group's transition is attributed
to the child it leaves, as the accepted example's sequence wiring is.

### Deferred question: is there an author-facing outcome leaf?

**Not decided here, and deliberately so.** Under this amendment every outcome
final and every transition into one is *emitter-generated*: a block type decides
which of its declared outcomes a given internal path reaches, and an author
never names an outcome except by putting content in the slot that feeds it.

The open alternative is a **leaf block type meaning "finish with outcome X"** -
an author drops it at the end of a subtree and chooses the outcome the enclosing
block completes with, the way a `return` ends a function body. It is the natural
authoring surface for a type with three or more outcomes whose paths are not in
one-to-one correspondence with its slots.

What the question does *not* touch, which is why the amendment above can stand
without it: both answers produce the same emission. The outcome final exists,
its id is `outcome_id/2`, entering it raises `done.outcome.<state id>.<outcome>`,
and the parent decides continuation. The question is only **who writes the edge
into the final** - the block type, or an author placing a leaf.

What it would have to settle if taken up:

- whether the leaf is a `core.*` type or a per-host concern, and whether it can
  name an outcome the enclosing block type did not declare (the compiler can
  check this, since it mints the ids);
- what it means in a subtree with no enclosing multi-outcome block, and what
  finding that produces;
- how it interacts with assignability (ADR-0003): a leaf that ends a path
  declares no `produces`, as `core.raise` already does, but an outcome-selecting
  leaf makes the enclosing block's `produces` a join over the paths that reach
  each outcome - the join ADR-0003 decision 4 declined to build a lattice for,
  and the reason the spike's `core.invoke` declares `produces: "unknown"`;
- whether it is authored at all, or whether it is the presentation of something
  the block type declares, which is ADR-0005's kind of question rather than this
  record's.

Until it is ruled, block types wire their own outcome finals and no such leaf
exists in the vocabulary.

### What this amendment does not change

- Decision 2's "one block, one state" and the ban on sibling states.
- Decision 3's derivation, its three properties, or `unstate_id/1`.
- Decision 5's provenance keys and its totality.
- Decision 6's determinism guarantee, whose compiler-version axis this
  amendment exercises rather than amends.
- Decisions 7 through 10 in any respect.
- ADR-0002's declaration surface, which is sb-0b0's to amend, and ADR-0001's
  document schema, which nothing here touches.

## Amendment (2026-08-29): a document compiled for use as a child, and `core.subchart` routing

**Status: accepted (2026-08-29, unqualified direction-agent verdict under the operator campaign-015 grant, PR 93).** This section records the
operator's 2026-08-29 ruling on the mirror pair `sb-81e` / `st-aj2k` and
nothing else. It is additive: it amends no accepted text above, and every
decision in the record, the 2026-08-28 amendment included, stands as written.
The upstream pin for the ruling is `st-iz97`.

### What the ruling settles

The 2026-08-28 amendment gave a block's outcome an event of its own -
`done.outcome.<state id>.<outcome>` - and made a parent route on it. That
works inside one document. It does not work across an `<invoke>`, because
raised events are internal to the session that raises them: a child session's
internal events do not appear in its parent's queue, and the only thing a
parent observes of a finished child is the completion event and the data the
child chose to send with it (SCXML 3.7 and 5.5, and statifier-ex ADR-0051
decision 5).

That gap is the one `core.subchart` recorded and declined to invent an answer
for. Its sketch in `spike/js/proposed-core.js` names the mapping from "which
final state" to "which slot" as open, verbatim: it "is not something ADR-0051's
invoke contract or ADR-0004's single-final emission decides today. Until it is
decided upstream, a subchart has the two outcomes an invoke has, and this file
says so rather than inventing a third." This amendment is that decision,
arriving.

**A child chart's outcome crosses the invoke boundary as
`done.invoke.<invoke_id>` data** - that is, as the child's top-level
`<final>`'s `<donedata>`.

### C1. A document compiled for use as a child emits one top-level `<final>` per root-block outcome

Compiling a document *for use as a child* adds one thing to the emission the
record already prescribes: a top-level `<final>` for each outcome the document's
root block declares, reached by a transition on that outcome's completion event
and carrying the outcome name as done data.

```
transition on   done.outcome.s_blk_ROOT.<outcome>
target          a top-level <final>
donedata        <param name="outcome" expr="'<outcome>'"/>
```

`s_blk_ROOT` is the root block's own state id, minted by decision 3 as any
other is; `<outcome>` is a root-block outcome name in the sense amendment 2a
fixed. The root block's outcome finals and the raises inside them are unchanged
- the document keeps emitting `done.outcome.s_blk_ROOT.<outcome>` exactly as
amendment 2c prescribes, and the top-level finals added here are what turn that
internal signal into something a parent session can see.

**This is not the alternative amendment 2c rejected.** 2c rejected `<donedata>`
plus a `cond` on `_event.data` for *structural parents inside one document*,
where an event is available and a routing decision would have been turned into
an expression evaluation for no gain. Across an invoke boundary there is no
event to route on: `<donedata>` is the channel the spec provides, and the
choice is between using it and having no answer at all.

### C2. `core.subchart`'s state routes `done.invoke` on `_event.data.outcome`

The block's own state carries, per outcome the referenced chart declares, a
transition on `done.invoke` conditioned on the outcome name:

```
<transition event="done.invoke" cond="_event.data.outcome == '<outcome>'" .../>
```

**The unconditioned `done.invoke` transition comes last**, as the default path:
document order decides which of several matching transitions is taken, so an
unconditioned transition placed anywhere but last would shadow every
conditioned one after it. Last, it is what a child that finished with an
outcome the parent does not route - or with none the parent recognizes - falls
through to.

`error.communication.invoke` routing to the `on_error` slot is **unchanged**.
The failure path is the one `core.invoke` already has and the one the spike's
sketch already declares; nothing in this amendment touches it.

### C3. Parallel subcharts write `<invoke id>`

Where subcharts run in parallel, the compiler writes an explicit `id` on the
`<invoke>` rather than letting the engine mint one, so that `_event.invokeid`
is static and a parent can tell its concurrent children apart by a value it
knows at compile time.

### Illustration

A signup wizard whose eligibility step runs another chart, that chart's root
block declaring the outcomes `done` and `abandoned`. Nothing here is a new
decision; it is C1 through C3 written out.

The child document's emission, at top level:

```xml
<!-- These transitions sit on the root block's own state, s_blk_ROOT, and
     target the top-level finals below. -->
<transition event="done.outcome.s_blk_ROOT.done" target="..."/>
<transition event="done.outcome.s_blk_ROOT.abandoned" target="..."/>

<!-- Each top-level final's id is minted under decision 3 and is the
     emitter's to choose; this record does not settle it, and the
     transition targets above are those same ids. -->
<final id="...">
  <donedata><param name="outcome" expr="'done'"/></donedata>
</final>
<final id="...">
  <donedata><param name="outcome" expr="'abandoned'"/></donedata>
</final>
```

The parent's `core.subchart` block, compiled:

```xml
<state id="s_blk_ELIGIBILITY" initial="s_blk_ELIGIBILITY__running">

  <state id="s_blk_ELIGIBILITY__running">
    <!-- The invoke type is the block type's call under the spike sketch -
         the host-registered child-chart invoke type - not this record's. -->
    <invoke type="..." src="..."/>

    <transition event="done.invoke" cond="_event.data.outcome == 'done'"
                target="s_blk_ELIGIBILITY__o_done"/>
    <transition event="done.invoke" cond="_event.data.outcome == 'abandoned'"
                target="s_blk_ELIGIBILITY__o_abandoned"/>
    <!-- unconditioned, and last: the default path. Which outcome it lands
         on is the block type's call, not this record's. -->
    <transition event="done.invoke" target="..."/>

    <transition event="error.communication.invoke" target="s_blk_ELIGIBILITY_error"/>
  </state>

  ...

</state>
```

### What this amendment does not change

- Amendment 2c's completion-event shape, or its rejection of `<donedata>`
  routing between structural parents inside one document.
- `core.invoke`'s emission, or `error.communication.invoke` routing to
  `on_error` in either type.
- Any accepted decision in this record, or the header above it.

## Amendment (2026-08-29): a delayed send's cancel, emitted in the arming state's `<onexit>`

**Status: accepted (2026-08-29, unqualified direction-agent verdict under the operator campaign-015 grant, PR 95).** This section is additive: nothing above it
is edited, and every decision in the record stands as written. It records the
emission half of the operator's 2026-08-29 delayed-send lifetime ruling
(`sb-b4f`, mirrored to statifier-ex as `st-q3ud`); the declaration half - that
`core.send`'s descriptor carries a send id, and that no `core.cancel` block
exists - is ADR-0002's, and its amendment of the same date holds it.

### What forces the amendment

`core.send` emits a delayed send that this package could not cancel, and the
type recorded the gap rather than guessing at it: a cancel that names the send
it cancels is a cross-subtree reference between blocks, which the umbrella's
D13 refuses - outcome paths are slots, never ports, and connectors are
rendered, never authored - as ADR-0001's tree invariant and ADR-0005's
amendment 10a state at record level, and the alternative that keeps the tree
invariant is scope-shaped - a delayed send is cancelled when the region that
armed it is left. The ruling picks the scope-shaped alternative, which makes
the cancel the *compiler's* to emit rather than an author's to draw.

### A. Identity and lifetime are upstream's

A pending delayed send is identified by `{session scope, send_id}` only
(statifier-ex ADR-0054 decision 3), and it lives until it fires, is cancelled,
or its run is found not live at fire time (decision 4 of the same record).
Resume keeps the scope (statifier-ex ADR-0060 decision 3); restart mints a new
one and the host discards; a change of chart revision does not affect the key.

Those are upstream's rules and this record restates them only to name what the
emitted cancel has to match. `statifier_oban` already keys on that pair.

### B. The cancel is emitted in the arming state's `<onexit>`

The compiler emits

```xml
<cancel sendid="..."/>
```

in the `<onexit>` of the state that armed the send - the enclosing group for a
rail - naming the send id ADR-0002's amendment of this date gives the
descriptor.

Nothing about this is authored. There is no cancel block, no `sendid` in any
config, and no edge in the document that carries it: the cancel is a
consequence of where the `core.send` sits in the tree, which is the property
that makes it scope-shaped and keeps D13 intact.

### C. What this amendment does not change

- Decision 2's "one block, one state". A cancel is executable content inside a
  state that already exists, not a state.
- Decision 3's id derivation, decision 5's provenance keys and their totality,
  or decision 6's determinism guarantee.
- The `core.send` emission in any other respect - the event, the optional
  delay, and the absence of a `target` are all as shipped.

### Deferred, named rather than guessed

- **How the send id is minted** - through the context, the way decision 3
  requires of every other derived id - is left to the bead that implements
  this section (`sb-b4f`), because the ruling settles the shape of the id and
  not the API that produces it.

## Amendment (2026-08-29): the sequential `core.foreach` compile

**Status: accepted (2026-08-29, unqualified direction-agent verdict under the operator campaign-015 grant, PR 94).** Drafted 2026-08-29 from the operator ruling on the loop
shape (sb-i61 / st-z4f3, "as recommended"). It records how a sequential
`core.foreach` block compiles under this record's existing decisions and names
one new compile finding; it amends no accepted decision above, and no accepted
text above has been edited. Upstream pin: st-wlrx.

### What forces the amendment

`core.foreach` is the first block type whose emission is not a fixed subtree:
it runs its body once per item of a list. Decision 2 gives it one state and
bans sibling states, decision 3 fixes how any auxiliary state is named, and
decision 6 makes the emission byte-deterministic - but nothing in the record
says what shape the loop itself takes, and the block type cannot invent one
without deciding, on its own, where the loop counter lives and whether the list
is re-read between passes. The ruling settles that, and this section records it.

### F1. The compile is a plain Appendix D loop

**The sequential `core.foreach` compile is a plain Appendix D loop.** Nothing in
it reaches outside the interpreter's ordinary macrostep semantics: no new
executable content, no engine extension, no re-entrant compile. The loop is
states, transitions, and assignments, and the engine runs it the way it runs
any other chart.

### F2. Cursor and snapshot are compiler-declared `<data>` roots

The cursor and a per-loop snapshot of the list are **compiler-declared `<data>`
roots**, in the generated namespace decision 3 already reserves:

```
s_blk_<id>__i        the cursor
s_blk_<id>__items    the per-loop snapshot
```

The snapshot is **assigned once at the block's `onentry`**, which is what gives
the loop spec 4.6.3 shallow-copy parity: the body iterates the list as it stood
when the loop began, and a later write to the source expression does not change
what the loop is walking. Both names sit under the `s_` prefix, so by decision
3's uniqueness property they cannot collide with an author's `<data>` id.

### F3. `item_as` / `index_as` are declared roots re-assigned by a head state

The author-facing bindings are **declared `<data>` roots** too - early binding
makes them global, so they exist for the whole session rather than only inside
the loop - and they are **re-assigned in a head state's `onentry` on each
pass**, from `snapshot[cursor]`. The head state is an auxiliary state under
decision 3, so it is minted through `Context.role_id/2` like any other.

### F4. The body compiles once, and `done.state` closes the loop

The body **compiles once, as a compound state**. Its `done.state` event fires a
**loop-back transition on the foreach state** that increments the cursor and
re-targets the head. There is no unrolling: the body's states, and therefore its
provenance entries, exist once no matter how long the list is.

### F5. Termination, and the limit it carries

Termination is `snapshot[cursor] === undefined`. Predicator indexes lists and
reads out of bounds as `undefined`, but it has **no list-length function**, so
there is no `i < len(items)` to test instead. The consequence is a **documented
limit**: a list holding a legitimate `undefined`/`null` item stops the loop
early, at that item.

In the resolved predicator the limit is **narrower than that wording**, and the
emitter must know it: `===` is strict, so a `nil` item does *not* trip
`=== undefined` - only an actual `:undefined` does, which for a list read means
only an out-of-bounds index. A list holding `nil` items therefore iterates to
its end. (Do not reach for loose `==` to widen it: `items[i] == undefined`
evaluates to `:undefined` rather than to a boolean.)

### F6. Colliding bound names are refused at compile time

**The compiler must refuse bound names that collide across nesting or with
author `<data>` ids.** A nested foreach that re-uses the outer loop's `item_as`,
or an `index_as` equal to an author-declared `<data>` id, would silently
overwrite the outer binding - early binding makes these roots global, so the
inner loop's writes are visible to the outer body after the inner loop ends.
The compiler refuses the document rather than emitting it.

The refusal is a finding under decision 10: **`:duplicate_binding`**, an
Emit-stage error with `fault: :author`, named against the foreach block whose
binding collides and carrying the offending `config_key` (`item_as` or
`index_as`).

This is a **narrow, ruling-mandated carve-out from decision 9's delegation**,
and it is stated as a carve-out rather than as an amendment of decision 9: the
compiler here does perform an id-uniqueness check, which decision 9 says the
package ships none of, and it pre-empts for these names the
`{:duplicate_id, id}` over `<data>` that decision 9 routes to the Chart stage.
The carve-out covers **foreach bound names only** - an `item_as` or `index_as`
against an enclosing foreach's bindings and against author-declared `<data>`
ids - because those names are the only ones the block vocabulary lets an author
choose that early binding then makes global. Every other chart-semantic check
decision 9 delegates stays delegated: no reachability analysis, no
transition-target check, no expression well-formedness check, and no general
id-uniqueness check over `<data>`. Widening the carve-out past foreach bound
names would be a change to decision 9.

### What this amendment does not change

- Decision 2's "one block, one state" and the ban on sibling states: the head
  and body states are the block's own descendants, not siblings.
- Decision 3's derivation, its three properties, or `unstate_id/1`.
- Decision 5's provenance keys and its totality.
- Decision 6's determinism guarantee.
- Decisions 7, 8, 10 and 11, and the 2026-08-28 outcome-tagged-finals
  amendment, in any respect.
- Decision 9's delegation in every respect except the narrow foreach bound-name
  carve-out F6 records; the decision's text is not edited, and its delegation
  holds everywhere else.
- ADR-0001's document schema and ADR-0002's declaration surface, neither of
  which this section touches.

## Amendment (2026-08-29): `core.parallel` `complete: first` - per-lane transitions, losing lanes exit and cancel

**Status: proposed (2026-08-29).** This section is additive: nothing above it
is edited, and every decision in the record stands as written. It drafts the
operator's 2026-08-29 ruling on how a racing `core.parallel` compiles
(`sb-olu`, mirrored to statifier-ex as `st-rau9`, "as recommended"). Upstream
pin: `st-iefu`.

### What forces the amendment

`core.parallel` ships one completion mode. Its emission wraps a single
`<parallel>` inside a compound state and takes one transition on
`done.state.<run>` - a `<parallel>` is done when every region is, so "done when
every lane is" needs no join logic and no decision of its own. A racing
parallel - done when the *first* lane finishes - has neither property. It needs
a completion event per lane rather than one for the block, and it leaves lanes
running that the block is already finished with, which raises a question no
decision above answers: what happens to a losing lane's `<invoke>`. The block
type cannot pick either half on its own, and the ruling settles both.

### P1. `complete: first` is one transition per lane, on the `<parallel>` element itself

**`complete: first` compiles to one transition per lane on the `<parallel>`
element itself, each taken on that lane's completion event and targeting the
block's done final.**

The transition set is per lane, not per block: nothing joins, and no auxiliary
state counts arrivals. A lane's completion event is the one decision 2 already
mints for it - each lane is a region, and a region reaching its `<final>`
raises `done.state.<region id>` - so the block type computes every event it
needs from decision 3's ids alone, exactly as the shipped mode computes its
single one.

The transitions sit on the `<parallel>` element itself, as ruled. What makes
the first arrival win is the event each transition is taken on:
`done.state.<region id>` is raised the moment one region reaches its
`<final>`, and taking the transition exits the `<parallel>` - every region
with it - instead of waiting for `done.state.<run>`, which the element raises
only when every region is done.

### P2. A losing lane gets Appendix D exit semantics: `onexit`, then one `CancelInvoke` per live invocation

**Losing lanes get Appendix D exit semantics.** Exiting the `<parallel>` exits
every region still in the configuration, and for each of those the engine runs
the region's `<onexit>` and then raises one `CancelInvoke` per live invocation
the region owns, dispatched through the registry handler's `cancel/2` - spec
6.4's "as if it were the final `<onexit>` handler". **That cancel is never
refused**: a handler does not get to decline it, and this compile does not
depend on whether a particular invocation is cancellable.

For an `scxml` child that means the child halts cancelled: it runs its own
`<onexit>` content and raises no `done.invoke`. A completion or failure report
that arrives after the cancel is **discarded at drain** (statifier-ex ADR-0068
decision 4), so a losing lane cannot deliver an outcome to a block that has
already finished.

None of that is this package's to implement. It is the engine's Appendix D
behaviour, and this section records it because it is what makes `complete:
first` a compile rather than a runtime protocol: the compiler emits the
transitions of P1 - and, for a delayed send, the `<cancel>` P3 records - and
no join, counter, or cancellation protocol of its own; the orderly exit of the
losing lanes is a consequence of the transitions.

### P3. Each lane's scope-shaped `<cancel>` is emitted in that lane's `<onexit>`

`CancelInvoke` covers invocations. A delayed send is not one, and the same exit
has to reach it. The composition is the one this record's delayed-send
amendment already fixes: **the compiler emits each lane's scope-shaped
`<cancel sendid="..."/>` in that lane's `<onexit>`**, under "Amendment
(2026-08-29): a delayed send's cancel, emitted in the arming state's
`<onexit>`", section **B. The cancel is emitted in the arming state's
`<onexit>`**.

Nothing new is decided here. Section B makes a delayed send's cancel a
consequence of where the `core.send` sits in the tree; a lane is a region and
therefore a scope, so a `core.send` in a losing lane is cancelled when that
lane is exited, by the `<onexit>` section B has the compiler emit for it. This
section records only that `complete: first` is the case that makes the scope
shape load-bearing rather than merely tidy.

### Note: the winning lane cancels too, and that is upstream's

Recorded for reviewers, and **not a decision of this record**: `st-iefu` found
that the *winning* lane also draws a `CancelInvoke` on exit, for an invocation
that has already completed. That is pre-existing engine behaviour rather than
anything `complete: first` introduces, and it was ruled upstream as an
`Invoke.Handler` documentation line (`st-9wkc`) rather than as a change of
behaviour. Nothing in P1 through P3 contradicts it, and a reader of a trace
should not assume that a cancel it observes names a live invocation.

### What this amendment does not change

- The completion mode `core.parallel` ships today - one `<parallel>` in a
  compound state, one transition on `done.state.<run>`, done when every region
  is. This section records a second mode and edits nothing about the first.
- Decision 2's "one block, one state" and the ban on sibling states. The lanes
  are regions inside the block's own `<parallel>`, exactly as they are today,
  and the added transitions are structure inside a state that already exists.
- Decision 3's derivation, or the `lane_<name>` and `done_lane_<name>` role
  families the block already mints through the context.
- Decision 5's provenance keys and their totality, or decision 6's determinism
  guarantee: the transition set stays a pure function of the ordered lane
  list.
- The `core.subchart` amendment of this date, C3 included - a parallel subchart
  still writes an explicit `<invoke id>`.
- The delayed-send amendment of this date in any respect beyond citing its
  section B.
