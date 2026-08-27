# sb-7f2: the LiveView editor shell

Bead: `sb-7f2` - Implement the LiveView editor shell (ADR-0005 d6-d8, d10-d14)
Stacked on: `sb-ia5` (the pure half - `Edit`, `Edit.History`, `Edit.Targets`,
`Finding`, `ViewModel`)
Record: `docs/adr/0005-liveview-editor.md`, accepted 2026-08-26

## What this bead ships

The rendered half of ADR-0005. `sb-ia5` left a pure command algebra and a view
model that already carries, per block, its declared slots, its form fields, its
presentation metadata and its findings routed to the position that renders
them. This bead is the translation layer above that and nothing more: the
components emit markup from a view model, and the one stateful module turns
`phx-` events into commands the algebra already knows how to apply.

Decisions covered: d6 (one round-trip per drag, validity as markup), d7 (one
JavaScript hook), d8 (every drop target reachable without dragging), d10
(palette panel from `palette_entry/0`), d11 (findings render at their anchors),
d12 (unresolvable blocks render and never lose data), d13 (the component tree
and the pure/rendered boundary), d14 (`sb-` classes, `--sb-*` properties,
per-component class override).

## The dependency shape, and the job that proves it

d1 is the packaging decision the scaffold deferred to the record:

```elixir
{:phoenix_live_view, "~> 1.0", optional: true}
```

`optional: true` alone is not enough, because Elixir compiles every module in a
package whether or not it is reachable. Every module under
`StatifierBlocks.Editor.*` is therefore wrapped in
`if Code.ensure_loaded?(Phoenix.LiveView) do ... end`, and no module outside
that namespace names Phoenix at all.

A guard nothing exercises without the dependency is a guard that is already
broken, so the acceptance property is mechanical and gets its own CI job. The
mechanism: `STATIFIER_BLOCKS_HEADLESS=1` makes `mix.exs` drop
`phoenix_live_view` from `deps/0` and redirect `deps_path`, `build_path` and
`lockfile` to headless-only siblings, so resolving a Phoenix-free tree can
never disturb the ordinary one - in particular it can never rewrite `mix.lock`.
In that tree the package must compile clean with warnings as errors and the
non-LiveView suite must pass.

Test files that name `Phoenix.LiveViewTest` carry the same guard, and every
test that needs the shell is tagged `:liveview` so the headless run excludes
it. `StatifierBlocks.HeadlessTest` asserts the two halves of the property from
inside the suite: with the flag set, `Phoenix.LiveView` is genuinely absent and
`StatifierBlocks.Editor` genuinely did not compile; without it, both are
present. A green run in either tree therefore says something.

## Component tree

d13 draws the boundary and this bead does not move it.

Outside the guard (unchanged, `sb-ia5`'s): `Edit`, `Edit.History`,
`Edit.Targets`, `Finding`, `ViewModel`.

Inside `StatifierBlocks.Editor.*`, all guarded:

| Module | Kind | Responsibility |
|---|---|---|
| `Editor` | live component | the only stateful one: document, history, selection, drag session, transient form state |
| `Editor.Canvas` | function | the tree's root and the drag hook's element |
| `Editor.BlockNode` | function, recursive | one block's chrome, dispatching to its slots |
| `Editor.Slot` | function | one named slot: header, children, gaps, "+" buttons |
| `Editor.ConfigForm` | function | the selected block's form, plus `decode/2` |
| `Editor.Field` | function | one field, dispatching on the closed type set |
| `Editor.PaletteBrowser` | function | grouped, searchable, filterable palette |
| `Editor.Findings` | function | the document-level findings panel |

Recursion is uniform: `BlockNode` renders slots via `Slot`, `Slot` renders
children via `BlockNode`. There is no `Group` component and no `Parallel`
component, and d13 says there must never be one - `layout` and `slot_style`
from `palette_entry/0` are the only things that differ.

## The drag, precisely (d6, d7)

- `dragstart` pushes one event. The server calls
  `Edit.Targets.droppable_slots/3` once, stores the result in the drag session,
  and re-renders - so every accepting slot is stamped `data-drop="ok"` and
  every other `data-drop="no"` before the pointer has moved.
- Hover highlighting is CSS on those attributes. Zero round-trips per hover.
- `drop` pushes `{block_id, parent_id, slot, index}`; the server builds a
  `:move` (or, from the palette, an `:insert`), applies it through
  `Edit.History.commit/4`, and re-renders.
- `dragend` clears the session.

The hook is `StatifierBlocksDrag`, attached to the canvas root, and it is the
whole client-side surface. It reads `data-block-id`, `data-slot` and
`data-index` off the DOM and calls `pushEventTo`. It never moves a node itself:
the server re-renders after every command, and a hook that patched the tree
would be fighting LiveView for ownership of the same elements.

**Adding a second hook requires amending ADR-0005.** That friction is made
mechanical rather than left to reviewer memory:
`StatifierBlocks.AssetsTest` reads `assets/js/statifier_blocks.js`, counts the
exported hook objects, and fails with a message naming d7 if there is more than
one. It runs in the headless tree too, because it reads a file and needs no
LiveView.

## The keyboard path (d8)

Every gap in a droppable slot carries a "+" button. Activating it opens the
palette filtered by the *same* predicate the drag uses -
`Edit.Targets.droppable_slots_for/3` against a probe block of the candidate
type - and choosing an entry emits an `:insert` at that exact position. There
is no parallel implementation of validity, which is what makes the whole
insertion path exercisable in `LiveViewTest` without simulating a drag.

## Theming (d14)

One structural stylesheet, `assets/css/statifier_blocks.css`. Every class the
package emits is prefixed `sb-`; every color, spacing, radius and drag
treatment is a `--sb-*` custom property with a default, set on the canvas root;
every top-level component takes a `class` attr appended to its own. A `theme`
assign on `Editor` is rendered as inline custom properties on the canvas root,
which is how a host overrides without a stylesheet at all.

Held mechanically: `theming_test.exs` scans the rendered markup and asserts
every class token in it starts with `sb-`, so a stray framework class fails the
gate rather than a review.

## Out of scope, recorded rather than done

- **The `Compiler.Finding` -> `StatifierBlocks.Finding` adapter.** `sb-ia5`
  suggested this bead as its home because a compile result is in hand here. It
  is not: this bead's decisions are d6-d8 and d10-d14, none of which wires a
  compile result into the editor, and d15 explicitly defers the SCXML/preview
  pane that would be the natural caller. `ViewModel.build/3` already takes
  caller-supplied findings, so the adapter is additive whenever its bead is
  filed. Reported, not built.
- **Duplicate as a gesture.** d2 names it as an `:insert` of a re-minted
  subtree, but no decision in this bead's range requires the affordance. d12
  requires select, move and delete for an unresolvable block, and those ship.
- **Anything built on `sb-ort`'s two package-reserved interrupt event names.**
  Queued for operator review; not built on.
- **Rich expression editing.** d9 ships a plain source input and an override
  seam; the seam is an assign here, and sui-bob owns what fills it.
- **Re-skinning existing examples.** `sb-xln` owns that sweep. New examples in
  this bead use a signup wizard with A/B testing, or card processing.

## Phases

1. Dependency shape and the headless proof: `mix.exs`, `.gitignore`, the CI
   job, `HeadlessTest`, `AssetsTest`, the hook, the stylesheet.
2. The rendered components: `Canvas`, `BlockNode`, `Slot`, `Field`,
   `ConfigForm`, `PaletteBrowser`, `Findings`.
3. The stateful shell: `Editor`, its event translation, and the
   `LiveViewTest` harness.
4. The acceptance tests: drag round-trip, keyboard path, findings at anchors,
   unresolvable preservation, theming.

Each phase leaves the full gate green on its own.
