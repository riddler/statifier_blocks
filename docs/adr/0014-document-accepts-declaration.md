# ADR-0014: A document declares the external events it accepts - a list of names on the envelope, carried through compile, and judged against the chart by the engine's check at publish

Status: accepted (2026-09-22, drafted for `sb-mgei` under the operator's
campaign consent). It merges at proposed; flipping it to accepted is a
separate request through the same `docs/adr/` gate, after the code that
builds it has landed.

Code cites below were read at `aa657cd` and carry their anchors; re-locate
by anchor, not by number.

## Context

**A composite already declares how it can finish, and nothing declares what
a document will listen to.** ADR-0002's amendment of 2026-09-12 gave a
composite an optional `outcomes` key, a list of names that replaces the
derived list, and made the compiler check every declared name against what
the expansion can raise (that amendment's `C1` and `C2`); its amendment of
2026-09-18 read the same list per instance (`C9`, `C9b`). The check is
`StatifierBlocks.Composite.unraisable_outcomes/5`
(`lib/statifier_blocks/composite.ex:993`, `def unraisable_outcomes`). An
outcome is what a piece of a document says to the thing around it. Its twin
is the other direction: the events the thing around a document may send into
it. That half has no declaration anywhere in this package. The envelope is
`%StatifierBlocks.Document{id, root, schema_version, revision, metadata,
datamodel}` (`lib/statifier_blocks/document.ex:62`, the `defstruct`), and
the only list on it is the `datamodel` roots of ADR-0001 decision 11.

**A host that routes external events into executions needs that list, and
today it can only guess it.** A document's chart listens to whatever its
transitions name. Some of those names are meant to arrive from outside - a
patron registration waits for the host to say the visitor's email address
was verified - and some are the chart talking to itself: a `core.send` to
self, a clock interrupt's delayed event (ADR-0010), the `done.state`
completion events the compiler wires its own sequencing on, which the
interpreter raises when a state enters its `<final>` (ADR-0004 decision 2).
From the
chart alone the two kinds look the same. An author who means "this document
accepts `email.verified` from outside, and nothing else" has nowhere to say
it, so a host that binds external sources to documents cannot tell a typo in
a binding from an event the document never meant to expose.

**The engine is gaining the measure; this package supplies the claim.** The
engine is specifying `Statifier.Chart.events/1`, the computed event
vocabulary of a chart - every event descriptor on a transition from a state
that can be active, patterns kept as patterns - and
`Statifier.Chart.check_accepts/2`, which judges a declared name list against
that vocabulary. Both are pure functions a host calls, outside
`Statifier.Validator`, for the reason statifier-ex's
`docs/adr/0069-host-registered-send-types.md` gives in its decision 3 for
the send-type check: a check against deployment state is not a spec check,
and `validate/3` takes no deployment state. This record cites those two
functions by name. What they compute is the engine's to decide; this record
decides where a block document keeps its declaration, how it survives the
compile, and what a block author and a host may rely on.

**The shape of the rule is one this package already follows.** ADR-0004
decision 8 surfaced invoke types as data on `%Compiled{}` so that "the host
comparing `invoke_types` against its registration at deploy time" is a
one-liner, and refused to make the mismatch a compile error because the
compiler cannot know deployment state. A declaration of accepted events is
the same kind of thing: the compile carries it, the host's publish step
judges it, and the runtime's behaviour on an unhandled event stays the
backstop.

## Decision

**1. A document declares the external events it accepts, as a list of event
names, and payload shape is reserved.** The declaration is the twin of a
composite's declared outcomes: outcomes say how a piece of a document can
finish towards what encloses it, and `accepts` says which events what
encloses the whole document may send into it. Each entry is an event
**name** - `email.verified`, not a descriptor, not a pattern the author
intends to be expanded - and nothing else in this slice. A later slice may
give an entry a payload shape; it decides its own encoding then, and this
record promises nothing about that encoding beyond decision 2's refusal of a
non-string entry, which is what makes a reader that predates it refuse
rather than misread it.

**2. The declaration is an optional top-level envelope key, `accepts`,
beside `datamodel`, and `schema_version` stays at 1.**

- **The key.** `accepts` is a JSON list of strings, in the author's order.
  On the struct it is `accepts: [String.t()]`, defaulting to `[]`, the same
  shape and default `datamodel` has on the `defstruct`
  (`lib/statifier_blocks/document.ex:62`). Order is kept as written and is
  not sorted; reordering the list is an edit like any other.
- **The canonical bytes.** An empty `accepts` is omitted from the canonical
  encoding, by the same "empty is omitted" rule `datamodel` uses
  (`lib/statifier_blocks/canonical_json.ex:117-119`, `defp
  maybe_put_list/3`, called for `datamodel` in `encode/1` at `:42`). So an
  absent or empty `accepts` leaves every existing document's bytes, and
  therefore its `content_hash/1`, unchanged. A non-empty `accepts` is in the
  bytes and in the hash, exactly as ADR-0001 11d puts `datamodel` there.
- **No bump.** ADR-0001 decision 7 bumps `schema_version` "only when this
  record is amended in a way that changes bytes", and ADR-0001 11e applied
  that criterion to `datamodel` and took no bump. The same reading holds
  here: no document encoded before this key exists changes a byte, so there
  is no bump to take. This record follows that precedent rather than
  re-arguing it.
- **The envelope allowlist gains the key.** The decoder refuses any
  envelope key it does not list (`lib/statifier_blocks/decode.ex:51`,
  `@envelope_keys`, enforced by `defp ensure_known_envelope_keys/1` at
  `:106-111`), so a 0.32.0 reader refuses a document carrying `accepts` with
  `{:malformed_envelope, {:unexpected_key, "accepts"}}`. That is ADR-0001
  11e's safety property working as intended: an old reader refuses loudly
  rather than dropping the declaration on the next encode. `accepts` joins
  `@envelope_keys`, and "no bump" stays a safety property for this key for
  the reason 11e gave for its own.
- **What `Document.validate/1` refuses.** `validate/1` keeps its return
  shape, `:ok | {:error, validation_error()}`
  (`lib/statifier_blocks/document.ex:254-255`), and a malformed `accepts`
  is a `{:malformed_envelope, _}` in the family `datamodel` already uses
  (`lib/statifier_blocks/validation.ex:124-132`, `defp check_datamodel/1`,
  and the duplicate arm in `defp check_datamodel_unique_ids/1` at
  `:190-195`). Four refusals, each reported for the first entry at fault:
  - not a list: `{:malformed_envelope, {:accepts, :not_a_list}}`;
  - an entry that is not a string: `{:malformed_envelope, {:accepts,
    {:entry, index, :not_a_string}}}`;
  - an empty string: `{:malformed_envelope, {:accepts, {:entry, index,
    :empty}}}`;
  - a name already in the list: `{:malformed_envelope, {:accepts,
    {:duplicate_name, name}}}`.

  `validation_error()` is not widened: every one of these is an arm of the
  existing `{:malformed_envelope, term()}`. The compiler's document stage
  already reports any `validate/1` refusal as its `{:invalid_document,
  reason}` finding (`lib/statifier_blocks/compiler.ex:543-544`, `defp
  document_stage/1`), so a malformed `accepts` fails the compile there with
  no new finding shape. The decoder passes a non-list value, and a
  non-string entry, through to `validate/1` unchanged, as it does for
  `datamodel`, so the refusal has one implementation.

**3. The compile carries the declaration onto `%Compiled{}` and
`%CompilationRecord{}`, and it never enters the chart.** Both structs gain
`accepts: [String.t()]`, defaulting to `[]`, holding the document's list
exactly as written (`lib/statifier_blocks/compiled.ex:46` and
`lib/statifier_blocks/compilation_record.ex:73-80`, the two `defstruct`s).
A host that holds the emitted chart reads the declaration beside it, and a
host that stores only the record reads it beside the record, without
re-reading the document.

Nothing about the declaration is emitted into the SCXML. The chart's bytes
are the same with and without it, so chart identity (ADR-0004 decision 7)
does not move when an author edits `accepts`, and a running execution's
resume is not disturbed by the edit - the same property ADR-0004 decision 7
gives a `metadata` edit. The document hash does move, because the key is in
the document's bytes (decision 2). The carry is a pass-through: the compile
reads nothing from `accepts`, judges nothing about it, and produces no
finding from it.

**4. The consistency rule: a declared name no reachable transition can take
refuses the publish; a reachable event nobody declared is internal.**

- **Declared but unreachable is a publish error.** A declared name that no
  event descriptor in the chart's computed vocabulary matches - the
  vocabulary `Statifier.Chart.events/1` computes over the emitted chart, from
  the states that can be active - names an event the document would accept
  and then ignore. The host's publish step refuses it. Matching is the
  engine's descriptor matching, so a declared `email.verified` is matched by
  a transition on `email.verified`, on `email`, or on `*`.
- **Reachable but undeclared is internal.** A descriptor the chart can take
  that no declared name matches is the document's own business: it is not
  bindable from outside, and no external sender may name it. It is not an
  error. The `done.state` descriptors the compiler wires its sequencing
  on, and a clock interrupt's delayed event, land here, which is where they
  belong.
- **Who judges it.** `Statifier.Chart.check_accepts/2`, the engine's pure
  function, over the machine compiled from `%Compiled{}`'s SCXML and the
  carried list. This package adds no check of its own for this rule and
  puts nothing in `Statifier.Validator`. The compile does not run the check,
  for ADR-0004 decision 8's reason: whether a declaration is acceptable is
  a question about the chart a deployment will start, asked where the host
  knows it will start it, and a compile that answered it would make an
  engine function a precondition of authoring.
- **What "can be active" means** is the engine's: this record takes the
  vocabulary `events/1` answers as the measure and adds no reachability
  analysis of its own over blocks.

**5. With no declaration, the computed set is the contract.** A document
whose `accepts` is absent or empty declares nothing, and for it the
vocabulary `Statifier.Chart.events/1` computes over the emitted chart is the
set of events it accepts. A host that wants the stricter reading - only
what the author named - requires a declaration before it publishes.

An empty list and an absent key are the same declaration. They encode to the
same bytes (decision 2), so they cannot mean different things, and "this
document accepts no external events at all" is not something this slice lets
an author say. That is the reading ADR-0002's `C1` and `C9b` already take for
an empty outcomes list, for the same reason. The carry reflects it: `[]` on
`%Compiled{}` and `%CompilationRecord{}` means "no declaration", and a host
passes the engine's no-declaration form to `check_accepts/2` when it reads
one.

**6. The editor surface is a row of the declarations panel, written through
its own command.** The datamodel roots are authored in the declarations
panel, `StatifierBlocks.Editor.Declarations.declarations/1`
(`lib/statifier_blocks/editor/declarations.ex:108`), over the pure list
helpers in `StatifierBlocks.Declarations`, and saved through
`{:set_datamodel, entries}` (`lib/statifier_blocks/edit.ex:198-202`, the
`apply/2` clause), the command ADR-0005's amendment of 2026-09-01 added as
its 2g. `accepts` is authored the same way:

- **A sibling command, `{:set_accepts, [String.t()]}`.** It replaces the
  document's whole `accepts` list, and its inverse is `{:set_accepts,
  previous}` - 2g's argument for one whole-list command over per-entry
  insert, remove and move carries over unchanged, and decision 3's
  inverse law holds by construction. It is a command rather than editor
  state by 2g's own test: the list is in the document and in its hash, and
  an author who deletes a declared name and cannot undo it has lost document
  content.
- **One grammar, one implementation.** `Edit.apply/2` refuses any list
  decision 2 refuses, in the same `{:malformed_envelope, {:accepts, _}}`
  arms, by calling a public function on `StatifierBlocks.Validation` - the
  shape `Validation.datamodel/1` already has
  (`lib/statifier_blocks/validation.ex:118-119`, `def datamodel/1`) - rather
  than restating the grammar, so the panel cannot admit a list `from_json/1`
  would refuse. `check_config/3` gains an `:ok` clause for the command, as it
  has for `{:set_datamodel, _}` (`lib/statifier_blocks/edit.ex:275`), because
  a declaration has no block type to ask.
- **The row.** The accepts list is a row of the same panel, beside the
  datamodel roots, under the rules 2j to 2l already set for that panel:
  reorder by buttons, a gesture that lands on what the document already
  holds commits nothing, and a refused edit is held as a draft whose
  refusal is drawn above it and is not a `%Finding{}`. The refusal sentence
  comes from the panel's existing refusal helper,
  `StatifierBlocks.Declarations.refusal/1`
  (`lib/statifier_blocks/declarations.ex:214`), which gains the `accepts`
  arms.

### Worked example: a patron registration document

A visitor becoming a library patron proves they own an email address, and
may walk away before they do. The document's chart waits on two events the
host sends in: the host's email provider reports the address verified, and
the host's session handling reports the visitor gone. The author declares
both:

```json
{
  "accepts": ["email.verified", "registration.abandoned"],
  "id": "bdoc_01JPATRONREG",
  "revision": 4,
  "root": {"...": "the registration tree, elided"},
  "schema_version": 1
}
```

The tree holds a `core.await` on `email.verified` and, on the rail of the
group around it, a `core.on_event` on `registration.abandoned`. The same
group carries a clock interrupt in ADR-0010's spelling - a delayed
`core.send` to self at the head of its body, caught by a second
`core.on_event` on its rail whose outcome is `abandon` - a deadline: if a
day passes before either event arrives, the interrupt abandons the group,
and with it the wait on `email.verified` (ADR-0010). The compiler also
wires its own
transitions between the steps on `done.state` completion events (ADR-0004
decision 2).

- **The compile.** `compile/3` succeeds as it did before; the SCXML and the
  chart identity are what they would be with no `accepts` key at all, and
  `compiled.accepts` and `compiled.record.accepts` are both
  `["email.verified", "registration.abandoned"]`.
- **The publish check.** The host calls `Statifier.Chart.check_accepts/2`
  with the machine and the carried list. Both names are matched by a
  reachable descriptor, so nothing is unreachable. The deadline's event and
  the completion descriptors are reachable and undeclared: internal, and not
  an error. The publish proceeds.
- **A declared name the chart cannot take.** The author deletes the
  `core.on_event` on `registration.abandoned` and leaves the declaration.
  The compile still succeeds - it judges nothing about `accepts`. The
  host's check now reports `registration.abandoned` unreachable, and the
  publish is refused until the author either restores a handler or removes
  the name.
- **No declaration.** The same document with `"accepts"` omitted accepts the
  computed set, `email.verified` and `registration.abandoned` among it, and
  also the deadline's event, because nothing marked it internal. That is the
  looser contract decision 5 describes, and the reason a host may require
  the declaration.

### What this record does not decide

- **Payload typing.** An entry is a name. What a declared event carries, and
  how its shape is written, is a later slice's (decision 1).
- **A name grammar beyond decision 2's four refusals.** `validate/1` does not
  check an entry against the event-name grammar `core.await`,
  `core.on_event` and `core.send` read, and does not refuse a `*` in one. A
  name no descriptor can match is caught by decision 4 at publish. Whether a
  declared entry may itself be a pattern is not decided here.
- **The host's store.** Where a host keeps a document, its compiled artifact
  or its record, and how it indexes the declaration, is the host's.
- **How a router uses the declaration.** Binding external sources to a
  document and refusing a binding that names an undeclared event is the
  router's, in its own record.
- **The engine's two functions.** What `Statifier.Chart.events/1` computes,
  what "can be active" means, how descriptors match, and the exact return of
  `Statifier.Chart.check_accepts/2` are the engine's record's.
- **An edit-time display of the check.** The editor running the same check
  while an author edits, and where its answer is drawn, is not decided here;
  the panel row of decision 6 is an authoring surface only. No finding
  anchor for a document-level declaration is added.

## What this record owes the accepted records

Three accepted records read differently once the code that builds this one
has landed, because each spells out in full a set this record grows. They are
not edited here. Each change is owed as an `## Amendment` on its owning
record, carried by a follow-up request through the same `docs/adr/` gate,
citing this record.

- **ADR-0001, decision 11's 11e and decision 7.** 11e names the envelope-key
  allowlist in full - `datamodel`, `id`, `metadata`, `revision`, `root`,
  `schema_version` - and was itself an Amendment on ADR-0001. Decision 2 of
  this record adds `accepts` to that list. Decision 7's bump criterion is
  worded as "when this record is amended in a way that changes bytes", and
  `accepts` is added by a different record; the amendment owed states that
  the criterion applies to the envelope wherever the key is decided, so the
  "no bump" of decision 2 above is ADR-0001's reading and not only this
  record's. The typespec appendix's `%Document{}` is part of the same
  change.
- **ADR-0004, decisions 1 and 7.** Decision 1 lists what the compiled
  artifact carries - the SCXML, the provenance map, the compilation record,
  the emitted invoke types and the warnings - and decision 7 spells out
  `%CompilationRecord{}` field by field; the typespec appendix repeats both
  as `compiled` and `compilation_record`. Decision 3 of this record adds
  `accepts` to each.
- **ADR-0005, decision 2 as amended by 2g.** Decision 2 is a closed command
  set, and 2g grew it from four to five as an amendment, in its words
  because "decision 2 says its command set is closed at four, and this
  section makes it five". Decision 6 of this record adds `{:set_accepts, [String.t()]}` as the sixth, beside
  `{:set_datamodel, _}`, under 2g's and 2h's rules.

## Consequences

- **A host can tell the events a document exposes from the events it keeps
  to itself**, from data on the compiled artifact and the record, without
  reading the document or guessing from the chart.
- **Every existing document is unchanged.** It has no `accepts` key, encodes
  to the same bytes, hashes the same, compiles to the same SCXML, and is
  read under decision 5's fallback.
- **An older reader refuses a document that declares.** A 0.32.0 decoder
  refuses the key by name; a document that declares nothing is readable by
  it as before.
- **The publish check depends on the engine's two functions.** Until a
  published engine carries `Statifier.Chart.events/1` and
  `Statifier.Chart.check_accepts/2`, the envelope key, the carry and the
  editor row stand on their own and decision 4 has no function to run.

### Alternatives declined

- **A compile finding for a declared name the chart cannot take.** Declined
  for decision 4's reason, which is ADR-0004 decision 8's: the compile would
  depend on an engine function to answer a deployment question, and an
  authoring host that never starts a chart would have to satisfy it.
- **Bumping `schema_version` to 2.** Declined: no existing document's bytes
  change, which is ADR-0001 decision 7's criterion, and 11e's allowlist
  already makes an old reader refuse rather than drop the key.
- **Declaring accepted events in `metadata`.** Declined: `metadata` is the
  host's and this layer "neither reads nor requires any key in it" (ADR-0001
  decision 7), so a declaration there could be neither validated nor
  carried.
- **Distinguishing "declares nothing" from "accepts nothing".** Declined for
  this slice: the two would need different bytes, and the only way to get
  them is to encode an empty list, which would move the hash of every
  document that has no reason to declare.

## Note (2026-09-22): decision 3's pass-through sentence covers a list `validate/1` admits

A dated Note rather than an amendment: it carries no `Status:` line, decides
nothing, and edits no clause. It states the reach of one sentence that read
wider than the record meant on the day it was written, because decision 2 of
the same record already sent a malformed list to the compile's Document
stage.

Decision 3 says the carry "is a pass-through: the compile reads nothing from
`accepts`, judges nothing about it, and produces no finding from it"
(`:147-149`). That is true of a list `Document.validate/1` admits. A list it
refuses is refused by the compile before any carry, as decision 2 says
(`:124-128`): `document_stage/1` in `lib/statifier_blocks/compiler.ex`
(`:628`, read at `main` `abf3f06`) reports the refusal as its
`{:invalid_document, reason}` finding, and the test `is part of validate/1,
so the compiler's document stage reports it` in
`test/statifier_blocks/accepts_test.exs` pins it. For an admitted list, the
test `judges nothing: an undeclarable name compiles with no finding` pins
decision 3's sentence.

## Note (2026-09-22): this record is flipped to accepted

A dated Note rather than an amendment: it carries no `Status:` line, decides
nothing, and edits no clause. The only line this request changes above it is
the record's own `Status:` line (`:3`), by one word, `proposed` to
`accepted`; the index row in `README.md` changes its status cell with it.
Everything else is this Note and the one before it, at the foot of the
file, so no line another record cites moves.

The operator granted, on 2026-09-22, the flip of proposed records in this
repository. This request takes that grant for this record, through the same
`docs/adr/` direction gate, after checking every claim it makes against the
code on `main`. It is the "separate request through the same `docs/adr/`
gate" the status paragraph names (`:3-6`), and the code that builds the
record has landed.

Every `lib/` cite below was read at `main` `abf3f06` and is written anchor
first, line second; a later reader re-locates by the anchor and not by the
number. The record's own cites are labelled `aa657cd`, and it is not edited
for those that have moved; each anchor still names what the record says. The
tests named below are in `test/statifier_blocks/accepts_test.exs`.

### Each decision, and where it reads today

| Decision | Read at `abf3f06` |
|---|---|
| 1, a list of names (`:67-78`) | an entry is a string and nothing else; `Validation.accepts/1` (`validation.ex:216`) refuses a non-string entry, which is the refusal decision 1 leans on. The test `asks nothing of a name past those four` pins that no further shape is read |
| 2, the key, the bytes, no bump (`:79-131`) | `accepts` is on the `%Document{}` `defstruct` (`document.ex:70`), default `[]`. `encode/1` puts it through `maybe_put_list/3` (`canonical_json.ex:43`; the empty clause at `:124`), so an empty list is omitted. `@envelope_keys` lists it (`decode.ex:51`), and the tag `v0.32.0` reads the same attribute without it. `validate_envelope/1` in `StatifierBlocks.Validation` runs the private `check_accepts/1` after `check_datamodel/1`, and `Document.validate/1` (`document.ex:274`) keeps its return. The tests under `Document.validate/1's four refusals (decision 2)`, `the canonical bytes (decision 2)` and `the decoder (decision 2)` pin the four refusals in their exact arms, the unchanged hash of every document without the key, and the decoder's pass-through; `is part of validate/1, so the compiler's document stage reports it` pins the `{:invalid_document, reason}` finding of `document_stage/1` (`compiler.ex:628`) |
| 3, the carry (`:133-149`) | `accepts` is on the `%Compiled{}` `defstruct` (`compiled.ex:110`) and the `%CompilationRecord{}` `defstruct` (`compilation_record.ex:83`), each default `[]`, set from `document.accepts` in `chart_stage/5` (`compiler.ex:3253`) and in the record the compile builds (`compiler.ex:3411`). The tests under `the compile carry (decision 3)` pin the carry as written, the unmoved SCXML and chart identity, and that the compile judges nothing |
| 4, the consistency rule (`:151-177`) | nothing in this package runs the check; the engine's functions are read below |
| 5, no declaration (`:179-192`) | `[]` is the default on all three structs and the encoding of `[]` and of an absent key is the same bytes (the test `an empty list and an absent key are the same bytes`) |
| 6, the editor surface (`:194-228`) | `Edit.apply/2`'s `{:set_accepts, names}` clause (`edit.ex:218`) replaces the list, answers `{:set_accepts, previous}` as its inverse, and refuses through `Validation.accepts/1`; `check_config/3` has an `:ok` clause for it (`edit.ex:299`) beside the `{:set_datamodel, _}` one (`:295`). The declarations panel draws the list as its second row (`StatifierBlocks.Editor.Declarations.declarations/1`, `editor/declarations.ex:137`), and `StatifierBlocks.Declarations.refusal/1` (`declarations.ex:279`) has the `accepts` arm. The tests under `{:set_accepts, names} (decision 6)` and `the panel arithmetic (decision 6)` pin the command, its inverse, the shared refusal and the phrasing, and `test/statifier_blocks/editor/accepted_events_test.exs` pins the row's buttons, the gesture that commits nothing and the held draft. The command is the sixth of decision 2's commands; `{:compound, _}` is not counted among them, as `ADR-0005` says: "A compound is not a sixth edit" (`docs/adr/0005-liveview-editor.md:5676`) |

### The engine's two functions

Decisions 4 and 5, and the Context's paragraph at `:42-54`, name two engine
functions the record cites and does not define. Read on statifier-ex's `main`
at `4fd4191`: `Statifier.Chart.events/1` (`lib/statifier/chart.ex:223`) and
`Statifier.Chart.check_accepts/2` (`:277`) are there, specified by that
repository's ADR-0071, which is accepted. So the Context's "The engine is
specifying" (`:43`) describes the day it was written. What the record says of
them holds:

- a declared `email.verified` is matched by a descriptor `email.verified`,
  `email` or `*` (decision 4, `:159-160`); `check_accepts/2`'s documentation
  gives the same matching on token boundaries;
- `check_accepts/2` answers the declared names nothing matches as
  `unreachable` and the descriptors nothing declares as `undeclared`, and
  refuses nothing itself, so decision 4's publish error is the host's refusal
  on `unreachable`;
- the engine's no-declaration form, which decision 5 has a host pass when it
  reads `[]` (`:189-192`), is `nil`. The engine reads `[]` as a declaration
  that the chart accepts nothing, which is why the host's translation matters.

The engine has answered one question this record leaves to it (`:287-288`):
`check_accepts/2`'s documentation says a `*` in a declared name is an
ordinary token, never a pattern. This record still decides no name grammar of
its own.

No published engine carries either function yet. The last engine release
tag, `v2.6.1`, holds neither commit, and this package's `mix.lock` resolves
`statifier` `2.5.0`. The Consequences' "Until a published engine carries
`Statifier.Chart.events/1` and `Statifier.Chart.check_accepts/2`, the
envelope key, the carry and the editor row stand on their own and decision 4
has no function to run" (`:343-346`) is therefore the state today.

### Sentences that name their own status

They are met here, not edited.

- The status paragraph says the record "merges at proposed; flipping it to
  accepted is a separate request through the same `docs/adr/` gate, after
  the code that builds it has landed" (`:4-6`). This request is that one.
- "What this record owes the accepted records" (`:302-330`) says the
  Amendments on `ADR-0001`, `ADR-0004` and `ADR-0005` are owed and not
  edited here. They were owed when this record was written; the Amendments
  of 2026-09-22 on `ADR-0001`, `ADR-0004` and `ADR-0005` (merged at
  `c362e40`) now record them, and this request adds none.

### Sentences that no longer hold as written, and the records that name the change

None reverses what the record decides.

- **"The engine is specifying `Statifier.Chart.events/1` ... and
  `Statifier.Chart.check_accepts/2`" (`:42-47`).** Both are specified and
  built, by statifier-ex's ADR-0071, as read above. What the Context says
  they compute holds.

### A sentence that holds, read beside a later record

- **"No finding anchor for a document-level declaration is added"
  (`:299-300`).** True of this record, which adds none. `ADR-0005`'s
  Amendment of 2026-09-22, "a `:document` anchor for the one finding that
  names no block" (`docs/adr/0005-liveview-editor.md:12022`, clause `11v`),
  has since added that anchor for a Document-stage compile finding, and says
  "`ADR-0014` decision 2 sends a malformed `accepts` list through the same
  stage" (`docs/adr/0005-liveview-editor.md:12046-12047`).
  `Finding.from_compiler/2` maps that stage to `:document`
  (`anchor_from_compiler/1`, `finding.ex:329`), so a malformed `accepts` a
  host hands the editor as a compile refusal is drawn as a `:document`
  finding. Decision 4's check is not a compile finding, and its edit-time
  display stays undecided.

Filed with `sb-tysd`.
