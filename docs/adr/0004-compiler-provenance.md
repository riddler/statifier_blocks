# ADR-0004: One block, one state - a deterministic compile carrying a provenance map

Status: accepted (2026-08-26); illustrations and option list amended (2026-08-27, operator rulings); decision 2 amended - outcome-tagged finals (accepted 2026-08-29, operator ruling); child-use compile and core.subchart routing amendment (2026-08-29, accepted under the operator campaign-015 direction-agent gate grant, PR 93); delayed-send cancel emission amendment (2026-08-29, accepted under the operator campaign-015 direction-agent gate grant, PR 95); core.foreach sequential loop amendment F1-F6 (2026-08-29, accepted under the operator campaign-015 direction-agent gate grant, PR 94); outcome_event/2 tagged-return ratification under 2e (2026-08-29, accepted under the operator campaign-015 direction-agent gate grant, PR 111); core.parallel complete-first amendment P1-P3 (2026-08-29, accepted under the operator campaign-015 direction-agent gate grant, PR 112); root-termination note, the terminate option (2026-08-29, accepted under the operator campaign-015 direction-agent gate grant, PR 123); host-declared-roots note, the declare option (2026-08-29, accepted under the operator campaign-015 direction-agent gate grant, PR 124); send-id minting and the config_value_span finding field amendment (2026-08-29, accepted under the operator campaign-015b direction-agent gate grant, PR 130); core.wait timer note - the timer rides the reserved send role (2026-08-29, accepted under the operator campaign-015b direction-agent gate grant, PR 132); core.subchart src identity and self-reference refusal amendment R1-R4 (2026-08-29, accepted under the operator campaign-015b direction-agent gate grant, PR 133)

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

**Status: accepted (2026-08-29, unqualified direction-agent verdict under the operator campaign-015 grant, PR 112).** This section is additive: nothing above it
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

## Note (2026-08-29): a root document that finishes, and the `terminate` option

Additive note, recorded for `sb-73f`. It defines one thing this record had
never said and changes nothing it does say. The record's Status is untouched.

### What forces the note

A production host published a compiled root document into the engine and
found that the run never completes. The cause is structural rather than a
bug: amendment 2b puts the root block's outcome finals *inside* the root
block's own state, so completing the root block raises
`done.outcome.<root state id>.<outcome>` internally and the session never
enters a top-level `<final>`. A session that never reaches a top-level
`<final>` never reports `:done`, so a durable runtime built on that signal -
`statifier_persistence` marks a run completed on it - leaves every published
chart active forever.

The C1 amendment of this date emits exactly the missing shape, but for a
*child* chart, and it says so in its own terms: `<donedata>` "is how a
child's outcome crosses the invoke boundary". Nothing in this record said
what it means for a **root** document to finish. This note says it.

### The sentence

**A root block document reaches a top-level `<final>` - one per outcome its
root block declares, reached from `done.outcome.<root state id>.<outcome>` -
when its root block completes, and it does so only when the compile asks
for it.**

Termination is **opt-in**, through a compile option (`terminate: true`,
default `false`), for the same reason C1's child shape is: a document
compiled without it is byte-identical to what it was before the option
existed, and this record's determinism guarantee (decision 6) is a promise
about bytes, not about intent. The finals carry **no `<donedata>`**: nothing
is listening across a boundary, and an invoke-flavoured payload on a root
document would be a shape a reader has to explain away.

Opting in is a **one-time chart-identity choice**. The option changes the
generated bytes, so it changes the chart's content hash, and under
statifier-ex ADR-0052 that is a different chart revision: a persisted
position is meaningful only against the revision that produced it. A host
turns `terminate` on before it publishes a document, not between two runs of
one.

### `child_use` stays the child-chart shape

This note adds a sibling; it does not widen C1. `child_use: true` remains
what a document compiled **for use as a child** passes, and it remains the
only thing that emits `<donedata>`, because the donedata is the invoke
boundary's channel and a root document has no boundary to cross.

The two are **mutually exclusive**: a document is compiled either for use as
a child or as a root that finishes. Passing both is refused at compile time
with an `:emit` finding rather than resolved silently, because both would put
a transition on the same `done.outcome` event on the root block's own state
and document order - not the caller - would decide which top-level `<final>`
a run reaches.

### The role, and why it is not `done_`

The added finals are minted under an ordinary role (decision 3), so
`unstate_id/1` inverts them and the provenance map stays total over the added
bytes. The role is **`root_<outcome>`**.

It is deliberately not `done_<outcome>`: `core.parallel` already mints the
`done_lane_<name>` family (this record's `complete: first` amendment), so a
`done_` root final would share a namespace with it, and a parallel root
declaring an outcome named `lane_<something>` would mint the same id twice.
`root_` collides with no role any block type mints today, nor with the
reserved `o_` outcome namespace of amendment 2b, nor with C1's `child_`
family.

### What this note does not change

- Amendment 2b's outcome finals, the raises inside them, or the reserved
  `o_` namespace. The root block's own emission is untouched; what the
  option adds is a sibling of the root state under `<scxml>` plus the
  transition that reaches it.
- C1, C2 or C3 in any respect, beyond naming `child_use` as the other half
  of a mutually exclusive pair.
- Decision 5's provenance totality or decision 6's determinism guarantee.
  The added elements are attributed to the root block like every other
  emitted element, and the emission stays a pure function of
  `{document, palette, compiler version, options}`.
- Decision 10's stage table. The refusal of the option pair is an `:emit`
  finding, not a new pipeline stage.

## Note (2026-08-29): where a `<data>` root declaration lives - the `:declare` compile option

A dated note rather than a proposed decision, because it decides nothing this
record has not already decided. Nothing above is edited, no decision changes,
and F2/F3/F6 stand exactly as the foreach amendment of this date wrote them.
What is recorded here is **where a declaration lives** for a root document,
which F6 assumed an answer to and no record had given.

**What forces the note.** F6 refuses a bound name that collides "with author
`<data>` ids", and `StatifierBlocks.Compiler.DeclaredRoots` says in the same
breath that the package has no author- or host-facing `<data>` declaration
concept at all. A production host publishing a root document through a strict
compile found the gap from the other side: against statifier 2.2.0 an
`<assign>` to an undeclared location and a `cond` reading an undeclared id both
raise `error.execution`, so a `core.assign` writing a host-seeded flag and a
`core.branch` guarding on one silently do nothing, and the loop's own source
list had nowhere to be declared either.

**The answer: the compile call.** `StatifierBlocks.Compiler.compile/3` takes a
`:declare` option, a list of `{id, expr}` pairs in declaration order:

    Compiler.compile(document, palette, declare: [{"targets", nil}, {"parked", "false"}])

Each pair becomes one `DeclaredRoots.declare/2` emission, prepended to the root
block's own children before `hoist/1` runs. Everything else follows from that
placement rather than from a second mechanism: the host's roots lead the single
`<datamodel>` in the order given, block-declared roots follow in document
order, and a block declaring a name the host declared is F6's
`:duplicate_binding` against that block and its config key, through the same
walk a nested loop's collision goes through. A document that declares nothing,
option absent or `[]` alike, still gets no `<datamodel>` element, so decision
6's guarantee is untouched and every chart compiled before the option existed
compiles to the same bytes.

**Why the compile call and not the document.** The declaration is a property of
the *deployment*, not of the tree an author edits: the same document published
against two hosts, or against one host's two environments, declares what that
host seeds. A document-level key would put it in the canonical bytes and
therefore in the document hash, which is a schema decision ADR-0001 owns and
this note does not take.

**Validation, and whose fault a bad one is.** An id must be a bare lowercase
identifier - the rule `core.invoke` applies to `assign_to`, because the host is
naming a location the chart will assign to and read in a guard, and
predicator's grammar is what both ends agree on. An `expr` is `nil` or a
non-empty string written verbatim. An ill-formed entry, and an id the option
lists twice, are Emit-stage findings against the root block carrying no
`config_key`, so decision 9's split reads them as `:package` rather than as the
author's - which is right, since no document edit fixes a compile call. Run
creation still wins over `expr` (SCXML 5.3.2); that is the engine's behaviour
and this note does not touch it.

**Provenance (decision 5) stays total.** A host-declared root's bytes belong to
no block, so they take the root block, exactly as `<scxml>` and the
`<datamodel>` wrapper do. The `role` records which surface produced them and is
spelled `:declare`, with the option's own leading colon, so that
`StateId.role?/1` rejects it and no role a block mints out of a state id can
ever equal it. There is no `config_key`, and the id is not a generated state
id, so it stays out of `by_state_id` as any author's `<data id>` does.

**The named follow-ups**, neither taken here:

- **a document-level key**, under ADR-0001, if authors need to declare roots in
  the editor rather than the host declaring them at publish time. That is a
  schema change with a hash consequence, and it is ADR-0001's to make;
- **a declaring block type**, e.g. a `core.declare`, if a declaration is better
  read as part of the tree. That is ADR-0002's declaration surface, and the
  argument `DeclaredRoots` already makes against a new `BlockType` callback
  applies to it.

Either one would be an additional surface, not a replacement: the hoist,
determinism, provenance and F6 refusal are shared, and this note is what F6's
"author-declared `<data>` ids" now points at for its first concrete case.

## Amendment (2026-08-29): the send id is minted through the context, and decision 10's finding shape gains `config_value_span`

**Status: accepted (2026-08-29, unqualified direction-agent verdict under the operator campaign-015b grant, PR 130).** This section is additive: nothing above it
is edited, no accepted decision changes, and the header line's status history
is the conductor's to extend. It records two things the code already does and
this record does not yet say: how a delayed send's `id` is minted, which the
cancel amendment of this date deferred by name, and one optional field
decision 10's finding shape grew after that decision was written.

### S1. The deferred send-id question is discharged, and this is the answer

The delayed-send cancel amendment above closes with a **Deferred, named rather
than guessed** item - "How the send id is minted ... is left to the bead that
implements this section (`sb-b4f`)". That bead has landed. The item is
discharged by this section rather than by editing it: the deferral was
honest when written, and a record reads better with the question and its
answer both visible than with the question quietly removed.

The answer is the one decision 3 already prescribes for every other derived
id, with no new mechanism. `StatifierBlocks.Compiler.Cancels` names the role
once:

    @role "send"

(`lib/statifier_blocks/compiler/cancels.ex:115`) and publishes it through
one public accessor:

    @spec armed_role() :: String.t()
    def armed_role, do: @role

(`lib/statifier_blocks/compiler/cancels.ex:136-137`). `core.send` mints its
descriptor id through the context under that role, exactly as decision 3
requires - "minted through `Context.role_id/2` rather than by string
concatenation inside the block type":

    with {:ok, id} <- Context.role_id(context, Cancels.armed_role()),

(`lib/statifier_blocks/core/send.ex:243`), and the `Compiler.Cancels` pass
reads the same id back by inverting it, selecting the children whose sends it
must cancel:

    {:ok, {^block_id, @role}} <- StateId.unstate_id(id) do

(`lib/statifier_blocks/compiler/cancels.ex:238`).

Three consequences follow from that choice, and they are why the role is
named once in the compiler rather than left to each block type:

- **The two halves name one string in one place.** The minting side and the
  reading side both go through `armed_role/0`, so the convention cannot drift
  between them. The module's own words: "the two halves of the convention name
  one string in one place" (`lib/statifier_blocks/compiler/cancels.ex:132-134`).
- **Decision 3's uniqueness argument covers the descriptor id unchanged.** The
  id is minted by `state_id/2` even though it names a `<send>` descriptor
  rather than a state, which is deliberate: upstream's uniqueness check is over
  all `ID`-typed attributes in one set, and minting through the same function
  is what keeps this id out of every other id's way. Nothing about decision 3's
  totality clause is extended by this - no state is generated here.
- **Selection is by inversion, not by bookkeeping.** The pass recovers the
  owning block from the id itself, so it needs no side-channel from the child
  to the parent. That is what lets decision 4 stand unchanged - `emit/2`
  returns only the block's own emission, and a parent still cannot read a
  child's emitted SCXML - while the cancel is nonetheless emitted in the
  parent's `<onexit>`.

The role is `send` for both halves; it is not an outcome role, and
`Context.role_id/2`'s reserved-prefix refusal is untouched by it.

### S2. Decision 10's finding shape carries an optional `config_value_span`

Decision 10 fixes the finding's ordering, typing, and stage table. The struct
it describes has since grown one optional field, added under decision 9's
last refinement, and decision 10's record does not mention it. Quoted
verbatim from `lib/statifier_blocks/compiler/finding.ex`:

    @type config_value_span :: {non_neg_integer(), non_neg_integer()}

(`:100`), in the struct's type:

    config_value_span: config_value_span() | nil,

(`:107`), in the `defstruct` list:

    :config_value_span,

(`:121`), and populated from `new/4`'s options:

    config_value_span: Keyword.get(opts, :config_value_span),

(`:149`).

It is, in the field's own words, "byte offsets into that value, 0-based,
exclusive end" (`lib/statifier_blocks/compiler/finding.ex:86-87`) - a narrowing
of `config_key`, never a replacement for it. The field's own typedoc states
the criterion and its owner: "Decision 9's last refinement
(`StatifierBlocks.Compiler.Chart` composes it, and its moduledoc owns the
criterion). `nil` on every finding that is not a chart-stage content finding
carrying a sub-expression span, which is the overwhelming majority - a consumer
with nothing to underline falls back to the whole field, exactly as it did
before this field existed." (`lib/statifier_blocks/compiler/finding.ex:89-94`).

Two properties this record cares about, and both hold:

- **Decision 10's "Every finding names a block" is untouched.** The span is
  optional and additive; it narrows *where inside a field*, and says nothing
  about ownership. A finding with a span still names its block and its
  `config_key`.
- **The stage table is unchanged.** Only the Chart stage composes a span, and
  Chart is already in the table. No stage is added, and no stage's error list
  changes.

### What this amendment does not change

- Decision 3's derivation, its three properties, or the role grammar. S1
  records which role `core.send` uses and where it is named, not a new way to
  derive an id.
- Decision 4's rule that a block type writes only its own emission, or the
  cancel amendment's B and C sections. The pass, its scope rule and its
  ordering all stand exactly as that amendment wrote them.
- Decision 5's provenance totality or decision 6's determinism guarantee. No
  byte of any compiled document moves because of this section: both facts it
  records are already true of the code on `main`.
- Decision 9's split, its fault rule, or which surface owns the span
  criterion. That stays `StatifierBlocks.Compiler.Chart`'s moduledoc, as the
  field's own typedoc says.
- Decision 10's stopping rule, its stage table, or its rule that every finding
  names a block.

## Note (2026-08-29): `core.wait`'s timer rides the reserved send role

`core.wait` mints its delayed `<send>` id under the reserved role the cancel
amendment above turns on - `StatifierBlocks.Compiler.Cancels.armed_role/0`,
the role `core.send` already mints under - rather than a role of its own, so a
wait left before its delay elapses has its timer cancelled in the enclosing
scope's `<onexit>` like any other armed send. The wait's own state bounds only
what the interpreter holds, so a delayed send a durable host has already
scheduled outlived it; charts containing a `core.wait` therefore compile to
different bytes than they did (`s_<block id>__send` where the id read
`s_<block id>__timer`), which decision 3's derivation makes a per-block change
and nothing else in the record is edited by (`sb-cqg`).

## Amendment (2026-08-29): `core.subchart`'s `src` is a document id, and a document may not run itself

**Status: accepted (2026-08-29, unqualified direction-agent verdict under the operator campaign-015b grant, PR 133).** This section is additive: nothing above it
is edited, no accepted decision changes, and the header line's status history
is the conductor's to extend. It records the operator's ruling on a question
the `core.subchart` amendment of this date left open - what the emitted `src`
resolves against - and the one refusal that ruling makes decidable inside a
single compile.

The ruling, in the operator's own words as recorded on `sb-0cm`:

> the emitted core.subchart src resolves against the DOCUMENT ID, not
> ADR-0052 chart identity. Reasons recorded with the ruling: chart identity is
> a hash of the emitted bytes, changes on every republish of the child, and
> cannot be known when the parent is authored; the document id is the stable
> authoring-time reference; the host's invoke handler (the ADR-0051 registry
> key statifier_blocks:subchart) resolves a document id to the host's current
> published chart, and pinning a specific child identity at publish time is
> the host's provenance concern (run metadata), not the compiler's. Refusal
> half: the package refuses a subchart whose chart equals the document it sits
> in (direct self-reference); cross-document cycles need a host-supplied
> document graph the compiler does not have and are named host-side.

### R1. What `src` is: the document id, written through verbatim

The shipped emission already does exactly what the ruling settles, and the
ruling is what makes it a decision rather than an accident. Quoted verbatim
from `lib/statifier_blocks/core/subchart.ex`, the `<invoke>` this type builds:

    [{"id", context.block_id}, {"src", chart}, {"type", @invoke_type}],

(`:323`), and the annotation that stamps the attribute back to the field the
author typed into:

    |> Emission.attribute_from_config("src", "chart")

(`:326`). `chart` is the author's `chart` config value, unchanged - no hash is
taken of it, no revision is appended to it, and nothing about the referenced
document is read, because `emit/2` cannot read one (decision 4, and the
subchart amendment's "a block type cannot read the document it references").

Three properties follow, and they are the reasons the ruling gives:

- **A document id is knowable at authoring time.** The parent is authored
  before the child is next published, so a reference minted then must survive
  that publish. A document id does. This is the same stability ADR-0001
  decision 3 gives a block id, one level up.
- **Chart identity is not, and moving would break the reference.** st-ADR-0052
  identity is a content hash of the emitted chart, so it changes on every
  republish of the child. A `src` holding one would name a chart revision that
  the very next edit of the child orphans, and the parent would have to be
  recompiled every time an unrelated document changed.
- **The resolution happens at run time, in the host.** The `type` in the same
  three attributes above is `statifier_blocks:subchart`, and st-ADR-0051 makes
  the handler set deployment state supplied per session. So the handler
  registered under that key is what turns a document id into a chart, against
  whatever the host currently publishes for that document.

### R2. What `src` is not: ADR-0052 chart identity, and where pinning lives

The Context above lists "how the document's identity relates to the engine's
chart identity (st-ADR-0052)" as one of the four questions this record owes an
answer to, and decision 7 answers it for the **compilation record**:
`StatifierBlocks.CompilationRecord` carries both, so a compiled artifact says
which document at which revision produced which chart identity. This section
answers it for the **reference**, which is a different direction and gets a
different answer: the compile of a parent emits a document id and takes no
position on which child identity a run will reach.

A host that must pin a run to a particular child revision - for audit, for
replay, for a provenance chain - records that on the **run**, in run metadata,
from the identity the handler actually resolved. That is host-side for the
reason the compiler cannot do it at all: the compiler is handed one document
and a palette, and the child's identity does not exist in that input. Nothing
here narrows decision 6's determinism guarantee or changes a byte of any
compiled document.

### R3. The refusal: a document may not name itself

The half of the reference a single compile *can* adjudicate is whether the id
it names is the id of the document it sits in. It refuses that case.

| | |
|---|---|
| Code | `:self_reference` |
| Stage | `:emit` |
| Severity | `:error` |
| Attributed to | the offending `core.subchart` block |
| `config_key` | `"chart"` - the author's verbatim value |
| `fault` | `:author`, by decision 9's split, since a config key is present |

Quoted verbatim from `lib/statifier_blocks/compiler/self_reference.ex`, the
criterion:

    @element "invoke"
    @attribute "src"

(`:80-81`), applied to the assembled emission:

    defp element_findings(%Emission{name: @element} = emission, document_id) do

(`:107`) and

    {@attribute, ^document_id} -> [finding(emission, document_id)]

(`:109`). The equality is exact: a document whose id merely shares a prefix with
another is a different document.

**It is not a new pipeline stage.** Decision 10's table is unchanged; the
finding carries the `:emit` stage it is produced in, exactly as the
sensitive-path refusal and the chart-use refusal do, and for the same reason -
the criterion is about the assembled emission rather than about one block's
config, and the pass runs between Emit and Chart where the document id and
every emitted `src` are both in hand:

    :ok <- self_reference_stage(emission, document.id),

(`lib/statifier_blocks/compiler.ex:274`). Decision 10's stopping rule applies
to it unchanged: a document that refers to itself does not reach the Chart
stage, because there is nothing worth serializing.

Decision 10's "every finding names a block" holds. The finding anchors on the
`core.subchart` block through the emission's owner, and on `chart` through the
`attribute_from_config` annotation quoted in R1, which is why the author sees
an underline on the field they typed rather than a chart-level complaint.

### R4. Cross-document cycles are host-side, and this record says so rather than deferring

`A -> B -> A` is the same defect one document further out, and this package
cannot decide it. A compile is handed **one** document and a palette; deciding
a cycle needs the document graph - who references whom across the host's whole
library - and no input to `compile/3` carries it. Inventing a compile option
that took a caller-supplied graph would put the check here while leaving the
truth of its input entirely to the caller, which is a worse answer than naming
the owner.

So the check belongs to the host's resolver, behind the same st-ADR-0051
registry key that resolves a document id to a chart: it is the one component
that sees every reference and the only one that can see a cycle. This is
**documented, not built** - a deliberate scope line, not a deferral waiting on
a bead. Should a later record give this package a document graph, the
criterion in R3 generalizes to it without a second mechanism; nothing here
depends on that happening.

### What this amendment does not change

- The `core.subchart` amendment's C1, C2 or C3. The routing, the outcome
  crossing, and the explicit `<invoke id>` all stand exactly as written; only
  what `src` *means* is settled here, and the shipped bytes already meant it.
- Decision 6's determinism guarantee or the compilation record's fields. No
  byte of any compiled document moves because of this section.
- Decision 9's fault split or which surface owns `config_value_span`. The
  refusal carries no span: only the Chart stage composes one.
- Decision 10's stage table, its stopping rule, or its rule that every finding
  names a block.
- The loose grammar `core.subchart` accepts for the `chart` field. This
  package does not own the shape of a host's document ids, and tightening the
  check would be a second, quieter proposal about what a reference may say.

## Note (2026-08-30): the editor's `invoke_types` assign, a suggestion list over decision 8's data

A dated note rather than an amendment, recorded for `sb-ht79` under
campaign-021 ruling R5. It records a seam the editor now carries and changes
nothing this record decides. The record's Status is untouched, no compiled
byte moves, and the compiler is not edited.

### What decision 8 left for a presentation to answer

Decision 8 closed the compile-time question and named the one it did not
close: "Whether the editor surfaces the mismatch live while authoring is a
presentation decision over data this record supplies." This note is that
presentation decision, made in the smallest form that is useful.

`StatifierBlocks.Editor` accepts an optional `invoke_types` assign - a list
of strings a host supplies, defaulting to empty. When it is non-empty, an
`invoke_type` config field renders as a text input bound to a `<datalist>`
of those strings; when it is absent or empty the field renders as the plain
text input it has always been. `StatifierBlocks.Editor.Field` owns the
rendering.

### Why a datalist, and not a select

Because decision 8's argument is about what may be *refused*, and a control
that refuses would contradict it. A `<select>` would make the host's list
the vocabulary; a `<datalist>` makes it a suggestion, and an author may type
a type that is on no list and have it stored verbatim. That is the same
answer decision 8 gave for the compile - the lint warns and never errors -
carried into the control an author actually touches, so the editor and the
compiler cannot disagree about whether an unknown type is allowed. Nothing
about what compiles changes: an unknown type stays a lint, on request, and
never a refusal.

The lifetime argument is why the list arrives as an assign and is stored
nowhere. Decision 8 grounds the two-registry gap in st-ADR-0051 making the
handler set **deployment state, supplied per session**, against a palette
that is authoring state. A suggestion list is a fact about the deployment
the author happens to be pointed at, so it is passed in per render by the
host that knows it, and no byte of it reaches the block, the document or
the compiled artifact. An authoring server with no handler map at all
supplies nothing and loses nothing, which is the case ADR-0002's
consequences blessed and this seam must not quietly un-bless.

### The two `invoke_types` surfaces, which are not the same surface

The name is now used twice on purpose, and the two are read from opposite
ends of the same vocabulary:

- **`%Compiled{}`'s `invoke_types`** (decision 8) is *derived from a
  document*: the sorted set of types the generated SCXML actually emits.
- **the editor's `invoke_types` assign** is *supplied by a host*: the types
  it is prepared to answer, the same set decision 8 describes a host handing
  to `:known_invoke_types`.

Neither reads the other, and no code path connects them. A host that already
computes one for the compiler's opt-in lint has the other for free, which is
the intended ergonomics rather than a coupling: decision 8's "one-liner over
a field it already published" gains a second reader, not a second producer.

### What this note does not do

- It does not touch the compiler, `:known_invoke_types`, or the lint's tier.
  The warning stays a warning and stays opt-in.
- It does not make the editor validate an invoke type. The `invoke_type`
  field's own shape check is `Core.Invoke`'s, unchanged, and the
  two-registry check remains the compiler's on request and the host's at
  deploy time.
- It does not widen ADR-0002 decision 7's field-type set. No new field type
  exists; a `:string` field keyed `invoke_type` renders differently, and a
  block type that declares `invoke_type` as some other field type keeps that
  type's control.
- It does not decide whether the editor shows a *live mismatch finding*
  while authoring. Decision 8 named that as sb-w50's, and a suggestion list
  is not it: this note supplies the vocabulary at the point of typing and
  leaves the surfacing question exactly where decision 8 left it.

## Note (2026-08-31): the document-level key is taken, and the Emit stage's first warning

A dated note rather than an amendment, recorded for `sb-ao6l` under
campaign-022 ruling R3. It records where two things this record already
anticipated now render, and one small fact the accepted text did not
contemplate; no decision above changes and no text above is edited.

**The first named follow-up is taken.** The Note (2026-08-29) on the
`:declare` compile option closed with two named follow-ups, "neither taken
here". The first - "**a document-level key**, under ADR-0001 ... a schema
change with a hash consequence, and it is ADR-0001's to make" - has been
taken, by ADR-0001's Amendment (2026-08-31), decision 11. The second - "**a
declaring block type**, e.g. a `core.declare`" - is *not* taken and remains
ADR-0002's, with the argument `DeclaredRoots` makes against a new `BlockType`
callback still standing against it. That note's closing sentence held: the
key is an additional surface, not a replacement, and the hoist, determinism,
provenance, and the F6 refusal are shared with it unchanged.

**The `:declare` option is unchanged in every particular.** Its grammar, its
Emit-stage refusals, its `:package` fault, its provenance role, and its
place at the head of the single `<datamodel>` all stand exactly as the note
wrote them. What changed is one word of status: it is no longer the *only*
surface. ADR-0001's decision 11f fixes the full order - option roots first
in the order given, then the document's roots in its `datamodel` key's
order, then block-declared roots in document order - and fixes host-wins for
an id both the option and the document declare, with the document's entry
dropped and a warning emitted.

**The Emit stage now produces a warning as well as errors.** That shadow
warning (`:shadowed_document_root`, ADR-0001 decision 11f) is minted at the
Emit stage, and decision 10's table - "Errors it can produce" - did not
previously contemplate an Emit-stage warning. The table is not edited, and
does not need to be: it is a table of *errors*, and a warning is not a stage
verdict. The stage still stops the compile only on errors, and the warning
rides on `%Compiled{}.warnings` exactly as decision 8's invoke-type lint
warning does - present on success, never a refusal, ordered with the rest by
the compiler's final pass.

**Provenance role `:datamodel` joins `:declare`.** A document-declared
root's bytes belong to no block, so they take the root block under decision
5's totality, with the role spelled `:datamodel` - a leading colon, in the
same reserved namespace the `:declare` note opened, so `StateId.role?/1`
rejects it and no role a block mints out of a state id can equal it. Two
non-block surfaces, two roles, one namespace; a consumer that switched on
`:declare` alone should switch on the leading colon instead.

## Amendment (2026-08-31): `core.drafts` emits nothing, `core.placeholder` emits a step, and four findings

**Status: accepted (2026-09-01), drafted for `sb-5h6q` under the operator campaign-024 grant; accepted on the gate's unqualified direction-agent verdict.** Additive; decisions 1
through 11 stand as accepted and no text above this line is edited by this
section. It is the compiler half of ADR-0002's amendment of this date, which
adds `core.drafts` and `core.placeholder` to decision 10's vocabulary
(campaign-024 rulings R-a and R-b); the two records were drafted together and
neither is readable without the other.

### What forces the amendment

Decision 5 makes provenance total: every byte of generated SCXML belongs to
exactly one block, and every block is answerable for the bytes it produced.
Decision 6 makes the compile deterministic against the document hash. Both
were written when every block in a document was in the flow, and a shelf is
the first block type that is not.

The question this section answers is not "how does a drafts block compile" but
"what does it mean for the record's own invariants that one block compiles to
nothing at all". Three of them are touched: totality (D2), determinism and the
document hash (D5), and decision 10's stage table (D3, D4).

### D1. `core.drafts` contributes nothing, and its contents contribute nothing

A `core.drafts` block emits no state, no transition, no `<data>` element, no
send and no attribute. Neither does any block inside it, at any depth. The
Emit stage does not call `emit/2` on the shelf or on anything under it, so a
shelved block type is not merely emitting-and-discarded: it is never asked.

ADR-0002's amendment of this date, section G9a, is what this rests on. The
shelf is elided from the root's child list before anything reads sequencing,
so the root's compiled state has the children it would have had if the shelf
were not in the document, in the order it would have had them. There is no
gap, no empty state and no skipped position.

**The bytes are identical, and that is the acceptance property.** Two
documents alike in everything except the contents of their `core.drafts`
block - one empty, one holding four fragments - compile to byte-identical
SCXML. So do a document with a shelf and the same document with the shelf
deleted. Anything else would mean a parked fragment was reaching the chart,
which is the entire failure the type exists to prevent.

### D2. The provenance map has no entry for a shelved block, and decision 5 is intact

Decision 5's totality runs from bytes to blocks: every generated byte maps
back to a block. It does not run the other way - it has never promised that
every block appears in the provenance map, and it could not, because a block
type's `emit/2` may legitimately produce a subtree in which some child
contributes no addressable span of its own.

A shelved block is that same absence taken to its limit and it is worth being
explicit rather than leaving a reader to infer it: `provenance` carries no
entry for the drafts block or for anything inside it, `StateId` mints no id
for any of them, and a runtime position can therefore never resolve to a
shelved block. That last is the property that matters at runtime. A position
captured against a chart names a state; no state was emitted for a fragment;
so no session can be sitting in one. The reserved-role namespace the
`:declare` note opened (`:datamodel`, `:declare`) is untouched by this
section - a shelf takes no role because it takes no bytes.

### D3. Two Structure-stage errors: `:drafts_block_misplaced` and `:duplicate_drafts_block`

ADR-0002's amendment of this date, section G12, states the two placement facts
`io/1` cannot carry, and campaign-024 ruling R-b puts their enforcement in
this stage. Decision 10's table is not edited; these two codes are written
here and read as additions to its Structure row, which is the convention this
record's earlier amendments use for a row a ruling adds:

| Code | Named against | Means |
|---|---|---|
| `:drafts_block_misplaced` | the `core.drafts` block | a `core.drafts` block appears somewhere other than as a direct child of the root block's `body` slot |
| `:duplicate_drafts_block` | the second and every later `core.drafts` block, in document order | the document carries more than one |

Both are errors, both carry `fault: :author` - which is not a judgement call
but what the stage already fixes, since every `:config` and `:structure`
finding is the author's under decision 9's split - and neither carries a
`config_key`, because neither is about a value in a form. Their anchor is the
block, which is decision 5's totality doing its ordinary work: an
unplaceable block is still a block and still names itself.

Naming the *second* drafts block rather than the first is deliberate. The
first one in document order is the one the author almost certainly means to
keep, and a finding on it would ask them to fix the block that is not the
problem. This is the same reasoning ADR-0001 decision 11f applies to a
shadowed root - the later claim yields - arriving at a different rule for the
same reason.

**Both belong in this stage on its own terms**, not only because a ruling put
them there. The Structure stage is where arity, `:undeclared_slot` and
assignability already live; it runs after Config, so an author with a
malformed form is not first told about their shelf; and it runs before Emit,
so nothing has been generated for a block that should not be in the document.

### D4. Two Emit-stage warnings: `:draft_blocks_present` and `:placeholder_block`

The Note of 2026-08-31 on the document-level key recorded that the Emit stage
now produces warnings as well as errors, and that decision 10's table is a
table of *errors* and does not need editing to accommodate one. Two more
arrive here on exactly that footing.

| Code | Stage | Severity | Fault | Anchor | Minted |
|---|---|---|---|---|---|
| `:draft_blocks_present` | `:emit` | `:warning` | `:author` | the `core.drafts` block | once per document, when the shelf's `body` is non-empty |
| `:placeholder_block` | `:emit` | `:warning` | `:author` | the `core.placeholder` block | once per placeholder block |

Both ride on `%Compiled{}.warnings` exactly as decision 8's invoke-type lint
warning and the shadow warning do: present on success, never a refusal,
ordered with the rest by the compiler's final pass. **The compile succeeds.**
That is the whole design and not an incidental property - an author's reason
for parking a fragment or marking a gap is that the workflow is unfinished,
and a compiler that refused to build an unfinished workflow would refuse
exactly when the author most needs to see it run.

**`:draft_blocks_present` is one finding, not one per fragment.** The fact
being reported is about the document - this document has parked work in it -
and it is reported once, on the shelf, whether the shelf holds one fragment or
twenty. Minting one per fragment would make the warning's loudness a function
of how much the author had parked, which is backwards: a well-used shelf is
not a worse document than a lightly-used one.

**An empty shelf mints nothing.** A `core.drafts` block whose `body` is empty
produces no warning at all, because there is nothing to say. Combined with
D1's byte-identity, that makes an empty shelf completely invisible to every
consumer of a compile: same SCXML, same provenance, same warnings. An author
who empties their shelf has a document that compiles as though they had never
had one.

**`:placeholder_block` is one per marker**, for the mirror-image reason: each
one is a distinct gap at a distinct place in the flow, and an author fixing
them needs to be told about each. The `note` config value, when the author
wrote one, is carried in the finding's message so the panel says what the
author said the gap was for; ADR-0002's amendment of this date, section G10b,
is what fixes that the package never otherwise reads it.

**What a host does with either warning is the host's.** The publish gate the
first embedder wants - refuse to publish a document that still warns - is a
host policy read off `%Compiled{}.warnings`, and this record neither
implements it nor requires it. That separation is decision 8's, already: a
lint is information, and what a deployment does with information is not the
compiler's decision.

### D5. `core.placeholder` compiles to a step that does nothing

A marker is in the flow (ADR-0002's amendment of this date, section G10), so
it has to compile to something or the flow would break around it. It emits the
smallest thing a step can be: one compound state carrying a single `<final>`
reached on entry, so the block completes immediately and the parent's ordinary
`done.state` sequencing carries on to the next sibling. It is decision 2's
shape with the default single `done` outcome and no work in it.

That the empty step is a *real* step is the point. The chart runs; a preview
walks straight through the gap; a session that reaches a placeholder leaves it
in the same macrostep. An author previewing a half-built workflow sees the
half they built, which is what makes a marker cheaper to place than a hole.

There is no `<log>`, no raised event and no data written. A marker that
announced itself into the chart would be a marker the author had to remember
to remove before the chart was real, and the warning of D4 is where the
reminder belongs - in the compile, addressed to the author, not in the running
machine addressed to nobody.

### D6. Determinism and the document hash: differing shelves, identical charts

Decision 6 is untouched and decision 7's two-hash split is what absorbs this.
Decision 6 already states the case, in the paragraph fixing that its guarantee
is not reversible: "Equal output does not imply equal input: a `metadata`-only
edit changes the document hash and produces identical SCXML." Shelf content is the second instance of exactly
that shape, and ADR-0001's Amendment (2026-08-31) decision 11d recorded the
first repeat of it for the document-level datamodel key.

So, stated in full because a reader of decision 7 will otherwise have to
derive it: two documents that differ only in the contents of their
`core.drafts` block have **different `document_hash` values and byte-identical
SCXML**, and therefore the same chart identity under st-ADR-0052. Parking a
fragment, reordering the shelf, or editing a shelved block's config all move
one hash and not the other.

Everything decision 7 says about that situation continues to hold with no
addition. `%Compiled{}.record` carries both hashes, so a caller that needs to
know whether the *document* changed reads `document_hash` and a caller that
needs to know whether the *chart* changed reads chart identity; a running
session pinned to a chart identity is unaffected by any amount of shelf
activity, which is the same non-reversibility the metadata case has always
had and the reason decision 7 keeps the two hashes apart.

**Determinism itself is unchanged.** The elision of G9a is a pure function of
the document - the shelf is found by block type, at a fixed position, with no
ordering question to get wrong - so the same document and the same palette
still compile to the same bytes, which is all decision 6 claims.

### What this amendment does not change

- **Decision 5's totality**, in the direction it was stated. Every generated
  byte still names a block. D2 records that the converse was never claimed.
- **Decision 9's fault split.** Both new Structure errors are `:author` because
  the stage already decides that; both new Emit warnings are `:author` because
  a parked fragment and a marked gap are things the author did on purpose.
- **Decision 10's stopping rule.** The pipeline still stops at the first stage
  producing errors and still reports every error from that stage. A document
  with two misplaced shelves reports both and never reaches Emit.
- **The Config stage's reach.** It walks the document, so it still runs
  `validate_config/1` on every block inside the shelf and still reports
  findings against them. The Chart stage's reach excludes them for the
  opposite reason and with no rule of its own: it maps findings from
  `Statifier.compile/2` over emitted bytes, and no shelved block emitted any.
- **The document schema.** ADR-0001 is untouched and `schema_version` stays
  at `1`.
- **Chart identity and the invoke-handler registry.** st-ADR-0052 and
  st-ADR-0051 are statifier-ex's; this record remains a client of both and
  changes neither.

## Note (2026-09-06): a failure-classed outcome's top-level `<final>` carries a reserved `<donedata>` param, under both options

A dated Note rather than an amendment. It edits nothing above this line, and
two sentences above it are narrowed by it rather than replaced - both are
quoted here so a reader meets the narrowing where the sentence is, not by
inference.

The 2026-08-29 root-termination Note says of a `terminate: true` compile that
"the finals carry **no `<donedata>`**", and its closing paragraph says
`child_use: true` "remains the only thing that emits `<donedata>`". Both were
true of every outcome a block type could declare when they were written,
because no outcome could say anything about itself. `sb-napt` gives one the
means to, under the operator's campaign-033 ruling `RQ-033-3` of 2026-09-06.

**The narrowing, in one sentence.** A top-level `<final>` for an outcome that
`StatifierBlocks.BlockType.failure_outcomes/2` classes as a failure carries a
`<donedata>` with the single reserved `<param>`

    <param expr="'failed'" name="statifier_persistence:run_status"/>

under `:terminate` **and** under `:child_use`, where it is appended after the
`outcome` param the child shape already emits. Every other final is
byte-identical to what it was: a `:terminate` final for an unclassed outcome
is still bare, a `:child_use` final for one still carries the `outcome` param
alone, and a compile passing neither option still emits no top-level final at
all.

**Why the root shape gains a payload it was written not to have.** The
root-termination Note's reason for emitting none was that "nothing is
listening across a boundary". That is no longer true: a durable stepper reads
the `{:done, _}` effect of a root document's own run and, on this key, decides
that the run **failed** rather than completed. The reader is the run's own
host rather than a parent across an `<invoke>`, which is precisely the case
the Note did not have. The key and its closed value set are not this record's
to set - they are fixed by `statifier_persistence`'s ADR-0008 amendment of
2026-09-06 (`sp-n8g`, the mirrored half of this bead), which also records why
`<donedata>` carries the tag rather than a state-id convention or a compiled
`<final>` attribute, and why the separator is a colon rather than a dot.

**Determinism is untouched (decision 6).** The class is a pure function of the
block type and its config, the param is emitted in one place in one order, and
a document whose root type classes no outcome compiles to the bytes it
compiled to before the callback existed. Opting into `terminate` is still the
one-time chart-identity choice that Note describes, and a root type that
*starts* classing an outcome moves the document's content hash for the same
reason and with the same consequence.

**Decision 5's totality holds by construction.** The `<donedata>` and its
`<param>` are children of the final the root block already owns, stamped
through the same `Attribution.stamp/3` call, so they carry the root block's
id in its `root_` or `child_` role and the map stays total over the added
bytes rather than growing a hole nobody owns.

**One thing a chart author has to do for the final to be reachable**, noted
because it is easy to miss and is not new: `core.map` and `core.subchart` emit
the route to their `error` outcome only when the matching `on_error` slot is
occupied (`core.invoke`'s rule, unchanged here). A root document that classes
`error` and leaves the slot empty compiles a failure-classed final nothing can
enter - which is the pre-existing shape ADR-0002's outcome amendment already
describes for any wired-but-unemitted outcome, met here for the first time by
an outcome that matters to a stepper.

Filed with `sb-napt`, mirrored with `sp-n8g` in `statifier_persistence`;
campaign-033 ruling `RQ-033-3`.

## Note (2026-09-06): the root shape gains one shared `<final>` for an unhandled failure below the root

A dated Note, not an amendment. Decision 5's totality rule, decision 6's byte
determinism, decision 3's role namespace and the root shape the 2026-08-29
root-termination Note and C1 fix are all unchanged; nothing above this line
loses a word. What is recorded here is the reading of one more span the
compiler emits under the same two options, because ADR-0002's amendment of
2026-09-06 says what those bytes *are* and why, and leaves their reading as a
root shape to this record - exactly as the reserved failure param's was, in
the Note above this one.

**The span.** Under `child_use: true` or `terminate: true`, and nowhere else,
a document with at least one unhandled failure-classed outcome below its root
block emits **one** additional top-level `<final>`, sibling of the completion
finals, plus one `<transition>` on the root block's own state per unhandled
pair. The final's id is minted from the root block's id under the role
`child_failed` or `root_failed` - the same two prefixes the completion finals
use, so a reader can tell which compile option produced it, and both are
ordinary roles in decision 3's sense that `unstate_id/1` inverts. Its
`<donedata>` carries the reserved `statifier_persistence:run_status` param
that the Note above fixes, and under `child_use: true` the `outcome` param
valued `'error'` ahead of it. Which outcomes count as unhandled, and why the
answer is a property of the failing block rather than of the container above
it, is ADR-0002's amendment of this date, section 4.

**Attribution splits, and decision 5 stays total.** The shared final is
stamped to the **root block**, in its `child_failed` or `root_failed` role,
because the document's own ending is a fact about the root and about nothing
else. Each catch transition is stamped to **the failing block**, following
decision 5's own rule and `Emit.chain/2`'s reading of it: "what happens after
the authorize step fails" is a fact about the authorize step. Both go through
the same `Attribution.stamp/3` every emitted span goes through, so the
provenance map stays total over the added bytes; a finding landing in a catch
transition points the reader at the block that failed rather than at the root
or at this package.

**Determinism is untouched (decision 6).** The walk is document pre-order over
the resolved tree, the collected set is read off `outcomes/1` and
`failure_outcomes/1` - both pure functions of config - and one shared final is
emitted whatever the size of the set. A document with no unhandled
failure-classed outcome below its root emits nothing at all and compiles to
the bytes it compiled to at 0.21.0, which `sb-hxs5` pins over a corpus of five
documents in three compile modes each. A document that gains the span moves
its content hash, and is a new chart revision under statifier-ex ADR-0052 -
the one-time cost the Note above already described for a root `core.map` or
`core.subchart`, met here by every chunk-shaped document.

**The transitions are external**, like the completion transitions beside them
and for the same reason: the point is to leave the root state for a sibling
final. A `<transition>` with no `type` attribute is external in SCXML, so the
attribute is absent here rather than spelled out, which is also what keeps the
added bytes comparable to the completion transitions a reader is already
holding.

**What this narrows in the Note above.** That Note closes on "one thing a
chart author has to do for the final to be reachable": `core.map` and
`core.subchart` emitted the route to their `error` outcome only when the
matching `on_error` slot was occupied, so a root document classing `error`
with the slot empty compiled a failure-classed final nothing could enter.
ADR-0002's amendment of this date, section 2, removes that condition for
`core.invoke`, `core.map` and `core.subchart` alike: the failure final is
emitted always and, with the slot empty, the failure transition targets it
directly. The paragraph's sentence held when it was written and is superseded
for the empty-slot case from this date; nothing else in it moves.

Filed with `sb-hxs5`, against ADR-0002's amendment of 2026-09-06;
campaign-034 rulings `RQ-034-1` and `RQ-034-13`.

## Amendment (2026-09-06): C1's `child_use` final may carry declared summary params after the outcome param

**Status: accepted (2026-09-06, campaign SF035, bead `sb-jvz3`, recording
campaign-034's ruling `RQ-034-2`).** A decision record merges at proposed under
the campaign invariant; flipping it to accepted is a separate gated request
through the same `docs/adr/` gate, and `sb-upv0` carries it. Additive: C1
stands as accepted, and no text above this line is edited by this section.

An amendment rather than a Note, because C1 says what a `child_use` final
carries in as many words - "carrying the outcome name as done data"
(`:1267`), with the `<donedata>` shape drawn as a single `<param>` at `:1272` -
and this record now says a final may carry more.

**What is decided.** A document compiled with `child_use: true` still emits one
top-level `<final>` per root-block outcome, reached by the same transition on
the same `done.outcome.s_blk_ROOT.<outcome>` event. Its `<donedata>` may now
carry, in this order:

1. `<param name="outcome" expr="'<outcome>'"/>` - C1's own, unchanged, first;
2. the reserved `<param name="statifier_persistence:run_status" expr="'failed'"/>`
   on a failure-classed outcome only - the Note of 2026-09-06 at `:2457`'s,
   unchanged, second;
3. one `<param name="<name>" expr="<path>"/>` per entry the root block type's
   optional `donedata_type/1` callback declares, in declaration order.

The third group is `ADR-0013` decision 3
(`docs/adr/0013-typed-fan-out-child-summary.md`, proposed 2026-09-06); the
callback that produces it is that record's decision 2, recorded on `ADR-0002`
by the Note filed with this amendment. `ADR-0013` itself says the widening is
this record's to make and does not make it (`:293-294`).

**Why after both compiler-minted params rather than between them.** Decision
6's byte determinism. A document whose root type declares nothing compiles to
exactly the bytes it compiles to today, and a failure-classed final does not
have its two existing params reordered by a declaration that arrives later.
The ruling's phrase "after the outcome param" is satisfied by either position;
byte stability picks this one. A document that declares something moves its
content hash and is a new chart revision under statifier-ex `ADR-0052`, the
one-time cost the Note at `:2522` already describes for the shared failure
final.

**The declared params are emitted on every top-level `child_use` final**,
including a failure-classed one, because `donedata_type/1` is a pure function
of the root block's config and the compiler classes outcomes rather than runs.
It has no other information at the point it mints them. They do not thereby
reach the parent from a failed child: `ADR-0009`'s Note of 2026-09-06 records
that a child run settling in a failure-classed final is stored `failed` and
that the driver answers the parent's invocation with
`{:failed, reason: <the run's failure>}` rather than with donedata
(`docs/adr/0009-fan-out-block-type.md:915-917`), so on that arm the collected
element carries a `"failure"` map and no `"donedata"` key at all (`:921-925`).
The bytes are minted and unread there, which is a cost in the compiled document
and nothing else - and a document compiled for use as a child is also a
document a host may run directly, where its `<donedata>` is read by whoever
invoked it.

**Two names a declaration may not mint.** `outcome` and
`statifier_persistence:run_status` are the compiler's, reserved by C1 and by
the failure seam respectively, and a `donedata_type/1` entry colliding with
either is an `:invalid_donedata_field` Emit finding against the root block
rather than a silently shadowed param. That refusal is what keeps the two
groups above separable, and it is `ADR-0002`'s Note of this date that declares
it.

### What this amendment narrows in the Note of 2026-08-29

That Note's `terminate` sibling closes on a sentence this amendment reads
against, and it is quoted here so a reader meets the narrowing rather than
inferring it. Under the heading "`child_use` stays the child-chart shape"
(`:1707`) it says: "This note adds a sibling; it does not widen C1"
(`:1709`). Every word of that sentence held when it was written and holds now
about **that** Note: the `terminate` option added a sibling shape and widened
nothing. What it is not is a promise that C1 is never widened - and this
amendment widens it, from a different bead, a different campaign and a
different question. The sentence is narrowed to its subject from this date:
the `terminate` Note does not widen C1; this section does.

Nothing else in that Note moves. `child_use: true` remains what a document
compiled **for use as a child** passes and remains the only thing that emits
`<donedata>` (`:1710-1712`); the two options remain **mutually exclusive**,
refused at compile with an `:emit` finding when both are passed
(`:1714-1719`); and the `terminate` finals still carry no `<donedata>` at all
(`:1696-1698`), so `donedata_type/1` reaches them not at all. A root type that
declares fields and is compiled with `terminate: true` emits none of them,
because there is no boundary for them to cross - which is that Note's own
reason, unchanged.

Filed with `sb-jvz3`, against `ADR-0013` as merged (PR 319, `b90d40e`);
campaign-SF035, from campaign-034's ruling `RQ-034-2`. `sb-nqfd` builds the
emission.

## Note (2026-09-06): decision 10's "first failing stage" takes exactly one exception - Config and Structure report together

`RQ-SF035-2`, taken by the operator with the campaign-SF035 walk and
implemented by `sb-c9b6`, amends one sentence of decision 10. The sentence is
"The pipeline stops at the first stage producing errors and reports every
error from that stage", and the rule it states now holds everywhere except
across the Config/Structure boundary: when the Config stage produces errors,
the Structure stage still runs, and the refusal carries the **union** of what
both found.

### Why this record and not another

The `sb-c9b6` brief named `ADR-0002` for this Note. That is a mis-cite and it
is worth saying so here rather than leaving the correction to be re-derived.
`ADR-0002` decides what a block type **declares** rather than when the
compiler consults it, and its decision 10 is a different thing again: "The
core vocabulary, as answers to these callbacks", the table of what each
shipped block type answers to `slots/1` and `config_schema/1`. Neither that
decision nor any other in `ADR-0002` states a rule about stage sequencing.
The "first failing stage" rule is **this** record's decision 10, so this is
where the amendment belongs.

[Cure 2026-09-06, `sb-c9b6`, pass 1 of the direction review: the paragraph
above first described `ADR-0002` decision 10 as the outcome-name vocabulary.
It is not - outcome names entered `ADR-0002` through its separate outcomes
amendment of 2026-08-29, and decision 10 is the callback-answer table quoted
here. The correction is to this Note's own explanatory prose; the conclusion
it supports, that the amended sentence is `ADR-0004`'s and not `ADR-0002`'s,
is unchanged and independently evidenced - `ADR-0002` carries no "first
failing stage" sentence at all.]

### What is amended, and what is not

The stage table is unchanged: the same five stages produce the same errors,
and Config and Structure keep the rows they have. What changes is only the
sequencing between those two rows.

Unchanged, and each for its own reason:

- **Resolve still stops the pipeline.** Decision 10's cascade argument is
  literally true there - a document with an unresolvable block type has no
  module to ask for a config schema or a slot set, so neither later stage has
  a question to put.
- **Structure still stops the pipeline before Emit.** Emit reads a tree
  Structure has agreed is well-formed, so an emit finding on a document
  Structure refused is a consequence, which is exactly what decision 10
  exists to keep out of an error panel. Chart and the stages after it are
  likewise untouched.
- **Within a stage every finding is still reported.** That clause is not
  weakened; this Note extends its argument by one boundary rather than
  replacing it.
- **Every finding still names a block.** Decision 5's totality is what makes
  the union renderable at all - two findings from two stages on two different
  cards are two annotations, not a list an author has to read positionally.
- **Refusal semantics are unchanged.** A document with a Config finding still
  does not compile. It now says more about why.

### Why the boundary moves here and nowhere else

Decision 10's own justification is that a later stage's findings on a
document an earlier stage refused are *consequences* rather than siblings.
Config and Structure are the one adjacent pair for which that is false.
Config reads config **values** - what `validate_config/1` says about them,
what a declaration is missing, what a declared payload does not carry.
Structure reads the **document** - slot counts, placement, and the reads and
writes blocks declare along the walk. A mis-typed field on one card and an
unsatisfied read on another are two independent statements about one
document, in decision 10's own sense of the word: neither is derived from the
other, and neither becomes true or false when the other is fixed.

The cost of treating them as sequential is paid by whoever has to fix the
document. A `:config` finding anywhere in a document hid every assignability
finding everywhere in it, so an author fixed the config, recompiled, and only
then discovered the typed refusal - one round trip per stage, on a surface
whose whole purpose is to answer while the author is still looking at the
card. The first production embedder cannot report a typed refusal in that
state at all, which is the ruling's occasion.

### The precondition the old sequencing bought, and how it is bought now

Running Config first bought something every source in the Structure stage
relied on without saying so: **only accepted config ever reached Structure**.
That is not a fact about assignability alone. `SlotValidation` counts a
block's children against the slot set `slots/1` derives from that block's
config (`ADR-0002` decision 6); `StatifierBlocks.Shelf` places a block the
config named; and a read or write signature is read off the config's path
fields. All three consult the value Config just refused.

So the precondition is bought again explicitly. A block Config refused is
**skipped by id** for the whole Structure stage: it reports no structure
finding of its own, and its declared writes leave no entry in the typed
environment (`ADR-0011`'s Note of this date carries the walk-side half). The
walk is not shortened - its siblings, its children and every other block are
checked exactly as they would have been - so what this is, is an absence of
one block's answers. A document with no `:config` finding has an empty skip
set and is compiled by the pipeline it was always compiled by; the byte
corpus is green unchanged.

### What a consumer of the finding list sees

One list may now carry findings from two stages at once, and therefore two of
`ADR-0005` decision 11's `source` values - `:config` and `:assignability` -
where before a refusal carried one. No value is added to that enum and no
mapping changes: `11h`'s stage-to-source rule already answers per finding,
and the adapter never promised a list was homogeneous. A surface that
*groups* findings by source will render two groups where it rendered one,
which is the intended result and the reason decision 5's per-block anchor
matters. Document order over blocks is also unchanged - the union is sorted
by the same pre-order rank, so a card's own findings stay together.

Filed with `sb-c9b6`, campaign-SF035. Code:
`lib/statifier_blocks/compiler.ex` (`compile/3`'s `with`,
`config_and_structure_stages/4`, `structure_stage/4`); goldens in
`test/statifier_blocks/compiler/both_stage_findings_test.exs`. Folds
`sb-lvh1`, which asked this question from the reference embedder's document.

## Note (2026-09-06): what the flip of the C1 amendment checked

`sb-upv0` is the separate gated request the amendment of this date names in
its own status paragraph (`:2592-2596`), and it has flipped that section's
`Status:` word from `proposed` to `accepted`. The word is the only text the
flip changes in this record; this Note is by addition, sits at the foot so no
line another record cites moves, and carries no `Status:` line of its own, as
a Note in this family carries none.

`sb-nqfd` (PR 353, `cc841a9`) put the emission on `main`, and the section was
verified against `main` at `94d1990` - the tip after `sb-1jcr` (PR 355,
`d804062`) and `sb-268w` (PR 356, `94d1990`) - rather than against the tree it
was drafted over. The `0.23.0` release prep
(`081e426`) landed on `main` while this flip was open; it changes two version
strings one line for one line and moves no line this Note cites.

**The three groups are in the order the amendment fixes, and nothing else
moved.** `completion_final/5` builds the `outcome` param first, the reserved
`statifier_persistence:run_status` param second and only on a failure-classed
outcome, and the declared params third, appended and never sorted
(`lib/statifier_blocks/compiler.ex:1709-1719`, the list at `:1710-1713`;
`declared_params/2` at `:1755-1762`, mapping each `donedata_type/1` entry to a
`<param>` whose `expr` is the declared path). A root type declaring nothing
produces the same two-group list it produced before the callback existed,
which is what the byte corpus pins
(`test/statifier_blocks/compiler/byte_corpus_test.exs`).

**The declared params are on every top-level `child_use` final**, failure
classed included, because `donedata_type/1` is read once per root config and
the compiler classes outcomes rather than runs. The `terminate` finals carry
no `<donedata>` at all, so a declared field reaches them not at all - the
narrowing this amendment states about the Note of 2026-08-29 is what the code
does.

**The two reserved names are refused.** A `donedata_type/1` entry named
`outcome` or `statifier_persistence:run_status`, or not a bare lowercase
identifier, is an `:invalid_donedata_field` Emit finding against the root
block rather than a silently shadowed param
(`lib/statifier_blocks/compiler.ex:1971-1984`).

**Every cite in the amendment resolves unchanged.** C1's heading and its
"carrying the outcome name as done data" sentence are at `:1262` and `:1267`,
the drawn `<param>` at `:1272`; the Note of 2026-08-29's sentences are at
`:1696-1698`, `:1707`, `:1709`, `:1710-1712` and `:1714-1719`; the reserved
param's Note is at `:2457` and the shared-final Note at `:2522`; `ADR-0013`
`:293-294` still says the widening is this record's to make; and `ADR-0009`
`:915-917` and `:921-925` still carry the failed arm. Nothing above the
amendment was edited by it or by this flip.

Filed with `sb-upv0`, campaign SF035's Lane A.

## Amendment (2026-09-07): a composite expands at the Resolve stage, and a finding inside an expansion is attributed one level up to the param that produced it

**Status: accepted (2026-09-07, campaign SF037, bead `sb-nzc1`, recording
campaign-SF037's rulings `RQ-SF037-5` and `RQ-SF037-6`).** A decision record
merges at proposed under the campaign invariant; flipping it to accepted is a
separate gated request through the same `docs/adr/` gate, and `sb-v3ny` carries
it. Additive: decisions 3, 5, 6, 8, 9 and 10 stand as accepted, and no text
above this line is edited by this section.

An amendment rather than a Note, because the pipeline gains a step it does not
have today and decision 5's `owner` gains a reporting rule it does not state.
`ADR-0002` decision 5's amendment filed with `sb-2gdx` - "`use
StatifierBlocks.Composite` - a block type derived from params plus a pure
subtree" - declares a block type whose emission is not its own: a composite
answers `subtree/1` with a tree of other block types, and
`Composite.expand/2` is the one function that turns a composite block into
that tree. **Where** in the compile that expansion happens, and **who owns** a
finding raised inside it, are this record's to say, and this section says them.

### E1. A composite is replaced by its expansion at Resolve, and stages 3-6 run on the expanded tree unchanged

Stage 2 of the pipeline is Resolve, where every block goes through
`StatifierBlocks.Palette.resolve/2`
(`lib/statifier_blocks/compiler.ex:22-24`). A resolved node whose module is a
composite is **replaced, in place, by the subtree `Composite.expand/2`
returns**, and the replacement is complete before the stage ends. Config,
Structure, Emit and Chart then read a tree with no composite in it, and need
no knowledge that one was ever there.

Three consequences, and they are why this stage rather than a later one:

- **Decision 4 is untouched.** `emit/2` receives the block and context it
  receives today and returns the emission it returns today; nothing in its
  contract admits a composite. `emit_stage/3`
  (`lib/statifier_blocks/compiler.ex:1273`) and the `emit/2` beneath it
  (`:1413`) call the same callback on the same shape.
- **A composite's own `emit/2` is never reached.** It exists because
  `StatifierBlocks.BlockType` requires it and the declaration generates it,
  and it **raises** if it is called. That is the honest spelling of
  unreachable: a bug in the expansion becomes a crash at the site of the bug
  rather than silently wrong bytes six stages downstream, where decision 6's
  determinism guarantee would faithfully reproduce them.
- **Config and Structure see the members.** An expanded member's
  `validate_config/1`, its slot arity and its assignability are checked
  exactly as they would be had an author placed those blocks by hand. That is
  the property E3 exists to pay for: the block those stages name is a block
  the author cannot see.

The later alternatives were considered and are worse for this record's own
reasons. Expanding at Emit would put a second tree-shaped thing inside
`emit/2` and make decision 4's contract a lie. Expanding at Chart would leave
the provenance map to be built over a tree the serializer never saw. Resolve
is already the stage that turns a stored block into the module that will emit
it; a composite is the case where that answer is a subtree rather than a
single module.

### E2. State ids derive from the expanded blocks' ids, by decision 3 as it stands

No new id shape is introduced, and decision 3's function is unchanged. Each
expanded member is an ordinary `Block.t()` with an id minted by the
declaration, deterministically from the composite block's id and containing no
`__` (`ADR-0002`'s amendment filed with `sb-2gdx`), so decision 3 derives its
state id the way it derives every other one - `state_id(block_id) = "s_" <>
block_id`, with `Context.role_id/2` for anything a member mints below itself.

Decision 3's three properties hold without amendment. **Uniqueness**: the
composite block's id is document-unique under `ADR-0001` decision 3 and the
declaration's minting is injective over it, so the members' ids are
document-unique too, and they contain no `__`, so the role namespace stays
separate. **Invertibility**: `unstate_id/1` still inverts a generated state id
without consulting the map. **Totality**: every member is a block, so every
generated state still carries an id.

A compound id naming the composite and the member was rejected for decision
3's own reason. It would need a second separator distinguishable from `__`,
and it would write the composite's identity into SCXML that nothing reads. The
expansion is not visible in the chart, and it does not need to be.

### E3. Every span inside an expansion is owned by its expanded block, and the finding is reported one level up

Decision 5 stands as written: the map is total over the emission, and its
`owner` names the block whose emission the span came from. Inside an expansion
that block is the **expanded member**, never the composite. The map records
what was emitted, and what was emitted is the members.

Reporting is the other half, and it is where this amendment adds a rule.
Decision 9 maps a finding to its innermost owning span; decision 10 says every
finding names a block. A finding whose owner names an expanded member names a
block the author cannot see, cannot select and cannot edit - so it is
**re-anchored one level up before it is reported**. Decision 5's `owner` is the
map at `:586-590`, the prose triple at `:230` written out:

```elixir
@type owner :: %{
        block_id: Block.id(),
        role: String.t() | nil,
        config_key: String.t() | nil
      }
```

and re-anchoring is a rule about the two fields a reported finding takes from
it - `block_id` becomes the composite block's, and `config_key` becomes the
param's key or `nil`:

- **A finding with a param to blame is reported against the composite block,
  with that param's key.** Alongside the expanded blocks, `Composite.expand/2`
  returns a **param map**. Its shape is `ADR-0002`'s to declare and this
  record does not restate it: `ADR-0002`'s amendment filed with `sb-2gdx`
  owns the function's return, and what this record needs of the map is only
  that it answers, for a block inside the expansion, which composite param is
  to blame for what that block was given - or that none is. When the map names
  a param for the block a mapped finding's `owner` points at, the reported
  finding's `block_id` is the composite block's and its `config_key` is that
  param's key. `ADR-0005` decision 11 ("Findings are anchored, and the
  anchor decides where they render") then renders it on a
  `{:config, block_id, key}` anchor - inline beneath a field on the
  composite's own form, which is the one field the author typed into and the
  one field they can change.
- **A finding with no param to blame is reported against the composite block
  with `config_key: nil`.** This is decision 9's existing precedent applied
  unchanged rather than a new case: a structural finding is a bug in this
  package or in a host's block type rather than the author's doing, and its
  owning span already carries `config_key: nil` (`:411`). A finding inside an
  expansion that no param produced is that kind of finding from the author's
  side - there is nothing on their form to point at - so it renders on the
  composite block's chrome, and "this cannot be fixed here" is again the only
  honest message.
- **It is never reported against the expanded block.** There is no third arm.
  A finding the author cannot act on and cannot even locate is worse than no
  finding, and decision 10's promise that every finding names a block is only
  worth anything if the block it names is one the author holds.

**The expanded anchors survive, at the engineer's altitude.** Re-anchoring is
a rule about the reported finding, not a rewrite of the map. Every span is
still owned by the member that emitted it, so the Source tab, which reads the
generated SCXML against the map, still highlights the member's own span, and a
fixture run still names the member. The author's surface says which param is
wrong; the engineer's surface says which state, inside which expansion,
carries the bytes. Both are true at once, and decision 5's totality is what
makes the second one possible at all.

No typespec in "The contract as typespecs" moves. `owner` keeps the three
fields it has, and a re-anchored finding is an ordinary
`StatifierBlocks.Compiler.Finding` with the `block_id` and `config_key`
decision 10 already gives it.

### E4. The document hash is the stored document's, and expanding by hand moves no compiled byte

Decision 6's triple is `{document canonical bytes, palette, compiler version}`
and this amendment leaves all three where they are. A document holding a
composite block is an ordinary `ADR-0001` document - the composite block is
stored as `{type, id, config, slots}` and nothing else, the expansion is not
stored, and no member appears in it - so the document hash under `ADR-0001`
decision 8 is the hash of what the author wrote: the composite block, not its
members.

The second half is worth stating as an obligation rather than leaving to be
inferred from decision 6:

> The SCXML a document holding a composite block compiles to is
> **byte-identical** to the SCXML the same document compiles to after that
> composite has been expanded in place.

The provenance maps are equal too, but as a corollary rather than a second
obligation: the same members emit the same spans and own them by the same ids,
so decision 6's own pairing of byte-identical SCXML with an equal map holds
across the expansion for decision 6's own reason.

Expanding in place is the editor's Expand action, which `ADR-0005`'s amendment
filed with `sb-mjrt` ("Expand as one compound edit, how a composite card
draws, and Collapse recorded at proposed") records. It replaces the composite
block with the same members `Composite.expand/2` produces, in the stored
document this time. It moves the document hash, because the author changed the
document; it must move no compiled byte, because the compiler was already
compiling those members. That equality is what makes Expand a presentational
choice rather than a semantic one: an author who expands gets an editable tree
and the same chart, and a chart already identified under st-ADR-0052 is not
re-identified by the decision to expand.

This record states the obligation. `sb-qxyh` builds the expansion and carries
the test that proves it, per reference composite.

### Worked example: a bad invoke type on a "Guarded step"

`myapp.guarded_step` is a composite declaring two params, `condition` and
`invoke_type`. Its `subtree/1` answers a `core.branch` whose taken arm holds a
`core.invoke`, and the call's `invoke_type` config field is filled from the
composite's `invoke_type` param. The author types `myapp:capture` into the
composite's one visible field, and the host has registered no handler for it.

```
stored document
  blk_GS  myapp.guarded_step
          %{"condition" => "...", "invoke_type" => "myapp:capture"}

Resolve, through Composite.expand/2
  blk_GS_arm   core.branch
    └── blk_GS_call  core.invoke  %{"invoke_type" => "myapp:capture", ...}

  param map: %{"blk_GS_arm" => nil, "blk_GS_call" => "invoke_type"}
```

Stages 3-6 run over the two members. Decision 8's invoke lint fires on the
`<invoke>` the call emitted, decision 9 maps its span to the innermost owner -
`%{block_id: "blk_GS_call", role: nil, config_key: "invoke_type"}`, correctly,
because that member emitted the bytes. The param map names `invoke_type` for
`blk_GS_call`, so E3 re-anchors the finding before it is reported:

```elixir
compiled.warnings
#=> [%{block_id: "blk_GS", stage: :chart, severity: :warning, fault: :author,
#      config_key: "invoke_type",
#      code: :no_registered_invoke_handler,
#      message: ~s(no handler registered for invoke type "myapp:capture")}]
```

which is the shape at `:817` with a `config_key` and the composite's own id.
The editor draws the warning beneath the "Invoke type" field on the "Guarded
step" card, which is the field the author filled in.

Had the same lint fired on an `<invoke>` the declaration writes itself, with
no param feeding it, the param map would name none: the finding would
still carry `block_id: "blk_GS"` and would carry `config_key: nil`, and the
editor would draw it on the composite's chrome with nothing to point at,
because there is nothing on that form the author can change. The Source tab,
in both cases, still highlights the `<invoke>` inside `s_blk_GS_call`, because
the map was never rewritten.

### What this amendment does not change

Decision 4's `emit/2` contract, decision 6's determinism guarantee and its
one-way reading, decision 7's join between document identity and chart
identity, and decision 10's ordering and finding shape all stand exactly as
accepted. No stage is added to the pipeline and none is removed: Resolve does
one more thing, and the count stays six. Nothing here decides how a composite
exposes its members' reads and writes to `ADR-0011`'s environment walk, which
is a different record's question and is named here only so it is not read into
this one. Nothing here gives a composite a slot of its own, and nothing here
puts a marker on an expanded block: an expansion is recognised structurally,
and a document holding a composite is an `ADR-0001` document at
`schema_version` 1.

Filed with `sb-nzc1`, campaign SF037, recording campaign-SF037's rulings
`RQ-SF037-5` and `RQ-SF037-6`. `sb-qxyh` implements it, and `sb-v3ny` carries
the flip.

## Note (2026-09-07): the composite-expansion amendment is flipped to accepted, with three corrections by addition and one open question named

`sb-qxyh` landed on `main` at `6d17c78`, and this Note is a reading of `main`
at `0c39a3c`. Every claim the Amendment of this date at `:2848` makes was
checked against that code before its `Status:` line at `:2850` was flipped to
accepted. The section's own second sentence - "A decision record merges at
proposed under the campaign invariant; flipping it to accepted is a separate
gated request through the same `docs/adr/` gate, and `sb-v3ny` carries it"
(`:2851-2855`) - is falsified by the flip in the ordinary way a status sentence
is, and is met here rather than edited: `sb-v3ny` is that request, and this is
it. No text above this line is edited by this Note.

### 1. What the claims check out to

| The section says | At | Today on `main` | Verdict |
|---|---|---|---|
| Resolve is stage 2 and every block goes through `Palette.resolve/2` | `:2869-2871` | `compiler.ex:22-24`, and the stage-2 section opens at `compiler.ex:513` | holds |
| a resolved node whose module is a composite is replaced in place by `Composite.expand/2`'s subtree | `:2871-2873` | `compiler.ex:545-549` dispatches on `Composite.composite?/1`; `expand_node/3` at `:567-580` splices | holds |
| the replacement is complete before the stage ends, and stages 3-6 read a tree with no composite in it | `:2873-2875` | `resolve_member/3` (`compiler.ex:595-603`) re-enters `resolve/2` per member, so the splice is finished at the stage boundary; `after_resolve/5` (`:471-487`) has no composite arm | holds |
| decision 4 is untouched; `emit_stage/3` and the `emit/2` beneath it call the same callback on the same shape | `:2879-2883` | holds, but the two line cites do not: see correction 3 |
| a composite's own `emit/2` exists because the behaviour requires it, and raises if reached | `:2884-2887` | `composite.ex:249-256`, and it is not in the `defoverridable` list at `:258` | holds |
| Config and Structure see the members, checked as if an author had placed them | `:2890-2894` | `config_findings/2` (`compiler.ex:941-960`) and `structure_stage/3` (`:891-897`) run per resolved node; but see correction 4 | holds, narrowed |
| no new id shape: a member's id is minted deterministically from the composite block's id and contains no `__` | `:2906-2909` | `composite.ex:535-543` and `mint_id/3` at `:545-553`, which raises `ArgumentError` on a minted id containing the doubled separator | holds |
| `unstate_id/1` still inverts a generated state id without consulting the map | `:2917-2918` | `state_id.ex:125`, untouched by this work | holds |
| the provenance map records the expanded member, never the composite | `:2929-2931` | `reanchor/2` (`compiler.ex:713-721`) rewrites findings only; `test/statifier_blocks/compiler/composite_expansion_test.exs:288-296` asserts the minted member owns the span and the composite does not | holds |
| a finding raised inside an expansion is re-anchored before it is reported | `:2937` | `compile/3` calls `stages/3` then `in_document_order/2` (`compiler.ex:444-448`), and `reanchor(expansion)` is the last step of `stages/3` (`:461`); the ordering carries a sabotage test at `composite_expansion_test.exs:249-260` | holds, widened by correction 1 |
| decision 5's `owner` is a map of `block_id`, `role` and `config_key`, and it does not move | `:2938-2946`, `:2989-2992` | `provenance.ex:62-66`, field for field identical to the section's re-quote and to decision 5 at `:586-590` | holds |
| `block_id` becomes the composite's and `config_key` the param's key or `nil`; there is no third arm | `:2948-2950`, `:2975` | `reanchor_finding/2` (`compiler.ex:726-731`) has exactly two arms | holds |
| a finding with no param to blame is reported against the composite with `config_key: nil` | `:2970`, `:3069-3071` | `blamed_param/2` (`composite.ex:570-583`) answers `nil` for none and for two-or-more; `composite_expansion_test.exs:236-247` asserts both fields | holds |
| the compiled chart of a document holding a composite is byte-identical to the chart after Expand, and the provenance maps are equal | `:3007-3012` | `composite_expansion_test.exs:161-171` and `:187-198`, once per reference composite, asserting `scxml`, `provenance` and `invoke_types`; the editor half is `test/statifier_blocks/editor/composite_expand_test.exs:202-216` | holds |
| no stage is added or removed; the count stays six | `:3081-3082` | `compiler.ex:20-53` and `Finding.stage()` at `finding.ex:95` still name six | holds |
| nothing puts a marker on an expanded block, and the stored document stays an `ADR-0001` document at `schema_version` 1 | `:3085-3088` | `mint/3` rewrites `id` and `slots` only; the expansion index is a compiler-local `@typep` at `compiler.ex:523`, not a block field | holds |

Nothing in the section is falsified. The four corrections below are additions.

### 2. Correction 1: re-anchoring climbs to the outermost composite, not one level

`:2937` and the paragraph at `:2934-2937` say a finding raised inside an
expansion is re-anchored "one level up". For a composite whose members are
themselves ordinary blocks that is the whole story, and it was the only case
the section had in view. The code generalises it: `anchor/2`
(`compiler.ex:739-748`) recurses -
`anchor(expansion, composite_id) || {composite_id, config_key}` - so a finding
inside a nested expansion is anchored to the **outermost** composite, and it
carries **that** composite's param key rather than the inner one. `resolve/2`
recurses through `resolve_member/3` (`compiler.ex:595-603`) so nested
composites expand at all, and `Map.merge(member_expansion, expansion)` at
`:598` makes the outer entry win.

This is the section's own principle applied rather than a departure from it:
`:2977-2978` says the block a finding names must be one the author holds, and
the author of a document holding one composite holds that composite and no
block inside it, however deep the nesting goes. The wording at `:2937` is
narrow, not wrong, and it is widened here.

### 3. Correction 2: `:composite_expansion_failed` belongs in decision 10's table

Decision 10's stage table at `:445-451` lists, in its Resolve row (`:447`),
`:unknown_block_type` and `:block_type_too_new`. Resolve now also produces
`:composite_expansion_failed`, in exactly two cases, both raised as ordinary
`Compiler.Finding`s at stage `:resolve`:

1. `Composite.expand/2` raised - the declaration is broken, or a member's
   config cannot be built. `compiler.ex:610-620` rescues it and reports
   `{:composite_expansion_failed, block.id, why}` against the composite block.
2. the document **root** is a composite whose subtree answers other than one
   top-level block. `root_expansion_finding/2` (`compiler.ex:628-636`) reports
   `{:composite_expansion_failed, id, {:root_expansion_not_single, count}}`,
   because a document has exactly one root and there is nowhere to splice the
   rest.

The code atom is derived from the reason tuple's head by `Finding.code/1`
(`finding.ex:178-186`) rather than enumerated, and `finding.ex:16` already
carries it in that module's own stage table. The table at `:445-451` is left
standing and corrected here; the row is spelled `Resolve` there and `:resolve`
in `finding.ex`, which is a difference of table convention and not of stage.

### 4. Correction 3: two line cites in the decision-4 paragraph

`:2879-2883` cites `compiler.ex:1273` for `emit_stage/3` and `:1413` for the
`emit/2` beneath it. Today they are at `compiler.ex:1530` and `compiler.ex:1670`.
Both cites were already off when the section was written - at `6d17c78^` the
two functions were at `:1287` and `:1427` - so this is an authoring slip rather
than drift `sb-qxyh` caused, and `mix adr.cites` cannot see it because the
check guards citations into `docs/adr/`, not into `lib/`. The claim the
paragraph makes is unaffected: both functions still take a `Resolved.t()` and
call the same callback on the same shape.

### 5. Correction 4: what Structure is handed, and the one asymmetry

`:2890-2894` says an expanded member's `validate_config/1`, slot arity and
assignability are checked "exactly as they would be had an author placed those
blocks by hand". That is true of the members. It glosses one difference for the
blocks around them. `structure_document/3` (`compiler.ex:918-922`) hands
Structure a **rebuilt** `Document` only when `map_size(expansion) > 0`;
a composite-free document is passed through untouched. The rebuild
(`resolved_block/1`, `compiler.ex:929-934`) carries each block's **migrated**
config, so in a composite-bearing document Structure reads migrated config
where in a composite-free one it reads stored config. `compiler.ex:914-917`
records the choice and its reason. Nothing this record decides turns on it -
Structure asks about arity and assignability, not values - and the narrowing is
recorded here rather than left to be rediscovered.

### 6. `RQ-SF037-17` is named open, and this record does not decide it

`Composite.expand/2` does not stamp a member's `type_version`. `mint/3`
(`composite.ex:535-543`) rewrites `id` and `slots` and nothing else, so a member
carries whatever `subtree/1` gave it, which is `Block.new/2`'s default of `1`
(`block.ex:54`). That member then goes through `Palette.resolve/2` like any
block, which migrates against `current_version/0`
(`palette.ex:522-549`) - so a member whose type is at version 2 takes the
migration path on every compile, purely because the subtree author passed no
`type_version:`. The composite block itself is stamped correctly in the derived
recipe (`composite.ex:454-460`). `sb-qxyh` declined to stamp at Resolve to keep
the byte identity `:3007-3009` requires. Today the question is latent: every
shipped type answers `current_version/0` with 1. Where `expand/2` should get a
member's current version is `RQ-SF037-17`, queued 2026-09-07 for the SF038
walk. This Note names it and decides nothing.

Filed with `sb-v3ny`, campaign SF037. This Note changes no code and adds no
README row; it flips the `Status:` line at `:2850` and nothing else in this
file.

## Amendment (2026-09-07): a pass-through slot's children are spliced into the expansion with their ids unchanged, and a finding on one of them is that child's own

**Status: accepted (2026-09-07, campaign SF038, bead `sb-1700`, recording
campaign-SF038's ruling `RQ-SF038-5`).** A decision record merges at proposed
under the campaign invariant; flipping it to accepted is a separate gated
request through the same `docs/adr/` gate, and `sb-vjvq` carries it once
`sb-q183` has landed. Additive: decisions 3, 5, 6, 8, 9 and 10 stand as
accepted, the Amendment of this date at `:2848` stands as accepted, and no text
above this line is edited by this section.

An amendment rather than a Note, because the Amendment at `:2848` says twice
that a composite has no slot of its own - `:3085-3086`, "Nothing here gives a
composite a slot of its own" - and `RQ-SF038-5` gives it one. A **pass-through
slot** is a slot the author fills on the composite's own card, whose children
the expansion carries into a named slot of a named member. `ADR-0002`'s
amendment filed with `sb-nlo5` owns the declaration - the `slots:` option, the
`"slots"` key on a data declaration, the `name -> {local_id, inner_slot}`
mapping, what `slots/1` answers, and what `declaration/1` refuses - and this
record does not restate any of it. `ADR-0011`'s amendment filed with `sb-p01u`
owns where the environment walk descends. **Where** the children land in the
compile, **what ids** they carry there, **who owns** a finding raised on one of
them, and **what the compiled bytes must equal** are this record's to say, and
this section says them. `sb-q183` builds it.

### T1. The children are spliced into the mapped inner slot at Resolve, and the composite is still gone by the end of the stage

E1 (`:2867`) stands unchanged: at Resolve a resolved node whose module is a
composite is replaced, in place, by the subtree `Composite.expand/2` returns,
and the replacement is complete before the stage ends. A pass-through slot
changes what that subtree contains, not when the replacement happens.

For a composite block whose type declares a pass-through slot `name` mapped to
`{local_id, inner_slot}`, the subtree the splice puts in the composite's place
is `Composite.expand/2`'s subtree in which **the composite block's own children
under `name` sit in the `inner_slot` slot of the member minted from
`local_id`**. They are spliced there in their stored order, after nothing and
before nothing - the mapped inner slot holds them and only them, because a
declaration that mapped a slot the subtree also fills would be two authors
writing one list, and whether such a declaration is admissible at all is
`ADR-0002`'s question rather than this one's.

Everything E1 buys is bought again here. Config, Structure, Emit and Chart read
a tree with no composite in it and need no knowledge that one was ever there;
they also need no knowledge that part of that tree came from the author's own
hand rather than from the declaration. `emit/2`'s contract is untouched, the
composite's own `emit/2` is still unreachable and still raises, and Config and
Structure see a child exactly as they would have seen it had the author placed
it where the splice puts it - which, for a pass-through child, is the literal
truth rather than the useful fiction E1 had to argue for.

Three cases the splice does not change:

- **An unfilled pass-through slot splices nothing.** The mapped inner slot is
  empty, which is the arity Structure then checks against the member's own
  `slots/1`. A member that requires children and is handed none produces the
  member's ordinary arity finding, re-anchored by E3 onto the composite, and
  that is the right surface: the empty slot the author must fill is on the
  composite's card.
- **A pass-through child that is itself a composite expands here too.** The
  splice happens before `resolve/2` re-enters per member, so a composite the
  author dropped into a pass-through slot is expanded by the same recursion
  that expands a nested member, and T3 says where its findings land.
- **The root refusal is unchanged.** A composite at the document root whose
  subtree answers other than one top-level block is refused with
  `{:composite_expansion_failed, id, {:root_expansion_not_single, count}}`
  (Correction 2, `:3160-3161`) whether it declares a pass-through slot or
  not: the count is a count of the subtree's top-level blocks, and pass-through
  children land inside one of them.

### T2. A pass-through child keeps its stored id, and its state id is the one it would have had anyway

E2 (`:2904`) says a member's id is minted deterministically from the composite
block's id. A pass-through child is **not minted**. It keeps the id the stored
document gave it, unchanged, through the splice and through every stage after
it.

This is not an exception to E2 so much as the case E2 never reached. Minting
exists because a subtree writes stable local ids that are not document ids and
must be made into some; a pass-through child arrived as a document block with a
document id already. Rewriting it would be an invention, and an expensive one:
`ADR-0001` decision 3's ids are what a host's saved selections, a trace and a
provenance highlight are keyed by, and the whole point of T4 is that moving a
child into the expansion moves nothing.

Decision 3 (`:122-126`) then derives the child's state id the way it derives
every other one - `state_id(block_id) = "s_" <> block_id`, with
`Context.role_id/2` for anything the child mints below itself - and its three
properties hold for the ordinary reason rather than a new one. **Uniqueness**:
the child's id is document-unique under `ADR-0001` decision 3, and it is
document-unique in the expanded tree too, because the splice moves it and does
not copy it. **Invertibility**: `unstate_id/1` inverts its state id, and the
child's id carries no `__` because no id in a stored document does.
**Totality**: the child is a block, so every state it generates carries an id.

One consequence is worth naming because it is the thing a reader will look for:
**a pass-through child's ids do not mention the composite**, where a minted
member's do. Two blocks that sit side by side in the expanded tree therefore
carry ids of two different shapes. That is correct and deliberate. The shape of
an id records where the id came from, and these came from two different places:
one from the declaration, one from the author.

### T3. A finding on a pass-through child is reported against that child

E3 (`:2926`) re-anchors a finding raised inside an expansion onto the composite
block, and Correction 1 (`:3129`) climbs to the outermost composite. Neither
applies to a pass-through child. **A finding whose owner is a pass-through
child, or any block below one, is reported against that block, with that
block's own `config_key`, exactly as it would be if no composite were in the
document.**

E3's argument is what decides this, applied rather than set aside. E3
re-anchors because a finding naming an expanded member "names a block the
author cannot see, cannot select and cannot edit" (`:2934-2937`, `:2977-2978`).
A pass-through child fails every clause of that test: the author placed it, it
is drawn on the composite's card, in the interior that `ADR-0005`'s `7E`
(`:8601`) and its campaign-SF038 amendment give the declared slot, they can
select it, and they can edit its fields. Re-anchoring it onto the composite
would take a finding the author can act on directly and point it at a form
that has no field for it - the exact harm E3's third bullet ("It is never
reported against the expanded block", `:2975`) exists to prevent, in the
other direction.

The mechanism is a single rule about the expansion index, and it is this
record's to state because the index is what E3's re-anchoring reads:

> The expansion index maps **expansion members only**. A pass-through child,
> and every block below it that the author placed, has no entry in it.

`anchor/2` (`:3134-3135`) therefore finds nothing for such a block and returns
it unchanged, and the two arms of E3 stay the two arms they are - no third arm
is added here either. Three readings follow:

- **A pass-through child that is itself a composite anchors its own members
  onto itself.** The climb from one of that composite's minted members reaches
  the child and stops, because the child has no entry. That is Correction 1's
  own principle: the climb ends at the outermost block the author holds, and
  here the author holds the child.
- **A finding on a member that the child's presence caused is still the
  member's, and so still the composite's.** If the declaration's own member
  raises a finding because of what it was handed, E3 re-anchors it onto the
  composite with the param map's key or `nil`. The pass-through slot is not a
  param and the param map does not name it; a structural finding of this kind
  lands on the composite's chrome with `config_key: nil`, which is E3's second
  arm unchanged.
- **The provenance map is untouched, as before.** Decision 5's `owner` names
  the block whose emission the span came from; for bytes a pass-through child
  emitted, that is the child, and the child's own id is what the Source tab
  highlights. Here the author's surface and the engineer's surface name the
  same block, where inside a minted expansion they name two.

No typespec moves. A finding reported against a pass-through child is an
ordinary `StatifierBlocks.Compiler.Finding` with the `block_id` and
`config_key` decision 10 already gives it.

### T4. The compiled bytes are the same before and after Expand, and here the findings are too

E4 (`:2994`) states the obligation that a document holding a composite compiles
byte-identically to the same document after that composite has been expanded in
place. That obligation extends to this case without weakening, and it is stated
here rather than left to be inferred:

> The SCXML a document holding a composite block with a filled pass-through
> slot compiles to is **byte-identical** to the SCXML the same document
> compiles to after that composite has been expanded in place, with the slot's
> children moved into the mapped inner slot and their ids unchanged.

The provenance maps are equal too, for E4's own reason: the same blocks emit
the same spans and own them by the same ids on both sides, and T2 is what makes
that true of the children - an id that was rewritten by the move would move
every state id below it and the equality would be a coincidence rather than a
consequence.

This case adds one equality E4 could not claim. **The findings reported on a
pass-through child are equal on both sides as well.** Before the Expand the
child sits in the expansion and is not re-anchored, because T3 keeps it out of
the index; after the Expand there is no expansion and nothing to re-anchor. E4
had no such claim to make about a minted member, whose findings are re-anchored
before the Expand and are the member's own after it - that difference is the
honest price of Expand and E4 names it. For the children the author placed,
Expand changes nothing they see at all: the same warning, on the same block,
under the same field.

This record states the obligation. `sb-q183` builds the splice and carries the
test that proves it, per reference composite, alongside the tests E4's
obligation already has.

### Worked example: a bad invoke type on a child inside a "Guarded section"

`myapp.guarded_section` is a composite declaring one param, `condition`, and
one pass-through slot, `body`, mapped to `{"guard", "taken"}`. Its `subtree/1`
answers a single `core.branch` with the local id `guard`, whose `taken` slot
the declaration leaves empty. The author fills the composite's one visible
field, drops a `core.invoke` into the interior the card draws for `body`, and
types `myapp:signup` into it - for which the host has registered no handler.

```
stored document
  blk_GX  myapp.guarded_section
          %{"condition" => "..."}
          slots: %{"body" => [
            blk_CALL  core.invoke  %{"invoke_type" => "myapp:signup", ...}
          ]}

Resolve, through Composite.expand/2
  blk_GX_guard   core.branch
    taken:
      blk_CALL   core.invoke  %{"invoke_type" => "myapp:signup", ...}

  expansion index: %{"blk_GX_guard" => {"blk_GX", nil}}
```

`blk_CALL` is absent from the index, and its id is the one the author's
document already carried. Stages 3-6 run over the branch and the call. Decision
8's invoke lint fires on the `<invoke>` the call emitted, decision 9 maps its
span to the innermost owner - `%{block_id: "blk_CALL", role: nil, config_key:
"invoke_type"}` - and T3 leaves it there:

```elixir
compiled.warnings
#=> [%{block_id: "blk_CALL", stage: :chart, severity: :warning, fault: :author,
#      config_key: "invoke_type",
#      code: :no_registered_invoke_handler,
#      message: ~s(no handler registered for invoke type "myapp:signup")}]
```

The editor draws the warning beneath the "Invoke type" field on the call's own
card, inside the "Guarded section" interior, which is the field the author
typed into. Compare the "Guarded step" example at `:3030`, where the same lint
on a member the declaration wrote is re-anchored onto the composite and drawn
on the composite's form: the two examples differ in exactly one thing, which is
who put the bad value there.

Had the branch itself raised a structural finding - an arity refusal because
the author left `body` empty and `core.branch` requires a taken arm - the
finding's owner would be `blk_GX_guard`, which the index does name, so E3 would
re-anchor it onto `blk_GX` with `config_key: nil` and the editor would draw it
on the composite's chrome. That is T3's second reading, and it is the right
surface: the empty slot is on the composite's card.

And after an Expand, both readings are unchanged in the first case and changed
in the ordinary way in the second: `blk_CALL` still carries its own warning
under its own field, while the branch's arity finding becomes the branch's own,
because there is no longer a composite to climb to.

### What this amendment does not change

Decision 3's function, decision 4's `emit/2` contract, decision 5's totality
and its `owner` shape, decision 6's determinism guarantee, decision 7's join
between document identity and chart identity, and decision 10's ordering and
finding shape all stand exactly as accepted. E1's stage count is unchanged:
Resolve still does one more thing than it did before `sb-nzc1`, and the count
is still six. Correction 1's climb to the outermost composite stands and is
narrowed by nothing here - T3 says where the climb starts, not how far it goes.
Nothing here decides the declaration's shape, which is `ADR-0002`'s, or where
the environment walk descends, which is `ADR-0011`'s, or how the card draws the
interior, which is `ADR-0005`'s; each is named so it is not read into this one.
A document holding a composite with a filled pass-through slot is an ordinary
`ADR-0001` document at `schema_version` 1: the children are stored under the
composite block's own `slots`, which is where `ADR-0001` decision 2
(`:63`) and decision 5 (`:110`) already put every block's children, and nothing
about the expansion is stored.

Filed with `sb-1700`, campaign SF038, recording campaign-SF038's ruling
`RQ-SF038-5`. `sb-q183` implements it, and `sb-vjvq` carries the flip.

## Note (2026-09-07): the pass-through splice amendment is flipped to accepted, and its cites re-counted

The Amendment of 2026-09-07 *a pass-through slot's children are spliced into
the expansion with their ids unchanged* (`:3217`) is flipped to **accepted**.
Its status line at `:3219` is the one word this request changed in this file;
no other line of the section, and no line above it, is edited. `sb-q183`
(PR 422, `main` `e61890a`) built `T1` to `T4`.

Read at `main` `d6fb241`.

### 1. The sentences the flip falsifies, met here rather than edited

- `:3222-3224`, "flipping it to accepted is a separate gated request through
  the same `docs/adr/` gate, and `sb-vjvq` carries it once `sb-q183` has
  landed". Performed rather than pending; the sentence stands.
- `:3398-3399`, "`sb-q183` builds the splice and carries the test that proves
  it". It did.
- `:3477-3479`, "`sb-q183` implements it, and `sb-vjvq` carries the flip". Both
  performed.
- `:3085-3086`, in the Amendment at `:2848`: "Nothing here gives a composite a
  slot of its own". Still true **of that section**, which is what it says; the
  slot is given by this section and by `ADR-0002`'s pass-through amendment.
  That sentence is the reason this one is an amendment rather than a Note, and
  it is unedited.

### 2. What the code answers, per clause, at `d6fb241`

| Clause | Where it is |
|---|---|
| `T1`, the splice at Resolve into the mapped inner slot, in stored order | `composite.ex:880-906`: `splice/3` folds the declared slots and `put_children/4` writes the children into the member minted from the local id, replacing that slot's list, so the mapped inner slot "holds them and only them". An unfilled slot splices nothing (`:884-889`, the `[] -> acc` arm) |
| `T2`, the children keep their stored ids | the spliced children are placed **outside** `mint/3`'s walk (`composite.ex:910-918`), which recurses only over `subtree/1`'s own blocks and their slot children. Nothing rewrites a spliced child's id |
| `T3`, a finding on a pass-through child is that child's own | `composite.ex:463-468`: the param map - which is what the compiler builds the expansion index from - is taken over the minted members **before** the children are spliced in, so a pass-through child has no entry in it and `anchor/2` returns it unchanged. The comment at `:463-467` cites this section by name |
| `T4`, the compiled bytes are equal before and after Expand | the equality `sb-q183` carries the test for; `expand/2` (`composite.ex:441-470`) is the one expansion function the compiler and the Expand gesture both read, which is what makes the two sides the same tree |

`T3`'s stated mechanism - "The expansion index maps **expansion members only**"
- is the code's mechanism verbatim, and it is worth recording that it is
implemented by **where** `param_map/2` is called rather than by a filter over
the index: there is no code that removes a pass-through child from the index,
because none is ever added.

### 3. Cites re-counted at `d6fb241`

Every cite this section makes into this file resolves unchanged: `:122-126`,
`:2848`, `:2867`, `:2904`, `:2926`, `:2934-2937`, `:2975`, `:2977-2978`,
`:2994`, `:3030`, `:3085-3086`, `:3129`, `:3134-3135`, `:3160-3161`. So do its
cites into `ADR-0001` (`:63`, `:110`) and `ADR-0005` (`:8601`); appends land at
the end of each file, so no line above moved, and `mix adr.cites` is green over
this request.

This section cites no line of `lib/`, so there is no code cite to re-count.
The functions it describes, for a later reader, are at `composite.ex:441`
(`expand/2`), `:880` (`splice/3`), `:893` (`put_children/4`), `:910` (`mint/3`)
and `:468` (the `param_map/2` call `T3` rests on).

Filed with `sb-vjvq`, campaign SF038.

## Note (2026-09-12): `emit/2`'s return type does not widen; a non-SCXML target is a separate optional callback, named and not built

RQ-SF041-2, ruled by the operator on 2026-09-12, answers the record question
the SF040 element-editor spike raised against **decision 4** at `:169`. This
section records the ruling. It changes no decision, edits no line above it,
and nothing in `lib/` changes with it.

Read at `main` `d9f4896`.

### 1. The question, and where it came from

`docs/spikes/SF040-element-editor.md` **section 4, "Ask R"** (`:427`) states
the question: *should a block type be able to emit for a non-SCXML target, and
if so by what shape?* It offers two candidates - widen `emit/2`'s return, or
add a separate optional callback - and prefers the second. Section 3's
recommendation (`:365`) is the half that rules on the editor and defers the
seam: its part (b) says the in-compiler emit "turns on a record decision" and
should not be taken until SF041 rules it.

The spike is correct that the narrowing is this record's. Read at `d9f4896`:

- **decision 4** (`:169`) fixes
  `{:ok, Emission.t()} | {:error, [finding()]}` and glosses `Emission.t()` as
  "a structural representation of one SCXML subtree" (`:194`);
- `ADR-0002` types the same callback loosely -
  `@callback emit(Block.t(), context :: term()) :: {:ok, term()} | {:error, term()}`
  at `docs/adr/0002-block-type-behaviour.md:481` - and delegates the signature
  here in terms (`:385`, "The compiler and provenance map (sb-iwz) own
  `emit/2`'s signature"), with its own row note at `:123`;
- the shipped behaviour matches this record, not `ADR-0002`'s loose gloss:
  `lib/statifier_blocks/block_type.ex:505-506` at `d9f4896` types the callback
  `@callback emit(Block.t(), StatifierBlocks.Compiler.Context.t()) :: {:ok,
  StatifierBlocks.Emission.t()} | {:error, emit_error()}`, with `:501` saying
  "The return is structural, never a string".

### 2. The ruling

1. **`emit/2`'s return type does not widen.** Decision 4's sentence stands as
   written. A `map()` arm would not narrow that sentence, it would replace it:
   a type answering `{:ok, %{}}` would pass the callback's own spec and fail
   downstream in the SCXML pass with no finding naming the cause, and a widened
   return cannot let one block type serve two targets at once.
2. **A non-SCXML target, when it is wanted, is a SEPARATE optional callback.**
   Its name is `emit_node/2`. It answers **one** node of the target document -
   not a subtree, not a document - and it carries the **same provenance tuple**
   decision 5 fixes at `:230`, `{block_id, role_or_nil, config_key_or_nil}`, so
   that a finding over a non-SCXML artifact routes by the map this record
   already specifies rather than by a second, parallel one. It is **optional**,
   and a block type that declares neither callback is refused at Resolve rather
   than at Emit - which is where `ADR-0002` decision 3 (`:86`, "Resolution is
   total and returns typed errors") already puts a resolution failure, as an
   ordinary typed arm rather than a raise. That refusal point is carried from
   the spike's candidate 2 as the operator adopted it
   (`docs/spikes/SF040-element-editor.md:467-468`, "a type that declares
   neither is refused at resolve rather than at emit"); it is recorded here as
   part of the adopted shape, not decided here, and a later request building
   the callback may find it wants a different point and say so. Being a
   callback on the block-type behaviour, it is **`ADR-0002`'s to declare**, and
   it is declared there when it is built, not here and not now.
   (The spike's candidate 2 spells the same shape `emit_json/2`, "or an
   emitter-keyed callback", at `docs/spikes/SF040-element-editor.md:465`. The
   ruled name is `emit_node/2`, and the difference is the name only: one node,
   not one subtree, is the part the name is carrying.)
3. **The emit seam stays as it is.** No function on the SCXML path changes
   shape for this. At `d9f4896`: `emit_stage/3` at
   `lib/statifier_blocks/compiler.ex:1658`, the private `emit/2` at `:1798`,
   and `chart_stage/5` at `:2503` each assume an SCXML emission, and each is
   correct to. A second target arrives beside them, never through them.
4. **The interim route is a host walk.** Until such a callback is built, a host
   that wants a non-SCXML artifact walks `Document.blocks/1` plus
   `committed_config/2` itself. That is the route the spike measured, at "under
   about 120 lines with zero package change and zero record cost"
   (`docs/spikes/SF040-element-editor.md:390`), and it is the answer for anyone
   asking today.

### 3. What is NOT built

`emit_node/2` is **not built in this campaign** and no bead carries it. There
is no `emit_node` in this repository at `d9f4896`: `grep -rn emit_node lib/
docs/ test/` answers nothing, and this section is the first text in the
repository to use the name. It is named here so that a later request has a
fixed shape to build to and a fixed record to amend - `ADR-0002` for the
declaration, this record for the provenance tuple it must carry - rather than
re-deriving the question. Whoever takes it should read section 3(c) of the
spike first: the spike's own conclusion is that the blocking work under either
answer is the element vocabulary, which is larger than either seam and
independent of this ruling.

### 4. Cites

Cites into this file: `:169` (decision 4), `:194`, `:230` (decision 5's owner
tuple). Cites into `ADR-0002`: `:86` (decision 3), `:123`, `:385`, `:481`. Code
cites, all read at `main` `d9f4896` and re-verified by anchor:
`block_type.ex:501`, `:505-506`; `compiler.ex:1658`, `:1798`, `:2503`. Spike
cites, read at `d9f4896`: `docs/spikes/SF040-element-editor.md:365`, `:390`,
`:427`, `:465`, `:467-468`. This section appends at the end of the file, so no
line above it moved.

Filed with `sb-xbn9`, campaign SF041.

## Note (2026-09-12): the reserved failure-seam key is renamed to `statifier_persistence:execution_status`, and the name it replaces stays reserved

Premise surface: `statifier_persistence`'s `ADR-0011: execution is the durable
noun` (**proposed**, campaign SF041, on `statifier_persistence` `main` at
`84ba7cf`), decision 4. That record owns the key - this one owns where the
compiler mints it - and decision 4 renames it. This Note records the rename
against every place this file names the old spelling; no line above it moves.

### 1. What the key is now

- The reserved `<donedata>` `<param>` the compiler mints on a failure-classed
  final is named **`statifier_persistence:execution_status`**. Its value
  vocabulary is unchanged: `'failed'`, one closed value.
- `statifier_persistence` **0.12.0 reads both keys for one release** - the new
  key wins where both are present, and reading the old one logs a deprecation
  line - and **0.13.0 reads only the new key**. `statifier_persistence >= 0.12`
  is therefore the floor for a durable host running charts this package
  compiles from now on.
- Nothing else about the failure seam moves. The mechanism this file's C1
  amendment of 2026-09-06 and its 2026-09-06 flip Note describe - which finals
  carry the param, that it is minted second and only on a failure-classed
  outcome, and that the params serialize in the order they are built - is
  exactly as recorded. Only the name of the key changes.

### 2. Where this file names the old spelling

Every mention below is read at `main` `e990ad7` and is to be read as naming
`statifier_persistence:execution_status` from this Note on. None of them is
edited; this Note is the correction.

`:2475` (the worked `<donedata>` block), `:2541` (the C1 amendment's sentence
on what a failure-classed final carries), `:2609` (item 2 of the two
compiler-minted params), `:2647` (the reserved-name sentence), `:2815` (the
ordering rule: the reserved param second), `:2832` (the refusal's wording).

The same is true of the two other records in this repository that name the old
spelling, which this Note reaches rather than edits: `ADR-0002`
(`0002-block-type-behaviour.md:3868`, `:4499`, `:4703`, `:4906`, @`e990ad7`)
and `ADR-0013` (`0013-typed-fan-out-child-summary.md:71-73`, `:209`, `:258`,
`:519`, `:665`, `:975`, `:1080-1081`, @`e990ad7`). `ADR-0013`'s cite table at
`:1080-1081` points at compiler.ex line numbers that predate this request; it
is historical and is left as it is, as this repository's ADR-cite ruling of
2026-09-07 says merged records are.

### 3. Both names are reserved, and why

A `donedata_type/1` entry may declare neither `statifier_persistence:execution_status`
nor the `statifier_persistence:run_status` it replaces. The second half is new
here and is not something decision 4 states: it follows from decision 4's own
transitional reader. For as long as `statifier_persistence` 0.12 reads the old
key, a host type that hand-declared that name would emit a `<param>` a durable
stepper reads as the execution's status, beside - and possibly disagreeing
with - the one the compiler mints. Refusing the name costs nothing (no shipped
type declares it) and removes the collision for the one release it can happen
in. When `statifier_persistence` 0.13.0 drops the transitional reader the
reservation may be dropped with it; that is a later request's call and this
Note does not pre-decide it.

One correction to how C1's refusal is described, found while proving the test
for this: **neither status key was ever reachable through the reserved-name
list**. `declarable_param?/1` refuses on `Config.identifier?/1` first, and a
namespaced name - anything carrying a `:` - is not a bare lowercase identifier,
so both keys are refused on shape whichever list they are on. Dropping either
from the list leaves every refusal green. What the list actually buys is the
**finding message**: it names the collision the author walked into rather than
reporting only that the shape is wrong. That is worth keeping and is why both
names stay on it, but this file's sentences at `:2647` and `:2832`, and
`ADR-0013`'s at `:209`, should be read as describing an over-determined
refusal, not the only lock on the name. The test that cashes this asserts the
message phrase rather than the finding code, because asserting the code alone
passes on the shape check and proves nothing about the reservation.

### 4. Cites

Cites into this file: `:2475`, `:2541`, `:2609`, `:2647`, `:2815`, `:2832`, all
@`e990ad7`. Code cites, read in the tree of the request this Note lands in and
re-verified by anchor; the spelling `@... @e990ad7` gives the line the same
anchor had on `main` before this request moved it:

- `@execution_status_key "statifier_persistence:execution_status"` at
  `lib/statifier_blocks/compiler.ex:361` (was `@run_status_key` at `:360`
  @`e990ad7`)
- `@legacy_execution_status_key` at `compiler.ex:374` (new in this request)
- `execution_status_param/0` at `compiler.ex:2292` (was `run_status_param/0`
  at `:2277` @`e990ad7`)
- the reserved-name check `declarable_param?/1` at `compiler.ex:2496-2498`
  (was `:2481-2483` @`e990ad7`) and its finding message at `:2506-2509` (was `:2490-2492` @`e990ad7`)

This section appends at the end of the file, so no line above it moved.

Filed with `sb-hykt`, campaign SF041.
