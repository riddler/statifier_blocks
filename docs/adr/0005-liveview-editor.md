# ADR-0005: The editor is a pure command algebra and view model with a thin LiveView shell

Status: accepted (2026-08-26); decision 5 and the worked example amended (2026-08-27, operator rulings); decision 12 amended (2026-08-28, operator ruling); decisions 10 (slot_style :failure) and 11 (:info) amended (2026-08-29, accepted under the operator campaign-014 direction-agent gate grant); decision 10 slot_outcome_key amended (2026-08-29, same gate, PR 78); decision 14 amended in part - 14a to 14e accepted, 14f proposed (2026-08-29, same gate, PR 85)

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
in decision 12 so nobody re-litigates them.

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
Decision 12 records that as a deferral, and the field renderer is written to
accept a host-supplied override component for exactly this reason.

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
was not allowed to do. `spike/dev/theme-audit.html` checks the rule and the
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

## Proposed amendment (2026-08-28): decisions 10 and 13, rendering the tree and its connectors

**Status: PROPOSED, not accepted.** Additive; decisions 10 and 13 stand as
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

### Proposed decision

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
This is decision 3's total-resolution posture arriving at presentation, the
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
