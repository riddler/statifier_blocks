# ADR-0018: The Map is a reader of the view model - a drawn projection beside a host's list, elkjs vendored whole, draw-only hooks, and one struct in

Status: proposed (2026-09-28, drafted for `sb-7v78` under the operator's
campaign consent; the rulings it records were taken by the operator on
2026-09-28). It merges at proposed; flipping it to accepted is a separate
request through the same `docs/adr/` gate, after the code that builds it
has shipped in a published version.

This record decides; the code lands beside it, in the requests that build
`StatifierBlocks.Map`, `StatifierBlocks.Map.Info`, the two function
components and the `StatifierBlocksMap` hook. `StatifierBlocks.Map`
landed on `main` at `8d16951`, while this record was in review; the
others follow it.

Code cites into this repository were read at `ff04855`, except the cite
into `lib/statifier_blocks/map.ex`, read at `8d16951`; each carries its
anchor, so re-locate by anchor, not by number. Cites into the reference host
(`statifier_examples`) were read at its commit `c620756` and name that
repository's files as the host's, never as this package's.

## Context

**A host already draws this document as a map, from this package's
structs.** The reference host's Plan view draws the block document twice
side by side: an indented list, one row per block, and a map of boxes in
boxes laid out by elkjs in the browser and drawn as plain SVG, with a
description region above that says what the selected or hovered element
is. Every fact the map shows comes from a package surface. The boxes and
their order come from `StatifierBlocks.ViewModel` (`outline/1`,
`flow_children/1`, `body_slots/1`, `arrangement/1`, all in
`lib/statifier_blocks/view_model.ex`). The end marks, the interrupt edges
and the timer edges are the ones `StatifierBlocks.Describe.outline/3`
answers (`lib/statifier_blocks/describe.ex:175`, `def outline`): the host's
graph module re-derives them off the view model, and a test beside it
holds them equal to the outline's for every fixture (statifier_examples
`lib/statifier_examples_web/plan_map.ex`, its moduledoc's "The end" and
"Timer edges"). The description region reads the outline and a type's
paragraph from `BlockType.explain/1`
(`lib/statifier_blocks/block_type.ex:1807`, `def explain`). The host's
graph module says of itself that the graph "is derived from the view model
on every change and is never stored" (its moduledoc's "A projection, never
a second model"). What the host wrote is a reader, not a model, and a
second host that wants the same map copies the host's graph module, its
description module, its two hooks and the vendored layout library.

**The operator ruled on 2026-09-28 that the Map moves into the package**:
one record, four decisions - the Map is a reader of the view model and
never an editor layout mode; elkjs is vendored with its licence and
checksum and its cost stated; the hook rule is amended so that draw-only
hooks are unlimited; the Map takes the editor's view model and the host's
selection as input and draws findings from the same struct. The
description region moves with the Map; the package editor gets the same
region later. The chart view is out.

**Four standing answers bound what the move may do.**

- ADR-0005 records the operator's ruling that "components promote and
  layouts do not" (`docs/adr/0005-liveview-editor.md:8023`, the
  2026-09-07 Amendment's "The first consumer"), and states of the view
  model's list walk that "this section adds no layout mode to the package
  editor" (`docs/adr/0005-liveview-editor.md:8029`, the same section). A
  map is exactly the kind of thing that could arrive as a mode of the
  editor.
- ADR-0005 decision 7, as amended on 2026-08-29, ships two hooks and says
  "A third hook still requires amending this record, and a hook that
  pushes anything but geometry or a command is still a thing this record
  does not have" (`docs/adr/0005-liveview-editor.md:2249`, that Amendment's
  Consequences). The Map's hook is a third.
- ADR-0005 decision 1 keeps this repository's toolchain Node-free
  (`docs/adr/0005-liveview-editor.md:129`) and lets no module outside
  `StatifierBlocks.Editor.*` name Phoenix
  (`docs/adr/0005-liveview-editor.md:111`, the quoted rule).
- ADR-0001 fixes a block's fields as `{type, id, config, slots}`
  (`docs/adr/0001-block-document-schema.md:63`, decision 2; its Amendment
  of 2026-09-28, at proposed, adds an optional author-written note), none
  of them a coordinate, and a position as a path that is "never stored"
  (`docs/adr/0001-block-document-schema.md:131-133`, decision 5); ADR-0005's
  `10a` keeps connectors "rendered, never authored"
  (`docs/adr/0005-liveview-editor.md:1061`). A drawn map is the natural
  place to propose storing a box's position or authoring an edge.

**What the describe already is not.** ADR-0016 decision 5 says the
describe is "Not a layout. No coordinate, size, colour or drawing rule is
answered, and no renderer of the outline ships with it"
(`docs/adr/0016-document-describes-itself.md:229`). That stays true: the
Map is a renderer beside the describe, not a change to it.

## Decision

### (a) `StatifierBlocks.Map` is a pure reader of `ViewModel`, held equal to `Describe` by test, never an editor layout mode

`StatifierBlocks.Map` is a new public module answering the graph a layout
hook lays out: one node per block, one per slot that is drawn as a box of
its own, one marker per empty slot, and the edges between them. It is
built from a `%StatifierBlocks.ViewModel{}` and the host's options - its
selection, and its words for event names - and from nothing else: it does
not call `StatifierBlocks.Describe` (`lib/statifier_blocks/map.ex:375`,
`def graph`, takes the view model and a keyword list). The end marks, the
interrupt edges and the timer edges it draws are derived from the view
model, as the reference host's graph module derives them, and its tests
hold them equal to the edges `Describe.outline/3` answers for every
fixture. It computes no position: every coordinate on the map is answered
by the layout library in the browser, lives only in the SVG it was drawn
into, and is laid out again on the next change.

**The layout-mode prohibition stands, and the Map is not a mode.** The
Map is not a mode, pane, tab, toggle or second canvas of
`StatifierBlocks.Editor`, and this record changes nothing the editor
draws. It is a reader of the same struct the editor renders, which a host
mounts where it chooses - beside its own list, as the reference host
does. A view that reads the same struct is not a layout of the editor, so
the operator's "components promote and layouts do not" is kept rather than
excepted: what promotes is a component.

**Decision 10b is the editor canvas's rule and is untouched.** `10b`'s
"Nothing in the renderer computes a coordinate" governs the editor's
canvas, where the browser lays out nested DOM and the connector layer
measures it. The Map is not that renderer; its boxes are placed by the
layout library in the browser from a graph the server built, and no
position it places ever reaches the server.

**Nothing the Map draws is stored or authored.** No coordinate, size or
edge reaches the document or any table; a block keeps ADR-0001 decision
2's fields and its position stays decision 5's path. Every edge on the
map is read from the view model - either one the describe also answers,
or a structural one (a slot's blocks in `flow_children/1` order) - and
no gesture on the map creates or deletes one: `10a` holds for the map as
it holds for the canvas.

**The extraction moves code; it does not redesign it.** What the reference
host's map draws at its commit `c620756` is what `StatifierBlocks.Map`
draws, test for test. A change to what is drawn is a later request's,
not part of the move.

`StatifierBlocks.Map` names no Phoenix module, so it sits outside decision
1's guarded namespace and compiles, with its tests, when
`phoenix_live_view` is absent.

### (b) elkjs 0.9.3 is vendored whole, with its licence and a checksum, and its cost is stated

The layout library is [elkjs](https://github.com/kieler/elkjs) 0.9.3. It is
vendored as `assets/vendor/elk.bundled.js`, byte-identical to
`lib/elk.bundled.js` in the elkjs 0.9.3 npm tarball (SHA-256
`b0745abd7f23cd91690a1587e377edbe19fd7233c783300290936720546216d4`).

- **Its licence ships beside it.** elkjs is under the Eclipse Public
  License 2.0; its licence text is vendored beside the file as
  `assets/vendor/elkjs-LICENSE.md`. The package's own licence stays MIT
  (`mix.exs:111`, `licenses:`); how the package metadata names the
  vendored file's licence is the release preparation's to write.
- **A checksum pins it.** The file gets one line in the package's
  vendored-file manifest, `.claude/firewall-vendor.txt`, in the shape the
  reference host already uses: the path, `sha256=` its digest,
  `upstream=elkjs@0.9.3`, and `licence=` the licence file's path. The
  pre-push terminology scan skips the line scans of a listed file whose
  bytes match, still scans its name, and an edit to the file ends the
  exemption.
- **It ships in the hex package.** `package()`'s `files:` lists `assets`
  whole (`mix.exs:123-124`, `files:`), so the vendored file and its licence
  reach a host with the hook that imports them. The hook imports the file
  by relative path; it is not an npm dependency of the package or of the
  host.
- **Its cost is stated, and it is loaded whole.** The file is 1,606,238
  bytes as shipped and 466,990 bytes gzipped as the reference host measured
  it (the gzipped figure moves by a few kilobytes with the compressor's
  level). It is the bundled build, one file carrying ELK and its own worker
  shim, and a bundler cannot shake any of it out: a host bundle that
  includes the Map hook includes all of it. The README that shows a host how
  to mount the Map says so, and says which import pulls it in.

A later elkjs version is a new vendored file with a new checksum line, in
a request of its own.

### (c) ADR-0005 decision 7 is amended: one hook pushes commands; any number of hooks may only measure or draw

The hook rule is amended in ADR-0005 itself, by its Amendment of
2026-09-28 on decision 7, which carries the rule and what a draw-only hook
may and may not do. What it means for the Map:

- **`StatifierBlocksMap`, at `assets/js/statifier_blocks_map.js`, is the
  first draw-only hook.** It lays out the graph `StatifierBlocks.Map`
  answered, draws it as SVG into an element the server keeps out of
  LiveView's patching, and marks the box of the block the host named as
  selected without laying the graph out again.
- **It pushes no command of its own.** A click on a box, a gap or an empty
  slot's marker is sent as the host list's own event - the event name the
  host passed in, with the payload the list sends for the same gesture:
  selecting a block, or opening the insert at that position. The reference
  host's hook does exactly this through one `pushEvent`, choosing the
  event from the stamp on what was clicked (statifier_examples
  `assets/js/plan_map.mjs`, `export function mapGesture`). The server
  cannot tell a gesture from the map from the same gesture on the list,
  and every change to the document is still one of decision 2's four
  commands, built by the host from its list's own event.
- **Hover swaps text client-side.** Pointing at a drawn element puts that
  element's description, computed by the server and rendered into the
  page, into the description region, and pointing away puts back what the
  region said; it pushes nothing and changes no selection. That code runs
  in the Map hook, which keeps it draw-only.

### (d) The Map takes the editor's view model and the host's selection as input, and draws findings from the same struct

**One struct in.** The Map's only inputs are the `%ViewModel{}` that
`ViewModel.build/3` answered for the document
(`lib/statifier_blocks/view_model.ex:519`, `def build`) - the same struct
an editor renders, findings included - and the host's selection, a block
id or none, beside the host's words for event names. There is no second
state: the Map keeps nothing between renders. It reads no document or
palette of its own: every box and edge is read off the view model's nodes
and slots (`ViewModel.outline/1` for the timer edges). Its end, interrupt
and timer edges are the ones `Describe.outline/3` answers, and that is
held by test rather than by calling the describe: the code moves as the
reference host wrote it.

**Findings come from that struct.** A block's findings are the ones its
`ViewModel.Node` carries (the `findings` field of
`StatifierBlocks.ViewModel.Node`), and the description region lists them;
the Map runs no validation and derives no finding.

**Selection marks and does nothing else.** The selection marks the one
block node it names and changes nothing else in the graph, so a host whose
selection moves hands the hook the same boxes; it also changes what the
description region shows.

**The description region is part of the Map's surface.**

- `StatifierBlocks.Map.Info` is a new public module answering the
  structured description of every element the map draws - a block, an
  arm, a rule, an edge, an empty marker - and of the idle state when
  nothing is selected, from the same view model and outline and the
  palette's `explain/1`. Where a block carries the author-written note
  ADR-0001's Amendment of 2026-09-28 proposes, the region shows it above
  the built-in text, as that Amendment's clause `2g` says.
- Two function components render the map region and the description
  region. The map region is `aria-hidden`; the description region is
  `aria-live="polite"` and is rendered on the server with the selected or
  idle content. The host's list stays the keyboard and screen-reader path
  to every gesture, and that is proven in LiveView tests, not claimed
  from a browser. Because the components name Phoenix, they sit inside
  decision 1's guarded `StatifierBlocks.Editor.*` namespace; that is where
  the compile guard lives, not a sign that they are part of the editor,
  and their module names are the building request's.
- The package editor gets the same region later, in a request of its own;
  this record does not put it there.

**The chart view is out.** A view that draws the compiled control flow -
the chart the compiler emits, rather than the block document - is not
decided here and is named as a later record's question. ADR-0016 decision
5 already keeps the describe from reading a chart, and the Map, which
reads the view model alone, reads no chart either.

### What this record does not decide

- The chart view (above).
- The editor's own description region, and the editor's field for
  writing a note.
- Any change to decision 2's four commands; the Map adds no command.
- Hand-placed positions, a density mode, or any stored layout.
- Any merge with statifier-ui's viewer renderer (sui-ADR-0008), which also
  lays out with elkjs; the two stay separate.
- Any change to a host's list or to the gestures it offers.

## Consequences

- **The package gains a drawn surface a host opts into.** Two pure public
  modules, two function components, a third hook and a vendored file with
  its licence and a manifest line. A host that mounts none of them gets
  the package it had: nothing this record adds changes what an existing
  function answers, and the headless build job still compiles and tests the package with
  `phoenix_live_view` absent.
- **The repository's tests run Node.** The Map hook's layout tests run the
  hook through the real elkjs outside the browser, so the gate needs
  `node` on the path and CI installs it. ADR-0005's Amendment of 2026-09-28
  on decision 1 records what that changes and what it does not: the
  package still bundles nothing, and a host needs no Node for it.
- **The hook-count test changes shape.** It asserts one hook that pushes
  commands and any number that only measure or draw, and it still fails on
  a hook that pushes a second command set.
- **The describe is unchanged.** ADR-0016 and ADR-0017 stand as written.
  The Map draws the edges the describe answers - a timer edge ADR-0017
  decision 3 answers is one the Map draws - and a test, not a call, keeps
  the two equal: a change to the describe's edges that the Map does not
  follow turns that test red.
- **The reference host stops carrying its copies** once a published
  version of this package carries the Map; that is the host's own work.
- **The bundle cost is visible to a host before it pays it**, in the
  README section that shows how to mount the Map.

## Note (2026-09-28): statifier-ui's elkjs renderer is decided, not built

A dated note, not an amendment: it changes no decision in this record.

The section "What this record does not decide" above names statifier-ui's
viewer renderer as one "which also lays out with elkjs", and spells its cite
in a shape that reads like a tracker id. That sentence stays as written; this
Note says what it refers to.

The record it means is statifier-ui's (the `statifier_ui` package) ADR-0008,
"Client-side elkjs layout rendering plain SVG", at
`docs/adr/0008-client-side-elkjs-layout.md` in that repository, which is
accepted. It decides an elkjs renderer for statifier-ui's diagram; that
renderer is not yet built. The diagram statifier-ui ships today is Mermaid
source: its `StatifierUI.Live` moduledoc, in the section "The diagram is
Mermaid source, and no Mermaid client ships", says so and names ADR-0008's
renderer as not built yet, and `StatifierUI.Diagram` renders Mermaid
`stateDiagram-v2` source. Both were read at statifier-ui's commit `e3141f4`.

The point the sentence makes is unchanged: the Map and that renderer stay
separate, and no merge of the two is decided here.

Filed with `sb-ew7o`.
