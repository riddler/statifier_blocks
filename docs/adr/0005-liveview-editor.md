# ADR-0005: The editor is a pure command algebra and view model with a thin LiveView shell

Status: accepted (2026-08-26)

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

Nothing in that list depends on the index within the slot, which is why
validity is per-slot. That is not a simplification for its own sake: it means
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
existing slots is permitted, since order is a document-level property that
asks the parent's type nothing.

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
`lane_nurture`) out of that lane and into the branch's `otherwise` slot,
dropping it above the notify that is already there.

**At `dragstart`,** the shell pushes one event and the server evaluates:

```elixir
Edit.Targets.droppable_slots(document, palette, "blk_NOT")
#=> [
#     {"blk_ROOT", "body"},
#     {"blk_GRP", "body"},
#     {"blk_GRP", "interrupts"},
#     {"blk_BR", "arm_qualified"},
#     {"blk_BR", "otherwise"},
#     {"blk_PAR", "lane_crm"},
#     {"blk_PAR", "lane_nurture"}
#   ]
```

Seven slots highlight at once, before the pointer has moved. Note what is
absent and why: nothing inside `blk_NOT` itself (rule 4 - it has no children
here, but the rule is what makes dragging a group safe), and `blk_GRP`'s
`interrupts` slot is present only because a `myapp.notify` is assignable
there; had sb-7rx's relation said otherwise, it would be dark. Every one of
those seven is a pure-function assertion in a test file.

**At `drop`,** the client pushes `{"blk_NOT", "blk_BR", "otherwise", 0}` and
the server builds and applies one command:

```elixir
{:ok, document, inverse} =
  Edit.apply(document, {:move, "blk_NOT", {"blk_BR", "otherwise", 0}})

inverse
#=> {:move, "blk_NOT", {"blk_PAR", "lane_nurture", 1}}
```

`lane_nurture` now holds only `blk_WAI`; `otherwise` holds `blk_NOT` then
`blk_NO2`. No id changed - ADR-0001 decision 3 - so the provenance map sb-iwz
will build still keys correctly for every block that did not move.

**Ctrl-Z** applies `inverse` and pushes *its* inverse onto the redo stack. The
document is byte-identical to the one before the drag, which is decision 3's
law, which is a property test.

What this example is chosen to demonstrate:

- **Pre-hover validity as a pure function.** The seven-element list is the
  entire interaction model of a drag, and it is computed by a function that
  takes a document, a palette, and an id, with no browser anywhere near it.
- **Slot granularity (decision 5).** `lane_nurture` appears once, not three
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
