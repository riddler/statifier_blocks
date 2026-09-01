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

**Status: proposed (2026-08-31), drafted for `sb-5h6q` under the operator campaign-024 grant and its direction-agent gate.** Additive; decisions 10 and
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
