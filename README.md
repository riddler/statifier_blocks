# StatifierBlocks

[![CI](https://github.com/riddler/statifier_blocks/actions/workflows/ci.yml/badge.svg)](https://github.com/riddler/statifier_blocks/actions/workflows/ci.yml)
[![Hex.pm Version](https://img.shields.io/hexpm/v/statifier_blocks.svg)](https://hex.pm/packages/statifier_blocks)
[![Hex Downloads](https://img.shields.io/hexpm/dt/statifier_blocks.svg)](https://hex.pm/packages/statifier_blocks)
[![Hex Docs](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/statifier_blocks/)
[![License](https://img.shields.io/hexpm/l/statifier_blocks.svg)](https://github.com/riddler/statifier_blocks/blob/main/LICENSE)

> **Pre-1.0.** Until `statifier_blocks` reaches v1.0, its public surface may change
> between minor releases, sometimes drastically: a release may rename modules,
> callbacks, table columns, telemetry events or error vocabulary with no
> compatibility shim. Every such change is recorded in
> [CHANGELOG.md](CHANGELOG.md) under a bold **Breaking** heading that says what
> to do about it. Pinning to an exact minor - `~> X.Y.0` - is the recommended way
> to consume the package until 1.0.

Block document model, one-way SCXML compiler, and LiveView editor components
for composing [Statifier](https://github.com/riddler/statifier-ex) statecharts
from typed blocks.

Statecharts are the right execution model for long-running workflows, and
SCXML is the right interchange format for them - but neither is something a
non-engineer will author by hand. This package is the authoring layer:

- **A block document model.** The authoring artifact is a document: a tree of
  typed blocks that a person composes, each block a unit with a declared
  shape rather than free-form XML. The document, not the chart, is the source
  of truth that gets edited and stored, one revision per saved edit. The
  four nouns this README uses - document, revision, chart, execution - have
  one job each; [Documents, revisions, charts and
  executions](docs/explanation/documents-revisions-charts-and-executions.md)
  says which.

- **A one-way SCXML compiler.** The compiler turns a block document into an
  SCXML chart that Statifier can run, and carries a provenance map so a
  runtime position in the chart can be pointed back at the block that
  produced it. The direction is deliberate: documents compile to charts, and
  nothing decompiles a chart back into blocks.

- **LiveView editor components.** The components a host embeds to let people
  compose, rearrange, and validate a block document in a browser - the
  editing surface over the model above, sharing the family's rendering and
  fixtures conventions with
  [statifier_ui](https://github.com/riddler/statifier-ui).

Blocks are typed and host-pluggable: a host registers the block types its own
domain needs, and the compiler and editor work off that registry rather than
off a closed built-in vocabulary.

## Installation

```elixir
def deps do
  [
    {:statifier_blocks, "~> 0.44.0"}
  ]
end
```

Two dependencies are **optional** and neither is added for you:
`phoenix_live_view`, without which no editor module compiles at all, and
`statifier_ui`, which an `:expression` field uses for its expression editor
when it resolves. See [How to embed the editor in a LiveView host](docs/guides/embed-the-editor.md).

Moving a host up from 0.31, one minor at a time:
[`docs/upgrading.md`](https://github.com/riddler/statifier_blocks/blob/main/docs/upgrading.md)
says what the host changes at each release, and names the calls a publish
step makes.

A document written against 0.27 still compiles. To have a composite in it say
how it finished - declared `outcomes`, a handler's `finish_as` and the
`on_<name>` slots an author fills - see
[`docs/guides/migrating-documents-0.27-to-0.34.md`](https://github.com/riddler/statifier_blocks/blob/main/docs/guides/migrating-documents-0.27-to-0.34.md).

Shapes a workflow commonly needs, built from the core block types - starting
with a step that must finish within a bound or the flow continues - are in
[`docs/guides/flow-patterns.md`](https://github.com/riddler/statifier_blocks/blob/main/docs/guides/flow-patterns.md).

## Documentation

- Do
  - [How to build a block document and compile it to a chart](docs/guides/build-and-compile.md) -
    write two block types, compose a document, compile it and point a running
    position back at its blocks
  - [How to register your own block types](docs/guides/register-block-types.md) -
    write a block type, declare one from a base or a subtree, and build a
    palette from your own types beside the core vocabulary
  - [How to type a palette](docs/typing-a-palette.md) - declare what each
    block type reads and writes at a datamodel path, and check a document
    against the records and shapes your host declares
  - [How to publish a document](docs/guides/publish-a-document.md) - call
    the checks a publish step runs, in order, and decide on each finding
    by its severity
  - [How to validate a document against the schema from any language](docs/guides/validate-a-document-against-the-schema.md) -
    hand the JSON Schema to a service in another language, check a stored
    document against it, and ask for a stricter schema built from your palette
  - [How to describe a document in words](docs/describing-a-document.md) -
    outline a document, write the outline as lines of English and reword them
    in your own voice
  - [How to embed the editor in a LiveView host](docs/guides/embed-the-editor.md) -
    register the hooks, import the stylesheet, render the editor component and
    connect selection, icons, findings and saved steps
- Look up
  - [Config fields and the handlers this package ships](docs/reference/config-fields-and-handlers.md) -
    where a config field's value is stored, and the invoke handler the package
    ships for `core.subchart`
  - [Editor assigns and host seams](docs/reference/editor-assigns-and-host-seams.md) -
    what the mounted editor holds, every seam a host declares, and the limits
    the canvas draws within
- Understand
  - [Documents, revisions, charts and executions, and why blocks compile to a chart](docs/explanation/documents-revisions-charts-and-executions.md) -
    what a document, a revision, a chart and an execution each are, how a
    compile joins a revision to its chart, and why the compile runs one way

## Mounting the Map

The Map draws a block document as boxes in boxes: every step, what holds
it, the arrows between them, where the document starts and where it
finishes. It is a reader of the same view model the editor renders, and a
page mounts it beside a list of the document's steps. It is not a mode of
the editor, and the editor draws no map (ADR-0018). The editor does draw
the description region described below, under its canvas, from its own
document and selection: the selected block's description, its note first,
or the document's when nothing is selected, with no paragraph on how to
read a map, since there is none beside it.

Three pieces make it. `StatifierBlocks.Map.graph/2` builds the graph from
the view model, `StatifierBlocks.Map.Info` describes every element the map
draws in words, and two function components in
`StatifierBlocks.Editor.MapRegions` render them into the page:
`map_region/1`, where the `StatifierBlocksMap` hook lays the graph out and
draws it, and `description_region/1`, which says what the selected block is,
or what the document is when nothing is selected. Pointing at anything the
map draws shows its description in that region, in the browser, and pointing
away puts back what it said.

### What the host brings

The components keep no state. A host brings four things, and each stays its
own:

1. **The view model.** `StatifierBlocks.ViewModel.build/3` of the document.
   Both regions read it; the description region also takes the document and
   the palette it was built from.
2. **The selection.** The block id the host's list has selected, or `nil`.
   The map marks that block's box and the description region describes it.
   Selecting a block is the host's to do, in its own event handler.
3. **The list's event names.** The names the host's list already sends to
   select a block and to open an insert. A click on a box, on the gap after
   a block or on an empty slot's marker is sent under those names with the
   payload the list sends for the same gesture (`"block-id"`, and `"slot"`
   for an empty slot), so the server cannot tell a gesture on the map from
   the same gesture on the list. The map has no event of its own.
4. **The list.** The map region is hidden from assistive technology
   (`aria-hidden="true"`) and nothing in it takes focus, so the list is the
   keyboard and screen-reader path to every step. Its rows point at the
   description region with `aria-describedby`, and the region is
   `aria-live="polite"`, so a selection made in the list is read out.

```heex
<StatifierBlocks.Editor.MapRegions.map_region
  id="plan-map"
  view_model={@view_model}
  selected={@selected_id}
  select_event="select-row"
  insert_event="insert-open"
  editable={true}
  description="plan-description"
/>

<StatifierBlocks.Editor.MapRegions.description_region
  id="plan-description"
  document={@document}
  view_model={@view_model}
  palette={@palette}
  selected={@selected_id}
/>

<ol>
  <li :for={{node, _depth, _kind} <- ViewModel.outline(@view_model)}>
    <button
      type="button"
      phx-click="select-row"
      phx-value-block-id={node.block_id}
      aria-describedby="plan-description"
    >
      {ViewModel.sentence(node)}
    </button>
  </li>
</ol>
```

`description` on the map region names the description region's id, which
is what gives the map its hover; a map without it draws and selects, and
shows no description under the pointer. Both components take `phrase`, the
host's words for its event names, as `StatifierBlocks.Map.graph/2` takes
it; pass the same function to both so the region says what the box says.
`insert_reveal` takes a selector for the element to scroll into view after
an insert armed from the map, since what the list opens may sit below it.
`map` on the description region says whether a map is mounted beside it,
and a host with a map leaves it at its default, `true`; `false` is how the
editor draws the region under its canvas: no hover layer, no store, and no
paragraph on how to read the map, nor the map's key, in the document's
description. `label`
on the description region is its accessible name, the `aria-label` of the
live region, `"Description"` by default; a host passes its own words.

### The hook, and what it costs

The Map hook is not in the package's default export. It has its own entry
point, `statifier_blocks/map`, because it imports the vendored elkjs build
that lays the graph out, and a host that never mounts the Map should never
bundle it. Register it beside the editor's hooks:

```javascript
import StatifierBlocks from "statifier_blocks";
import { StatifierBlocksMap } from "statifier_blocks/map";

let liveSocket = new LiveSocket("/live", Socket, {
  hooks: { ...StatifierBlocks, StatifierBlocksMap },
});
```

On the `NODE_PATH` route the specifier is
`statifier_blocks/assets/js/statifier_blocks_map.js`.

The hook draws into a child of its element marked `data-map-canvas`, which
`map_region/1` renders with `phx-update="ignore"` so that LiveView leaves
the drawing alone. A host that attaches the hook to its own element gives
it that child. An element without one is not supported: the hook draws into
the element itself, which LiveView patches, so a patch can take the drawing
away, and it warns once per mount in the browser console, naming the
missing child.

That import pulls in `assets/vendor/elk.bundled.js`, elkjs 0.9.3 under the
Eclipse Public License 2.0 (its licence ships beside it), and pulls it in
whole: 1,606,238 bytes as shipped and 466,990 bytes gzipped, none of which a
bundler can shake out.

### Theming the Map

On a page of the host's, both regions read the `--sb-*` palette from the
page, since neither sits inside the editor (the description region the
editor draws under its canvas reads the editor's own tokens instead): set
the palette on an ancestor of the regions, or on
`.sb-map__region` and `.sb-map__description-frame` themselves (the frame
holds the description region and its hover layer). The map's drawing
reads the `--sb-map-*` tokens, declared on `.sb-map__region` and mapped onto
the palette, so a page that themes the palette dresses the map too; set one
of them to disagree with that mapping. Set it on `.sb-map__region` itself,
or on a selector that reaches that element: the region declares every
`--sb-map-*` token on itself, so a value set on an ancestor loses to that
declaration. The drawing carries a fallback for each, which is what the map
looks like on a page that sets none.

### Working on the Map in this repository

The package bundles nothing, and a host needs no Node for the Map. This
repository's own tests do: the Map hook's layout tests run the hook through
the vendored elkjs outside the browser, so a contributor needs `node` on the
path to run the full `mix quality` gate (`mise.toml` pins the version CI
uses).

## Design records

The contracts this package is built out of are written down as ADRs in
[`docs/adr/`](https://github.com/riddler/statifier_blocks/tree/main/docs/adr):
the document schema (0001), the block-type behaviour (0002), host-pluggable
assignability (0003), the compiler and its provenance map (0004), and the
editor architecture (0005), and the typed environment a pre-order walk carries
from datamodel path to type (0011). A module's docs cite the decision it
implements;
when the two disagree, the record is the contract and the code is the bug.

## License

MIT - see
[LICENSE](https://github.com/riddler/statifier_blocks/blob/main/LICENSE).

One file is not: `assets/vendor/elk.bundled.js`, elkjs 0.9.3 vendored
unmodified for the Map hook, is under the Eclipse Public License 2.0, and its
licence text ships beside it as `assets/vendor/elkjs-LICENSE.md`.
