# ADR-0005: The editor is a pure command algebra and view model with a thin LiveView shell

Status: accepted (2026-08-26); decision 5 and the worked example amended (2026-08-27, operator rulings); decision 12 amended (2026-08-28, operator ruling); decisions 10 (slot_style :failure) and 11 (:info) amended (2026-08-29, accepted under the operator campaign-014 direction-agent gate grant); decision 10 slot_outcome_key amended (2026-08-29, same gate, PR 78); decision 14 amended in part - 14a to 14e accepted, 14f proposed (2026-08-29, same gate, PR 85); decision 11 amended - undeclared datamodel paths as `:info` findings, 11e-11g (2026-08-29, accepted under the operator campaign-015 direction-agent gate grant, PR 90); decision 9 amended - the `:duration` control, predicator strings primary (2026-08-29, accepted under the operator campaign-015 direction-agent gate grant, PR 91); the shell arrangement recorded - three panes and a drawer, rulings 1A/2A/3A/7A/8A (2026-08-29, accepted under the operator campaign-015 direction-agent gate grant, PR 92); decision 7 amended - a second, read-only measurement hook (2026-08-29, accepted under the operator campaign-015 direction-agent gate grant, PR 100); decision 10 amended - the shipped `icon` names are heroicon names, 10k/10l (2026-08-29, accepted under the operator campaign-015b direction-agent gate grant, PR 128); decisions 10 and 13 amended - rendering the tree and its connectors, 10a-10c (2026-08-29, accepted under the operator campaign-016 direction-agent gate grant, PR 135); decision 10 amended - the presentation trio and the 24-character cap, 10m-10o (2026-08-30, accepted under the operator campaign-017 direction-agent gate grant, PR 155); decision 11 amended - a `:compile` source and `:lint` at `:error`, 11h/11i (2026-08-30, same gate, PR 155); decision 11 amended - `:arity` dropped from the source enum, 11j (2026-08-30, same gate, PR 155); decision 2 amended - a container folds shut and the fold is editor state, 2a-2f (2026-08-30, accepted under the operator campaign-020 direction-agent gate grant, PR 176); decision 11 amended - what feeds the declared set 11e reads, 11k-11m (2026-08-31, accepted under the operator campaign-022 direction-agent gate grant, PR 189)

## Context

ADR-0001 fixed the document: a tree of `{type, id, config, slots}` nodes with
stable ids, where a block's position is fully described by its path
`{parent id, slot name, index}`. ADR-0002 fixed the extension seam: a block
type is a behaviour module, resolved through a caller-supplied palette, whose
callbacks are pure functions of config. Both records named this one as the
owner of four questions they deliberately left open - what `palette_entry/0`
contains, how a config schema renders as a form, how validation findings are
presented, and what an unresolvable block looks like on screen.

This record answers those four and settles the shape of the editor itself.

**The editor ships in this package, from day one.** That is an operator
decision this record records rather than argues: `statifier_blocks` ships both
the headless core and the LiveView editor components. The alternative - a
`statifier_blocks_ui` satellite - was rejected because the editor and the
block-type behaviour move together. Every callback ADR-0002 declared exists to
be rendered by something, and splitting the two across packages means every
change to the behaviour is a two-repo, two-release dance for no compensating
benefit. The family already has a package that owns rendering for the *engine*
(statifier-ui, charts and traces); this package owns rendering for the
*document*, which is a different artifact with a different lifetime.

Shipping the editor in the same package as the core creates one obligation
that the rest of this record is largely about discharging: **a host that never
renders anything must not pay for LiveView.** An authoring API that compiles
documents in a background job, a test suite that exercises validation, a
migration script - none of these should drag in Phoenix. The dependency shape
that makes that true was deliberately deferred from the scaffold bead to this
record, and decision 1 settles it.

**This does not reopen sui-ADR-0007.** That record made statifier-ui's
authoring text-first: SCXML source is the artifact, a graphical canvas that
regenerates SCXML from gestures is ruled out, and undoing that would be a
superseding record owing an answer to the round-trip problem. A block editor
that compiles to SCXML looks, at a glance, like exactly the thing that record
forbids, so it is worth being precise about why it is not.

The artifacts are different and so are their round-trip obligations. In
statifier-ui the SCXML *is* the document, so a canvas that writes it back has
to reconstruct source it did not author - comments, formatting, hand-written
constructs the canvas has no vocabulary for - and that is the problem
sui-ADR-0007 declined to solve. Here the block document is the source of
truth and SCXML is generated output that **nothing ever edits and nothing ever
parses back** (ADR-0001: "There is no reverse edge"). There is no round-trip
problem to answer because there is no round trip. The two records agree on the
underlying principle - never edit a generated artifact - and reach different
surfaces because they are pointed at different sources of truth. A host may
sensibly run both: block authoring for workflows it owns, text authoring for
charts it hand-writes.

Three further forces shape the design.

**The editor knows only the block-type behaviour.** This is the second
operator pre-decision, and it is the same discipline ADR-0002 decision 2
applied to the palette. The editor never contains a branch on a type name -
not on `core.branch`, not on `core.parallel`, and certainly not on any host
type. A host's palette arrives as behaviour implementations; if the editor
cannot render a block type through the callbacks alone, the deficiency is in
the callback surface and gets fixed there. Palette contents, publishing,
authorization, storage, and who may edit what all stay host-side and are named
in decision 15's last bullet so nobody re-litigates them.

**Every gesture must reduce to something testable without a browser.** The
brief is explicit about this and it is the single most load-bearing constraint
here. Drag-and-drop is the interaction most likely to be tested by clicking
around and declared fine, and the one most likely to corrupt a document when
it is wrong. If the semantics of a drag live in JavaScript, or in a
LiveComponent's `handle_event`, they are testable only through a browser
driver. So the design pushes all of it - the mutation, its inverse, and the
set of places a block may be dropped - into pure functions over
`{document, palette}`, and leaves the LiveView shell with nothing but
translation.

**Validity must be visible before the author hovers.** The brief asks that
every valid slot highlight at drag start rather than lighting up one at a time
under the pointer. That is a usability requirement with an architectural
consequence: the valid-target set has to be computable in one shot from the
dragged block and the document, which it is, because assignability (sb-7rx) is
a pure function of block types and config.

## Decision

**1. `phoenix_live_view` is an optional dependency at `~> 1.0`, and the
editor modules are compiled behind a presence guard.** This is the shape the
scaffold bead deferred here.

```elixir
{:phoenix_live_view, "~> 1.0", optional: true}
```

The version requirement and the flag are copied deliberately from
statifier-ui's `mix.exs`, where `{:phoenix_live_view, "~> 1.0", optional: true}`
carries a comment making the same argument for the same reason. Two packages in
one family disagreeing about the LiveView floor is a problem a host discovers
at dependency resolution, and there is no reason to create it.

`optional: true` alone is not sufficient and the reason is worth writing down,
because it is the part that gets this wrong in practice. Elixir compiles every
module in a package regardless of which are reachable, so a module that calls
`use Phoenix.Component` fails to compile when the optional dependency is
absent - which is precisely the case the flag exists to support. sui-ADR-0004
already settled the remedy for its own optional integrations, and this record
adopts it rather than inventing a second one:

> Every module under `StatifierBlocks.Editor.*` is wrapped in
> `if Code.ensure_loaded?(Phoenix.LiveView) do ... end`, and no module outside
> that namespace references Phoenix in any way.

The acceptance property is mechanical and belongs in CI as its own job:
**the package compiles clean, and the full headless test suite passes, with
`phoenix_live_view` absent from the dependency tree.** A guard that is never
exercised without the dependency present is a guard that is already broken.

Two consequences follow that are easy to miss. The namespace boundary is now
load-bearing rather than decorative - `StatifierBlocks.Editor.*` is the only
place Phoenix may be named, and that includes the pure view model, which is
therefore *not* under that namespace (decision 3). And a host that wants the
editor adds `phoenix_live_view` to its own deps, which it already has, since a
host without LiveView has nowhere to put the editor anyway.

No `phoenix_html`, `esbuild`, or `tailwind` dependency is declared. The first
arrives transitively with LiveView; the latter two are asset-pipeline tools
that belong to the host, and this repository's toolchain stays Node-free for
the same reasons sui-ADR-0009 gives. Decision 7 is how the editor's JavaScript
reaches a host bundle without them.

One packaging detail, recorded because the sibling repo currently has it
wrong: **`assets` must appear in the `files:` list** in `mix.exs`. Source that
ships as source is only public API if it is actually in the hex tarball.

**2. Four commands, closed set, each a serializable value.** Every author
gesture - drag, drop, click a "+", delete, duplicate, edit a field - produces
exactly one of:

| Command | Meaning |
|---|---|
| `{:insert, target, %Block{}}` | put this block (and its subtree) at this position |
| `{:remove, block_id}` | detach this block and its subtree |
| `{:move, block_id, target}` | relocate an existing block to this position |
| `{:update_config, block_id, config}` | replace one block's config |

where `target` is `{parent_id, slot_name, index}` - ADR-0001 decision 5's path
element, unchanged.

Four, not seven, because the obvious extras are not primitive. **Reordering
within a slot is a `:move`** whose target parent and slot happen to match the
source. **Duplication is an `:insert`** of a subtree whose ids were freshly
minted before the command was built. **Inserting from the palette is an
`:insert`** of a block the palette constructed. Collapsing these matters more
than it looks: it means there is one code path that puts a block into a slot,
so the assignability check, the arity check, and the index arithmetic have one
implementation each rather than three that drift.

Minting ids outside the command is the subtle half. ADR-0001 decision 3 says
duplication mints new ids, which makes duplication *not* a pure function of
the document - it needs entropy. Rather than admit an id generator into the
command algebra and give up determinism, the LiveView process mints the ids at
gesture time and bakes the finished block into the `:insert`. The recorded
command is then fully serializable, and replaying a command log against the
same starting document yields the same document every time. The undo stack,
the test fixtures, and any future collaborative transport all get that
property for free.

**3. `Edit.apply/2` returns the inverse command, and the undo stack is a list
of commands.** Not a list of document snapshots, and not a list of
hand-written inverse pairs.

```elixir
@spec apply(Document.t(), Edit.t()) :: {:ok, Document.t(), Edit.t()} | {:error, term()}
```

The third element is the command that undoes the one just applied: the inverse
of an `:insert` is a `:remove`, the inverse of a `:remove` is an `:insert`
carrying the detached subtree and its original position, the inverse of a
`:move` is a `:move` back, and the inverse of an `:update_config` is an
`:update_config` to the previous config. Undo is applying the inverse and
pushing *its* inverse onto the redo stack; redo is the same in the other
direction. There is one function to test.

The law this is held to, in the same style as ADR-0001's round-trip law: for
every document `d` and every command `e` that applies to it,

```
{:ok, d2, inv} = apply(d, e)
{:ok, d3, _}   = apply(d2, inv)
d3 == d
```

and this is a property test over generated documents and commands, not three
examples.

Because the algebra is pure and lives outside `StatifierBlocks.Editor.*`, all
of it is tested with no LiveView in the dependency tree at all - which is the
same CI job decision 1 already requires.

**4. Move-index semantics: the target index is read against the slot with the
moved block already removed.** A one-line decision that prevents a genuine
class of off-by-one bug. Moving a block from index 1 to index 3 of the same
five-child slot means "remove it, then insert at 3 of the remaining four", not
"insert at 3 of the original five and then remove". Every sortable
implementation has to pick one; this record picks the one that makes `:move`
describable without reference to its own source position, so that the command
means the same thing whether the source and target slots are the same or
different.

**5. Drop-target validity is a property of the slot, not of the gap, and it is
computed once per drag.** The valid-target enumeration is a pure function:

```elixir
@spec droppable_slots(Document.t(), Palette.t(), Block.id()) :: [{Block.id(), Block.slot_name()}]
```

A slot accepts the dragged block when all four hold:

1. The slot is declared - the parent resolves through the palette, and
   `slots/1` on the parent's *current config* lists this slot name.
2. Assignability accepts it - the relation sb-7rx defines, consulted through
   one predicate and nothing else.
3. The slot has room - a `:exactly_one` or `:zero_or_one` slot that is
   already occupied is not a target. A drop never silently replaces a child;
   the author removes first.
4. The slot is not inside the dragged block's own subtree - a block cannot
   become its own descendant, and ADR-0001 decision 1's tree invariant is not
   negotiable.

Rules 1, 3 and 4 do not depend on the index within the slot; rule 2's
kind-admission half is index-free too, while its seam half reads the
neighbours at the index and therefore does move with it (amended
2026-08-27 - the original sentence claimed index-independence outright).
Per-slot validity is a deliberate over-approximation on exactly that half:
highlighting a slot when at least one of its gaps admits the block can
offer a gap that later yields a `:type_mismatch` finding, and can never
hide a gap that would have been clean - which is the right direction for a
mechanism the editor does not block on. That is not a simplification for
its own sake: it means
the enumeration is O(slots) rather than O(gaps), and it means the editor
highlights a whole slot as a target region rather than lighting up n+1
individual seams, which is also the clearer thing to look at.

**The editor never blocks an edit for a validation reason, with the single
exception of the four rules above.** Dragging the last child out of an
`:at_least_one` slot is permitted and produces a validation finding; it is not
prevented. The asymmetry is deliberate. A target-side check stops a gesture
that is meaningless or destructive, while a source-side check would make legal
rearrangements impossible - you cannot move a block from one `:at_least_one`
slot to another without a transient violation in between. ADR-0002 decision 6
already established that arity is a validation rule applied to a document that
is allowed to fail it. A document mid-edit is allowed to be invalid; deciding
whether an invalid document may be *saved* is the host's, not the editor's.

**6. One round-trip per drag, and validity reaches the client as markup.**
The interaction, precisely:

- `dragstart` on a block pushes one event to the server.
- The server computes `droppable_slots/3` and re-renders, stamping
  `data-drop="ok"` on the accepting slots and `data-drop="no"` on the rest.
- Hover highlighting is CSS on those attributes. It costs nothing and it
  cannot disagree with the server.
- `drop` on a gap pushes `{block_id, parent_id, slot, index}`; the server
  builds a `:move` (or `:insert`), applies it, and re-renders.
- `dragend` clears the drag session.

So there is exactly one round-trip at drag start and one at drop, and zero per
hover - which is what the pre-hover-validity requirement in the brief buys,
and the reason it is worth requiring. It also means the client holds no
validity logic to fall out of sync, and no drag state that survives a
re-render.

**7. Exactly one JavaScript hook.** `StatifierBlocksDrag`, attached to the
canvas root, and it is the whole client-side surface of this package.

Its entire job is to translate pointer and drag events into `pushEvent` calls,
reading `data-block-id`, `data-slot`, and `data-index` off the DOM. It never
mutates the block tree in the DOM - the server re-renders after every command,
so a hook that moved nodes itself would be fighting LiveView's DOM patching
for ownership of the same elements, which is the standard way drag-and-drop
integrations break.

One hook, rather than one per interactive affordance, because decision 2 made
every gesture a server-side command. Config fields, the palette, selection,
undo, and the "+" buttons are all ordinary `phx-` bindings with no JavaScript
at all. **Adding a second hook requires amending this record**, which is a
deliberately high bar: a second hook is the signal that some behaviour has
started living on the client, and that is the thing this design is arranged to
prevent.

The DOM contract the hook depends on is therefore part of the contract:
`data-block-id` on each block's root element, `data-slot` and `data-index` on
each gap, `data-drop` on each slot during a drag session. Stamping structure
with data attributes and asserting on the stamps is sui-ADR-0007's convention,
and decision 13 leans on it for the same reason that record does: it is what
makes rendering testable without pixels.

**The hook ships as source in `assets/`, per sui-ADR-0009.** The host adds
`"statifier_blocks": "file:../deps/statifier_blocks"` to its
`assets/package.json` and imports the hook in `app.js`; this repository never
bundles anything and never acquires a Node toolchain. `assets/`'s entry point,
its export name, and the hook name are versioned public API with the same
obligations as the Elixir modules - again sui-ADR-0009's rule, inherited
wholesale.

The hook is named `StatifierBlocksDrag` rather than anything shorter because
two packages in this family may end up registering hooks into the same host
`app.js`, and a collision there is a debugging session nobody enjoys.

Worth naming, because it is the one place this record could have diverged:
sui-ADR-0009 bans colocated hooks for anything pulling npm dependencies, but
explicitly permits them for "a genuinely self-contained hook with no imports",
which is exactly what `StatifierBlocksDrag` is. A colocated hook would free a
host from the `package.json` line and the bundler entirely - a real
improvement over the source-delivery burden sui-ADR-0009 accepts for
CodeMirror's sake. It is not taken here only because colocated hooks require a
LiveView floor above the `~> 1.0` decision 1 just matched to the sibling
repo. **If that floor ever moves, this is the first thing to revisit**, and
under sui-ADR-0009's own carve-out it would be a consistent move rather than a
divergence.

**8. Every drop target is reachable without dragging.** Each gap in a
highlighted slot carries a "+" button; activating it opens the palette
filtered to the block types that slot accepts, and choosing one emits an
`:insert` at that exact position. The filter uses the same predicate as
decision 5, not a parallel implementation.

This is not only an accessibility affordance, though it is that - drag-and-drop
is unusable by keyboard and hostile on touch. It is also what makes the whole
insertion path exercisable in `LiveViewTest` without simulating a drag,
because clicking a "+" and choosing a type produces the identical command a
successful drop would.

**9. Config forms are generated from `config_schema/1`, and an invalid form
never reaches the document.** ADR-0002 decision 7 gave a closed field-type
set precisely so that the editor's renderer can be total; here is the mapping,
which is exhaustive by construction:

| Field type | Rendering |
|---|---|
| `:string` | single-line text input |
| `:integer` | number input, step 1 |
| `:boolean` | checkbox |
| `{:select, choices}` | select, choices in declared order |
| `:expression` | single-line source input (see below) |
| `:duration` | structured value/unit control emitting an ISO-8601 string |
| `{:list, t}` | repeatable rows of `t`'s renderer, with add and remove |

The schema is re-derived after every config change rather than cached, because
ADR-0002 decision 7 made it a function of config - a branch grows a condition
field as arms are added, and a select's choices can depend on an earlier
field. The form is a projection of current config, never a stateful mirror
of it.

`:duration` emits a string rather than a number because ADR-0001 decision 6
forbids floats in config, and "1.5 hours" has to be `PT1H30M`. The control
exists so the author does not have to know that.

`:expression` renders as a plain source input in this package. Predicator
source is statifier-ui's subject (sui-bob, sui-ADR-0006), and a richer
affordance - completion against the datamodel, inline evaluation against a
dataset - is a component this package should consume rather than reimplement.
Decision 15 records that as a deferral, and the field renderer is written to
accept a host-supplied override component for exactly this reason. [Correction
2026-08-29, sb-4kh: was "Decision 12". The rich-expression-editing deferral is
decision 15's "Rich expression editing is statifier-ui's (sui-bob)" bullet;
decision 12 is about unresolvable blocks. Found by sb-e3c.]

Now the part that falls out of ADR-0002 and is easy to get wrong. ADR-0002
decision 6 guarantees `slots/1` returns without raising only for config that
`validate_config/1` accepts. So the editor must never call `slots/1` on config
it knows to be invalid - and an author halfway through typing an identifier
has invalid config almost continuously. Therefore:

> **An `:update_config` command is applied to the document only when
> `validate_config/1` returns `:ok`.** In-progress form state that does not
> validate lives in the editor's transient assigns, never in the document and
> never on the undo stack.

Three things follow. The document is always structurally sound - the slot set
of every block in it is well-defined, which every consumer downstream depends
on. The undo stack has meaningful granularity: undo steps back to the last
config that validated, not through individual keystrokes. And validation
findings on a form are always about the value the author is currently typing,
because the last valid value is already committed.

**10. `palette_entry/0` returns presentation metadata, all of it optional
except a label, and none of it markup.** This is the callback ADR-0002
decision 5 hung off the block-type module and left to this record to fill in.

| Key | Default | Meaning |
|---|---|---|
| `label` | the type name | what the author reads |
| `group` | `"Other"` | palette section heading |
| `description` | `""` | one line, shown on hover and in the palette |
| `icon` | `nil` | an icon *name* |
| `keywords` | `[]` | additional palette search terms |
| `order` | `0` | sort position within the group |
| `layout` | `:stack` | `:stack` or `:columns` - how this type's slots are arranged |
| `slot_style` | `%{}` | statically-named slot to `:primary` or `:secondary` |

Every default is specified because a block type omitting `palette_entry/0`
entirely must still render, and ADR-0002 decision 5 promised it would.

[Open item 2026-08-29, sb-4kh - NEEDS A DECISION, none taken here. ADR-0002's
amendment section B closes with "The cap itself is a number ADR-0005 decision
10 should carry rather than this record; the spike's is 24 characters for both
the badge and the join marker." The cap now exists in code as
`@presentation_cap 24` in `lib/statifier_blocks/block_type.ex` (sb-zfd), with
ADR-0002 B3's refuse-never-truncate semantics. Adopting it into this decision
is more than a correction, for two reasons: decision 10's table above carries
no `badge` or `join_label` row at all, and ADR-0002 B1 says explicitly that it
"does not adopt the trio into decision 10 on that record's behalf". So adopting
the cap means first adopting the trio into this table, which is a decision for
the operator or the direction-agent gate. Recorded, not decided.]

**`icon` is a name, never markup.** The editor takes an icon component as an
attr and passes the name to it; a host that ships heroicons renders heroicons,
a host that ships nothing gets a neutral glyph. A package that accepted raw
SVG from a callback would be injecting host-authored markup into its own
render tree, which is both an injection surface and a guarantee that the icon
set fragments across palettes.

`layout` and `slot_style` are how nested groups render distinctly **without
the editor branching on a type name.** `core.parallel` declares
`layout: :columns`, so its lane slots sit side by side and the absence of
ordering between them is visible; `core.resumable_group` declares
`slot_style: %{"interrupts" => :secondary}`, so its interrupt rules render as
an attached rail rather than as a second body. Both are per-type constants,
which is exactly what an arity-zero callback can express, and neither requires
naming a config-parameterized slot - arms and lanes are unlisted and default
to primary. A host block type with the same structural shape gets the same
rendering by declaring the same thing, which is the property that matters.

Deliberately *not* here: the resume mode. `core.resumable_group`'s
shallow-versus-deep history is a `:select` config field (ADR-0002 decision
10), so it renders through decision 9's ordinary form machinery with no editor
support whatsoever. The brief lists "resume toggles" alongside groups and
lanes; the answer is that two of the three need presentation metadata and the
third is already just config, and noticing that is the point.

**11. Findings are anchored, and the anchor decides where they render.**
Findings arrive from sources with different shapes - `validate_config/1`
returns `{key, message}` pairs, arity and undeclared-slot violations are about
a slot, resolution failures are about a block - so the editor normalizes them:

```elixir
%Finding{
  severity: :error | :warning,
  anchor:   {:config, block_id, key} | {:slot, block_id, slot_name} | {:block, block_id},
  source:   :config | :arity | :assignability | :resolution | :lint,
  message:  String.t()
}
```

The anchor is the whole routing mechanism: a `:config` finding renders inline
beneath its field, a `:slot` finding on that slot's header, a `:block` finding
on the block's chrome. A document-level panel lists all findings; selecting
one selects and reveals its anchor. A collapsed subtree carries a count badge
so a finding can never hide inside something folded shut - which is the
failure mode that makes tree editors feel unreliable.

Severity is two-valued, and every source listed above except `:lint` produces
`:error`. `:lint` is present because ADR-0002's consequences named a real gap:
a block type can emit an invoke type for which the host has registered no
runtime handler, and nothing catches it at authoring time. **Whether that lint
belongs to the compiler or to the editor is sb-iwz's to settle, not this
record's** - so this record decides only that the presentation layer has a
place to put the answer, and that it renders as a warning rather than an error
because a document with one is still compilable and still correct if the host
registers the handler before it runs.

[Open items 2026-08-29, sb-4kh - BOTH NEED A DECISION, neither taken here.
Building the adapter from compiler findings to this shape (`Finding.from_compiler/2`,
sb-kmk) and the palette-aware slot validation behind it (sb-da9) exposed two
gaps in the `source` enum above.

1. **No bucket for an `:emit`, `:chart` or `:document` stage error.** The
   adapter maps compiler findings to a source by stage: `:config` to `:config`,
   `:resolve` to `:resolution`, `:structure` to `:assignability`, and anything
   else at `:error` severity is refused as `{:no_presentation_source, finding}`.
   So an error raised against generated SCXML or against the document envelope
   has no source in this enum and cannot render in the editor today. The
   adapter refuses rather than lying about where the rule lives, which is the
   right refusal for it to make, but it leaves real compile errors unroutable.
   Closing the gap means adding a value to an accepted enum.

2. **`:arity` is unreachable by construction.** Slot arity and undeclared-slot
   violations landed as `StatifierBlocks.SlotValidation`, reported through the
   compiler's `:structure` stage, so they adapt to `:assignability`. No rule in
   the adapter yields `:arity`, and no other producer exists. It remains
   reachable only by a caller passing `source: :arity` explicitly to
   `from_compiler/2`. Whether to drop the enum entry or keep it with a note is
   a decision, and the prose above ("arity and undeclared-slot violations are
   about a slot") should follow whichever way it goes.

Both are recorded here so the gap is not re-derived; neither is decided.]

**12. Unresolvable blocks render, and never lose data.** ADR-0001 decision 9
made decoding registry-free and ADR-0002 decision 3 made resolution total,
both of them explicitly to create this case rather than avoid it. Here is what
the author sees.

A block whose type does not resolve - `{:error, {:unknown_block_type, name}}`,
or `{:error, {:block_type_too_new, ...}}`, which differ only in message -
renders with:

- its type name and an unavailable chrome, plus a `:block` finding;
- its config shown read-only as canonical JSON, because there is no
  `config_schema/1` to drive a form and inventing one would be guessing;
- **its existing children rendered normally, recursively.** The children are
  in the document's `slots` map, which decoding preserved; slot headers show
  the raw slot names, since there are no declared labels.

It may be selected, moved, and deleted. Its config may not be edited. It is
never a drop target for a new or foreign block, because decision 5's first
rule needs `slots/1` and there is none. Reordering blocks *within* one of its
existing slots is **not offered either**, for the same reason: decision 5's
enumeration works from `slots/1`, so an unresolvable parent contributes no
targets at all, and `droppable_slots/3`'s return type - a list of
`{block_id, slot_name}` - cannot express "this slot, but only for blocks
already in it". Nothing here forbids the reorder in principle: order is a
document-level property that asks the parent's type nothing, so an enumeration
that later expresses it is a purely additive extension of decision 5 rather
than a reversal of this one (amended 2026-08-28, operator ruling - the
original sentence said the reorder is permitted; decision 5's enumeration is
correct as written and this sentence was the error).

The acceptance property is preservation: **open a document containing a block
type the host does not have, edit an unrelated part of the tree, save, and the
unresolvable block's bytes are unchanged.** An editor that quietly dropped it
would turn a missing palette entry into silent data loss, which is exactly the
outcome ADR-0001 decision 9 paid for the ability to avoid.

**13. The component tree, and where the boundary between pure and rendered
falls.** The acceptance criterion for this bead asks the component boundaries
be named, so they are named.

Outside `StatifierBlocks.Editor.*` - no Phoenix, tested with LiveView absent:

| Module | Responsibility |
|---|---|
| `StatifierBlocks.Edit` | the command type, `apply/2`, inverses (decisions 2-4) |
| `StatifierBlocks.Edit.History` | undo and redo stacks over commands |
| `StatifierBlocks.Edit.Targets` | `droppable_slots/3` (decision 5) |
| `StatifierBlocks.ViewModel` | derives everything renderable from `{document, palette}` |

Inside `StatifierBlocks.Editor.*` - guarded per decision 1:

| Module | Kind | Responsibility |
|---|---|---|
| `StatifierBlocks.Editor` | live component | the only stateful one: document, history, selection, drag session |
| `StatifierBlocks.Editor.Canvas` | function | the tree's root and the drag hook's element |
| `StatifierBlocks.Editor.BlockNode` | function, recursive | one block's chrome, dispatching to its slots |
| `StatifierBlocks.Editor.Slot` | function | one named slot: header, children, gaps, "+" buttons |
| `StatifierBlocks.Editor.ConfigForm` | function | the selected block's form |
| `StatifierBlocks.Editor.Field` | function | one field, dispatching on the closed type set |
| `StatifierBlocks.Editor.PaletteBrowser` | function | grouped, searchable, filterable palette |
| `StatifierBlocks.Editor.Findings` | function | the document-level findings panel |

`ViewModel` is the load-bearing one. It is where resolution, migration,
validation, and `palette_entry/0` lookup happen, and it produces a structure in
which every block is already paired with its declared slots, its findings, and
its presentation metadata. The components below it are then close to
mechanical - they read a view model and emit markup, with no palette lookups
and no callback invocations of their own. That is what keeps the untested
surface down to markup, and it is why `ViewModel` lives outside the guarded
namespace despite being an editor concern.

Recursion is uniform. `BlockNode` renders slots via `Slot`, `Slot` renders
children via `BlockNode`, and groups, lanes, branches, and interrupt rails are
all the same two components differing only by the metadata in decision 10.
There is no `Group` component and no `Parallel` component, and there must
never be one.

Only `StatifierBlocks.Editor` is stateful. Everything else is a function
component taking assigns, which means each is renderable in isolation in a
test and none of them can accumulate state that disagrees with the document.

**14. Theming is a class prefix, CSS custom properties, and a per-component
class override.** The package ships one stylesheet of structural CSS - the
things the editor is broken without, like the column layout and the drag
affordances - and no visual opinion beyond that.

- Every class the package emits is prefixed `sb-`.
- Colors, spacing, radii, and the drag-highlight treatment are CSS custom
  properties on the canvas root, named `--sb-*`, each with a default.
- Every top-level component accepts a `class` attr appended to its own.
- No CSS framework is depended on and no framework's class names are emitted,
  so the editor drops into a host with any styling approach.

"Moderate" is the operative word from the brief and it cuts both ways: enough
that a host can make the editor look like its own product without forking it,
and not so much that the package acquires a theming DSL to maintain. A host
wanting more than this restyles with its own CSS against the `sb-` prefix,
which is a stable surface this record commits to.

**This is a new contract, not an inherited one.** statifier-ui has no theming
convention - no class prefix, no custom-property namespace, nothing reserved -
so there is nothing here to be consistent with and this record is not citing
sui-ADR-0009 for it. The `sb-` prefix and the `--sb-*` property namespace are
chosen to not collide with a `sui-` equivalent if that repo ever wants one,
and if the family later wants a shared theming contract, this record is the
one that gets superseded.

**15. What this record does not decide.** Named so the boundary is not
re-derived later.

- **Assignability (sb-7rx)** owns `io/1`'s return shape, what a type
  expression is, and the compatibility relation. This record consumes it
  through exactly one predicate in decision 5's rule 2 and takes no position
  on its internals.
- **The compiler and provenance map (sb-iwz)** own emission, state-id
  generation, and provenance. An SCXML or diagram preview pane is a natural
  editor feature and is deliberately not specified here, because it consumes
  a provenance map that does not exist yet.
- **The unregistered-invoke-type lint** is sb-iwz's to place, per decision 11.
  This record commits only to rendering it if it lands.
- **Per-palette-entry fixtures** - the "test this step" panel ADR-0002
  decision 9 sketched - wait on sui-13q, unchanged and still provisional.
- **Rich expression editing** is statifier-ui's (sui-bob). Decision 9 ships a
  plain input and an override seam.
- **Concurrent editing.** The editor is a single-session component. It
  surfaces the `revision` it loaded (ADR-0001 decision 7) so a host can do
  optimistic concurrency on save, and it does not merge, rebase, or resolve
  anything. Multi-user editing, if it ever arrives, is a new record.
- **Host concerns**, restated once so they are unambiguous: which palette
  entries a tenant may use, who may edit or publish a document, where it is
  stored, and what publishing means are all outside this package.

## Consequences

- A host that only compiles documents adds no Phoenix dependency and compiles
  no editor code. The CI job that proves this is not optional; decision 1's
  guard is untrustworthy without it.
- Because the command algebra, the target enumeration, and the view model are
  pure and unguarded, the great majority of the editor's behaviour is tested
  in plain ExUnit with no browser and no LiveView. `LiveViewTest` covers the
  shell's event translation. The single JS hook is the only surface no ExUnit
  test reaches, and keeping it to one is what makes that acceptable.
- The undo stack is a command log, so it serializes. Nothing in this record
  requires that, but a persisted edit history or an operational-transform
  transport later would start from a data structure that already exists rather
  than from a rewrite.
- Committing config only when it validates means undo granularity is
  coarser than keystrokes, and an author who types garbage and hits undo goes
  back to the last good value rather than to the previous character. That is
  the intended trade for never letting `slots/1` see config that
  `validate_config/1` rejects.
- The editor renders block types it has never heard of, including ones whose
  implementation was deleted, and preserves them byte for byte. The cost is
  that a host removing a palette entry gets no warning until an author opens
  a document that used it.
- Presentation metadata on `palette_entry/0` means adding a new *structural
  arrangement* - something that is neither a stack nor columns - is a change
  to this record and to that callback's contract, not a new component. That is
  deliberate friction. The alternative is an editor that grows a special case
  per block type, which is the thing the operator pre-decision exists to
  prevent.
- One hook and server-side validity means every drag costs a round-trip at
  its start. On a document large enough for that to be perceptible, the fix is
  to make `droppable_slots/3` faster, not to move it to the client - and
  because it is a pure function, that optimization is measurable in a
  benchmark rather than in a browser.
- Two of this record's decisions are pinned to records that do not exist yet
  (sb-7rx's predicate, sb-iwz's lint). Neither blocks implementation: the
  predicate can be stubbed to "everything is assignable" and the lint is
  simply absent, and both are one-line changes when their records land.

## The contract as typespecs

```elixir
defmodule StatifierBlocks.Edit do
  @moduledoc """
  The editor's command algebra. Pure, serializable, invertible - and
  deliberately free of Phoenix, so it is tested with LiveView absent
  (ADR-0005 decision 1).
  """

  alias StatifierBlocks.{Block, Document}

  @typedoc "A position, not a block. ADR-0001 decision 5's path element."
  @type target :: {Block.id(), Block.slot_name(), non_neg_integer()}

  @typedoc """
  Ids in an `:insert`ed block are already minted, which is what keeps the
  command replayable (ADR-0005 decision 2).
  """
  @type t ::
          {:insert, target(), Block.t()}
          | {:remove, Block.id()}
          | {:move, Block.id(), target()}
          | {:update_config, Block.id(), Block.config()}

  @doc """
  Applies one command, returning the new document and the command that undoes
  it. Total: refuses rather than raises.

  For `:move`, the target index is read against the slot with the moved block
  already removed (ADR-0005 decision 4).
  """
  @spec apply(Document.t(), t()) ::
          {:ok, Document.t(), t()}
          | {:error, {:no_such_block, Block.id()}}
          | {:error, {:no_such_slot, Block.id(), Block.slot_name()}}
          | {:error, {:index_out_of_range, target()}}
          | {:error, {:would_cycle, Block.id()}}
end

defmodule StatifierBlocks.Edit.Targets do
  @moduledoc "Drop-target enumeration. One pure function; see ADR-0005 decision 5."

  alias StatifierBlocks.{Block, Document, Palette}

  @doc """
  Slots that would accept this block: declared, assignable (sb-7rx), with
  room, and outside the block's own subtree. Per-slot, not per-gap.
  """
  @spec droppable_slots(Document.t(), Palette.t(), Block.id()) ::
          [{Block.id(), Block.slot_name()}]
end

defmodule StatifierBlocks.Finding do
  @moduledoc "Normalized for presentation; the anchor routes it (ADR-0005 decision 11)."

  alias StatifierBlocks.Block

  @type anchor ::
          {:config, Block.id(), key :: String.t()}
          | {:slot, Block.id(), Block.slot_name()}
          | {:block, Block.id()}

  @type t :: %__MODULE__{
          severity: :error | :warning,
          anchor: anchor(),
          source: :config | :arity | :assignability | :resolution | :lint,
          message: String.t()
        }

  defstruct [:severity, :anchor, :source, :message]
end
```

And the shape of `palette_entry/0`, whose contents ADR-0002 decision 5
deferred here:

```elixir
@typedoc """
All keys optional. `icon` is a name resolved by a host-supplied component,
never markup (ADR-0005 decision 10).
"""
@type palette_entry :: %{
        optional(:label) => String.t(),
        optional(:group) => String.t(),
        optional(:description) => String.t(),
        optional(:icon) => String.t(),
        optional(:keywords) => [String.t()],
        optional(:order) => integer(),
        optional(:layout) => :stack | :columns,
        optional(:slot_style) => %{optional(String.t()) => :primary | :secondary}
      }
```

## Worked example: one drag, end to end

The document is ADR-0001's worked example. The author drags `blk_NOT` (a
notify step, currently the second block in the parallel block's
`lane_receipt`) out of that lane and into the branch's `otherwise` slot,
dropping it above the notify that is already there.

**At `dragstart`,** the shell pushes one event and the server evaluates:

```elixir
Edit.Targets.droppable_slots(document, palette, "blk_NOT")
#=> [
#     {"blk_ROOT", "body"},
#     {"blk_GRP", "body"},
#     {"blk_BR", "arm_approved"},
#     {"blk_BR", "otherwise"},
#     {"blk_PAR", "lane_capture"},
#     {"blk_PAR", "lane_receipt"}
#   ]
```

Six slots highlight at once, before the pointer has moved (amended
2026-08-27: this example originally listed seven, including
`{"blk_GRP", "interrupts"}` - machine-checking found the relation says
otherwise, exactly as the conditional below predicted). Note what is absent
and why: nothing inside `blk_NOT` itself (rule 4 - it has no children here,
but the rule is what makes dragging a group safe), and `blk_GRP`'s
`interrupts` slot is dark because the notify step's kinds do not include
`:interrupt_handler`, which is the only kind that slot accepts; had
sb-7rx's relation said otherwise, it would light. Every one of those six is
a pure-function assertion in a test file.

**At `drop`,** the client pushes `{"blk_NOT", "blk_BR", "otherwise", 0}` and
the server builds and applies one command:

```elixir
{:ok, document, inverse} =
  Edit.apply(document, {:move, "blk_NOT", {"blk_BR", "otherwise", 0}})

inverse
#=> {:move, "blk_NOT", {"blk_PAR", "lane_receipt", 1}}
```

`lane_receipt` now holds only `blk_WAI`; `otherwise` holds `blk_NOT` then
`blk_NO2`. No id changed - ADR-0001 decision 3 - so the provenance map sb-iwz
will build still keys correctly for every block that did not move.

**Ctrl-Z** applies `inverse` and pushes *its* inverse onto the redo stack. The
document is byte-identical to the one before the drag, which is decision 3's
law, which is a property test.

What this example is chosen to demonstrate:

- **Pre-hover validity as a pure function.** The six-element list is the
  entire interaction model of a drag, and it is computed by a function that
  takes a document, a palette, and an id, with no browser anywhere near it.
- **Slot granularity (decision 5).** `lane_receipt` appears once, not three
  times for its three gaps, and the source slot is a legitimate target
  because dropping back where you started is not an error.
- **The command is smaller than the gesture.** A drag across the tree is four
  words, and its inverse is four words, and that is the entire undo
  implementation.
- **The editor asked the palette nothing about `myapp.notify` beyond the
  behaviour.** It called `slots/1` on each candidate parent and the
  assignability predicate on the dragged type. There is no branch anywhere on
  the string `"myapp.notify"` or `"core.parallel"`, which is the operator
  pre-decision holding under load.

---

## Amendment (2026-08-28): decision 14, what the theming surface has to contain

**Status: accepted in part (2026-08-29, unqualified direction-agent verdict under the operator campaign-014 grant, PR 85): 14a, 14b, 14c, 14d and 14e are accepted; 14f stays PROPOSED for the candidate tokens not yet declared - see the Note (2026-08-29) at the end of this record for what landed.** Drafted 2026-08-28 as a proposed amendment. This section is additive; nothing above it
is changed by it. It is drafted from what the campaign-012 editor spike (`spike/`) found
by taking a dark theme to parity and making a third, host-brand theme carry the
whole surface as a pure token override (`sb-957`, `sb-vhu`).

### Context

Decision 14 settles the *mechanism*: an `sb-` class prefix, `--sb-*` custom
properties on the canvas root each with a default, a `class` attr per
component, and no framework. The spike did not find that mechanism wanting.
Every finding below is about what the surface must **contain** for that
mechanism to be sufficient, which is a different question and one decision 14
does not currently answer beyond "colors, spacing, radii, and the
drag-highlight treatment".

The evidence is a working three-theme prototype, not an argument. `host-brand.css`
holds itself to a hard rule - a theme file may set `--sb-*` properties and may
do nothing else, no structural declaration and no `sb-` class - and every hole
below was found by that rule failing: a restyle needed something the theme file
was not allowed to do. [Correction 2026-08-29, sb-4kh: the "no `sb-` class"
half of that sentence was never literally true of the file.
`spike/css/themes/host-brand.css` does name `sb-` classes, in the two selectors
that scope the theme (`.sb-spike[data-sb-theme="host-brand"]` and
`[data-sb-theme="host-brand"] .sb-spike`). The rule the file actually holds
itself to is the one the findings below rest on: it carries no declaration
other than `--sb-*` custom properties, the `sb-` classes it names being scoping
selectors only. Found by sb-2b9; no finding in this amendment is affected.] `spike/dev/theme-audit.html` checks the rule and the
arithmetic against the real stylesheets rather than asserting them in a comment
(52 checks). Screenshots are in the private campaign journal (campaign 012
journal, private: `sb-957-13`/`-14` for the browser-chrome pair, `-10`/`-11`
for the accent layering).

### Proposed decision

**14a. A colour-token surface is not sufficient for a dark theme, and
`--sb-color-scheme` is part of the contract.** The half of a component the
browser paints - a `<select>`'s drop-down, the scrollbar troughs, the text
caret, the selection highlight, a search input's UA clear button - is reachable
by no colour token at all. A theme that restates every colour and omits this
still opens a white menu over a dark editor. The package therefore declares
`--sb-color-scheme` with a default of `light`, every theme states its own, and
the stylesheet reads it as:

```css
/* on the editor's own root element, whatever the package emits there */
.sb-editor { color-scheme: var(--sb-color-scheme); }
```

**scoped to the editor's own container, never on `:root`.** Telling the host
page which scheme it is in is the editor reaching outside its box, and decision
14's whole posture is that it does not.

This was invisible for four beads of spike work. It is proposed as a decision
rather than a note because it is the one token whose absence produces a defect
that reads as "the dark theme is half-finished" and cannot be diagnosed from
the stylesheet.

**14b. The scoped reset ships, and every selector in it is
zero-specificity on the container half.** The spike found the same bug twice.
`.sb-spike button` and `.sb-spike p` each weigh one class plus one element,
which beats any single-class component rule, so the reset silently stripped
padding, border and background off every button, input and select the
component stylesheet styled (this is what collided the five inspector tab
labels into `ConfigFindingsDatamodelCondition...`), and later stripped
`.sb-hint`'s margin, `.sb-code`'s padding, `.sb-empty`'s padding and
`.sb-pane__title`'s font size. Both symptoms are quiet, which is why the second
survived four beads.

The proposed rule, and it is mechanical enough to be a lint:

> A scoped reset may match its container only through `:where(.sb-editor)`.
> Any reset selector that matches the container as a class is a bug generator,
> because it forces every component rule above it to defend itself with an
> element qualifier that the next author will not know to copy.

Six spike rules had escaped locally by qualifying themselves
(`p.sb-datamodel__none`, `ul.sb-datamodel__list--nested`, four others); all six
dropped the qualification once the reset was `:where()`-wrapped. That is the
shape of the win: the reset stops being something component CSS has to fight.

**14c. The surface has three tiers, and a host should be able to tell which
one it is in.** Not new tokens - a statement about the ones there are, which is
what makes the surface documentable:

| Tier | What it is | What a host taking it on is doing |
|---|---|---|
| 1, the palette | `--sb-bg*`, `--sb-fg*`, `--sb-border*`, `--sb-accent*`, the status colours, `--sb-radius*`, `--sb-font*`, `--sb-space*` | making the editor look like its product; a couple of dozen lines |
| 2, the treatments | `--sb-drop-ok-*`, `--sb-gap-*`, `--sb-run-mark*`, `--sb-ghost-*`, `--sb-connector*`, `--sb-syntax-*`, `--sb-path-*`, `--sb-focus-*` | disagreeing with a specific mark without overriding a rule |
| 3, `--sb-color-scheme` | 14a | telling the browser which scheme to paint its own chrome in |

The tiering earns its place on tier 2. A mark a theme must be able to *reverse*
needs tokens of its own: `--sb-ghost-*` is three tokens rather than
`background: var(--sb-fg); color: var(--sb-bg)` in a rule precisely because
that inversion is correct in light and produces a white chip in dark. Likewise
the replayed-step ring hard-coded `2px` twice and borrowed `--sb-accent`, so a
host could not make the replay mark tellable apart from selection; it is
`--sb-run-mark`, `-width` and `-offset` now.

**14d. A palette entry may declare `accentToken`, a token NAME, and that is
the per-block-type styling seam.** Decision 14 gives a host the editor and
nothing below it: a host registering its own block types has no way to make
them look like its own without writing a rule per type, which is the special
casing decision 10 exists to prevent.

The proposal adds one optional key to `palette_entry/0`:

| Key | Default | Meaning |
|---|---|---|
| `accent_token` | `nil` | the *name* of a `--sb-*` custom property supplying this type's accent |

The renderer stamps `data-sb-block-accent` on the block's card and its palette
row and rebinds, on that element only:

```css
--sb-block-accent: var(<the declared name>, var(--sb-accent));
```

Three properties make it worth adding rather than leaving to host CSS:

- **The editor still never learns a type name.** No rule in the stylesheet and
  no branch in any module mentions a block type; two rules read
  `--sb-block-accent` (an icon tile and a card stripe) and they are the only
  two. Adding a type with its own identity adds no CSS.
- **The value is decided by the theme, never by the block type.** A descriptor
  carries a name, not a colour - the same discipline decision 10 already
  applies to `icon`, and for the same reason: a block type naming a hex value
  is deciding what it looks like in themes it has never seen.
- **It degrades.** The name is validated against an anchored pattern
  (`/^--sb-[a-z0-9]+(-[a-z0-9]+)*$/` in the spike's `theme.js`) before it
  reaches a style attribute, so a typo in a host's registry falls back to the
  editor's accent rather than injecting or producing a broken card.

Two shaping tokens go with it: `--sb-block-accent-mix` (how much of the accent
the icon tile is tinted with; the spike's dark theme raises 14% to 22%, because
14% of a pale colour over near-black is not a tint) and `--sb-block-edge` (the
stripe's width; `0` keeps the colour and drops the stripe).

The layering is the part worth keeping. The spike's `myapp.capture` points at
`--sb-accent-myapp-capture`, which light and dark resolve to the family's
`--sb-accent-myapp` - so the whole `myapp.*` group reads as one - while the
host-brand theme gives it a hotter red, so the block type that moves money
stands out from its own family. Same document, same DOM, same JavaScript, one
line in a theme file.

**14e. Token coverage is checked in both directions, and a reserved name is a
promise.** A token declared and consumed by nothing is worse than a missing
one: a host sets it, nothing moves, and there is no way to tell that from a
bug. `--sb-gap-height` and `--sb-gap-hover-bg` were both declared and dead in
the spike's first pass. So:

> The package's own check fails on **either** direction: a `var(--sb-*)`
> reference with no declaration, and a declared token no rule reads.

And the precedent set rather than the exception made: `--sb-connector-active`
was reserved for a connector state the canvas never drew. It was **retired**,
not left in place, because a name in a published surface is a commitment to
keep meaning what it says.

**14f. Candidate additions to the shipped surface, found by the spike.**
Recorded as candidates because each is a real hole the spike had to fill, and
because deciding them one at a time later is worse than deciding them together:

| Candidate | Why the spike needed it |
|---|---|
| `--sb-card-width`, `--sb-column-min-width`, `--sb-column-empty-min-width`, `--sb-rail-width`, `--sb-config-preview-max-height` | canvas sizing constants that were literals; a host with a larger type scale cannot fix a clipped card without editing a rule |
| `--sb-syntax-path`, `-keyword`, `-string`, `-number`, `-operator` | the condition editor's five roles; a syntax palette is exactly the kind of thing a host has an existing opinion about |
| `--sb-path-known`, `--sb-path-unknown` | the known/unknown path underlines - deliberately not the status colours, because "undeclared" is not an error (see the datamodel sketch on `sb-6fa`) |
| `--sb-ghost-bg`, `-fg`, `-border` | 14c's reversible inversion |
| `--sb-run-mark`, `-width`, `-offset` | 14c's distinguishable mark |
| `--sb-gap-height`, `--sb-gap-drag-height`, `--sb-gap-armed-bg` | the drag seam's height and armed fill, previously two dead tokens and a literal |
| `--sb-scroll-shadow`, `--sb-scroll-shadow-size` | the four-layer background that makes a clipped scroller say so on first paint with no scroll listener |

None of these is proposed for `palette_entry/0` or for any module's API; they
are additions to the `--sb-*` surface, which is where decision 14 says visual
opinion is allowed to live.

A judgement call the spike took and flags rather than hides: `--sb-fg-subtle`
failed 4.5:1 on the sunken surface in all three themes and was moved, and
`--sb-border-strong` (near 1.9:1) now clears 3:1 - but **`--sb-border` is
deliberately not held to a contrast ratio.** It divides two panes of one
surface; it is decoration rather than a boundary carrying information, and
holding it to 3:1 turns every pane edge into a rule. That is a design ruling,
not a measurement, and it belongs to the operator.

### Consequences

- A dark theme becomes a checkable claim rather than a visual impression: the
  theme audit can assert that every theme states `--sb-color-scheme` and every
  colour it must restate.
- The reset rule in 14b is a lint, not a convention, which is the only form it
  survives in - the bug it prevents is silent by construction.
- `accent_token` widens `palette_entry/0`, which decision 10 says is a change
  to this record and to that callback's contract. That is the deliberate
  friction decision 10 asks for, and this is a record amendment asking for it.
- Token coverage failing in both directions means adding a token ahead of the
  rule that reads it now fails the build. That is intended; 14e is the reason.
- Nothing here changes the mechanism, so a host already themed against
  decision 14 keeps working; every addition is a token with a default.

---

## Amendment (2026-08-28): decisions 10 and 13, rendering the tree and its connectors

**Status: accepted (2026-08-29, unqualified direction-agent verdict under the operator campaign-016 grant, PR 135).** Additive; decisions 10 and 13 stand as
accepted until the operator rules.

### Context

Decision 10 gives the renderer `layout` and `slot_style` and decision 13 gives
it a uniform recursion - `BlockNode` renders slots via `Slot`, `Slot` renders
children via `BlockNode`, and there is no `Group` component and no `Parallel`
component. Neither record says how the *edges between blocks* are produced,
because until something drew them there was nothing to say. The campaign-012
spike drew them, over a document 41 blocks deep at nesting depth 7 with
conditioned transitions throughout (`sb-aj5`, `sb-ad2`; canvas evidence in the
campaign journal, private: `sb-aj5-1` through `-8`).

What follows is the set of rules that made those edges legible at depth, each
of which is currently a property of one prototype and would otherwise be
re-derived - probably differently - by whoever builds the shipped canvas.

### Decision

**10a. Connectors are rendered, never authored.** Adjacency and nesting stay
the sole source of truth for what connects to what. There is no edge in the
document, no edge in the command algebra, and no gesture that creates or
deletes one. This is a restatement of ADR-0001's tree invariant at the
presentation layer, and it is written down because a canvas that draws lines is
the natural place for someone to propose making them editable, and doing so
would reintroduce exactly the reverse edge ADR-0001 refused.

**10b. The browser does the layout; geometry is measured, never computed.**
Two passes, in this order:

1. Emit the layout tree as **nested DOM** - the nesting *is* the layout. A
   block's card sits inside its parent's slot box, columns are a grid, a lane
   is a column.
2. Measure what the browser laid out, and draw the connectors over it as SVG.

Nothing in the renderer computes a coordinate. This is the decision that keeps
the recursion in decision 13 uniform: a layout engine that positioned cards
itself would need to know how much room a group takes, which is a per-shape
question, which is how a `Parallel` component gets born. Measuring instead
means the two components decision 13 names stay the only two, and it means
natural CSS behaviour - a column growing to its content - is free rather than
something the layout engine has to reimplement.

The consequence worth stating: **columns take their natural height**, and
equalizing them is not attempted. A lane with two steps beside a lane with nine
is honest about that, and forcing a common height either stretches the short
lane's connectors into a lie about spacing or introduces a scroll region inside
a lane.

**10c. A boundary box is drawn for a container with a secondary slot, and for
nothing else.** Decision 10 gives `slot_style: :secondary` for interrupt rails.
The spike found the same metadata answers a second question: an interrupt rule
is *about a region*, so a rule attached to a body needs that body to have a
visible edge, and drawing a box around every container instead turns a
depth-7 document into nested rectangles that read as noise.

So `slot_style` with any `:secondary` entry both places the rail and marks the
container as a boundary. One piece of metadata, two renderings, no type name -
which is the property decision 10 exists to preserve.

[Correction 2026-08-29, sb-4kh: 10c's "and for nothing else" is superseded by
amendment 10h, accepted 2026-08-29. The boundary is now derived from the **rail
partition**, not from `:secondary` specifically: a container is a boundary box
if **any** of its slots declares a rail style, `:secondary` and `:failure`
alike. 10c's stated reason - an attached rule is about a region, so the region
needs a visible edge - is unchanged and is what 10h extends; only the set it
ranges over widened.]

**10d. A fan lands on the column header, not on the first card.** Where one
block's edge fans out to several - a branch's arms, a parallel's lanes - each
edge terminates at the top edge of the arm or lane column, not at the first
card inside it. An empty arm therefore still has a visible edge arriving at it,
which is the case an author most needs to see, and a column whose first child
is a nested group does not have its edge disappear into that group's chrome.

**10e. Guard-line reservation is per-arm-row, not per-arm.** An arm's condition
renders as a pill above the arm's column (derived from an `:expression` config
field keyed by the slot name, per decision 10's existing metadata). Vertical
space for that pill is reserved across **all** arms of one branch, whether or
not each arm has a condition - so the arms' first cards align, and `otherwise`
does not sit one line higher than its siblings. Without the reservation the row
of cards under a branch is ragged in a way that reads as a rendering bug.

**10f. Open question, put to the record rather than guessed: an interrupt
rule's outcome is invisible at the edge level.** `core.on_event` carries an
`outcome` of `abandon` or `resume` (ADR-0002 decision 10). The spike draws
every interrupt exit edge uniformly to the container's exit and shows the
outcome only on the rail card, so abandon and resume look identical on the
canvas - which is a real loss, because "does this rule end the group or return
to it" is the question an author reading the picture is asking.

The spike declined to fix it, and the reason is the proposal: routing the two
differently means the renderer reading `config["outcome"]` and branching on its
value, which is a presentational heuristic over a config key of one core type -
a type-name branch wearing a different hat. The clean fix is metadata:

> A block type may declare, per statically-named slot, that its rule blocks
> carry an **outcome** - a declared key whose value the renderer may route on
> without knowing which type declared it.

That is a genuine widening of decision 10's metadata table and is deliberately
left as a question rather than drafted as a table row, because the right shape
depends on whether any second consumer for it exists. **Operator's call.**

### Smaller items folded in here

**The d12-versus-assignability seam. RULED 2026-08-28: d12's prose was the
error.** Decision 12 originally said reordering blocks *within* an unresolvable
block's existing slots is permitted, since order asks the parent's type
nothing. The shipped `droppable_slots/3` (decision 5, rule 1) excludes an
unresolvable parent outright - it needs `slots/1`, and there is none - and its
return type, a list of `{block_id, slot_name}`, cannot express "this slot, but
only for blocks already in it". The spike mirrors the shipped code and
therefore does not offer the reorder. Two options were put, both coherent:
amend d12's prose to say the reorder is not offered, making the enumeration
correct as written; or extend the enumeration so a slot may be returned with a
restriction, widening `droppable_slots/3`'s return type - and therefore its
callers and its tests - to carry a case that exists for exactly one situation.

The operator took the first: the trade is a smaller contract against a stated
capability the author cannot actually reach, and the capability loses.
Decision 12's sentence is amended above to say the reorder is not offered,
while keeping order-asks-the-parent's-type-nothing as the reason the door
stays open - the principle forbids nothing, so an enumeration that later
expresses the reorder is an additive extension of decision 5 rather than a
reversal. Filed and applied at `sb-cvo`; the divergence note next to the
spike's own d12 test suite (`sb-ad2`) now cites this ruling.

**Decision 11's severity set: `:info` proposed, open.** The spike's findings
pane renders a third severity for advisory rows that read wrong in warning
chrome. Every one of them is `origin: "demo"` - **no validation path produces
one** - so this is a proposal about the record, not a reading of it. It has now
been sighted twice from different directions: the findings pane wanted it, and
the datamodel pane's undeclared-path advisories were deliberately kept *out* of
findings for the same reason (a findings entry is a claim that something is
wrong, and a host may legitimately carry values it has not described). Whether
the answer is a third severity or a second channel is the question; either way
it is one decision, not two. **Operator's call.**

**Decision 9's `:duration` control: the escape hatch is evidence, not
decoration.** Decision 9 says `:duration` emits an ISO-8601 string through a
structured value/unit control so the author does not have to know that. The
spike built the control and found the obvious limit: a value/unit pair cannot
express `PT1H30M`. It shipped an "edit as ISO-8601" escape hatch beside the
control. The shipped editor needs the same decision made deliberately - a
compound control, an escape hatch, or a documented refusal of durations that
are not one unit.

### Consequences

- 10b makes the canvas's correctness a question about *measurement* rather than
  about a layout algorithm, so the parts worth testing without a browser (the
  layout model, the connector geometry as pure functions of measured boxes)
  are separable from the parts that are not, exactly as decision 13 separates
  the view model from the components.
- 10c, 10d and 10e are legibility rules that cost nothing to honour and are
  invisible until violated; writing them down is the only way they survive a
  reimplementation.
- 10f, if taken, widens `palette_entry/0` a second time. Taking 10f and 14d
  together is one contract change to that callback rather than two.
- Nothing proposed here adds a component. Decision 13's `BlockNode`/`Slot`
  recursion renders every structural idiom the spike exercised - sequences,
  groups, branch arms, parallel lanes, interrupt rails, resumable history, and
  an unresolvable block at depth 7 - which is the strongest available evidence
  that decision 13's uniformity holds under load.

[Note 2026-08-29: campaign 016 implements this section - sb-otg carries the
tier-2 layout (narrow centred cards, measured SVG connectors, ONE OF / ALL OF
pills, insertion markers) and sb-8yb carries the boundary box of 10c.]

---

## Note (2026-08-28): decision 14, config chips carry no accent

A dated note rather than a proposed decision, because it ratifies a deletion
rather than asking for anything. It belongs to the 14d lane above - the
per-block-type accent seam - and records the one place that accent
deliberately does not reach.

**The rule was dead CSS for four beads.** `.sb-chip--config` carried a rule
declaring an accent tint and a medium weight, and it never painted: `.sb-chip`
is declared further down the stylesheet at equal specificity and won every one
of those properties, and the rule's `padding` was the base's value restated.
sb-p0k found the ordering while placing the card badge and reported it rather
than reviving it from inside another bead; sb-pt1's polish pass then decided
against reviving it, and the class kept its rule-free comment. What shipped
throughout, and what shipped after, is a plain muted chip.

**Every visual judgment in the spike was made against the chip that actually
rendered.** That is the whole argument, and it is why this is worth a record
rather than a code comment. Four beads of canvas work - card density, the meta
row's layout, depth-7 narrowing - were tuned looking at plain chips. sb-p0k's
badge is the sharpest case: it is a ring rather than a fill, an inset shadow
carrying no new token, and the ring was chosen **precisely so a badge would not
read like a filled config chip**. Restoring a tint would falsify the premise of
a design decision already taken, and would do it invisibly.

**The card already carries its one identity, and it is the stripe.** 14d gives a
block type an accent and spends it in two places: an icon tile and a card
stripe. A third accent-bearing element inside the same card is a second claim
on the same signal, and it lands hardest where it fits worst - the config chips
are on the interrupt rules ("Abandon", "Resume", "Deep"), whose cards already
carry the rail's warning identity, so a tinted pill inside a warning-tan card
argues with the card around it.

The class itself stays written on the card. It names what the chip *is*, and
the finding machinery and any later rule need the hook; the class having no
rule is the decision, not an oversight to be tidied away.

Recorded so the shipped editor does not re-litigate this from the stylesheet.
Restoring a tint nobody has ever seen is a new design, not a bug fix, and if
the shipped editor wants config chips to carry an accent it should decide that
looking at them.

---

## Amendment (2026-08-29): decision 10, `slot_style: :failure`

**Status: accepted (2026-08-29, unqualified direction-agent verdict under the operator campaign-014 grant, PR 69).** Drafted 2026-08-29 as a proposed amendment. Additive; decision 10 stands as accepted
and no text above this line is changed by it. It is
drafted from what campaign 013 built and the operator then ruled on: the
failure-path slot style (`sb-68b`, PR 56) and the exit-edge ruling that
followed it (`sb-67s`, 2026-08-29).

### Context

Decision 10's `slot_style` map is two-valued: a statically-named slot is
`:primary` or `:secondary`, and `:secondary` is the interrupt rail. That was
enough while the rail was the only non-body arrangement the editor drew. It
stopped being enough the moment a block type acquired a second way to finish.

`core.invoke`'s `on_error` slot is not an interrupt. An interrupt rule fires
out of band, against a region, on an event the region did not ask for. An
`on_error` subtree runs *because the call failed*, as the continuation of that
outcome, and when it finishes the enclosing parent carries on. Both were
declaring `:secondary`, so both rendered in the same dashed, warning-tinted
vocabulary, and "fires out of band" and "runs when the call fails" were
indistinguishable on the canvas (campaign-012 evidence:
`sb-pt1-onerror-vs-interrupts-light.jpg`, private journal).

The accepted ADR-0004 amendment (2026-08-29, decision 2, outcome-tagged
finals) is what makes the distinction a contract rather than a matter of
taste. Under 2c and 2d an `on_error` subtree's completion targets the block's
error-outcome final, that final raises `done.outcome.<state id>.error`, and
**the parent decides continuation; the block does not**. A failure path is
therefore in-band by construction: it ends in an ordinary completion event
that an ordinary parent transition consumes. The rendering vocabulary should
say so, and the rendering vocabulary currently says the opposite.

The spike built it and the operator ruled on the edge. Screens are in the
private campaign journal (campaign 013, cited by filename, not copied here):
`sb-68b-failure-vs-interrupt-light.jpg` and its `-dark`/`-host-brand` pair for
the two vocabularies side by side, `sb-68b-empty-failure-slot-light.jpg` and
its pair for the empty case, and `sb-ea4-failure-rail-exit-edge-light.jpg` and
its pair for the edge that contradicted the rail it left.

### Proposed decision

**10g. `slot_style` admits a third value, `:failure`.** Decision 10's table row
reads `statically-named slot to :primary or :secondary`; it would read
`statically-named slot to :primary, :secondary or :failure`. Nothing else in
the table changes, the key stays optional with a `%{}` default, and every
block type that declares no `slot_style` renders exactly as it does today.
`core.invoke` declares `slot_style: %{"on_error" => :failure}`.

`:failure` means: **an in-band continuation path taken on a bad outcome.** It
is a claim about how the slot's children are reached and what happens when
they are done, not a claim about what they contain - a failure slot holding
one notify block and a failure slot holding a nested group are the same
declaration.

**10h. What the renderer derives from the style, and nothing it derives from a
type name.** The three values partition into two questions, and keeping them
two is what stops a third value from becoming a third code path per component.

| Derived property | `:primary` | `:secondary` | `:failure` |
|---|---|---|---|
| Placement | in the body flow | attached rail | attached rail |
| Container is a boundary (10c) | no | yes | yes |
| Slot edge treatment | none | dashed, warning family | solid, error family |
| Slot card shadow | ordinary | flat | ordinary |
| Empty slot | ordinary empty affordance | dashed warning edge | solid error edge |
| Exit edge kind | flow | interrupt | flow |

Two of those rows carry the whole proposal.

*Placement and boundary are one question, asked of the rail partition.* A
container is a boundary box (amendment 10c) if **any** of its slots declares a
rail style, `:secondary` and `:failure` alike - not if it declares
`:secondary` specifically. 10c's stated reason - an attached rule is about a
region, so the region needs a visible edge - is as true of a failure path as
of an interrupt, and deriving both the rail placement and the boundary from
one partition is what kept the recursion in decision 13 from acquiring a
branch (`sb-68b`: `layoutNode.secondary` became the rail partition rather than
the `:secondary` partition, and that was the whole structural change).

*The exit edge is the second question, and the operator ruled it.* Per the
2026-08-29 `sb-67s` ruling: **a failure rail's exit renders as an ordinary
solid flow edge**, and the dashed exit channel with the interrupt arrowhead
stays exclusively interrupt-rail vocabulary. An error tint on that flow edge
is the drafter's call and carries no meaning. The ruling's grounding is the
ADR-0004 amendment quoted above: a failure path leaves through a completion
event the parent continues on, which is flow, not escape. Before the ruling
the renderer emitted the interrupt edge kind for every rail child without
reading the slot style, so a failure rail was drawn in-band and left
out-of-band in the same picture (`sb-ea4-failure-rail-exit-edge-*`).

**No component reads a type name to reach any cell of that table.** The
renderer reads the declared style; `core.invoke` declares `:failure` because
its `on_error` slot is one, and a host block type whose slot has the same
shape declares the same thing and gets the same rendering, with no editor
change. That is the property decision 10 exists to preserve, and it is the
reason this is a metadata widening rather than a special case for one core
type.

**10i. An unrecognized style resolves to `:primary`.** A `slot_style` value the
editor does not know - a host declaring against a newer record, a typo -
renders as an ordinary body slot rather than raising or dropping the slot.
This is ADR-0002 decision 3's total-resolution posture (correction 2026-08-29,
sb-4kh: was "decision 3", which reads as this record's decision 3 - the undo
stack) arriving at presentation, the
same discipline ADR-0002's amendment B3 applies to the metadata trio: a
malformed declaration in one host's registry produces the ordinary card, never
a broken one and never an exception. The children are still rendered, still
selectable, and still saved.

**10j. No new token.** Every value the failure vocabulary needs already exists
in the error family the theme surface carries (`--sb-error`, `--sb-error-bg`,
and the ordinary card shadow). Declaring aliases would be three restatements
per theme of a value that already themes correctly, and amendment 14e's token
coverage runs in both directions, so an unread token fails the build. The
spike's theme audit stayed green across all three themes without one
(`sb-68b`).

### Consequences

- The two rail vocabularies become distinguishable at a glance and stay
  distinguishable at depth, which is the failure the campaign-012 screens
  recorded and campaign 013 fixed.
- The canvas and the compiled chart now agree: what ADR-0004's amendment makes
  an in-band outcome event, the renderer draws as an in-band edge.
- `slot_style` becomes a small closed vocabulary rather than a boolean in
  disguise, so 10i stops being optional - a third value means a fourth is
  possible, and a host will eventually declare one this editor does not have.
- Nothing here adds a component, and nothing here widens `palette_entry/0`'s
  key set. It is a value added to a key that already exists, which is the
  cheapest shape a rendering change can take and the reason it is proposed
  separately from 10f and 14d.
- It does not settle 10f. Whether a block type may declare that its rule
  blocks carry a routable **outcome** key is still open and still the
  operator's call; `:failure` is a slot's style, not a config-value route.

---

## Amendment (2026-08-29): decision 11, an `:info` severity

**Status: accepted (2026-08-29, unqualified direction-agent verdict under the operator campaign-014 grant, PR 69).** Drafted 2026-08-29 as a proposed amendment. Additive; decision 11 stands as accepted
and no text above this line is changed by it.

### Context

This section does not restate the case - it answers a question already put to
this record. The d10/13 amendment above, under **Decision 11's severity set:
`:info` proposed, open**, records that the campaign-012 spike's findings pane
renders a third severity, that every instance of it is `origin: "demo"`, that
the datamodel pane's undeclared-path advisories were kept out of findings for
a related reason, and that whether the answer is a third severity or a second
channel is the operator's call. Read that paragraph first; everything it says
still holds.

What this section adds is the drafted form of one of the two answers, so that
the operator is ruling on a written decision rather than on a description of
one.

### Proposed decision

**11a. `severity` admits `:info`, for advisory findings.** Decision 11's
`%Finding{}` severity field reads `:error | :warning`; it would read
`:error | :warning | :info`. The anchor, source, and message fields are
unchanged, and the anchor stays the whole routing mechanism.

`:info` means: **this is worth the author's attention and nothing is wrong.**
That is the line decision 11 currently cannot draw. `:error` says the document
does not compile; `:warning` says it compiles and something may not behave as
intended - decision 11's own example, an invoke type with no registered
handler, is correct the moment the host registers one. Neither fits a row that
is offering information the author did not ask for and making no claim at all,
and the spike found that such rows read wrong in warning chrome.

**11b. Only `:lint` may produce it, and today nothing does.** This is the part
to state honestly rather than to leave implied.

Decision 11 says every source except `:lint` produces `:error`. That stands
unchanged: `:config`, `:arity`, `:assignability` and `:resolution` are all
claims that something is wrong, and none of them may produce an `:info`.
`:lint` is the only source that may - and **no lint produces one today.** No
validation path in the shipped package, and none in the spike, emits an
advisory finding; every `:info` row ever rendered was fixture data marked
`origin: "demo"`. This amendment therefore proposes a severity with no
producer.

That is deliberate and it is the argument's weakest point, so it is named
rather than dressed up. The case for taking it anyway is that the *rendering*
is not speculative - the pane, the anchor routing, the collapsed-subtree count
badge and the document-level panel all handle a third severity today, and the
question of what chrome an advisory row wears was answered by looking at it.
The case against is that a severity nothing emits is a contract widened on
spec, and the honest disposal of that is the operator's: **accept it as the
place a real advisory will land, or hold it until a producer exists.** The
first lint likely to need it is the unregistered-invoke-type lint decision 11
already names, and that lint is `sb-iwz`'s to place, not this record's.

**11c. What the renderer derives, and what it does not.** An `:info` finding
renders in a neutral advisory chrome, distinct from the warning family and
never in the error family. It routes by anchor exactly as the other two do, it
appears in the document-level panel, and it contributes to a collapsed
subtree's count badge - a finding that can hide inside something folded shut
is the failure mode decision 11 exists to prevent, and an advisory hides just
as well as a warning.

It changes no verdict. A document whose only findings are `:info` is exactly
as compilable and exactly as correct as one with no findings, and any consumer
gating on findings gates on `:error`, as it did before this amendment. Sorting
and grouping put `:info` last.

**11d. It does not answer the datamodel question.** The undeclared-path
advisories the datamodel pane deliberately keeps out of findings stay out. A
findings entry is a claim about the document, and a host may legitimately
carry values it has not described; whether those advisories eventually arrive
as `:info` findings or as a separate channel is a question this section leaves
exactly where the paragraph above left it.

### Consequences

- Decision 11's severity set becomes three-valued, and every existing consumer
  keeps working, because nothing emits the new value.
- The distinction between "wrong", "may not behave as intended" and "worth
  knowing" becomes expressible, which is what lets a future lint be written
  without either overstating itself or being left out of the pane.
- Accepting a severity with no producer is a real cost: it is a contract that
  cannot be exercised, and it will stay unexercised until `sb-iwz`'s lint or
  something like it lands. Holding it costs the reverse - the first lint that
  needs it arrives with a record amendment attached.
- Nothing here changes the anchor vocabulary, the source list, or the routing.
  It is one value on one field.

---

## Amendment (2026-08-29): decision 10, `slot_outcome_key`

**Status: accepted (2026-08-29, unqualified direction-agent verdict under the operator campaign-014 grant, PR 78).** Drafted 2026-08-29 as a proposed amendment. Additive; decision 10 stands as accepted
and no text above this line is changed by it. It answers the question the
d10/13 amendment above deliberately left open as **10f**, and it is drafted
from what `sb-77n` built rather than from a shape guessed ahead of the code.

### Context

10f names a real loss and declines to fix it. `core.on_event` carries an
`outcome` of `abandon` or `resume`, the canvas draws every interrupt exit edge
identically, and "does this rule end the group or return to it" - the question
an author reading the picture is asking - is therefore invisible at the edge
level. The spike refused the obvious fix because it is not the fix it looks
like: a renderer reading `config["outcome"]` and routing on its value is a
branch over a config key of one core type, which is a type-name branch wearing
a different hat.

10f proposes metadata instead, and stops there: "A block type may declare, per
statically-named slot, that its rule blocks carry an **outcome** - a declared
key whose value the renderer may route on without knowing which type declared
it." It calls the shape the operator's, because the right one depends on
whether a second consumer exists. This section takes that sentence at its word
and writes it down as a table row.

### Proposed decision

One row is added to decision 10's metadata table:

| Key | Default | Meaning |
|---|---|---|
| `slot_outcome_key` | `%{}` | statically-named slot to the config key the blocks in that slot carry their outcome under |

A block type may declare, per statically-named slot, the config key its rule
blocks carry their outcome under. It names a KEY and never an outcome value,
so a renderer routes on the value without knowing which type declared it - the
property this decision exists to preserve - and ADR-0002 amendment A2's parked
question, which outcome a given slot completion reaches, stays parked. The
declaration is read through a total normalizer under ADR-0002 amendment B3: a
non-map declaration, a non-string key, and a key or value outside the
outcome-name alphabet all read as no declared outcome, which is the uniform
rendering every consumer had before the declaration existed.

### Why a key rather than an outcome

The tempting shape is the other one - a map from slot name to the outcome that
slot's escape produces - and it is the one this section refuses. ADR-0002's
accepted amendment says so directly in section A2: "Which outcome a given
slot's completion reaches is deliberately not a third declaration", and it
records the alternative as a deferred question in that record's section F
rather than as a decision. A row here binding a slot to an outcome name would
decide, on ADR-0002's behalf and in the wrong record, the exact question that
record parked.

The `slot_style: :failure` amendment accepted earlier the same day reaches
the same reading from the other side. Its last consequence says the question
left open is "whether a block type may declare that its rule blocks carry a
routable **outcome** key" - a key, not a binding - and that `:failure` is "a
slot's style, not a config-value route". This row is that key, and it leaves
`:failure` exactly where that amendment put it.

Naming a key decides nothing about that binding. It says only where a per-BLOCK
fact lives, which is a thing the container genuinely knows about its own slot
and cannot be derived any other way: the outcome belongs to the rule block, the
container declares the slot, and the key is the only thing that joins them
without either side learning the other's type name.

### Consequences

- `slot_outcome_key` widens `palette_entry/0`, which decision 10 says is a
  change to this record and to that callback's contract. That is the friction
  decision 10 asks for, and this is a record amendment asking for it.
- A canvas may route an abandon differently from a resume. Nothing in this
  record says it must, or says what either routing looks like - 10a-10e own
  the drawing, and the value reaching them is all this row provides.
- The compiler reads none of it, and must not. ADR-0004 decision 4 keeps a
  child's config out of its parent's compile context, so a group wires both
  interrupt outcomes unconditionally and the handler picks one by raising. A
  compiler read of this key would be exactly the parent-reads-child-config
  move that record forbids; the declaration's consumer is presentational.
- Every block type that declares nothing keeps rendering exactly as before,
  and so does every type that declares this wrongly. That is B3's discipline
  arriving at one more key rather than a new posture.

---

## Note (2026-08-29): decision 14 amendment, what campaign 014 landed

A dated note, not a status change. The 2026-08-28 amendment above is still
**PROPOSED** and its Status line is untouched; this records, subsection by
subsection, what is now true in the shipped code and what is still only
written down. Two beads did the work: `sb-8dc` graduated the spike's CSS and
DOM patterns into `assets/`, and `sb-2b9` completed the token contract and the
audit. Where a subsection is true in code, the file and the test that holds it
there are named, so the reader can check rather than take this on trust.

The record is deliberately silent on whether any of it should be accepted.
That is the operator's call, and this note exists to make it a decision about
evidence rather than about a proposal.

### 14a, `--sb-color-scheme` - TRUE IN CODE

`assets/css/statifier_blocks.css` declares `--sb-color-scheme: light` on the
editor's root and reads it as `color-scheme: var(--sb-color-scheme)` on
`.sb-editor`, scoped to the container exactly as the subsection asks and
nowhere near `:root`. Both halves are asserted in
`test/statifier_blocks/theme_audit_test.exs` ("the scheme token (14a)"),
including a check that no `:root` selector appears in the stylesheet at all.

### 14b, the zero-specificity reset - TRUE IN CODE

The scoped reset ships and every descendant selector matches its container
through `:where(.sb-editor)`. The proposed rule is a lint rather than a
convention, which is the form the subsection asks for: the same test file
scans for `.sb-editor <element>` and fails on any hit, with a corroborating
test that the reset is actually present so the lint cannot pass vacuously on
an empty stylesheet.

One thing the graduation decided and the record should carry: this package's
reset does **not** strip padding, border, background and `appearance` off
controls the way the spike's did. The spike restyles its own buttons, inputs
and selects; this package leaves them native on purpose, so a reset that took
their chrome away would leave a `<select>` looking like text. What graduated
is the font inheritance, which no browser does on its own.

### 14c, the three tiers - TRUE IN CODE as of `sb-2b9`

Every token the stylesheet declares carries its tier in the file's header
comment, and `docs/theming.md` is organised around the same three tiers. It is
checked in both directions, which is what keeps a tier table from rotting: a
declared token with no tier line fails, and a tier line naming a token the
stylesheet does not declare fails.

Two things the shipped tiering settles that the subsection's table left open,
and they are extensions of its enumeration rather than readings of it:

- The canvas metrics (`--sb-column-min-width`, `--sb-rail-width`,
  `--sb-config-preview-max-height`), `--sb-disabled-opacity`, and the
  per-type accent's shaping (`--sb-block-accent-mix`, `--sb-block-edge`,
  `--sb-block-accent-tint`) are tier 2. They are not marks, but they are the
  same bargain: a thing a host may want to disagree with without overriding a
  rule.
- `--sb-block-accent` itself is tier 1. It is an accent colour with a default,
  and a host that never registers a block type of its own still inherits it
  from `--sb-accent`.

### 14d, `accent_token` - CONSUMPTION SIDE TRUE IN CODE; the declaration is elsewhere

The consumption half shipped with the graduation.
`StatifierBlocks.ViewModel.accent_token/1` validates a declared name against
the anchored pattern the subsection specifies and returns `nil` for anything
else, so a colour, a typo, or an injection attempt degrades to the editor's
accent rather than reaching a style attribute.
`StatifierBlocks.Editor.BlockNode` and `.PaletteBrowser` stamp
`data-sb-block-accent` and rebind `--sb-block-accent` on that element only.
Two rules in the stylesheet read it - the icon tile and the card stripe - and
no rule and no module names a block type.

`sb-2b9` added the check from the other end. The normalizer cannot know
whether a well-formed name means anything, and an undefined one degrades
*silently*: the block type just quietly looks like a type that declared
nothing. `StatifierBlocks.ThemeAudit.accent_token_gaps/2` reports a name
nothing defines, and the audit runs it over the registry `docs/theming.md`
documents against the tokens that document's theme defines.

What is **not** landed here: widening `palette_entry/0` in the block-type
behaviour so a host can declare the key through the registry. That is a
change to ADR-0002's callback contract and belongs to `sb-zfd`, which is in
flight in the same campaign. Until it lands, the key is consumed but not
declarable through the published palette API, and 14d is therefore half true.

### 14e, coverage in both directions - TRUE IN CODE

The audit fails on a `var(--sb-*)` reference with no declaration and on a
declared token no rule reads, with a third test asserting the scan saw the
surface at all. The precedent the subsection sets was followed rather than
described: `--sb-drop-no-opacity` was **retired** when one-sided validity
marking removed its consumer, and the 14f candidates whose consumers do not
exist in the shipped editor (the syntax roles, the path underlines, the drag
ghost, the run mark, the scroll shadows) are deliberately **not declared** -
under 14e they would fail the build.

### 14f, the candidates - PARTLY LANDED, the rest still PROPOSED

Landed, because their consumers shipped: `--sb-gap-height`,
`--sb-gap-drag-height`, `--sb-column-min-width`, `--sb-rail-width`,
`--sb-config-preview-max-height`.

Still proposed, with no consumer in the shipped editor and therefore no
declaration: `--sb-card-width`, `--sb-column-empty-min-width`, the five
`--sb-syntax-*` roles, `--sb-path-known` / `-unknown`, the `--sb-ghost-*`
trio, `--sb-run-mark` and its `-width` / `-offset`, `--sb-gap-armed-bg`, and
`--sb-scroll-shadow` / `-size`. Each arrives with the rule that reads it.

The judgement call at the end of 14f is now enforced rather than asserted.
`--sb-fg-subtle` clears 4.5:1 against the worst surface in the theme,
`--sb-border-strong` clears 3:1, and `--sb-border` is held to no ratio, with
the reason recorded beside the exemption in the test rather than only in the
stylesheet. The arithmetic is `test/support/theme_audit.ex`, a port of the
pure half of the spike's `js/theme.js`; it is test-only, ships in no release,
and takes stylesheet text rather than reading a document, which is what lets
it run in the gate instead of in Chrome by hand.

### Two things the operator may want to rule on

Neither is claimed as decided, and neither is implied by the proposal.

**A new colour held to a ratio.** The audit found `--sb-drop-ok-border` at
2.93:1 on the sunken surface and `sb-2b9` moved it to `#2c945a`. The reasoning
is 14f's own: an accepting slot's outline is the editor telling an author
where a drop will land, so it carries information and belongs with
`--sb-border-strong` rather than with `--sb-border`. That is the same kind of
design ruling 14f flagged as the operator's, arriving at one more token. The
test makes it explicit either way: every colour token must be given a
threshold or be given a recorded reason for having none, so a colour token can
no longer arrive with no ruling at all.

**Where a host theme's selector may point.** The purity rule is enforced as
"every declaration is a `--sb-*` custom property", which is the half that is
mechanical. The *selector* half needs a clarification the amendment does not
make: the package declares its defaults on `.sb-editor` itself, so a host
declaration on an ancestor loses to them however specific the ancestor's
selector is. A working host theme therefore has to name `.sb-editor` in its
selector, which sits awkwardly beside the spike's prose rule that a theme file
"may not name an `sb-` class". `docs/theming.md` documents naming it as the
supported shape; the record should either say the same or say what the
alternative hook is.

---

## Amendment (2026-08-29): decision 11, undeclared datamodel paths arrive as `:info` findings

**Status: accepted (2026-08-29, unqualified direction-agent verdict under the operator campaign-015 grant, PR 90).** Additive;
decision 11 and the accepted `:info` amendment above both stand exactly as
written, and no text above this line is edited by this section. It amends
11d, which is the only clause it touches.

### Context

11d ended with the datamodel question open, in its own words: "whether those
advisories eventually arrive as `:info` findings or as a separate channel is a
question this section leaves exactly where the paragraph above left it." The
d10/13 amendment had put the same question as a choice between a third
severity and a second channel, and named it the operator's call.

Both halves now have the same answer. The third severity is accepted - the
amendment above. This section spends it: the advisories are findings, and
there is no second channel. **The d10/13 "third severity or a second channel"
question is closed by this section; nothing further is open on it.**

It also answers 11b's honest weakness. That clause proposed a severity with no
producer, named that as the argument's weakest point, and left the disposal to
the operator: "accept it as the place a real advisory will land, or hold it
until a producer exists." This is the place, and this is the first producer.

### Decision

**11e. An undeclared datamodel path produces an `:info` finding, routed by the
same anchor as everything else.** A config field a block type has annotated as
holding a datamodel path (ADR-0002 decision 7's `datamodel_path?: true` key,
amended the same day as this section) is checked against the host-supplied
datamodel. A path the datamodel does not declare produces one `%Finding{}`:
anchor `{:config, block_id, key}` - the field's `key`, its identity per
decision 7, not its `value_path`; severity `:info`, the value the amendment
above added; source `:lint`, which 11b already fixes as the only source
permitted to produce an `:info`.

Nothing else about the finding is special. It renders in the advisory chrome
11c describes, it appears in the document-level panel, it counts toward a
collapsed subtree's badge, and per 11c it changes no verdict: a document whose
only findings are these is exactly as compilable as one with none.

**11f. Produced only when the host supplies a datamodel. No datamodel, nothing
produced.** This qualifier is the whole of what answers 11d's objection, so it
is stated as a condition on production rather than as guidance.

11d's objection was that "a host may legitimately carry values it has not
described", which makes an undeclared-path claim unfounded. It is unfounded
precisely when nothing was described. A host that hands the editor a datamodel
is making the claim itself - it is saying *these are the paths this document
may address* - and a path outside that set is then worth the author's
attention, which is exactly what 11a says `:info` means. A host that supplies
no datamodel has made no claim, and the editor makes none on its behalf.

**Absence is not unknown-ness.** With no datamodel supplied, the check does not
run, produces no findings, and reports nothing anywhere - not a quieter
severity, not an empty pane, not a "datamodel unknown" row.

The input shape is not this record's to fix. The shipped editor takes an
optional datamodel that normalizes to a set of declared paths, which is the
whole contract this check needs; the typed, scoped datamodel *document* is a
separate accepted record, ADR-0006, and the declared-path set is derivable
from it by one total function. This section is written against the set, so it
holds under either. [Correction 2026-08-29, sb-l0g: was "a separate Proposed
record (`sb-g8m`)". That record landed as ADR-0006, "The datamodel document is
a typed, three-scope declaration, and the declared-path set is its
projection", accepted 2026-08-29 (PR 101) - it names this paragraph as the
deferral it discharges. Stale status only; the deferral itself, and the
sentence that this section is written against the set, are unchanged. Note
that ADR-0006's Context quotes this paragraph in its pre-correction wording,
on purpose: it is quoting the deferral as it stood when the record was
proposed.]

**11g. Not a separate channel.** The datamodel pane grows no advisory list of
its own, and no consumer gets a second stream to merge with findings. The
findings pane is where these arrive, because the reason 11d gave for keeping
them out - a findings entry is a claim about the document - is satisfied once
11f's qualifier is in place: with a datamodel in hand the entry *is* a claim
about the document, and a well-founded one.

Worked example, signup wizard: a `core.assign` block writes to
`signup.variant`, the host supplies a datamodel declaring `signup.variant_id`
and `signup.step`, and the editor anchors one `:info` finding on that block's
`path` field saying the path is not declared. The author either fixes the
typo or extends the datamodel; nothing is blocked either way, and the document
compiles as it did before.

### Consequences

- `:info` acquires a producer, so the contract the amendment above accepted
  stops being one that cannot be exercised. `sb-iwz`'s unregistered-invoke-type
  lint remains the other candidate and is unaffected by this.
- The check is conditional on an input, which is a shape no other finding has:
  every other source produces from the document alone. That is the cost of
  11f, and it is deliberate - it is what keeps the claim well-founded.
- `sb-6b1`'s datamodel-path annotation half has a record to build against: the
  anchor, the severity, the source, and the no-datamodel behaviour are all
  fixed here rather than chosen in the editor.
- ADR-0002 decision 7 gains the annotation this depends on, in its own dated
  amendment of the same date. Neither section is useful without the other.
- Nothing changes in the anchor vocabulary, the source list, the severity set,
  or the routing. This section adds a producer and a precondition, and no
  field.

---

## Amendment (2026-08-29): decision 9, the `:duration` control

**Status: accepted (2026-08-29, unqualified direction-agent verdict under the operator campaign-015 grant, PR 91).** Drafted 2026-08-29 from an operator ruling. Additive;
decision 9 stands as accepted and no text above this line is changed by it. It
closes the open item the d10/13 amendment above left as "Decision 9's
`:duration` control: the escape hatch is evidence, not decoration".

### Context

Decision 9's field-type table renders `:duration` as a "structured value/unit
control emitting an ISO-8601 string", and the prose beneath it explains why:
ADR-0001 decision 6 forbids floats in config, so "1.5 hours" has to be
`PT1H30M`, and the control exists so the author does not have to know that.

The spike built that control and found its limit from the inside. A value/unit
pair cannot express `PT1H30M` at all, so the spike shipped an "edit as
ISO-8601" escape hatch beside the control - which is the escape hatch the
d10/13 amendment records as evidence rather than decoration, and leaves as a
question for the shipped editor: a compound control, an escape hatch, or a
documented refusal of durations that are not one unit.

The campaign-014 ruling D4 answered it for the spike: a single text control
taking predicator duration strings, with the author's string stored verbatim
and compiled to the ISO pivot at emit time (`sb-709`; `core.send` reads both
spellings). This section takes the same answer for the shipped editor, on the
operator's ruling, and writes it down as a table row so the shipped renderer
has a record to graduate against rather than a spike to copy.

### Decision

Decision 9's `:duration` row is amended to read:

| Field type | Rendering |
|---|---|
| `:duration` | one text control; predicator duration strings primary, with on-screen examples |

The row's terms, in full:

- **One text control**, not a value/unit pair and not a pair with an escape
  hatch beside it. The compound control's limit is structural rather than
  incidental, and a control plus an escape hatch is two ways to say one thing
  with a rule about which wins.
- **Predicator duration strings are primary**, with the examples on screen:
  `30s`, `15m`, `1h30m`, `2d`, `3d8h`. They are the form a person types, and
  showing them beside the field is what replaces the affordance a unit
  dropdown used to carry.
- **ISO-8601 is still accepted.** It is the spelling ADR-0001 decision 6
  already admits into config and the one existing documents hold, so a field
  that refused it would refuse values already written.
- **Empty means the key is omitted.** A cleared field and a never-set field
  are the same value; there is no `PT0S`, and no third state for "the author
  touched this and then did not finish".
- **Format is validated inline, before the document gate.** Decision 9's rule
  that an `:update_config` command reaches the document only when
  `validate_config/1` returns `:ok` is unchanged; the inline check is the
  earlier, per-field one that tells the author which of the two spellings the
  field is failing while they are still typing it.

**The stored form is the author's string verbatim.** Whichever spelling was
typed is what `config` holds - the editor canonicalises nothing on the way in.

**Emitters compile to the ISO pivot at emit time.** A predicator string is
read through `Predicator.Duration.parse/1` and canonicalised to ISO-8601; a
stored ISO value is already at the pivot. The emitted attribute is the
shorthand form the engine reads, which is what `core.send` already does.

**Predicator owns the grammar.** Which strings parse, how a fraction expands,
how a repeated unit accumulates, what `mo` and `y` approximate: all of that is
`Predicator.Duration`'s to define, and this record cites it rather than
restating it. A grammar restated here would be a second opinion that drifts.

### Consequences

- The open item this section closes needs no separate ruling. Of the three
  shapes it put (a compound control, an escape hatch, or a documented refusal),
  the answer is none of them: the compound control is what the row stops
  requiring, so there is no longer a pair for an escape hatch to sit beside.
- The shipped `:duration` field renderer becomes this control, graduating the
  spike's rather than reimplementing it, and `core.wait` and `core.timeout`
  come to accept both spellings the way `core.send` already does. Both follow
  this record and neither precedes it.
- ADR-0002 decision 7's closed field-type set is untouched. `:duration` is
  still one of the seven types and still holds a string; what changed is how
  the editor renders it and which strings that string may be.
- ADR-0001 decision 6's no-floats rule is why the pivot is ISO and not a
  number, and it stays the reason. A predicator string with a fractional
  component normalises into whole ISO components or it does not compile;
  neither spelling puts a float in `config`.
- The verbatim stored form costs one thing and buys another. It costs a
  canonical form: two documents can hold `1h30m` and `PT1H30M` and mean the
  same span, so anything comparing durations compares the compiled value and
  not the stored bytes. It buys the author's own text surviving a round trip
  through the editor, which is the property the annotation rules in ADR-0004
  care about and the reason a `delay` attribute is not annotated.

---

## Amendment (2026-08-29): the shell arrangement - three panes and a drawer

**Status: accepted (2026-08-29, unqualified direction-agent verdict under the operator campaign-015 grant, PR 92).** Drafted 2026-08-29 from the operator layout rulings
taken in the campaign-014 decision walkthrough (walkthrough artifact
`ff7335cf`; the rulings are recorded on `sb-054`, `sb-3l1` and `sb-eb2`).
Additive; decision 13 is untouched and no text above this line is changed by
it. The rulings are recorded here under the operator's own labels - 1A, 2A, 3A,
7A, 8A - so a reader can trace each clause back to the walkthrough rather than
to this record's paraphrase.

### Context

Decision 13 names the component tree and says where the boundary between pure
and rendered falls. It does not say how those components are arranged on a
page, and until campaign 014 nothing needed it to: the shipped editor was a
canvas with an inspector beside it, and everything document-level - findings,
the truth table for a condition, the datamodel view the spike was sketching -
went into another inspector tab because that was the only place there was.

That stopped working for one measurable reason. Document-level content here is
tabular, and tables need width. A truth table for a branch in a credit-card
processing document has one row per case and one column per bound input plus
the verdicts; at the inspector's 21rem it either scrolls sideways or inverts
its column order to keep the answers on screen, and campaign 014 did the
second and then filed the inversion as a readability defect (`sb-3l1` item d).
The spike moved the table to a full-width bottom drawer (`sb-054`, PR 79) and
the defect went away, because the drawer is as wide as the editor is.

The arrangement is therefore not a styling preference. It is a claim about
what kind of content each region holds, and that claim is what this section
records so the shell graduation (`sb-832`) implements a decided shape rather
than re-deriving one.

### Decision

**1A. The shell is a grid of three columns - palette, canvas, inspector -
plus one full-width drawer row.** The drawer holds tabular, document-level
content. Three things belong there, in the order they arrive:

- truth tables, today;
- fixture runs, when the fixtures seam lands (decision 15 defers those to
  `sui-13q` and this section does not disturb that deferral - it reserves the
  drawer tab, not the feature);
- the datamodel declared-path view, per the `sb-6b1` ruling of the same date.

"Tabular" and "document-level" are both load-bearing, and together they are
the rule that decides where a future pane goes. Content that is a grid of rows
about the whole document goes to the drawer. Content that is about one block
does not, whatever its shape.

**2A. The drawer is a resizable split with a viewer-remembered height and a
collapsed strip; it is never open-or-gone.** Collapsed, it is a strip carrying
a title and a count - "Truth tables (3)" - which is what makes the content
discoverable from any state rather than only from the affordance that opens
it. The spike's cold-start gap (`sb-3l1` item e: with tables out of the
inspector, the only cold open was a per-block button on a block that owns a
table) is closed by the strip itself, and opening the drawer with no table on
the selected block shows the miss-state list as the drawer's index page.

The height is remembered per viewer. It is not remembered by the package: the
package has no viewer, and a component that persists a per-person preference
is a component that has quietly acquired a session. The resize sends a
server-side command carrying the new height and the host stores it, on the
same reasoning decision 6 uses for the drag - one round trip, the state that
matters lives where state already lives.

**3A. The inspector is about the selected block, and carries exactly Config,
Findings, Condition.** Anything about the document goes to the drawer. That is
the whole rule, and it is worth stating as a rule rather than as a list
because the list will grow and the rule will not. The document-level findings
panel decision 13 names stays a document-level panel; the inspector's Findings
tab is the selected block's findings, which is the distinction `sb-3l1` item a
turns on.

Datamodel and Fixtures, which the spike had as inspector tabs, are drawer tabs
under this rule. They were never about the selected block.

**Precision (2026-08-30, `sb-1g4q`), because 3A reads narrower than it is:**
"about the selected block" says what a tab is about, not what it does when
there is no selection. With `node: nil` the Findings tab has no block to be
about, and since `sb-dbqq` (campaign-018 ruling D1) it lists the **document's**
findings, grouped by block. That is 3A's empty state and not a fourth surface:
the moment anything is selected the tab is that block's findings again, the
document-level list an author *navigates* is still the drawer's (3A's own
sentence above: anything about the document goes to the drawer), and no tab
was added. What 3A forbids is a pane that is about two subjects at once;
what it does not require is a pane that says nothing when its subject is
missing.

**7A. Breakpoints are container queries on `.sb-editor`.** They are container
queries and not media queries because the editor is a component embedded in a
host page whose chrome the package does not control; a viewport width tells it
nothing reliable about the width it was actually given. The steps:

| Container width | Arrangement |
|---|---|
| 1280 and up | three panes plus the drawer row |
| 1024 and 900 | the palette stacks |
| 780 | the inspector stacks |
| 640 | canvas first, then the panes, then the drawer last |

Below 780 the palette collapses to a strip - search and a "+" - that opens as
a sheet, so the inspector gets the full row. The stacking order below 640 is
canvas, panes, drawer: the canvas is the document, the panes are about a
selection in it, and the drawer is about the whole document, so the order is
narrowest scope of attention first.

**8A. The package ships the editing surface; the host ships the document
chrome.** The split, stated once so a host knows what it is expected to
provide:

| Side | Surface |
|---|---|
| package | the canvas toolbar (zoom, fit width, fit active, depth and count), the tabbed inspector, the drawer, the grouped palette with descriptions |
| host | the outer header: document identity, the document switcher, the theme control, compile and publish |

The package's half is everything that operates on the document that is open.
The host's half is everything that decides which document is open or what
happens to it next - which is decision 15's existing boundary ("which palette
entries a tenant may use, who may edit or publish a document, where it is
stored, and what publishing means are all outside this package") applied to
the header rather than restated.

**How the host's half attaches: slots for markup, events for actions.** A
header region is a named slot the host fills with its own markup, because
markup is exactly the thing a host wants to own and a slot costs the package
no API surface at all. An action the host must react to - publish was pressed,
the switcher chose a document - is a documented event, because an event is a
contract the package can keep stable while the host's markup changes under it.
The two are not alternatives; the header is one of each, and a host that
renders its own publish button in a slot and receives the press as an event is
the intended shape.

### No new JavaScript

Nothing in this section adds a JavaScript hook. Decision 7 ships exactly one -
the drag hook - and the only amendment to that in flight is the read-only
measurement hook `sb-y14` records for the connector layer; this section cites
it and does not draft it. The drawer resize is a server-side command carrying
the height, which is the same round-trip discipline decision 6 sets for the
drag, and the breakpoints are container queries in CSS, which is why 7A is
written as a stylesheet rule and not as a resize observer.

The temptation is real and worth naming: a resize handle, a remembered height
and five breakpoints all look like client-side concerns, and every one of them
has a JavaScript shape that is shorter to write. The reason to refuse it is
decision 7's reason - behaviour that lives on the client is behaviour the
server cannot test and the host cannot override - and none of these three
needs the client to do anything a stylesheet and one command cannot.

### Consequences

- `sb-832` implements this: the canvas toolbar, the tabbed inspector, the
  drawer skeleton with its strip and resize, the grouped palette, and the
  breakpoints. This section is its specification and the reason it can be one
  bead rather than a design conversation.
- The drawer's tab set is open by construction and closed by rule. Truth
  tables ship first, fixture runs and the datamodel view have reserved places,
  and anything later is admitted by the 1A test - tabular and document-level -
  or it is not admitted.
- The host acquires a small obligation it did not have: it renders the header
  and it stores the drawer height. Both are stated here so a host embedding
  the editor in a signup wizard with A/B testing knows the editor will not
  draw its own document switcher and is not waiting for permission to draw
  one.
- Decision 13's component tree is unchanged. Every component this section
  arranges either exists there or is a new function component under the same
  recursion rules; nothing here makes a second stateful component and nothing
  here needs one.
- The inspector rule constrains future work in the direction this record
  wants. A pane that is about the document has one place to go, so the
  question "which inspector tab does this become" stops being asked.

---

## Amendment (2026-08-29): decision 7, a second hook that only measures

**Status: accepted (2026-08-29, unqualified direction-agent verdict under the operator campaign-015 grant, PR 100).** Additive; decision 7 stands exactly as
written and no text above this line is edited by this section. It amends the
hook count and nothing else: the drag hook, the DOM contract it depends on,
the delivery rule, and the argument for keeping every other affordance in
`phx-` bindings all survive unchanged.

### Context

Decision 7 ships exactly one JavaScript hook and says, in as many words, that
**adding a second hook requires amending this record**, "a deliberately high
bar: a second hook is the signal that some behaviour has started living on the
client, and that is the thing this design is arranged to prevent."

The proposed d10/13 amendment above then asked for something the one-hook rule
does not allow. 10b decides that **the browser does the layout and geometry is
measured, never computed**, and 10d and 10e are rules about where a measured
edge lands and how much room a guard row reserves. Every one of them needs a
number that only the browser knows: where the browser actually put a card,
a column header, or an arm row, after fonts, wrapping, and a container's
natural height have all had their say. Nothing in Elixir can produce that
number, and nothing in CSS can hand it to the server.

So the connector layer sat behind a record question rather than behind any
missing code. The campaign-012/013 spike had already proved the rules work at
depth (`spike/js/layout.js` and `spike/js/render.js`, over the same document
41 blocks deep at nesting depth 7 that the section above cites), and the
graduation bead `sb-k7r` was filed and blocked on this section.

The operator ruled on `sb-y14` (2026-08-29): amend, admitting a second hook
whose entire job is read-only measurement, and argue in the amendment why that
does not weaken decision 7's reason.

### Decision

**7a. A second hook is admitted, and its whole contract is measurement.** The
editor ships two hooks. The second one, `StatifierBlocksMeasure`:

- **reads laid-out boxes after render** - geometry the browser produced, off
  elements the server rendered;
- **pushes that geometry to the server**, and that push is the only thing it
  sends;
- **issues no commands.** It does not push an author intent of any kind:
  no `:insert`, `:move`, `:remove` or `:update`, no selection, no collapse,
  no drag event. Decision 2's closed command set is untouched by it;
- **never mutates the DOM.** It writes no node, no attribute, no style, and
  no class; it does not draw the connectors it makes drawable;
- **holds no behaviour.** No validity rule, no layout rule, no routing rule,
  and no state that survives a re-render lives inside it.

The hook is named on decision 7's own naming argument - a `StatifierBlocks`
prefix, because two packages in this family may register hooks into one host
`app.js` - and it ships as source in `assets/` under sui-ADR-0009 with the
same versioned-public-API obligations decision 7 places on the drag hook. Both
are consequences of rules already accepted here, not new choices.

**7b. The invariant decision 7 was defending is the one that holds, and it is
not the count.** The count was the proxy. The rule underneath it is that
**behaviour does not move to the client**, and a measuring hook does not move
any, because it produces an *input* rather than a *decision*.

The distinction is sharp enough to check. `StatifierBlocksDrag` reports an
author's intent, and what it reports changes the document: a drop is a `:move`.
`StatifierBlocksMeasure` reports a fact about the rendering the server just
produced, and what it reports changes no document, no command, no validity
verdict and no finding. Feed it a different measurement and the same document
comes back; feed the drag hook a different drop and a different document does.
That is the whole difference between input and behaviour, and it is why the
second hook cannot become the thing the one-hook rule feared: there is nothing
for behaviour to hide in, because the hook decides nothing and remembers
nothing.

Three properties follow, and each is a check on 7a rather than a new rule:

1. **The geometry the hook pushes is authoritative about pixels and about
   nothing else.** The server may route a connector with it. The server may
   not learn from it what a block *is*, where it *belongs*, or whether a drop
   is legal - those stay where decisions 2, 5 and 6 put them.
2. **The connector geometry itself is computed on the server**, as pure
   functions from measured rectangles to path data. That is exactly the split
   the spike's `layout.js` already keeps - its geometry half takes measured
   rectangles and "know[s] nothing about blocks - a rectangle is a rectangle" -
   and it is what keeps decision 13's promise that rendering is testable
   without a browser. 10b's "geometry is measured, never computed" is untouched
   by this: what 10b forbids is *computing where a card goes*, and measuring is
   still how that is answered. Deriving a path from a box the browser already
   placed is downstream of the layout, not a second layout engine.
3. **The editor is fully usable with the hook absent.** A host that never
   imports it gets an editor that authors, validates, compiles and renders
   exactly as before, minus the drawn connectors. If anything ever stops
   working without the hook, behaviour has moved into it and this section has
   been violated - which makes the absent-hook case the standing test of 7a,
   not merely a graceful-degradation nicety.

**7c. What the hook may observe, and what it may not.** Concretely, so that
"read-only measurement" is a contract rather than a mood:

*May observe:* the rendered box of an element the server stamped as an
anchor - a block's card, a slot's children list, a column or arm header, a
rail, an outlet - and the stage's own box and scroll extent, which is what
makes the observed boxes comparable to each other. Reading is by the ordinary
browser box-measurement APIs over the DOM the server rendered; the anchors are
stamped with data attributes, which is decision 7's existing convention and
sui-ADR-0007's, extended rather than replaced.

*May push:* rectangles - a position and a size in the stage's coordinate
space, each keyed to the anchor it was read from.

*May not observe or push:* anything that is not geometry of a server-rendered
anchor. Not config values, not the text an author typed, not the contents of a
form field, not a datamodel value, not pointer positions, not timings, not
anything read from `window` beyond what is needed to make the boxes
comparable. A payload that carries author data has stopped being a
measurement, and the plainest statement of this clause is that the push should
be reconstructible from the rendering alone.

**7d. Left open on purpose, and owned by `sb-k7r`.** The ruling settled that
the hook exists and what kind of thing it is. It did not settle the wire, and
this section does not invent one:

- the **payload shape** - how a rectangle and its anchor key are spelled, and
  whether one push carries the whole stage or a delta;
- the **push cadence** - what triggers a measurement (first paint, a
  re-render, a resize, an observer) and how it is coalesced, given that the
  spike found two frames necessary before font swap and scrollbars settle;
- the **coordinate space** - what the stage-relative space is exactly, and how
  a host's own transform on an ancestor is handled. The spike's `render.js`
  found this the one place a zoom costs anything and unscales against the
  stage; whether the shipped hook does the same or pushes rendered coordinates
  and a scale is an implementation choice with a test behind it, not a record
  question;
- the **anchor attribute names** themselves, which extend decision 7's DOM
  contract and should be chosen alongside the markup that carries them.

Each is a question the shipped implementation answers with a test rather than
one this record answers by guess. If any of them turns out to force a choice
this section forbids, that is a stop and another amendment, not a quiet
widening.

### Consequences

- **The connector layer can graduate.** 10b, 10d and 10e stop being blocked on
  a record question and become an implementation with a proposal behind it;
  `sb-k7r` is unblocked and is the bead that spends this section. 10a
  (connectors are rendered, never authored) is unaffected and stays the guard
  against the reverse edge ADR-0001 refused - measuring does not make an edge
  editable, and this section adds no gesture that could.
- **The hook count stops being the invariant, and "one hook that pushes
  commands" replaces it.** That is a weaker sentence to check than "exactly
  one hook", so the burden moves to 7a's five clauses and 7b's absent-hook
  test. A third hook still requires amending this record, and a hook that
  pushes anything but geometry or a command is still a thing this record does
  not have.
- **`assets/` acquires a second entry point**, with the versioned-public-API
  obligations sui-ADR-0009 already places on the first. A host that wants
  connectors adds one more import; a host that does not, does not.
- **Decision 6's round-trip count is untouched.** Measurement is not part of
  the drag interaction: one round-trip at drag start, one at drop, zero per
  hover, exactly as written.
- **Nothing in decisions 2, 5, 8, 9, 11, 12 or 13 changes.** No command, no
  droppability rule, no keyboard path, no form, no finding, no unresolvable
  block behaviour, and no component boundary is touched by a hook that only
  reads boxes.

---

## Note (2026-08-29): decision 10, a default icon set ships as markup

A dated note rather than a proposed decision, because it decides nothing this
record has not already decided. Decision 10's `icon` seam is unchanged, and so
is decision 14's line between markup and styling. What is recorded here is
which side of that line the package's own glyphs fall on, and why the sentence
that produced the defect was read too literally.

**The sentence.** Decision 10 says `icon` is "a name, never markup", and adds
that "a host that ships heroicons renders heroicons, a host that ships nothing
gets a neutral glyph". The second clause was implemented as a `U+25A1` white
square in every tile. That is a neutral glyph in the sense the sentence meant
and a broken page in the sense a reader means: a white square is what a font
renders when it has nothing, so the shipped editor's first impression on a host
that had not yet written an icon component was of a failure to load. The
palette got no tile at all, because the `icon` attr `Editor` passes
`PaletteBrowser` was declared and never rendered.

**What ships now.** `StatifierBlocks.Editor.Icons`, inline SVG for the eleven
names `Palette.core/0` emits, used when the host passes no `icon`, and a test
holds the set to those names in both directions. A host's `icon` still wins on
every tile, on the canvas and on the palette rows alike, which is the seam
exactly as decision 10 wrote it - the default is only what resolves the name
when nobody else does.

**Why this is markup and not styling, which is the part worth recording.**
14d's rule is that a block type carries a *name* and the theme decides what it
means, so nothing that varies by theme may be baked into a component. The
glyphs do not vary by theme: every path paints with `currentColor` and the
`<svg>` fills its tile, so `.sb-node__icon` and `.sb-palette__icon` - two rules,
reading `--sb-block-accent` and `--sb-block-accent-tint`, which 14d already
governs - decide colour and size. The set adds no token, reads no token, and
names no block type. 14d is untouched, and a theme restyles the icons by
restyling the two tokens it was already restyling.

The injection argument in decision 10 is untouched too. It is about markup
arriving from a *host callback*, and this is markup this package wrote for
names this package emits. Nothing about it makes the editor accept SVG from a
palette entry, and nothing should.

**The two deliberate empty states**, because "never a white square" is only
half an answer:

- an entry that declares no icon (`icon: nil`, decision 10's default) renders
  **no tile**. A type that declared nothing is not missing something, and this
  holds for a host's component too - it is never called with a `nil` name,
  which is a narrowing of the seam a host can only benefit from;
- a name the shipped set does not have renders a **neutral mark**, three dots,
  with the name in `data-icon`. A host type declaring `icon: "credit-card"`
  gets a chip that reads as deliberate rather than as a failure, and the fix
  stays the one decision 10 already named: pass an `icon` component.

Recorded so the shipped editor does not re-derive this from the stylesheet, and
so that a later reading of "a host that ships nothing gets a neutral glyph"
does not restore the square.

---

## Amendment (2026-08-29): decision 10, the shipped `icon` names are heroicon names

**Status: accepted (2026-08-29, unqualified direction-agent verdict under the operator campaign-015b grant, PR 128).** Additive; decision 10 stands exactly as
written and no text above this line is edited by this section. It changes no
callback, no default, and no resolution rule. It names the vocabulary the
shipped names already draw from, which is the one thing every existing
sentence on the subject leaves the reader to infer.

### Context

Decision 10's table row for `icon` gives its type as "an icon *name*" (:398),
and the prose beneath it says only that "a host that ships heroicons renders
heroicons, a host that ships nothing gets a neutral glyph" (:420). The Note
(2026-08-29) above quotes that same clause (:2258).
`StatifierBlocks.Editor.BlockNode` says it the same way - "a host that ships
heroicons renders heroicons"
(`lib/statifier_blocks/editor/block_node.ex:22-23`).

Every one of those is a **conditional about the host**. None of them says what
the package's own names *are*. A reader holding only this record cannot tell
whether `bars-3` is a heroicon name or a coincidence, and that is precisely the
question a host has to answer before deciding whether prefixing is enough or a
mapping table is needed.

The README already answers it, in a code comment rather than in a record:

> `# A heroicons-style component: the name in, your markup out. The core types`
> `# name heroicons ("clock", "bars-3", "arrow-path", ...), so a host already`
> `# using them resolves every one by prefixing.`
>
> - `README.md:517-519`

and its example resolves them exactly that way:

> `<span class={[@class, "hero-" <> @name]} aria-hidden="true" />`
>
> - `README.md:525`

A convention that lives only in a README comment is a convention a reader finds
after guessing, not before.

### Decision

**10k. The `icon` names the core palette emits are heroicon outline names, and
this record says so.** `Palette.core/0` registers thirteen types, through
`core_types/0` (`lib/statifier_blocks/palette.ex:89-101`); their `icon` values,
verbatim and in registration order, are:

| Type | Declaration | `icon` |
|---|---|---|
| `core.sequence` | `lib/statifier_blocks/core/sequence.ex:58` | `icon: "bars-3",` |
| `core.group` | `lib/statifier_blocks/core/group.ex:74` | `icon: "rectangle-group",` |
| `core.branch` | `lib/statifier_blocks/core/branch.ex:153` | `icon: "arrows-right-left",` |
| `core.parallel` | `lib/statifier_blocks/core/parallel.ex:178` | `icon: "view-columns",` |
| `core.wait` | `lib/statifier_blocks/core/wait.ex:86` | `icon: "clock",` |
| `core.resumable_group` | `lib/statifier_blocks/core/resumable_group.ex:86` | `icon: "arrow-path",` |
| `core.on_event` | `lib/statifier_blocks/core/on_event.ex:118` | `icon: "bolt",` |
| `core.invoke` | `lib/statifier_blocks/core/invoke.ex:158` | `icon: "arrow-up-right",` |
| `core.raise` | `lib/statifier_blocks/core/raise.ex:94` | `icon: "megaphone",` |
| `core.assign` | `lib/statifier_blocks/core/assign.ex:136` | `icon: "inbox",` |
| `core.send` | `lib/statifier_blocks/core/send.ex:186` | `icon: "paper-airplane",` |
| `core.subchart` | `lib/statifier_blocks/core/subchart.ex:260` | `icon: "rectangle-group",` |
| `core.foreach` | `lib/statifier_blocks/core/foreach.ex:283` | `icon: "arrow-path",` |

Thirteen rows, **eleven distinct names**: `rectangle-group` is shared by
`core.group` and `core.subchart`, and `arrow-path` by `core.resumable_group`
and `core.foreach`. That is why the Note above, and the `Editor.Icons` test it
describes, count eleven and not thirteen - the count is of names, not of types.

**10l. The naming is a convention, never a dependency.** Three consequences
follow, and none of them is new behaviour:

- **A host that ships heroicons resolves every name by prefixing `hero-`**, as
  the README example does at `README.md:525`. No mapping table, no per-type
  registration, no coordination with this package's release cadence.
- **A host that ships a different icon set maps the names itself**, and the
  eleven above are the complete list it has to cover for the core palette. A
  host type declaring its own name is that host's problem, exactly as the Note
  above already says.
- **The package does not depend on heroicons.** There is no `heroicons` entry
  in `mix.exs` or `mix.lock`, and there will not be one. What ships instead is
  `StatifierBlocks.Editor.Icons`, this package's own inline SVG for the eleven
  names, used when the host passes no `icon` - the arrangement the Note above
  records. Naming the vocabulary is what lets a host predict the names; it is
  not a claim on the host's asset pipeline.

### Consequences

- **Adding a fourteenth core type with a new icon obliges two things**: the
  name is drawn from the heroicon outline set, and `Editor.Icons` gains the
  matching glyph. The Note above already holds the second half with a test in
  both directions; 10k is what makes the first half checkable by a reader
  rather than by taste.
- **A name that has no heroicon is the signal to stop**, not to invent one. The
  choice then is a different heroicon that fits, or an amendment to this
  section - the same bar decision 10 sets everywhere else.
- **Nothing in the `icon` seam moves.** `icon` is still a name and never
  markup, the host's component still wins on every tile, `nil` still means no
  tile, and decision 14's markup/styling line is untouched.
- **The README comment stops being the only statement of the convention.** It
  is now a restatement of this section rather than the sole source, which is
  the defect this amendment exists to close.

## Amendment (2026-08-30): decision 10, the presentation trio and the 24-character cap

**Status: accepted (2026-08-30, unqualified direction-agent verdict under the operator campaign-017 grant, PR 155).** Additive; decision 10 stands exactly as
written and no text above this line is edited by this section. It closes the
open item recorded in decision 10 (:407-418) - that bracket stays where it is,
as the record of the question, and this section is the answer to it.

### Context

ADR-0002's amendment B named three keys the spike's palette entries carry and
this record's decision 10 table does not: `accent_token` (a `--sb-*` custom
property *name*), `badge` (a short chip for the card header), and `join_label`
(what the join marker under a side-by-side arrangement says, as a function of
config). B1 is explicit that it does not adopt them here: "This section does
not adopt the trio into decision 10 on that record's behalf, and a host reading
only this section learns nothing about what the editor draws."

B3 is equally explicit about the length cap it leaves behind: "The cap itself
is a number ADR-0005 decision 10 should carry rather than this record; the
spike's is 24 characters for both the badge and the join marker, chosen so that
'calls the host' and 'timer' fit and a sentence does not."

Both halves have since landed in code. `palette_entry/0` in
`lib/statifier_blocks/block_type.ex` already carries `accent_token`, `badge`
and `join_label` as optional keys, `badge/1` and `join_label/2` normalize them
under B3's discipline, `StatifierBlocks.ViewModel.accent_token/1` normalizes
the third, and the cap exists as `@presentation_cap 24` with a comment saying
in as many words that it lives there only because "decision 10 carries no
number today" (`sb-zfd`). Decision 10 is the record that owns
`palette_entry/0`'s contents, so the shipped surface is currently wider than
the record that defines it, and the number that governs two of its keys is a
constant in a module rather than a decision. This section fixes both, on this
record's own behalf rather than ADR-0002's.

### Decision

**10m. The trio joins decision 10's metadata table.** Three rows are added:

| Key | Default | Meaning |
|---|---|---|
| `accent_token` | `nil` | a `--sb-*` custom-property *name*, rebound on this block's element only |
| `badge` | `nil` | a short chip on the card header |
| `join_label` | `nil` | a one-argument function of the block's config returning the word under a side-by-side arrangement's join marker |

Every default is `nil`, meaning the editor's own behaviour: its own accent, no
chip, its own word. That keeps decision 10's standing promise that a block type
omitting `palette_entry/0` entirely still renders, and it is the same shape the
`slot_style`, `slot_outcome_key` and `icon` rows already have.

`accent_token` is not new here - decision 14's 14d proposed it and the Note
above records the consumption side as true in code. What is new is that it sits
in the table that defines `palette_entry/0` rather than only in a theming
amendment, which is where a host reading for the callback's contract looks.

**10n. The cap is 24 characters, and it belongs to this decision.** `badge` and
the `join_label` return are each refused when longer than 24 characters. The
number is decision 10's, not ADR-0002's and not
`lib/statifier_blocks/block_type.ex`'s: B3 asked this record to carry it, and
this is the record carrying it. The value is the spike's, chosen so that "calls
the host" and "timer" fit and a sentence does not, and it is adopted because
two independent surfaces have now been drawn against it rather than because a
different number would be worse.

**10o. The normalizer semantics stay ADR-0002 B3's, unchanged.** Adopting the
keys adopts the discipline that already governs them: refuse, never truncate -
an over-long badge is dropped, not clipped, and one carrying a newline is
dropped, not collapsed to a space. A `join_label` that raises degrades to the
editor's own word, inside the bounded rescue B3 authorizes for exactly that
callback. This section adds nothing to that table and weakens nothing in it;
ADR-0002 keeps ownership of the semantics because `join_label` is the first
executable thing to hang off a palette entry and decision 4's purity rule is
that record's to apply.

### Consequences

- **`palette_entry/0` is wider by three keys**, which decision 10 says is a
  change to this record and to that callback's contract. The friction is the
  point: the surface a host declares against is not allowed to grow by
  accretion in a module's typespec, and this section is what makes the three
  keys that already shipped legitimate rather than merely present.
- **The cap has one home.** `@presentation_cap 24`'s comment currently says it
  lives in the module because this record carries no number; once this section
  is accepted the comment is stale and should point here instead. That is a
  code-comment follow-up, not a behaviour change - the value is identical.
- **A fourth presentation key is a fourth amendment.** The bar decision 10 sets
  everywhere else is unchanged by having cleared three at once.
- **ADR-0002 B1's refusal is honoured rather than overridden.** B1 declined to
  adopt the trio on this record's behalf; this record adopts it on its own,
  which is the only route B1 left open and the reason the open item sat
  undecided rather than being closed by the record that raised it.

## Amendment (2026-08-30): decision 11, a `:compile` source, and `:lint` may carry `:error`

**Status: accepted (2026-08-30, unqualified direction-agent verdict under the operator campaign-017 grant, PR 155).** Additive; decision 11 stands as accepted and
no text above this line is edited by this section. It closes the first of the
two open items recorded under decision 11 (:479-497); the second is closed by
the section after this one.

### Context

Building `Finding.from_compiler/2` (`sb-kmk`) and the palette-aware slot
validation behind it (`sb-da9`) exposed a gap the open item states plainly: the
adapter maps compiler findings to a presentation source by stage - `:config` to
`:config`, `:resolve` to `:resolution`, `:structure` to `:assignability` - and
"anything else at `:error` severity is refused as `{:no_presentation_source,
finding}`". So an error raised against generated SCXML, against the document
envelope, or at any other stage has no source in decision 11's enum and cannot
render in the editor at all.

The refusal is the right refusal for the adapter to make - it declines to lie
about where a rule lives rather than guessing a bucket - but the consequence is
that a real compile error is unroutable, which is the one class of finding an
author most needs to see anchored.

The same gap reaches decision 11 from a second direction. `sb-4e0`'s
SensitivePaths refusals arrive as `{:lint, :error}` pairs, and decision 11's
prose says "every source listed above except `:lint` produces `:error`", with
`:lint` rendering "as a warning rather than an error because a document with
one is still compilable". A refusal to compile a document that reads a
sensitive path is not that: the document does not compile, and presenting it as
a warning would misstate what happened.

### Decision

**11h. `:compile` joins decision 11's `source` enum, and it is
stage-agnostic.** A finding the by-stage mapping cannot place, at any severity,
takes `source: :compile`. It says "the compiler said so" and deliberately says
nothing more: it does not name the stage, because naming the stage in the
presentation enum would make this enum grow a value every time the compiler
grows a stage, and the presentation layer has no use for the distinction. The
anchor still decides where the finding renders, exactly as decision 11 says;
`:compile` only says where the finding came from.

`from_compiler/2` may then map any unplaced compiler finding to `:compile`
instead of refusing it. The `{:no_presentation_source, finding}` refusal keeps
its meaning for inputs that are not compiler findings at all; it stops being
the answer for compiler findings at stages the mapping does not name.

**11i. `:lint` may carry `:error`.** Decision 11's "every source listed above
except `:lint` produces `:error`" is a statement about the one lint that
existed when it was written - the unregistered-invoke-type lint, which is
correctly a warning for the reason decision 11 gives. It is not a property of
the source. `:lint` is the source for rules the editor or the compiler applies
beyond schema validity, and some of those rules are refusals: a SensitivePaths
refusal is an error, and rendering it as a warning would tell an author their
document compiles when it does not.

Severity and source are therefore independent, which is what decision 11's
struct already says with two separate fields. The unregistered-invoke-type
lint's severity is unchanged and stays `:warning`.

### Consequences

- **The adapter stops refusing real errors.** The class of compile error that
  could not render in the editor now has a source, and the editor's
  document-level panel is complete in the sense decision 11 promised: no
  finding can hide, including inside something folded shut, and now also
  including inside a stage the mapping does not name.
- **The enum stops tracking the compiler's stage list.** One stage-agnostic
  value is a bound on this enum's growth, where a value per stage would have
  been a standing obligation to amend this record whenever the compiler
  changed shape.
- **`:lint` carrying `:error` is a presentation fact, not a licence.** It does
  not decide whether any particular lint belongs to the compiler or the editor
  - that is still `sb-iwz`'s, per decision 11 and decision 15 - and it does not
  make any existing lint an error.
- **`Finding.from_compiler/2` gains a mapping rule.** That is a code follow-up
  in its own bead, not a change this section makes.

That follow-up has since landed as `sb-3pv4`: rule 4 in
`lib/statifier_blocks/finding.ex` maps an unplaced compiler finding to
`:compile` instead of refusing, and `:no_presentation_source` was retained
there but no longer produced through that door. `sb-mmyj` then dropped it from
`from_compiler_error/0` under 11j's rule that a value with no producer is worse
than absent, so `{:unanchorable, _}` is the only member left; the refusal
survives on this record as history, not as a shape the code can return.

## Amendment (2026-08-30): decision 11, `:arity` leaves the source enum

**Status: accepted (2026-08-30, unqualified direction-agent verdict under the operator campaign-017 grant, PR 155).** Additive; decision 11 stands as accepted
and no text above this line is edited by this section, which supersedes the
named clauses rather than rewriting them in place - the convention every
amendment on this record follows. It closes the second of the two open items
recorded under decision 11 (:490-497).

### Context

The open item states the finding: "Slot arity and undeclared-slot violations
landed as `StatifierBlocks.SlotValidation`, reported through the compiler's
`:structure` stage, so they adapt to `:assignability`. No rule in the adapter
yields `:arity`, and no other producer exists. It remains reachable only by a
caller passing `source: :arity` explicitly to `from_compiler/2`."

An enum value no producer produces is worse than absent. A reader of decision
11 reasonably infers that arity findings arrive tagged `:arity` and writes a
presentation rule against it that will never fire, and the mismatch is
invisible until someone traces the adapter.

### Decision

**11j. `:arity` is dropped from decision 11's `source` enum.** The accepted
enum is `:config | :assignability | :resolution | :lint | :compile`, with
`:compile` added by the section immediately above. Slot arity and
undeclared-slot violations are `:assignability` findings, which is where the
adapter has always put them and what the `:structure` stage they come through
actually means.

Two passages above are superseded on this point and no other:

- Decision 11's `%Finding{}` sketch (:453) lists `:arity` in the `source`
  union. Read it without that value.
- The typespec appendix (:738) carries the same union a second time, for the
  same struct. It is superseded identically; it was always a duplicate of the
  sketch rather than a second contract.

Decision 11's prose immediately above the sketch - "arity and undeclared-slot
violations are about a slot" - stands unchanged and is now more accurate, not
less: it describes what those findings are *anchored to*, which is still
`{:slot, block_id, slot_name}`, and says nothing about which source they carry.
The open item asked whether that prose should follow the enum; the answer is
that it never depended on it.

### Consequences

- **Nothing that renders today changes.** No producer emitted `:arity`, so no
  finding moves, no anchor moves, and no presentation rule that ever fired
  stops firing.
- **`@type source` in `lib/statifier_blocks/finding.ex` is now wider than this
  record**, since it still lists `:arity`. Narrowing it is a code follow-up in
  its own bead, along with the `view_model.ex` moduledoc sentence that names
  `:arity` among the sources it does not produce. This section is deliberately
  docs-only; until that bead lands, an explicit `source: :arity` passed to
  `from_compiler/2` is still accepted by the code and is no longer a value this
  record defines.
- **The remaining four-plus-one enum is fully reachable.** `:config`,
  `:assignability` and `:resolution` come from the by-stage mapping, `:lint`
  from the lint seam, and `:compile` from everything else the compiler says -
  which is the property the two open items together were asking for.

That bead was `sb-3pv4`: `@type source` and the `view_model.ex` sentence have
since landed matching this section, and `source: :arity` is no longer a value
`source/0` admits, so passing it no longer typechecks (it is not rejected at
runtime).

## Note (2026-08-30): decision 11, the number a host reads

A dated note rather than an amendment, because decision 11 is unchanged in
every particular: what a finding is, what it is anchored to, where it renders
and which of them the editor derives are all exactly as the decision and its
amendments have them. What this records is a *reader* for a number decision 11
already implies, and the ruling about which number that is.

**The number is the drawer's.** One document had three findings numbers by
construction. The reference host's header counted the raw compiler output; the
drawer's Findings tab counted `ViewModel.findings` - the derived `:resolution`
and `:config` findings, the caller's, and 11g's datamodel advisories; the
container badges counted a per-node subtree rollup of the same list. The first
of those disagrees with the other two on every document where a block fails to
resolve or a path is undeclared, and it disagrees in the *other* direction for
a compiler finding no anchor accepts. Ruled (operator, campaign 018, D1): the
Findings tab's count is the document's findings number, and a host header shows
that number or none.

**The seam is `StatifierBlocks.Editor.findings_count/3`**, a pure function of
`{document, palette}` plus the `:findings` and `:datamodel` options, which are
the assigns of the same names and the same defaults. It returns
`Shell.findings_count/1` over `ViewModel.findings` for those inputs, and the
component's own `rebuild/1` composes its view model through the same private
function, so the host's number and the rendered number are one computation and
not two that agree.

Taking inputs rather than exposing component state is the substantive part.
The editor is a `LiveComponent`: a host holds no handle on its socket, so the
alternatives were pushing a count back through `on_change` - which is one
render late on mount and never arrives at all for a document nobody edits - or
a new callback with a new lifetime to reason about. A pure function of the
inputs the host already has is available on its first render and adds no
lifecycle. Decision 15's line holds: what the host does with the number, or
whether it shows one, stays the host's.

**Orphans are inside the number.** A finding anchored on a block the document
no longer holds renders nowhere on the canvas, and `ViewModel` keeps it in
`orphan_findings` for exactly that reason - but it is still something wrong
with this document, and a number that dropped it would let a header call a
document clean while the drawer listed the finding underneath.

No new vocabulary, no new anchor, no change to what is derived. The count in
`Editor.Findings`' own `data-findings-count` attribute is the same list
counted at its own call site; folding it into the seam is cosmetic and was
left alone deliberately, since it is markup this note does not need to move.

---

## Note (2026-08-30): decision 7, the measured `viewport` and the `fit` attr

A dated note rather than an amendment, because decision 7 and its 2026-08-29
amendment are unchanged in every particular: the editor ships two hooks, the
second one only measures, and 7a's five clauses hold as written. What this
records is two things the shipped implementation settled that the record does
not yet say out loud - one of them a wire choice 7d explicitly left open, the
other a host attr that spends what the wire now carries.

**The payload carries the scroller's box under a `viewport` key.** 7d left the
payload shape to the implementation, and `sb-6ai` chose one push per stage
carrying `stage`, `anchors` and `viewport`. The first two are the connector
half. The third is the box the stage has to *fit into*: the scroller the stage
is laid out inside, stamped `data-sb-anchor="viewport"` - a reserved key beside
the stage's own, for the same reason - and sent beside the anchors rather than
among them, because it is the one box that must not be unscaled. It lives
outside the transform, and its usable width is its content box with padding
removed, since padding is width the tree is never laid out into. Without it
`Fit width` and `Fit active` were modes with no number behind them, which is
what shipped first. This is within 7c: it is the geometry of a
server-stamped anchor and nothing else, it is reconstructible from the
rendering alone, and no author data crosses with it.

`sb-6ai` also landed the other half of `Fit active`, and it is worth recording
where it lives: a scroll position is not a document value and no stylesheet
sets one, so the server stamps the canvas with `data-sb-reveal="<n>:<block
id>"` and the **drag** hook carries the scroll out once per stamp it has not
already acted on. That is a command hook doing a command's work on an author's
press, not the measuring hook acquiring behaviour: `StatifierBlocksMeasure`
still writes nothing to the DOM and remembers nothing between renders.

**The `fit` attr (`sb-ehqn`, ruling D3).** Opening at 100% leaves a document
wider than the canvas with its right-hand columns off the edge, and the only
remedy was the author pressing `Fit width` on every document they opened.
Ruled: opening at a fit is a **host opt-in**, not a new default. The editor
takes `fit`, one of `:manual` (the default, today's behaviour), `:width` or
`:active`; an unknown value is refused into `:manual` by `Shell.fit_mode/1`,
the way `inspector_tab/1` refuses an unknown tab, so no mode reaches the DOM
that no rule and no button can leave.

What the attr does is exactly one thing: at mount it sets the mode and arms a
fit, and the **first measurement payload** spends it, running the same
computation the toolbar button runs, on the same ladder, against the same
measured `viewport`. It is spent once. The guard is *having measured*, not the
attr's value - a host re-renders for reasons of its own, and an attr that
re-fitted on each of them would throw an author back to the fit every time the
host's own header changed. After that the attr is inert, `zoom -/+` return the
canvas to `:manual` as they always have, and the editor is in the state it
would have been in had the author pressed the button. A host that never
imports the measurement hook measures nothing, so the fit is never spent: the
mode is set, the canvas is at 100%, and 7b.3's absent-hook test holds here
too.

Two consequences worth stating so they are not re-derived. Opening at
`:active` with nothing selected is today's `Fit active` with nothing selected -
the mode and nothing else, and no reveal is stamped, because a scroll the
author did not ask for is a gesture rather than an opening state. And a host
that swaps the open document into an editor that has already measured does
**not** get a second fit; the attr opens an editor, and re-opening one is a
host remounting the component. If that turns out to be the wrong line, it is a
bead and a note, not a quiet widening.

No new hook, no new command, no new anchor vocabulary, and nothing in decision
7's contract moves: the client still measures, `Shell` still decides which
step, and the stylesheet still scales.

---

## Note (2026-08-30): decision 7, the pre-fit gate on an armed fit

A dated note rather than an amendment: nothing in decision 7, its 2026-08-29
amendment, or the fit note above it changes. 7a's five clauses hold as
written and the measuring hook still writes nothing to the DOM. What this
records is one more server-stamped attr and two stylesheet rules, both of
them inside the contract already written down, and the reason the pairing
needed saying out loud.

### What the fit note left showing

Opening at a fit is spent by the first measurement payload, so between the
mount and that payload the canvas is laid out at 100%. The dead render and
the first connected render both carry `data-zoom="100"`, and the render
after them carries the fitted step. On a document wide enough to want a fit
- which is the only document a host opts in for - the author sees the whole
chart painted at full size and then snap. Campaign 018's host capture
recorded it (`w4-host-light-prefit-flash`), and it reads as a bug in the
editor rather than as a fit arriving.

That flash is not a defect in the fit note's reasoning; it is the visible
cost of what the note settled deliberately. The fit needs numbers only the
browser has, the browser has them only once the tree is laid out, and laying
the tree out is what paints the frame. Nothing moves that ordering. What is
available is holding the ink back for the one frame the ordering costs.

### Decision

**The armed fit is stamped, and the stylesheet holds the stage back under
it.** `.sb-editor` carries `data-fit-pending` for exactly as long as
`fit_pending` is armed - present in the dead render, gone in the same render
that spends the fit - and the stylesheet keeps `.sb-canvas-zoom` at
`visibility: hidden` while it is there.

Three things about that, each of them the reason a different alternative was
not taken:

- **It is `visibility`, not `display` and not `opacity`.** A hidden box is
  still laid out, and the layout is exactly what the hook measures; the
  measurement is what spends the fit. `display: none` would remove the
  layout and deadlock the state it is waiting for. `opacity` would leave the
  frame paintable and merely transparent, which is a weaker claim about a
  frame this note says should not be shown at all.
- **The attr is the server's, like every other.** It is stamped by the code
  path that arms the fit and cleared by the code path that spends it, so the
  DOM says what the assigns say and no re-render can leave a stale gate
  behind. 7a's "writes no node, no attribute, no style, and no class" is
  untouched: the measuring hook is not involved in this at all, and the gate
  is reconstructible from the rendering alone.
- **The gate follows the arming, not the outcome.** `:active` with nothing
  selected arms a fit that moves no canvas, and it is gated all the same:
  what is being held back is the frame before a decision, not the frame
  before a change.

**A CSS-only delayed reveal ends the wait unconditionally.** A host that
never imports the measurement hook measures nothing, so it never spends the
fit - the fit note says so in as many words - and with no fallback that
host's stage would be gated forever. Blank is a worse failure than unfitted,
and it would be a new failure introduced into a configuration that works
today. So the same rule carries `animation: sb-fit-reveal 1ms linear 500ms
forwards`, over a keyframe whose only declaration is `visibility: visible`.
It fires once, half a second after the attr appears, and it is a floor
rather than a schedule: a host that did import the hook has measured long
before it, and the rule has stopped matching by then.

The reveal is CSS because the alternative is a timer, and a timer is
behaviour. A `Process.send_after` in the component would make a render
depend on wall-clock time and give every mount a message to schedule and to
drain; a timer in the hook would be 7a's "holds no behaviour" breaking in
the one hook that is allowed none. An `animation` is a declaration in a
stylesheet a host can read, override and diff, which is what the zoom ladder
beside it is too.

### Consequences

The hook-less host is unchanged in every way an author can name but one: its
stage appears half a second after the rest of the editor, at 100%, with the
mode set. That is the state the fit note already describes, arriving a
little later, and the cost is paid only by a host that opted into a fit
without importing the hook - which is the pairing the README's registration
section already tells a host not to build.

A host that overrides the gate rule away gets the flash back and nothing
else moves: the attr is inert to everything except the stylesheet. A host
that overrides the keyframe away and has no hook gets a stage that never
appears, and that is the one combination a theme must not ship.

No new hook, no new command, no new anchor vocabulary and no new state: one
attr the server already had a value for, and two rules in the section that
already scales the canvas.

---

## Note (2026-08-30): decision 7, a document the host swaps in is another opening

A dated note rather than an amendment, and it is the note the fit note above
asked for by name. Decision 7 is unchanged, its 2026-08-29 amendment is
unchanged, and the pre-fit gate note is unchanged: no clause of 7a moves, the
measuring hook still writes nothing to the DOM, and the gate rule and the
delayed reveal are the same two stylesheet rules that note recorded. What
changes is one sentence the fit note itself marked provisional, and what this
records is the reading that replaced it.

### The sentence this supersedes

The fit note closes on two consequences it did not want re-derived, and the
second is this:

> And a host that swaps the open document into an editor that has already
> measured does **not** get a second fit; the attr opens an editor, and
> re-opening one is a host remounting the component. If that turns out to be
> the wrong line, it is a bead and a note, not a quiet widening.

It turned out to be the wrong line, and this is the bead and the note. The
sentence stays where it is as the record of what was decided first; from here
on the rule below is what the editor does.

What was wrong with it is the noun. Everywhere else the fit note says that
what the attr opens is a *document* - it is the press an author would
otherwise make on every document they open - and then it draws the boundary
around the *editor*, so a host that keeps one editor mounted and changes which
document is in it gets the opening state for the first document and never
again. That is the whole of a host with a document switcher, which is the
shape a host that has documents to switch between actually has: the author
picks a second document, the canvas lays it out at 100%, and the affordance
the attr exists to remove is back on every switch but the first.

The alternative that sentence implies - a host remounting the component per
document - is a real option and a worse one. A remount throws away the undo
stack, the selection, the drafts and the folds together, where the shell's
`switch_document/2` (decision 2's amendment, clause 2b) decides each of them
separately and on its own reason. That separation is the reason a switch is
not a remount, so it is not something to spend on getting a fit back.

### Decision

On a change of the open document's **identity** - `Document.id` differs from
the one the editor holds, which is the test `switch_document/2` already makes
(decision 2's amendment, 2b) - the fit attr is armed exactly as it is armed
at mount:

1. What is armed is the `fit` attr the host passes **in that same update**,
   not the mode the editor happens to be holding. `:manual`, or no attr at
   all, arms nothing, exactly as at mount: a host that never opted into a fit
   does not start getting one because it changed document.
2. It is armed whether or not anything has been measured. The measurement the
   arming guard protects belongs to the document that has just left; the one
   that arrives has been measured no more than a mount's has.
3. The pre-fit gate is stamped again with it and lifts on the measurement that
   spends the fit, which is the pairing the note above records and not a
   second mechanism.
4. A re-render carrying the document already open is untouched by every clause
   above and still never re-fits. That is the guard the fit note was really
   describing, and it is the one an author notices: a host re-rendering for a
   reason of its own must not throw them back to the fit.

Read together: the fit is spent once per open document rather than once per
editor.

### Consequences

The frame after a swap is the frame after a mount, and the same two rules
cover it. The gate rule keeps the stage unpainted while a fit is armed, so the
arriving document is not painted at 100% and then snapped to its fit; the
delayed reveal bounds a swap's wait the way it bounds a mount's, so a
hook-less host that swaps documents gets the late stage that note already
describes rather than a canvas that never comes back. Neither rule is edited
here.

A host that swaps documents under `:manual` sees nothing change at all: no
attr is stamped, so there is no frame to hide and no reveal to wait for.

The cost is that an author who has zoomed the first document by hand, then
switches away and back, gets the second document at its fit rather than at the
zoom they chose. That is the right way round - the zoom they chose was chosen
against a document that is no longer on the canvas - and the zoom controls are
where they always were.

No new attr, no new command, no new anchor vocabulary and no new state. What
the editor gained is one boolean that lives for the length of a single update,
handed from the switch that already computes the identity comparison to the
arming that now needs its answer.

Implements bead `sb-e4r5`, under campaign-020 ruling D7.

---

## Amendment (2026-08-30): decision 10, the summary chip row

**Status: accepted (2026-08-30, unqualified direction-agent verdict under the operator campaign-018 grant, PR 166).** Drafted 2026-08-30 as a proposed amendment, implementing bead `sb-2mxa`. Additive; decision 10 stands exactly as
written and no text above this line is edited by this section. It answers the
question ADR-0002's amendment H deferred to this record by name: "The chip
*markup* on the card - a `.sb-node__summary` chip row rather than one joined
string - is ADR-0005's to describe and a later bead's to ship."

### Context

ADR-0002 amendment H gave a block type an optional `summary/1` returning a
string or a list of chips, and H5 put the result on the card's second line
through `ViewModel.subtitle/1`. What ships today joins a chip list with `", "`
into the one span the second line has ever had, `.sb-node__type`
(`lib/statifier_blocks/view_model.ex`, `lib/statifier_blocks/editor/block_node.ex`).
H said so in as many words and called it the deferral it was.

The join is wrong in two ways that only show on a real document. A two-chip
`core.on_event` reads `Abandon, fraud.aborted` - an outcome and an event name
punctuated as though they were one phrase - and a three-lane `core.parallel`
wraps mid-join, so the second line breaks between a comma and the chip it
belongs to. The card cannot say which of those tokens are separate facts,
because the markup does not distinguish them.

Two decisions already taken constrain the answer rather than leaving it open.
ADR-0002 B3's refuse-never-truncate discipline applies **per chip** at the
`@presentation_cap`, and it is already enforced where the view model is built
(`StatifierBlocks.BlockType.summary/2` drops an over-long or newline-carrying
chip and keeps its siblings), so a chip row draws what survived rather than
policing anything itself. And the Note above (2026-08-28, decision 14, config
chips carry no accent) already settled what a chip on this card looks like: the
card spends its one identity on the icon tile and the stripe, and a third
accent-bearing element inside it is a second claim on the same signal.

### Proposed decision

**10p. A chip list renders as a chip row, one element per chip.** The row is
`.sb-node__summary`, the name ADR-0002 H already used, and each chip is its own
inline element inside it (`.sb-node__chip`). The row is a direct child of
`.sb-node__chrome`, which is the flat-markup rule the card face is built on: a
grid places the row without a wrapper per column, and every `> .sb-node__chrome
> .sb-*` selector a host or a test already holds keeps reading the same card.

The row reads `ViewModel.Node.summary` directly, which is what H5 anticipated,
so no block type changes and nothing new is stored or serialized.

**10q. The row is the second line, so it never shares one with the type
label.** H5's rule stands untouched: the card's second line is the type's own
label when the author named the block, and the type's summary of this block's
config otherwise. The chip row is that second fact drawn as chips, and it
renders exactly where the joined string rendered - so `.sb-node__summary` and
`.sb-node__type` are mutually exclusive by construction and occupy one grid
cell. `ViewModel.subtitle/1` keeps its type-label arm and stops joining chips;
the summary arm becomes the row.

Two edges, stated rather than left to the markup: a summary of `[]` - eight of
the thirteen core types, and every type that declared none - renders **no row
at all**, not an empty element; a one-chip summary renders **exactly one chip**
and no join marker of any kind.

**10r. The row wraps, and a chip carries no accent.** The card has a fixed
width (`--sb-card-width`) and a three-lane `core.parallel` is an ordinary
document, so the row wraps to a second line rather than clipping: a clipped row
would hide a lane the slots directly underneath it still draw, and the card and
the slot list disagreeing about which lanes exist is the failure ADR-0002 H's
own `core.parallel` note exists to prevent. A chip is muted, on the theming
surface the stylesheet already declares - this section introduces no `--sb-*`
token, and the 2026-08-28 Note is why it introduces no tint.

### Consequences

- **`ViewModel.subtitle/1` narrows.** Its chip-joining arm is the thing this
  section replaces, so the function answers the type label or `nil` and the
  chips are read from the node. That is a visible change to a public function's
  return for exactly the nodes that grow a chip row, and its documentation and
  doctests move with it. Nothing else about the card face moves.
- **A card can now be taller than it was.** A wrapped chip row is two lines
  where the joined string was one, and the invoke line under it moves down with
  it. That is the same wrap the join already produced on a three-chip summary,
  landing on chip boundaries instead of inside the punctuation.
- **The cap keeps one home.** This section adds no second opinion about length:
  refusal stays ADR-0002 B3's, at the number decision 10 carries since the
  amendment above, applied where the summary is built.
- **`.sb-node__chip` is a new class and not a new token.** Decision 14's
  markup/styling line is unchanged: the class is a hook the stylesheet paints
  from the existing surface, and a host restyling it does so the way it
  restyles every other `.sb-*` element.
- **ADR-0002's deferral is discharged.** H's Consequences named this record and
  a later bead; the bead was `sb-2mxa` (2026-08-30, campaign 018), which shipped
  the markup, the stylesheet rules and the tests in the same request as this
  section.

---

## Note (2026-08-30): decision 10, the cap signals

A dated note rather than an amendment: decision 10 and the chip-row amendment
above are unchanged in every particular, the presentation cap keeps its number
and its refuse-never-truncate discipline, and no text above this line is edited
by this section. Drafted 2026-08-30, implementing bead `sb-z80a` (campaign
019). What is recorded here is a consequence of the refusal that neither record
states, and the reader the editor now has for it.

### What the refusal costs

ADR-0002 B3 refuses an over-long chip rather than clipping it, and the
amendment above adopts that per chip: "a chip row draws what survived rather
than policing anything itself". Both halves are right. The cost is that
refusing is *invisible*. A `core.parallel` whose lane is
`balance_check_and_fraud_review` draws the same card as a `core.parallel` that
declared no lanes at all, because in both cases `ViewModel.Node.summary` is
`[]` and 10q says an empty summary draws no row. The author sees a card with
one line and nothing anywhere says a second line was declared and dropped.

This is not hypothetical. Two flagship-fixture blocks in `statifier_examples`
rendered without their second line for weeks (campaign 018, `se-62u`), and
what made it survive that long is exactly this: there was nothing to notice.
A truncated chip is a rendering bug someone files; a missing chip reads as the
declaration it is, which is the property B3 wanted and is also why it hides.

### The decision

**The cap gets a reader, and refusing raises a lint.** Two additions, neither
of which touches what is drawn:

`StatifierBlocks.BlockType.summary_refusals/2` answers the chips `summary/2`
dropped, as `{index, reason}` in declaration order, with `reason` in
`:too_long | :blank | :multiline | :not_a_string` - B3's refusal set,
enumerated. The index is the position in the list the **type declared**, not in
what survived: `summary/2` has already closed the gap and cannot be indexed
against, and the author is looking at their own declaration. That index is
zero-based, as a list index is, while the position the sentence
`summary_refusal_message/3` builds counts is one-based, as a reader counting
chips does - the same split `StatifierBlocks.BlockType`'s own `@doc` on that
function records. `summary/2` and the private `chip/1` are unchanged in
behaviour and are defined against the same refusal pass, so the chips that
draw and the chips that are reported can never be computed from two readings
of one callback.

`StatifierBlocks.ViewModel.derived_findings/2` reads it once per resolved
block and emits one finding per refusal: source `:lint`, severity `:warning`,
anchored `{:block, id}`. The message names the chip's position, its length and
the cap - "summary chip 2 is 30 characters; the cap is 24, so it is not
drawn" - because those are the three facts that turn "nothing drew" into a fix,
and none of them is on the card. The sentence is built in
`StatifierBlocks.BlockType` (`summary_refusal_message/3`), which is where the
number lives; ADR-0002 amendment H's Consequences section states one number in
one place, and a sentence quoting it from the editor would be a second home
for it.

**Why `:lint` and `:warning` rather than an error.** Decision 11 reserves every
non-error severity to `:lint`, and the document compiles with an undrawn chip
exactly as it compiles without one - so an error would be a false verdict to
every consumer that gates on findings, and `:info` would understate a card that
is not saying what its type declared. `:warning` is decision 11's own reading:
"it compiles and something may not behave as intended".

**Why not widen the cap, and why not truncate.** Both were available and both
are refused here for reasons already recorded, neither of which is this
section's to revisit. Truncation is 10o's: it keeps ADR-0002 B3's
refuse-never-truncate discipline unchanged - an over-long chip is dropped, not
clipped - and says of itself that it adds nothing to that table and weakens
nothing in it. The number is 10n's, which states that it is decision 10's and
not ADR-0002's, because B3 asked this record to carry it; the value is the
spike's, chosen there so that "calls the host" and "timer" fit and a sentence
does not. This section adds no second opinion about length. It says only that a
decision the editor takes on the author's behalf should be legible to the
author.

### What this Note also names

`ViewModel.summary_chips/1` (`lib/statifier_blocks/view_model.ex`) is **the
public reader of the chip row**. The chip-row amendment above and ADR-0002's H
Note both say the chips are "read from the node", which is true and does not
name the function a host calls; a host reading `Node.summary` directly gets the
titled-card case wrong, because it is `summary_chips/1` and not the struct
field that carries 10q's rule that a named card draws the type label instead.
Naming it here is the same discipline campaign 018 applied to the findings
number a host reads. ADR-0002's H Note gains one line saying the same, so a
reader who arrives from the declaration side lands on it too.

### Consequences

- **A well-formed document is unchanged.** No refusal, no finding; the findings
  list, the drawer count and every severity a host reads are byte-for-byte what
  they were. The only documents that move are the ones that were already
  drawing less than they declared.
- **A document can now carry a `:warning` it did not before**, and the drawer's
  count includes it. That is the point, and it is why the severity matters: a
  count that grew is not a document that stopped compiling.
- **The refusal set is now public vocabulary.** `:too_long`, `:blank`,
  `:multiline` and `:not_a_string` are B3's table, named. A future refusal has
  to add a value here rather than folding into an existing one, which is the
  cost of making the set legible and is worth paying once.
- **Nothing serializes and nothing is stored.** The refusals are derived at
  build time from config that is already stored, exactly as the summary is.
- **The badge and the join marker do not get this yet.** They share `chip/1`'s
  refusal set and could carry the same signal; this section covers the summary
  row only, because that is where the silent drop was observed. Widening it is
  a bead and a Note, not something a reader should assume from this one.

---

## Note (2026-08-30): decision 12, the read-only config is an inspector surface

A dated note rather than an amendment: decision 12 is unchanged in every
particular, and what it says an author sees for an unresolvable block is what
an author sees. What this records is *where* one of its three bullets renders,
because the bullet was written when the answer was the card and the answer is
now the pane.

Decision 12's second bullet - "its config shown read-only as canonical JSON,
because there is no `config_schema/1` to drive a form and inventing one would
be guessing" - is **the inspector's Block section**, not the card's face.
Campaign-017 ruling D4 moved those bytes there, as `sb-u1j` / PR 153, which
also renamed the rule that paints them `.sb-inspector__raw-config`.
`ViewModel.Node.raw_config_json` is still built exactly as
before, from `CanonicalJson.encode_term/1` over the stored config, and it now
has exactly one reader in `lib/`:
`StatifierBlocks.Editor.Inspector`'s `block_section/1`. Nothing on the canvas
renders it.

The reason is the one decision 12's own bullet gives for the bytes being
read-only, applied to position: a stored config carries whatever the host that
wrote it carried, so on a card it made the one broken block the widest thing
in its lane. The pane an author reaches by asking about that block in
particular is where an arbitrary-length string can be shown honestly - it
wraps mid-token there, which is the only alternative to clipping bytes the
author is reading it to match.

Unchanged by this note: the bullet's content, the encoding, the fact that the
config may not be edited, and every other clause of decision 12. A card still
carries the type name, the unavailable chrome, the `:block` finding, and the
block's existing children rendered normally.

`sb-dbqq` (campaign-018 ruling D1) is the second application of the same
reasoning and is cited here so the pair is readable as one move: the pane an
author reaches by asking a question is where a long or document-shaped answer
can be given honestly. The campaign-017 ruling D4 moved the read-only config
there because a card could not hold it; `sb-dbqq` gave the Findings tab the
document's findings because a pane with no selection had nothing to hold at
all. Both leave the card and the drawer exactly as decision 12 and shell
amendment 3A ("anything about the document goes to the drawer") describe them.

---

## Note (2026-08-30): decision 11, what the "about a slot" sentence is about

Recorded because a campaign-017 direction-agent review left it as a
non-qualifying note on PR 155, and a reader who re-derives it is doing the
work twice.

The 2026-08-30 amendment that drops `:arity` from the `source` enum (11j)
keeps decision 11's prose that "arity and undeclared-slot violations are about
a slot", and keeping it was deliberate. The sentence is about the **anchor**,
not about the source value: what those findings are anchored to is
`{:slot, block_id, slot_name}`, which no amendment has touched, and what they
now carry as a source is `:assignability`, which is where
`Finding.from_compiler/2` has always put the `:structure` stage
(`lib/statifier_blocks/finding.ex`, the by-stage rule). Nothing in the
sentence ever depended on an `:arity` value existing, which is why dropping
one did not cost it anything.

One precision the sentence does not carry on its own, true in code today:
**nothing in this package constructs a `{:slot, _, _}` anchor.**
`from_compiler/2` cannot - `Compiler.Finding` carries no slot name, so the
mechanical anchor
rules produce `{:config, id, key}` or `{:block, id}` and nothing else, which
that function's own moduledoc states as a known gap. So the slot-shaped
structural findings `sb-da9` shipped (`:slot_arity_violated`,
`:undeclared_slot`) reach the editor anchored to their **block**, and a slot
anchor is a shape a caller supplies and `ViewModel` routes, not one the
compiler seam produces. The sentence describes where such a finding belongs;
the seam that would put it there is still future work.

No decision moves, no enum moves, no anchor moves. Filed with `sb-dbqq`.

---

## Note (2026-08-30): decision 11, the readers the findings surfaces share

A dated note rather than an amendment: decision 11 is unchanged in every
particular, and so is the note above it that records the number a host reads.
What this records is that the same discipline - one number computed in one
place, every surface reading it - has named readers for the rest of what a
findings surface draws, so a surface added later calls one instead of
tallying a second time.

`StatifierBlocks.Shell.severity_counts/1` is that number's breakdown. It
takes the same list `findings_count/1` takes and returns one
`%{severity: _, count: _}` per severity that has something at it, in the
order the shell orders severities, omitting a severity with nothing at it
rather than drawing a zero. Both document-level surfaces read it and neither
counts for itself.

`StatifierBlocks.Editor.Findings.severity_pills/1` is the pill row that
renders it, and both of those surfaces render *it* rather than repeating its
markup - the drawer's Findings tab and the inspector's unselected Findings
tab. That is what makes the pills sum to the count on the tab beside them by
construction rather than by agreement.

`StatifierBlocks.Editor.Findings.row/1` is the finding anatomy decision 11
describes, and its `subject` attribute is an opt-in that defaults to false: a
row names the block only where the surface around it does not already. The
document-wide list passes it; the inspector's rows do not, because the pane's
header or the group's heading is the subject there and a subject on every
line would repeat it.

`StatifierBlocks.Editor.Findings.anchor_tag/1` is a finding's anchor as the
`data-anchor` string, and both surfaces call it rather than building the
string. It is a function of the anchor alone, so a test or a host looking for
a finding's row in the DOM builds exactly what the renderer built.

Unchanged by this note: the number and the ruling that names it, what a
finding is, what it is anchored to, which severities exist, and which
surfaces render a finding. Nothing here adds vocabulary; it records which
functions are the shared readers, so the next surface reads rather than
re-derives.

---

## Amendment (2026-08-30): decision 2, a container folds shut

**Status: accepted (2026-08-30, unqualified direction-agent verdict under the operator campaign-020 grant, PR 176).** Drafted 2026-08-30 as a proposed amendment, implementing bead `sb-2vqm`. Additive; decision 2 stands exactly as
written and no text above this line is edited by this section. It ships the
control decision 2's own consequences left unbuilt, and it ships it **without
adding a command**, which is the only reason a section about folding a card
belongs to decision 2 at all.

### Context

Three places in this record already describe a folded container as something
this editor has. Decision 11 says a collapsed subtree carries a count badge
"so a finding can never hide inside something folded shut"; the `:info`
amendment (2026-08-29) says an advisory "contributes to a collapsed subtree's
count badge"; the undeclared-paths amendment (2026-08-29) says the same of an
undeclared path's finding, "and per 11c it changes no verdict". The Note
(2026-08-28) on decision 14 goes further and treats the badge's ring treatment
as a design decision already taken.

None of it was true. Nothing collapsed, so `.sb-badge` rendered on no face at
all after `sb-vamn` removed the version that painted every container's rollup,
and the stylesheet carried the class as a seam with a comment saying what the
bead that landed collapse would owe. Three sentences of this record described
an editor that did not exist, and the number they described - `findings_count`,
the subtree rollup - was already on every node waiting for a face to be read
on.

The reason it stayed unbuilt is worth stating, because it is the objection this
section has to answer. `BlockNode`'s moduledoc and the stylesheet both refused
to invent the control on the grounds that decision 2's command set is closed:
`:insert`, `:remove`, `:move`, `:update_config` and nothing else. Adding a
fifth command to hang a fold from would be deciding a piece of the interaction
model inside a presentation bead, so both refused and said so.

That refusal was right about the command set and wrong about what collapse is.

### Decision

**2a. Collapse is editor state, and decision 2's four commands are unchanged.**
The set was always the DOCUMENT's algebra - what an author does *to the
document*, serializable, invertible, replayable. Which containers this author
has folded shut is not in the document, so there is no fifth command, nothing
new on the undo stack, and nothing new serialized. `{:insert, target,
%Block{}}`, `{:remove, block_id}`, `{:move, block_id, target}` and
`{:update_config, block_id, config}` are still the whole set, and this section
adds none.

Collapse joins the selection and the palette's own fold as state the shell
holds: a `MapSet` of block ids beside `selected_id`, toggled by one server
event carrying the block id, in the shape the palette fold already has. It
touches no `Edit` function, no `Document`, and no compiler.

**2b. `switch_document/2` clears it, exactly as it clears the selection.** A
block id from the old document names nothing in the new one, so the set is
cleared on a document identity change, as the selection, the drafts and the
pending insert already are by the shell's `switch_document/2` - behaviour this
record has not stated before this amendment. The palette's own fold is the
deliberate exception it already was: that one addresses no block, so nothing
about it stops being true when a different document opens, and the reset must
not reach it.

Not persisted, in either direction: the host is told nothing, no assign
survives a remount, and there is no attr for a host to open an editor
pre-folded. A fold is a thing an author did a moment ago, not a document
property.

**2c. The collapsed face renders nothing below the chrome.** A collapsed
container carries `data-collapsed="true"` and renders **no slots region, no fan
label and no join marker** - not hidden, not `display: none`, but not rendered
at all. Three consequences follow from that and none of them is a new
mechanism: no child card exists in the markup, so the measurement hook admitted
by decision 7's amendment (2026-08-29) has nothing to measure and needs no
change; `Connectors.edges` finds no anchor and draws no edge into the subtree,
which is the missing-anchor case it already answers with `:none`; and the
container's outlet sits directly under its chrome, so the flow past a folded
container is the flow it already had.

A container with an empty subtree may still fold. What folds is the region, not
the children that happen to be in it.

**2d. Against decision 8: a folded region's drop targets are not reachable
until it is opened.** Decision 8 says every drop target is reachable without
dragging, by the "+" on its gap. That promise is about the targets an author
can see. A folded container renders none of its gaps, so none of its "+"
buttons is reachable by pointer or by keyboard while it is shut - and the way
to reach them is the fold itself, which is one control away and never hidden.
This is stated rather than left to the markup because decision 8 is otherwise
read as an unconditional claim about every target in the document.

**2e. The control is a native button on container chrome, and there is no
shortcut key.** A `<button>` carrying `aria-expanded`, so Enter and Space are
the browser's, the tab order is the document's, and no window key binding
exists. It appears on container chrome only. Its rest state is the one the
delete control already uses - revealed on hover or on selection - while the
container is open, and it is **always** visible while the container is shut,
because a control that hides a region has to be the way back to it and hover is
not a gesture a keyboard has.

**2f. The badge renders on a collapsed container with findings, as a ring.** It
carries the subtree rollup `findings_count` and it renders only where this
record has always put it: on a collapsed subtree, when the rollup is greater
than zero. Never on an open face, never at zero, and nothing else about the
rollup changes - it stays on every node for the drawer and the inspector to
read.

It is a **ring** and not a fill. The Note (2026-08-28) on decision 14 argued
that as a decision already taken - "it is a ring rather than a fill, an inset
shadow carrying no new token, and the ring was chosen precisely so a badge
would not read like a filled config chip" - against a badge nothing rendered.
This section is where that becomes a rule the browser executes.

### Consequences

- **Three sentences of this record become true.** Decision 11's collapsed
  subtree carries a count badge; the `:info` amendment's advisory contributes
  to it; the undeclared-path finding counts toward it and still changes no
  verdict. All three described a face that did not exist, and none of them
  needed editing to become correct - which is the evidence that this section
  implements the record rather than widening it.

- **`--sb-fg-on-accent` is retired, under 14e.** The badge's fill was the
  token's only consumer, and a ring whose count is `--sb-error` leaves nothing
  reading it. Amendment 14e refuses a declared token no rule reads and checks
  that in both directions, so the token cannot simply be stranded: it leaves
  the tier table, the declarations, `docs/theming.md`'s documented host theme,
  and its own contrast assertions together. That is a removal from a published
  surface. A host theme that declares it keeps compiling and keeps rendering -
  a declaration nothing reads is inert - but the name is no longer part of what
  this package documents, and the changelog says so under `Removed`.

- **A card can carry two controls where it carried one.** The fold sits beside
  the delete control on a container's chrome, in the same square, answering to
  the same reveal rule. The operator ruling of 2026-08-29 that the stylesheet
  quotes beside `.sb-node__remove` asked for exactly that pair - "`x` on hover,
  `-` + `x` on the selected card, nothing at rest" - and only the `x` half
  could ship at the time.

- **A folded container changes shape.** With nothing under its chrome it takes
  the width a leaf takes rather than the width of a body it is not drawing.
  That is a stylesheet rule about a card with no body, not a new layout mode.

- **Nothing new is asserted about the client.** Neither hook file changes.
  Collapse is markup the server rendered, which is what keeps decision 7's
  one-hook argument and its measurement amendment intact: the second hook still
  only measures, and it measures whatever is on the page.

Filed with `sb-2vqm`, under the campaign-020 rulings D1 through D6 - in order:
collapse is editor state, the reset on a document switch, the collapsed face,
the ring and the token retirement, the keyboard path, and the number the badge
reads.

---

## Amendment (2026-08-30): the shell arrangement, a fullscreen surface and a second pane fold

**Status: accepted (2026-08-30, unqualified direction-agent verdict under the
operator campaign-021 grant, PR 179).** Implements bead
`sb-flae`, from campaign-021 rulings R2 and R3. Additive; the 2026-08-29 shell
arrangement amendment stands exactly as written and no text above this line is
edited by this section, with one exception it names below: the sentence in
`StatifierBlocks.Editor.Inspector`'s moduledoc that said the inspector has no
collapse was that amendment's ruling, and campaign-021 ruling R3 is the
separate ruling it said would be needed.

### Context

The 2026-08-29 amendment decided the shell's regions and the boundary between
what the package draws and what the host draws. It did not decide the shape of
the box the host puts the whole thing in, and for as long as the editor was a
canvas with an inspector beside it that omission cost nothing: a component that
fits in a column fits wherever a host has a column.

The shell amendment's own arrangement is what ended that. Three panes plus a
full-width drawer row is not a component that sits in a page's content column;
it is a page. Every consequence of pretending otherwise has now been paid at
least once - a drawer resized against a height the host never gave it, a
container query answering about a column rather than about the editor, a
canvas that scrolls inside a pane that scrolls inside a host page. `sb-ceb`'s
bounded mode and the `--sb-editor-height` token it added are the shape of that
bill: they exist so a host CAN hand the editor a definite height, and nothing
in this record has ever said that a host SHOULD.

The second gap is smaller and is the same gap. The shell amendment gave the
palette a fold and refused the inspector one in a single sentence, on the
grounds that one pane's fold was enough of an answer to a cramped canvas. That
was a reasonable ruling against a component embedded in someone else's column,
where the editor's width is not the editor's to spend. It reads differently
against a surface that owns the viewport, where the canvas's width is the
whole of what the author has and both side panes are spending it.

### Decision

**8B. The editor assumes it owns the viewport, and a host mounts it on a
dedicated route.** This extends 8A's split rather than changing it: 8A says
which surfaces each side ships, and this says what the host's side is expected
to look like. The host's outer header, document switcher and publish controls
are chrome ABOVE a full-bleed container, and what goes in that container is the
editor at the viewport's height minus that chrome. Not a card in a content
column, not a panel in a tabbed admin page, and not a region sharing a scroll
container with anything else.

Stated as an assumption rather than as a requirement, because it is not
enforceable and should not be: `--sb-editor-height` still defaults to `auto`,
a host that drops the editor into a column still gets a working editor, and
nothing in the package inspects its own box. What changes is whose defect it
is when the drawer is off the bottom of a page. Under this clause that is the
host's mounting, not the package's layout.

**The exit link is `:header` slot content.** A fullscreen route needs a way
back out - a breadcrumb, a close control, whatever the host's application
calls it - and the package ships no such control and adds no attr for one. It
goes in the `:header` slot, which is 8A's answer already: the slot is where the
host's own markup goes, and a link back to wherever the author came from is
markup only the host can write. This is the first time this record names the
slot; it has existed in `StatifierBlocks.Editor` since the shell graduation
(the `slot(:header, ...)` declaration, and the `.sb-editor__header` element
that renders it only when the host fills it), and 8A described it in prose as
"a header region is a named slot the host fills with its own markup" without
committing to what it is called. It is called `:header`.

**Small read-only chart rendering is out of the editor's scope.** The obvious
reading of a fullscreen editor is that a host now has nowhere to show a chart
at thumbnail size - in a list of documents, in a card, beside a run. That is a
real need and it is not this component's: an editing surface that also renders
well at 200 pixels is two components wearing one name, and the compromises run
in opposite directions. The answer is a separate read-only viewer surface. It
is noted here so the question stops being asked of the editor, and it is noted
as unbuilt: nothing in this campaign or this record promises it, schedules it,
or reserves a name for it.

**Consequence: window-level keyboard bindings stop being rude.** A component
embedded in a host page may not bind window keys - it does not know what else
is on the page, and a chart editor that swallows `/` from a host's search box
is the defect that reasoning prevents. A surface that owns the viewport is the
case where it is no longer true, so the spike's keyboard layer becomes
ELIGIBLE to graduate. Eligible is the whole of the claim: it is not scheduled
here, no binding is specified here, and the one window binding the editor
already has (Escape, while a palette insert is armed) is unaffected either way.

**1B. The inspector folds, in the palette's shape.** The 2026-08-29 amendment
refused this and said a second one would be a separate ruling; campaign-021
ruling R3 is that ruling, and the answer is yes. Under 8B the canvas's width is
the author's whole budget, and 21rem of inspector is the larger of the two
things they can get back.

It is deliberately the same mechanism and not a generalisation of it. One
boolean of shell state, one server event carrying nothing, one attribute on the
pane and one on the layout, and one stylesheet template per fold combination -
no hook, no client state, no persistence, and no attr for a host to open the
editor with a pane pre-folded. Like the palette's fold it is NOT reset by a
document switch: a pane fold addresses no block, so nothing about it stops
being true when a different document opens, which is the same sentence the
2026-08-30 amendment on decision 2 writes to exempt the palette from the
collapsed-ids reset. Clause 2b of that amendment is where the document-switch
reset itself is written down, and it is the clause to cite for it: the shell
arrangement's own rulings name no part of that reset. Unlike the collapsed-ids
set, and for that reason, it is not editor state about the document at all.

3A is untouched. A folded inspector is still a pane about the selected block;
it is a pane about the selected block that is not on screen. No tab was added,
no tab was moved to the drawer, and the folded face renders no content of its
own beyond the pane's name and the control that brings it back.

### Consequences

- **One new token, and it is tier 2.** `--sb-inspector-collapsed-width` joins
  `--sb-palette-collapsed-width` in the structural tier, for the same reason
  that one exists: a rail holds a chevron and a rotated word at whatever type
  scale the host set. Two tokens rather than one shared rail width, so a host
  retuning one pane is not forced into retuning the other. Amendment 14e's
  check passes in both directions - it is declared, and exactly the fold's own
  template reads it.

- **The fold templates compose, and that is why there are three.** A folded
  palette, a folded inspector, and both folded are three grid templates at the
  1280 breakpoint, because a rule that rebound only the third column would lose
  to the palette's template whenever both panes were shut - and both shut is
  precisely the state an author reaches for on a wide document.

- **Nothing new is asserted about the client.** Neither hook file changes. The
  folded face is markup the server rendered, which is decision 7's one-hook
  argument and its measurement amendment intact for the same reason the
  container fold left them intact.

- **`--sb-editor-height` is now the documented mounting, not an escape
  hatch.** `sb-ceb` added it so a host COULD bound the editor; 8B says a host
  SHOULD. The token, its default of `auto`, and the bounded mode's behaviour
  are all unchanged - what changed is which of the two modes this record
  recommends.

- **A question this record has been answering by omission now has an answer.**
  "Where does the back link go" and "can I put this in a tab" were both
  answered case by case from 8A's prose. 8B answers them once.

Filed with `sb-flae`, under campaign-021 rulings R2 and R3 - the fullscreen
stance and the inspector's fold, in one section because they are one claim
about the shell read from two sides.

---

## Amendment (2026-08-30): the shell arrangement, the drawer's tab strip is also a host seam

**Status: accepted (2026-08-30, unqualified direction-agent verdict under the
operator campaign-021 grant, PR 186), implementing bead `sb-lpdt`, a block-B
constituent of campaign-021.** Additive; the 2026-08-29 shell arrangement
amendment stands as written and no text above this line is edited by this
section. What it qualifies, it qualifies by naming a second party rather than
by moving a rule: every clause below keeps its force over the package's own
tabs exactly as it reads today.

An amendment rather than a note, deliberately. A note records what accepted
text already meant; this section says something the accepted text does not
say, and a reader of that text alone would reach the opposite conclusion.

### Context

Two clauses of the shell amendment bear on this, and both are quoted here
rather than paraphrased because the whole of the question is what their words
cover.

The first is the summary bullet: "The drawer's tab set is open by construction
and closed by rule. Truth tables ship first, fixture runs and the datamodel
view have reserved places, and anything later is admitted by the 1A test -
tabular and document-level - or it is not admitted." It is written about the
surface unqualified. Read on its own it says that every tab the drawer will
ever carry passes through this record.

The second is 8A's table, whose package row reads "the canvas toolbar (zoom,
fit width, fit active, depth and count), the tabbed inspector, **the drawer**,
the grouped palette with descriptions", against a host row of "the outer
header: document identity, the document switcher, the theme control, compile
and publish". The drawer is on the package's side of that split, whole. So the
`:header` slot is not a precedent that carries here: the header is the host's
surface by that table, and the drawer is not.

Both are true and neither anticipated a host with content that passes 1A's own
test. A host executing the open document has one: a run feed is one row per
step about the whole document, which is what 1A admits and what the inspector
cannot hold.

### The qualification

**For a tab the host contributes, the 1A admission test transfers to the host
as its own obligation.** The package draws the tab, activates it, counts it on
the strip and gives it a panel; what goes in the panel is the host's, and
whether it is tabular and document-level is the host's judgement to make about
its own content. This is the shell amendment's existing shape, not a new one:
its consequences already state that "the host acquires a small obligation it
did not have: it renders the header and it stores the drawer height", and 8A
itself already makes host markup the host's responsibility under "slots for
markup, events for actions". The drawer gains a third item on that list.

**The package's built-in set stays governed by the bullet exactly as written.**
Truth tables and findings ship; fixture runs and the datamodel view keep their
reserved places; anything this package adds to its own tab set is admitted by
1A here, in this record, or it is not admitted. The bullet loses nothing. What
it gains is a stated scope, and 8A's package row gains one clause: the drawer
is the package's surface, and its tab strip is a seam.

**The first tenant is the examples app's run feed**, the consumer campaign-021
names for this seam. It is a different bead in a different repo and nothing in
this package knows about it.

### How it attaches

`drawer_tabs`, an assign: a list of `%{id:, title:, content:}` descriptors with
an optional `count:`, where `content` is a function component the drawer calls
when its tab is active. That is decision 9's existing seam shape, the one
`icon` and `expression_component` already use.

An assign rather than a slot, and the reason is empirical rather than
stylistic: a slot cannot carry live host content through a `LiveComponent`,
because such a component re-renders when the assigns it was passed change and
a host assign read only inside a slot body is not one of them, so an appended
step never reaches the screen. A run feed that does not move is not a run feed,
which is what settles the shape.

Two admission rules are the package's and are about the strip rather than about
content: a host tab named for one of the package's own tabs is dropped, because
that name already resolves to the package's tab and two identically titled tabs
on one strip cannot be told apart; and a repeated id is kept once, because the
id is stamped into the tab's DOM id and its panel's and a duplicate breaks the
`aria-controls` pairing for both.

### Unchanged by this amendment

Decision 1A's test, in its own words and in its own scope. 2A's five drawer
states, its strip, its per-viewer height and the resize that is a command
rather than a hook. The package's two tabs and the reserved places behind them.
3A's inspector. The component tree of decision 13, and decision 7's single
hook - a host tab adds no JavaScript.

One consequence is worth stating rather than leaving to be discovered: the
strip's unchosen-tab rule, which 2A gives as the first tab that actually holds
something, now reaches host tabs too, so a document with no truth tables, no
findings and a running feed opens on the feed. That is 2A's own reasoning about
the strip applied to a third tab, the way the 2026-08-29 findings ruling
applied it to a second.

Filed with `sb-lpdt`, as campaign-021's block-B constituent for the drawer
seam.

---

## Amendment (2026-08-31): decision 11, what feeds the declared set 11e reads

**Status: accepted (2026-08-31, UNQUALIFIED direction-agent verdict, PR 189),
implementing bead `sb-y4oa`, campaign-022's A2 under the operator's ruling of
the same day.** Drafted 2026-08-31 as a proposed amendment. Additive; 11e, 11f and 11g
stand exactly as written and no text above this line is edited by this
section. It answers a question those clauses did not ask, because at the time
they were written there was only one party who could declare anything.

An amendment rather than a note, deliberately, and for the reason the drawer
amendment of 2026-08-30 gives: a note records what accepted text already
meant, and a reader of 11e alone - "checked against the host-supplied
datamodel" - would reach the opposite conclusion from the one below.

### Context

ADR-0001's amendment of 2026-08-31 gave the block document a top-level
`datamodel` key: a list of the `<data>` roots the document's own guards and
assigns need to exist at run time. That record was careful not to decide what
the new key means here. Its clause 11g says so in as many words, and it is
quoted rather than paraphrased because the quotation is the whole of this
section's mandate:

> Whether a document-declared root should therefore **count as declared** for
> ADR-0005's 11e undeclared-path advisory is carried as an **open question,
> not decided here**: ADR-0005's 11e is written against a set the host
> supplies ("The input shape is not this record's to fix", its 11f), and
> widening what feeds that set is ADR-0005's decision to take on ADR-0005's
> record.

This is that record, and this section is that decision.

Two clauses of ADR-0001's amendment are untouched by it and are named here so
that nobody has to check. Its 11g's split between the two artifacts stands: an
ADR-0006 datamodel document describes a vocabulary, and the document's own
`datamodel` key declares that a root exists. Its 11h stands too - "It produces
no finding about an undeclared path, ever" - and it is a statement about the
key, not about this check. The producer of the advisory is 11e's and stays
11e's; nothing about the key emits a finding, before or after this section.
What changes is one input to a check that already exists, on the record that
owns it.

The reason to take the question rather than leave it carried is 11f's own
argument, applied to a second declarer. 11f grounds the advisory in a claim
somebody actually made: "A host that hands the editor a datamodel is making
the claim itself - it is saying *these are the paths this document may
address* - and a path outside that set is then worth the author's attention."
A document that declares its roots has made a claim of exactly that kind about
itself. Leaving it out does not make the advisory more careful; it makes it
wrong, and wrong in the direction 11d warned about - a document that declares
`signup` and assigns to `signup.step` would be told its own root is
undeclared, which is the unfounded claim 11f exists to prevent.

### Decision

**11k. The declared set is the union of three declarations, not one.** A path
held by a field annotated `datamodel_path?: true` is declared when any of
these says so:

  1. the host's datamodel, ADR-0006's projection or a bare path list, exactly
     as 11e has always read it;
  2. the roots the compile call's `:declare` option names (ADR-0004's
     `:declare` note, ADR-0001 11f's first precedence tier);
  3. the roots the document's own `datamodel` key names (ADR-0001 decision
     11).

Sources 2 and 3 together are what ADR-0001 11f calls the declaration
surfaces, in its precedence order. **Precedence does not reach here.** 11f's
host-wins rule decides which `<data>` element is emitted for a colliding id;
this check asks only whether an id was declared at all, and both surfaces
answer that question with the same word. A root shadowed under 11f is still a
declared root, and a `:shadowed_document_root` warning is ADR-0001's to
report, not an advisory of this record's.

**11l. A root is matched by root segment; a datamodel path is still matched
whole.** An entry in sources 2 and 3 is a bare root - ADR-0001 11g's "bare
root segment, globally addressable as itself" - so a declared root `signup`
declares `signup` and every path beneath it. Source 1 is unchanged and is
still exact-membership: a datamodel declaring `signup.step` declares
`signup.step` and says nothing about `signup.variant`.

The two rules are different because the two declarations are different
claims. A datamodel enumerates the paths a document may address, so a path it
omits is a path it excluded. A root declaration says storage exists at a name,
and says nothing at all about what is under it, so a path beneath a declared
root is not excluded by anything.

**11m. 11f's precondition widens from "a datamodel was supplied" to
"something was declared", and no further.** The check runs when the host
supplied a datamodel - `nil` still suppresses it, and an empty set is still a
claim, both exactly as 11f has them - **or** when either declaration surface
names at least one root. When nothing is declared anywhere, nothing is
produced: no advisory, no quieter severity, no empty pane, no "datamodel
unknown" row. 11f's *absence is not unknown-ness* paragraph is unchanged in
force; this clause only widens what counts as presence.

Nothing else about the finding changes. The anchor is still
`{:config, block_id, key}`, the severity is still `:info`, the source is still
`:lint`, 11g's no-second-channel rule is untouched, and 11c's rule that this
changes no verdict holds as it did.

Worked example, the same signup wizard 11g uses: the document declares the
root `signup`, the host supplies no datamodel, and a `core.assign` block
writes to `signup.variant`. Nothing is reported - the root is declared, and
the document said nothing about what lives under it. Change the block to write
to `sigunp.variant` and one `:info` finding is anchored on its `path` field:
no surface declares the root `sigunp`, so the typo is exactly the thing worth
the author's attention.

### Consequences

- **A document that declares roots can quiet a host's finer claim, and that
  is the deliberate cost.** A host declaring the path `signup.step` and a
  document declaring the root `signup` together declare all of `signup.*`, so
  the host's enumeration no longer catches `signup.variant`. 11f's priority
  is what settles it: an advisory that is well-founded and quiet beats one
  that is louder and unfounded, and the document's claim about its own roots
  is not one this package may overrule.
- **A document with no host at all now gets advisories.** Before this section
  the check was dead for every caller that supplied no datamodel; after it,
  a document that declares its own roots lints its own paths. That is the
  first case in which the producer 11e added is exercised without a host
  having to do anything.
- **The editor grows one assign**, `declare`, mirroring the compile call's
  option so the editor can read the same host roots the compiler will. It is
  a translation-only addition of the kind decision 1 permits: normalized once
  on update, concatenated once in the rebuild, with no logic of its own. Its
  default is `[]`, which per 11m declares nothing and so changes nothing for
  a host that does not pass it.
- **Nothing new is added to the finding vocabulary.** No anchor, no severity,
  no source, no field, and no second channel. This section changes one input
  and one precondition.
- **ADR-0001's 11g open question is discharged**, on the record 11g named and
  in the direction 11g's own correspondence paragraph pointed: an entry `id`
  there "is what ADR-0006's vocabulary calls a top-level `local`-scope
  entry's `path`", and a path is what this check reads.
- **ADR-0006 decision 9 is untouched.** The datamodel document is still
  advisory and still never a gate; this section adds two more advisory inputs
  beside it and gates on none of them.

---

## Amendment (2026-08-31): decision 10, `slot_style: :tray`, and a shelf that draws no connectors

**Status: accepted (2026-09-01), drafted for `sb-5h6q` under the operator campaign-024 grant; accepted on the gate's unqualified direction-agent verdict.** Additive; decisions 10 and
11 stand as accepted and no text above this line is edited by this section. It
is the editor half of ADR-0002's amendment of this date, which adds
`core.drafts` and `core.placeholder` to that record's decision 10 under
campaign-024 rulings R-a and R-b, and of ADR-0004's amendment of the same
date, which is what makes 10u a contract rather than a preference.

### The word "draft", which this record already uses for something else

Decision 9's uncommitted config-form value is a **config draft**: a per-field
value that lives while a form is open, is held in the editor's own assign, and
never reaches the document. What ADR-0002's amendment of this date adds is a
**draft fragment**: a block subtree stored *in* the document, inside a
`core.drafts` block's `body` slot, in the canonical bytes, in the document
hash and on the undo stack. They share a word and nothing else.

This section therefore says **the drafts tray** for the surface and **a draft
fragment** for what sits on it, and never "a draft" unqualified. The verb needs
the same care for a different reason: parking in this family already means
invoke run-parking (`StatifierBlocks.Core.Invoke`), which is a runtime state a
session sits in and has nothing to do with this. The rule these sections keep
is that **the thing parked is always named** - a fragment is parked in the
drafts tray, and a fragment is never an invoke run - so "a parked fragment"
reads unambiguously while a bare "parked" would not.

### 10s. `slot_style` admits a fourth value, `:tray`

The `slot_style` row of decision 10's table reads `statically-named slot to
:primary, :secondary or :failure` after the accepted 2026-08-29 amendment; it
would read `statically-named slot to :primary, :secondary, :failure or
:tray`. Nothing else in the table changes, the key stays optional with a `%{}`
default, and every block type that declares no `slot_style` renders exactly as
it does today. `core.drafts` declares `slot_style: %{"body" => :tray}`.

`:tray` means: **a shelf of children that are not in the flow at all.** It is
not a claim about what the children are - a tray holding one notify block and
a tray holding a nested group are the same declaration - it is a claim about
whether the slot's contents participate in sequencing. They do not, and
ADR-0002's amendment of this date, section G9a, is what makes that a compiler
fact rather than a rendering one.

This is a value added to a key that already exists, which is the cheapest
shape a rendering change can take and the same argument the `:failure`
amendment made for itself. No component is added and `palette_entry/0`'s key
set does not grow.

### 10t. What the renderer derives, and the partition `:tray` is not in

Amendment 10h fixed that the styles partition into two questions and that
keeping them two is what stops a fourth value from becoming a fourth code path
per component. Its table gains a column:

| Derived property | `:primary` | `:secondary` | `:failure` | `:tray` |
|---|---|---|---|---|
| Placement | in the body flow | attached rail | attached rail | detached shelf |
| Container is a boundary (10c) | no | yes | yes | no |
| Slot edge treatment | none | dashed, warning family | solid, error family | muted neutral shelf edge |
| Slot card shadow | ordinary | flat | ordinary | flat |
| Empty slot | ordinary empty affordance | dashed warning edge | solid error edge | ordinary empty affordance |
| Exit edge kind | flow | interrupt | flow | none |

Two rows carry the section.

**`:tray` is not in the rail partition, so it contributes no boundary.** 10h
made "is this container a boundary box" a question asked of the rail partition
- any slot declaring `:secondary` or `:failure` makes its container one - on
10c's stated grounds that an attached rule is about a *region* and a region
needs a visible edge. A tray is not attached to a region; it is beside the
document. Folding it into the rail partition would put a boundary box around
the root block of every document that has a shelf, which would draw a frame
around the entire workflow to say something about a shelf beside it. The
partition stays two-valued and `:tray` joins `:primary` outside it.

**The exit edge kind is `none`, and so is the entry edge, and so is every
edge between the children.** That is 10u.

### 10u. The tray draws no connectors, in or out or between

A drafts tray's children are drawn as separate cards with **no connector of
any kind**: none entering the tray, none leaving it, and - the one that
matters - **none between one fragment and the next**. The renderer must not
draw the tray as a chain.

This is a contract, not a visual preference, and the grounding is ADR-0002's
amendment of this date, section G9a. A slot's child order is ordered in the
stored bytes because ADR-0001 decision 5 makes every slot's children an
ordered list, and the tray's order is therefore stable, undoable and hashed
like any other. But G9a fixes that the compiler removes the shelf from the
flow before anything reads that order as sequencing, and ADR-0004's amendment
of this date fixes that no state, no transition and no provenance entry is
emitted for any of it. So the order in a tray is **shelf order** - where the
author put things down - and nothing downstream reads it as anything else.

An edge between two cards is this editor's whole vocabulary for "this happens
and then that happens" (decision 13, and the 2026-08-28 amendment on rendering
the tree and its connectors). Drawing one between two parked fragments would
assert a sequencing relationship that no compiler stage reads and no runtime
can ever produce, on a surface whose entire value is that the canvas and the
compiled chart agree - which is the property the `:failure` amendment's
consequences named and this section is protecting in the same words.

The same reasoning is why a fragment's own internal connectors are drawn
normally. Inside a parked fragment the child order *is* sequencing: it is a
subtree that means what it will mean once it is placed, ADR-0003's amendment
of this date keeps checking its internal seams while it is parked, and
drawing it as anything other than the flow it is would hide the thing the
author parked it to keep working on.

### 10v. `:tray` inherits 10i, and an older editor never reaches it anyway

An editor that does not know `:tray` resolves it to `:primary` under 10i and
renders the shelf's contents as an ordinary body flow, connectors and all -
the failure 10u exists to prevent. In practice it will not arrive there: an
editor old enough not to know the style is old enough not to resolve
`core.drafts` at all, and ADR-0002 decision 3's total resolution puts the
whole block behind the unresolvable-block presentation decision 12 of this
record owns, where its children are not laid out as a flow because they are
not laid out at all.

Recorded rather than relied on. 10i's posture is unchanged and is still the
right default for a style an editor does not know; this is a note that the
one bad rendering it could produce is unreachable by the ordinary route, not
an argument for a second mechanism.

### 11n. Findings inside the tray render on the fragment, by decision 11 unchanged

Decision 11 makes the anchor the whole routing mechanism, and it needs no
amendment here: a `:config` finding against a field of a parked block renders
inline beneath that field, a `:slot` finding on that slot's header, a
`:block` finding on that block's chrome. The anchor names a block id, the
block is in the document, and where it is drawn is where its findings are
drawn. Nothing about a fragment being parked in the drafts tray changes that.

Three consequences of leaving it unchanged are worth stating, because a reader
could reasonably expect each of them to need a rule and none of them does.

**The tray is inside the document-level panel.** Decision 11's panel lists
every finding and selecting one selects and reveals its anchor; a finding on a
parked fragment behaves the same way, and revealing it opens the tray. The
alternative - filtering parked findings out of the panel - would mean an
author could not find the problem they parked the fragment because of.

**A folded tray carries a count badge**, by decision 11's existing rule that a
collapsed subtree does, so a finding can never hide inside something folded
shut. That rule was written against exactly this failure mode and a tray is a
container that will usually be folded.

**`:draft_blocks_present` renders on the tray itself.** ADR-0004's amendment
of this date anchors that warning on the `core.drafts` block and mints it once
per document, so it lands on the tray's own chrome rather than on any
fragment, and it says something about the document rather than about anybody's
work. `:placeholder_block` lands on each marker's card, in the flow, where the
gap is.

### Deferred, named rather than guessed

**Where the tray is drawn.** This section fixes that the tray is out of the
flow, contributes no boundary and draws no connectors. It deliberately does
not fix *where* on the editor's surface it appears - a strip at the foot of
the canvas, or a tab in the drawer whose tab strip the 2026-08-30 amendment
made a host seam. Both satisfy everything above, the choice is answerable from
a built surface and not from this record, and it is `sb-uag7`'s to make and to
bring back here if it needs a rule.

**A palette-to-tray drop.** Whether an author may drop a new block from the
palette straight onto the tray, or must place it and then move it, is an edit
affordance rather than a rendering one. Nothing here forbids either; decision
2's four-command closed set already covers both, since a drop is an Insert and
a move is a Move.

### Consequences

- The editor gains a fourth slot style and no new component, no new anchor, no
  new severity and no new finding source. Whether it also needs no new theme
  token is left to the implementing bead rather than asserted here: 10j's
  no-new-token finding was about the error family specifically and does not
  carry over on its own, and amendment 14e's two-way token coverage will fail
  the build if the tray's edge and card turn out to need one that is not
  declared.
- **The edit algebra is untouched.** Parking a fragment in the drafts tray and
  placing it back into the flow are ordinary Move commands over ADR-0001's
  tree, with decision 3's inverses, so undo and redo work on them for the same
  reason they work on every other move. No command is added and none is
  amended - which is the strongest evidence available that this is a container
  and not a second document.
- `slot_style` now has four values and 10i matters more than it did, exactly
  as the `:failure` amendment predicted when it said a third value means a
  fourth is possible. This is that fourth, and it is this package's rather
  than a host's, which was not the case that amendment had in mind.
- **The canvas and the compiled chart still agree**, which is the property
  10u is written to protect. What ADR-0004 compiles to nothing, the renderer
  draws with no edges; what it compiles to a step, the renderer draws in the
  flow. A reader who can see the picture can predict the chart, and that
  remains true with a shelf in the document.

---

## Note (2026-09-01): decision 10, where the tray is drawn, and how it opens

A dated note rather than an amendment. The 2026-08-31 amendment above stands
in every particular: `:tray` is still the fourth `slot_style`, it is still
outside the rail partition, and 10u still says no connector enters the tray,
leaves it, or runs between two fragments. What this records is *where* the
tray is drawn and *how it opens* - the same shape as this record's Note of
2026-08-30 on decision 12's read-only config, which changed no decision and
recorded which surface one of its bullets renders on.

It answers the first item that amendment's *Deferred, named rather than
guessed* section left open, and carries two adjustments the operator ruled at
the campaign-024 wrap walk after reading the shipped surface (`sb-e2zy`;
captures in the fleet journal at `024-screens/se-ihm-*`).

**Where: the foot of the canvas, last in the root's `body`.** Not a drawer
tab. The shelf renders after its slot's flow children, and ADR-0002's G12a
admits it only as a direct child of the root's `body`, so "last in the root's
body" *is* a strip at the foot of the canvas - the two descriptions name one
position, which is why this needs no new component and no new anchor. The
grounds are in the placement comment on `shelf_last/1` in
`lib/statifier_blocks/editor/slot.ex`, and they are worth restating here
because the alternative was live: the drawer's own admission test is
"tabular and document-level" and a shelf is neither, and a bespoke strip is
what decision 13 forbids. The cost of the answer is one stable sort. The
index carried alongside each child stays the DOCUMENT index, so drop targets
and gaps keep naming real positions while the drawing order changes.

**A non-empty tray opens folded.** Decision 2's amendment of 2026-08-30 owns
the fold and is unchanged by this note: the control is the same one, the
collapsed set is still per-session editor state that is neither in the
document nor on the undo stack, and it is still cleared when the host swaps a
document in. What changes is the value it starts at - a shelf holding
anything opens collapsed, and the author unfolds it on demand. Section 11n
already assumed this shape when it wrote that "a tray is a container that will
usually be folded", and the count badge that section relies on is what keeps
a finding inside a folded tray visible. The reason is the surface: at default
zoom a shelf holding two or three parked fragments is taller than the flow
above it, so a document opened to be read opens showing the parked work.

An **empty** tray opens as it always did. It has nothing to hide, and its
tray is the drop target the first fragment is parked onto - an editor that
folded it shut would have folded away the affordance rather than the clutter.

The reset and the opening are the same value, deliberately: a document the
host swaps in opens the way it opens when it is the first document, which is
the sentence the 2026-08-30 note on a swapped document had to write for the
fit and is written here for the fold.

**No inbound connector on the anchor card.** 10u's "none entering the tray"
is read at both ends: no edge starts at the shelf's card, and no edge *ends*
there either. The anchor card sits in the root's steps chain and an arrowhead
landing on it is exactly the misreading 10u exists to prevent - at default
zoom it makes the shelf read as a trailing step, which is the one thing a
shelf is not. Stated as its own sentence because the two exclusions that hold
it up in `Connectors` are both written from the *source* side (a tray slot
draws no adjacency, and every other slot's chain is read off `flow_children/1`),
so a reader checking the guarantee from the target side had to re-derive it.
The shipped build was already drawing no such edge; this note fixes the
guarantee rather than reporting a repair, and the assertion in the inbound
direction now exists beside the ones in the outbound.

Unchanged by this note: 10s, 10t, 10u, 10v and 11n in every particular; the
edit algebra, which parks and places a fragment with the ordinary Move
commands; and decision 2's four-command closed set, which the fold was
already outside of.

---

## Amendment (2026-09-01): decision 2, a fifth command, and the declarations panel

**Status: accepted (2026-09-01, UNQUALIFIED direction-agent verdict under the
operator campaign-026 grant, PR 211), implementing bead `sb-d0nv`,
campaign-026's Lane A1.** Drafted 2026-09-01 as a proposed amendment.
Additive; decisions 2, 3, 7, 8, 9 and 11 stand as written and no
text above this line is edited by this section, which supersedes decision 2's
"four, not seven" count rather than rewriting it in place - the convention
every amendment on this record follows.

An amendment rather than a note, and this one could not have been anything
else. A note records what accepted text already meant; decision 2 says its
command set is closed at four, and this section makes it five. It also takes a
door another record opened and left for this one.

### Context

ADR-0001's amendment of 2026-08-31 gave the block document a top-level
`datamodel` key: an ordered list of `{id, expr, description}` entries naming
the `<data>` roots the document's own guards and assigns need. Its 11i names
the surface this section builds and declines to build it, in the sentence this
section exists to answer:

> A host may now carry roots in the tree the author edits rather than in the
> publish call, which is what makes an editor able to show and edit them one
> day. **No editor surface is proposed here**; that is ADR-0005's, when taken.

This is ADR-0005 taking it. Two clauses of that record are untouched by this
section and are named so that nobody has to check. Its 11b's entry shape is
exactly three fields and this section adds no fourth; its 11g's split between
the two artifacts stands, so an ADR-0006 datamodel document still describes a
vocabulary and this key still only declares that a root exists.

The reason to take it now rather than leave it named is that the key is
already load-bearing and already unreachable. The compiler emits its roots,
`content_hash/1` covers them (11d), and this record's own 11k reads them as
the third of the three sources feeding the 11e advisory - so a document
without them lints its paths differently from one with them. Every one of
those consequences is available to a host that hand-edits JSON and to nobody
else. An authoring package whose author cannot author a key its own compiler
compiles is the gap this section closes.

### Decision

**2g. Decision 2's closed set grows by one:
`{:set_datamodel, [%Document.DatamodelEntry{}]}`.** It replaces the
document's whole `datamodel` list. The four structural rules the algebra
applies are about the tree and none of them reaches it: an entry is not a
block, the list is not a slot, and there is no `target()` for an index to be
read against.

The set opens here and did not open for the fold, and the two cases are
decided by the same test rather than by different ones. 2a kept the set at
four because a collapsed container is "editor state ... neither in the
document nor on the undo stack". A declaration is the opposite on both counts.
It is in the document by 11a and in the canonical bytes by 11d, which puts it
in the hash; and an author who deletes a declaration and cannot undo it has
lost document content, which is the loss the undo stack exists to prevent. The
question 2a asked - is this thing part of the document? - has the other answer
here, so it gets the other outcome.

**Five, and not eight.** No per-entry insert, remove or move. Decision 2's own
argument for collapsing seven commands into four is the argument for
collapsing four gestures into one here: it means there is one code path that
writes the key, so the grammar check, the ordering and the inverse have one
implementation each rather than four that drift. Add, edit, remove and reorder
are the same command carrying a different list.

Three further reasons, none of which decision 2 could have anticipated because
none of them is about a tree. The entry list has no `target()` and no slot, so
per-entry commands would need a second index vocabulary beside decision 4's,
applied to a different kind of container and tested separately. The list is
small and wholly serializable - a document's roots, not a subtree - so
carrying it entire costs a command log nothing that matters. And the inverse
is the list that was there before, which makes the command its own kind of
inverse and makes decision 3's law hold by construction: no new inverse rule
is written, and the property test gains a command rather than a case.

**2h. The command is where the grammar is enforced, and `check_config/3` is
not.** `Edit.apply/2` refuses any list ADR-0001 11b and 11c refuse, in 11c's
own error family - `{:malformed_envelope, {:datamodel, reason}}` - by calling
the one implementation of that grammar rather than restating it.
`StatifierBlocks.Validation` is that implementation; the function it already
had becomes public and nothing about what it checks changes.

Not `check_config/3`, because that is decision 9's block-type gate: it
resolves a block through the palette and asks its type. A declaration has no
block type and no palette to ask. What it has is a grammar, and a grammar is
the same kind of question the four structural rules answer for the tree, so it
is answered where they are. `check_config/3` gains a clause that says `:ok`
and says why.

One consequence is worth stating rather than leaving to be discovered: a list
this command accepts is a list `Document.validate/1` accepts, so `to_json/1`
can never raise on a document this command produced. `Edit.History` needs no
change at all - `commit/4`, `undo/3` and `redo/3` route through the funnel
they already have, and the refusal reaches all three.

**2i. The panel is a drawer tab, and it fills the place 1A reserved.** 1A's
admission test is two words and a declaration list passes both: it is a grid
of rows - a name, an initial value, a description - and it is about the
envelope, which is the whole document rather than any block in it. 3A keeps it
out of the inspector for the reason 3A already gave about Datamodel and
Fixtures: they were never about the selected block.

It is the third tab, after Truth tables and Findings, so 2A's unchosen-tab
rule reaches it unchanged and a document with tables in it opens where it
always did. The strip's count is the number of declarations the **document**
holds, never the number in a draft (2l), because 2A's count is a statement
about the document.

**The tab is called Declarations, not Datamodel.** The place 1A reserved was
described as "the datamodel declared-path view", and this is not that view.
That sentence described a read-only report, which under 11k's union would be a
report over three sources at once - the host's datamodel, the compile call's
`:declare` roots, and this key. What ships here is the one source an author
can change. The report stays unbuilt and this section reserves nothing for it;
if it is taken later it is admitted by 1A on its own merits, here, like any
other tab. The name follows ADR-0001 11g's split for the same reason that
record draws it: a tab called Datamodel beside an ADR-0006 datamodel document
names the wrong artifact.

**2j. Reorder is buttons, and that is the gesture rather than the fallback.**
Decision 7 ships exactly one JavaScript hook, on the canvas's cards, and a
second drag surface would be a second hook or a widening of the first. A list
of three rows buys neither. Up and Down are native buttons, one command each.

Decision 8 is satisfied by construction rather than by a parallel path. Its
rule is that every drop target is reachable without dragging, written for a
canvas that has gaps, slots and geometry; this panel has none of the three, so
there is no dragging path for the keyboard path to be an alternative to. A
control at either end of the list is disabled rather than live-and-inert, and
the server refuses the same move anyway - the ends are a no-op on both sides,
because a wrapping reorder would make one press of a repeated gesture do the
opposite of the press before it.

Order stays load-bearing. It is the emission order of the document's `<data>`
elements (11a), which is why moving a row is a document edit on the undo stack
and not a display preference, and it is the authoring act ADR-0001's
alternatives section refused to make inexpressible.

**2k. A gesture that lands on what the document already holds commits
nothing.** An index off the end, a move off either end, and a form change that
retypes the value already there all produce the list the document has. None of
them reaches the command: no history entry, no notification, no revision move.
Without this the first row's Up would push an undo entry that undoes nothing,
and an author's next undo would appear to be broken.

**2l. A refused edit is held as a draft, and its refusal is not a finding.**
This is decision 9's draft treatment applied to the second surface with the
same problem. A value the document refuses is still the value the author is
holding, and redrawing the document's own value over it deletes their
keystrokes to punish a typo. The panel therefore draws the refused list, and
the sentence saying why is drawn above it. The draft is cleared by a change
the document accepts, and by a document the host swaps in - the same reset
`switch_document/2` already applies to the config drafts, for the same reason.

The refusal is **not** a `%Finding{}` and never enters the findings pipeline.
Decision 11 makes the anchor the whole routing mechanism and its anchors name
a block, a slot or a config key; none of the three can name a declaration
entry. Inventing a fourth anchor shape would be a change to decision 11 that
this section does not need and has no second consumer for: a refusal here is
about the panel that produced it, it is transient, and it is already on the
author's screen. 11g's no-second-channel rule is untouched, because nothing
here is a channel.

**2m. The panel produces no advisories, and changes none of 11e's rules.**
ADR-0001 11h - "It produces no finding about an undeclared path, ever" - is a
statement about the key and is unchanged by there being an editor for it. 11e
is still the only producer, still anchored `{:config, block_id, key}`, still
`:info` from `:lint`, and it already reads the document's own roots as 11k's
third source. Editing a declaration therefore changes which advisories 11e
produces, through an input that already exists and with no new rule anywhere.
That is 11k working, not a widening of it.

`sb-sj79` carries campaign-026's R26-8 confirmation of the same point on this
record. Nothing in this section waits on it and nothing in this section
forecloses it.

### Consequences

- **The document's declaration surface becomes reachable.** Everything 11i
  said the key made possible - roots carried in the tree the author edits
  rather than in the publish call - is now something an author can do without
  hand-editing JSON.
- **The command set is five and the reason it is closed is unchanged.** What
  2a defended was not the number; it was the rule that a presentation state
  does not become a command. That rule is intact, and this section is the
  case on the other side of it.
- **The property test gains a command rather than a case.** Because the
  inverse of `{:set_datamodel, entries}` is `{:set_datamodel, previous}`,
  decision 3's law needs no new arm: the generator emits the command, valid
  and refusable, and the existing law covers it.
- **`StatifierBlocks.Validation`'s datamodel check acquires a second caller**
  and becomes public for it. The `datamodel` key now has two writers - a
  stored document and this command - and one refusal, which is the property
  ADR-0001 11c wanted when it put the check in structural validation rather
  than in the compile pipeline.
- **The drawer's tab set is three and the bullet that governs it is
  unweakened.** 1A's test admitted this tab; fixture runs and the read-only
  declared-path view keep their reserved places; a host tab is still the
  host's obligation under the 2026-08-30 seam amendment.
- **A host that renders the editor gets the panel with no change of its own.**
  No new assign, no new event, no new slot. The document reaches the host
  through `on_change` exactly as every other edit does.

### Alternatives considered

- **Declaration edits outside the undo stack, as editor state.** Rejected by
  2a's own test: the key is in the document and in the hash, so an edit to it
  is not editor state, and a deleted declaration would be document content
  with no way back.
- **Per-entry `:insert_declaration` / `:remove_declaration` /
  `:move_declaration` commands.** Rejected: three commands where one does, a
  second index vocabulary beside decision 4's applied to a container that is
  not a slot, and three inverses to write and test where the whole-list
  command's inverse is the previous list.
- **A general `{:update_envelope, key, value}` command.** Rejected as too
  wide for what is being asked. It would put `id` and `revision` inside the
  algebra, and 8A gives both to the host; a command able to rewrite the
  document's identity is not one this record wants written by an author
  gesture. If `metadata` ever needs a surface it gets its own decision, on
  the same terms this one took.
- **Drag-to-reorder, reusing the canvas hook.** Rejected: decision 7's hook is
  about cards on a measured canvas and would have to grow a second mode for a
  table with no geometry, which is a widening of the one hook this record
  deliberately has - for a gesture two buttons already express.
- **Rendering a refusal as an `:info` finding.** Rejected: decision 11's
  anchors cannot name a declaration entry, so it would need a fourth anchor
  shape, and 11c's rule that findings are claims about the document does not
  fit a message about a form the document never accepted.
- **An expression editor for `expr`, through decision 9's
  `expression_component` seam.** Rejected here, not forever. That seam is for
  conditions on blocks, `expr` is written verbatim into the emitted
  `<data expr="...">` attribute, and whether it is well-formed is predicator's
  question and the compiler's - not one this panel can answer. The field is a
  text input, and a future section may say otherwise.

---

## Note (2026-09-01): decision 11, R26-8 ratifies 11k source 3

Recorded because the operator's campaign-026 ruling **R26-8** - *document-
declared roots count as declared for 11e's undeclared-path advisory; union
them into the declared-path set; advisory-never-a-gate unchanged* - was taken
against ADR-0001 11g's open question, and a reader who arrives at that
question from ADR-0001 needs this record to say where the answer already is.

**It is a note and not an amendment because it moves nothing.** The record's
own rule for the choice is the one the 2026-08-31 amendment states about
itself: a note records what accepted text already means, and an amendment is
for text a reader of the clause alone would read the other way. R26-8's
substance is already accepted text here. The amendment of 2026-08-31,
*decision 11, what feeds the declared set 11e reads* (accepted, UNQUALIFIED
direction-agent verdict, PR 189, implementing bead `sb-y4oa`), decides it in
its 11k:

> **11k. The declared set is the union of three declarations, not one.** [...]
> 3. the roots the document's own `datamodel` key names (ADR-0001 decision
>    11).

That is R26-8, clause for clause: the third source is the document's own
declaration, it reaches the set 11e reads by union, and 11l gives it
root-segment matching while leaving source 1 exact. That amendment's
consequences already say **"ADR-0001's 11g open question is discharged"**, on
the record 11g named, which is what ADR-0001 11g asked for and what R26-8
confirms. So the ruling and the record agree, and the ruling is the later of
the two - it ratifies a decision this record had already taken rather than
directing a new one.

**Advisory-never-a-gate is unchanged, and was never in question.** 11c's rule
that these findings change no verdict, 11f's `nil`-suppression as 11m widens
it, ADR-0006 decision 9's advisory-only datamodel document, and ADR-0001 11h's
"it produces no finding about an undeclared path, ever" about the key itself
all stand exactly as written. R26-8 changes no input, no precondition, no
anchor, no severity and no source, because 11k-11m already changed the only
input there was.

**Verified in the shipped code and its tests**, so the agreement is between
the ruling and the artifact and not only between two prose sections:

- `StatifierBlocks.Datamodel.findings/4`
  (`lib/statifier_blocks/datamodel.ex`) unions `document_roots/1` - read off
  the `Document` struct's `datamodel` entries, so no caller can pass the wrong
  one or forget it - with `declared_roots/1` over the `:declare` option, and
  runs the check when either the datamodel is non-`nil` or that union is
  non-empty, which is 11m's widened precondition exactly. Landed 2026-08-31 in
  `15138cc`.
- `test/statifier_blocks/datamodel_test.exs` pins the behaviour in both
  directions under `describe "a declared root (11k, 11l)"` and
  `describe "nothing declared anywhere (11m)"`: a document-declared root
  covers every path beneath it, an undeclared root beside it is still flagged
  in the same call, the datamodel's own paths stay matched whole, a blank
  declared root declares nothing, and a document that declares roots lints its
  own paths with no host involved at all.

No decision moves, no clause is edited, and no text above this line changes.
Filed with `sb-sj79`, campaign-026's Lane A2.

---

## Note (2026-09-01): decision 9, what a path candidates feed is and is not

A dated note rather than an amendment, because decision 9 is unchanged in
every clause. `:expression` still renders as a plain source input in this
package; rich expression editing - a richer affordance, inline evaluation
against a dataset - is still statifier-ui's, still deferred by decision 15's
"Rich expression editing is statifier-ui's (sui-bob)" bullet, and the
`expression_component` override is still the seam it is deferred through.
The `:update_config` gate is untouched.

The note exists because decision 9 names **"completion against the
datamodel"** as one example of the affordance it defers, and sb-0vt landed a
`<datalist>` of declared datamodel paths on that very input. A reader
holding those two side by side is owed the sentence that separates them, and
without it the code and the record read as disagreeing - which, by this
repo's own rule that the record is the contract, would make the code the bug.

**The distinction the record draws.** Decision 9 defers the *affordance*: a
control that understands predicator source. What landed is *data* - the set
of paths the document's own declaring surfaces already name, offered through
the plainest control HTML has. Three things follow, and each is checkable
rather than asserted:

- **It suggests and never constrains.** A `<datalist>` is the control the
  `invoke_type` list already uses for the same reason (see decision 9's
  neighbours and ADR-0004 decision 8): free text stays valid, and an
  undeclared path stays 11e's `:info` advisory rather than becoming a
  refusal. `validate_config/1` remains the only gate.
- **It adds no JavaScript.** Decision 7's two-hook limit is untouched and
  still mechanically enforced by `test/statifier_blocks/assets_test.exs`.
- **It is not completion, and cannot become it here.** A browser matches a
  datalist against the input's *whole value*, so the list is live while the
  author types a leading path and goes quiet once the expression grows an
  operator. Completion mid-expression needs the caret position inside the
  source - which needs either a hook decision 7 forbids or the richer
  component decision 9 defers - and it needs predicator's operator and
  keyword vocabulary, which predicator exposes no public enumeration of
  (`Predicator.Lexer` holds those tokens privately; `Functions.Provider`
  covers function names alone). Copying that vocabulary into this package
  would be a second, silently drifting copy of a contract predicator owns.

**Where the seam moved, additively.** `expression_component` is now called
with a `:candidates` key beside `:field`, `:id`, `:name` and `:value`. An
override written before this note takes a map and reads the keys it knows,
so nothing that worked stops working; an override written after it is handed
the declared paths rather than re-deriving them from assigns the field
component is not given. That is the seam being supplied, not narrowed.

**Where it renders.** `StatifierBlocks.Datamodel.candidates/3` reads the
same three declaring surfaces `findings/4` does - the host's datamodel, the
compile call's `:declare` roots, and the document's own `datamodel` key -
through the same normalizers, so the set an author is offered and the set
that decides whether they get an advisory cannot drift apart. It lives in
that module for that reason. `candidates_under/2` is the narrowing query for
a component that re-renders per keystroke, and it reaches ADR-0006 decision
6's projection through `Predicates.Datamodel.under/2` rather than restating
it. Absence collapses to `[]` and renders no `<datalist>` at all, which is
the same "an empty list is markup that suggests nothing" rule the
`invoke_type` control follows.

What stays open is unchanged and is tracked elsewhere: the richer component
is sui-wqr's, predicator's grammar vocabulary is px-15q's, and decision 15's
per-palette-entry fixtures pane is still undecided.

No decision moves, no clause is edited, and no text above this line changes.
Filed with `sb-0vt`, campaign-026's Lane A3, under ruling RQ-026-5.

---

## Note (2026-09-01): decision 2, what amendment 2b's "clears it" means

A dated note rather than an amendment, and a one-line reconciliation of two
sentences of this record that a reader can read as disagreeing.

The 2026-08-30 amendment's clause 2b says `switch_document/2` "clears it,
exactly as it clears the selection", and it was literally true when it was
written: the collapsed set went to the empty set on a document identity
change. The 2026-09-01 note on decision 10 then gave the fold an opening
value - a non-empty tray opens folded - and said "the reset and the opening
are the same value, deliberately". The shipped shell does the second: both
clauses of `switch_document/2` in `lib/statifier_blocks/editor.ex` assign
`collapsed_ids` from `opening_folds/1`, not from `MapSet.new/0`.

**The two say the same thing, and 2b's guarantee is untouched.** What 2b
promises is that no fold carried from the old document survives the swap -
"a block id from the old document names nothing in the new one" - and
resetting to the new document's opening folds is exactly that: every id in
the resulting set is a stocked shelf in the document being opened, and no id
from the old one can be in it. Where the document has no stocked shelf,
`opening_folds/1` returns the empty set and the behaviour is literally the
one 2b describes.

Read 2b as *clears the author's folds*, not as *assigns the empty set*. The
rest of the clause stands unedited: the reset still fires only on a document
identity change, the palette's own fold (and, per the 2026-08-30 fullscreen
amendment, the pane folds) is still the deliberate exception because it
addresses no block, the set is still per-session editor state that is neither
in the document nor on the undo stack, and it is still not persisted in
either direction.

No decision moves and no clause is edited. Filed with `sb-8fsb`,
campaign-026.

---

## Amendment (2026-09-02): the drawer's fourth tab, fixture runs against the compiled chart

**Status: accepted (2026-09-02, UNQUALIFIED direction-agent verdict, PR 225),
drafted with the implementation it records, implementing bead `sb-4yze`,
campaign-027's Lane E.** Additive; decisions 1, 7, 14 and 15 stand as written
and no text above this line is edited by this section.

### Context

The drawer's third reserved place - "fixture runs" - was named twice without
being drafted: in `drawer.ex`'s moduledoc and in `editor.ex:758-765`'s comment
on the tab-pick handler, both of which listed "fixture runs, the datamodel
view" as what remained after the 2026-09-01 declarations amendment took the
first door ADR-0001 11i opened. This section takes the second. Both call
sites now read as the implementation left them - the moduledoc names fixture
runs as landed and the declared-path view as what remains, and the handler
comment names `sb-ouly` for it - which this section records rather than
re-derives.

The tab passes 1A's admission test the same way tables, findings and
declarations did before it: it is tabular - one row per fixture row - and it
is about the whole document, never about the block currently selected. 3A's
reason for keeping tables and findings out of the inspector applies here
unchanged: fixture runs were never about the selected block either.

### Proposed decision

**A fourth drawer tab, `:fixtures`,** listing every fixture row attached to
the document's blocks with a per-row verdict. It joins `:tables`, `:findings`
and `:declarations` in `Shell.drawer_tabs/0`, last, so a document that already
has tables open still opens where it always did (2A's unchosen-tab rule
resolves to the first tab with a non-zero count, and the order of the list is
what "first" means).

**The data path, named end to end.** The `fixtures` assign
(`%{block_id => [TruthTable.t()]} | nil`, unchanged) is read by
`StatifierBlocks.Runtime.FixtureRuns.run/4`, which calls
`StatifierBlocks.Compiler.compile/3` once against the document and palette,
then `Statifier.compile/2` on the emitted SCXML bytes, then
`Statifier.initialize/2` once per fixture row with `datamodel: row.context`.
Each call's `%MachineState{}.entered_states` is mapped through
`Statifier.Machine.id/2` to state ids, and those ids are resolved to owning
blocks through `StatifierBlocks.Provenance.owners_of_states/2`. The fixture's
own block is walked in slot-declaration order for the first slot holding an
entered descendant, and comparing that slot against the row's expected slot
(the cell whose `expected` is `true`) produces the verdict.

**Why `initialize/2` alone, and why `entered_states` rather than the final
configuration.** A `core.branch` arm is transient - `Core.Branch.emit/2`
compiles it to a compound state whose `initial` is a transient pick state,
so the arm can be entered and left inside the same macrostep `initialize/2`
runs, and the chart can reach its `<final>` during initialization. The final
configuration can therefore miss the very arm the row took. `entered_states`
accumulates across the whole session and misses nothing; reading it is the
same inspection `Statifier.Testing.Case` performs on
`MachineState.active_leaf_states/1`, applied to a wider field, and it is not
a fifth driving function - no `Statifier.send_event/2` call is made, because
a `%TruthTable.Row{}` carries bindings and a context, never an event.

**Why the driving code calls `Statifier`'s four functions directly.**
`Statifier.Testing.Case` is an ExUnit case template - `use`-able only in a
test - and its own moduledoc forbids any module in `lib/` outside
`Statifier.Testing.*` from referencing it. `compile/2`, `initialize/2`,
`send_event/2` and `active_leaf_states/1` **are** the closed ADR-0053 /
ADR-0006 surface it names; calling them directly from `lib/` is that surface,
not a way around it, and the test suite is free to `use` the template where
it helps.

**Where the runner lives, and why.**
`StatifierBlocks.Runtime.FixtureRuns`, outside the
`Code.ensure_loaded?(Phoenix.LiveView)` guard, on the rule `Shell`'s own
moduledoc already states: what is worth testing goes in
`lib/statifier_blocks/`, unguarded. Decision 1's headless CI job is what
makes that guard trustworthy, and the part worth testing belongs where the
headless tree can reach it. The `Runtime.*` namespace is
`runtime/subchart.ex`'s precedent - the half that runs, set against the
authoring half that is everything else in `lib/`.

**What counts in the strip: rows.** `Shell.fixture_row_count/1` counts the
rows the fixtures source holds, not the failures a run against them
produces - the same convention `:tables` and `:findings` follow, counting
content rather than problems. `drawer_view/1` runs on every render, and
counting failures would put a compile plus N chart runs inside every
keystroke; the run itself is driven only while the drawer is open on this
tab and its memo key has changed, through `refresh_fixture_runs/1`.

**The drawer's `status` field is not overloaded.** `status`, `tables` and
`jumps` on `drawer()` describe the truth-tables tab and keep their present
meanings. The fixtures tab's own state - a `StatifierBlocks.Runtime.FixtureRuns.t()`,
carrying its own `:no_fixtures | :compile_error | :ready` status and, on
`:ready`, a `Run.t()` per row with verdict `:pass | :fail | :row_error |
:no_expectation | :not_comparable | :unreached` - is a separate editor
assign, because it is neither pure nor cheap and `drawer_view/1` is both.

**Decision 7's two-hook limit, restated as acceptance.** The package ships
exactly two hooks, `StatifierBlocksDrag` and `StatifierBlocksMeasure`; this
tab is server-rendered, adds no JavaScript, and edits neither hook file.
`test/statifier_blocks/assets_test.exs` holds the limit against the files
rather than against reviewer memory, and it is unchanged by this section.

**Decision 15 is narrowed, not contradicted.** Decision 15's bullet on this
exact question - "**Per-palette-entry fixtures** - the 'test this step' panel
ADR-0002 decision 9 sketched - wait on sui-13q, unchanged and still
provisional" - names a different surface than this one. This tab is not that
panel: it is document-level and tabular, over every fixture row already
attached to the document's blocks, not per-palette-entry; it invents no
fixture-bundle format of its own; and the deferred per-entry pane stays
exactly as deferred as decision 15 left it. The convention this tab consumes
rather than competes with is sui-13q's, recorded in statifier-ui's
`docs/fixture-bundles.md` (`StatifierUI.Fixtures` / `StatifierUI.Fixtures.Bundle`).

**The last reserved place.** `drawer.ex`'s moduledoc and `editor.ex`'s
tab-pick handler comment named two reserved places, "fixture runs, the
datamodel view". This section takes the first. The read-only declared-path
view is `sb-ouly`'s and is the one that remains.

**The precedent for landing a proposed amendment with its implementation.**
`## Amendment (2026-09-01): decision 2, a fifth command, and the declarations
panel`, Status line "PR 211", bead `sb-d0nv`, landed as commit `cea57f1`,
which carried `docs/adr/0005-liveview-editor.md` together with
`lib/statifier_blocks/shell.ex`, `lib/statifier_blocks/editor/drawer.ex`,
`assets/css/statifier_blocks.css`, `changelog.d/sb-d0nv.md` and five test
files in one commit, and was flipped to accepted afterwards in `ecf182b`.
Verified with `git show --stat cea57f1`.

### Consequences

- **The drawer's tab set is four and the bullet that governs it is
  unweakened.** 1A's test admitted this tab the way it admitted the three
  before it; the read-only declared-path view keeps its reserved place; a
  host tab is still the host's obligation under the 2026-08-30 seam
  amendment.
- **A document's fixture rows become inspectable without a separate
  harness.** An author sees, per row, the slot the row expected against the
  slot the compiled chart actually took, in the same surface as the tables
  that produced the rows.
- **No new command, no new hook, no new anchor.** The tab reads
  `StatifierBlocks.Runtime.FixtureRuns.run/4`'s result and draws it; nothing
  here touches decision 2's command set, decision 7's hook count, or decision
  11's finding anchors. A compile failure surfaces through the same
  `%Finding{}` list the findings tab already draws, carried on the fixture
  run's own `:compile_error` status.
- **A host that renders the editor gets the tab with no change of its own.**
  No new assign beyond the existing `fixtures` one, no new event beyond the
  existing `drawer-open` / `drawer-tab` pair.

No decision moves, no clause is edited, and no text above this line changes.
Filed with `sb-4yze`, campaign-027's Lane E, under ruling R27-9.

## Note (2026-09-02): decision 1A, the last reserved place, filled

A dated note rather than an amendment, because no decision moves, no clause
is edited, no text above this line changes, and nothing here widens 1A's
admission test. What it records is which content took the place 1A reserved,
because the place was named repeatedly and never described - and a reserved
name that outlives its own reservation reads, to the next reader, as a tab
that is still owed.

### What the place was

1A reserved two: "fixture runs and the datamodel view". The
`## Amendment (2026-09-02): the drawer's fourth tab, fixture runs against the
compiled chart` above took the first, and ended by saying of the second that
"the read-only declared-path view is `sb-ouly`'s and is the one that remains".
It remains no longer, and this note is what its Consequences bullet - "the
read-only declared-path view keeps its reserved place" - is superseded by. The
bullet is left standing as written, dated where it is; this note is where the
current state is read off.

### What the tab renders

A fifth package tab, `:datamodel`, titled **Datamodel** - the name 1A's
reservation used, and the name the 2026-09-01 declarations amendment
deliberately did not take for the third tab ("The tab is called Declarations,
not Datamodel"). The two names now sit beside each other and mean what that
amendment said they mean: Declarations is the editable list of roots the
document's own envelope declares, and Datamodel is the read-only view over the
whole declared vocabulary.

One row per declared path, sorted, carrying:

| Column | Source |
|---|---|
| Path | the path itself |
| Declared by | which of 11k's three surfaces declared it - the host's datamodel, the compile call's roots, the document's own envelope - all of them when more than one did |
| Type | the ADR-0006 entry's `type`, with a `list`'s `item_type` spelled out, and `unspecified` where no entry describes the path |
| Scope | the ADR-0006 entry's scope |
| Label | the ADR-0006 entry's label |

The row set is `StatifierBlocks.Datamodel.candidates/3`'s set, path for path,
and a test asserts that rather than assuming it. That is the whole reason the
tab shows three surfaces where the reservation's words say "declared-path
view": the 11e advisory an author is looking at is decided against the union
of the three, so a view that showed only the host's datamodel would answer a
different question than the finding beside it asked. Shape comes from the
ADR-0006 document alone, because a bare declared root has none by 11l and a
path set carries none at all.

Read-only, and not as an omission. Two of the three surfaces are the host's
and the compile call's, which the package cannot write to; the third is the
Declarations tab's, one tab away. An empty view is distinguished in prose
rather than by an empty table: with nothing declared anywhere, no
undeclared-path advisory is produced either (11m), and the panel says so.

### What it does not change

No new command (decision 2), no new hook - it is server-rendered and edits
neither of decision 7's two hook files - no new anchor (decision 11), and no
new host assign: the rows are derived in `render/1` from the `datamodel`,
`declare` and `document` the editor already holds. The strip's unchosen-tab
resolution is unchanged and the tab is placed last under 2A's arrival-order
rule, which matters more here than it did for fixtures: a datamodel is the
thing most likely to be non-empty on a document that holds nothing else, so
ahead of the others it would capture the resolution for nearly every host that
supplies one.

The drawer's package tab set is five, and 1A's test governs it unweakened. No
reserved place remains behind it; anything later is admitted by 1A on its own
merits or not at all.

## Note (2026-09-04): decision 9, the expression seam is filled, and in what order

A dated note rather than an amendment, because nothing decision 9 *decided*
moves. `:expression` still renders through the `expression_component` seam
decision 9 put there; a host override still wins over everything; the
`:update_config` gate is untouched; the document still stores the author's own
source string and this package still holds no structured expression model of
its own. Decision 15's deferral is not reversed either - it is honored in the
way it was written to be honored, by *consuming* statifier-ui's component
rather than reimplementing predicator source here.

What moves is narrower and entirely factual: the seam now has a default
filling, because the package the deferral names has shipped the component.
Three sentences in this record describe the old default as a present-tense
fact, and a reader holding them beside the code would find the code in the
wrong - which, by this repo's rule that the record is the contract, is exactly
backwards. So they are named here rather than left to be discovered.

### The sentences this supersedes

Decision 9's table row:

> | `:expression` | single-line source input (see below) |

and the sentence beneath it that opens the `:expression` paragraph:

> `:expression` renders as a plain source input in this package.

and, in decision 15, the second sentence of the rich-expression-editing
bullet:

> Decision 9 ships a plain input and an override seam.

and, in the note of 2026-09-01 above, its restatement of the same fact:

> `:expression` still renders as a plain source input in this package

All four stay where they are as the record of what was true until sb-m6e0.
From here on the order below is what an `:expression` field renders. Every
other clause of each of those passages is unchanged - decision 15's first
sentence in particular ("Rich expression editing is statifier-ui's (sui-bob)")
is not superseded but satisfied, and the whole of the 2026-09-01 note's
distinction between a path *feed* and a completion *affordance* still holds,
because what fills the seam is the affordance and it arrived from the package
that owns it.

### The order

Three answers, tried in this order, and the order is the whole rule:

1. **An `expression_component` the host passed.** The host asked for its own
   control and gets it, whatever else is available. This is decision 9's
   original seam, unnarrowed.
2. **`StatifierUI.Live.ExpressionInput`, when `statifier_ui` resolves.**
   Picklists of field, operator and value over the source predicator can
   round-trip, and a text input over everything else.
3. **The plain source input this package has always rendered**, with the
   `<datalist>` of declared paths the 2026-09-01 note records.

Two properties of clause 2 are load-bearing, and neither is this package's to
weaken, because both are what let clause 2 replace clause 3 without the record
having to decide anything new. The component **never refuses a source string
and never rewrites one**: source it cannot draw as rows - anything outside the
subset `StatifierUI.Expression.simple/2` answers for - is drawn as text, and
an author who typed something the picklists cannot represent keeps their text
exactly as typed. And **every control it draws writes a complete expression
source string into the same named input the text mode edits**, so what reaches
`:update_config` is a source string either way and the gate sees no new shape.

Clause 3 is not a degraded mode being tolerated; it is a supported
configuration, and CI holds it that way (below).

### How clause 2 is resolved, and why a tree without the package is quiet

`statifier_ui` is an **optional** dependency, resolved the way
`phoenix_live_view` is under decision 1. The module is never named as a call
target: it is read at runtime from `:statifier_blocks,
:expression_component_module` (defaulting to `StatifierUI.Live.ExpressionInput`)
and captured through `Code.ensure_loaded?/1` plus
`function_exported?(module, :expression_input, 1)`. A tree without the package
therefore produces no compile warning and nothing raises - it simply lands on
clause 3.

The indirection earns its keep twice over. It is the same shape statifier-ui
itself uses to reach `Predicator.Simple`, so the family has one pattern rather
than two; and it is what makes clause 3 *assertable on a machine where clause
2 resolves*, by pointing the key at a module that does not exist. Without it,
the absent branch could only ever be tested by removing a dependency, which is
to say it would not be tested. `test/statifier_blocks/editor/expression_component_test.exs`
covers all three clauses on one machine for exactly that reason.

### Decision 1's property was checked, not assumed

`statifier_ui` was added inside `live_view_dep()` rather than beside the
unconditional dependencies, and the placement is the argument: its only
consumer is a LiveView component, so pulling it into the headless tree would
resolve a package nothing in that tree can call. Decision 1's acceptance
property is therefore untouched and was verified rather than reasoned about -
under `STATIFIER_BLOCKS_HEADLESS=1` the package resolves, compiles and passes
its full suite (1,444 tests), and the "Headless (phoenix_live_view absent)" CI
job passed on sb-m6e0's request. A second optional dependency is the case that
would have broken that property quietly if it had been declared in the wrong
list, which is why the check is recorded here and not left implied.

### Decision 7 is untouched, and this is the case that could have moved it

No JavaScript was added, no hook file was edited, and no third hook arrived.
The picklist affordance carries its own client behaviour, but that hook is
**statifier-ui's, shipped from statifier-ui's package**, so this package's
client surface is still the two hooks decision 7 admits and
`test/statifier_blocks/assets_test.exs` still enforces the count against the
files in `assets/js/`. Recorded explicitly because a rich in-place editor is
exactly the shape of feature that would otherwise justify a third hook, and
decision 7 sets a deliberately high bar for one: consuming a component from
the package that owns the subject is how the bar was cleared rather than
argued down.

### `value_candidates`

The seam gained a second additive key alongside `candidates`:
`value_candidates`, a `%{path => [candidate]}` map where a candidate is
`%{label: , value: }` or a bare string. It is threaded as a new editor assign
along the same chain `path_candidates` already takes - editor, inspector,
config form, field, and the field's control - and reaches the component behind
the seam untouched. Nothing in this package interprets it, and that is the point:
only a host knows which of its own declared paths have a bounded set of values
at all. A path with no entry gets a free-text value control rather than an
empty dropdown, which is the same "suggests, never constrains" posture the
path `<datalist>` takes and the same posture 11e's advisory takes on an
undeclared path.

Additivity is the compatibility argument and it is the same one the
2026-09-01 note made for `candidates`: an override written before either key
existed takes a map and reads the keys it knows, so nothing that worked stops
working.

### What is not decided here

The dependency arrangement clause 2 currently rests on is **interim and is not
a decision of this record**. `statifier_ui` and `predicator` are both pinned by
git ref in `mix.exs` at the moment, the second with `override: true` and only
because statifier-ui pins predicator the same way and Mix refuses the
divergence. Both pins come out at the post-publish re-pin, when predicator
9.2.0 and statifier_ui 0.4.0 are on Hex. It is named here in one paragraph
only so that a reader who opens `mix.exs` beside this note is not left to
wonder whether a git pin is something the record intends; the arrangement,
its consequences and its removal are tracked in the campaign's linkage ledger,
not here. Nothing in the order above depends on how the two packages are
pinned.

Also unchanged and tracked elsewhere: predicator's grammar vocabulary is
px-15q's, and decision 15's per-palette-entry fixtures pane is still
undecided.

No decision moves, no clause is edited, and no text above this line changes -
the four superseded sentences stay where they are, as the record of what was
true before.

Filed with `sb-mzah`, campaign-028's Lane B2, recording what `sb-m6e0` landed.

## Amendment (2026-09-05): decision 10, a summary chip that is a generated event name draws as a name

**Status: proposed (2026-09-05, campaign 029 Lane G, bead `sb-1hqt`).** A
decision record merges at proposed under campaign 029's invariant; flipping it
to accepted is a separate gated request. Additive; decision 10 stands exactly
as written, **10n and 10o are unchanged in every particular**, and no text
above this line is edited by this section. Nothing here is built yet - this
section is the record ahead of the code.

### Context

ADR-0004 decision 2 fixes that a block signals completion with
`done.state.<state id>`, and that record's outcome amendment 2c adds
`done.outcome.<state id>.<outcome>` for each declared outcome.
`StatifierBlocks.Compiler.StateId` is where both are spelled - `done_event/1`
and `outcome_event/2` - over a state id that is `"s_" <> block_id`
(`state_id/1`).

A block type whose `summary/1` describes its config in terms of one of those
events puts the whole generated string on the card. The chip-row amendment
above already quotes the neighbouring case, `core.on_event`'s
`Abandon, fraud.aborted`, and a chip naming a generated done event reads worse
than that one, because it is not a name anyone chose:
`done.outcome.s_blk_AUTH.error` is twenty-nine characters of which the author
wrote five.

The five characters are the whole point. `s_blk_AUTH` is the state id of a
block whose card, on the same canvas, says **Authorize**. Getting from one to
the other requires knowing ADR-0004 decision 3's derivation, and the card is
precisely the surface that should not require it. What the author declared
was an outcome called `error` on a block they named; what the card shows is
the compiler's spelling of that fact.

### Decision

**10w. A chip whose text has the shape of a generated done-event name is
drawn as `<block label> · <outcome>`, and the raw name is kept on the chip's
`title` attribute.** Two shapes are recognised, and each draws one way:

| Chip text | Drawn as | Where the parts come from |
|---|---|---|
| `done.outcome.<state id>.<outcome>` | `<block label> · <outcome>` | the state id inverts to a block id; the outcome is the segment after it |
| `done.state.<state id>` | `<block label> · done` | the state id inverts to a block id; `done` is the role `Core.Emit` mints the completion `<final>` under |

`<block label>` is the label the named block's own card draws - the author's
title where they gave one, and the type's label otherwise. That is
`StatifierBlocks.ViewModel.title/1`, read rather than re-derived here. The
second row draws the literal word `done` rather than inventing a name, because
`done.state` carries none: ADR-0004 decision 2 makes it the block's completion
signal and nothing more, and `StatifierBlocks.Core.Emit` reaches it through a
`<final>` under the role `"done"`. Spelling that role is honest; spelling
something friendlier would be this record naming a concept ADR-0004 does not
have.

The raw event name goes on `title`, verbatim and untruncated. That is the
half that keeps the translation lossless: an author debugging a chart against
generated SCXML, or a support engineer reading a screenshot beside a trace,
needs the exact string, and a translation that destroys it would trade one
unreadable card for one unanswerable question. `title` is where this record
already puts the exact form of a thing whose drawn form is shorter, and the
chip element is `.sb-node__chip` - the class the chip-row amendment above
introduced, unchanged, gaining an attribute rather than a sibling.

**10x. The translation is applied where the chip is built, ahead of the cap.**
`StatifierBlocks.BlockType.summary/2` is where refusal already happens, and
the translated text is what the cap measures, not the generated one.

The order is load-bearing and it is the reason this section can leave 10n and
10o alone. `done.outcome.s_blk_AUTH.error` is over the cap; measured before
translation it is refused, drawing nothing and raising the `:lint` finding the
2026-08-30 Note added - a warning telling the author that "summary chip 2 is
29 characters; the cap is 24, so it is not drawn" about a string they cannot
shorten, because they did not write it. That is the one failure mode this
section exists to prevent, and translating after the cap would install it.
Translating first, `Authorize · error` is seventeen characters, draws, and needs
no exemption from anything.

The ordering has a cost the implementing bead should see coming, named here
rather than discovered there. `summary/2` and `summary_refusals/2` both
derive from the declared chips of **one** block and its config; translating
needs the labels of other blocks, which neither can currently see. So this
clause requires widening what the summary pass is given, or moving the
measurement to where the document already is. Which of the two is the
implementing bead's call - this section decides the order, not the seam - but
the seam is real and no clause above provides it.

**10y. A name that does not invert unambiguously leaves the chip exactly as it
is.** No translation, no `title`, no finding, no refusal that would not
otherwise have happened - the chip goes through the existing path untouched
and the cap measures the string as written. This is the failure mode's
direction, chosen deliberately: a chip drawn as its raw event name is ugly,
and a chip drawn as the wrong block's label is a lie. The first is a
presentation defect an author reports; the second is a card that says a
different block completed.

"Unambiguously" is doing real work in that sentence, and the next section says
why.

### 10n and 10o are unchanged, and what "unchanged" means here

Neither clause moves, and neither is weakened.

**10n keeps its number**, and the cap keeps its one home: this section states
no length, sets no second threshold, and adds no opinion about how long a chip
may be. It changes what string the cap is applied to, in one enumerated case,
and 10x is the whole of that change.

**10o keeps refuse-never-truncate.** A translated chip that is still over the
cap - a block whose author-given label is long - is refused exactly as any
other over-long chip is refused, and it raises exactly the same `:lint`
warning at exactly the same severity. That case is the one the lint was built
for: the author gave the block its label and can shorten it, so the sentence
the Note builds names a fix the reader can act on.

**The cap lint therefore keeps firing for every chip an author can actually
fix**, which is every chip an author wrote. What this section exempts is the
narrow complement: chips no author wrote, whose text the compiler generated
from a derivation the author never sees. Those are not exempted from the cap
either, strictly - they are shortened before it, which is a different and
smaller claim than an exemption, and it is the claim 10x makes.

### What the implementing bead has to build, and what it must not assume

Three facts about the code as it stands today, recorded because a bead that
assumed otherwise would be building on something that is not there.

**No event-name parser exists.** `StatifierBlocks.Compiler.StateId` ships the
constructors - `done_event/1`, `outcome_event/2` - and inverts *state ids*
through `unstate_id/1` and `unoutcome_id/1`. Nothing inverts an *event name*.
The implementing bead adds that function, and it belongs in `StateId` for the
reason `unoutcome_id/1`'s own `@doc` gives about itself: the inversion belongs
beside the derivation it inverts, not inside a caller that would have to
rediscover why it is exact.

**Block-id opacity is a convention, not an enforced grammar.**
`StateId`'s moduledoc argues invertibility from ADR-0001 decision 3 - a block
id is "stable, document-unique, opaque and never reused", and "a `blk_`-prefixed
UXID contains no `__`". That is true of every id this package *mints*. It is
not true of every id this package *admits*:
`StatifierBlocks.Validation`'s block-id check accepts any non-empty UTF-8
string, so a document arriving through `from_json/1` may legitimately carry a
block id containing `__`, or `.`, or the literal text `done.state.`.

**The state-id inversions already rest on that convention too**, and this
record should not claim otherwise on the way to making a point about event
names. `unstate_id/1` splits on the *first* `__` and performs no role-shape
check of its own, so a block id carrying `__` misinverts there as well:
`unstate_id("s_a__b")` answers `{:ok, {"a", "b"}}`, which is a block id
nothing minted and a role nobody declared, where the honest answer for a
block whose id is `a__b` would have been `{"a__b", nil}`. That is checked
against the code, not reasoned about. It is invisible today only because
every id this package mints is a `blk_`-prefixed UXID, which is exactly the
convention this subsection is naming.

An event-name inversion is worse in degree rather than different in kind:
`done.outcome.s_A.B.C` has two readings when a block id may contain a dot,
and a dot is not even a character the derivation reserves. The point of
recording both is that the new parser inherits a hazard the existing
inversions have, rather than introducing one they are immune to.

Recording this is not a call to tighten the validator. That would be an
ADR-0001 amendment, it would refuse documents that are valid today, and it is
not this record's to make. It is a call to make the parser total and honest
about it, which is what 10y already requires.

**The fail-safe is therefore required, not advisory.** The implementing bead
returns "not a generated name" for every string it cannot invert to exactly
one `{block id, outcome}` pair, including a string that inverts to a block id
no block in this document carries - a chip may name a block that was deleted,
and a label looked up for a block that is gone is not a label. In every such
case 10y applies and the chip is drawn as written.

### What is not decided here

- **The badge and the join marker.** They share the chip pipeline and could
  carry the same translation. The 2026-08-30 Note declined to widen itself to
  them for the same reason and this section declines identically: widening is
  a bead and a Note, not something a reader should assume from this one.
- **Whether a translated chip is clickable.** A chip naming a block that is on
  the canvas is an obvious candidate for a jump, and decision 11's findings
  rows already have that affordance. It is not decided here, and 10w draws a
  span, not a control.
- **Any change to what a block type declares.** `summary/1`'s contract is
  ADR-0002 amendment H's and is untouched: a type keeps returning the strings
  it returns today, and no type is asked to spell an event differently because
  of this section.

### Consequences

- **A card can say less than the string behind it, and that is new.** Every
  other chip on the card is drawn as the type declared it. This one is drawn
  as a function of it, and `title` is what keeps that reversible. A test that
  asserts on chip text for a `done.*` summary changes; a test that asserts on
  a type's declared summary does not.
- **The view model gains a reader dependency it did not have.** Translating
  needs the labels of blocks *other than* the one whose card is being built,
  so the chip pass reads across the document rather than down one block. That
  is a real coupling and it is named here so the implementing bead does not
  discover it as a surprise.
- **`ViewModel.summary_chips/1` stays the public reader.** The 2026-08-30 Note
  named it as the function a host calls, and a host calling it gets translated
  chips - which is the point, since a host drawing its own card should not
  have to redo this.
- **No new token, no new class, no new hook, no new command.** Decision 14's
  markup/styling line, decision 7's two-hook count and decision 2's command
  set are all untouched.
- **Nothing serializes and nothing is stored.** The translation is derived at
  build time from a document that is already stored, exactly as the summary
  and the refusals are.

Filed with `sb-1hqt`, campaign-029's Lane G.

## Amendment (2026-09-05): the host seams, `on_select` and a selection descriptor

**Status: proposed (2026-09-05, campaign 029 Lane G, bead `sb-1hqt`).** A
decision record merges at proposed under campaign 029's invariant; flipping it
to accepted is a separate gated request. Additive; decisions 2, 8A and 15
stand as written and no text above this line is edited by this section. This
section is the record for bead `sb-0mwg`, and nothing here is built yet.

### Context

The editor keeps the selected block id as component state and offers the host
no way to observe it. `on_change` is the only callback the assigns table
carries that reports anything back, and it reports documents.

8A already decided that the package ships the editing surface and the host
ships the document chrome, and that the host's half attaches through "slots
for markup, events for actions". A host panel that wants to follow the canvas
selection - a per-block detail pane in the host's own chrome, a preview, a
side-by-side of the block's data - is exactly the case 8A's split anticipates,
and it is the case the split currently cannot serve: the editor is a
`LiveComponent`, so the host has no handle on its socket, and there is no
event carrying the one fact the panel needs.

The workaround a consumer actually reached for is worth recording, because it
is the cost. Building a per-block panel on 0.15, the consumer listed every
candidate block in the document in its own panel and made the operator pick
the block a second time, next to a canvas where they had just picked it. Two
selections that must agree, with nothing keeping them in agreement, is the
shape of defect 8A's seam exists to prevent.

The same argument the findings count made applies in the other direction and
is why this is a callback rather than a reader. `findings_count/3` is a pure
function of the assigns the host already holds, so the host can compute it
without asking the component anything. A *selection* is not: it is editor
state that only the component knows, produced by a gesture on the canvas, and
there is no pure function of the host's assigns that answers it. What cannot
be read has to be pushed.

### Decision

**An `on_select` assign, a one-argument function, called with each new
selection.** It sits beside `on_change` in the assigns table and has the same
shape and the same optionality: absent by default, ignored unless it is a
function of arity one, invoked for its effect and never for its return value.
`on_change`'s existing handling (`notify_change/2`) is the pattern, and
`on_select` gets its own sibling rather than overloading it, because a
document and a selection are different subjects and a host that wants one
should not have to receive the other.

**What it is called with is a selection descriptor, not a block.** A map:

| Key | Value |
|---|---|
| `id` | the selected block's id |
| `type` | the block's type name, as the document stores it |
| `label` | what the block's card draws as its first line - the author's title where they gave one, the type's label otherwise |

and `nil` for no selection.

Three keys and not the block, deliberately. The host already holds the
document - it passed it in - so shipping the block's config back through a
callback would make `on_select` a second channel for something the host can
already read, and a channel that goes stale the moment the two disagree. What
the host cannot derive is which id is selected; `type` and `label` come along
because a panel that has to render a heading before it looks anything up is
the common case, and because `label` is the view model's answer rather than a
rule a host would have to reimplement from H5.

**`nil` is a selection and is delivered like one.** Deselection calls
`on_select` with `nil`; a host panel that follows the canvas has to be able to
empty itself, and a callback that only ever fires on a *new* block leaves the
panel showing the last one forever. This is the same reading 3A's precision
takes of the Findings tab: a surface whose subject is missing says so, rather
than saying nothing.

**It fires when the selection changes, and not otherwise.** Not on every
render, not on an edit to the selected block, not on the component's first
render when nothing is selected. Selecting the already-selected block is not a
change and does not fire. The rule is the same round-trip discipline decision
6 sets for the drag: one message per thing that happened.

**No new command, and `on_change` is untouched.** Decision 2's command set
stays four plus the fifth the 2026-09-01 amendment added; selection is editor
state and not a document edit, so there is no `:select` command to add and
nothing about selection is serialized, stored, undone or redone. `on_change`
keeps reporting documents and only documents.

### Consequences

- **A host panel can follow the canvas, and the double-pick goes away.** That
  is the whole of what this buys, and it is 8A's split working as written: the
  package owns the canvas and the selection gesture, the host owns its own
  chrome, and one documented event crosses between them.
- **The host acquires no obligation.** `on_select` is optional and a host that
  does not pass it sees no change of any kind - no new assign it must supply,
  no new event it must handle.
- **The inspector is unaffected.** The package's own inspector reads the
  selection from component state as it does today; `on_select` is a seam out,
  not a rewiring of what is already inside.
- **A future descriptor key is additive.** The value is a map, so a host reads
  the keys it knows, which is the same compatibility argument the 2026-09-01
  note made for `candidates` and the 2026-09-04 note made for
  `value_candidates`.
- **This is not the per-palette-entry pane.** Decision 15's deferral of a
  "test this step" panel is not touched by a callback that reports which block
  is selected.

Filed with `sb-1hqt`, campaign-029's Lane G.

## Note (2026-09-05): decision 9, where a value picker's candidates come from, and the hint beside them

A dated note rather than an amendment: decision 9 is unchanged in every
particular, the `expression_component` seam and the three-clause order the
2026-09-04 note records stand exactly as written, and no text above this line
is edited by this section. Drafted 2026-09-05 as the record ahead of the code,
bead `sb-1hqt`, campaign 029 Lane G. It merges at proposed under the campaign
invariant like every other section filed with it.

What is recorded here is where a value picker's candidates come from when the
host supplies none, and a second, weaker thing drawn beside the field that is
deliberately not a candidate at all.

### The default feed: what the datamodel already declares

The 2026-09-04 note added `value_candidates` and said of it that "nothing in
this package interprets it, and that is the point: only a host knows which of
its own declared paths have a bounded set of values at all". That sentence is
right about the host and wrong about *only*. A datamodel document declares
one, per path, and this package already reads it.

**A path's value candidates default from the datamodel index's declared
enumeration - ADR-0006's `one_of` - and a host-supplied entry is merged over
them, per path.** `one_of` is ADR-0006's optional entry key, "a completion
hint listing the values a host expects", and it is carried through to the
index this package builds: `StatifierBlocks.Predicates.Datamodel`'s entry type
declares `one_of: [term()] | nil` and its decoder reads it. Nothing consumes
it today.

**Merged over, per path, means replacement at the path.** A path the host's
`value_candidates` map names uses the host's list and only the host's list; a
path it does not name keeps the declared enumeration; a path with neither gets
a free-text value control. Not a union, and the reason is that a union has no
author: if a host lists three values for a path whose datamodel declares five,
the host is correcting the datamodel for this editor, and a control that
answered eight would be showing a set nobody declared. Replacement makes the
host's entry mean what a host writing it plainly intends.

**This does not reopen ADR-0006's open question.** That record asks "whether
`one_of` is a hint or a claim" and carries it as a hint with no contract.
Defaulting a picker from a hint is a *use* of the hint, not a promotion of it:
nothing here validates a value against the list, nothing refuses a value
outside it, and a value control fed from `one_of` still admits anything the
author types. That is the same suggests-never-constrains posture the path
`<datalist>` takes and that 11e's advisory takes on an undeclared path, and it
is the posture this section keeps.

**One thing the implementing bead should not assume.** Neither of the two
functions a reader is likely to reach for hands the enumeration over.
`StatifierBlocks.Datamodel.candidates/3` answers a sorted list of path
strings and carries no per-path shape at all; `declared_view/3`, which is
what the Datamodel drawer tab draws, answers rows carrying `type`,
`item_type`, `scope`, `label` and `sensitive?`, and does **not** carry
`one_of`. The default feed reads the index entry through
`StatifierBlocks.Predicates.Datamodel`, not either of those. Whether the row
should also carry it is the Datamodel drawer tab's question and not this one.

### The hint: a fixture value, drawn beside the field, never an option

The second surface is weaker and is not a candidate feed at all.

**Beside the value field, this package draws a hint derived from the selected
block's fixture rows.** Its rule, in two halves:

- **The exemplar** is the value the selected block's **first fixture row in
  declaration order** binds to the path being edited. First, not most common
  and not most recent: an author reading their own fixtures reads them in the
  order they wrote them, and "the first one" is the only choice that needs no
  explanation and no tie-break.
- **The whole set** goes on the hint's `title` attribute: every distinct value
  the path takes across that block's rows, in first-appearance order. One
  glance for the shape of a value, one hover for the range of them.

The rows are the ones the `fixtures` assign already holds for the selected
block - `%{block_id => [TruthTable.t()]}`, keyed by block, read through
`Shell.tables_for/2` - and the values are `%TruthTable.Row{}`'s `bindings`,
which are keyed by path. Nothing new is stored, nothing new is passed in, and
a document with no fixtures source draws no hint.

**A hint is never an option.** It does not enter the picker, it is not merged
with `one_of` or with the host's map, and it cannot be picked. A fixture value
is an *example* - ADR-0006 draws exactly this line, quoting sui-ADR-0006 on
its own datasets: "datasets are examples, expectations are values, and a
schema layer stays optional-later". An example promoted into a dropdown
becomes a declaration the author never made, and the next author reads the
list as the set of legal values. The whole reason the hint is worth having is
that it costs nothing to be wrong about; putting it in the picker would make
being wrong about it expensive.

**And it adds no assign to the rendering package.** The value control an
`:expression` draws is statifier-ui's, reached through the seam clause 2 of
the 2026-09-04 note describes. The hint is not passed through that seam and
that component gains no key: this package draws the hint itself, as an element
beside the control, out of the `fixtures` it already holds. The seam's shape is
what makes clause 2 replaceable and clause 3 assertable, and a package-specific
hint threaded through it would be this record widening another package's API
to draw its own decoration.

**It is a hint, not a `placeholder`.** `StatifierBlocks.Editor.Field`'s rule
that exactly two control types carry a placeholder, and that neither is chosen
by key or by type name, is untouched: the hint is a sibling element with its
own text, not a third placeholder source, and that rule stays closed for
whoever amends ADR-0002 decision 7's field record.

### Consequences

- **A host that declares a datamodel gets value pickers it did not configure**,
  on exactly the paths whose entries carry `one_of`. A host that declares none,
  or whose entries carry none, sees what it sees today.
- **`value_candidates` narrows in meaning and not in shape.** It stays the
  same key with the same value; what changes is that supplying nothing is no
  longer the same as there being nothing.
- **The hint is per-block and follows the selection**, because fixtures are
  attached per block. A path edited on a block with no rows has no hint, and
  that is silence rather than an empty affordance.
- **Nothing validates and nothing refuses.** No finding is added, no severity
  is used, and decision 11's source enum is untouched.
- **No new command, no new hook, no new anchor, no new host assign.**

Filed with `sb-1hqt`, campaign-029's Lane G.

## Amendment (2026-09-05): 3A admits a Fixtures tab in the inspector

**Status: proposed (2026-09-05, campaign 029 Lane G, bead `sb-1hqt`).** A
decision record merges at proposed under campaign 029's invariant; flipping it
to accepted is a separate gated request. Additive; 1A, 2A and the drawer's own
Fixtures tab stand exactly as written and no text above this line is edited by
this section. Nothing here is built yet.

### The sentence this amends

3A, in full:

> **3A. The inspector is about the selected block, and carries exactly Config,
> Findings, Condition.** Anything about the document goes to the drawer. That
> is the whole rule, and it is worth stating as a rule rather than as a list
> because the list will grow and the rule will not. The document-level findings
> panel decision 13 names stays a document-level panel; the inspector's Findings
> tab is the selected block's findings, which is the distinction `sb-3l1` item a
> turns on.

and the paragraph under it:

> Datamodel and Fixtures, which the spike had as inspector tabs, are drawer
> tabs under this rule. They were never about the selected block.

The first sentence's own second half is what this amendment turns on: 3A says
of itself that the list will grow and the rule will not. This section grows
the list by one and leaves the rule exactly where it is.

### Why a fixture row is about a block

The rule's test is "about the selected block", and a fixture row passes it as
a matter of how fixtures are shaped rather than as an argument about them.

**A fixture row attaches to one block.** The `fixtures` assign is
`%{block_id => [TruthTable.t()]}` - keyed by block id, one bucket per block,
no document-level bucket and no row that belongs to two blocks. A row's
bindings build a context and its expectation names a slot *of that block*; the
drawer's own Fixtures tab compares the row's expected slot against the slot
the compiled chart took, which is a statement about the block that owns the
slots. There is no reading of a fixture row under which its subject is
something other than the block it is attached to.

So the selected block's rows are about the selected block, and a pane showing
exactly those rows is a pane about one subject - which is the whole of what 3A
requires of an inspector tab.

**And the 2026-08-30 precision already reads 3A as a rule rather than a closed
list.** It says so in as many words - "3A reads narrower than it is" - and
resolves a question the literal list could not answer, about what the Findings
tab does with no selection, by going to the rule instead: "What 3A forbids is
a pane that is about two subjects at once; what it does not require is a pane
that says nothing when its subject is missing." A record that has already been
read as a rule once, to admit behaviour its list did not mention, is read the
same way here.

### What the paragraph under 3A meant, and still means

"Datamodel and Fixtures, which the spike had as inspector tabs, are drawer
tabs under this rule. They were never about the selected block."

That sentence stays true of the surfaces it was about. The spike's Fixtures
tab, and the drawer's Fixtures tab that eventually shipped as
`sb-4yze`, are document-level: the 2026-09-02 amendment admits the drawer tab
under 1A precisely because it is "tabular - one row per fixture row - and it
is about the whole document, never about the block currently selected", and
repeats 3A's reason for keeping it out of the inspector. None of that moves.
The tab this section admits is a different pane with a different row set: the
selected block's rows, and nothing else, drawn where the selection already is.

### Decision

**The inspector's tab set becomes Config, Findings, Condition, Fixtures**, and
the rule stays "about the selected block; anything about the document goes to
the drawer".

**The tab is titled Fixtures, and the two Fixtures tabs coexist by pane.**
That is not a collision this section is tolerating - it is the arrangement the
inspector and the drawer already have. **Findings** is an inspector tab and a
drawer tab today, and the inspector's own module records why that is fine:
"The Findings tab is **not** the document-level findings panel". The
distinction that carries Findings carries Fixtures unchanged, and inventing a
second name for the same subject to avoid a repetition the record already
lives with would make the inspector harder to read, not easier. 3A's own
closing sentence is where that distinction is set - "the inspector's Findings
tab is the selected block's findings" against the document-level panel - so
the precedent is inside the clause being amended and not only in the module
that implements it.

**It shows the selected block's rows and no others**, and with no selection it
has no subject - the empty state the 2026-08-30 precision describes, not a
fourth surface and not a copy of the drawer's list.

**It is last in `Shell.inspector_tabs/0`.** Config keeps the first position
and therefore keeps the unchosen-tab resolution, which matters more in the
inspector than in the drawer: Config is what an author selecting a block is
almost always going to.

**It adds no assign, no command, no hook and no anchor.** The rows are the
`fixtures` the editor already holds, read through the same
`Shell.tables_for/2` the drawer's truth-table tab uses; decision 2's command
set, decision 7's two-hook limit and decision 11's finding anchors are all
untouched.

### What this does not decide

- **Whether the tab runs anything.** The drawer's Fixtures tab drives each row
  through the compiled chart via `Runtime.FixtureRuns.run/4`, which is a
  compile plus one chart run per row. Whether the inspector's tab shows
  verdicts or only the rows and their bindings is the implementing bead's
  question against 2A's own reasoning about what may sit inside a render, and
  this section deliberately does not answer it.
- **Whether fixtures become editable here.** They are not editable anywhere
  today, and admitting a pane is not admitting an editor.
- **Decision 15's per-palette-entry fixtures pane**, which stays exactly as
  deferred as decision 15 and the 2026-09-02 amendment left it. That pane is
  about a palette entry; this tab is about a block in a document.

### Consequences

- **The inspector's tab set is four and 3A governs it unweakened.** The rule
  is the same sentence it has been since 2026-08-29, and a future pane is
  admitted by it or it is not.
- **An author sees a block's fixtures where they selected the block**, without
  opening the drawer and finding their rows among every other block's.
- **The drawer's Fixtures tab is unchanged in every particular** - same rows,
  same verdicts, same count, same place in the tab order.
- **Two tabs read the same source and cannot disagree**, because they read the
  same `fixtures` assign through the same reader rather than each deriving its
  own.
- **A host contributing its own inspector content is unaffected**; the
  inspector has no host-tab seam and this section does not add one.

Filed with `sb-1hqt`, campaign-029's Lane G.

## Amendment (2026-09-05): decision 9, the `:duration` control reads one grammar

**Status: proposed (2026-09-05, campaign 029 Lane A, bead `sb-8acm`).**
Additive; no text above this line is edited by this section. It reverses one
clause of the 2026-08-29 amendment to decision 9 above, and it reverses it
because the premise that clause rests on turned out to be false.

### Context

The 2026-08-29 amendment settled `:duration` on one text control, with the
expression language's duration strings primary and the on-screen examples
`30s`, `15m`, `1h30m`, `2d`, `3d8h`. It kept a second, older calendar-style
spelling accepted beside them - the one this record's earlier prose uses in its
examples - and the third bullet of its Decision list is where the argument for
keeping it sits. That bullet gives two grounds: that the older spelling is one
ADR-0001 decision 6 already admits into `config`, and - the ground carrying
the "so" - that it is what documents already written hold, so a field refusing
it would refuse values that exist.

The second of those is not a design preference. It is a factual claim about
documents in the world, and it is the operative reason the field carries two
grammars rather than one: the first ground says only that `config` permits the
older spelling, never that the editor must offer it. Campaign 029 checked the
factual one before building anything further on it.

**The premise is false.** Every place the sweep found the older spelling is a
place this package owns: the prose of these records, the moduledocs and
refusal messages of the modules that implement the control, a plan document,
and this package's own test corpus throughout - the `test/fixtures/`
documents, the support modules that build them, and inline literals across the
suite alike. It found no author-written document holding one. There are no
values already written for a stricter field to refuse - there is only this
package's own corpus, which this package migrates itself, in this campaign.

A clause that exists to protect documents which do not exist protects nothing,
and what it costs is paid on every field: two grammars in one input, two ways
for a value to be wrong, a canonicalisation step between them, and an author
who has to be told which of two spellings the field is failing.

### Proposed decision

**9a. The `:duration` control reads one grammar, the expression language's.**
The 2026-08-29 amendment's table row stands as written - one text control, the
expression language's duration strings, the examples on screen. What changes is
a bullet beneath it: the older spelling is **no longer accepted** in a
`:duration` field. A value that grammar does not parse is a format finding,
whatever else it might once have meant.

**9b. The falsified premise, named.** The clause 9a reverses is the third
bullet of the 2026-08-29 Decision list, the one whose operative ground is that
existing documents hold the older spelling and a field refusing it would refuse
values already written. It is reversed on the fact, not on a change of taste:
the documents it names were looked for and are not there. That bullet's other
ground - that ADR-0001 decision 6 already admits the spelling into `config` -
is answered on the merits by 9e below: decision 6 permits the spelling, and
permitting is not requiring. Every other bullet of that amendment stands,
including that empty means the key is omitted, that the stored form is the
author's string verbatim, and that format is validated inline before the
document gate.

**9c. There is no pivot any more, because there is nothing to pivot from.** The
2026-08-29 amendment described a compile that reads the author's string and
canonicalises it through the older spelling before emitting. With one grammar
in and one rendering out, that middle form has no reader left: the stored
string is parsed to the expression language's normalised duration and rendered
straight to the attribute the engine reads. Two things follow that the older
arrangement could not give. Sub-second and fractional-second spellings become
expressible - and the reason is narrower than "the older spelling could not
hold them", because it could: that grammar admits a decimal fraction on its
smallest component. What blocked them was this package's own renderer of it.
`StatifierBlocks.Core.Duration`'s private `render/1` answers `:error` for any
normalised duration still carrying milliseconds, and the component writer
beneath it emits every field as an integer, so a value with a millisecond
left in it had no form that renderer could write and therefore no canonical
form on that path. Remove the middle form and that renderer goes with it. And
the verbatim-storage property gets cheaper rather than dearer: one grammar in
means the stored bytes and the compiled value can disagree in fewer ways.

**9d. Wording is part of this decision, not a matter of style.** No refusal
message, on-screen example, field hint, test name or line of documentation in
this package names the retired spelling. A message that names it teaches it,
and a grammar taught in a refusal is a grammar an author will reach for next.
The refusals say what is accepted - "must be a duration like `30s` or
`1h30m`" - and stop there. There is exactly one exception in the whole
package: a single migration line in the release changelog, so that a reader
holding an old value can find out what became of it. That line is written
once, by the bead that cuts the release, and nowhere else.

**9e. What ADR-0001 decision 6 still supplies.** Decision 6's no-floats rule is
why a duration is a string in `config` at all, and 9a does not touch it. What
changes is only which strings the editor will put there. The document schema
still sees an opaque string, and this record still does not restate the
grammar: which strings parse, how a fraction expands, how a repeated unit
accumulates, and what the calendar-approximating units mean are all
`Predicator.Duration`'s to define, exactly as the 2026-08-29 amendment set it.

### Consequences

- **This record now disagrees with itself in prose, deliberately.** Sentences
  above this line use the retired spelling as a live example, and they stay
  exactly as written: a record's history is not edited, and 9a is applied the
  way every amendment in this file is applied, by superseding from below. A
  reader who meets one of those sentences and this section together should read
  this section as the rule and that sentence as what was true before it. The
  prose that does get brought into line is the *code's* - moduledocs, refusal
  messages and on-screen hints - because those are read as instructions rather
  than as history.
- **The code follows this record and does not precede it.** The recogniser
  change, the refusal wording and the fixture migration land on `sb-4r1p`.
  Until they do, the shipped control is what the 2026-08-29 amendment
  describes.
- **It is a breaking change, and the release says so.** A document holding the
  older spelling stops validating, and a public function whose only job was to
  produce that spelling goes. The sweep is the argument that the blast radius
  is this package's own corpus; the release carries its migration line
  regardless, because a sweep can only see what it can reach.
- **ADR-0002 decision 7's closed field-type set is untouched, again.**
  `:duration` is still one of the seven field types and still holds a string.
  Its cross-reference beside decision 7, and the `core.send` row's G2a, are
  superseded in one clause each by a dated Note of this date in that record
  rather than rewritten here.
- **ADR-0001 decision 6's worked example is spelled in the older grammar**, and
  a dated Note of this date in that record says so. The example demonstrates
  opacity and no-floats, and it demonstrates both just as well once its
  fixture migrates.
- **The datamodel half is ADR-0006's, and `sb-b05e` has recorded it.** That
  bead ran on this same lane and amended that record on its own; its amendment
  has landed, and nothing here reaches into it either way. This section is
  about the `:duration` control and the block config it writes; what a
  declared datamodel entry of duration type means is that record's subject,
  and this one decides nothing about it.

Filed with `sb-8acm`, campaign-029's Lane A. The lane's other record change is
`sb-b05e`, against ADR-0006; it landed as a request of its own, and this
section neither depends on it nor touches what it recorded.

## Amendment (2026-09-05): decision 2, a compound command, and a palette entry that names a recipe

**Status: proposed (2026-09-05, campaign 030 Lane S0, bead `sb-8vkc`).** A
decision record merges at proposed under campaign 030's invariant; flipping it
to accepted is a separate gated request. Additive; decision 2's table of edits
stands exactly as written, decision 3's round-trip law is unchanged, and no
text above this line is edited by this section. Nothing here is built yet -
`sb-qfl1` implements.

### Context

ADR-0010 decision 1, accepted 2026-09-02, settles that a clock interrupt is not
a block type but an arrangement of two: a `core.send` carrying the deadline
event and a `delay`, placed as the first block of a group's `body` slot, and a
`core.on_event` naming the same event on that group's `interrupts` slot
(`docs/adr/0010-clock-interrupt-spelling.md`, decision 1, "No `core.timeout`.
The pair is the spelling"). It makes the case on the vocabulary's own admission
test - a type whose whole content is a spelling of an arrangement the
vocabulary already expresses does not join the vocabulary - and it names what
that costs: the author writes two blocks rather than one, into two different
slots of the same group, in a fixed order, naming one event string twice.

The palette does not carry that arrangement, and the reason is structural
rather than an oversight. A palette entry today is one block type and one
insert: `StatifierBlocks.Palette` is a map from `type_name` to module
(`lib/statifier_blocks/palette.ex:38-43`), the browser draws an entry per
resolvable name, and arming one produces a single `{:insert, target, block}`
for the position the author armed. There is no entry that puts down two blocks,
and none that puts a block anywhere except where the author aimed.

Two things follow, and they are the whole of this section's context. First, the
knowledge is nowhere: which slot each half belongs in, that the send goes first
in `body`, and that the two halves must name the same event are facts an author
has to hold in their head, and a record they will not have read is where those
facts live. Second, a half-built arrangement is not one undo away. Two picks
are two commits, so undoing "the deadline" is two gestures with a state between
them in which the deadline event is armed and nothing on the rail catches it -
a document that compiles, and compiles to a chart that abandons on an event no
handler answers.

Both are the same shape of problem: an arrangement the vocabulary expresses but
the authoring surface cannot name. This section names it, in two parts - a
composition in the algebra, and an entry in the palette that produces one.

### Decision

**2n. `Edit.t()` admits a composition, and the set of edits stays five.**
The algebra grows one constructor:

    {:compound, [t()]}

carrying a non-empty list of commands. `Edit.apply/2` applies them left to
right against the intermediate documents; the inverse it returns is the
compound of each step's inverse **in reverse order**. A member that refuses
refuses the whole compound - `apply/2` answers `{:error, term()}` and no
document at all, so there is no partially applied document for a caller to
mistake for a result - and the refusal is the
member's own error term, unchanged, so a caller reads why rather than that
something in a list failed.

Two properties are the reason for the constructor rather than a loop in the
shell. `Edit.History` pushes one inverse per commit, so a compound is **one
undo entry**: one gesture in, one gesture out, and no state between the halves
that the author can stop in. And `check_config/3` runs on the compound's leaves
through the same funnel every other command goes through
(`lib/statifier_blocks/edit/history.ex`), so "invalid config never reaches the
document" holds for a composed edit exactly as it holds for a single one.

**A compound is not a sixth edit, and decision 2's closure argument is
unrevised.** Decision 2 says every author gesture produces exactly one of a
named set, and defends the size of that set by showing the obvious extras are
not primitive: reordering is a `:move`, duplication is an `:insert`,
"inserting from the palette is an `:insert`". A `:compound` adds no meaning to
that set. Its leaves are drawn from it and nothing else - a compound whose list
is empty, or contains a `:compound`, is refused rather than flattened - so
every edit a document can undergo is still one of the five, and the sentence
decision 2 is defending stays true word for word. What is new is a rule beside
it: **a gesture may produce a composition of those edits, and the composition
is what the history remembers.**

This revises one bullet of the 2026-09-01 amendment's Consequences, the one
reading "The command set is five and the reason it is closed is unchanged."
The count is unchanged and so is the reason. What that bullet did not have to
distinguish, because nothing then composed, is the set of edits from the set of
`Edit.t()` constructors: after this clause those are five and six. Read the
bullet as the claim about edits it was making, and read this clause as saying
where the sixth constructor sits - above the five, never beside them. 2a's own
test is untouched either way: a presentation state still does not become a
command, and a compound is not a presentation state.

**1C. A palette may name recipes as well as types.** `StatifierBlocks.Palette`
gains a second map beside `types`:

    recipes: %{optional(String.t()) => module()}

registered as a value exactly as types are, and by the same functions: the
`recipes:` option on `new/2`, and `{name, module}` registrations in
`from_modules/2`'s ordered list, where **later entries win**. The collision
rule is therefore the one that already governs types - a host that registers
its own recipe under a core recipe's name reads its own, because it wrote it
later (`lib/statifier_blocks/palette.ex:143-147`). Everything the `Palette`
moduledoc says about what a palette *is* applies to the second map unchanged:
it is a caller-supplied value built once per operation, there is no global
registry, and two hosts in one runtime resolve independently.

The names live in one namespace per map, not one across both. A recipe named
`"deadline"` and a type named `"deadline"` do not collide, because nothing
resolves a name without knowing which map it is asking - a document's
`type_name` is looked up in `types` and only there, and a palette browser entry
carries which of the two it came from. ADR-0002 decision 2's map from
`type_name` to module is untouched by this clause, and decision 10's core
vocabulary table does not grow: a recipe is not a block type, has no
`type_name`, and can appear in no document.

**2C. A recipe is a module implementing two callbacks.**

    @callback insert(target :: Edit.target(), document :: Document.t()) ::
                {:ok, [Edit.t()]} | {:error, term()}
    @callback palette_entry() :: BlockType.palette_entry()

`palette_entry/0` is decision 10's map, in every particular: the same optional
keys, the same total normalizers, the same fallback to the entry's name when
it is absent. A recipe draws in the palette browser the way a type draws, and
that is deliberate - the author picking a deadline is not doing a different
kind of thing from the author picking a send, and an entry that announced
itself as a special kind of entry would be teaching a distinction the author
does not have to make.

`insert/2` is where a recipe differs from a type. It is handed the armed
position and the document, and it answers with the commands that build the
arrangement - a list the caller wraps in a single `{:compound, commands}` and
commits. It is pure: it mints no ids of its own beyond what decision 2 already
requires of an `:insert` (ids are minted at gesture time and baked into the
command), it reads the document rather than writing it, and it may refuse.
A refusal is the ordinary case where the arrangement does not fit - see 3C -
and it is an error term, never an exception.

**3C. A recipe reaches the armed position and the enclosing group, and nothing
above it.** The commands `insert/2` returns may target:

- the armed position itself, exactly as a type's insert does; and
- **any slot of the block that encloses the armed position** - its parent -
  including slots other than the one armed.

They may target nothing else. A command naming a block above the enclosing
group, a sibling's interior, or the document root when the root is not the
enclosing group, is refused by the caller before it is applied, and the whole
compound goes with it.

The bound is the deadline's own shape rather than a round number.
ADR-0010 decision 1 puts the `core.send` in the group's `body` and the
`core.on_event` on that same group's `interrupts` rail: an author who arms the
head of a group's `body` and picks "deadline" is reaching exactly one level
out, to the rail of the group they are already inside. That is the widest reach
any arrangement in the accepted vocabulary asks for, and it is a reach the
author can see - the enclosing group is on screen, drawn around the position
they armed. A recipe that could write two levels up would move blocks into a
region the author is not looking at, and no accepted record asks for one.

`insert/2` refuses rather than reaching further. A "deadline" armed at a
position whose enclosing block declares no `interrupts` slot - a
`core.sequence`, say, whose moduledoc says so in terms
(`lib/statifier_blocks/core/sequence.ex:14`) - has nowhere to put its handler,
and
answers `{:error, ...}` naming that. The refusal is a refused gesture, not a
finding: nothing is written, so there is nothing for the view model to say
anything about.

**4C. Core registers one recipe, `"deadline"`.** `Palette.core/0` carries it in
`recipes`, built from the pair ADR-0010 decision 1 spells: a `core.send` at
index 0 of the enclosing group's `body` carrying a `delay` and a generated
deadline event name, and a `core.on_event` on that group's `interrupts` slot
naming the same event. Both halves are ordinary blocks of ordinary core types;
the recipe is the knowledge of how they go together and nothing more.

It sits in `Palette.core_recipes/0` beside `Palette.core_types/0`
(`lib/statifier_blocks/palette.ex:87`), and a host composes the two
maps the same way - `Palette.new/2` with both, or `from_modules/2` with
`core: true`. A palette built without it is as valid as a palette with it,
which is the property `core_types/0` already has and which this clause does not
weaken: nothing in this package has a privileged path to a recipe either.

### What this does not decide

- **Whether a recipe can edit an existing arrangement.** `insert/2` builds; it
  is not a refactoring seam, and there is no `remove/2` beside it. Deleting a
  deadline is deleting two blocks, and it is two gestures until some record
  says otherwise.
- **Whether the palette browser groups recipes apart from types.** 2C says a
  recipe draws as an entry; where entries sit relative to one another is
  decision 10's `group` and `order` keys doing what they already do, and a
  layout ruling is not taken here.
- **Anything about the compound outside the editor.** The compiler never sees
  an `Edit.t()`, the wire format carries documents rather than commands, and
  no transport question is opened by the constructor.

### Consequences

- **The deadline becomes one gesture and one undo.** An author picks
  "deadline" at the head of a group's body and gets both halves, correctly
  slotted, with one event name written twice by the recipe rather than twice
  by them. Undo removes the arrangement, not half of it.
- **Decision 3's round-trip law gains a case rather than an arm.** The inverse
  of a compound is the compound of inverses reversed, so
  `apply(apply(d, e), inverse) == d` follows from the law holding of each
  member. The property test generates a compound of generated commands; it does
  not need a law of its own.
- **`Edit.apply/2`'s error surface does not grow.** A compound answers with a
  member's error term verbatim, so nothing that reads those terms - the
  history, the shell, a test - learns a new shape.
- **A host gets recipes without a new mount seam.** `Palette` is already the
  value a host builds and hands in (decision 15's single-session editor); the
  second map rides the same value, so no assign, no option and no callback is
  added to the editor's host surface.
- **ADR-0002 is untouched, and this section says which parts on purpose.**
  Decision 2's `type_name`-to-module resolution, decision 10's vocabulary
  table and its count, every `config_schema/1`, and the block-type behaviour's
  callback list all stand exactly as they are. A recipe implements a callback
  pair of its own, not `StatifierBlocks.BlockType`, and `palette_entry/0` is
  the only name the two share.
- **`sb-qfl1` builds it, and this record precedes the code.** Until it lands
  the palette holds types only, and the deadline is the two picks ADR-0010
  describes.

Filed with `sb-8vkc`, campaign-030's Lane S0.

## Amendment (2026-09-05): decisions 10 and 11, a palette entry may declare how many of it a document holds

**Status: proposed (2026-09-05, campaign 030 Lane S0, bead `sb-8vkc`).** A
decision record merges at proposed under campaign 030's invariant; flipping it
to accepted is a separate gated request. Additive; decision 10's existing keys
stand exactly as written, decision 11's anchor enum and routing table are
unchanged, and no text above this line is edited by this section. Nothing here
is built yet - `sb-vl93` implements.

### Context

Every rule that reaches an author as a **finding** is local. `validate_config/1`
is handed one block's config and answers about that config
(`lib/statifier_blocks/block_type.ex`). `SlotValidation` is handed a parent and
its children. Assignability is a relation between one block's outputs and its
neighbour's inputs. The view model's two derived sources are both per-block:
`:resolution` on a block that does not resolve, `:config` on a resolved block's
config, one finding per `{key, message}` pair
(`lib/statifier_blocks/view_model.ex:15-28`).

The package does hold two whole-document rules already, and naming them is what
makes the gap legible rather than contradicting it.
`StatifierBlocks.Validation.validate/1` refuses a document whose block ids are
not unique across the whole tree, and one whose datamodel entry ids are not
unique (`lib/statifier_blocks/validation.ex:49-52` and `:120-127`). Both are
**structural refusals**: conditions a document may not be in at all, answered
before anything renders, and neither is a thing an author is shown beside a
block and asked to fix. What this section is about is the other kind - a rule a
host declares, that a document may sit in violation of while the author works,
and that therefore has to be *shown* rather than refused.

There is a class of rule a host wants that none of those can express, because
its subject is the document rather than any block in it: **how many of this
block type the document may hold, and where.** A host whose vocabulary carries
a "start here" block wants exactly one of it, at the top. A host with a
settlement step wants at most one. Today the only way to say either is for the
host to check the document itself, after the editor has handed it back through
`on_change`, and to render the answer somewhere the editor is not - which is to
say, not beside the block the author would have to move.

Decision 11 already has the surface such an answer belongs on. What it does not
have is a producer that can see the whole document, and decision 10 has no key
a host can use to ask for one. This section adds the smallest thing that closes
that: a declaration, and one rule that reads it.

### Decision

**10z. `palette_entry/0` gains an optional `singleton` key.**

    optional(:singleton) => :head | :anywhere

Absent means unconstrained, and that is the default every entry has today: an
entry that does not carry the key is read exactly as it is read now, and no
existing entry changes meaning. The two values say how many and where:

| Value | What the document must hold |
|---|---|
| `:anywhere` | exactly one block of this type, at any position |
| `:head` | exactly one block of this type, and it is the first child of the root's first slot |

`:head` is `:anywhere` plus a position, not a different kind of claim - both
say "exactly one", and only `:head` says where. There is no `:at_most_one` and
no `:at_least_one`: an entry either constrains the count to one or does not
constrain it, and a host that wants a looser rule has the callback 11o's last
paragraph defers rather than a third value here.

The key is presentation metadata in the same sense every other decision-10 key
is - inert data a host declares and this package reads - and it is read through
the same discipline: an entry carrying a value that is neither atom is read as
absent, never as an error, because a palette entry is a host's data and
decision 10's normalizers refuse rather than raise.

**11o. `ViewModel` derives a third source, and it is a `:config` finding
anchored at the root.** `build/3` walks the document once more, counting blocks
per `type_name` whose resolved entry carries `singleton`, and emits a finding
when the count is wrong:

| Declared | Document holds | Finding |
|---|---|---|
| `:anywhere` or `:head` | no block of that type | one finding, "this document needs a ..." |
| `:anywhere` or `:head` | two or more | one finding naming the count |
| `:head` | exactly one, not at the root's first position | one finding naming where it is |

One finding per violating type, not one per surplus block: the author's problem
is the arrangement, and a document holding four of something would otherwise
draw four findings saying the same sentence.

Its `source` is `:config` - the enum member
(`lib/statifier_blocks/finding.ex:63`) that already means "a declared shape
says so", which is what a `singleton` declaration is. Its severity is `:error`,
like the other two derived sources.

Its **anchor is `{:block, root_id}`**, and that needs saying plainly because
decision 11's anchor enum has three members and none of them is a document
(`lib/statifier_blocks/finding.ex:39-42`). This section does not widen the
enum. A document-scoped finding needs an anchor that exists, the root block is
the one block every document has
(`lib/statifier_blocks/document.ex:47-55`, where `root` is typed `Block.t()`
rather than optional), and the root is the document's own representative on
screen - so the finding routes by the existing table's `{:block, id}` row, onto
the root node's chrome, and into the document-level panel that reads the whole
findings list. No route is added and no route changes.

**A finding, never a fix-up.** Nothing here inserts a missing block, removes a
surplus one, or moves one to the head. The editor says what is wrong and the
author acts, which is decision 11's whole posture: findings are what the editor
knows, and edits are what the author does. An automatic repair would also be
unsound at the only moment it would fire - a document is briefly wrong in the
middle of every arrangement an author builds by hand, and a rule that repaired
it would fight them.

**What this seam defers, named rather than left open.** A `singleton`
declaration is a count, and a host will want rules a count cannot state: two of
these only if that one is absent, this block must precede that one, no more
than three. Those are a **host `validate_document/1` callback** - a seam by
which a host supplies its own whole-document rule and gets its findings routed
like these - and that callback is **not decided here and not in campaign 030**.
This section deliberately ships the narrow case rather than the general one,
because the narrow case is expressible as data a host declares and the general
one needs a callback, an anchor vocabulary wide enough for a host's own rules,
and an answer to what happens when a host's rule and a declared `singleton`
disagree. Naming the follow-up is the point of the paragraph: `singleton` is
not a first instalment of that callback, and a host reading it as one will
build against a seam that does not exist yet.

### Consequences

- **Decision 10's key set grows by one and its posture does not.** Every key
  there is optional, host-declared, and inert; `singleton` is all three. An
  entry that omits it is the entry it is today.
- **Decision 11's enum, anchors and routing table are untouched.** The new
  finding uses an existing source, an existing anchor shape and an existing
  row of the routing table. This section adds a producer, not a mechanism.
- **`ViewModel` gains its third derived source, and the moduledoc's "exactly
  two" sentence is superseded by this clause** - by reference, in the form this
  file uses for a superseded count: the 2026-09-01 amendment supersedes decision
  2's "four, not seven" rather than rewriting it in place (`:4114-4118`). The sentence is not rewritten
  here; `sb-vl93` brings the moduledoc into line with this record, because
  moduledocs are read as instructions rather than as history.
- **The count is one document walk, and it is the walk `build/3` already
  makes.** No second traversal, and nothing here depends on the compiler
  having run.
- **A host that declares nothing pays nothing.** With no entry carrying the
  key, the counting arm has no types to count and emits no finding, so a
  palette that has never heard of this key produces a view model identical to
  today's.
- **`sb-vl93` builds it, and this record precedes the code.**

Filed with `sb-8vkc`, campaign-030's Lane S0.

## Note (2026-09-05): decision 9, clause 9d has a second exception, and it is a migration

A dated Note rather than an amendment: the 2026-09-05 amendment to decision 9
above stands in every particular, `9a` still admits one grammar and `9d` still
governs what the package's prose may name. No text above this line is edited by
this section. Drafted 2026-09-05 as the record ahead of the code, bead
`sb-8vkc`, campaign 030 Lane S0; it merges at proposed under the campaign
invariant like every other section filed with it, and flipping it to accepted
is a separate gated request. `sb-me4u` implements.

### What 9d left the older documents with, and why that is a gap

9d is a wording rule, and it is a good one: a message that names a retired
spelling teaches it. But the amendment it belongs to also made a document
holding the retired spelling **stop validating**, and its own Consequences say
so - "a document holding the older spelling stops validating", named there as
the breaking half of the change. The sweep behind `9b` is the argument that the
blast radius is this package's own corpus, and that corpus has migrated. What
the sweep could see is not everything there is: it reached this repository, and
a document a host stored is somewhere else.

So the position 9d leaves is that such a document, if one exists, opens in the
editor as a `:duration` field carrying a value the field refuses, with a
refusal that - correctly, per 9d - will not tell the author what the value used
to mean. The author is handed an unreadable string and a message that names
only what is accepted.

This Note records the answer, which is not a wording change: **the value is
migrated rather than refused**, through the mechanism ADR-0002 decision 8
already provides for exactly this.

### The decision

**A `type_version` bump on the two types that declare a `:duration` field.**
`core.wait` and `core.send` each go to `current_version/0` of 2 and each
implements `migrate_config/2`, which rewrites a stored `:duration` value in
the retired spelling into the equivalent value in the accepted one and leaves
every other config key alone. A stored value that is already in the accepted
spelling, or that is empty, or that is in neither spelling, is passed through
untouched - migration answers `{:ok, config}` there, because a value the
migration cannot read is a value the field's own refusal is the right answer
for, and a failed migration is a resolution error that would render the block
unopenable rather than fixable.

The two types, and nothing else:

| Type | `current_version/0` today | after | Config key migrated | Field declaration |
|---|---|---|---|---|
| `core.wait` | 1 (`lib/statifier_blocks/core/wait.ex:39`) | 2 | `"duration"` | `:duration`, required, default `"1h"` (`:45-54`) |
| `core.send` | 1 (`lib/statifier_blocks/core/send.ex:102`) | 2 | `"delay"` | `:duration`, optional, default `""` (`:115-131`) |

Neither implements `migrate_config/2` today, and neither reaches the
behaviour's `__using__` default either: both declare `@behaviour
StatifierBlocks.BlockType` rather than `use` it
(`lib/statifier_blocks/core/wait.ex:25`, `lib/statifier_blocks/core/send.ex:91`),
so the default arm at `lib/statifier_blocks/block_type.ex:124-130` is never
injected into them and the callback is simply not exported. The path a
behind-version block of either type takes today is the no-callback arm ADR-0002
decision 8's 2026-08-27 amendment already fixed: `Palette.resolve/2` finds no
exported `migrate_config/2` and answers
`{:error, {:migration_failed, block_id, :no_migration_available}}`
(`lib/statifier_blocks/palette.ex:262-269`). Nothing reaches that arm while
`current_version/0` is 1, because no block can be behind - and it is exactly
the arm that starts firing the moment it becomes 2, which is why implementing
the callback is not optional on this bump. They are the package's first two
users of that callback; the callback itself
is unchanged and has existed since the behaviour was written
(`lib/statifier_blocks/block_type.ex:304-310`). There is no third `:duration`
field in the shipped vocabulary to reach, which the 2026-09-05 Note in ADR-0002
already establishes and this section does not re-derive.

**It runs at open, and writes nothing back.** ADR-0002 decision 8 fixes all of
this and none of it is new here: migration runs at resolution time, is a single
hop from the stored version straight to `current_version/0`, is applied to the
in-memory block only, and leaves the stored `type_version` as stored. A host
that wants the migrated bytes persisted saves the document, which is a host
decision on the host's own `revision` axis. What an author sees is a field
holding a readable value, and what the store holds is unchanged. What a
subsequent save writes is not decided here - the last bullet under "What this
Note does not do" says why, and where it is deferred to.

**The recogniser is private, and it is reachable from nowhere else.** The
retired spelling is read by one module, `StatifierBlocks.Core.DurationMigration`
(`lib/statifier_blocks/core/duration_migration.ex`), which is `@moduledoc
false` and called by exactly two functions: the two `migrate_config/2`
implementations named above. It is **not** consulted by `validate_config/1`, by
`Core.Config`, by `DurationInput`, or by any other reader, and nothing it
returns reaches a message. A `:duration` field still reads one grammar, which
is `9a` unweakened: the migration runs before the field ever sees the value,
and by the time the field sees it there is one spelling in play.

**What 9d's exception becomes.** Of the retired spelling 9d says: "There is
exactly one exception in the whole package: a single migration line in the
release changelog". That count is revised, and this is the single sentence of
9d this Note touches. The exceptions are now:

1. the changelog's migration line, as 9d has it; and
2. `duration_migration.ex` and its own test file - the recogniser has to
   recognise the thing, and the test has to hold a whole retired-spelling
   string to pin that it does.

Everything else 9d says is unrevised and binding: no refusal message, no
on-screen example, no field hint, no test name and no line of documentation
outside those two files names the retired spelling. The corresponding
acceptance line on the campaign-029 code bead `sb-4r1p` - "No refusal message,
on-screen example, test name or doc line names the retired spelling; the only
repo-wide mention is the changelog fragment's single migration line" - is
revised in the same one place and no other: *the only repo-wide mentions are
that changelog line, the migration module, and the migration module's test.*
That bead is closed and its work landed; nothing here reopens it, and this
sentence records which of its criteria a later reader should read against this
Note rather than as written.

**It is compatible with the wording rule it revises, and deliberately so.** The
grammar a `:duration` field parses names nothing retired. Every refusal, hint
and on-screen example names nothing retired. What names it is a private module
no author, message or document can reach, and a test that exists to keep that
module honest. The rule 9d is defending - a grammar taught in a refusal is a
grammar an author will reach for next - is untouched, because nothing here is
taught to anyone.

### What this Note does not do

- **It does not revise `9a`, `9b`, `9c` or `9e`.** One grammar in, one
  rendering out, the falsified premise, and what ADR-0001 decision 6 supplies
  all stand exactly as written.
- **It does not make the retired spelling storable again, and it does not
  claim opening a document rewrites it.** The field refuses the retired
  spelling the moment an author types it, which is `9a` unweakened. But the
  migration runs inside `ViewModel.build/3`, through `Palette.resolve/2` on
  each block as the view model is derived
  (`lib/statifier_blocks/view_model.ex:772`, `:826`, `:879`), and the document
  the editor holds - the one it hands back through `on_change` - is the
  document it was given. So a block the author never touches round-trips its
  stored bytes, retired spelling included. Whether the editor should adopt the
  migrated config into its held document at open is a real question and this
  Note deliberately does not answer it: it is **deferred to `sb-me4u`**, which
  either decides it or records it as still open. What this section relies on is
  only what decision 8 guarantees - that this package does not write migrated
  bytes back on its own.
- **It does not change `validate_config/1` on either type**, or either type's
  `config_schema/1`, `slots/1`, outcomes or emitted SCXML. The bump is to
  `current_version/0` and the addition is `migrate_config/2`; the shipped
  shape of both types is otherwise what it is at `main`.
- **It does not decide what a host does with a migrated document.** Persisting
  is the host's, per ADR-0002 decision 8, and this section adds no hint, no
  option and no callback about it.

Filed with `sb-8vkc`, campaign-030's Lane S0.

## Note (2026-09-05): the 2026-09-05 decision-9 amendment, seven corrections to its record apparatus

A dated Note about the 2026-09-05 amendment to decision 9 above and about the
2026-09-05 Note at the end of this record. Nothing either decides moves: `9a`
still admits one grammar, `9b`'s falsified premise is still falsified, `9c`
still abolishes the middle form, `9d` still governs what this package's prose
may name, `9e` still leaves the grammar to `Predicator.Duration`, and the
second exception the closing Note adds is unrevised. No text above this line
is edited by this section. Every correction was raised in review against the
request that added the section it concerns and routed to a follow-up rather
than cured in place, so each merged artifact stayed the artifact its review
read. Recorded under campaign 030's fill lane D; it merges at proposed under
the campaign invariant, and flipping it to accepted is a separate gated
request.

### 1. The amendment's own status line, completed

That amendment's status line reads "**Status: proposed (2026-09-05, campaign
029 Lane A, bead `sb-8acm`).**" (`:5476`). Every 2026-09-05 section around it
carries a second sentence it omits - that a decision record merges at proposed
under the campaign invariant, and that flipping it to accepted is a separate
gated request. The three nearest are the campaign-029 Lane G sections above
it, which name that same campaign's invariant (`:4897-4899`, `:5109-5111`,
`:5339-5341`); the three campaign-030 sections below it say the same of
campaign 030's (`:5612-5614`, `:5838-5840`, `:5992-5994`). The omission is in
the line, not in the fact: that amendment merged at proposed like every one of
them, and accepting it is a separate gated request. Read the missing sentence
into it.

### 2. Where the older spelling actually survives

Two passages under-count, in two different ways, and both are worth a line
because the sweep is the whole argument for `9b`.

**The sweep paragraph's stated shape.** It lists "the prose of these records,
the moduledocs and refusal messages of the modules that implement the
control, a plan document, and this package's own test corpus throughout"
(`:5499-5506`). Two places the sweep reached are not in that list:
`CHANGELOG.md`, and the `spike/` tree. In the spike the older spelling is
named in `spike/README.md`, in five files under `spike/js/`, in a comment in
`spike/css/editor.css`, in `spike/dev/selftest.html`, and in one prose line
inside `spike/fixtures/documents/card-processing.json:15`. It is worth being
exact about that last one: the spelling is named there in a comment string,
and no spike fixture *authors* a duration in it - `card-processing.json`
writes its deadline as `15m`. Neither omission weakens the finding, because
what the sweep concludes is that no *author-written* document holds the
spelling, and a changelog entry and a laboratory are as much this package's
own as a fixture is. What a stated shape omitting two of the places searched
costs is a later reader's confidence that they were counted rather than
missed.

**Clause 9d's exception count, and what "the whole package" denotes.** `9d`
as written says there is "exactly one exception in the whole package: a
single migration line in the release changelog" (`:5557-5560`). The
2026-09-05 Note at the end of this record already revises that count, from one
exception to two - the changelog's migration line, and the private recogniser
together with its own test file, which is two exceptions spanning three files
(`:6077-6094`). What no section has yet said is that the revised count is
still short, and by how much.

`CHANGELOG.md` names the older spelling in more than the migration line.
Three bullets of the accepted `0.3.0` entry name it as shipped behaviour of
that day (`CHANGELOG.md:1143-1146`, `:1147-1151`, `:1152-1154`). They are
history rather than instruction, they stay exactly as written, and no bead
migrates them. The `spike/` tree names it in the places listed above, and
nothing migrates those either. That directory opens "Status: exploratory. This
is a laboratory, not the product" and rules that where it and an accepted
record disagree the record is the contract (`spike/README.md:1-26`), which is
why no bead has been filed to bring it into line. Whether that makes the spike
an exception to `9d` or text `9d` was never written to reach is a question this
Note leaves open, exactly as it leaves the changelog bullets open below.

**This corrects a count and declines to re-scope the rule.** `9d`'s own words
bind what this package's prose *names*: no refusal message, on-screen example,
field hint, test name or line of documentation, with the exceptions the record
and its closing Note enumerate. Nothing here narrows that: the whole
repository is still in scope, `test/` and `docs/` emphatically included - the
closing Note's own second exception covers a test file, which would be
incoherent otherwise. What is corrected is the arithmetic of the phrase
"exactly one exception in the whole package", which was already false when it
was written and is corrected here rather than defended. Whether the released
changelog bullets and the spike are best recorded as further exceptions, or as
text the rule was never written to reach, is a question for whoever next amends
`9d`; this Note deliberately does not answer it, because answering it would be
a decision and this is a correction. No message, hint or example gains
permission here either way.

### 3. `9b`'s "every other bullet" is wider than it means

`9b` closes: "Every other bullet of that amendment stands, including that
empty means the key is omitted, that the stored form is the author's string
verbatim, and that format is validated inline before the document gate."
(`:5529-5532`). The 2026-08-29 amendment's Decision is five bullets
(`:1864-1882`) followed by three standalone bold paragraphs (`:1884`,
`:1887`, `:1892`). Two of the three things `9b` names are bullets; the
stored-form clause is one of the standalone paragraphs. Read the sentence
with the wider referent it needs - every other clause of that amendment's
Decision - and then with the one exclusion that wider referent forces: the
emit-time paragraph at `:1887-1890`, which has a compile canonicalise through
the middle form before emitting, does **not** stand, because `9c` is exactly
its reversal. The three clauses `9b` names are unaffected, and so is every
clause not named here.

### 4. One fact, two tenses

The amendment's Consequences say ADR-0002 decision 7's cross-reference and
the `core.send` row's G2a "are superseded in one clause each by a dated Note
of this date in that record" (`:5590-5594`), while that Note says both
passages "stand exactly as they were written on 2026-08-29" until this
amendment is accepted. The two sentences describe one fact from opposite
sides of the same acceptance. The Note's is the governing one, because the
supersession is by reference and a reference to a proposed section does not
take effect before that section does. Read the Consequences bullet as "are
superseded, on this amendment's acceptance, in one clause each".

### 5. `sb-b05e`'s request landed; its amendment is proposed

The last Consequences bullet says "`sb-b05e` has recorded it" and that "its
amendment has landed" (`:5599-5601`). The request merged; the section it
merged carries **Status: proposed**
(`docs/adr/0006-datamodel-document.md:455`), and accepting it is a separate
change on its own gate. Read "has landed" as "has merged, at proposed" - the
same reading every 2026-09-05 section in this family gets, this one included.

### Two readings the sections below ask for

Raised against the request that filed them and left unedited there for the
same reason:

- **"It runs at open" names the occasion, not an exclusive one.** The closing
  Note's title and its heading sentence (`:6057`) say "at open" because that
  is the occasion an author meets. The migration runs wherever
  `Palette.resolve/2` runs, which in `lib/` is ten call sites across seven
  modules, and in `test/` is nineteen more across seven files: the compiler
  (`lib/statifier_blocks/compiler.ex:361`), the view model
  (`lib/statifier_blocks/view_model.ex:772`, `:826`, `:879`), slot validation
  (`lib/statifier_blocks/slot_validation.ex:78`), assignability
  (`lib/statifier_blocks/assignability.ex:384`, `:566`), the edit path
  (`lib/statifier_blocks/edit.ex:219`,
  `lib/statifier_blocks/edit/targets.ex:267`) and the datamodel walk
  (`lib/statifier_blocks/datamodel.ex:655`). That Note claims no exclusivity
  and nothing it says is wrong; this bullet exists so a reader does not infer
  one.
  - [Note 2026-09-05, `sb-5omq`: the enumeration after "seven files:" lists
    the ten `lib/` call sites, not the seven `test/` files - the colon
    attaches to the `lib/` clause above it, and the `test/` occurrences are
    counted here rather than named.]
- **"Walks the document once more" is the same walk, not an extra one.**
  Clause 11o says `build/3` "walks the document once more, counting blocks
  per `type_name`" (`:5909`), and a Consequences bullet below it says "No
  second traversal, and nothing here depends on the compiler having run"
  (`:5975-5977`). The bullet is the operative one: the counting happens
  inside the traversal `build/3` already makes. Read 11o's phrase as "counts
  as it walks", not as a second pass.

Filed with `sb-a9r8`, campaign-030's fill lane D.

## Amendment (2026-09-05): decision 11, the host's own whole-document rule, and what a lone deadline half is not

**Status: proposed (2026-09-05, campaign 031 lane H, bead `sb-w2m1`).** A
decision record merges at proposed under campaign 031's invariant; flipping it
to accepted is a separate gated request. Additive; decision 11's source enum,
severity enum, anchor enum and routing table are unchanged, clause `10z`'s
`singleton` key stands exactly as written, and no text above this line is
edited by this section. **Nothing here is built in campaign 031.** Clauses
`11p` to `11t` are a record ahead of their code, and the bead that implements
them is campaign 032's, filed beside the host's first rule; clause `11u`
decides that a case produces no finding, so it has no code to wait for.

### Context

The 2026-09-05 amendment above shipped the narrow whole-document rule - a
count, declared as data on a palette entry - and named the general one as its
follow-up rather than leaving it open: a **host `validate_document/1`
callback**, "not decided here and not in campaign 030" (`:5950-5960`). That
paragraph also named the three things such a callback needs before it can be
built: a seam by which a host supplies its own whole-document rule, an anchor
vocabulary wide enough for a host's own rules, and an answer to what happens
when a host's rule and a declared `singleton` disagree. This section answers
all three, and nothing else about it.

It answers a second question in the same breath, because the two turn out to
be one question read from opposite ends. `sb-5ju0` asks whether a group holding
only the deadline's `core.send`, or only its `core.on_event`, produces a
finding. ADR-0010 decision 6 anticipated an advisory of that shape and
deliberately did not decide it, filing "when either half stands alone"
(`docs/adr/0010-clock-interrupt-spelling.md:269-273`) with the two arms beside
it, and its deferred list routes the whole item here in terms: "its findings,
their severity, and whether 'the send is not the head of the body' is a warning
or silence. ADR-0005's findings layer and the declaration-advisory work own it"
(`docs/adr/0010-clock-interrupt-spelling.md:345-347`). Deciding the seam without deciding the case it was cited for
would leave the case where it has been since 2026-09-02, and deciding the case
without the seam would leave the answer with nowhere to live.

The two are one question because a lone half is not a fact about a block. It is
a fact about a document, and it is order-sensitive and cross-block - the same
class as "a model step needs a decision before an act", which is the class
`validate_document/1` exists for.

### Decision

**11p. `Palette` gains `validators`, and a host's whole-document rule is a
module on it.** The struct grows a fourth field
(`lib/statifier_blocks/palette.ex:56-62`):

    validators: [module()]

defaulting to `[]`, supplied through a `:validators` option on `new/2` beside
`:recipes` and `:assignability` (`lib/statifier_blocks/palette.ex:80-86`), each module implementing

    @callback validate_document(document :: Document.t()) :: [finding_spec()]

as `StatifierBlocks.DocumentValidator`.

It rides the palette because the palette is already the value a host builds and
hands in, and because two host-supplied modules already ride it: the
`assignability` relation of ADR-0003 decision 6 (`lib/statifier_blocks/palette.ex:69-73`) and clause `1C`'s
`recipes`. A host that declares a rule adds a module to the value it was
building anyway - no assign, no mount option and no editor callback is added,
which is the property `1C` established for recipes and this clause does not
weaken.

It is a **list rather than a map**, and ordered. There is no name to key on,
nothing resolves a validator by name, and nothing collides: every module in the
list runs, in list order, and a later entry does not replace an earlier one.
That is deliberately not the `types`/`recipes` rule - those are lookups, where
last-wins is what a host overriding a core entry needs, and this is not a
lookup.

**A validator is not a block type and not a recipe.** It implements one
callback of its own, it appears in no palette browser, it has no
`palette_entry/0`, and it can appear in no document. `StatifierBlocks.BlockType`
and `StatifierBlocks.Recipe` are untouched by this clause.

**11q. The argument is the `Document.t()`, and that is the whole view.** The
callback is arity one, and what it is handed is the document as authored.

It is not handed the `Palette`, because the host built the palette and handing
it back would be handing a caller its own value. It is not handed the
`ViewModel`, because the view model is what is being built when the callback
runs - a rule that could read it would be reading a half-built value, and one
that could read a finished one would need a second pass this section does not
buy. And it is not handed a compiled chart, because the compiler has not run
and must not have to: a document is briefly wrong in the middle of every
arrangement an author builds by hand, and a rule that only spoke after a
successful compile would be silent at exactly the moments the author needs it.
This is `11o`'s posture and not a new one - "nothing here depends on the
compiler having run" (`:5975-5977`).

What a `Document.t()` carries is what a whole-document rule needs: every
block, its `type`, its config and its position in its parent's slots. "A model
step needs a decision before an act" is a statement about type names and order,
and both are there.

**11r. A validator says where and what; the package says which source.** A
member of the returned list is

    {anchor, message} | {anchor, message, opts}

where `anchor` is decision 11's existing anchor (`lib/statifier_blocks/finding.ex:39-42`), `message`
is a string, and `opts` is a keyword list carrying `:severity`.

This is `validate_config/1`'s division of labour, one level up. That callback
answers `{key, message}` pairs and the package builds the anchor and stamps the
source (`lib/statifier_blocks/view_model.ex:1026`); a document rule needs to
name its own anchor, because its subject is not the one block whose config was
handed to it, but it does not get to name its own source.

**The source the package stamps is `:lint`.** It is the enum member
(`lib/statifier_blocks/finding.ex:63`) that already means "the editor applied a rule" rather than "a
declared shape says so", which is `11o`'s reason for `:config` and is exactly
what a `singleton` declaration is and a host's rule is not. It is also the only
member with the full severity range: `11b` reserves `:info` to `:lint`, and
`11i` admits `:error` on it, so a host rule can say all three things a rule
wants to say. A host cannot claim `:compile` or `:resolution` for its own rule,
which is the point of stamping rather than accepting.

**Severity defaults to `:warning`, not to `:error`.** That is a departure from
`Finding.new/4`'s own default (`lib/statifier_blocks/finding.ex:90`, `:100` of that file) and the reason is
decision 11's definition of the words: `:error` says the document does not
compile, and a host rule cannot make a document not compile - the compiler
never sees a validator. A host may still pass `severity: :error`, and it means
what a host means by it: *my* gate refuses this document. A consumer gating on
`:error` is then told so, which is the point of allowing it.

**Total, never raising, on its own data.** A returned term that is not a list,
and a member that is neither of the two shapes above, is read as **no
finding** - decision 10's normalizer discipline, applied to a host's return
value. An exception raised inside the callback is not caught, exactly as
`validate_config/1`'s is not (`lib/statifier_blocks/view_model.ex:1026`): a host's code raising is
that host's bug, and swallowing it would hide it at the only moment it is
visible.

**11s. The anchor vocabulary is the one that exists, and the root carries a
document-scoped rule.** The enum keeps its three members and no fourth is
added. A rule whose subject is a particular block anchors at that block, by
whichever of the three rows fits, and renders where that row already sends it.
A rule whose subject is the document anchors at `{:block, root_id}` and reaches
the drawer's document-level findings list - which is `11o`'s route, taken for
`11o`'s reason: the root is the one block every document has
(`lib/statifier_blocks/document.ex:47-55`), and "anything about the document
goes to the drawer" is decision `1A`/`3A`'s arrangement doing what it already
does. No route is added and no route changes.

**An anchor naming an id the document does not hold is already handled, and it
is the existing safety net rather than a new refusal.** `ViewModel.build/3`
splits every finding on whether its block id is in the document and puts the
misses in `orphan_findings` (`lib/statifier_blocks/view_model.ex:423-424` and `:434` of that file), unrendered. A
host rule that names a stale id lands there with everything else that does. So
this clause adds no validation of a host's anchors, no error term and no
refusal path: the mechanism that catches the case predates the seam.

**`orphan_findings` is that and only that.** The name means "a finding whose
anchor names a block id this document does not hold" in the view model, and in
the compiler it names a second thing already - the findings gathered from the
children of a block whose own type did not resolve
(`lib/statifier_blocks/compiler.ex:405-410`). Two meanings is one more than a
name should carry, and clause `11u` below is deliberately not given a third.

**11t. It runs inside the one walk, after the derived sources, and a
disagreement with `singleton` is shown rather than reconciled.** The validators
run in `ViewModel.build/3`, in the palette's list order, after the three
derived sources and before the `findings` argument the compiler's findings
arrive in. The resulting order is fixed by the palette rather than by a map's
iteration, for the reason `singleton_findings` sorts (`lib/statifier_blocks/view_model.ex:841-853`):
a findings list whose order moved between builds would be a rendering that
moved for no reason the author can see.

A host rule may contradict a declared `singleton` - the palette says a document
needs exactly one settlement step, the host's rule says two are fine when a
third block is absent - and **both findings are emitted, unreconciled**. The
package cannot reconcile them: reconciling would mean understanding the host's
rule, which is the thing this seam exists because it cannot do. Suppressing
either one would make one of the host's two declarations a lie, and the host
made both. The two are distinguishable where it matters - the derived one is
`:config` and the host's is `:lint` - and a host that does not want both stops
declaring `singleton` for that type, which is a one-line change to a value it
owns.

**A finding, never a fix-up**, unchanged from `11o`: a validator returns
findings and returns nothing else. It cannot edit the document, and no
`Edit.t()` is reachable from it.

**11u. A lone deadline half is not a finding, and it is not an orphan.** A
group holding only the deadline's `core.send`, or only its `core.on_event`,
produces **no finding** from any source this package derives. This is the
answer to `sb-5ju0` and to the third arm of ADR-0010 decision 6.

| The group holds | What it is on its own terms | Finding |
|---|---|---|
| only the delayed `core.send` | a delayed send: a step that arms an event to arrive later and completes in the same macrostep (`lib/statifier_blocks/core/send.ex:24-30`) | none |
| only the `core.on_event` on the rail | an event handler: a rail catch for an event sent elsewhere in the chart, or by the host at runtime | none |

Three reasons, and the first is the one that decides it.

**The pair has no representation in the document.** Clause `4C` says it in
terms: both halves are ordinary blocks of ordinary core types, and "the recipe
is the knowledge of how they go together and nothing more". That knowledge
lives at gesture time and is not written down. Nothing marks a `core.send` as a
deadline's send, so there is no such thing as *the* deadline half to find
missing - there is a send, and a question about whether some author once
intended a partner for it.

**Both shapes are the ordinary case, not a degraded one.** A delayed
`core.send` with no rail handler is a fire-and-forget timer, and a `core.on_event`
with no local sender is the ordinary rail catch: `core.raise` and `core.on_event`
have been coupled across a document since the vocabulary had a rail
(`docs/adr/0010-clock-interrupt-spelling.md:245-249`), and the sender may be
another subtree, or the host. A finding here would fire on documents that are
right, which is the failure mode a findings layer can least afford - decision
11's advisory arm is worth nothing to an author who has learned to ignore it.

**What is left is a whole-document question, and it now has a seam.** The
residue of `sb-5ju0` is real and worth naming: "is this event ever sent?" and
"is this event ever caught?". Both are cross-block, both are about the document
rather than any block in it, and neither is answerable by this package, which
does not know the set of events a host sends at runtime. A **host** does know,
and a host that wants the rule writes it as a `validate_document/1` validator
under `11p` - in its own vocabulary, where "this send is a deadline" is
something it can actually tell. That is the routing this section exists to make
available, and it is the reason the two decisions are one record.

**The one deadline finding this package does emit needs both halves, and that
is not incidental.** ADR-0010's `RQ-026-6` Note ruled a resumable-group
advisory, and it shipped on `sb-dj1p` as the compiler's `:emit`-stage
`deadline_lost_on_resume` finding
(`lib/statifier_blocks/compiler.ex:741-758` and `:795-809` of that file). It
fires only where a delayed `core.send` heads a `core.resumable_group`'s `body`
**and** that same group's `interrupts` rail carries a `core.on_event` whose
`outcome` is `resume`: `armed_head?/1` and `resumes?/1` are conjoined
(`:756-757` of that file). A group holding one half satisfies one conjunct and
never the other, so the one deadline-shaped finding the package has is already
silent on exactly the case this clause decides. What lets that finding speak is
a **recognised pair** - two blocks whose relationship the compiler can read off
the document it is handed. A lone half offers it nothing to read, and this
clause declines to invent a substitute.

**The name, if the rule is ever written, is "a lone deadline half."** It is not
an orphan. `orphan` already means an anchor naming a block this document does
not hold (`11s` above), and a lone half is the opposite case in every
particular: the block is present, resolves, compiles, and is exactly where the
author put it.

### What this does not decide

- **The other two arms of ADR-0010 decision 6.** A delayed `core.send` and a
  rail `core.on_event` on the same group whose event names do **not** match,
  and a deadline send that is not the head of the body, are recognisable shapes
  in a way a lone half is not, and they stay exactly where that record's
  deferred list left them (`docs/adr/0010-clock-interrupt-spelling.md:345-347`).
  This section answers the standalone arm and touches neither of the others.
  `sb-dj1p`'s resumable-group advisory is untouched too: it closed in campaign
  027 and clause `11u` above says why it is silent on a lone half rather than
  changing anything about it.
- **Whether any validator ships in this package.** `Palette.core/0` gains
  nothing here. Core declares types and one recipe; it declares no rules about
  documents, and a palette built without validators is as valid as one with
  them - the property `core_types/0` and `core_recipes/0` already have.
- **Ordering or priority among validators.** They run in list order and every
  one of them runs. Nothing lets one validator suppress another's finding, and
  no record asks for it.
- **A validator in the compiler.** The compiler never calls one. Everything
  here is the view model's, which is to say the editor's, and a document that
  compiles with a host's rule violated still compiles.
- **Whether a host rule can reach outside the document.** `validate_document/1`
  is pure and is handed one value. A rule needing the datamodel, a fixture or a
  network call is a host's own concern, evaluated before it builds the palette
  or after it reads `on_change`, and this seam neither helps nor hinders it.

### Consequences

- **`10z`'s named follow-up is answered, and `singleton` is not retroactively
  an instalment of it.** That paragraph warned that a host reading `singleton`
  as a first instalment "will build against a seam that does not exist yet".
  The seam exists as a record now and as code in campaign 032; the warning
  stands unedited, because the two remain different things - a declared count
  and a written rule.
- **Decision 11's four enums and its routing table are still untouched.** This
  section adds a fourth producer, on an existing source, through existing
  anchors, onto existing routes. Every amendment to decision 11 since
  2026-08-30 has been able to say some version of that sentence, and it is not
  an accident: the mechanism was built to take producers.
- **`ViewModel` gains a fourth source of findings and no fourth traversal.**
  The validators are called once each per build, on the document they are handed
  whole; nothing walks it again for them.
- **A palette that declares nothing pays nothing.** With `validators: []` -
  every palette today - the arm has no modules to call and the view model is
  identical to today's.
- **`sb-5ju0` is answered in the negative and needs no code.** Its acceptance
  criterion asked for a record decision saying whether a lone half is a finding,
  its class and its anchor; the answer is that it is not one, so there is no
  class and no anchor to state, and the tests and the sabotage case its "if yes"
  arm named are not written. The behaviour the package has today - a send-only
  group and an on_event-only group each compiling with zero findings, which is
  what campaign 030 machine-checked on `sb-qfl1`'s branch - is the behaviour
  this record blesses rather than a gap in it.
- **`sb-qfl1`'s retired criterion is retired by a decision, not by silence.**
  That criterion read "removing one half yields the finding the compiler already
  emits for an orphan", and it rested on behaviour the package never had and on
  a name that means something else. It is answered here: there is no such
  finding, and there was never an orphan.
- **This record precedes the code for `11p` to `11t`, and a campaign 032 bead
  builds them beside the host's first rule.** Until then a palette holds types,
  recipes and a relation, and a host with a whole-document rule checks the
  document itself after `on_change`, which is where clause `10z`'s Context
  found it.

Filed with `sb-w2m1`, campaign-031's lane H.

## Note (2026-09-06): decision 11 and the Datamodel tab carry the typed environment, and the "seven field types" count is stale

A dated Note rather than an amendment, carrying two items. It records where
something decided elsewhere renders here, and it corrects a count in a
consequences bullet above. Nothing this record decides changes and no line
above is edited.

### 1. Where the typed environment lands

`ADR-0011` replaces `ADR-0003`'s data-flow seam with a pre-order walk carrying
an environment from datamodel path to type. Its decision 9 fixes what that
environment makes available to an author, and says in as many words that how
either surface is drawn stays this record's. The two places are:

- **Findings carry the declared label.** A finding about a datamodel path
  names the declaration's `label` - required on every entry and on every
  `sd-ADR-0001` type declaration - rather than only the dotted path. This is
  decision 11's message copy, not a new source and not a new severity.
- **The Datamodel tab lists the environment at the selected block.** The
  drawer's fifth package tab, `:datamodel` (the 2026-09-02 Note on decision 1A
  above), is a read-only view over the datamodel document; it gains "what is
  known here", the paths the environment holds at the selected block's
  position with their types. It could not have answered that before, because
  nothing computed a per-position answer.

Two clauses of decision 11 are reached by `ADR-0011` and neither is rewritten.
Clause **11e**'s `:info` advisory for a path outside the declared set keeps its
severity, its wording, and the three sources 11k feeds it: `ADR-0011` decision
5 rules that a read of a path the environment does not hold **stays** that
`:info`, on 11f's own grounding argument that the advisory answers a claim
somebody actually made. What is new is a second, different failure - an
**unsatisfied read**, where a write and a read make claims that cannot both be
true - and `ADR-0011` decision 5 gives that one the validation `:error`
standing `ADR-0003` decision 8 gave `{:type_mismatch, ...}`. Clause **11n** and
every other clause are untouched.

One widening of an existing advisory follows and it is worth naming because it
closes a gap this record's own layer had: `core.on_event`'s `capture` keys are
datamodel paths that reached 11e's advisory through no field declaration, so
paths a capture writes were invisible to the pass covering every other
datamodel path. `ADR-0011` decision 10 makes a capture's target paths write
signatures, which puts them in front of the same advisory by the same
mechanism as every other path. `sb-sy0q` builds the two surfaces and `sb-xk1h`
the capture control.

### 2. The count in the 2026-09-05 duration amendment's consequences

That amendment's consequences say, of `ADR-0002` decision 7's closed
field-type set, that "`:duration` is still one of the seven field types and
still holds a string" (`:5589`). The sentence's point - that the set is
untouched by the duration change - is correct and unchanged. **The number is
stale.** `ADR-0002`'s amendment of the same date added an eighth member,
`{:path, opts}`, so the set has eight. Read the bullet as "one of the field
types"; nothing else in it moves, and the line stays where it is because
amending it in place would edit an accepted section to fix a count a dated
Note can carry.

## Note (2026-09-06): the 2026-09-05 corrections Note's `Palette.resolve/2` enumeration is a census, and it has moved

A dated Note rather than an amendment. It re-counts one enumeration in the
2026-09-05 corrections Note above and says what kind of claim such an
enumeration is. Nothing this record decides changes, no line above is edited,
and the reading the enumerated bullet was written to give is untouched.

### What the bullet says, and when it was exact

The first of that Note's "Two readings the sections below ask for"
(`:6263-6280`) argues that "it runs at open" names the occasion an author
meets rather than an exclusive one, and supports that by counting where
`Palette.resolve/2` is actually called: "in `lib/` ... ten call sites across
seven modules, and in `test/` ... nineteen more across seven files", followed
by the ten `lib/` cites.

Those numbers were exact on the commit that merged them (`e22849b`,
2026-09-05). `lib/` held ten calls across seven modules on that tree, and
`lib/statifier_blocks/slot_validation.ex:56` was excluded from the count,
correctly, as a doc mention rather than a call.

### The census as of `02fa1dc`

`lib/` now holds **fourteen** calls across **eight** modules: assignability
(`lib/statifier_blocks/assignability.ex:384`, `:566`), the compiler
(`lib/statifier_blocks/compiler.ex:361`), the datamodel walk
(`lib/statifier_blocks/datamodel.ex:655`), the edit path
(`lib/statifier_blocks/edit.ex:270`,
`lib/statifier_blocks/edit/targets.ex:267`), the editor shell
(`lib/statifier_blocks/editor.ex:1622`, `:1684`), slot validation
(`lib/statifier_blocks/slot_validation.ex:78`) and the view model
(`lib/statifier_blocks/view_model.ex:820`, `:924`, `:1010`, `:1093`,
`:1180`). `slot_validation.ex:56` is still a doc mention and still not
counted.

Three movements account for the difference, all of them later than `e22849b`:

- the view model went from three calls to five - `:924` arrived with the
  cardinality seam (`5d7de42`) and the fifth with the host's subchart
  outcomes (`0ae8c3f`);
- the editor shell became the eighth module, with two calls, when the body's
  outcomes reached `core.on_event`'s event field (`66b5874`);
- the remaining cites moved by line only, not by existence: `edit.ex:219` is
  now `:270`, and the view model's `:772`, `:826` and `:879` are now `:820`,
  `:1010` and `:1093`.

The `test/` half is unchanged: nineteen occurrences across seven files,
`test/support/core_fixtures.ex` among them.

### What this does and does not settle

The bullet's argument does not depend on the arithmetic. "At open" names the
occasion whatever the census is; a larger count strengthens the point rather
than qualifying it, and the 2026-09-05 sub-note on that bullet - that the
enumeration after "seven files:" lists the `lib/` sites and not the `test/`
files - reads exactly as it did.

What this Note settles is the standing of such an enumeration. **A call-site
count in this record is a census dated to the section that took it, not a
claim about the code at any later date.** A reader citing one re-counts it
against the tree first, and a section that takes a fresh one says which commit
it counted on, as this one does. Both counts above are taken on `02fa1dc`; a
later commit that adds or removes a caller moves them again, and falsifies
neither this Note nor the one above it.

Filed with `sb-06al`, campaign 032's docs fill.

## Note (2026-09-06): clauses `11p` to `11t` have code, and three things the amendment left to the implementation

A dated note rather than an amendment. It records that the section above is no
longer a record ahead of its code, and it says how three points that section
left open were settled in the building. Nothing this record decides changes,
no clause is edited, and no line above this one is touched.

### The merge

`11p` to `11t` shipped with `sb-nyla`, campaign 033's second-pass code lane.
`StatifierBlocks.Palette` carries `validators`, defaulting to `[]`, supplied
through a `:validators` option on `new/2`; `StatifierBlocks.DocumentValidator`
is the behaviour, with `validate_document/1` as its one callback; and
`StatifierBlocks.ViewModel.build/3` runs the palette's validators after the
per-block derived sources and before the `findings` argument, stamping `:lint`
and defaulting the severity to `:warning`.

The seam is the one `11p` names and no other. **No assign, no mount option and
no editor callback was added**, which is the property `1C` established for
recipes and `11p` said this clause does not weaken. The implementing bead's
own title describes the callback as sitting "beside `on_change`"; what that
describes is when a host's rule speaks, not where it is declared, and where it
is declared is the palette, exactly as `11p` says.

The drawer needed no change at all. A validator's finding reaches the Findings
tab through decision 11's existing anchors and the existing routing table, and
the row already carries the source chip that says which rule is speaking -
which is the claim this section's Consequences makes ("this section adds a
fourth producer, on an existing source, through existing anchors, onto
existing routes") arriving as a rendering test rather than as prose.

### 1. `singleton` runs on the same path, and keeps `:config`

The declared rule and the written one are now **one mechanism**: the palette's
`singleton` declarations state their findings in the same
`{anchor, message} | {anchor, message, opts}` vocabulary a validator uses, go
through the same normalizer, and run in the same arm of
`ViewModel.build/3` - the declared rule first, then the validators in the
palette's list order, which is the order `11t` fixes.

What did **not** move is the source. A `singleton` finding is still `:config`
at `:error`, and a validator's is `:lint` at `:warning`. That is `11r`'s own
distinction doing its work: `:config` says a declared shape is not satisfied,
`:lint` says the editor applied a rule, and `11t` requires the two to stay
distinguishable where a host's rule contradicts a declared `singleton`. The
shared path is the mechanism; the stamp is the meaning, and only the mechanism
was shared.

`singleton` is therefore not itself a `DocumentValidator`, and could not be:
`11q` hands the callback the document and only the document, and the
`singleton` rule reads the palette, which is where a host declared it.

### 2. What "read as no finding" covers, member by member

`11r` says a returned term that is not a list, and a member that is neither of
the two shapes, is read as no finding. Three cases the clause does not
enumerate were settled the same way, all of them by the same reading -
a member this package does not recognise is not a finding, and nothing is
raised or refused back at the host:

| The member | What happens |
|---|---|
| a third element that is not a keyword list | no finding: `{anchor, message, opts}` declares `opts` a keyword list, so this is not that shape |
| an anchor outside the three rows of `11s` | no finding |
| a message that is not a string | no finding |

One case is settled the other way, and it is the only one: a `:severity`
outside decision 11's three-valued enum falls back to the **default severity**
rather than dropping the finding. The member is the declared shape, its anchor
and message say something true about the document, and an unrecognised option
value is not a reason to silence a rule that fired. This is the narrowest
reading of "total on its own data" that keeps the finding, and it is recorded
here because `11r` does not name the case.

Anchors are still not validated against the document. An anchor naming an id
this document does not hold lands in `orphan_findings` through the split
`11s` points at, which is what that clause says should happen.

### 3. The moduledoc count `11o` left stale

`11o`'s Consequences superseded `StatifierBlocks.ViewModel`'s "exactly two
derived sources" sentence without giving it a replacement number, and the
sentence has been carrying a superseded count since. It now states the true
one: **five**, with the list beneath it as the thing counted. Nothing in this
record depends on the number; it is recorded here because two sections above
sent a reader to that moduledoc.

Filed with `sb-nyla`, campaign 033's second-pass code lane. The moduledoc
count in item 3 is the item `sb-q1r4` was holding for this bead; the two
record-prose items that bead also carries are untouched here and stay with
it.

---

## Note (2026-09-06): the run pane, and why the event log is not a drawer tab

A dated note rather than an amendment. Nothing this record decides changes, no
clause is edited, no line above this one is touched, and nothing here widens
1A's admission test or adds a region to the shell. What it records is where a
new surface went and, more usefully, why 1A did not claim half of it - because
the 2026-08-29 shell amendment's rule reads onto an event log at a glance, and
a reader who applies it that way would conclude the code contradicts this
record.

### What the pane is

The editor accepts a **run** - statifier-ui's `StatifierUI.Live.State`, live
or persisted - and while one is seated the canvas is drawn inside a pane that
composes statifier-ui's `status/1` and `scrubber/1` above it and its
`event_log/1` below. The canvas takes the seat an ops view gives a Mermaid
diagram, and that diagram is not mounted: the blocks the author wrote are a
better drawing of the same chart, and they are already laid out and already
markable. Scrubbing or clicking a log entry moves the run's selection, and the
marks the canvas draws are re-resolved from it on every render.

The three surfaces are statifier-ui's, drawn as statifier-ui ships them. No
statifier-ui module changed for this, no wire type was added, and the two
events the components emit are renamed rather than re-invented -
`scrub_event` and `select_event` are attrs those components already declare
for exactly this.

### It is not a new region, and the arithmetic says so

The 2026-08-29 shell amendment's 1A names three columns plus one full-width
drawer row, and 7A tabulates that arrangement at four container widths. This
pane adds to none of it. `.sb-editor__main` - the element that occupies the
`canvas` grid area, and has since the shell graduation - is a flex column, and
the pane goes inside it rather than beside it. With a run seated that column
holds the canvas toolbar and the pane, and the canvas panel is inside the pane;
with no run there is no pane element at all and the column holds the toolbar and
the canvas panel, as it always has. Either way the element in the `canvas` grid
area is the same one. `grid-template-areas`, `grid-template-columns` and
`grid-template-rows` are byte-identical in the base rule and in all four of
7A's breakpoints; no `grid-area` was added or moved.

The pane also carries the pane header shape the other three carry, which is
the toolbar's own argument in its moduledoc applied once more: a region that
does not name itself is a region a reader has to identify by its contents.

### Why the event log is not in the drawer

1A's test for the drawer is two words, **tabular** and **document-level**, and
the sentence that makes it a rule is "content that is a grid of rows about the
whole document goes to the drawer; content that is about one block does not,
whatever its shape". An event log is a grid of rows, so the first half fits.
The second half is where it stops, and the reason is worth writing down
because it is the case 1A did not have in front of it.

A run's event log is not about the document. It is about **one run over** the
document, which is a third subject 1A names neither side of: the drawer's
content is derived from the document and is true of it whoever is looking,
while a log is true of one execution and is meaningless without the run it
came from. Putting it in the drawer would also separate it from the scrubber,
and those two are one control - the log's entries and the scrubber's four
buttons move the same selection, and an author moving between them across two
regions of the shell is being asked to hold a relationship the layout has
hidden. So the pane keeps the three run surfaces together, around the thing
they are describing.

This claims nothing about future drawer tabs. 1A's test governs those
unchanged and unweakened, and the drawer's own six tabs are untouched: the
run adds no tab, and the one drawer surface it does reach is described below.

### What it does change, named rather than left to be found

- **The Datamodel tab's "what is known here" table grows a column while a run
  is seated.** `ADR-0011` decision 9's two surfaces - the surfaces that record
  names, and the ones this record already cites in that qualified form above -
  are unchanged in what they are for, and this one is still read-only, still
  produces no finding, and still tints nothing: the added cell says what the run
  was holding at that path at the point the scrubber is on, beside the type the
  position declares. A declared
  type and a held value side by side is how a read that should not have worked
  becomes visible without this package ruling on it. With no run the column is
  absent rather than empty, because an empty cell would be a claim that
  nothing was held where the truth is that nobody asked.

- **The marks are the run's while a run is seated.** The host's
  `active_marks` and `invoke_mark` still exist and still behave as they did;
  they simply do not contribute while a run is there, because merging two
  answers to "where is this run" would draw a configuration no point in the
  run was ever at.

- **A different document puts the run away**, beside the marks and for a
  reason the 2026-08-30 amendment's pane-fold exemption does not reach: a run
  resolves through the provenance map of the document it is over, so over
  another document it would name blocks that do not exist.

- **Markup carrying statifier-ui's own class names now reaches the page**, in
  the `statifier-ui-*` namespace, while a run is seated. Decision 14's rule is
  that this package emits no unprefixed class of its own and depends on no
  framework's, and that is unchanged - these classes are another package's,
  drawn by that package's components, in its own documented namespace. This
  package's stylesheet reaches them only under `.sb-run`, and only far enough
  to seat them in a pane: spacing, the type scale, the subtle-text colour, and
  the four scrubber controls drawn as buttons rather than as whatever the
  browser draws by default. That last one is a chrome treatment rather than
  layout, and it is named here so the restraint is not overstated - what the
  package does not do is theme that markup in depth, which would be claiming a
  surface it does not own.

- **No new hook.** Decision 7's two hooks are untouched. The scrubber's four
  buttons and the log's entries are server round trips, which is the same
  discipline the drawer resize takes.

Filed with `sb-xbyt`, campaign 033's editor-as-debugger lane, alongside
`sb-grc1`, which built the marks resolution this pane hangs on.

## Note (2026-09-06): the `11p`-`11u` amendment's Status casing, and where `11r`'s "decision 10's normalizer discipline" resolves

A dated Note rather than an amendment. It corrects two pieces of the
2026-09-05 `11p`-`11u` amendment's apparatus - one typographic, one a cite
target - and it changes nothing that amendment decides. No line above this one
is edited, and both clauses read exactly as they did.

### The Status line writes `lane` where this record writes `Lane`

The amendment's Status line (`:6293`) opens **"Status: proposed (2026-09-05,
campaign 031 lane H, bead `sb-w2m1`)"**, and its closing attribution (`:6601`)
reads "Filed with `sb-w2m1`, campaign-031's lane H." Everywhere else this
record names a lane by its letter it capitalises the word: `Lane G` (`:4897`,
`:5109`, `:5222`, `:5339`, and the attributions at `:5105`, `:5214`, `:5335`,
`:5470`), `Lane A` (`:5474`, `:5604`), `Lane S0` (`:5610`, `:5836`, `:5832`,
`:5982`, `:6132`), `Lane A2` (`:4406`), `Lane A3` (`:4475`), `Lane E`
(`:4662`), `Lane B2` (`:4893`). The 2026-09-05 amendment is the only section
that lowercases a lettered lane, and it does so in both of the places it names
one.

The lowercase `lane` elsewhere in this record is a different construction and
is not at issue: in `campaign-030's fill lane D` (`:6289`) and in
`campaign 033's second-pass code lane` (`:6814`) the word is a common noun
inside a descriptive phrase rather than half of a lane's name.

The deviation is typographic and nothing turns on it: both lines name campaign
031's lane H, which is the lane `sb-w2m1` was worked in, and they name it
unambiguously either way. It is corrected here rather than in place because a
change of case is a change to a word, which puts it outside the formatting-only
exemption this record's edits run under; correcting `:6293` and `:6601`
directly would remove two lines from a merged amendment, and amendments here
are additive. **Read `:6293` and `:6601` as `Lane H`.**

### `11r`'s "decision 10's normalizer discipline" names the `slot_outcome_key` amendment

Clause `11r` says that a host `validate_document/1` return which is not a list,
and a member of it which is neither of the two accepted shapes, is read as no
finding - "**decision 10's normalizer discipline**, applied to a host's return
value" (`:6421`). The phrase is exact about the discipline and loose about
where it is written down.

Decision 10 as originally taken (`:389-:405`) is a table of eight presentation
keys and their defaults. It says every default is specified so a type omitting
`palette_entry/0` still renders, and it says nothing at all about normalizing a
declaration: the word does not appear in the decision, and no reader following
the cite to `:389` finds the discipline `11r` is invoking.

The discipline reaches decision 10 through the **2026-08-29 amendment,
`slot_outcome_key`** (`:1490`), whose table row is `:1521` and whose statement
of it is the paragraph at `:1527-:1531`: the declaration "is read through a
total normalizer under ADR-0002 amendment B3: a non-map declaration, a
non-string key, and a key or value outside the outcome-name alphabet all read
as no declared outcome, which is the uniform rendering every consumer had
before the declaration existed." Clause `10o` (`:2489`) then says in as many
words that the normalizer semantics "stay ADR-0002 B3's, unchanged", and
`ADR-0002` amendment `B3` (`docs/adr/0002-block-type-behaviour.md:831`) is
where the semantics themselves are owned - refuse, do not truncate; a throw
degrades.

So the chain is `11r` -> the `slot_outcome_key` amendment -> `ADR-0002` B3, and
"decision 10's" is a fair name for the middle link because that is the decision
the amendment amends. **A reader following `11r`'s cite goes to `:1490` and its
`:1527-:1531` paragraph, not to `:389`.**

Nothing `11r` claims depends on which of the three is read. All three say the
same thing about a total reader - a shape it does not recognise is absent, not
an error - and `11r` applies it one level up, to a host's return value rather
than to a host's declaration. The clause stands as written.

Filed with `sb-wkg9`, campaign 034's docs fill.

## Note (2026-09-06): decision 9, the control for a `{:type_expr, opts}` field

A dated Note rather than an amendment. Decision 9's field-type table gains one
row by addition; no clause of decision 9 is edited, its "re-derived after every
config change" rule stands, the `:update_config` gate is untouched, and no line
above this one changes. Drafted as the record ahead of its code - `sb-1jcr`
builds the control - and it merges at proposed under the campaign invariant
like every other section filed with it.

The field type itself is not this record's. `ADR-0002` decision 7 as amended
for `{:type_expr, opts}` (campaign-SF035, `sb-zvar`, in flight) admits the
member and fixes what it stores, what `opts` carries, what config-time
validation reads, and which existing fields migrate to it. This section decides
the one thing the editor's table is keyed on: how the control is drawn.

### The row

| Field type | Rendering |
|---|---|
| `{:type_expr, opts}` | per `opts.arms`: a text input bound to a `<datalist>` of the document's declared type names, or an inline member-list form; a toggle when the field admits both |

### The name arm, and where its `<datalist>` comes from

**The name arm is the `invoke_type` control's shape, over a different feed.** A
single-line text input with a `<datalist>` beside it, free text still valid,
the plain input when the list is empty - the same "an empty list is markup that
suggests nothing" rule the 2026-09-01 Note above states for the path feed.

**The names are the datamodel document's declarations, not its index.** A
declared type name is the `name` of a `record` or a `shape` the document's
`types` key declares, and this package already computes exactly that list:
`StatifierBlocks.Datamodel.declared_types/1`
(`lib/statifier_blocks/datamodel.ex:635`), sorted by name, the reader the
Datamodel tab's declared-types half already draws (`lib/statifier_blocks/editor.ex:738`,
`lib/statifier_blocks/editor/drawer.ex:387`). The control reads that same list rather than deriving a
second one, for the reason the 2026-09-01 Note gives about paths: the set an
author is offered and the set validation judges must not be able to drift
apart.

**It is a different feed from `{:path, opts}`'s, and deliberately disjoint.**
`sd-ADR-0001` decision 7 says the `types` key contributes no path, so the
declared *paths* a `{:path, opts}` field suggests and the declared *type names*
this field suggests share no member and are never merged. Two feeds, two
controls, one field type each.

**It suggests and never constrains.** A name the author types that no
declaration carries is stored verbatim; this Note adds no refusal for it, and
whether such a name earns an advisory is decided where every other such
question is - `ADR-0002` decision 7 as amended, for the refusal, and clause
`11e` for the advisory. Nothing here adds a source, a severity, or an anchor.

### The inline arm: a member-list form, and it renders in the Config tab

**The inline arm draws a form of its own: an ordered member list, each row
carrying the member's name, its type, and whether it is required.** Adding and
removing a row is the affordance `{:list, t}`'s rows already have
(`lib/statifier_blocks/editor/field.ex:699`), and a member's *type* control is
this same row recursing - the name arm's `<datalist>`, or one of the scalars
the datamodel's closed set admits - so a member may itself hold an inline
shape and the form nests as a `{:list, t}` of a `{:list, t}` nests.

**The member spelling is `sd-ADR-0001`'s, and this record does not re-spell
it.** Its 2026-09-06 inline-shape amendment - merged in `statifier_datamodel` at
proposed on ruling `RQ-SF035-1`, and taking effect when `sd-izx` lands its code
and the status flips - gives the arm, gives a member its three keys, and settles
two things this control must not re-decide: a member's type is never absent -
a spelling that resolves to nothing is the datamodel's unknown - and **member
order is authoring order while identity is member-set-wise**. So the form
preserves the order the author writes, because that is the order an unmet-member
reason is rendered in, and it must not present reordering as though it changed
the value. What the editor stores is what that amendment defines; where it is
written down is there and only there.

**And the arm this control writes is not a datamodel document's.** That
amendment's clause (c) says an inline shape is built by a *consumer* and has no
document syntax in `statifier_datamodel`; nothing here reopens that. What this
control edits is a field inside one block's `config`, in a block document, which
`ADR-0001` owns and which has carried consumer-built values since it existed.
How that field's bytes are stored and parsed back is `ADR-0002` decision 7 as
amended (`sb-zvar`), not this section: the control edits a value, and the
spelling of the value on disk is decided where the field type is.

**One correction to where it renders.** `sb-j2vp` was filed saying the inline
editor renders "inside the drawer (`drawer.ex`)". It does not, and ruling 3A is
why: the inspector is about the selected block and the drawer is about the
document, which is the whole reason the Datamodel is a drawer tab here and was
an inspector tab in the spike. A config field is about the selected block, so
every control in decision 9's table renders in the **inspector's Config tab**,
through `StatifierBlocks.Editor.ConfigForm` and `Editor.Field`
(`lib/statifier_blocks/editor/inspector.ex:464`,
`lib/statifier_blocks/editor/config_form.ex:171`). The inline arm is a nested form inside that
field's control and nowhere else. Nothing in 1A's tabular test admits it to the
drawer, and no drawer tab is added by this Note.

### The toggle, when a field admits both arms

**Which arm shows is `opts.arms`, and a field declaring one arm shows no
toggle.** A field admitting both draws a two-way toggle above the control,
labelled by the arms themselves, and the arm it opens on is the one the stored
value already is.

**Switching arms replaces the value; it never translates it.** A name and a
member list are not two spellings of one value - `sd-ADR-0001`'s own step 2
compares a declared name nominally and an inline shape member-set-wise - so
there is nothing to carry across, and a control that guessed a translation
would be authoring a shape the author did not write. The new arm opens empty,
and the edit reaches the document through `:update_config` exactly as every
other field edit does. No new command, no new hook, no new host assign.

### A value the control cannot read renders raw

**A stored value that is neither arm renders in the name arm's text input,
showing the bytes exactly as stored, and the field carries its `:config`
finding beneath it.** Raw rather than blank, for decision 9's own reason that
an invalid form never reaches the document: a control that showed nothing would
invite the author to save over a value they never saw, which turns an author's
typo into an editor's deletion.

The finding is **not new here**. It is the one `{:type_expr, opts}`'s
config-time validation already produces (`ADR-0002` decision 7 as amended,
`sb-zvar`), anchored `{:config, block_id, key}` and routed beneath its field by
decision 11's existing rule (`lib/statifier_blocks/finding.ex:39-41`). This
Note adds no finding, no source, and no severity; it says only what the control
draws while one is outstanding.

### Worked example, signup

A `core.on_event` handling `myapp:signup` declares its `payload`. The host's
datamodel declares a `record` named `signup.registration`, so the author types
`s` and takes it from the list; the field is stored as that name, and a
`core.assign` reading `signup.registration.email` is checked against it.

A second handler carries a one-off the host does not want in its `types` key.
Its `payload` field admits both arms, so the author toggles to the inline arm
and writes two members - `email`, string, required; `variant`, string, not
required - and the same check runs against the shape they just wrote, with no
name minted in the host's document.

### What this Note does not do

- **It adds no field type.** The member is `ADR-0002` decision 7's, admitted
  there; this is its row.
- **It adds no JavaScript.** Decision 7's two-hook limit is untouched and still
  mechanically enforced by `test/statifier_blocks/assets_test.exs`.
- **It does not make the table exhaustive again, and one row is still owed.**
  Decision 9 calls its table "exhaustive by construction", and the 2026-09-06
  Note above records that `ADR-0002`'s set reached eight members with
  `{:path, opts}`. That member has shipped its control and its row in
  `Editor.Field`'s own table (`lib/statifier_blocks/editor/field.ex:19`), and
  the 2026-09-01 Note above describes its feed - but decision 9's table has
  never carried its row. With this section the table holds eight rows of a set
  of nine. Repairing that is `{:path, opts}`'s own record debt and is not taken
  here, because writing another member's row into this section would put a
  second proposal inside this one.
- **It moves no cite and edits no clause.** Every line number above is a census
  taken on `f3e737f`, in the sense the 2026-09-06 census Note fixes: dated to
  this section, re-counted by a later reader rather than trusted.

Filed with `sb-j2vp`, campaign-SF035's Lane A.

## Note (2026-09-06): two pieces of the Status-casing Note's apparatus - `:6145`'s lowercase `lane`, and the `Lane S0` cite list's order

A dated Note rather than an amendment. It concerns the 2026-09-06 Note on the
`11p`-`11u` amendment's Status casing (`:6935`) and nothing else: no decision
of this record moves, no clause is edited, and no line above this one changes.
Both items were raised as non-qualifying tidy notes in the review of the
request that added that Note and routed to a follow-up rather than cured in
place, so that merged section stayed the artifact its review read. Every line
number below is a census taken on `70a3193`, in the sense the 2026-09-06 census
Note above fixes: dated to this section, re-counted by a later reader rather
than trusted.

### 1. `:6145` is a third member of the not-at-issue list

That Note's carve-out paragraph (`:6955-:6958`) says the lowercase `lane`
elsewhere in this record is a different construction, and lists two places
where it is: `campaign-030's fill lane D` (`:6289`) and `campaign 033's
second-pass code lane` (`:6814`).

There is a third, and the list omits it. `:6145` reads "Recorded under campaign
030's fill lane D; it merges at proposed under" - the opening paragraph of the
2026-09-05 corrections Note (`:6134`), naming the lane that Note was recorded
under. It is `:6289`'s construction in the part that carries the point:
`campaign 030's fill lane D` against `:6289`'s `campaign-030's fill lane D`,
the same descriptive phrase with the campaign's number attached the other way.
The word is a common noun there, not half of a lettered lane's name.
**Read `:6145` as a third member of that paragraph's list, beside `:6289` and
`:6814`.**

Nothing the paragraph claims changes by gaining it. The 2026-09-05 `11p`-`11u`
amendment is still the only section of this record that lowercases a *lettered*
lane, it still does so in both of the two places it names one, and `:6293` and
`:6601` are still read as `Lane H`.

Recording the addition here rather than at `:6957` is the reason that Note
gives for not correcting `:6293` in place: adding a cite to a merged sentence
adds words, which puts it outside the formatting-only exemption this record's
edits run under, and amendments here are additive.

### 2. The `Lane S0` cite list is transposed, and it stays as it stands

Same Note, the enumeration of capitalised lettered lanes (`:6947-:6953`), where
the `Lane S0` group reads `` `:5610`, `:5836`, `:5832`, `:5982`, `:6132` ``.
The other groups are written in ascending line order - Lane G's in the two
ascending runs that sentence itself splits it into, the four it lists first and
then the four it calls attributions; this one is not, because `:5836` and
`:5832` are transposed.

All five cites resolve, and to what the sentence claims of them:

| Cite | What is there |
|---|---|
| `:5610` | "Status: proposed (2026-09-05, campaign 030 Lane S0, bead `sb-8vkc`)." |
| `:5832` | "Filed with `sb-8vkc`, campaign-030's Lane S0." |
| `:5836` | "Status: proposed (2026-09-05, campaign 030 Lane S0, bead `sb-8vkc`)." |
| `:5982` | "Filed with `sb-8vkc`, campaign-030's Lane S0." |
| `:6132` | "Filed with `sb-8vkc`, campaign-030's Lane S0." |

**Read the group as `:5610`, `:5832`, `:5836`, `:5982`, `:6132`.** That is the
whole of the correction, and it is recorded rather than applied for two
reasons.

The first is that it cannot be applied under the exemption. Swapping two cites
reorders words, and the formatting-only exemption a merged record's in-place
edit runs under admits whitespace, wrapping, list indentation and separator
style only - no word added, removed, or reordered. Applying it would be an
amendment removing a line from a merged Note, and amendments here are additive.

The second is that nothing turns on the order. The group is a set of places
where this record capitalises `Lane S0`, offered as evidence for a claim about
casing; it is not a sequence, no member's meaning depends on which member
precedes it, and the claim it supports - that the 2026-09-05 amendment is the
only section that lowercases a lettered lane - is unaffected by the order the
five are written in. So the transposition is errata, corrected by this
sentence, and it does not earn a section of its own anywhere else.

### What this Note does not do

- **It edits nothing.** No line above this one is changed, and both clauses of
  the Status-casing Note read exactly as they did.
- **It adds no decision.** Neither item touches a decision, a clause, or a
  control; both are about where a cite points and how a word is set.
- **It does not re-open the casing question.** `:6293` and `:6601` are still
  corrected by reading, not in place, for the reason the 2026-09-06 Note gives.

Filed with `sb-x88o`, campaign-SF035's Lane A.

## Note (2026-09-07): decision 9's `{:type_expr, opts}` Note carries no `Status:` line, and its two forward references now read

`sb-wzoa` is the request that flips the Theme 1 records of campaign SF035, and
it reached this record expecting a status word to move. There is none to move.
The Note of 2026-09-06 on decision 9 (`:7006`), filed with `sb-j2vp`, carries no
`Status:` line, which is this family's convention for a Note - `ADR-0002`'s Note
at its own `:4948-4950` states it in as many words, and `sb-upv0` reached the
same conclusion about `ADR-0002` decision 5's callback Note. **Nothing in this
record is flipped and nothing above this line is edited.** This Note is by
addition, sits at the foot so no line a sibling record cites moves, and carries
no `Status:` line of its own either.

It records the two sentences of that Note a reader would otherwise read as
current. Every cite below is a census taken on `main` at `f750b3b`, dated to
this Note and to be re-counted rather than trusted.

**1. "It merges at proposed under the campaign invariant."** That is the
section's own account of how it landed and it is accurate as written; it says
nothing about a status word, because the section has none. What a reader wants
from it - whether the decision it records is settled - is answered by this
record's head `Status:` line at `:3`, which reads `accepted`, exactly as it is
for every other Note in this file.

**2. "`ADR-0002` decision 7 as amended for `{:type_expr, opts}`
(campaign-SF035, `sb-zvar`, in flight)."** It is no longer in flight. That
amendment merged as `sb-zvar` (PR 349, `e1d4c52`) and is **accepted** from this
date, flipped by this same request; the Note at the foot of
`docs/adr/0002-block-type-behaviour.md` records what the flip checked. So the
field type this section draws a control for is settled, and the division of
labour the section states - the field type there, the control here - stands
unchanged.

**What is not settled, and is not this record's.** `ADR-0011`'s amendment of
2026-09-06 on decisions 1 and 2 is **not** accepted: `sb-wzoa` left it at
`proposed` over an open question about which datamodel paths the environment
seeds, recorded in the Note at the foot of `docs/adr/0011-typed-environment.md`
and adjacent to the campaign's records bead `sb-m9eq`, which asks where along
the walk a seeded type enters. Nothing in decision 9's Note depends on it. That
Note reads the *declared type names* the document's `types` key declares,
through `StatifierBlocks.Datamodel.declared_types/1`
(`lib/statifier_blocks/datamodel.ex:635`), and says in terms that this feed and
`{:path, opts}`'s are disjoint and are never merged. The seeding question is
about the path feed's side of that line, so it reaches no clause here.

**What this Note does not do.** It adds no decision, no clause, no control and
no row; it edits nothing; and it does not make decision 9's table exhaustive -
the `{:path, opts}` row that Note says is still owed is still owed.

Filed with `sb-wzoa`, campaign SF035's Lane A.

## Amendment (2026-09-07): a `profile` assign names which surfaces a mount renders, and one of them is read-only

**Status: accepted (2026-09-07, campaign SF036, bead `sb-qhzl`, on rulings
`RQ-SF036-1` and `RQ-SF036-2`).** A decision record merges at proposed under
campaign SF036's invariant; flipping it to accepted is a separate gated request
(`sb-xnxw`, after the implementing bead). Additive: 1B, decision 15 and every
clause above this line stand exactly as written, and no text above this line is
edited by this section. Nothing here is built yet - `sb-2bmk` is the request
that builds it.

Every code cite below is a reading of `main` at `b71740c`, dated to this
section and to be re-read rather than trusted.

### The gap

Two clauses of this record are read as if they answered this question, and
neither does.

**1B**, which this record states twice. At `:3356-3359`:

> Not persisted, in either direction: the host is told nothing, no assign
> survives a remount, and there is no attr for a host to open an editor
> pre-folded. A fold is a thing an author did a moment ago, not a document
> property.

and again at `:3540-3544`:

> It is deliberately the same mechanism and not a generalisation of it. One
> boolean of shell state [...] no hook, no client state, no persistence, and no
> attr for a host to open the editor with a pane pre-folded.

**Decision 15**, at `:629-631`:

> - **Host concerns**, restated once so they are unambiguous: which palette
>   entries a tenant may use, who may edit or publish a document, where it is
>   stored, and what publishing means are all outside this package.

1B is about a *fold*: a pane an author collapsed a moment ago, which the host
never hears about and cannot pre-set. Decision 15 is about *authority over
content and lifecycle*: which entries a tenant may use, who may edit, where a
document lives. Neither is about which **surfaces** a mount draws at all.

The embedder that finds the gap is the one mounting this editor for two
audiences out of one codebase: its own engineers, who want the whole editor,
and operations staff who should see a canvas, the Findings and Fixtures tabs
and nothing else - or a rendering they cannot type into. Today that host's only
lever is a fork of the component, because 8A's split (`:3513-3515`) gives it the
`:header` slot and nothing else, and every pane below the header is
unconditional in `render/1` (`lib/statifier_blocks/editor.ex:752`; the
`sb-editor__layout` div at `:817`, its `PaletteBrowser.palette_browser` child
at `:821` and its `Toolbar.toolbar` at `:835`).

### The decision

**A `profile` assign names which of this editor's surfaces a mount renders, and
whether that mount edits.** It is one optional assign on the editor component,
a plain map, and its default is everything:

```elixir
@type toolbar_chip :: :history | :zoom | :fits | :metrics

@type profile :: %{
        optional(:drawer_tabs) => [Shell.tab_id()] | :all,
        optional(:inspector_tabs) => [Shell.inspector_tab()] | :all,
        optional(:palette_groups) => [String.t()] | :all,
        optional(:toolbar) => [toolbar_chip()] | :all,
        optional(:read_only?) => boolean()
      }
```

with the default

```elixir
%{
  drawer_tabs: :all,
  inspector_tabs: :all,
  palette_groups: :all,
  toolbar: :all,
  read_only?: false
}
```

**A host that passes no `profile` gets the 0.23.0 editor, exactly.** That is the
constraint the shape is built around, and it is why every key is optional and
why `:all` is a member of every list type rather than a separate flag: a key a
host does not mention resolves to the default, and the default is what the
editor already draws. There is no arrangement of this map, including `%{}`, that
removes a surface a host did not name.

**There are no named profiles.** No `:operations`, no `:reviewer`, no
`:minimal`, no preset of any kind, in this package or in a host's reach through
it. A preset is a claim about which audiences exist, and which audiences exist
is the host's to know - the same reasoning decision 15 already applies to which
palette entries a tenant may use. A host that wants a name for a profile writes
the map into a module attribute of its own and names it there. This is a
positive decision, not an omission: a later request that adds a preset is
amending this section.

**A profile is not persisted and it is not a document property.** It is what the
host says about the mount, supplied on every render like `palette` or
`datamodel`, and it survives a remount only because the host passes it again.

### The ids a profile may list

Each list names ids the package already has. This section adds no id and renames
none.

| Key | The ids it draws from | Source |
|---|---|---|
| `inspector_tabs` | `:config`, `:findings`, `:condition`, `:fixtures` | `Shell.inspector_tabs/0` (`lib/statifier_blocks/shell.ex:477`) over `@inspector_tabs` (`:166`) |
| `drawer_tabs` | `:tables`, `:findings`, `:declarations`, `:fixtures`, `:datamodel`, `:source`, **and** the string ids of the host's own drawer tabs | `Shell.drawer_tabs/0` (`:501`) over `@drawer_tabs` (`:191`); host ids are the `id` of each entry in the `drawer_tabs` assign, after `Shell.host_tabs/1` (`:551-557`) has had them |
| `palette_groups` | the `group` name of each palette entry, as strings | the `palette_groups` field of `StatifierBlocks.ViewModel` (`lib/statifier_blocks/view_model.ex:403`), built by grouping the palette on `entry.group` (`:1763-1764`, private); the name is whatever a block type's `palette_entry/0` returned, defaulted to `"Other"` by decision 10's defaults (`lib/statifier_blocks/editor/palette_browser.ex:18`). Core's own types all declare `"Structure"` |
| `toolbar` | `:history`, `:zoom`, `:fits`, `:metrics` | the four addressable groups of `Editor.Toolbar.toolbar/1` (`lib/statifier_blocks/editor/toolbar.ex:81`): Undo/Redo (`:87-106`), the segmented zoom control (`:108-130`), `Fit width` / `Fit active` (`:132-154`), and the two read chips (`:156-159`) |

Three of these need a word.

**`palette_groups` is an open set of strings, and that is not a defect.** A group
name is a block type's own word, not a member of a closed list this package
keeps, so a profile that names `"Structure"` is naming a string that a host's
palette may or may not contain. That is the same footing the `allowed` set the
palette already filters on stands on, and it is why the unknown-id rule below
matters more here than anywhere else.

**`toolbar`'s members are called chips in ruling `RQ-SF036-1`'s spelling, and
the code uses that word more narrowly.** In `Editor.Toolbar` a chip is
specifically a read-only fact drawn as `sb-toolbar__chip` - `nested tree`,
`depth`, `blocks`. `toolbar_chip()` above is the profile's word for **a toolbar
item a profile may list**, which is wider: two of the four are groups of
buttons. The type is named for the ruled shape and defined here so no reader
has to guess which of the two senses a list member is in.

**The `Canvas` heading and the `nested tree` chip are not addressable.** They are
what makes the canvas read as a pane beside the other two - the toolbar's own
moduledoc says so at `:38-46` ("without a name a row of unlabelled buttons is
the only pane in the editor that has to be recognised by its contents") - so a
profile that could remove them could produce an editor whose middle pane has no
name. `:metrics` covers the two right-aligned read chips and nothing else.

### An id the shell does not know is dropped, never an error

**A list member the package cannot resolve is dropped, and the mount renders.**
Not an argument error, not a finding, not a refusal: the surface the id would
have named is simply not there, and every id in the list that did resolve is.

This is a **new rule**, stated here on this record's own authority. It is worth
saying plainly because the nearest existing rule is not it: `Shell.host_tabs/1`
(`:551-557`, doc `:533-549`) drops a host tab whose id collides with one of the
package's own reserved names, and drops a repeated id, and its doc says in as
many words that "Nothing else is filtered" (`:543`) - an unknown host tab id is
exactly what it passes through. That clause is about strip readability. This one
is about a host list outliving the thing it names.

The precedent it does follow is `Shell.drawer_tab/2` (`:518-530`) and
`Shell.inspector_tab/1` (`:486-492`): a tab name the package does not know
resolves to a default and never raises. The reasoning there is that the name
arrives from outside and a crafted one must not be a crash; the reasoning here
is adjacent and stronger. A profile is written once, in a host's code, against
the package's tab set at the version it was written for. If an unknown id
raised, then removing a tab from this package - or a host removing one of its
own drawer tabs - would turn every mount whose profile still names it into a
crash at render, in an audience-scoping map whose entire purpose is to be
conservative. Dropping makes the failure mode "a surface is missing", which is
visible and recoverable; raising makes it "the editor is gone", which is
neither.

A profile list is therefore never validated against the shell's ids at
declaration, and there is no `validate_profile/1`.

### `read_only?`

**`read_only?: true` renders the document without offering any way to change
it.** Six clauses, and they are a set rather than a suggestion:

1. **No palette column.** The `PaletteBrowser.palette_browser` call in the layout
   (`editor.ex:821`, the layout div's first child) does not render. Not a
   collapsed palette - a mount with no palette at all. `palette_groups` still
   parses and is simply moot for that mount.
2. **No drag hook.** The canvas does not mount `phx-hook="StatifierBlocksDrag"`
   (`lib/statifier_blocks/editor/canvas.ex:132`). The measure hook
   (`editor/connector_layer.ex:48`) is unaffected: it is decision 7's read-only
   measurement and reads nothing the author can change.
3. **Config forms render as values.** The inspector's Config tab draws each
   field's label and its current value, not a control. It is a rendering of
   `ViewModel.Field`, not a disabled form: a disabled `<input>` is a control that
   refuses, and what is wanted here is a reading. This values-only rendering is a
   surface in its own right, and a host-native read-only view over `ViewModel`
   in the reference embedder is its second reader.
4. **Selection and findings stay.** Selecting a block still works, `on_select`
   still fires, the inspector still follows the selection, and every findings
   surface - the inspector's tab, the drawer's, the per-card counts - draws
   exactly what it draws in an editing mount. Reading a document is the whole
   point of the mount; findings are the most-read thing on it.
5. **Undo and Redo are hidden.** Not disabled: hidden. `:history` is drawn as if
   the profile had not listed it, whatever the profile's `toolbar` list says.
   A history control over a document that cannot change has nothing to offer,
   and a permanently-disabled pair of buttons is a worse answer than their
   absence. Zoom, the fits and the metrics are untouched - all four are ways of
   reading.
6. **`on_change` never fires.** No edit reaches the document, so there is no new
   document to hand back, so the callback is never called with one. A host may
   pass `on_change` alongside `read_only?: true` without that being a
   contradiction to resolve; it simply never runs.

And one clause about what read-only is *not*:

**A document is never refused for being read-only.** Every document that renders
in an editing mount renders in a read-only one. There is no shape of document,
no finding, and no missing assign that makes a read-only mount decline to draw.
`read_only?` narrows what a mount *offers*, never what it *accepts*.

**This is not the read-only viewer surface `:3515-3520` names.** That paragraph
declines a *small* chart rendering - "an editing surface that also renders well
at 200 pixels is two components wearing one name" - and answers it with "a
separate read-only viewer surface", noted as unbuilt. A read-only mount of this
editor is the same component at the same size drawing the same canvas, with the
editing affordances withheld; it makes no claim about thumbnails and does not
build, schedule or promise the surface that paragraph names, which is still
unbuilt. The other twenty-odd uses of "read-only" in this record are about a
read-only *pane* or *view* - decision 12's read-only config inspector surface at
`:3177`, the declared-path view at `:4628-4713`, the measurement hook - and none
of them is about a mount.

### The Note this leaves under 1B

1B stands, in both places it is stated, for the thing it is about.

**A fold is the author's gesture; a profile is the host's statement of
audience.** A fold is one boolean of shell state that an author toggled a moment
ago and that the host is deliberately never told about, which is why 1B refuses
an attr for it: an attr would make a transient gesture into something a host
sets and therefore into something the author is arguing with. A profile is the
opposite direction of travel. It is a standing fact about *who this mount is
for*, supplied by the host on every render, and it removes a pane rather than
collapsing one - a folded palette has a handle that reopens it, a profiled-away
palette is not there.

So the second is not a generalisation of the first, and this section is not the
"attr to open the editor with a pane pre-folded" that both `:3356-3359` and
`:3540-3544` refuse. Both sentences stand for folds, unamended: after this
section there is still no attr that pre-folds a pane, and a mount whose profile
draws the palette still opens with it expanded, for the author to fold or not.

### The sentence decision 15 gains

Decision 15's host-concerns list at `:629-631` is a list of things this package
does not decide. This section adds one sentence to how it is read, without
editing it:

> **Which surfaces a mount shows is also the host's to say, and this record now
> gives it the lever.** Decision 15's list names authority over content and
> lifecycle - which entries a tenant may use, who may edit, where a document is
> stored. Audience scoping sits beside them and always did; the difference is
> that this record answers it rather than leaving it outside the package,
> because the answer is a shape of assign and not a policy.

### Where this lands

- **The assigns table** (`lib/statifier_blocks/editor.ex:469-497`, the table
  under `## Assigns` at `:467`) gains a `profile` row. It does not gain it
  in this request: `sb-2bmk` adds the row when it adds the assign.
- **`docs/profiles.md`** - the host-facing page a profile needs, with the two
  worked mounts below written out against the real tab ids - is new in
  `sb-2bmk`. It does not exist yet.
- **`sb-2bmk`** is the implementing request. **`sb-xnxw`** flips this section
  from proposed to accepted afterwards.

### Worked example

A card-processing host mounts the same editor twice.

**An operations mount.** Its operations staff investigate settlement documents:
they need the canvas, the findings, and the fixture runs, and they have no
business inserting blocks.

```elixir
<.live_component
  module={StatifierBlocks.Editor}
  id="ops-editor"
  document={@document}
  palette={@palette}
  fixtures={@fixtures}
  profile={%{
    drawer_tabs: [:findings, :fixtures],
    inspector_tabs: [:findings, :fixtures],
    palette_groups: [],
    toolbar: [:zoom, :fits, :metrics]
  }}
/>
```

The drawer's strip carries two tabs; the inspector's carries two; the palette
column renders with no groups in it; the toolbar keeps zoom, the fits and the
metrics and drops Undo/Redo. `read_only?` is absent, so it is `false` and this
mount still edits - which is the point of showing it: **scoping the surfaces and
withholding editing are two separate settings**, and a host may want either
without the other.

**A read-only review mount.** The same document, opened by a reviewer who signs
off on it:

```elixir
<.live_component
  module={StatifierBlocks.Editor}
  id="review-editor"
  document={@document}
  palette={@palette}
  fixtures={@fixtures}
  on_select={&JS.push("reviewing", value: &1)}
  profile={%{
    drawer_tabs: [:findings, :fixtures, :source],
    read_only?: true
  }}
/>
```

`inspector_tabs`, `palette_groups` and `toolbar` are unmentioned, so all three
are `:all` - and then `read_only?` withholds the palette column and hides
Undo/Redo regardless. The reviewer selects blocks, reads their config as values,
reads findings and fixture runs and the compiled source, and cannot change a
character. `on_select` fires on every selection; `on_change` never fires.

### What this section does not decide

- **It names no profile.** See the decision: presets are refused, not deferred.
- **It says nothing about who a mount is for.** A host decides which profile a
  given viewer gets, out of its own authorization, exactly as decision 15 leaves
  it.
- **It adds no id, tab, group or toolbar item.** Every id a profile may list is
  one the package already draws.
- **It does not make `read_only?` an authorization boundary.** A read-only mount
  withholds affordances; it is not a permission check, and a host that must
  prevent a write enforces that where it handles the write, not by trusting a
  rendering. This is decision 15's "who may edit" left exactly where decision 15
  put it.
- **It does not build the read-only viewer surface `:3515-3520` names**, which
  is still unbuilt and still not this component's.
- **It edits nothing.** 1B, decision 15, 8A and every clause above stand as
  written; this section is additive and sits at the foot of the record so no
  line a sibling record cites moves.

Filed with `sb-qhzl`, campaign SF036.

## Note (2026-09-07): decision 9's table gains the `{:path, opts}` row, and is exhaustive again at nine

A dated Note rather than an amendment. Decision 9's field-type table gains one
row **by addition**; no clause of decision 9 is edited, its "re-derived after
every config change" rule stands, the `:update_config` gate is untouched, and
no line above this one changes. It records a control that already shipped
rather than proposing one, which is the one way this section differs from the
2026-09-06 Note on `{:type_expr, opts}` (`:7006`) whose shape it otherwise
follows.

### The row

| Field type | Rendering |
|---|---|
| `{:path, opts}` | single-line text input bound to a `<datalist>` of the declared datamodel paths; the plain input when there are none |

That is the row `StatifierBlocks.Editor.Field`'s own moduledoc table already
carries, word for word (`lib/statifier_blocks/editor/field.ex:19`), and the
copy here is deliberately the same wording rather than a paraphrase: the
renderer's table and this record's table are one mapping stated twice, and two
spellings of one mapping is how a record and its code start to drift.

**Where the control is defined.** `StatifierBlocks.Editor.Field`'s `control/1`
has two clauses for the type: the datalist arm, matched when
`path_candidates` is non-empty (`lib/statifier_blocks/editor/field.ex:687-710`),
and the plain-input arm it falls to when there are none
(`lib/statifier_blocks/editor/field.ex:715-726`). The reasoning behind both -
that the list suggests and never constrains, that `validate_config/1` remains
the only gate, that an undeclared path stays clause `11e`'s `:info` advisory
anchored on the field's `key`, that `opts`' `expects` and `writes` are read by
`StatifierBlocks.Environment` and not by the control, and that a `{:path, opts}`
inside a `{:list, t}` renders as the row fallback input - is in that module's
"The `{:path, opts}` control" section
(`lib/statifier_blocks/editor/field.ex:294-322`). None of it is restated here;
this section decides the one thing decision 9's table is keyed on, which is how
the control is drawn.

The feed is the one the 2026-09-01 Note on this decision (`:4410`) describes:
`StatifierBlocks.Datamodel.candidates/3`, reading the same three declaring
surfaces `findings/4` reads, so the set an author is offered and the set that
decides whether they get an advisory cannot drift apart. That Note describes
the feed on an `:expression` field; this row is the same feed reached by a
field's **type** instead of by the source it is typing into. The two are the
same `<datalist>`, and neither is completion.

### The claim in decision 9's own sentence, restored

Decision 9 introduces the table as "the mapping, which is exhaustive by
construction". The claim has been false since 2026-09-05, and its arithmetic is
recorded above in three places, each of them true when it was written:

- The 2026-09-06 Note at `:6603` records `ADR-0002`'s closed field-type set
  reaching **eight** members with `{:path, opts}`, and corrects a stale "seven"
  in the 2026-09-05 duration amendment's consequences. It corrects the count in
  the consequences bullet; it does not touch the table.
- The 2026-09-06 Note at `:7006` adds the `{:type_expr, opts}` row and says so
  in as many words: "With this section the table holds eight rows of a set of
  nine", and names repairing that as `{:path, opts}`'s own record debt,
  deliberately not taken there.
- The 2026-09-07 Note at `:7253` restates the debt as still owed: it "does not
  make decision 9's table exhaustive - the `{:path, opts}` row that Note says is
  still owed is still owed".

With the row above, it is paid. The set `ADR-0002` decision 7 closes has nine
members, spelled in `StatifierBlocks.BlockType`'s `field_type/0`
(`lib/statifier_blocks/block_type.ex:152-161`) and enumerated in prose at
`lib/statifier_blocks/block_type.ex:300-302`: `:string`, `:integer`,
`:boolean`, `{:select, choices}`, `:expression`, `:duration`,
`{:list, field_type()}`, `{:path, opts}` and `{:type_expr, opts}`. Decision 9's
table carries seven of them in its own body; the 2026-09-06 Note carries the
eighth; this section carries the ninth. Nine of nine, and "exhaustive by
construction" reads true again - by construction because the set is closed
where `ADR-0002` decision 7 closes it, and `control/1` dispatches on it clause
by clause, ending in a fallback that renders a plain text input for anything
the set does not name (`lib/statifier_blocks/editor/field.ex:923-933`).

### The implementing bead

**None: the control shipped before the row did.** `{:path, opts}` and both of
its `control/1` clauses landed on `main` in `23d1455` ("Adds the `{:path, opts}`
field type", 2026-09-05), filed with `sb-2ym4`. This section adds no code, asks
for none, and changes no behaviour a mount has today; it is the record catching
up to a member the code has carried for two days. It is filed with `sb-mliu`,
campaign SF036, under ruling `RQ-SF036-0d`.

### What this Note does not do

- **It adds no field type.** The set is `ADR-0002` decision 7's, and it is
  unchanged at nine. Nothing here admits a member, retires one, or re-spells
  what one stores.
- **It adds no control, no source, no severity and no anchor.** The two
  `control/1` clauses are already on `main`; the advisory for an undeclared
  path is clause `11e`'s, unwidened.
- **It edits nothing above it.** Decision 9's table keeps its seven rows in
  place, the three Notes above keep their counts as written and dated, and no
  cite a sibling record takes on this file moves. The table is read as its body
  plus the two rows its Notes add - which is how a record grows here, and why
  the count sentences above stay where they are rather than being corrected in
  place.
- **It does not flip a status.** This section merges at proposed under campaign
  SF036's invariant, like every other section filed with it.

Filed with `sb-mliu`, campaign SF036.

## Note (2026-09-07): the formatting-only exemption this record's edits run under, stated here, and where `:7200`'s attribution of it is quoted from

A dated Note rather than an amendment, in the shape of the 2026-09-06 Note at
`:7166`: two pieces of apparatus that three sections above use, neither of them
a decision this record takes. No clause of this record moves, no line above this
one is edited, and every section named below reads exactly as it did. Every line
number in it is a census taken on `7775bd6`.

### 1. The exemption, stated inside this record

Three sections of this record invoke **the formatting-only exemption** by name:

| Cite | What it says of the exemption |
|---|---|
| `:6963-:6964` | "a change of case is a change to a word, which puts it outside the formatting-only exemption this record's edits run under" |
| `:7202-:7203` | "adds words, which puts it outside the formatting-only exemption this record's edits run under" |
| `:7229-:7231` | "the formatting-only exemption a merged record's in-place edit runs under admits whitespace, wrapping, list indentation and separator style only - no word added, removed, or reordered" |

The first two invoke the term and give one instance of what it excludes; only
the third states any of what it admits, and it does so in passing, inside an
argument about a transposed cite list, 266 lines after a reader first meets the
term. A reader arriving at `:6963` cannot resolve it from this record. It is
stated here in full, in this record's own words, so that they can:

**The formatting-only exemption.** An in-place edit to a merged section of this
record is permitted when the diff changes **whitespace, wrapping, list
indentation, or separator style only** - no word added, no word removed, no word
reordered. A bare separator line may be added or deleted, and the check is a
word-diff run over the **non-separator** lines: reflowing a paragraph to a
different column, re-indenting a list, or adding or removing a rule between two
sections all pass it, because the words on the non-separator lines are the same
words in the same order. **Any changed word makes the edit an amendment**, and
an amendment to this record is additive - a new dated section, zero lines
removed. That is the whole of the rule, and there is no fourth category between
the two: an edit either changes no word and may be applied in place, or it
changes a word and is recorded in a new section beneath.

This is not a decision of this record and it decides nothing about the editor.
It is the campaign convention this record has been edited under since
2026-09-05, stated here because the record invokes it three times and defines it
nowhere. It is stated, not narrowed and not widened: each of the three sections
above reads true against it as written, and each is an instance of the same
clause. `:6963`'s change of case changes a word; `:7202`'s added cite adds
words; `:7229`'s swap reorders two. All three are outside the exemption for the
one reason the rule gives, and all three were correctly recorded rather than
applied.

### 2. What `:7200-:7203` attributes to the Status-casing Note, quoted on both sides

`:7200-:7203` reads:

> Recording the addition here rather than at `:6957` is the reason that Note
> gives for not correcting `:6293` in place: adding a cite to a merged sentence
> adds words, which puts it outside the formatting-only exemption this record's
> edits run under, and amendments here are additive.

The reason the Status-casing Note actually gives, at `:6962-:6966`, is:

> It is corrected here rather than in place because a change of case is a change
> to a word, which puts it outside the formatting-only exemption this record's
> edits run under; correcting `:6293` and `:6601` directly would remove two
> lines from a merged amendment, and amendments here are additive.

The two are not the same sentence. That Note's ground is **a change of case**;
`:7200`'s is **an added cite**, which is a different act. What is shared is the
clause of the exemption both fall under - part 1's "no word added, no word
removed, no word reordered" - and the additive consequence, whose wording
`:7203` does carry over verbatim ("and amendments here are additive"). The
Status-casing Note also gives a second, independent ground that `:7200` does not
carry across at all: that correcting `:6293` and `:6601` directly **would remove
two lines from a merged amendment**.

So the generalisation is sound and the attribution is loose. **Read `:7200-:7201`
as naming the exemption clause that Note's reason falls under, not as quoting
that Note's reason:** the Status-casing Note gives change-of-case as its ground,
`:7200`'s ground is that adding a cite adds words, and both are the same clause
of the rule stated in part 1. Nothing either section concludes changes by the
distinction - `:6293` and `:6601` are still read as `Lane H`, and `:6145` is
still a third member of the not-at-issue list.

### The implementing bead

**None: this section is record-only.** It adds no code, asks for none, and
changes no behaviour a mount has today. It is filed with `sb-4m4x`, campaign
SF036, under ruling `RQ-SF036-0d`.

### What this Note does not do

- **It edits nothing above it.** `:6963`, `:7202` and `:7229` stand as written,
  and the three sections that carry them read exactly as their reviews read
  them. Part 2 records how one sentence is to be read; it does not rewrite it.
- **It does not change the exemption.** Part 1 states a convention that was
  already in force over every section of this record; no edit that was
  permitted before it is refused after, and none that was refused is now
  permitted.
- **It takes no decision and adds no clause.** Nothing here is a decision of
  this record, nothing is numbered, and no clause of any decision gains, loses
  or re-spells a member.
- **It does not flip a status.** This section merges at proposed under campaign
  SF036's invariant, like every other section filed with it.

Filed with `sb-4m4x`, campaign SF036.

## Amendment (2026-09-07): decision 10, `ViewModel.Node.sentence`, and `ViewModel.outline/1` - the one walk a list view, an outline pane and a test all consume

**Status: accepted (2026-09-07, campaign SF036, bead `sb-hlut`, on ruling
`RQ-SF036-5`).** A decision record merges at proposed under campaign SF036's
invariant; flipping this section's status line to accepted is a separate gated
request (`sb-xnxw`, after `sb-w37s` lands the code). Additive: decision 10 at
`:389-442`, its amendments `10n` and `10o` at `:2480-2497`, the `on_select`
descriptor table at `:5156-5164` and every clause above this line stand
exactly as written, and no text above this line is edited by this section.
Nothing here is built yet - `sb-w37s` is the request that builds it.

Every code cite below is a reading of `main` at `b08c99a`, dated to this
section and to be re-read rather than trusted.

### The gap

This record gives a consumer two ways to read a block and no third.

**Chips**, capped and refused rather than truncated (`10n` at `:2480`, `10o`
at `:2489`). The cap's own reason names what it excludes: 24 characters was
chosen "so that 'calls the host' and 'timer' fit **and a sentence does not**".

**The canvas**, which is a picture: `arrangement/1`, `body_slots/1`,
`rail?/1`, `tray?/1`, `flow_children/1` and `shelf_children/1`
(`lib/statifier_blocks/view_model.ex:798`, `:814`, `:700`, `:719`, `:741`,
`:748`) are the partition a two-dimensional renderer needs, and each answers
one question about one node or one slot. There is no function on this module
that hands a consumer the document **in reading order**.

A host that renders a document as a vertical list of lines therefore has two
holes to fill by hand: it has no per-block line to draw, and no walk to draw
it from. Both are filled here, and both are filled **once**, on the view
model, so the outline pane this package may grow, a host's own list view, and
a test asserting what a document says are reading the same list rather than
three re-derivations of it.

`ADR-0002`'s amendment of this date declares the block-type half - an optional
`sentence/1`, `config -> String.t()`, outside the 24-character arm of that
record's B3 refusal set. This section is the view-model half.

### `ViewModel.Node` gains `sentence`

`Node`'s struct at `view_model.ex:347-365` gains one key,
`sentence: nil`, typed `String.t() | nil` - a plain field beside `title`,
`summary`, `join_label` and `outcome`, resolved by `build/3` (`:446-447`) at
build time like every one of them, not a function called later.

**It resolves in three steps**, and the claim spans three states, so it
carries a table:

| The block | `Node.sentence` holds |
|---|---|
| its type declares `sentence/1`, and the reader accepts the return | that string |
| its type declares no usable `sentence/1`, and the author gave a `title` | the author's `title` |
| neither | the type's label, falling back to the type name |

"The reader" is `StatifierBlocks.BlockType.sentence/2`, whose four cases -
including a raise, a throw, an exit and a malformed return, each of which
answers the **type's label** and never the author's `title` - are `ADR-0002`'s
amendment of this date and are not restated here.

Rows two and three are the rule the `on_select` descriptor table already
states at `:5162` for `label`:

> what the block's card draws as its first line - the author's title where
> they gave one, the type's label otherwise

extended by exactly one line at the top: **the type's own sentence, where it
declares one.** `ViewModel.title/1` (`:546-547`) is that rule in code and is
**not changed**: `title/1` keeps both its clauses and every consumer of it
reads what it read before. `sentence` is a fourth thing a node carries, not a
re-spelling of the third.

**An unresolvable block** - one whose type the palette cannot resolve, built
by `build_unresolvable_node/*` (`:1398`) - has no callback to ask and no
label, so it lands on row three's fallback, the type name as the document
stores it. A list view therefore draws a line for every block in the document
and never a blank one.

**Chips are unchanged.** `10p`, `10q`, `10r` and `10w`, `summary_chips/1`
(`:637-638`), `summary_titles`, the cap at `10n` and the refusal discipline at
`10o` all keep every word they have. In particular `summary_chips/1`'s first
clause - a node with an author's `title` draws no chips - is untouched, and
`sentence` does not become a chip, is not capped, and appears in no chip list.
A card draws what it drew yesterday.

### `ViewModel.outline/1`

```elixir
@type kind :: :step | :arm | :rail | :tray

@spec outline(t()) :: [{Node.t(), non_neg_integer(), kind()}]
def outline(%__MODULE__{} = view_model)
```

Public on `StatifierBlocks.ViewModel`, **pure**, and a pure function of the
view model alone: it reads `root` and walks the `Node`/`Slot` tree that is
already there. It resolves nothing, calls no callback, consults no palette and
reads no findings - everything it needs `build/3` has already put in the
struct. Calling it twice on one view model returns two identical lists.

**Pre-order.** The document's reading order: a node, then everything under it,
then the next node. The first entry is always `{root, 0, :step}`.

**Every block appears exactly once.** The four kinds are a partition of how a
block is *reached*, not a filter on which blocks are listed: arms, rails and
trays are **kinds**, never omissions. A consumer that wants only the flow
filters the list it was given; the walk hides nothing, because a walk that
hides a failure rail is a walk a reviewer cannot trust to be the document.

**The four kinds, per variant:**

| `kind` | The slot the node's parent holds it in | What it says about the node | Depth |
|---|---|---|---|
| `:step` | the parent's body, where `arrangement/1` is `:stack` | the next thing that happens | parent's depth + 1 |
| `:arm` | one of the parent's body slots, where `arrangement/1` is `:fan` or `:lanes` | one alternative, or one concurrent lane | parent's depth + 1 |
| `:rail` | a slot `rail?/1` accepts: `:secondary` or `:failure` | an attached rule beside the parent's region | parent's depth + 1 |
| `:tray` | a slot `tray?/1` accepts: `:tray` | beside the document rather than in it | parent's depth + 1 |

and the root, which sits in no slot at all, is `{root, 0, :step}`.

**Depth is block nesting depth and nothing else.** Every child is exactly one
deeper than the node whose slot holds it, in all four rows. A slot is not an
entry in the list and never consumes a level: an arm's blocks are one deeper
than their container, not two, and a rail's blocks are at the same depth as
that container's body blocks. The slot's identity is carried by the `kind`
column instead, which is why `kind` exists rather than a second numeric
column. A consumer that wants to draw a heading per slot draws it at the
transition between kinds; a consumer that wants indentation reads `depth`.

**`:step` versus `:arm` is `arrangement/1`'s question, asked once.**
`arrangement/1` (`:797-808`) already answers `:stack`, `:fan` or `:lanes` for
a node from its `body_slots/1` and its entry's `layout`, and `:fan` is
documented there as the exclusive arrangement and `:lanes` as the concurrent
one. The outline reuses that function rather than re-deriving the distinction
from a slot count, so a type declaring `layout: :columns` reads as arms here
for the same reason its slots sit side by side on the canvas, and the two
surfaces cannot drift apart.

**Slot order is the canvas's order, not the declaration's.** For each node the
walk visits `body_slots/1`'s slots first, in that function's order, then the
slots `rail?/1` accepts, then the slots `tray?/1` accepts - each group in
`node.slots` order within itself. `body_slots/1` (`:814`) is already defined
as "every slot placed in the body flow, in order", and the rail-then-tray tail
is what `10h`'s placement partition (`:1313`) and `10s` (`:3868`) put beside
and below the body - `10t` (`:3889`) is the section spelling out that `:tray`
is deliberately not in the rail partition, which is why the tail has two
groups rather than one. Reading order matching drawing order is the property that lets
a list view and the canvas be looked at side by side.

**Child order within a slot is `flow_children/1` then `shelf_children/1`.**
`flow_children/1` (`:741`) is the slot's children with the drafts shelf
rejected; `shelf_children/1` (`:748`) is the shelf, at most one by `ADR-0002`
G12b, and the canvas draws it last so it sits at the foot. The outline visits
both, in that order, and a shelf takes the kind of the slot holding it like
any other child. It is visited rather than skipped for the same reason a rail
is: `flow_children/1` exists so a renderer can draw connectors past the shelf,
not so a reader can be told the shelf is not in the document. A consumer that
wants the flow alone has `shelf?/1` (`:735`) and the list.

**A leaf contributes one entry.** A node with no slots, or with slots holding
no children, appears once and nothing follows it until its parent's next
child.

### The first consumer

The reference embedder's Plan view (`statifier_examples`) is the first thing
to consume this: a **host list view** that draws one line per block from
`Node.sentence`, indents it by `depth`, and uses `kind` to mark the lines that
are arms, rails and trays. It is a host's own surface, built out of this
package's components and this walk, and it stays in `statifier_examples`: the
operator's ruling `D16` (umbrella `docs/decisions.md`) is that components
promote and layouts do not. That pointer takes the qualified "umbrella" form
`ADR-0002:717` and `ADR-0004:895` already use for `D13`, because the document
it names is not in this repository; the principle itself is stated in the
sentence above and does not depend on reaching it.

Stated once so it cannot be misread: **this section adds no layout mode to the
package editor**, and nothing here is a mode, a view toggle, a second canvas
or an editor tab. `outline/1` is a function on the view model. What a host
draws with the list it returns is the host's.

### What this section does not decide

- **No layout mode, no pane, no tab.** See above; this is a function and a
  struct key.
- **Nothing about the canvas.** `arrangement/1`, `body_slots/1`, `rail?/1`,
  `tray?/1`, `flow_children/1`, `shelf_children/1`, `join_label` and every
  drawn edge behave exactly as before; `outline/1` reads them and changes
  none of them.
- **Nothing about chips.** `10n`, `10o`, `10p`, `10q`, `10r`, `10w` and
  `summary_chips/1` are untouched, and `sentence` is not a chip.
- **No cap on `sentence`.** That is `ADR-0002`'s amendment of this date, by
  `10n`'s own argument about where a presentation number lives; if a maximum
  is ever wanted for a **drawn** sentence it is this decision's to carry, and
  it is not carried here.
- **No selection, no findings, no ids.** `outline/1` returns nodes; a
  consumer that wants a block's id reads `node.block_id`, and the
  `on_select` descriptor at `:5156-5164` is unchanged and gains no `sentence`
  key.
- **No sort, no filter, no collapse.** The list is the document in reading
  order. Folding, filtering and searching it are a consumer's, and this
  package holds no state for them.
- **It edits nothing.** Decision 10, its amendments, the `on_select` table
  and every clause above stand as written; this section is additive and sits
  at the foot of the record so no line a sibling record cites moves.

### Implementing and flipping beads

`sb-w37s` builds `Node.sentence`, `outline/1` and the core types' sentences,
from this section and `ADR-0002`'s amendment of this date as merged.
`se-1cl` builds the Plan view against them in `statifier_examples`.
`sb-xnxw` flips **this section's status line** to accepted after `sb-w37s`
lands.

Filed with `sb-hlut`, campaign SF036, on ruling `RQ-SF036-5`.

## Amendment (2026-09-07): clauses 1C-4C, an optional `Recipe.members/2`, and the compound that deletes an arrangement in one gesture

**Status: accepted (2026-09-07, campaign SF036, bead `sb-gdmw`, on ruling
`RQ-SF036-7`).** A decision record merges at proposed under campaign SF036's
invariant, and **this section does not flip in SF036** - the ruling is record
only, and the campaign's consent (clause 11) says so in terms. Additive:
clauses `1C` to `4C` at `:5698-5788`, their "What this does not decide" at
`:5790-5802`, their Consequences at `:5804-5832`, clause `2n` at `:5654`,
clause `11u` at `:6477` and every clause above this line stand exactly as
written, and no text above this line is edited by this section. Nothing here
is built yet.

Every code cite below is a reading of `main` at `b57c197`, dated to this
section and to be re-read rather than trusted.

### The gap this closes, and the sentence that named it

Clause `4C`'s own "What this does not decide" left the hole and dated its own
answer to a later record (`:5792-5795`):

> **Whether a recipe can edit an existing arrangement.** `insert/2` builds; it
> is not a refactoring seam, and there is no `remove/2` beside it. Deleting a
> deadline is deleting two blocks, and it is two gestures until some record
> says otherwise.

This is that record, and it says otherwise for **delete only**. The wider
claim in that bullet - that a recipe is not a refactoring seam - is not
disturbed: nothing here lets a recipe move a block, retype one, or rewrite an
arrangement in place. It gains one read-only question it can answer about a
document it is shown, and the editor decides what to do with the answer.

The asymmetry the bullet describes is real and is worth stating plainly before
it is fixed. `insert/2` makes the deadline **one** gesture: one pick, two
`:insert`s, one `{:compound, ...}`, one undo entry (`2n` at `:5654`, "a
compound is **one undo entry**: one gesture in, one gesture out"). Removing it
is two picks, two `"remove"` events (`lib/statifier_blocks/editor.ex:1303-1311`),
two commits and **two** undo entries - and, between them, a document in the
state clause `11u` calls a lone deadline half. The arrangement goes in whole
and comes out in pieces.

### 1D. `StatifierBlocks.Recipe` gains an optional `members/2`

    @callback members(block_id :: Block.id(), document :: Document.t()) ::
                [Block.id()]

    @optional_callbacks members: 2

It is **optional**, which is the whole of its cost to an existing recipe: a
module implementing only `insert/2` and `palette_entry/0`
(`lib/statifier_blocks/recipe.ex:53-60`) is a valid recipe after this clause
exactly as it was before it, and a host that never wants a compound delete
writes nothing.

It is **pure**, on `insert/2`'s terms and for `insert/2`'s reason
(`:5736-5743`): it is handed a block id and the document as it stands, it
reads and does not write, it mints nothing, and it raises nothing. It returns
a list of block ids.

The **answer includes the block it was asked about** when the recipe claims
it, and is `[]` when it does not. A recipe that answers `[block_id]` and
nothing else has claimed a one-block arrangement, which is the same shape as
declining for every purpose the editor has - the compound of one remove and
the plain remove are the same gesture. `[]` is the way to say "not mine", and
a recipe with no `members/2` says it by omission.

### 2D. A recipe recognises its arrangement **structurally**, not by a mark

Nothing in the document says "this send is a deadline's send". Clause `11u`
(`:6477`) settles that as the first of its three reasons, and quotes `4C` for
it: both halves are ordinary blocks of ordinary core types, "the recipe is the
knowledge of how they go together and nothing more", and that knowledge lives
at gesture time and is not written down.

`members/2` does not change that, and the design turns on its not changing it.
A recipe answers by **recognising a shape in the document it is shown**, using
the same core knowledge `insert/2` already carries. For the core `"deadline"`
recipe, the shape is the one ADR-0010 decision 1 spells and
`StatifierBlocks.Core.DeadlineRecipe` already writes
(`lib/statifier_blocks/core/deadline_recipe.ex:73-85`):

- a `core.send` in a group's `body` slot, carrying an `event` and a `delay`; and
- a `core.on_event` on **that same group's** `interrupts` rail, whose `event`
  is the same string.

Asked about either half, the recipe finds the enclosing group, looks for the
partner on the other slot with the matching event name, and answers both ids
when it finds one.

Three properties follow from recognising the shape rather than the origin,
and each is deliberate.

**A hand-built pair is claimed.** An author who put down a `core.send` and a
rail `core.on_event` by hand, with matching event names, has built the
arrangement whether or not they used the palette entry. The recipe cannot tell
the difference, and should not: `11u`'s "the pair has no representation in the
document" cuts both ways.

**A renamed event still matches.** `DeadlineRecipe` generates the event name
(`:147-148`, `"deadline." <> String.slice(id, -8, 8)`), but recognition tests
that the two halves **agree**, not that either matches the generated form. An
author who renamed the event to something their domain uses has renamed both
halves - the config form writes one at a time, and a pair that disagrees is
not an arrangement - so the pair either still matches or is no longer a pair.

**A recipe never claims a block outside the enclosing group.** `3C`
(`:5745-5774`) bounds what `insert/2` may write to the armed position and the
enclosing block's slots, on the argument that an author can see the enclosing
group and cannot see what is above it. The same bound is the right one for a
delete a gesture triggers, for the same reason: an author deleting a block
must not have a block removed from a region they are not looking at. A
`members/2` answer naming a block that is not in the same enclosing group as
the asked-about block is refused by the caller before the compound is built,
exactly as an out-of-reach `insert/2` list is (`within_reach?/2`,
`lib/statifier_blocks/recipe.ex:89-92`).

### 3D. On delete the editor asks every recipe, and one claim becomes one compound

Where the editor today commits `{:remove, id}`
(`lib/statifier_blocks/editor.ex:1309`), it first asks each recipe in the
palette's `recipes` map (`lib/statifier_blocks/palette.ex:77`, `:223-225`)
that exports `members/2`. Then:

- **no recipe claims the block** - the commit is `{:remove, id}`, byte for
  byte what it is today;
- **exactly one recipe claims it** - the commit is the `{:compound, ...}` of
  a `{:remove, ...}` per claimed id. By `2n` (`:5654-5661`) that is **one undo
  entry**, so the arrangement comes out the way it went in, and one undo puts
  it back whole;
- **more than one recipe claims it** - the editor takes the claim of the
  recipe that sorts first by name, and the record does not make this a
  refusal. Recipes are a host-registered map with a later-wins collision rule
  on names (`1C` at `:5705-5708`); two recipes recognising the same shape is a
  host having registered two, and the deterministic pick is the property that
  matters at delete time.

The compound is **offered**, not imposed. An author who asked to delete one
block and got two removed without being told would learn not to trust the
delete; the clause is that the editor puts the compound to the author and
commits it on their word. `2n`'s undo is what makes a mistaken yes cheap, not
a substitute for asking.

### The claim, per variant

`members/2` is a question about a document, and what a document holds varies.
The claim is therefore stated per case rather than in general.

| The block the author deletes | What `members/2` answers | What the editor commits |
|---|---|---|
| a half of an arrangement a recipe recognises (both halves present, same enclosing group, agreeing event) | both ids, including the asked-about one | one `{:compound, [{:remove, a}, {:remove, b}]}`, offered to the author, one undo entry |
| a block no recipe recognises - most blocks in most documents | `[]`, or nothing at all where the recipe omits the callback | `{:remove, id}`, unchanged from today |
| a **partial** arrangement: a lone deadline half, its partner absent or its event renamed apart | not decided here - see below | `{:remove, id}` under the conservative reading, and this section does not settle it |
| a **composite block type**, once one exists | not asked - a composite is one block | `{:remove, id}`, one block, one command, by construction |

### `members` here are blocks; a shape's members are fields

This package already uses the word `member` for something else, and the two
must not be read as one vocabulary. A **shape**'s members are the fields of a
record-shaped type expression: `@type member :: %{name: String.t(), type:
type_expr(), required?: boolean()}` and `{:shape, [member()]}`
(`lib/statifier_blocks/environment.ex:132`, `:135`), decoded and rendered by
the type-expression control (`type_expr_members/1` at
`lib/statifier_blocks/editor/field.ex:1200-1202`, `decode_members/1` at
`:1259-1266`). A **recipe**'s members are blocks in a document. There is no
name collision - `Recipe.members/2` is a new function on a module that has
neither - but the word is shared, and a reader who carries the shape meaning
into this section will read it wrong.

### Worked example: a settlement deadline in the card-processing document

A `core.group` named "Settle" holds, in its `body`, a `core.send` with
`event: "deadline.a1b2c3d4"` and `delay: "1h"`, then a `myapp:capture` invoke;
on its `interrupts` rail it holds a `core.on_event` with
`event: "deadline.a1b2c3d4"` leading to a `myapp:authorize` reversal. One
palette pick put the pair down (`4C`); the author added the rest.

The author now selects the `core.send` and deletes it. The editor asks the
palette's recipes. `"deadline"` finds the send's enclosing group, finds a
`core.on_event` on that group's `interrupts` rail whose `event` equals the
send's, and answers both ids. The editor offers the compound; the author takes
it; one commit removes both halves and one undo restores both. Today the same
author gets one block removed, a lone `core.on_event` left on the rail, and -
correctly, by `11u` - **no finding telling them so**.

Had the author instead deleted the `myapp:capture` invoke, no recipe would
claim it, and the commit would be the `{:remove, id}` it is today.

### Which recipe-removes survive a composite block type

The next campaign's composites give a host a way to ship an arrangement as a
**single block type** whose interior the editor draws from the type rather
than from the document's tree. That changes the delete question completely for
anything expressed that way, and the boundary between the two mechanisms is
this record's to name, because it is the reason `members/2` is not made
redundant by them:

- **A composite deletes as one block by construction.** It is one block id in
  the document, one `{:remove, id}`, one undo entry, and no recipe is asked
  anything. It needs no membership because it has the representation `11u`
  says the deadline pair lacks - the block itself.
- **`members/2` serves exactly the arrangements that are still plain blocks.**
  An arrangement a host ships as a recipe stays two or more ordinary blocks in
  the document, keeps `11u`'s "no representation" property, and therefore
  keeps needing someone to recognise it at delete time.

So the boundary is not "recipes versus composites" as authoring gestures - it
is whether the arrangement is **written down as one thing**. The core
`"deadline"` recipe is the live case on the near side of that line: ADR-0010
decision 1 rules the clock interrupt is a pair rather than a `core.timeout`
type, so it is not a composite candidate, and it keeps `members/2` for as long
as that ruling stands. A host that later converts one of its own recipes into
a composite drops that recipe's `members/2` with it, and nothing in this
package has to be told.

### What this section does not decide

- **How the offer is drawn.** Whether the editor asks in a confirm dialog, a
  toast with an undo affordance, an inline count on the delete control, or
  something else, is presentation, and this record takes no layout ruling -
  the same restraint `4C`'s own non-decisions take about where recipe entries
  sit in the palette browser (`:5796-5799`).
- **Whether a partial arrangement is anything at all.** Clause `11u`
  (`:6477`) already answered the **compile-time** half of `sb-5ju0`'s
  question: a lone deadline half is not a finding and is not an orphan, and
  this section does not reopen it. The **delete-time** half is a different
  question and is left open here: whether `members/2` may claim a block whose
  partner is absent, and what a compound of one would mean. The table above
  records the conservative reading (a lone half deletes as one block) as the
  behaviour in the absence of a decision, not as the decision.
- **Nothing about `insert/2`, `palette_entry/0` or `within_reach?/2`.**
  Clauses `1C` to `4C` stand as written; `members/2` is a third callback
  beside two, and the first that is optional.
- **Nothing about the compiler or the wire format.** `4C`'s third
  non-decision (`:5800-5802`) holds unchanged: the compiler never sees an
  `Edit.t()`, and a compound of removes is no more visible outside the editor
  than a compound of inserts is.
- **No new finding, anywhere.** A document holding a partial arrangement is a
  document `11u` blesses. Nothing here adds a lint, a warning, or a view-model
  finding, and a recipe that declines to claim a block is not reporting
  anything about it.
- **No cross-document reach.** `members/2` is bounded by `3C`'s enclosing
  group (`2D` above); "is this event ever caught anywhere in the chart" stays
  the whole-document question `11u` routes to a host's `validate_document/1`
  validator under `11p`.

### Implementing and flipping beads

No bead in campaign SF036 builds this, and none flips it. The code is the
**SF037 composites campaign**'s: `Recipe.members/2`, the core `"deadline"`
recipe's implementation of it, the editor's delete path, and the offer.
**This record does not flip in SF036** (consent clause 11); the flip is a
separate gated request in the campaign that lands the code, and it re-reads
every cite above against `main` as it stands then.

Filed with `sb-gdmw`, campaign SF036, on ruling `RQ-SF036-7`.

## Note (2026-09-07): the `profile` amendment and the `Node.sentence` / `outline/1` amendment are flipped to accepted, and their code cites re-counted

The Amendment of 2026-09-07 on the `profile` assign and the read-only mount
(`:7303`) and the Amendment of 2026-09-07 on decision 10,
`ViewModel.Node.sentence` and `ViewModel.outline/1` (`:7852`) both read
`Status: accepted` from this date. `sb-xnxw` is the separate gated request
both sections' own status paragraphs name, and this Note is what the flip
checked.

It is by addition, sits at the **foot** of this record so that no line a
sibling record cites moves, edits no clause, and carries no `Status:` line of
its own. The only lines the request removes in this file are the two the
status words sit on. No marker is inserted beside either status paragraph:
inserting one mid-file is what this campaign's append-at-the-end rule exists
to prevent, and every forward sentence those paragraphs carry is met here
instead, where it stands. The Amendment of 2026-09-07 on `Recipe.members/2`
(`:8069`) is **not** flipped by this request and its status line is untouched,
on campaign SF036's ruling `RQ-SF036-7`.

### What was implemented, and where the flip read it

| Section | Implementing request | On `main` at | Read for this flip at |
|---|---|---|---|
| the `profile` assign and the read-only mount (`:7303`) | `sb-2bmk`, PR 378 | `8abc655` | `8abc655` |
| `Node.sentence` and `outline/1` (`:7852`) | `sb-w37s`, PR 377 | `ea2fdee` | `8abc655` |

Both status paragraphs say "Nothing here is built yet" and name their
implementing request; both are met by those two commits. The `profile`
section's "Where this lands" says the assigns table gains a `profile` row and
that `docs/profiles.md` "does not exist yet", both in `sb-2bmk`: the row is at
`lib/statifier_blocks/editor.ex:525` under the `## Assigns` heading at `:494`,
and `docs/profiles.md` exists. The outline section's closing sentence - that
`sb-xnxw` flips it after `sb-w37s` lands - is met by this request.

### What the flip verified, claim by claim

**The `profile` amendment.** The shape is the ruled one, verbatim:
`t:StatifierBlocks.Editor.toolbar_chip/0` (`editor.ex:586`) is `:history |
:zoom | :fits | :metrics`, and `t:StatifierBlocks.Editor.profile/0`
(`:592-598`) carries the five optional keys with `:all` a member of every list
type. The default is everything (`@default_profile`, `:603-609`): a mount that
passes no `profile` draws what `0.23.0` drew. There are no named profiles
anywhere in the package - no preset constructor, no `:operations`, no
`:reviewer`. There is no `validate_profile/1`: the only occurrence of the name
in `lib/` is the comment at `editor.ex:2091` recording that the amendment
refuses one, and an unresolved id is dropped by `Shell.inspector_tabs/1` and
`Shell.drawer_tabs/1` filtering the listed ids against the package's own
(`shell.ex:500-503`, `:545-548`) rather than raising. `read_only?`'s six
clauses each have code: clause 1, the palette column is behind `:if={not
@read_only?}` (`editor.ex:919`); clause 2, the canvas's drag hook is
`phx-hook={@drag_hook? && "StatifierBlocksDrag"}` (`editor/canvas.ex:144`)
with `drag_hook?={not @read_only?}` at `editor.ex:954`, while the measure hook
(`editor/connector_layer.ex:48`) is untouched; clause 3, the inspector and the
drawer both take `read_only` (`editor.ex:975`, `:1002`) and the config form
renders values; clause 4, selection and findings are unbranched - `"select"`
is not in the refused set; clause 5, `toolbar_items/1` drops `:history` from a
read-only mount whatever the profile listed (`editor.ex:2142-2146`); clause 6,
a single `handle_event/3` clause matching `%{profile: %{read_only?: true}}`
answers every gesture that would reach the document with the socket it was
given (`:1046-1048`), so `on_change` never fires. And a document is never
refused for being read-only: nothing on that path declines to draw.

**The `Node.sentence` / `outline/1` amendment.** `Node` carries `sentence:
nil` in its `defstruct` (`view_model.ex:402`), resolved at build time
(`:1531`) and not by a function called later. The three-step resolution is
`sentence/5` (`view_model.ex:1750-1758`): the reader's answer where
`declares_sentence?/1` (`:1760-1763`) says the type declares one, else the
author's `title`, else the entry's label falling back to the type name.
`ViewModel.title/1` is unchanged and keeps both its clauses (`:594-595`).
`outline/1` (`:941-942`) is public, pure, and returns `[{Node.t(),
non_neg_integer(), kind()}]` with `kind` typed `:step | :arm | :rail | :tray`
(`:871`). It is pre-order and the first entry is `{root, 0, :step}`:
`outline_walk/3` (`:946-954`) prepends the node and appends body, then rails,
then trays, and `outline_slot/3` (`:958-963`) visits `flow_children/1` then
`shelf_children/1`, walking each child at `depth + 1` - so every block appears
exactly once, a slot consumes no level, and reading order is the canvas's
order. `:step` versus `:arm` is `arrangement/1`'s question asked once
(`:947`), not re-derived from a slot count. Chips are untouched.

### Cites re-counted

`sb-2bmk` and `sb-w37s` moved code that both sections cite, and both sections
end by saying their cites are to be re-read rather than trusted. The
load-bearing ones read, at `8abc655`:

| Cited as, in the section | Reads today, at `8abc655` |
|---|---|
| `editor.ex` `:752` (`render/1`), `:817`, `:821`, `:835` | `:831`, the layout div `:914`, `PaletteBrowser.palette_browser` `:918`, `Toolbar.toolbar` `:933` |
| `editor.ex` `:469-497` (the assigns table), `:467` | `:494` is the `## Assigns` heading; the `profile` row is `:525` |
| `shell.ex` `:477` / `:166`, `:501` / `:191` | `inspector_tabs/0` `:477` and `@inspector_tabs` `:166` unmoved; `drawer_tabs/0` is `:527`, `@drawer_tabs` `:191` unmoved |
| `shell.ex` `:551-557` (`host_tabs/1`), doc `:533-549`, `:543` | `host_tabs/1` `:598` |
| `shell.ex` `:518-530` (`drawer_tab/2`), `:486-492` (`inspector_tab/1`) | `:565-577`, `:512-518` |
| `view_model.ex` `:403` (the `palette_groups` field), `:1763-1764` | `:451` in `@type t`, `:461` in the `defstruct`; the private builder is `:1953` |
| `editor/toolbar.ex` `:81` (`toolbar/1`), `:38-46` | `:96` |
| `editor/canvas.ex` `:132` (the drag hook) | `:144` |
| `editor/connector_layer.ex` `:48` (the measure hook) | `:48`, unmoved |
| `editor/palette_browser.ex` `:18` (decision 10's defaults) | `:16-21` |
| `view_model.ex` `:347-365` (`Node`'s struct), `:446-447` (`build/3`) | `defstruct` `:395-413`, the `sentence` key at `:402`; `build/3` resolves it at `:1531` |
| `view_model.ex` `:546-547` (`title/1`) | `:594-595` |
| `view_model.ex` `:1398` (`build_unresolvable_node`) | `:1557` |
| `view_model.ex` `:700` (`rail?/1`), `:719` (`tray?/1`), `:735` (`shelf?/1`), `:741` (`flow_children/1`), `:748` (`shelf_children/1`) | `:748`, `:767-768`, `:783`, `:789`, `:796` |
| `view_model.ex` `:797-808` / `:798` (`arrangement/1`), `:814` (`body_slots/1`) | `:846`, `:862` |
| `view_model.ex` `:637-638` (`summary_chips/1`) | `:685-686`, both clauses unchanged |

The cross-record line citations this file makes into `ADR-0002` and into
itself are re-baselined by the `mix adr.cites --update` this same request
runs, so the lines this campaign moved are recorded as a reviewed diff rather
than found by the next record to be edited.

### One line `ADR-0002`'s Note of this date needs read beside this record

`ADR-0002`'s amendment of this date says a block type that `use`s the
behaviour and overrides nothing is "indistinguishable from a module that
declares no `sentence/1`". That holds at **its** reader and not in **this**
record's chain: the injected default is a real `def sentence/1`, so
`declares_sentence?/1` (`view_model.ex:1760-1763`) answers `true` for it and
`Node.sentence` takes the reader's answer - the type's palette label - rather
than the author's `title`. The full statement, and the cost it carries, is in
`ADR-0002`'s foot Note of this date. Nothing in this record's three-step table
changes: the table is written in terms of what the type **declares**, and an
injected default is declared.

Filed with `sb-xnxw`, campaign SF036, folding the `ADR-0005` half of
`sb-xtcp`'s residue.

## Amendment (2026-09-07): Expand as one compound edit, how a composite block draws, and Collapse recorded at proposed

**Status: accepted (2026-09-07, campaign SF037, bead `sb-mjrt`, on rulings
`RQ-SF037-2` and `RQ-SF037-4`).** Parts **(i)** and **(ii)** below are flipped
to accepted by a separate gated request, `sb-v3ny`, after `sb-hgxl` lands the
gesture and the card. Part **(iii)**, Collapse, **is at proposed by its own
words and is not flipped in campaign SF037**: `RQ-SF037-4` rules it record
only, no bead in this campaign builds it, and a section whose code is a later
campaign's has nothing for a flip to check.

Additive. Clause `2n` (`:5654`), clauses `1C` to `4C` (`:5698`, `:5722`,
`:5745`, `:5776`), the Amendment of this date on `Recipe.members/2` (`:8069`,
whose own status line at `:8071` is untouched and stays at proposed), and every
other clause above this line stand exactly as written; no text above this line
is edited by this section. Nothing in parts (i) and (ii) is built yet, and
nothing in part (iii) is scheduled.

Every code cite below is a reading of `main` at `b1c3308`, dated to this
section and to be re-read rather than trusted.

### What a composite is, and which record decides which half

A **composite** is a block type derived from params plus a pure subtree: the
host declares the params an author fills in and the arrangement they produce,
and the package derives the type, the recipe and the expansion from that one
declaration. The declaration itself, and the behaviour a host `use`s to write
one, are `ADR-0002`'s: bead `sb-2gdx`, "ADR-0002 decision 5 amendment
(proposed): `use StatifierBlocks.Composite` - a block type derived from params
plus a pure subtree". What the **compiler** does with one - it expands at the
Resolve stage, and a finding inside an expansion is attributed one level up to
the param that produced it - is `ADR-0004`'s: bead `sb-nzc1`, "ADR-0004
amendment (proposed): the compiler expands a composite at the Resolve stage,
and a finding inside an expansion is attributed one level up to the param that
produced it". A composite that carries state, and the palette entry shape
`{module, state}` that reaches it, are the later `ADR-0002` amendment `sb-5b7j`,
"ADR-0002 amendment (proposed): a palette entry may be `{module, state}`,
resolved through one call seam, and `Composite.Data` is the stateful
composite". Those sections are in flight beside this one and are cited here by
bead and title deliberately: they have no line numbers yet, and a record does
not cite a line that does not exist.

This record decides the **editor's** half and nothing else: the gesture that
replaces a composite with its expansion, how a composite draws on the canvas
and in the palette browser, and - at proposed - the inverse gesture that turns
a selection into a declaration.

### (i) Expand: one gesture, one compound, one undo entry

**1E. Expand commits one `{:compound, ...}` whose first member removes the
composite.** A gesture on a selected composite block commits

    {:compound, [{:remove, id} | inserts]}

where `inserts` is the expansion's blocks as `{:insert, target, block}`
commands, in the order the expansion gives them. It is clause `2n`'s
constructor (`:5654`) used for exactly what `2n` describes: one author gesture,
a list of ordinary commands, and nothing new in the algebra. The set of edits
is still five, and Expand adds no sixth.

**2E. The remove comes first, and the inserts land at the composite's own
target.** `2n` says `Edit.apply/2` applies a compound's members "left to right
against the intermediate documents", and that is the whole reason the order is
fixed rather than incidental: the composite is removed first so that the
position it occupied is free, and each insert then names **the composite's own
target** - the same parent, the same slot, the same index the composite held -
so the expansion appears where the composite was rather than after it. A member
that refuses refuses the whole compound and `apply/2` answers `{:error, term()}`
with no document at all (`2n`), so an Expand that cannot complete leaves the
composite exactly where it was.

How many roots an expansion has is not this record's to fix - it is the shape
of `sb-2gdx`'s declaration - so the clause is written for a list of one or
more. Where a declaration's expansion is a single subtree, `inserts` is one
command.

**3E. One undo entry, and the selection lands on the first expanded block.**
By `2n` a compound is one undo entry - "one gesture in, one gesture out, and
no state between the halves that the author can stop in" - and its inverse is
the compound of each member's inverse in reverse order. So one undo removes
every expanded block and puts the composite back whole, and there is no
intermediate document in which the composite is gone and the expansion is not
yet there. After the commit the editor selects the **first** expanded block:
the block of the first `:insert` in the list. The composite's id is gone from
the document, so leaving `selected_id` (`lib/statifier_blocks/editor.ex:650`)
pointing at it would leave the inspector addressing a block that no longer
exists; selecting the first expanded block is the smallest answer that keeps
the author's attention where their gesture landed.

**4E. Expanded blocks carry no marker.** Nothing in the document records that a
block came out of a composite. `ADR-0001` decision 2 - "**2. A block is
`{type, id, config, slots}` and nothing else.**"
(`docs/adr/0001-block-document-schema.md:63`) - stands unweakened, and this
clause is what keeps it standing: an expanded block is an ordinary block, a
document holding one is an ordinary `ADR-0001` document, and a document that
has been Expanded is byte-identical to the same arrangement an author built by
hand.

Three consequences follow, and each is deliberate.

*Provenance is the history's, not the document's.* A plan view may say
"expanded from X" only while the compound `1E` committed still **heads the
history**; once another edit is committed on top, the document no longer knows,
and nothing is entitled to say it. This is the same discipline `2D` (`:8134`)
takes for the deadline pair: a recipe recognises its arrangement structurally
and not by a mark, because there is no mark.

*Collapse recognises structurally.* Part (iii)'s inverse gesture reads the
subtree in front of it, exactly as `members/2` reads the document it is shown
(`2D`, `:8134`). It never asks what a block used to be.

*A hand-built arrangement is indistinguishable from an expanded one, and that
is correct.* The same argument `2D` makes for the deadline pair - "an author
who put down a `core.send` and a rail `core.on_event` by hand ... has built the
arrangement whether or not they used the palette entry" - applies here word for
word.

**5E. Expand is refused when the target slot cannot hold the expansion's
root.** A composite declares its own `kinds`, and its expansion's root block
declares its own; nothing makes the two equal. So a slot that admitted the
composite need not admit what comes out of it, and the check is real rather
than defensive: before the compound is built, the editor asks whether the
target slot admits the expansion's root, by `ADR-0003` decision 3's rule -
"`:any` admits everything, otherwise `P`'s `slot_accepts[S]` and `B`'s `kinds`
must intersect" (`docs/adr/0003-assignability.md:98-99`; the editor already
reads `Assignability.slot_accepts/3` at
`lib/statifier_blocks/editor.ex:2595`). If it does not, **the gesture is
refused**: nothing is written, no command is built, and the composite stays.

The refusal is a **refused gesture, not a finding**, in exactly the sense `3C`
takes for a "deadline" armed where there is no `interrupts` rail (`:5745`,
"nothing is written, so there is nothing for the view model to say anything
about"). No lint, no warning, no view-model finding, and no entry in the
document.

**6E. This clause names the gesture, not the control's label.** "Expand" is the
name of the gesture in this record. It is already a **user-facing label** in
this package for something else: the card fold and unfold toggle answers
"Expand" when a card is folded
(`lib/statifier_blocks/editor/block_node.ex:496`), and the inspector's own
collapse control reads "Expand the inspector"
(`lib/statifier_blocks/editor/inspector.ex:338-339`). Two controls on the same
card both reading "Expand" would teach an author that unfolding a card and
replacing it with its expansion are one thing, which is the opposite of true.
So the implementing bead (`sb-hgxl`) chooses a label that does not collide with
the fold toggle, and this record takes no layout or wording ruling beyond that
constraint - the same restraint `4C`'s non-decisions take about where recipe
entries sit in the palette browser (`:5796-5799`). The module and function
names `Composite.expand/2` are free of the collision entirely; it is the label
on the card that is at issue.

### (ii) The card: a composite draws as one card, with no interior

**7E. A composite draws as an ordinary leaf card.** It is one block in the
document, so it is one node in the view model, and it draws the way any type
with no slots draws - summary chips and a sentence above them, and nothing
inside. `ViewModel.Node` (`lib/statifier_blocks/view_model.ex:309-428`) needs
no new field for it: the chips come from the composite's **params**, which are
its `config`, through the same `summary_chips/1` a `myapp:capture` invoke's
chips come through, and the sentence resolves through the same three-step
`Node.sentence` the Amendment of this date at `:7852` records. Nothing on the
canvas is special-cased for a composite, and that is the claim: if the drawing
code has to learn the word "composite", this clause has been implemented wrong.

**8E. A composite's `slots/1` is empty, in campaign SF037.** By `RQ-SF037-3` a
composite exposes **no slot of its own**: its `slots/1` answers `[]`, so it has
no interior an author can drop a block into, and the arrangement inside the
expansion is not addressable until it is expanded. A composite is therefore a
whole step or nothing, and an author who wants to edit its interior Expands it
first. Pass-through slots - a composite that offers one of its expansion's
slots to the author - are a later campaign's question and are not decided here.

**9E. A composite's palette entry is `kind: :type`.** The palette browser's
entry kind is `@type kind :: :type | :recipe`
(`lib/statifier_blocks/view_model.ex:445`), and a composite is a **block type**:
it has a `type_name`, it appears in a document, and `1C` (`:5698`) puts it in
the palette's `types` map, not beside it in `recipes`. No third kind is added.
An author picking a composite from the browser is doing the same thing as an
author picking a `core.group`, and `2C`'s argument for why a recipe draws like
a type (`:5722`, "an entry that announced itself as a special kind of entry
would be teaching a distinction the author does not have to make") is the same
argument, applied to an entry that really is a type.

**10E. The boundary between a recipe and a composite is the one this record
already named.** The Amendment of this date on `Recipe.members/2` states it
under "Which recipe-removes survive a composite block type" (`:8255`), and that
sentence is the boundary parts (i) and (ii) rest on:

> So the boundary is not "recipes versus composites" as authoring gestures - it
> is whether the arrangement is **written down as one thing**.

A composite is written down as one thing: one block id, one `{:remove, id}` on
delete, and no recipe asked anything (`3D`, `:8184`). Expand is the gesture
that turns it back into the several things a recipe's arrangement always was -
and after Expand, `members/2` is what recognises the result, because after
Expand there is nothing else to recognise it by.

### Worked example: "Authorize with a deadline" expanded in the card-processing document

A host ships a composite block type, `myapp.authorize_with_deadline`, declaring
two params: `delay`, a duration string, and `amount`, a path the authorization
reads. Its expansion is one subtree: a `core.group` whose `body` holds a
`core.send` carrying a generated deadline event and the declared `delay`, then
a `myapp:authorize` invoke reading `amount`; and on that same group's
`interrupts` rail, a `core.on_event` naming the same event and leading to a
`myapp:capture` reversal. It is, block for block, the arrangement `4C`'s
`"deadline"` recipe writes (`:5776`) with the authorization dropped inside it -
the difference is that the recipe writes those blocks into the author's
document and steps back, while the composite **is** a block in the document
that stands for them.

The author has one such block, id `"b7"`, at index 2 of the `body` of the
document root - a `core.sequence` with id `"seq1"` - drawn as a
single card reading "Authorize with a deadline" with a `1h` chip and an
`amount` chip - no interior, nothing to open (`7E`, `8E`). They want to change
what happens when the clock runs out, which the composite's params do not
expose. They select the card and Expand.

The editor checks that `seq1`'s `body` admits a `core.group` (`5E`); it does
(`ADR-0003` decision 3: a `core.sequence`'s `body` admits `:step`, and a
`core.group` is one).
It commits

    {:compound, [
      {:remove, "b7"},
      {:insert, {"seq1", "body", 2}, %Block{type: "core.group", ...}}
    ]}

- one command, one undo entry (`3E`) - and selects the inserted group. The
document now holds an ordinary `core.group` with an ordinary send, invoke and
rail handler inside it, indistinguishable from the same arrangement built by
hand (`4E`). The author edits the `core.on_event`'s subtree freely.

Two things follow that are worth stating because they are easy to expect
otherwise. **The document does not remember.** Once the author commits their
next edit, nothing anywhere says these four blocks were once one; a plan view
that said "expanded from Authorize with a deadline" while the compound headed
the history stops saying it (`4E`). And **the deadline recipe now claims the
pair**: the send and the rail handler are exactly the shape `2D` (`:8134`)
recognises, so deleting either one offers the compound delete the Amendment of
this date describes. Before the Expand, deleting the composite was one
`{:remove, id}` and no recipe was asked (`3D`'s fourth table row, `:8184`).
That is `10E`'s boundary, walked in one document in two gestures.

### (iii) Collapse: "save selection as a step", proposed and not built

**This part is at proposed by its own words and is not flipped in campaign
SF037.** `RQ-SF037-4` rules Collapse record only: no bead in this campaign
implements it, `sb-v3ny` flips parts (i) and (ii) and not this part, and a
later campaign's record - which will have code to check the clauses against -
is what may flip it. What follows is a proposal, stated fully enough to be
argued with and to bound what the SF037 code must not foreclose.

**11E. The proposal.** A gesture on a selection, "save selection as a step",
offers to turn the selected arrangement into a composite **declaration**: the
author marks which of the arrangement's config values become params, and the
subtree becomes the declaration's template with those values replaced by the
params that stand for them. The output is a declaration in the shape
`ADR-0002`'s data-composite amendment fixes - bead `sb-5b7j`, "ADR-0002
amendment (proposed): a palette entry may be `{module, state}`, resolved
through one call seam, and `Composite.Data` is the stateful composite" - and
not a new shape of this record's invention. This record proposes the gesture;
that record owns the declaration it produces.

**12E. The selection must be exactly one subtree under one parent.** Collapse
refuses anything else: two siblings, a block and a cousin, a selection
straddling two slots, or a partial subtree with a child left outside. The
reason is `1E`'s inverse read backwards. Expand replaces one block with an
expansion rooted where the block was; for Collapse to be its inverse, what it
replaces must be a single rooted thing occupying a single position, or there is
no one position for the composite to take. A selection of two siblings would
have to become two blocks or one block with two roots, and neither is a
composite.

**13E. A subtree that would need a pass-through slot is refused.** By `8E` a
composite in this campaign has no slots. A subtree with an **empty** slot the
author plainly means to keep filling - a `core.group` whose `body` the author
left open for later - cannot be expressed as a composite that exposes nothing,
and Collapse refuses it rather than silently freezing the slot shut. This
refusal is `8E`'s bound showing up on the authoring side, and it is the clause
that a later campaign's pass-through slots would relax. Like `5E`'s, it is a
refused gesture and not a finding.

**14E. Code is a later campaign's.** Nothing in campaign SF037 builds `11E` to
`13E`, and the SF037 code is under no obligation to leave a seam for them
beyond what parts (i) and (ii) already require. What it **is** obliged not to
do is foreclose them, and the two clauses that could have are already settled
the other way: `4E`'s no-marker rule means Collapse has nothing to look up and
must recognise structurally, which is what `12E` assumes; and `8E`'s empty
`slots/1` is what `13E` refuses against.

### What this section does not decide

- **How Expand is offered.** Whether the gesture is a control on the card, a
  context-menu entry, a toolbar action, or a keystroke is presentation, and
  this record takes no layout ruling - only `6E`'s constraint that whatever
  label it carries does not collide with the fold toggle.
- **Whether a non-root member of an expansion can be refused where its root is
  admitted.** `5E` tests the root, because the root is what takes the
  composite's position. Whether an expansion can even contain a second block
  that the same slot would refuse is a question about the shape of `sb-2gdx`'s
  declaration and is that record's, not this one's.
- **Anything about the compiler.** The compiler never sees an `Edit.t()`
  (`4C`'s third non-decision, `:5800-5802`), and Expand is an `Edit.t()`.
  What the compiler does with an unexpanded composite is `sb-nzc1`'s
  amendment of `ADR-0004`, and this record neither restates nor qualifies it.
- **Anything about how a composite's expansion reaches the environment.** How
  a composite exposes its expansion's path reads and writes to the environment
  walk is an open question at the time this section is written, it concerns
  `ADR-0002` and `ADR-0011` rather than this record, and this section asserts
  no mechanism for it.
- **No new finding, anywhere.** `5E`'s refusal and `13E`'s refusal write
  nothing, and a document holding a composite is a document `ADR-0001` blesses
  unchanged.
- **Nothing about `2n`, `1C` to `4C`, or `Recipe.members/2`.** Every one of
  those clauses stands as written; this section adds beside them and revises
  none of them.

### Two corrections to the Note at `:7749`, folding `sb-luo1`

`sb-luo1` records two residue items the `sb-4m4x` direction reviewer left
against the Note of 2026-09-07 at `:7749` ("the formatting-only exemption this
record's edits run under, stated here"). Both are answered here, by addition
and with no line removed.

**The quote-boundary cite reads `:6962-:6964`.** That Note's first table row
(`:7763`) cites `:6963-:6964` for the quotation

> "a change of case is a change to a word, which puts it outside the
> formatting-only exemption this record's edits run under"

The article that opens the quotation sits at the **end of `:6962`**, which
reads "unambiguously either way. It is corrected here rather than in place
because a"; `:6963` begins "change of case is a change to a word". The quoted
span is therefore `:6962-:6964`, one line wider than the row says. The row is
inherited from `sb-4m4x`'s own bead text and the narrow reading was carried
into the table with it. **Read `:7763`'s cite as `:6962-:6964`.** Nothing else
in that row changes: the quotation itself is exact, and the argument the Note
builds on it is untouched.

**The exemption's attribution stands as written, uncited, and the reason is
recorded rather than the cite added.** The Note says at `:7787-:7788` that the
formatting-only exemption "is the campaign convention this record has been
edited under since 2026-09-05", with no citation, where this record elsewhere
uses a qualified form for a campaign ruling - "the campaign-014 ruling D4"
(`:1847`), "under campaign-020 ruling D7" (`:2970`). `sb-luo1` asks whether the
attribution should take that form, and files the general question - whether a
public commit or request body is a citable anchor for this record - for a walk.

The judgement recorded here is that **the uncited attribution stands**, on a
distinction the two qualified forms make plain. `:1847` and `:2970` cite
rulings that **decided something this record then wrote down**: D4 chose the
duration control, D7 chose the arming behaviour, and each is a decision the
record is accountable for and a reader may want to trace. The exemption is not
of that kind. The Note itself says so in terms at `:7786` - "This is not a
decision of this record and it decides nothing about the editor" - and states
the rule in full in this record's own words immediately above, precisely so
that a reader can resolve it **without** leaving the file. A cite to an
external anchor would suggest the anchor governs and the statement paraphrases
it, when the Note's whole purpose is that the statement here is the one a
reader of this record uses. The general question `sb-luo1` raises is left open
for a walk and is not answered by this judgement, which is about this one
sentence.

### Implementing and flipping beads

`sb-hgxl` builds parts (i) and (ii) - the Expand gesture, the compound, the
refusal, and the composite card - from this section as merged, against
`sb-2gdx`'s and `sb-nzc1`'s amendments as merged. `sb-v3ny` flips **parts (i)
and (ii) of this section's status line** to accepted after `sb-hgxl` lands, and
re-reads every cite above against `main` as it stands then. **Part (iii) is not
flipped by `sb-v3ny`** and no bead in campaign SF037 flips it. No bead in this
campaign builds `11E` to `13E`.

Filed with `sb-mjrt`, campaign SF037, on rulings `RQ-SF037-2` and `RQ-SF037-4`,
folding `sb-luo1`.

## Amendment (2026-09-07): a `selected_id` a host may write, honoured in `update/2` through `rebuild/1`

**Status: accepted (2026-09-07, campaign SF037, bead `sb-2lx1`, on ruling
`RQ-SF037-12`).** A decision record merges at proposed under this campaign's
invariant; flipping it to accepted is a separate gated request, `sb-v3ny`,
after `sb-gbxt` builds it. Additive. The 2026-09-05 amendment *the host seams,
`on_select` and a selection descriptor* (`:5107`, whose own status line at
`:5109` is untouched and stays at proposed), decision 2's closed command set,
and every other clause above this line stand exactly as written; no text above
this line is edited by this section. Nothing here is built yet.

Every code cite below is a reading of `main` at `b37cf1d`, dated to this
section and to be re-read rather than trusted.

### Context

The selection crosses this component's boundary in one direction. The
2026-09-05 amendment (`:5107`) added `on_select`, and its argument for a
callback rather than a reader was that a selection "is editor state that only
the component knows, produced by a gesture on the canvas, and there is no pure
function of the host's assigns that answers it" (`:5140-:5142`). That argument
is about *reading* a selection, and it is correct. It says nothing about
*setting* one, and the assigns table (`lib/statifier_blocks/editor.ex:498-525`)
accordingly carries no key
that does.

A host now has a surface that needs to. The 2026-09-07 amendment on
`ViewModel.Node.sentence` and `ViewModel.outline/1` (`:7852`) hands a host the
rows to draw its own outline pane or plan view beside the editor, from the same
walk the canvas draws from. An operator clicking a row in that pane is making a
selection, and the pane has nowhere to put it. The double-pick the 2026-09-05
amendment records as the cost of having no seam - "Two selections that must
agree, with nothing keeping them in agreement" (`:5133-:5134`) - comes back in the
mirror image: the host's pane and the canvas each hold a selection, `on_select`
keeps the pane in step with the canvas, and nothing keeps the canvas in step
with the pane.

What a host reaches for instead is worth recording, because it is the cost.
`selected_id` is component state with an internal default (`:650` of
`lib/statifier_blocks/editor.ex`) and no row in the assigns table, but
`update/2` opens with `assign(assigns)` (`lib/statifier_blocks/editor.ex:707`),
which writes every key the caller named. A host can therefore pass
`selected_id` through `send_update/3` today and see something happen. Three
things are wrong with that, and only the third is obvious:

- **It is an undocumented internal.** The record does not list it, so nothing
  about it is promised: a rename, a split, or a move into a struct is a change
  this record would be free to make, and it would break a host silently.
- **It is not normalized.** The internal paths are careful never to leave
  `selected_id` naming a block the document does not hold - `remove_block/2`
  clears it when the removed block was the selected one
  (`lib/statifier_blocks/editor.ex:1737`), `remove_compound/2` does the same for
  a set (`:1749`), and `switch_document/2` clears it outright on a document
  swap (`:2007`). A raw write from outside is held to none of that, and an id
  the document does not hold survives into `notified_id`
  (`lib/statifier_blocks/editor.ex:651`, `:3372`), where it silences the next
  genuine selection of a real block that happens to be compared against it.
- **It is unguarded.** `assign(assigns)` writes what the caller named, so a
  host that passes the key on one `send_update/3` and not the next is not
  clearing the selection, it is leaving it - which is the right behaviour, but
  it is the right behaviour by accident rather than by a rule anyone wrote
  down.

There is already an assign of exactly this kind, and it is the model.

### Decision

**1S. `selected_id` is a documented input assign, honoured only when the update
carries it.** It gains a row in the assigns table
(`lib/statifier_blocks/editor.ex:498-525`) beside `on_select` (`:506` of that
file), and a guarded branch in `update/2`
(`lib/statifier_blocks/editor.ex:699`) keyed on
`Map.has_key?(assigns, :selected_id)`, placed with the other guarded branches
and before `{:ok, rebuild(socket)}` (`:782`). The guard is `active_marks`'
guard (`lib/statifier_blocks/editor.ex:757-763`) and it is there for the reason
that branch's comment gives (`:751-:756`): `send_update/3` "delivers the keys
it names and nothing else", so an assign read unguarded vanishes on the next
re-render the host made for a reason of its own. An update that does not carry
the key leaves the selection exactly as the author left it.

**2S. `active_marks` is the symmetry, clause for clause.** `active_marks` is
the existing host-supplied assign that is *held as editor state* rather than
merely read: it has a row in the assigns table
(`lib/statifier_blocks/editor.ex:513`) that says so, a
`has_key?` guard (`lib/statifier_blocks/editor.ex:758`), a normalizer on
the way in (`active_list/1`, `lib/statifier_blocks/editor.ex:2095-2100`), a
derived companion assigned in the same breath (`:active_ids`, `:761`), and a
reset on a document swap (`switch_document/2`,
`lib/statifier_blocks/editor.ex:2023`). `selected_id` takes that shape and adds
nothing to it: guard, normalizer (3S), and a reset on document swap it already
has (`:2007`). This is not a new kind of assign; it is the second member of a
kind this record already has one of.

**3S. An id the document does not hold clears the selection.** The branch
resolves the incoming id against the document being rendered. If it resolves,
`selected_id` becomes that id. If it does not - a stale row, a block a
collaborator removed, a typo - `selected_id` becomes `nil`, and *not* the
unknown id. This is the invariant `:1737`, `:1749` and `:2007` already keep
from the inside, stated once for the outside: `selected_id` never names a block
the document does not hold. Refusing the update instead was considered and
rejected: a host whose pane is one render behind the document is the normal
case, not an error, and `update/2` has no channel to refuse on - it answers
`{:ok, socket}` and nothing else.

**4S. Clearing fires `on_select` with `nil`, and so does every other change.**
The branch sits before `rebuild/1` (`lib/statifier_blocks/editor.ex:2824`),
which calls `notify_select/2` (`:2844`, `:3363`), so an input selection is
reported out on exactly the terms the 2026-09-05 amendment set: `nil` is a
selection and is delivered like one (`:5175`), and the callback fires when the
selection changes and not otherwise (`:5182`) - a host that writes the id
already selected gets no callback, because `notify_select/2` compares against
`notified_id` (`lib/statifier_blocks/editor.ex:3364`) and finds no change.
Because 3S normalizes *before* `rebuild/1` runs, `notified_id` records `nil`
rather than the unknown id, and the next selection of a real block fires.

A host that both writes `selected_id` and passes `on_select` therefore hears
its own write back. That is deliberate and it is not an echo to suppress: the
callback reports what the component's selection *is*, the write says what the
host would like it to be, and 3S is precisely the case where the two differ.
A host that suppressed its own write would never learn that its id was cleared.

**5S. It is an input, not a command.** A selection is editor state and not a
document edit. Decision 2's closed command set is untouched by this section:
there is no `:select` command, nothing about a selection is serialized, stored,
undone or redone, and `on_change` does not fire for one. This is the same
closure the 2026-09-05 amendment states at `:5188` ("No new command, and
`on_change` is untouched"), read from the other side - that section closed the
command set against the seam *out*, and this one adds no command to the seam
*in*. The moduledoc's "There is no `:select` command"
(`lib/statifier_blocks/editor.ex:461`) stands as written and needs no
qualification, because a documented assign is not a command.

**6S. The input takes the canvas gesture's companion resets, and nothing
else.** Selecting on the canvas closes the palette sheet and drops the
config-field focus in the same assignment
(`lib/statifier_blocks/editor.ex:1070`), because both are anchored to the block
the author was working on. A selection arriving from a host's pane leaves the
same two surfaces stale, so it takes the same two resets. It does *not* open
the drawer, change the inspector tab, scroll the canvas, or discard a draft: a
host that moves the selection is saying which block the editor is about, not
operating the editor's chrome.

### Worked example: an outline row click in the signup domain

A host mounts the editor for its `myapp:signup` document and draws its own
outline pane beside it from `ViewModel.outline/1` (`:7852`), one row per block.
The operator clicks the row for the block that sends the confirmation. The host
holds that row's block id, and calls

    send_update(StatifierBlocks.Editor,
      id: "signup-editor",
      selected_id: "blk_send_confirmation"
    )

`update/2`'s guarded branch reads the key (1S), the id resolves against the
document (3S), and `rebuild/1` draws the canvas with that block selected and
the inspector addressing it. `notify_select/2` sees the selection change and
calls the host's `on_select` with
`%{id: "blk_send_confirmation", type: ..., label: ...}` (4S), which the host's
pane uses to mark the row it just clicked - the same descriptor a canvas click
would have produced, by the same path. The two surfaces agree, and neither is
the authority: whichever one the operator touched last is.

Now suppose a collaborator removed that block and the host's pane is a render
behind. The id does not resolve, 3S clears the selection to `nil`, and
`on_select` fires with `nil`. The host's pane empties itself, which is the
behaviour the 2026-09-05 amendment already requires of a panel that follows the
canvas (`:5175`), reached here through the input rather than through a
deselection gesture. What does *not* happen is the inspector addressing a block
that is gone.

### Consequences

- **A host's own outline pane or plan view becomes a selection surface.** That
  is the whole of what this buys. `on_select` made the canvas's selection
  observable; this makes it writable, and the pair is what a two-surface host
  needs to keep one selection rather than two.
- **The host acquires no obligation.** The assign is optional, its internal
  default (`lib/statifier_blocks/editor.ex:650`) is unchanged, and a host that
  never passes it sees no difference of any kind.
- **Two writers, one assign, and no conflict to resolve.** The canvas gesture
  and the host both write `selected_id`, one write per update, last write wins.
  There is no merge, no priority and no "host mode": a selection has one value
  and the most recent gesture - from either side - decides it.
- **The inspector is unaffected.** It reads the selection out of component
  state exactly as it does today; this section changes where a write may come
  from, not what reads it.
- **Expand is the first in-package consumer, and `3E` is unaffected.** Clause
  `3E` (`:8524`) selects the first expanded block after the compound commits,
  and it does so for the reason 3S generalizes: the composite's id "is gone
  from the document, so leaving `selected_id` ... pointing at it would leave
  the inspector addressing a block that no longer exists" (`:8531-:8534`).
  That is the invariant of 3S, reached from inside the component, and Expand
  is the first thing in this package to need it - which is why `3E` is the
  first in-package consumer of this section's rule rather than an exception to
  it. Nothing in `3E` is revised: it names an internal write
  (`lib/statifier_blocks/editor.ex:1723` is the existing shape of one), and an
  internal write that already names a block the document holds satisfies 3S
  trivially. What this section adds is that one normalization now answers both
  paths, which is `sb-gbxt`'s to arrange.
- **Nothing about the wire format, the document, or the command set.** No new
  command (5S), no serialized field, no schema change. A document is what
  `ADR-0001` says it is, before and after.

### Implementing and flipping beads

`sb-gbxt` builds this section from it as merged - the assigns-table row, the
guarded branch, the normalization, and the tests that prove 3S and 4S. `sb-v3ny`
flips this section's status line to accepted after `sb-gbxt` lands, and re-reads
every cite above against `main` as it stands then.

Filed with `sb-2lx1`, campaign SF037, on ruling `RQ-SF037-12`.

## Note (2026-09-07): the `Recipe.members/2` amendment is flipped to accepted, its cites re-counted, and the `3D` tiebreak recorded as ruled

The Amendment of 2026-09-07 on clauses `1C`-`4C`, an optional
`Recipe.members/2` and the compound that deletes an arrangement (`:8069`)
reads `Status: accepted` from this date. `sb-yl9f` is the separate gated
request that section's own closing paragraph leaves to "the campaign that
lands the code" (`:8319`) without naming a bead, and this Note is what the
flip checked.

It is by addition, sits at the **foot** of this record so that no line a
sibling record cites moves, edits no clause, and carries no `Status:` line of
its own. The only line the request removes in this file is the one the status
word sits on. No marker is inserted beside the status paragraph: inserting one
mid-file is what this campaign's append-at-the-end rule exists to prevent, and
every forward sentence that section carries is met here instead, where it
stands.

Three of its sentences are answered by this request rather than reworded:

- "**this section does not flip in SF036** - the ruling is record only, and
  the campaign's consent (clause 11) says so in terms" is unchanged and true:
  it did not flip in SF036. It flips in **SF037**, the campaign that landed
  its code, which is what the same section's "Implementing and flipping beads"
  said would happen.
- "Nothing here is built yet." is met: `sb-e491` built it, and the
  claim-by-claim reading below is where this request checked it.
- "the flip is a separate gated request in the campaign that lands the code,
  and it re-reads every cite above against `main` as it stands then" is met by
  this request and by the re-count table below.

### What was implemented, and where the flip read it

| Section | Implementing request | On `main` at | Read for this flip at |
|---|---|---|---|
| `1D`, `2D`, `3D` and the per-variant table (`:8069`) | `sb-e491`, PR 388 | `b37cf1d` | `e3db9b1` |

### What the flip verified, claim by claim

**`1D`. The callback, and that it is optional.** `StatifierBlocks.Recipe`
declares `@callback members(block_id :: Block.id(), document :: Document.t())
:: [Block.id()]` (`recipe.ex:95`) and `@optional_callbacks members: 2`
(`:97`), beside `insert/2` (`:73-74`) and `palette_entry/0` (`:80`). It is the
only optional callback on the module. The optionality is not theoretical: the
recipe `StatifierBlocks.Composite`'s `__before_compile__` derives for a
composite type (`composite.ex:277-296`) implements `insert/2` and
`palette_entry/0` and nothing else, and is a valid recipe. The answer includes
the asked-about block when the recipe claims it, and `[]` is how a recipe says
"not mine" - both are stated in the callback's own `@doc` and both are what
the caller relies on (`3D` below).

**`2D`. Structural recognition, and the three properties.**
`StatifierBlocks.Core.DeadlineRecipe.members/2` (`deadline_recipe.ex:136-145`)
takes the last step of the document path for the asked-about block, resolves
the enclosing group, and dispatches on the slot the block sits in. `pair/3`
(`:166-187`) reads the shape and nothing else: asked about a `core.send` in
`body` carrying a non-empty `event` and a non-empty `delay`, it looks for a
`core.on_event` on that same group's `interrupts` rail whose `event` is equal
(`partner/4`, `:190-196`) and answers `[send_id, handler_id]`; asked about the
handler, it looks into the body for the send and answers the same list in the
same order. The three properties the section derives all hold in that code:

- a **hand-built pair is claimed**, because nothing in `pair/3` or `partner/4`
  reads provenance - only type, slot, `event` and `delay`;
- a **renamed event still matches**, because the test is equality between the
  two halves' `event` values, never equality with `event_name/1`'s generated
  form (`:248`, `"deadline." <> String.slice(id, -8, 8)`);
- **nothing outside the enclosing group is named**, because the rail is read
  off the group the asked-about block sits in and off no other block. The
  section says the caller refuses an out-of-group answer as it refuses an
  out-of-reach `insert/2` list; `same_enclosing_block?/3`
  (`editor.ex:1807-1813`) is that refusal, and `Recipe.within_reach?/2`
  (`recipe.ex:126-127`) is the `insert/2` one it is modelled on.

**`3D`. Ask every recipe; one claim becomes one compound.** `recipe_claim/2`
(`editor.ex:1777-1784`) sorts the palette's `recipes` map by name and takes the
first valid claim; `claim/3` (`:1786-1796`) asks only a module that exports
`members/2` (`members_exported?/1`, `:1798-1801`). The three cases the section
names are the three the code has: no claim commits `{:remove, id}` through
`remove_block/2` (`:1735-1740`, the commit at `:1739`), byte for byte the path
that existed before; one claim commits `{:compound, [{:remove, a}, {:remove,
b}]}` through `remove_compound/2` (`:1747-1752`), which by `2n` is one undo
entry; more than one claim takes the first by name and is not a refusal.

The compound is **offered, not imposed**, as the section requires:
`handle_event("remove", ...)` (`:1432-1442`) holds the claim as a
`pending_remove` assign instead of committing, and `handle_event(
"remove-confirm", ...)` (`:1448-1455`) recomputes the claim before committing
it, so an offer the document has outgrown falls back to the plain remove. The
section takes no layout ruling and none is taken by the code beyond the
smallest presentation that is honest: the block card's own delete control
draws `x2` where its `x` was, with a `keep` beside it
(`editor/block_node.ex:394-416`), and `"remove-cancel"` (`:1457-1459`) is
the way out. No mode is added to the editor.

Two answers the code refuses that the section's `2D` and `1D` require it to:
an answer naming a block outside the asked-about block's enclosing block, and
an answer that omits the asked-about block itself (`id in ids`,
`editor.ex:1790`). A claim of one id takes the unchanged path, which is `1D`'s
"a compound of one remove and a plain remove are the same gesture".

**The per-variant table.** Row 1 (both halves present) and row 2 (no recipe
recognises it) are the two paths above. Row 3, the **partial** arrangement, is
what `pair/3` answers `[]` for - a lone half, or a pair renamed apart - so the
conservative reading the table records is what the code does. That row is
recorded as behaviour in the absence of a decision and not as the decision,
and this flip does **not** settle it: the section's "Whether a partial
arrangement is anything at all" stays an open question, and nothing in
`sb-e491` decided it. Row 4, the composite, is verified below.

**"Which recipe-removes survive a composite block type."** `sb-xio9` landed
composites (`lib/statifier_blocks/composite.ex`, `main` at `d0af5f0`), so the
section's forward-looking boundary can be read against code for the first
time, and it holds:

- a composite **is one block**: `slots(_config)` is `[]` for every composite
  (`composite.ex:231`), so it has no interior in the document's tree to
  delete piecewise, and its delete is one `{:remove, id}` through
  `remove_block/2`;
- **no recipe claims it.** The recipe derived from a composite's declaration
  implements `insert/2` and `palette_entry/0` only (`composite.ex:277-296`),
  so `members_exported?/1` answers `false` for it and `claim/3` declines
  without calling anything. That is `1D`'s "a recipe with no `members/2` says
  it by omission", arriving for composites by construction rather than by a
  special case;
- **`members/2` serves the arrangements that are still plain blocks**, which
  is the core `"deadline"` recipe - registered in the palette's `recipes` map
  (`palette.ex:178`, the `defstruct` field at `:77`) rather than in `types`,
  where a composite's entry sits (`composite.ex:157`).

The boundary sentence this section states - "it is whether the arrangement is
**written down as one thing**" - is the one the Amendment of this date on
Expand and the composite card rests its `10E` on (`:8631`), and the two
records agree.

### What this flip verified as record and not yet as code

`10E` (`:8639-8643`) reads this section's boundary forward one step: after
Expand, `members/2` is what recognises the result, because after Expand there
is nothing else to recognise it by. That step is verified here **as record**
and is noted as pending code:

- the **Expand gesture** is `sb-hgxl`, which has not landed at `e3db9b1`.
  What can be checked today is that the shape `Composite.expand/2` produces
  for the reference composite - a group whose `body` holds a `core.send`
  carrying an event and a `delay`, and whose `interrupts` rail holds a
  `core.on_event` naming the same event - is exactly the shape
  `DeadlineRecipe.members/2` recognises, both halves inside the one enclosing
  group `same_enclosing_block?/3` requires. That the recognition then runs on
  an expanded document is `sb-hgxl`'s to demonstrate;
- the composite card's drawing - "whose interior the editor draws from the
  type rather than from the document's tree" - is `sb-hgxl`'s as well: the
  Amendment of this date on Expand names it in the same sentence that names
  the gesture, and it is likewise unlanded at `e3db9b1`. Nothing in this
  section's delete claims depends on it: `slots/1 = []` is what makes the
  delete one block, and that is landed.

Neither is falsified. Both are claims about code a later request in this
campaign lands, recorded here so the next reader is not left to guess which
half of the section had code behind it on the day it was accepted.

### `RQ-SF037-11`: the `3D` first-by-name tiebreak stands

`3D`'s third case - more than one recipe claims the block, and the editor
takes the claim of the recipe that sorts first by name rather than refusing -
was put to the campaign as an open question and ruled on 2026-09-07: the
tiebreak **stands**, unchanged, as `3D` wrote it. The reason is the record's
own, and is repeated here so the ruling is legible without the campaign's
paperwork: a host that registered two recipes recognising one shape gets a
deterministic pick, not a refusal. Recipes are a host-registered map with a
later-wins collision rule on names (`1C` at `:5705-5708`); two recipes
recognising the same shape is a host having registered two, and an author at
delete time needs an answer rather than an argument. `recipe_claim/2`
(`editor.ex:1782-1783`) implements it as written - `Enum.sort_by/2` on the
name, then the first valid claim - and no clause of this record is amended by
the ruling.

### Cites re-counted

`sb-e491` and the requests beside it moved code this section cites, and the
section ends by saying its cites are to be re-read rather than trusted. Every
one, read at `e3db9b1`:

| Cited as, in the section | Reads today, at `e3db9b1` |
|---|---|
| `editor.ex:1303-1311` (the two `"remove"` events; `sb-1q2r`) | `def handle_event("remove", %{"block-id" => id}, socket)` is `:1432`, its body `:1433-1442`; the plain path is `remove_block/2` `:1735-1740` |
| `editor.ex:1309` (where the editor commits `{:remove, id}`) | `commit({:remove, id})` at `:1739`, inside `remove_block/2` |
| `recipe.ex:53-60` (a module implementing only `insert/2` and `palette_entry/0` is a valid recipe) | the moduledoc sentence is `:33-38`; the callbacks themselves are `insert/2` `:73-74`, `palette_entry/0` `:80`, `members/2` `:95`, `@optional_callbacks members: 2` `:97` |
| `recipe.ex:89-92` (`within_reach?/2`) | `@spec` and `def` at `:126-127`, its `@doc` `:98-125` |
| `deadline_recipe.ex:73-85` (the shape the recipe writes and recognises) | `:73-85` is now the moduledoc's closing paragraph and the module attributes; the moduledoc's account of the shape and its three consequences is `:52-74`, and the recognition itself is `members/2` `:136-145`, `pair/3` `:166-187`, `partner/4` `:190-196` |
| `deadline_recipe.ex:147-148` (`"deadline." <> String.slice(id, -8, 8)`) | `event_name/1` at `:248` |
| `palette.ex:77` (the `recipes` field), `:223-225` (the recipes map) | `:77` unmoved; `manifest/1` is `:224` with `recipe_entries` at `:226`, `core_recipes/0` `:178`, `fetch_recipe/2` `:479-480` |
| `environment.ex:132`, `:135` (a shape's members) | both unmoved: `type_expr` with its `{:shape, [member()]}` arm at `:132`, `@type member` at `:135` |
| `field.ex:1200-1202` (`type_expr_members/1`), `:1259-1266` (`decode_members/1`) | `:1383-1384` and `:1440-1448` |

The `editor.ex:1303-1311` row is the whole of `sb-1q2r`, which is folded into
this request: the range was a reading of a `main` two campaigns of editor work
ago, and the handler it names has moved twice since. `sb-1q2r`'s second item -
whether the `3D` tiebreak should be revisited - is the question `RQ-SF037-11`
answers above.

Filed with `sb-yl9f`, campaign SF037, on ruling `RQ-SF037-11`, folding
`sb-1q2r`.

## Note (2026-09-07): the Expand/card amendment's parts (i) and (ii) and the `selected_id` amendment are flipped to accepted, with seven corrections by addition and three questions named; Collapse stays at proposed

`sb-hgxl` landed the gesture and the card on `main` at `ecc0db4`, and `sb-gbxt`
landed the `selected_id` input at `0c39a3c`. This Note is a reading of `main` at
`0c39a3c`. Every claim of the Amendment at `:8449` (parts **(i)** and **(ii)**
only) and of the Amendment at `:8825` was checked against that code before the
two `Status:` lines at `:8451` and `:8827` were flipped. No text above this line
is edited; everything below corrects by addition, which is this file's practice
at `:8398-8446`.

### 0. What flipped, what did not, and the sentences the flip falsifies

**Part (iii), Collapse, is not flipped.** The section says so three times in its
own words - at `:8454-8457`, again inside the part at `:8694-8698` ("`sb-v3ny`
flips parts (i) and (ii) and not this part"), and again at `:8818-8820`. The
section carries one `Status:` line for all three parts, so that one word now
reads `accepted`; clauses `11E` to `14E` remain at proposed **by the section's
own words**, which are the authority on their status and are unedited. Nothing
in this campaign builds Collapse, and `RQ-SF037-4` rules it record only.

Sentences the flip falsifies, left standing and met here: `:8463-8464`,
"Nothing in parts (i) and (ii) is built yet, and nothing in part (iii) is
scheduled" - the first half is now false and the second still holds; `:8834`,
"Nothing here is built yet"; and the two dating disclaimers at `:8466-8467`
(`b1c3308`) and `:8836-8837` (`b37cf1d`), which ask to be re-read rather than
trusted. They were.

### 1. Correction 1: the `Recipe.members/2` amendment is accepted, not proposed

`:8460-8461` says of the Amendment on `Recipe.members/2` at `:8069` that its
"own status line at `:8071` is untouched and **stays at proposed**". It does
not. `sb-yl9f` flipped it to accepted on 2026-09-07 at `b4461f5`, after this
section was written and before this flip, and `:8071` reads `accepted` today.

The claim the sentence was making - that this section edits no text above it and
leaves that amendment's status alone - is unaffected: `sb-mjrt` did not touch
`:8071` and neither does this Note. Only the parenthetical statement of what
that line *said* has gone stale, in the ordinary way a sibling record's landing
makes a dated cross-reference stale. It is left standing and dated here.

### 2. Correction 2: `2E`'s index walks

`:8512-8513` says each insert names "**the composite's own target** - the same
parent, the same slot, the same index the composite held". The parent and the
slot are the composite's. The index is not: `expansion_inserts/5` builds the
commands with `Enum.with_index(index)` (`editor.ex:1879`), so the n-th member
lands at the composite's index **plus n**.

This is `1E` chosen over `2E`'s wording rather than a departure from the
section. `1E` at `:8502-8503` fixes the inserts as "the expansion's blocks ...
in the order the expansion gives them", and a compound whose every insert names
one index applies them at that index in turn, which reverses the members. The
two clauses cannot both be read literally; the code took the reading that keeps
`1E`'s order, and says so at `editor.ex:1861-1870`. For a one-member expansion -
which is every case `2E`'s own worked example walks - the two readings are the
same command. `2E` is read as "the same parent and the same slot, starting at
the index the composite held".

### 3. Correction 3: `5E` admits every top-level member, not only the root

`:8569-8570` says the editor "asks whether the target slot admits **the
expansion's root**", and "What this section does not decide" reinforces it at
`:8745-8749`: "**`5E` tests the root, because the root is what takes the
composite's position.** Whether an expansion can even contain a second block
that the same slot would refuse ... is that record's, not this one's."

The code tests **every top-level member**:
`Enum.all?(members, &admits_expansion?(...))` at `editor.ex:1876`, with
`admits_expansion?/5` (`:1896-1908`) resolving parent and member through the
palette and asking `Assignability.admits?/3` (`assignability.ex:196-198`). The
implementation is therefore strictly stricter than `5E`, and it answers in the
strict direction the question `:8745-8749` declined to ask. `5E`'s decision -
that a refused expansion refuses the whole gesture, that nothing is written and
no command is built (`:8574-8575`, `editor.ex:1884`, `:1827`, `refused/2` at
`:2002`) - holds exactly as written.

**Whether admission should test the root alone or every top-level member is a
record question this Note names and does not decide.** The code has taken the
strict reading; `:8745-8749` says the question belongs to another record. It is
named here for the SF038 walk so that the next reader is not left to infer the
answer from the code.

The cite in the same clause has moved and changed function. `:8573-8574` says
"the editor already reads `Assignability.slot_accepts/3` at
`lib/statifier_blocks/editor.ex:2595`". `:2595` is a comment inside a
datamodel-reading helper today. The only `slot_accepts` call in `editor.ex` is
at `:2903`, inside `body_slot?/3` (`:2901-2907`), which answers whether a slot
is a body for the outcome-candidate machinery and is **not** the Expand
admission check. The admission check uses `admits?/3`, a different function, at
`:1900-1904`.

### 4. Correction 4: the worked example holds five blocks

`:8647-8653` declares an expansion of **five** blocks: a `core.group`, a
`core.send` and a `myapp:authorize` invoke in its `body`, and on its
`interrupts` rail a `core.on_event` leading to a `myapp:capture` reversal.
`:8683` calls them "these four blocks", and the enumeration at `:8677-8678` -
"an ordinary `core.group` with an ordinary send, invoke and rail handler inside
it" - omits the `myapp:capture` reversal that `:8653` put under the
`core.on_event`. The count is five and the omitted block is the reversal.

Nothing the paragraph argues turns on the number: "the document does not
remember" is true of five blocks exactly as of four. `:8676`'s "one command, one
undo entry" is `3E`'s claim about the gesture and the compound, not about the
command count inside the compound, which is six.

### 5. Correction 5: `3D`'s fourth row, and the boundary sentence

`:8640` (clause `10E`) and `:8689` (the worked example) both cite `:8184` for
"`3D`'s fourth table row". `:8184` is `3D`'s **heading**. The table's header is
`:8215-8216` and its fourth row is `:8220`:
"| a **composite block type**, once one exists | not asked - a composite is one
block | `{:remove, id}`, one block, one command, by construction |". Both cites
are read as `:8220`.

`10E` at `:8633` and `:8636-8637` attributes the boundary sentence - "So the
boundary is not 'recipes versus composites' ... written down as one thing" - to
`:8255`. `:8255` is the heading of that subsection; the sentence is at
`:8273-8274`.

### 6. Correction 6: what the `selected_id` amendment cites, and two phrasings

`sb-gbxt` built the input as the amendment describes, with one structural
difference and two phrasings that read wider than the code.

**The guard is extracted, not inline.** `1S` at `:8895-8898` puts "a guarded
branch **in `update/2`** ... keyed on `Map.has_key?(assigns, :selected_id)`,
placed with the other guarded branches and before `{:ok, rebuild(socket)}`".
The guard is in `put_selection/2` (`editor.ex:2957-2971`), called from `update/2`
at `:783` - between the `active_marks` branch (`:770-777`) and the `invoke_mark`
branch (`:785-790`), before `{:ok, rebuild(socket)}` at `:801`. So it sits
exactly where `1S` places it and does what `1S` says; only the branch's body was
lifted out, for the reason the code records at `:779-782` and `:2949-2951` - one
more branch inline crosses Credo's complexity bound for `update/2` as a whole.
`3S`'s normalization is `put_selected_id/2` (`:2981-2990`), and it answers `nil`
rather than the unknown id exactly as `:8919-8922` requires.

**Expand's selection is written after its commit, through the same input.**
`expand_composite/2` runs `commit/2` at `editor.ex:1823`, then
`put_selected_id(first_inserted_id(inserts) || socket.assigns.selected_id)` at
`:1824`, then `rebuild()` at `:1825`. Reaching the normalizer after the commit
is what lets it resolve the id against the **new** document, and the fallback
clears exactly when the composite that was selected has just gone. The
consequence at `:9023-9024` - "one normalization now answers both paths" - is
built: `put_selected_id/2` is called from `put_selection/2` and from
`expand_composite/2` and from nowhere else. The older recipe-insert path at
`:1750-1757` still writes `selected_id:` in an `assign` **before** its commit;
Expand deliberately does not.

**`:8865`.** "`update/2` opens with `assign(assigns)`
(`lib/statifier_blocks/editor.ex:707`)". `:707` is `last_error: nil`, the final
key of `mount/1`'s assign list. `update/2` opens at `:712`, and `assign(assigns)`
is at `:720` - the first **write**, after two reads. The point the sentence makes
- that `update/2` writes every key the caller named, so a host can pass
`selected_id` through `send_update/3` today and see something happen - is exact.

**`:8878-8881`.** An unnormalized id "survives into `notified_id` ... where it
silences the next genuine selection of a real block that happens to be compared
against it". `notify_select/2` (`editor.ex:3586-3597`) returns early only when
`socket.assigns.selected_id == socket.assigns.notified_id`. So a stale
`notified_id` silences the next selection **only when the block selected is the
one whose id it holds** - which is what the sentence's trailing qualifier says
and what its opening clause reads wider than. It is read as "silences the next
selection of a real block whose id happens to equal it".

**Rebuild count.** The host-input path costs **no** extra rebuild:
`put_selection/2` rebuilds nothing and `update/2` ends with the single
`{:ok, rebuild(socket)}` it always ran, which is what `4S`'s "the branch sits
before `rebuild/1`" (`:8930-8931`) buys. The **Expand** path costs one extra:
`commit/2` ends with its own `rebuild()` and `expand_composite/2` calls
`rebuild()` again at `:1825`, because the selection must be written after the
commit and `notify_select/2` runs only inside `rebuild/1` (`editor.ex:1819-1820`).

### 7. Correction 7: the cites the code moved

Claims unchanged; numbers only. Cites not listed here resolve exactly as
written, including `editor.ex:461`, `inspector.ex:338-339`,
`view_model.ex:309-428`, `view_model.ex:445`,
`docs/adr/0001-block-document-schema.md:63`, `docs/adr/0003-assignability.md:98-99`,
and this file's `:5654`, `:7852`, `:8069`, `:8134` and `:8524`.

| Cited in the two sections | Cited as | Reads today, at `0c39a3c` |
|---|---|---|
| `selected_id`'s internal default (`:8532`, `:8863-8864`, `:9003`) | `editor.ex:650` | `:662` |
| `notified_id` (`:8879-8880`) | `editor.ex:651`, `:3372` | `:663`, and the comparison at `:3587` |
| the fold toggle's "Expand" (`:8586-8587`) | `block_node.ex:496` | `fold_label/1` at `:607` |
| the assigns table (`:8847-8849`, `:8893-8894`) | `editor.ex:498-525`, `on_select` at `:506` | `:506-536`, `on_select` at `:516`, and the new `selected_id` row at `:517` |
| `active_marks`' guard and its comment (`:8898-8900`, `:8905-8913`) | `:757-763`, comment `:751-756`, `:758`, `:761`, table row `:513` | `:770-777`, comment `:764-769`, `:771`, `:774`, row `:524` |
| `update/2`'s guarded branch and its end (`:8895-8898`) | `editor.ex:699`, `:782` | `put_selection/2` at `:2957-2971`, called at `:783`; `{:ok, rebuild(socket)}` at `:801` |
| `active_list/1` and `switch_document/2`'s resets (`:8905-8913`, `:8877-8878`) | `:2095-2100`, `:2023`, `:2007` | `:2274-2279`, `:2202`, `:2185` |
| `remove_block/2`, `remove_compound/2` (`:8874-8877`) | `:1737`, `:1749` | `:1770`, `:1782` |
| `rebuild/1` and `notify_select/2` (`:8930-8931`, `:8935-8936`) | `:2824`, `:2844`, `:3363`, `:3364` | `:3046`, `:3067`, `:3586`, `:3587` |
| the select handler's assignment (`:8958-8961`) | `editor.ex:1070` | `:1090` |
| the existing internal write (`:9020-9021`) | `editor.ex:1723` | `:1714` |
| `slot_accepts` (`:8573-8574`) | `editor.ex:2595` | `:2903`, and it is a different function: see correction 3 |
| `3D`'s fourth row (`:8640`, `:8689`) | `:8184` | `:8220`: see correction 5 |
| the boundary sentence (`:8633`, `:8636-8637`) | `:8255` | `:8273-8274` |

### 8. What holds exactly, and what is named as a question

`6E` holds: the implementing bead chose **"Replace with its steps"**
(`block_node.ex:383`, with the aria-label at `:382` and the visible word
"steps" at `:388`), which collides with neither the card's fold toggle
("Expand", `block_node.ex:607`) nor the inspector's control ("Expand the
inspector", `inspector.ex:338-339`), which is exactly what `:8592-8593` asked of
it.

`7E` holds on every load-bearing claim. A composite is one node; `ViewModel.Node`
(`view_model.ex:309-428`) gained no field; the chips come from the composite's
config through the same `summary_chips/1`; and the drawing code never learned
the word. The affordance is threaded as `:expandable_ids`, a `MapSet` built in
`rebuild/1` (`editor.ex:3063`, from `composite_ids/2` at `:1916-1922`) and
passed `editor.ex:981` to `canvas.ex:117`/`:178` to `slot.ex:223`/`:306`/`:327`/`:344`
to `block_node.ex:280`/`:378`/`:475`/`:541-545`. `ViewModel` is untouched:
`ecc0db4` does not touch `lib/statifier_blocks/view_model.ex`, and the file
contains no occurrence of "composite".

`4E` holds: expanded blocks carry no marker, and `ADR-0001` decision 2 at
`docs/adr/0001-block-document-schema.md:63` stands. `8E` holds: a composite's
`slots/1` answers `[]` (`composite.ex:231`). `9E`'s `@type kind :: :type | :recipe`
is exact at `view_model.ex:445`. `3E` holds: the editor selects the first
expanded block after the commit.

**Two questions this Note names and does not decide.**

`7E` at `:8602-8603` says a composite "draws the way any type with no slots
draws - **summary chips and a sentence above them**". No card in this package
draws `Node.sentence`. `block_node.ex:355-389` draws the title button
(`ViewModel.title/1`, `:362`), the type subtitle (`:364-366`), the chips
(`:367-375`) and the invoke type (`:376`); no drawing component reads
`Node.sentence` at all. The `sentence/1` amendment of this date says as much in
its own terms - "A card draws what it drew yesterday" (`:7936`) - and speaks of
a "**drawn** sentence" as a thing that does not yet exist (`:8044-8047`). The
line a card actually draws above its chips is `ViewModel.title/1`, which
`:7916-7923` keeps deliberately distinct from `sentence`. `7E`'s claim about a
composite is true of every card equally, which is its point; **whether the
canvas card should draw `Node.sentence` at all is undecided by this record**,
and is named here rather than settled.

**Expand raises rather than refusing when a composite's declaration is broken.**
`expand_composite/2` handles three refusals through its `with`/`else`
(`editor.ex:1810-1828`) and the code enumerates them at `:1799-1804` -
"Nothing is written in any of them and the composite stays exactly where it
was". A fourth failure is not among them: `expansion_inserts/5` calls
`Composite.expand(block, module)` unguarded at `editor.ex:1874`, and
`Composite.expand/2` **raises** on a broken declaration - a `subtree/1`
answering `[]` or a non-`Block`, or duplicate local ids (`composite.ex:370`,
`:380`, and `check_local_ids!/2`). The error propagates out of
`handle_event("expand", ...)` and takes the LiveView process with it. This is
consistent with `composite.ex`'s own stance that a malformed declaration is a
programmer error, and it is inconsistent with `2E`'s "an Expand that cannot
complete leaves the composite exactly where it was" (`:8514-8517`) read as a
statement about every failure. **Whether the editor should rescue a malformed
declaration or let it raise is named here as a follow-up**, not decided; nothing
in parts (i) or (ii) depends on the answer, because a shipped declaration that
raises fails its own package's tests first.

### 9. `sb-yl9f`'s pending-code paragraph, dated forward

The Note at `:9038` records at `:9172-9196` what it verified "as record and not
yet as code", and both bullets are scoped to `main` at `e3db9b1`: the Expand
gesture "has not landed at `e3db9b1`", and the composite card's drawing is
"likewise unlanded at `e3db9b1`". Both remain true as dated readings, and both
are now answered: **`sb-hgxl` landed the gesture and the card at `ecc0db4`**,
five commits later. `10E`'s forward reading - that after Expand, `members/2` is
what recognises the result - now runs on an expanded document, which
`:9186` said was `sb-hgxl`'s to demonstrate, and
`test/statifier_blocks/editor/composite_expand_test.exs` is where it is
demonstrated.

One phrase inside that paragraph is worth correcting while it is being dated.
`:9187-9188` quotes `:8258-8259`'s "whose interior the editor draws from the
type rather than from the document's tree" as the composite card's drawing. As
built, a composite has **no** interior: `8E` makes its `slots/1` `[]`
(`composite.ex:231`) and `block_node.ex:530-531` says so in terms - "a
composite's `slots/1` is empty by clause `8E`, so `container?/1` is false". The
inherited phrase describes a card that was never built; the card that was built
is the leaf card `7E` describes.

### 10. Folding `sb-cr7e`: the `ADR-0011` amendment is accepted

`:7285-7290` reads "`ADR-0011`'s amendment of 2026-09-06 on decisions 1 and 2 is
**not** accepted: `sb-wzoa` left it at `proposed` over an open question about
which datamodel paths the environment seeds". It was true of that Note and is
time-bounded by its own words. For the later reader: `sb-wzoa` accepted that
amendment on 2026-09-07 at `dcf5668`, and
`docs/adr/0011-typed-environment.md:1848` reads `accepted` today. The open
question it names, about which paths the environment seeds, was itself answered
by the Note at `docs/adr/0011-typed-environment.md:1577`. The sentence at
`:7285-7290` is left standing and dated here.

### 11. Folding `sb-ot1x`: the layout-div cite, and the attribution

`sb-ot1x`'s `ADR-0005` items are folded here.

**The layout div.** The cite lives in the `sb-xnxw` amendment's
cites-re-counted table, in the row at `:8411` - not at `:8393`, which the bead
gives. That row was written against `main` at `8abc655` and has drifted again.
Today, at `0c39a3c`: `render/1` opens at `editor.ex:851` (cited `:831`), the
layout `div` opens at `:933` with its class attribute on `:934` (cited `:914`),
`PaletteBrowser.palette_browser` is at `:938` (cited `:918`), and
`Toolbar.toolbar` is at `:953` (cited `:933`). The bead's proposed correction of
`:914` to `:913` is wrong in both directions: `:913` is a
`Shell.insert_target/2` call, and the div's real line is `:933`. The row is
left standing and corrected here.

**The attribution.** `sb-ot1x` observes that `ADR-0002:6309-6314` attributes to
this record's amendment "a separate `function_exported?/3` question in the
chain", while this record's three-step table at `:7902-7906` speaks only of a
type that "declares `sentence/1`" and never names the function. That is right,
and the exact form of what this record decided is its own sentence at
`:8442-8444`: "the table is written in terms of what the type **declares**, and
an injected default is declared." `function_exported?/3` is how the
implementation asks that question - in `ViewModel.declares_sentence?/1` - and
naming it is `ADR-0002`'s reading of this record rather than a quotation of it.
`ADR-0002`'s foot Note of this date carries the same correction from its side.

Filed with `sb-v3ny`, campaign SF037, folding the `ADR-0005` half of `sb-cr7e`
and the `ADR-0005` items of `sb-ot1x`. This Note changes no code and adds no
README row; it flips the `Status:` lines at `:8451` and `:8827` and nothing else
in this file, and clauses `11E` to `14E` stay at proposed by the words of the
section that holds them.

## Amendment (2026-09-07): part (iii) by addition - Collapse's host seam is a pure proposer, an `on_collapse` callback and a separate replacement compound, and a proposed declaration may spell all nine field kinds

**Status: accepted (2026-09-07, campaign SF038, bead `sb-2fvz`, on rulings
`RQ-SF038-1`, `RQ-SF038-2` and `RQ-SF038-5`).** A decision record merges at
proposed under campaign SF038's invariant; flipping it to accepted is a
separate gated request, `sb-vjvq`, after `sb-uzly` builds it. Additive by
addition: clauses `11E` (`:8701`), `12E` (`:8712`), `13E` (`:8722`) and `14E`
(`:8731`), the section that holds them at `:8692`, that section's own status
paragraph at `:8451-8458`, the flip Note's restatement at `:9253`, and every
other clause in this file stand exactly as written. **No text above this line
is edited by this section**, and no line above it is removed.

It is appended at the **end of this file**, after the last Note, for the reason
`ADR-0002`'s data-composite amendment gives about itself
(`docs/adr/0002-block-type-behaviour.md:6744-6748`): other records on `main`
cite this one by line number, and an insert above any of them would leave those
citations pointing at the wrong text.

Every code cite below is a reading of `main` at `503ed48`, dated to this
section and to be re-read rather than trusted.

### What this section changes about part (iii), stated first

Part (iii) at `:8692` is a proposal "stated fully enough to be argued with and
to bound what the SF037 code must not foreclose". Campaign SF038 builds it, so
it now has to be stated fully enough to be **built** from. This section adds
`15E` to `20E`. Of the four clauses already there:

| Clause | Status after this section |
|---|---|
| `11E` (`:8701`) | Stands. The gesture, the marked params, and the declaration in `ADR-0002`'s shape are unchanged; `15E` to `18E` say what function produces it and where the output goes. |
| `12E` (`:8712`) | Stands, unamended. Exactly one subtree under one parent. `20E` restates that it stands. |
| `13E` (`:8722`) | **Relaxed by `20E`**, on `RQ-SF038-5`. It is the clause `13E` itself predicts - "the clause that a later campaign's pass-through slots would relax" (`:8727-8728`). |
| `14E` (`:8731`) | Superseded in fact and left standing in text. "Code is a later campaign's" was true when written; this campaign is that campaign, and `sb-uzly` is the request. Nothing else `14E` says changes: `4E`'s no-marker rule and structural recognition still hold, and they are what `15E` rests on. |

The section's `Status:` line at `:8451` reads `accepted` for parts (i) and (ii)
and, by the section's own words at `:8454-8457` and by the flip Note at
`:9253`, **not** for part (iii). This section does not touch that line. Part
(iii) is flipped - together with this amendment's own status line above - by
`sb-vjvq`, after `sb-uzly` lands, and not before.

### `15E`. The proposer is a pure public function, and it is the whole of the package's half

**`StatifierBlocks.Composite.Collapse.propose/3` takes the document, the
palette and the selection's block ids, and answers
`{:ok, declaration} | {:error, reason}`.** It reads; it does not write. It
takes no socket, no assigns and no `Edit.Session.t()`, it is callable from a
test, a script or a host's own code with no LiveView in the picture, and it is
the only entry point this package offers to Collapse's first half.

Three arguments and not two. The **document** is what the selection's ids point
into and what `12E`'s single-subtree check is run against. The **palette** is
how the proposer learns each selected block's field declarations, which is what
`18E` needs to decide which values are params and `19E` needs to decide whether
a value can be spelled at all; a block's type name in the document is a string,
and only the palette turns it into a schema. The **selection ids** are a list,
because the gesture's subject is a selection and `12E`'s refusal is a statement
about a list rather than a precondition the caller must have already met.

**What it answers is the storable row, minus its name.** The `{:ok, ...}` value
is a JSON-shaped map in the shape `ADR-0002`'s data-composite amendment fixes
(`docs/adr/0002-block-type-behaviour.md:7192-7223`) with `"version" => 1`,
`"params"` and `"subtree"` - and **without `"type_name"`**. `RQ-SF038-1` fixes
the arity at three and none of the three is a name, which is not an oversight:
a type name is a key in the **host's** palette namespace, the host is the only
party that knows what is already registered there and what its tenants may
call things, and a package that minted one would be minting a collision it
cannot see. `Composite.Data.declaration/1` (`lib/statifier_blocks/composite/data.ex:286`)
therefore refuses the map until the host names it, and that refusal is the
seam working rather than a gap in it: naming is the host's act, and the row is
not a declaration until it has been performed.

`"sentence"` and `"palette_entry"` are omitted for the same reason at one
remove. Both are optional in `declaration/1`, both are prose or presentation
the author never typed in this gesture, and a proposer that invented an English
sentence template or an icon would be inventing content and calling it a
proposal.

### `16E`. The gesture hands the declaration to `on_collapse`, edits nothing, and persists nothing

**"Save as a step" on a selected subtree calls `propose/3` and hands the result
to an `on_collapse` host callback, in `on_select`'s shape.** The 2026-09-05
host-seams amendment (`:5107`) fixes that shape and this clause takes it
whole: an assign beside `on_change` and `on_select`, absent by default,
ignored unless it is a function of arity one, invoked for its effect and never
for its return value, and fired once per thing that happened.

**The gesture edits no document and the package persists nothing.** No command
is committed, no `Edit.t()` is built, `on_change` does not fire, and the
undo history is not touched. The document after the gesture is byte-identical
to the document before it. What the host receives is a map; what it does with
it - which table, which column, which tenant it belongs to, whether it is
saved at all - is the host's, and this package has no opinion and no
storage. That is epic ruling `R5` ("a saved composite lives in the host's own
table; the package never persists") arriving at the one gesture that could
have broken it.

This is why the seam is a callback and not a return value, and the 2026-09-05
amendment's own argument (`:5137-5143`) applies here unchanged: a selection is
component state the host cannot compute from its own assigns, and neither is
the declaration derived from it. What cannot be read has to be pushed.

**A refusal is delivered too, or it is not delivered at all.** `propose/3`
answering `{:error, reason}` is a refused gesture in `5E`'s and `13E`'s sense
(`:8728-8729`: "it is a refused gesture and not a finding") - the editor
reports it to the author in its own chrome and writes nothing. `on_collapse`
fires only on `{:ok, declaration}`, so a host callback never has to pattern
match a failure it did not ask for.

### `17E`. `Collapse.replacement/4` answers the compound, and the host commits it

**`Collapse.replacement/4` takes the document, the selection's root id, the
type name the host registered, and the declaration, and answers the
`{:compound, ...}` that puts the composite where the arrangement was.** It is
the exact inverse of `1E` (`:8497`):

    {:compound, [{:remove, root_id}, {:insert, target, block}]}

where `target` is the arrangement's own target - the same parent, the same
slot, the same index the selection's root held - and `block` is a block of the
named type whose config is each param's declared `"default"`, which by `18E`
is the value the author had selected. Removing first and inserting at the
freed position is `2E`'s ordering (`:8508-8518`) for `2E`'s reason, read
backwards.

**It is a separate public function, and the host calls it or does not.** The
gesture does not call it, `on_collapse` does not call it, and nothing in this
package calls it. A host that saves a declaration and never swaps the
arrangement out has done a legitimate thing - it has added a type to its
palette - and the arrangement it was built from is still an ordinary
arrangement, which `4E` (`:8537`) is exactly the guarantee for. The swap can
only happen after the host has stored the declaration, named it, and rebuilt
the palette with it, because until then `{:insert, target, block}` names a
type the document cannot resolve; the ordering is a fact about the host's
work, not a rule this record imposes.

**One remove and one insert, both singular, and `12E` is why.** A compound is
one undo entry by `2n` (`:5654`) and `3E` (`:8524`), so the swap is one
gesture in and one gesture out for the author, with no intermediate document
in which the arrangement is gone and the composite is not yet there. The host
commits it through `Edit.Session.commit/2`, the same seam every other edit
takes.

### `18E`. Which params are proposed, how they are keyed, and what the template becomes

**The proposed params are the config values the author marks in the gesture;
where the author marks none, every value that differs from its field's
default.** The marked case is the primary one - the author is the only party
who knows which of `"myapp:signup"` and `"failed"` is the thing that varies -
and the unmarked case is a default that is right more often than it is wrong:
a value left at its field's default is a value the author never chose, and a
param whose default is the field's default parameterises nothing.

**Each param's field declaration is the source field's, and its default is the
selected value.** The `"type"`, `"label"`, and whichever of `"required?"`,
`"value_path"`, `"datamodel_path?"`, `"hidden?"` and `"readonly?"` the source
field declares are carried across unchanged (`data.ex:80-84`), and `"default"`
is set to what the block's config held. Nothing is re-derived: the control the
author sees on the composite's form is the control they were looking at on the
block, which is the whole of what makes the collapsed step recognisable to the
person who collapsed it.

**Keys, and the collision the arrangement can force.** A param's key is the
source field's key. Two blocks in one arrangement can declare the same field
key - two `core.assign`s both declare `path` (`lib/statifier_blocks/core/assign.ex:64-75`)
- so where a key would repeat, every colliding param takes the key
`<id_suffix>_<field key>` instead, with `id_suffix` the template node's own
(below) and the un-colliding params keeping their bare keys. The rule is
deterministic and it is stated because the alternative - refusing the
arrangement - would refuse the two-assign case, which is a perfectly ordinary
thing to want to save.

**The template is the subtree with each proposed value replaced by a
placeholder, and whole-value substitution is exactly the arm it needs.** Each
marked value becomes `%{"$param" => key}`; every other config value is carried
across as the literal it is. `Composite.Data`'s placeholder vocabulary already
records that this is its reason for existing (`data.ex:130-148`: "The reason
is `Collapse`: the gesture that lifts an arrangement's config values into
params emits **whole** values"), and this clause is the other half of that
sentence. A config value that genuinely is a one-key `"$param"` map is carried
as `%{"$literal" => ...}`, which is what that escape is for.

**`"id_suffix"` is minted from the source block's type, not from its id.** The
suffix is the type name's last dot-separated segment - `core.invoke` gives
`invoke`, `core.assign` gives `assign` - with a positional discriminator
appended where a type repeats in the arrangement, in document order:
`assign`, `assign_2`, `assign_3`. The source block's own id is not used
because a document id is arbitrary (`blk_7`), carries no meaning to a later
reader of the declaration, and need not match `@id_suffix`'s pattern
(`data.ex:213`), while a type segment always does.

One consequence, and it is sharp enough to state rather than leave to be
found. A `use`-composite twin of a collapsed declaration is byte-identical in
expansion **only if its authored `id_suffix`es are the ones this rule mints**.
`ADR-0002`'s "Guarded step" (`docs/adr/0002-block-type-behaviour.md:6665`) is
authored with `call` and `guard`, so its expansion's block ids are
`blk_GS_call` and `blk_GS_guard` where a collapse of the same arrangement
mints `blk_GS_invoke` and `blk_GS_assign`. The configs, the types and the tree
shape are identical; the ids are not, and a test asserting the byte-identity
this campaign's invariant requires compares a collapse against a twin written
with the minted suffixes. Nothing is wrong with either name - the rule simply
cannot ask an author who is not there.

### `19E`. All nine field kinds have a data spelling, and a value that still cannot be spelled is refused by name

`RQ-SF038-2`. A collapsed declaration is a `Composite.Data` row, so a field
kind with no JSON spelling is a field the gesture cannot carry. Today five of
the nine have one and four do not: `data.ex:86-93` says so in terms - the four
that carry options "are tuples rather than names and are refused here; ... a
spelling for them is a later record's to decide". **This clause is that
record.** All four gain a spelling.

**The spelling is one new optional key, `"options"`, beside the `"type"` name
the row already carries.** `"type"` stays what `data.ex:86-87` says it is - a
field type's name as a string - and `@field_types` (`data.ex:215-221`) gains
the four missing names. What the tuple's second element carries rides in
`"options"`, decoded by `decode_param/1` (`data.ex:478`) per kind:

| `"type"` | `"options"` | The `field_type/0` built (`lib/statifier_blocks/block_type.ex:179-188`) |
|---|---|---|
| `"string"`, `"integer"`, `"boolean"`, `"expression"`, `"duration"` | absent | `:string`, `:integer`, `:boolean`, `:expression`, `:duration` - unchanged, and an `"options"` on one of them is refused |
| `"select"` | `%{"choices" => [[value, label], ...]}` - a list of two-element lists of strings | `{:select, [{value, label}, ...]}` |
| `"path"` | the path options map: whichever of `"expects"` and `"writes"` the field declares, each a type expression as `ADR-0011` spells one | `{:path, %{expects: T}}` / `{:path, %{writes: T}}` / `{:path, %{}}` (`block_type.ex:205-225`) |
| `"list"` | `%{"inner" => ...}`, whose value is itself a `"type"` / `"options"` pair - the same spelling, one level down | `{:list, inner}` |
| `"type_expr"` | `%{"arms" => ["name", "inline"], "allow_empty?" => false}` - both keys optional, `"arms"` any non-empty subset | `{:type_expr, %{arms: [:name, :inline], allow_empty?: bool}}` (`block_type.ex:259-270`) |

Four notes on the table, one per row that needed a choice.

**`"select"`'s choices are pairs and not a map**, because `{:select, choices}`
is an ordered list of `{value, label}` (`block_type.ex:183`) and a JSON object
does not promise order. A two-element list is the smallest thing that keeps
the order the control draws in.

**`"path"`'s options are the map itself**, not a wrapper, because `path_opts`
is already a map with two optional keys whose values `ADR-0011` already writes
as strings (`block_type.ex:222-224`: `type: {:path, %{expects: "Settleable"}}`).
There is nothing to translate.

**`"list"` recurses through the same spelling**, so `%{"type" => "list",
"options" => %{"inner" => %{"type" => "string"}}}` is `{:list, :string}`, and
an inner kind that is itself unspellable makes the whole field unspellable by
the rule below rather than by a special case.

**`"type_expr"` needs no arm from `statifier_datamodel`, and this is the
premise that decided it.** The value a `{:type_expr, opts}` field holds is
"a declared type **name** as a JSON string, an inline shape as a JSON list of
`"name"` / `"type"` / `"required?"` objects, or nothing at all"
(`block_type.ex:259-265`) - it is already JSON, and `{:shape, members}` "is
never what a document holds" (`:264-265`). So the spelling carries `opts` and
nothing else, no type expression crosses a package boundary here, and
`RQ-SF038-2`'s "sd OUT" is a consequence of that sentence rather than a
scoping preference.

**A value the spelling still cannot carry is refused, and the refusal names
the block and the field.** A field type that is none of the nine, a `"select"`
whose choices are not string pairs, a `{:list, inner}` whose inner is
unspellable, or a `"default"` that is not JSON: `propose/3` answers
`{:error, {:unspellable_field, block_id, field_key}}` and proposes nothing.
Two ids, because "this arrangement cannot be saved" is not actionable and
"the `payload` field on `blk_13` cannot be saved" is - the author can go and
look at it. This is `16E`'s refused gesture, not a finding: nothing is written
and no document is changed.

### `20E`. `12E` stands; `13E` is relaxed, and an unfilled slot is proposed as a pass-through slot

`RQ-SF038-5`.

**`12E` stands exactly as written.** Exactly one subtree under one parent; two
siblings, a block and a cousin, a selection straddling two slots, or a partial
subtree with a child left outside are all still refused, for `12E`'s reason
(`:8712-8721`), which pass-through slots do not touch: a composite still takes
one position, and a slot the composite exposes is a slot **inside** its one
subtree, not a second root.

**`13E` is relaxed. A selection whose subtree holds an unfilled slot is
admitted, and that slot is proposed as a pass-through slot of the
declaration.** `13E` refused it because `8E` (`:8612`) gave a composite no
slots, so a `core.group` whose `body` the author left open could only have
been frozen shut. Campaign SF038 gives a composite slots - `ADR-0002`'s
pass-through amendment is the record - and the refusal's premise is gone with
it. `13E`'s own text predicts this ("the clause that a later campaign's
pass-through slots would relax", `:8727-8728`); this is that relaxation and
nothing wider.

**In the declaration's words.** The proposed row carries a `"slots"` key in
the shape the `ADR-0002` pass-through amendment fixes: a slot name to
`[local_id, inner_slot]`, where `local_id` is the template node's own
`"id_suffix"` (`18E`) and `inner_slot` is that node's own slot name. This
record proposes the gesture; that record owns the shape, exactly as `11E`
already says of the declaration itself (`:8709-8710`), and this section
invents no second spelling for it.

**The proposed slot's name is the inner slot's own name**, or, where two
proposed slots would collide on it, `<local_id>_<inner slot>` for every
colliding one - the same rule and the same reason as `18E`'s param keys.

**A filled slot is not proposed, and its children are not lifted.** Only an
**unfilled** slot becomes a pass-through slot. A slot with children in it is
part of what the author selected: its children become template nodes under it
like every other block in the subtree, they keep their configs and their
proposed placeholders, and they are not hoisted out into a slot the composite
exposes. An author who wants them to be a slot empties the slot first and
collapses again, which is a gesture they can see the result of; a Collapse
that silently turned a filled slot into an opening would be deciding for them
that the blocks they put there were an example rather than the thing.

**More than one unfilled slot proposes more than one pass-through slot**, and
there is no cap. Nothing in `12E` or in the pass-through shape counts them,
and a rule that admitted one and refused two would be an arbitrary line.

### Worked example: "Guarded step", collapsed

The signup domain. An author has built, by hand, a call that records the
failure when it comes back on the error path - `ADR-0002`'s "Guarded step"
arrangement (`docs/adr/0002-block-type-behaviour.md:6665`) with signup values
rather than card-processing ones:

    core.invoke   id "blk_7"
      config  %{"invoke_type" => "myapp:signup", "assign_to" => ""}
      slots   %{"on_error" => [
        core.assign  id "blk_9"
          config  %{"path"  => "signup.verification.failure",
                    "value" => "failed"}
      ]}

They select `blk_7` and `blk_9`, mark `invoke_type` and `path`, and take "Save
as a step".

**`propose/3` answers**, with the document, the palette and `["blk_7", "blk_9"]`:

    %{
      "version" => 1,
      "params" => [
        %{"key" => "invoke_type", "type" => "string", "label" => "Invoke type",
          "required?" => true, "default" => "myapp:signup"},
        %{"key" => "path", "type" => "string", "label" => "Write to",
          "required?" => true, "datamodel_path?" => true,
          "default" => "signup.verification.failure"}
      ],
      "subtree" => [
        %{"type" => "core.invoke", "id_suffix" => "invoke",
          "config" => %{"invoke_type" => %{"$param" => "invoke_type"},
                        "assign_to" => ""},
          "slots" => %{"on_error" => [
            %{"type" => "core.assign", "id_suffix" => "assign",
              "config" => %{"path"  => %{"$param" => "path"},
                            "value" => "failed"}}
          ]}}
      ]
    }

Reading it against the clauses: no `"type_name"`, no `"sentence"`, no
`"palette_entry"` (`15E`); `"version" => 1`; two params, each carrying its
source field's `"type"`, `"label"`, `"required?"` and `"datamodel_path?"`
with the selected value as its `"default"` (`18E`) - `core.assign` declares
`path` as a `:string` carrying `datamodel_path?: true`, not as a
`{:path, opts}` field (`lib/statifier_blocks/core/assign.ex:64-75`), and the
labels are that module's own rather than the ones `ADR-0002`'s hand-written
declaration chose; `"assign_to"` and `"value"` carried as literals because the
author did not mark them (`18E`); `"id_suffix"`es minted from the type
segments, each unique on its first use (`18E`); no `"slots"` key, because
`on_error` is filled (`20E`).

Nothing here needs `19E`'s new spellings, and the example is left that way
rather than stretched. Had the author also marked `core.invoke`'s
`assign_to`, which **is** a `{:path, %{}}` field
(`lib/statifier_blocks/core/invoke.ex:139-144`), that param would read
`%{"key" => "assign_to", "type" => "path", "options" => %{}, ...}` by `19E`'s
table - one new key, and the empty options map because the field declares
neither `expects` nor `writes`.

**The gesture then stops.** `on_collapse` receives that map; the document is
unchanged; `blk_7` and `blk_9` are exactly where they were. The host names it
`"myapp.guarded_step"`, stores it, and registers it - `{:ok, state} =
Composite.Data.declaration(row)`, then `Palette.from_modules([{"myapp.guarded_step",
{StatifierBlocks.Composite.Data, state}}], [])`
(`docs/adr/0002-block-type-behaviour.md:7227-7232`).

**The byte-identity.** A `use`-composite twin declaring the same two params
and the same subtree with `id_suffix`es `invoke` and `assign` expands, for a
composite block `blk_AD` with config `%{"invoke_type" => "myapp:signup",
"path" => "signup.verification.failure"}`, to:

| | Type | Minted id | Config |
|---|---|---|---|
| root | `core.invoke` | `blk_AD_invoke` | `%{"invoke_type" => "myapp:signup", "assign_to" => ""}` |
| in `on_error` | `core.assign` | `blk_AD_assign` | `%{"path" => "signup.verification.failure", "value" => "failed"}` |

which is what the data declaration above expands to, block for block, config
for config, id for id. `ADR-0002`'s own "Guarded step" is authored with `call`
and `guard` instead, so it differs in those two ids and in nothing else -
`18E`'s stated consequence, showing up in the first example that could have
hidden it.

**And the replacement, if the host wants it.** `Collapse.replacement/4` with
the document, `"blk_7"`, `"myapp.guarded_step"` and the declaration answers

    {:compound, [
      {:remove, "blk_7"},
      {:insert, target_of("blk_7"), %Block{type: "myapp.guarded_step",
        config: %{"invoke_type" => "myapp:signup",
                  "path" => "signup.verification.failure"}}}
    ]}

- the config is each param's `"default"` (`17E`), which is each marked value
(`18E`), so the composite the author gets back expands to the arrangement they
started with. The host commits it through `Edit.Session.commit/2` and the
author sees one undo entry.

### Worked example: "Guarded section", with the inner slot left unfilled

The same author, the same domain, one difference: they have not decided what
happens on the error path yet, and they want the step saved so that each use
can answer that for itself.

    core.invoke   id "blk_7"
      config  %{"invoke_type" => "myapp:signup", "assign_to" => ""}
      slots   %{"on_error" => []}

`core.invoke` declares `on_error` at `:zero_or_one`
(`lib/statifier_blocks/core/invoke.ex:96`), so the arrangement is legal as it
stands. They select `blk_7` alone and mark `invoke_type`.

**Under `13E` this gesture was refused.** The subtree holds an empty slot the
author "plainly means to keep filling" (`:8723-8726`), a composite had no
slots to expose it through (`8E`), and refusing was the honest answer.

**Under `20E` it is admitted**, and `propose/3` answers:

    %{
      "version" => 1,
      "params" => [
        %{"key" => "invoke_type", "type" => "string", "label" => "Invoke type",
          "required?" => true, "default" => "myapp:signup"}
      ],
      "slots" => %{"on_error" => ["invoke", "on_error"]},
      "subtree" => [
        %{"type" => "core.invoke", "id_suffix" => "invoke",
          "config" => %{"invoke_type" => %{"$param" => "invoke_type"},
                        "assign_to" => ""},
          "slots" => %{"on_error" => []}}
      ]
    }

One param, and one pass-through slot: the name `on_error` because nothing
collides with it, mapped to `["invoke", "on_error"]` - the template node's
`"id_suffix"` and that node's own slot name, in the `ADR-0002` pass-through
amendment's words. The template keeps the slot empty; it is the mapping, not a
hole in the template, that makes the opening real.

Named `"myapp.guarded_section"` and registered, it draws one card with one
interior, an author drops a `core.assign` into it, and the expansion splices
that block into the invoke's `on_error` keeping its own id. How the card draws
the interior and how `expand/2` splices is `ADR-0002`'s pass-through amendment
and this record's card clauses, not this section's; what this section decides
is only that Collapse proposes the slot instead of refusing the selection.

**A filled slot, for contrast.** Had the author left the `core.assign` in
`on_error` and taken the gesture, they would have got the first example: a
template with the assign inside it and no `"slots"` key at all. The two
arrangements differ by one block and the declarations differ by a slot,
which is the relationship `20E`'s two arms are meant to have.

### What this section does not decide

- **How a composite declares a pass-through slot.** `ADR-0002`'s
  pass-through amendment fixes the `"slots"` shape, the `use` option beside
  it, `slots/1`'s answer, and what `expand/2` splices. `20E` cites that shape
  and proposes into it; it does not define it, and where the two are read
  together, that record is the authority on the shape and this one on the
  gesture.
- **How the card draws an interior for a declared slot.** `8E` (`:8612`) says
  a composite's `slots/1` is empty "in campaign SF037" and `7E` (`:8601`) that
  it draws as a leaf card. Both are amended elsewhere on `RQ-SF038-5` and
  `RQ-SF038-14`, and this section neither restates nor qualifies them: it
  decides what Collapse **proposes**, and nothing about what the editor
  **draws**.
- **How a data composite declares a migration**, or what a declaration's
  `"version"` and a template node's version discipline are. `RQ-SF038-3` and
  `RQ-SF038-4` are ruled and their record is `ADR-0002`'s. `15E` sets
  `"version" => 1` on a first proposal because a row must have one; everything
  after the first save is that record's.
- **Where the host puts the declaration.** `16E` hands it over and stops. The
  table, the tenant scoping, the versioning of the host's own rows, and
  whether the host offers the swap at all are the host's, and epic `R5`,
  quoted under `16E`, is why.
- **What the gesture's control looks like.** `6E` (`:8583`) already takes this
  ruling for Expand - the clause names the gesture and not the control's
  label - and it applies here word for word. The operator's ruling `D16`
  (umbrella `docs/decisions.md`), which this record already cites in that
  qualified form at `:8023` - "components promote and layouts do not" -
  stands, and **this section adds no layout mode to the package editor**.
- **Anything about the compiler.** A document holding a collapsed composite is
  an ordinary `ADR-0001` `schema_version` 1 document naming a type by string;
  `4E` (`:8537`) is unweakened, an arrangement that has been collapsed and one
  built by hand are indistinguishable, and what the compiler does with a
  composite is `ADR-0004`'s.

### Implementing and flipping beads

`sb-uzly` builds `15E` to `20E` from this section as merged, against the
`ADR-0002` pass-through amendment as merged. `sb-vjvq` flips **part (iii)'s
clauses `11E` to `20E` and this section's own status line** to accepted after
`sb-uzly` lands, and re-reads every cite above against `main` as it stands
then. Nothing in this section is built yet.

Filed with `sb-2fvz`, campaign SF038, on rulings `RQ-SF038-1`, `RQ-SF038-2`
and `RQ-SF038-5`.

## Note (2026-09-07): the recipe seam a host picker calls, decision 9's decode answer, what `5E` admits, and the partial arrangement at delete time

Four items, from campaign SF038's walk (rulings `RQ-SF038-15`, `RQ-SF038-17`
and `RQ-SF038-14`). This is a **Note**: it carries no status line, nothing
flips with it, and no text above this line is changed by it. Items 1 and 2
answer questions earlier sections left open; items 3 and 4 say which of two
readings already written down here is the decision, so that the next reader is
not left to infer one from the code.

**Every `lib/` line number below is read at `main` `7fa35a2`.** The `mix
adr.cites` baseline covers citations into `docs/adr/` and nothing else, so a
cite into code is protected by the name beside it rather than by the gate: the
function, heading or comment named is what a later reader matches, and the
number is where it stood on that day. Item 3 is the worked example of why -
it re-counts two cites the 2026-09-07 corrections Note made against a
`lib/statifier_blocks/editor.ex` that has moved since.

### 1. A host picker that offers recipes calls `Edit.Targets`, not the editor

`1C` (`:5698`) lets a palette name recipes beside types, and `4C` (`:5776`)
registers core's one. What neither clause gave is a way for a host drawing its
**own** picker to ask the two questions this package already answers for its
own palette browser: which recipe names would land at an armed position, and
what command list inserts one. Both answers exist, and both are private to
`StatifierBlocks.Editor` - `accepted_recipes/2`
(`lib/statifier_blocks/editor.ex:3490-3492`, called from the palette-open
handler at `:1610`), the `recipe_lands?/4` it filters with (`:3501-3503`), and
`insert_from_recipe/3` (`:1872-1880`). A host that wants its own picker today
has to re-derive them, and a re-derivation is where `3C`'s bound goes quiet.

**The pair is promoted to `StatifierBlocks.Edit.Targets`**, which is already
the module that answers what-may-land-where for the palette's other map:

    @spec accepted_recipes(
            Document.t(),
            Palette.t(),
            Edit.target(),
            Assignability.context()
          ) :: MapSet.t(Palette.recipe_name())

    @spec recipe_inserts(
            Document.t(),
            Palette.t(),
            Palette.recipe_name(),
            Edit.target()
          ) :: {:ok, [Edit.t()]} | {:error, term()}

`accepted_recipes/4` takes the document, the palette, the armed position and a
context, in that order and with that default, because
`Edit.Targets.accepted_types/4` (`lib/statifier_blocks/edit/targets.ex:169-175`)
takes exactly those for exactly the same question asked of `types`. A host
composing a picker asks the two maps the same way or it learns two shapes for
one gesture.

`recipe_inserts/4` is `insert_from_recipe/3`'s middle with the socket taken
out: `Palette.fetch_recipe/2`, then the recipe's own `insert/2` (`2C`,
`:5722`), then `Recipe.within_reach?/2` for `3C`'s bound
(`lib/statifier_blocks/recipe.ex:127`). It answers the commands or the
refusal, and it commits nothing - assigning, minting a selection and committing
the `{:compound, commands}` stay the editor's, which is the half of
`insert_from_recipe/3` that does not generalise.

**The two compose, and that is what retires the third private.**
`accepted_recipes/4` is the filter over `palette.recipes` whose test is
`recipe_inserts/4` answering `{:ok, _}`. That is what `recipe_lands?/4` is
today, spelled once instead of twice, so the paint and the write cannot drift
apart on which recipes fit.

**Both checks still run at the write.** The comment above
`insert_from_recipe/3` (`editor.ex:1862-1871`) gives the reason and it is
unweakened by the promotion: a pick can arrive for a row the filter removed - a
stale sheet, a document swapped under an armed palette - and a recipe module's
bound is a property of the write rather than of the paint. A host that draws
its own picker from `accepted_recipes/4` and then commits its own compound is
running the same two checks in the same order; a host that skips the filter and
calls `recipe_inserts/4` alone still gets the refusal.

**The editor calls what it exports.** `accepted_recipes/2` becomes the same
three-line socket wrapper `accepted_types/3` already is (`:3463-3474`) -
unpack `document` and `palette`, pass `Assignability.context(socket.assigns)` -
and `recipe_lands?/4` goes.

#### What item 1 does not decide

- **Whether recipe admission should consult the context.** It does not today,
  and the promotion does not change that: `2C`'s `insert/2` callback is handed
  the target and the document and nothing else, so the fourth argument reaches
  no recipe. The comment at `editor.ex:3476-3477` already says a recipe's fit
  has one way of being asked. The argument is there for the shape a caller
  asks both maps in, and whether a later clause should thread it further is a
  question, not a promise.
- **Nothing about `Recipe`.** No callback is added, removed or widened;
  `insert/2` and `palette_entry/0` (`2C`) and the optional `members/2` are as
  written.
- **How a host draws the picker.** `4C`'s own non-decision (`:5796-5799`)
  stands, and this item takes no layout ruling.

`sb-5i4p` builds this item, after this Note. Nothing here is built yet.

### 2. Decision 9's decode does not omit untouched blank optionals

`RQ-SF038-17` answers the record question `sb-pgis` named in its request and
`RQ-SF037-12` put out of that campaign: whether `ConfigForm.decode/3`
(`lib/statifier_blocks/editor/config_form.ex:414-416`) should omit a blank
optional field the author never reached, rather than writing an empty string
into config. **The answer is no**, and the three parts the question asked for
are answered in its own order.

**(i) A blank optional field is not omitted, for any field type.** The one
exemption is the one that already exists.

**(ii) `decode/3`'s posting property stands, and the `:duration` omission stays
a special case rather than generalising.** The property is that a field whose
control did not post keeps the value it had: `decode/3` reduces over the
**schema's** fields, and a field the params have nothing for falls to
`field.value` (`config_form.ex:422-425`). The `:duration` omission is
`omitted?/2`'s single non-default clause (`:526-527`), and the heading above
`decode/3` calls it the one value that is not written at all (`:396`). The
decision-9 amendment of 2026-08-29 (`:1826`) is why it is there and why it does
not spread: a cleared `:duration` and a never-set `:duration` have to be the
same value because there is no zero-duration stand-in for them to differ by.
No other field type has that property. An empty `:string` is a string, an
empty `:expression` is an expression that fails to parse, and an empty
`:select` is a choice the schema either offers or does not - each is a value
the key can hold, so for each of them "absent" and "blank" are two states an
author can be in and a config can record.

**(iii) Clearing a field and never touching it stay the same value.** They are
the same today and this item keeps them so, which is exactly why the request
cannot be honoured: a `phx-change` payload posts the same empty string for
both, so "untouched" is not a thing the form can say. Honouring it would take a
new signal in the markup or a new rule about which blanks are meaningful, and
either is a change to the contract rather than a change to the decode.

Per case, over a field the schema declares and the form drew:

| What the author did | What the params carry | What `decode/3` writes |
|---|---|---|
| typed a value | that value | the value, at the field's path |
| cleared a `:duration` to blank | `""` | **the key is dropped** (`omitted?/2`, the exemption) |
| never reached a `:duration`, and it was already blank | `""` | the key is dropped, which is the same config - and that identity is the point of the exemption |
| cleared any other field to blank | `""` | `""`, at the field's path |
| never reached any other field | `""` | `""` - indistinguishable from clearing it, by (iii) |
| a field whose control did not post at all (a read-only form, a field the form did not draw) | nothing | `field.value`, unchanged |

**A `{config, changed?}` return is declined.** Widening `decode/3` from a
config to a pair would put the question back on every caller as a value to
thread, and it would answer a different question from the one asked: whether
the decode's output differs from its input is not whether the **author**
touched a field, which is the thing the payload cannot say. `decode/3`'s
return is `Block.config()` and stays it.

Nothing in `config_form.ex` changes under this item. It is recorded because two
records - ADR-0002 decision 7 on `config_schema/1` as a rendering hint, and
decision 9 here on the gate and the `:duration` omission - are what a change
would have had to move, and a question answered in a request body is answered
nowhere a later reader will look.

### 3. `5E` admits every top-level member, and the code is the decision

The Note of 2026-09-07 on the Expand and card amendment names this as a record
question and declines to decide it (`:9299-9318`): `5E` is written as a test of
**the expansion's root**, the code tests every top-level member
(`Enum.all?(members, &admits_expansion?(...))` at `editor.ex:2010`, with
`admits_expansion?/5` at `:2028-2030`), and the earlier non-decision says the
question belongs to another record. Those two cites are re-counted here
against the code as it stands: the correction Note reads them at `:1876` and
`:1896-1908`, where the lines have since moved.

`RQ-SF038-14` decides it here: **`5E` admits every top-level member of the
expansion, adopting the code.** The strict reading is the decision and the
root-only reading is superseded.

Two reasons. The first is that the strict reading is the one that keeps `5E`'s
own promise. `5E` refuses the gesture whole - nothing written, no command built
- so that an author never lands in a document the slot would not have accepted.
An expansion whose root the slot admits and whose second top-level member it
refuses would land exactly that document, and the refusal would arrive
afterwards as a finding on a block the author did not choose to put there. The
second is that the strict reading is the conservative one: every arrangement
root-only admission would have accepted, member-wise admission accepts too,
unless some member is refused - and in that case the gesture is refused rather
than a document being written that a later record would have to explain.

The correction Note's other holdings are untouched: `5E`'s refusal semantics
stand as written, and nothing it decided is reopened. Its two `editor.ex`
cites for this clause moved with a later edit and are re-counted above; that is
the ordinary cost of a line-number cite rather than a defect in what it said.
What changes is only that the question it named is no longer open.

### 4. The partial arrangement at delete time: the conservative reading is the decision

The `members/2` amendment records the conservative reading in its per-variant
table - a lone deadline half deletes as one block (`:8219`) - and its
non-decisions say the table records that "as the behaviour in the absence of a
decision, not as the decision" (`:8289-8296`).

`RQ-SF038-14` makes it the decision. **A partial arrangement deletes as one
block, and `members/2` claims nothing whose partner is absent.**

- **`members/2` answers `[]` for a block whose partner is missing**, or whose
  partner's event has been renamed apart, or that sits in a different enclosing
  group from the one the recipe recognises. It claims a block only when it can
  answer the whole arrangement.
- **The editor therefore commits `{:remove, id}`**, one block and one command,
  which is what it does for every block no recipe claims - the table's second
  row, reached by the third.
- **There is no compound of one.** A single-element `{:compound, [{:remove,
  id}]}` would be a second spelling of `{:remove, id}` with the same undo
  entry, and the offer `members/2` exists to make - the editor putting a
  two-block delete to the author before committing it - has nothing to put.

This is the reading `11u` (`:6477`) forces at the other end of the same
question. `11u` decides that a lone half produces no finding, because the pair
has no representation in the document: nothing marks a `core.send` as a
deadline's send, so there is no *the* missing half to find. A `members/2` that
claimed a lone half would be asserting at delete time precisely the thing
`11u` says is not there at compile time - that this block is half of something -
and it would assert it on a guess about an author's intent rather than on
anything written down. The two halves of `sb-5ju0`'s question get the same
answer for the same reason, which is the outcome the non-decision left room
for.

Nothing under `11u` is reopened and no finding is added anywhere. The
amendment's table row at `:8219` reads as the decision it already describes;
its wording is left as written, and this item is what makes it one.

Filed with `sb-twa0`, campaign SF038, on rulings `RQ-SF038-15`, `RQ-SF038-17`
and `RQ-SF038-14`. `sb-5i4p` implements item 1; items 2, 3 and 4 record
decisions about code that already stands.

## Note (2026-09-07): part (iii)'s Collapse amendment is flipped to accepted, its cites re-counted, two readings recorded as the code's, and 7E/8E pointed at the pass-through amendment

The Amendment of 2026-09-07 *part (iii) by addition* (`:9564`) is flipped to
**accepted**. Its own status line at `:9566` is the one word this Note's
request changed in that section; nothing else in it, and no line above it, is
edited. `sb-uzly` (PR 412, `main` `7fa35a2`) landed `15E` to `20E`, and this
Note is `sb-vjvq`, the flip the section names.

Read at `main` `d6fb241`.

### 1. The sentences the flip falsifies, met here rather than edited

The section carries its status in prose in several places, and the campaign's
record rule is that such a sentence is met in a foot Note rather than reworded
or removed. Each is left standing exactly as written:

- `:8694-8698`, inside part (iii): "**This part is at proposed by its own words
  and is not flipped in campaign SF037.**" True of campaign SF037, which is the
  campaign it names. Campaign SF038 is the "later campaign's record - which
  will have code to check the clauses against" that the same sentence says
  "is what may flip it", and this is that flip.
- `:8454-8457`, the section-level status paragraph: "Part **(iii)**, Collapse,
  **is at proposed by its own words and is not flipped in campaign SF037**".
  Same reading; the section's one `Status:` line at `:8451` already reads
  `accepted` and is **not** touched by this request.
- `:8818-8820`: "**Part (iii) is not flipped by `sb-v3ny`** and no bead in
  campaign SF037 flips it." It was not. `sb-vjvq` is a campaign-SF038 bead.
- `:9253-9259`, the SF037 flip Note: "**Part (iii), Collapse, is not flipped.**
  ... clauses `11E` to `14E` remain at proposed **by the section's own words**".
  That was the state after `sb-v3ny`. Clauses `11E` to `20E` are accepted as of
  this Note, which is the amendment's own instruction at `:10064-10068`
  ("`sb-vjvq` flips **part (iii)'s clauses `11E` to `20E` and this section's own
  status line** to accepted after `sb-uzly` lands").
- `:9564`'s section: "Nothing in this section is built yet" (`:10068`). It is
  built now, by `sb-uzly`.
- `:8463-8464`, "Nothing in parts (i) and (ii) is built yet, and nothing in
  part (iii) is scheduled", and `:8834`, "Nothing here is built yet": both
  halves are now false and both lines stand, met here.
- The dating disclaimers at `:8466-8467`, `:8836-8837` and `:9582-9583`, each
  asking to be re-read rather than trusted. They were, at `d6fb241`.

### 2. Two record-vs-code readings, recorded as the code's

Neither is a claim the flip refuses; both are the record read one way and the
code built another, and this Note records the code's reading as the one that
stands.

1. **`propose/3` is `propose/4` with a default.** `15E` fixes the proposer at
   three arguments and this Note keeps that: `propose/3` is exactly the
   record's signature, is `18E`'s unmarked reading, and is what the doctest
   calls. `18E`'s **marked** case needs a marks channel, so the marks ride an
   optional fourth argument - `Collapse.propose(document, palette, ids, marks:
   %{block_id => [field key]})`, `collapse.ex:186-190`, one head with
   `opts \\ []`. An empty marks map and an absent one both read as `18E`'s
   unmarked case (`collapse.ex:193-201`), which is what a tray with nothing
   ticked hands over. The record's arity sentence is met, not widened.
2. **`replacement/4` answers `{:ok, compound}`, not the bare compound.**
   `17E`'s prose says the function "answers the `{:compound, ...}`"; the code
   answers `{:ok, {:compound, [...]}} | {:error, reason}`
   (`collapse.ex:234-255`), because it must refuse the document root
   (`{:error, {:cannot_collapse_root, id}}`) and an id the document does not
   hold (`{:error, {:no_such_block, id}}`) rather than raise. The compound
   inside the `:ok` is exactly the one `17E` prints, in `17E`'s order. The
   tagged return is the reading that stands.

Also recorded, from `19E`'s implementation: a `{:path, opts}` field's options
are spelled as **strings only** (`19E`'s own reasoning, "whose values `ADR-0011`
already writes as strings"), so a `{:path, %{writes: {:list, shape}}}` field -
`core.map`'s `collect` - is refused as `{:error, {:unspellable_field, block_id,
field_key}}`. That is `19E`'s last clause applied, not an exception to it.

### 3. Cites re-counted at `d6fb241`

Every cite this section makes into this file resolves unchanged: `:5107`,
`:5137-5143`, `:5654`, `:8023`, `:8451`, `:8497`, `:8508-8518`, `:8524`,
`:8537`, `:8583`, `:8601`, `:8612`, `:8692`, `:8701`, `:8712`, `:8722`,
`:8731`, `:9253`. Appends land at the end of this file, so no line above moved.

The code cites have moved, and these are the readings at `d6fb241`:

| The section's cite | At `d6fb241` |
|---|---|
| `data.ex:286`, `declaration/1` | `composite/data.ex:419` |
| `data.ex:80-84`, a param's declared keys | `composite/data.ex:80-84`, unmoved |
| `data.ex:86-93`, "four ... are refused here" | `composite/data.ex:86-93`, and it now reads the other way: all nine field types have a name, the five plain ones alone and the four option-carrying ones with an optional `"options"` key. `19E` is what changed it |
| `data.ex:130-148`, the placeholder vocabulary | `composite/data.ex:175-192` |
| `data.ex:213`, `@id_suffix` | `composite/data.ex:334` (the prose statement of the same pattern at `:141-146`) |
| `data.ex:215-221`, `@field_types` | `composite/data.ex:350` |
| `data.ex:478`, `decode_param/1` | `composite/data.ex:660` |
| `block_type.ex:179-188`, `field_type/0` | unmoved |
| `block_type.ex:183`, `{:select, choices}` | unmoved |
| `block_type.ex:205-225`, `path_opts` | `:205-230`; the three-spelling example the section quotes is at `:223-225` |
| `block_type.ex:259-270`, `type_expr_opts` | unmoved; "`{:shape, members}` ... is never what a document holds" at `:263-265` |
| `core/assign.ex:64-75`, `path` and `value` | `:63-75`, `path` at `:65-73` |
| `core/invoke.ex:96`, `on_error` at `:zero_or_one` | unmoved |
| `core/invoke.ex:139-144`, `assign_to` as `{:path, %{}}` | `:139-145` |
| new: the proposer | `composite/collapse.ex:186-209` (`propose`), `:234-255` (`replacement`), `:504-552` (`19E`'s spellings), `:659-672` (`20E`'s pass-through proposal) |

The cites into `ADR-0002` - `:7192-7223`, `:6665`, `:7227-7232`, `:6744-6748` -
resolve, and `mix adr.cites` is green over this request.

### 4. `7E` and `8E`, and where their amendment lives (`sb-o9ex`)

`7E` (`:8601`, "A composite draws as an ordinary leaf card") and `8E` (`:8612`,
"A composite's `slots/1` is empty, in campaign SF037") are **amended by
addition** for the declared slot's interior; see `ADR-0002`'s pass-through
Amendment of 2026-09-07, `P6`
(`docs/adr/0002-block-type-behaviour.md:8274`). Neither clause's text is
edited here, and this Note adds no card rule of its own: `P6` is the authority
on what the card draws, exactly as this section's "What this section does not
decide" already says of it.

Filed with `sb-vjvq`, campaign SF038.

## Note (2026-09-08): the collapse tray without `on_collapse`, the chip cap and where a presentation finding draws, no sentence on the card, the reserved control strip, `4C` per-target admission, `last_error` on the surface, four read-only clauses, and `config_form/1` as a call a host composes

A dated Note rather than an amendment: it carries no `Status:` line, it never
flips, and no text above this line is edited by it. Eight items, each a ruling
taken with the operator at the campaign-SF039 walk on 2026-09-08 - `RQ-SF039-5`,
`-6`, `-7`, `-11`, `-12` and `-15` - written down here so that the beads which
build them have a record to build from rather than a plan to remember.

**Nothing in this Note is built yet.** Each item names the bead that builds it.
A reader in a later campaign should check the code before trusting any sentence
here that is written in the present tense about a surface.

**Every code cite below was read at `main` `f9b62c5`** (the `v0.26.0` tag), and
each is given with its anchor - a function head, a module attribute, an `attr`
declaration, or a CSS class name - so that a line which a later landing moves is
re-located by the anchor rather than by the number.

### 1. With `on_collapse` unset, the "Save as a step" control and its tray are not drawn

`16E` (`:9642`) makes the Collapse gesture a pure proposer: it hands a
declaration to an `on_collapse` host callback, edits nothing and persists
nothing. `on_collapse` is optional and defaults to `nil` (`editor.ex:703`,
`on_collapse: nil` in `mount/1`'s assigns), and `notify_collapse/2`
(`editor.ex:3710`, the `case socket.assigns.on_collapse do` head) answers `:ok`
and returns the socket unchanged when the assign is not a one-arity function.

The control, however, is drawn without consulting it. `.sb-node__save-step`
(`block_node.ex:402`, `title="Save as a step"`, `phx-click="save-as-step"`) is
conditioned on `:if={@node.block_id == @selected_id and not @root?}` and on
nothing else.

**The ruling.** With `on_collapse` unset, neither the "Save as a step" control
nor the tray it opens is drawn. A gesture whose only outcome is a callback
nobody registered offers the author a marking step, a Save, and then silence;
withholding it is the honest answer, and it is the same answer `read_only?`
clause 1 already gives (`:7476`) - the palette column is *not rendered*, rather
than rendered inert.

**"Replace with its steps" stays.** Expand (`.sb-node__expand`,
`block_node.ex:389`, `title="Replace with its steps"`, the word on the button is
`steps` at `:397`) needs no host callback: it is an `Edit.t()` the editor
commits itself. It is unaffected by this item in both directions - it is drawn
when `on_collapse` is unset, and its own conditions are unchanged.

Built by `sb-59rt`.

### 2. The cap is 32, and a presentation-cap finding draws in the drawer, not on the card face

Three parts, and they are separable.

**The number.** `10n` (`:2480`) fixes the presentation cap at 24 characters and
says the number is this record's rather than `ADR-0002`'s. It moves to **32**.
`@presentation_cap` (`block_type.ex:1365`) is the one place it is written, and
every message that quotes it interpolates it (`block_type.ex:1752-1768`), so the
messages follow the number.

**The cap is width-independent, and `--sb-card-width` does not move.**
`--sb-card-width` stays at `14rem` (`assets/css/statifier_blocks.css:394`). The
cap is a legibility number - what reads as a chip rather than as a sentence -
and not a measurement of the card. 32 is chosen as what fits one line at the
card's present width, but the two are not tied: a host that re-tokens the card
wider does not thereby get a longer cap, and this record takes no layout ruling
here.

**Where the diagnostic draws.** `summary_findings/4` (`view_model.ex:1717`)
makes one `:lint` finding per chip the cap refused, at `:warning`, and that is
`:3068`'s reader - the refusal is made legible rather than silent. But
`face_findings/1` (`block_node.ex:654`, called at `:469`) draws *every* finding
a node carries on the card face, so the diagnostics land on top of the card they
are about. Campaign SF038's capture bead `se-brd` measured what that costs: on
the card-processing composite fixture, four `.sb-finding` paragraphs filled the
card body below the chips and their background extended past the card's left and
right edges; on the signup guarded-section fixture the single one drew as a
full-width line between the card and its `THEN` slot label, so it read as
belonging to the slot rather than to the card.

**The ruling, two clauses.** A presentation-cap finding draws **only** in the
drawer's Findings tab, never on the card face - it is a diagnostic about a
declaration, and the drawer is where the document's diagnostics are read. And a
finding that *does* draw on a card face is **contained by that card**: it is
laid out inside the card's own box and neither overflows its edges nor reads as
belonging to a neighbouring slot.

**One clause is named here rather than taken here.** `RQ-SF039-6` also rules
that an over-cap chip draws truncated with an ellipsis instead of being dropped.
That is not this record's to take. `10o` (`:2489`) adopts `ADR-0002` `B3`'s
refuse-never-truncate discipline explicitly and says `ADR-0002` keeps ownership
of the semantics; `B3` itself (`docs/adr/0002-block-type-behaviour.md:831`, its
refuse-never-truncate bullet at
`docs/adr/0002-block-type-behaviour.md:846-847`) says "An over-long badge is
dropped, not clipped to the cap"; and `ADR-0002`'s own test for where such a
change belongs is stated in that record at
`docs/adr/0002-block-type-behaviour.md:5976-5981` - narrowing the reach of a
rule `ADR-0002` states "is a decision this record takes, not a catch-up
entry". So the ellipsis clause is **recorded here as ruled and queued**, and
the record that carries it is `ADR-0002`'s to write.
Nothing in this item depends on it: the number, the width-independence, the
Findings-tab home and the containment all stand whether the chip that exceeds 32
is dropped or clipped.

Built by `sb-hwlr`.

### 3. The card draws no sentence, and `se-brd`'s expectation of one was wrong

A card draws its title (`.sb-node__label`, `block_node.ex:366`), its type
subtitle, its summary chip row (`.sb-node__summary`, `block_node.ex:376`) and,
for a composite, the interior of the declared slot that `ADR-0002`'s
pass-through Amendment `P6` governs
(`docs/adr/0002-block-type-behaviour.md:8274`), which is where `7E` (`:8601`)
and `8E` (`:8612`) were pointed by the Note of 2026-09-07 (`:10304`). It draws
no sentence, no clause of this record asks it to, and none is added.

The sentence is the **list** altitude's. `ViewModel.Node.sentence` and
`ViewModel.outline/1` were built by the Amendment of 2026-09-07 (`:7852`) for
"the one walk a list view, an outline pane and a test all consume", and that is
where a block as one line of prose belongs.

`se-brd`, campaign SF038's capture bead, asked for "the composite card with
chips and sentence and no interior" and reported back that the card carried the
title and the chips only, with no element of a sentence class anywhere in the
canvas DOM, while the sentence did appear in the host's list row. **The bead's
expectation was wrong, and the code was right.** It is recorded here so that the
next reader of those captures does not read a missing sentence as a defect. No
card change follows from this item.

### 4. The control strip is reserved beside the title

The card's controls are siblings of the title inside `.sb-node__chrome` and are
revealed on hover or selection: `.sb-node__expand` (`block_node.ex:389`),
`.sb-node__save-step` (`:402`), `.sb-node__fold` (`:415`) and `.sb-node__remove`
(`:432`) each carry `data-reveal="hover-or-selected"`. Because the space is not
held while they are hidden, the title uses it, and the controls then appear on
top of the title: `se-brd` reported "steps" and "x" sitting over the last word
of "Authorize with a deadline".

**The ruling.** The control strip is **reserved** beside the title at all times:
the space the controls occupy is held whether or not they are revealed, the
title wraps beside it, and nothing truncates. Reserving is chosen over
truncating for the reason `B3` gives about chips - a clipped title reads as a
rendering bug where a wrapped one reads as a long name - and over drawing the
controls at rest for the reason `data-reveal` exists at all: a card at rest
should show the document, not the chrome.

This record names the strip **by role**, not by a class: there is no
`.sb-node__strip` in the markup at `f9b62c5`, and which element holds the
reservation is the implementing bead's to choose.

Built by `sb-59rt`.

### 5. `4C`: per-target admission beside the sweep

`accepted_types/4` (`edit/targets.ex:227`, `@spec` at `:221`) answers which of a
palette's block types would be accepted at one `{parent_id, slot}` target, by
probing **every** type in the palette. `accepted_recipes/4` is its recipe half,
added by the Note of 2026-09-07 (`:10073`, whose `@spec` for the promoted
arity is at `:10106-10111`) under clause `4C` (`:5776`) as the `1C`-`4C`
Amendment (`:8069`) reads it.

A "+" chooser at a gap does not have that question. It has "may *this* type go
*here*", asked once, and today the only public way to ask it is to build the
whole set and test membership.

**The ruling.** Two public functions join the module:

- **`Edit.Targets.admits_at?/5`** - `(document, palette, target, type, ctx)`
  answering a boolean. One probe of `type` and one `Assignability.check/5`
  (`assignability.ex:657`) at the gap, and nothing else.
- **`Edit.Targets.accepted_types_at/5`** - the same question over a **candidate
  list**, defaulting to the palette's own types, so a surface that already knows
  its shortlist pays for the shortlist rather than for the palette.

`accepted_types/4` **stays** and is the sweep: it is not deprecated, its
signature does not change, and it remains the right call for a palette browser
filtering itself against a position. The module's moduledoc says which of the
three to call, so that a surface writing the filter by hand - the failure the
`accepted_types/4` doc already warns about, where two views filtering the same
palette disagree and neither is visibly wrong - has one paragraph to read
instead of three function docs to compare.

Built by `sb-h5xq`.

### 6. A refused gesture renders `last_error` on the surface

`refused/2` (`editor.ex:2220`) assigns `last_error` and rebuilds. The assign is
carried across a session round-trip (`editor.ex:1737`, `:1784`) and read by the
declarations panel for its own refusal sentence (`editor.ex:1860`,
`Declarations.refusal(session.last_error)`), and it is rendered **nowhere else**:
no editor component template reads `@last_error` at `f9b62c5`. So a gesture the
editor refused - `5E`'s three refusals, the broken-declaration one - looks on
screen exactly like a gesture that did nothing, which is the same
indistinguishability the emulated-input problem has, arriving from the other
side.

**The ruling.** A refused gesture renders `last_error` on the surface. What the
sentence says is the refusal's own vocabulary, and where it is drawn is the
implementing bead's; this record rules only that the refusal is visible where
the gesture was made.

Built by `sb-f4r1`.

### 7. Four clauses about a read-only mount

The `profile` Amendment of 2026-09-07 (`:7303`) gives `read_only?` six clauses
(`:7473`). Four readings are added here; none of them widens what the clauses
say, and one of them is a bug.

**7a. `expand` joins the refused set.** `@read_only_refused`
(`editor.ex:683-691`) lists the events a read-only mount answers with the socket
it was given, and `expand` is not among them. It should be: Expand commits an
`Edit.t()` and changes the document, which is exactly what clause 6 says never
happens on such a mount. The passage that explains an *absence* from that list
is the moduledoc at `editor.ex:513`, and it is about "Save as a step", which
reaches nothing a read-only mount withholds because it is a read; it is not
about Expand and never was. This is a defect, filed as `sb-cqh8`.

**7b. An empty slot on a read-only mount draws a non-interactive placeholder.**
`gap/1` (`slot.ex:411`) draws its "+" behind `:if={not @read_only}`
(`slot.ex:428`), so on a read-only mount the gap is an empty `<div class="sb-gap">`
and an empty slot has nothing in it at all. The visible ring is styled on the
button, so withholding the button withheld the slot's only mark. Ruled: an empty
slot on a read-only mount draws a **non-interactive** placeholder - a mark that
says "this slot is empty", not a control that refuses. Built by `sb-b7i0`.

**7c. Clause 1 withholds the gap "+" as well as the palette column.** Clause 1
is written in terms of the palette *column* (`:7476`), and a reader could take
it to leave the gap "+" - which opens the same palette by the same
`palette-open` event - untouched. It does not. The code already reads it the
narrow-offering way (`slot.ex:428`, and the `read_only` attr's own doc at
`slot.ex:245`, "`true` draws the gaps without their '+' buttons"), and that
reading is the correct one: clause 1 is about a mount offering **no way to add a
block**, and the column and the gap are two doors to one room. This item records
the reading; no code changes for it.

**7d. The drawer's package tab set is six, and the Source listing is the
sixth.** `@drawer_tabs` (`shell.ex:191`) is
`[:tables, :findings, :declarations, :fixtures, :datamodel, :source]`. The
drawer's own moduledoc says the same in prose ("The Source listing is the sixth
and came behind no reservation at all", `drawer.ex:36`), and `1A`'s reserved
places are spent. Six is the number; a seventh joins only on its own merits
under `1A`. This item records the count; no code changes for it.

### 8. `Editor.ConfigForm.config_form/1` becomes a call a host composes

The operator's ruling `D16` (umbrella `docs/decisions.md`), already cited by
this record at `:8023` and `:10052`, is that a host's own authoring surface
draws package components rather than re-implementing them. A host that wants one
block's fields under its **own** `handle_event/3` is the case this item is
about.

`config_form/1` (`config_form.ex:220`) is nearly that component already. Two
things stop it:

- `phx-change` and `phx-submit` are hard-coded to `"config-change"`
  (`config_form.ex:229-230`), which is the editor component's own event name.
- `attr(:target, :any, required: true)` (`config_form.ex:50`) is required, so a
  host whose form posts to the LiveView itself has no way to omit it.

**The ruling.** `config_form/1` gains an **`event`** attr, defaulting to
`"config-change"` so that every present caller is unchanged, and its **target
becomes optional**. A host then composes one call instead of hand-writing a
field pair.

**The block id is not new.** The form already posts the block it is about as a
hidden input - `<input type="hidden" name="block-id" value={@node.block_id} ... />`
at `config_form.ex:239` - and that input is what a host reads the id out of its
params by. This item does not add it; it names it, because a host composing the
call needs to know the id arrives without being asked for.

What this item does **not** decide is the look. The field controls, their
labels and their layout stay the package's; the surrounding chrome stays the
host's. It adds no layout mode to the package editor.

Built by `sb-ykkl`; the reference embedder deletes its hand-written pair in
`se-7p1`.

### Cite table

Every line number below was read at `main` `f9b62c5`; the anchor beside each is
what a later reader matches.

| Cite | Anchor |
|---|---|
| `editor.ex:703` | `on_collapse: nil` in `mount/1`'s assigns |
| `editor.ex:3710` | `notify_collapse/2`, `case socket.assigns.on_collapse do` |
| `editor.ex:513` | the "Save as a step" moduledoc paragraph, "It is offered on a read-only mount as well" |
| `editor.ex:683-691` | `@read_only_refused` |
| `editor.ex:1737`, `:1784` | `last_error` across a session round-trip |
| `editor.ex:1860` | `Declarations.refusal(session.last_error)` |
| `editor.ex:2220` | `defp refused(socket, reason)` |
| `block_node.ex:366` | `class="sb-node__label"` |
| `block_node.ex:376` | `class="sb-node__summary"` |
| `block_node.ex:389`, `:397` | `class="sb-node__expand"`, the word `steps` |
| `block_node.ex:402` | `class="sb-node__save-step"` |
| `block_node.ex:415` | `class="sb-node__fold"` |
| `block_node.ex:432` | `class="sb-node__remove"` |
| `block_node.ex:469`, `:654` | `face_findings/1`, its call and its head |
| `block_type.ex:1365` | `@presentation_cap 24` |
| `block_type.ex:1752-1768` | the summary-refusal messages |
| `view_model.ex:1717` | `defp summary_findings(block_id, module, config, labels)` |
| `edit/targets.ex:194`, `:200` | `accepted_types/4`, its `@spec` and its head |
| `assignability.ex:586` | `def check/5` |
| `slot.ex:245` | the `read_only` attr doc, "draws the gaps without their '+' buttons" |
| `slot.ex:411`, `:428` | `defp gap(assigns)`, the `:if={not @read_only}` on `.sb-gap__add` |
| `shell.ex:191` | `@drawer_tabs` |
| `drawer.ex:36` | "The Source listing is the sixth" |
| `config_form.ex:50` | `attr(:target, :any, required: true)` |
| `config_form.ex:220` | `def config_form(assigns)`, the editing head |
| `config_form.ex:229-230` | `phx-change="config-change"`, `phx-submit="config-change"` |
| `config_form.ex:239` | the hidden `block-id` input |

The cites into this file - `:2480`, `:2489`, `:3068`, `:5776`, `:7303`,
`:7471`, `:7473`, `:7476`, `:7852`, `:8023`, `:8069`, `:8601`,
`:8612`, `:9642`, `:10052`, `:10097`, `:10304` - resolve unchanged; appends land
at the end of this file, so no line above moved. The cites into `ADR-0002` are
written in full wherever they appear above -
`docs/adr/0002-block-type-behaviour.md` at `:831`, `:846-847`, `:5976-5981`
and `:8274` - so that a bare `:` cite in this file always means a line in
this file.

Filed with `sb-0xdu`, campaign SF039.

## Note (2026-09-08): the cite-tidy pass - `16E`'s citation of an epic ruling stands as quoted content, item 5's two code cites re-counted at `6d54afe`, and `11n`'s attribution to `ADR-0003` decision 8 verified

A dated Note rather than an amendment: no decision, no clause and no
heading of this record changes. It is the cite-tidy pass campaign SF039
runs once, last on this repository's lane. Every `lib/` line below was read
at `main` `6d54afe`, beside the anchor it is matched by, which is the
practice `docs/adr/README.md` now states once for every record here.

### 1. `16E` cites the epic ruling by its quoted content, and that is enough

`### `16E`` names the ruling it turns on as "epic ruling `R5`" followed by
the ruling's own words - "a saved composite lives in the host's own table;
the package never persists" (`:9657-9659`) - and the not-decided list
repeats the reference as "epic `R5`, quoted under `16E`" (`:10048-10049`).
This file's other `R`-labels are **campaign**-qualified: "campaign-021
rulings R2 and R3" (`:3452`, `:3589`).

The two forms are not in competition, and `16E`'s is correct as it stands.
A campaign-qualified label resolves against a campaign this repository's
records name elsewhere; an epic's `R`-labels have no campaign to qualify
them by and no record in this repository that enumerates them, so the
quoted content is what makes the reference resolvable to a reader who has
only this file. Where a label is an epic's, quote the ruling; where it is a
campaign's, qualify it. Nothing changes in `16E`.

### 2. Item 5's two code cites, re-counted

The Note of 2026-09-08's item 5 was written before `sb-h5xq` and `sb-x903`
landed, and both of its `lib/` cites moved.

| Cited as | Reads at `6d54afe` |
|---|---|
| `accepted_types/4` at `edit/targets.ex:200`, `@spec` at `:194` | `def accepted_types` at `:227`, `@spec` at `:221`. `sb-h5xq` added `admits_at?/5` at `:300` and `accepted_types_at/5` at `:337` beside it, exactly as the item rules |
| `Assignability.check/5` at `assignability.ex:586` | `def check` at `:657`, `@spec` at `:655` |

Item 5 also cited the Note of 2026-09-07 at `:10097` for where
`accepted_recipes/4` was added. `:10097` is the line naming the
**editor's** private `accepted_recipes/2`, not the promoted arity. The
citation now names that Note by its head (`:10073`) and its `@spec` for the
promoted arity (`:10106-10111`). Both were corrected in place, because a
citation in ordinary prose points at code and at text as they are now.

### 3. `11n`'s attribution to `ADR-0003` decision 8 is correct

A reading raised against `:6635-6636` - that the validation-`:error`
standing of `{:type_mismatch, ...}` belongs to `ADR-0011` decision 8 rather
than to `ADR-0003` decision 8 - does not hold, and the sentence is left
exactly as written. `ADR-0003` decision 8 is what gives an assignability
failure its finding and its shape (`0003:268`, and the 2026-08-29
amendment's own context at `0003:554-556`). `ADR-0011` decision 5 says the
same thing in the same words - "with the standing `ADR-0003` decision 8
gave `{:type_mismatch, ...}`" (`0011:305-306`) - and `ADR-0011` decision 8
is about `:shape_not_satisfied` joining that vocabulary, closing with
"`ADR-0003` decision 8's `{:kind_not_admitted, ...}` tuple is unchanged"
(`0011:417`). The attribution is recorded here as verified so the reading
is not re-raised.

Filed with `sb-dxck`, campaign SF039, from `sb-x9xr` and the campaign's own
cite residue. This Note changes no code and flips no status line in this
file.
