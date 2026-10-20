# How to mount the Map

This guide shows you how to put the Map beside a list of a document's steps
on a page of your own LiveView app: render its two regions, connect the
list's events to them, register the Map hook and theme the result.

The example host is a library's staff app, where a librarian reads the
patron registration document - the screens a visitor goes through to become
a library patron - as a list of steps with the Map beside it.

The Map draws a block document as boxes in boxes: every step, what holds it,
the arrows between them, where the document starts and where it finishes. It
is a reader of the same view model the editor renders, and a page mounts it
beside a list of the document's steps. It is not a mode of the editor, and
the editor draws no map (ADR-0018). The editor does draw the description
region described below, under its canvas, from its own document and
selection: the selected block's description, its note first, or the
document's when nothing is selected, with no paragraph on how to read a map,
since there is none beside it.

Three pieces make it. `StatifierBlocks.Map.graph/2` builds the graph from
the view model, `StatifierBlocks.Map.Info` describes every element the map
draws in words, and two function components in
`StatifierBlocks.Editor.MapRegions` render them into the page:
`map_region/1`, where the `StatifierBlocksMap` hook lays the graph out and
draws it, and `description_region/1`, which says what the selected block is,
or what the document is when nothing is selected. Pointing at anything the
map draws shows its description in that region, in the browser, and pointing
away puts back what it said.

The editor's own page is [How to embed the editor in a LiveView
host](embed-the-editor.md).

## Before you start: what you bring

The components keep no state. You bring four things, and each stays your
own:

1. **The view model.** `StatifierBlocks.ViewModel.build/3` of the document.
   Both regions read it; the description region also takes the document and
   the palette it was built from.
2. **The selection.** The block id your list has selected, or `nil`. The map
   marks that block's box and the description region describes it. Selecting
   a block is yours to do, in your own event handler.
3. **The list's event names.** The names your list already sends to select a
   block and to open an insert. A click on a box, on the gap after a block
   or on an empty slot's marker is sent under those names with the payload
   the list sends for the same gesture (`"block-id"`, and `"slot"` for an
   empty slot), so the server cannot tell a gesture on the map from the same
   gesture on the list. The map has no event of its own.
4. **The list.** The map region is hidden from assistive technology
   (`aria-hidden="true"`) and nothing in it takes focus, so the list is the
   keyboard and screen-reader path to every step. Its rows point at the
   description region with `aria-describedby`, and the region is
   `aria-live="polite"`, so a selection made in the list is read out.

## Render the regions beside the list

Render the map region, the description region and the list in the page's
template:

```heex
<StatifierBlocks.Editor.MapRegions.map_region
  id="registration-map"
  view_model={@view_model}
  selected={@selected_id}
  select_event="select-row"
  insert_event="insert-open"
  editable={true}
  description="registration-description"
/>

<StatifierBlocks.Editor.MapRegions.description_region
  id="registration-description"
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
      aria-describedby="registration-description"
    >
      {ViewModel.sentence(node)}
    </button>
  </li>
</ol>
```

## Choose the options you need

These attributes are optional, and each does one thing:

- `description` on the map region names the description region's id, which
  is what gives the map its hover. A map without it draws and selects, and
  shows no description under the pointer.
- `phrase` on both components is your words for your event names, as
  `StatifierBlocks.Map.graph/2` takes it. Pass the same function to both so
  the region says what the box says.
- `insert_reveal` on the map region takes a selector for the element to
  scroll into view after an insert armed from the map, since what the list
  opens may sit below it.
- `map` on the description region says whether a map is mounted beside it.
  Leave it at its default, `true`, when you mount a map; `false` is how the
  editor draws the region under its canvas: no hover layer, no store, and no
  paragraph on how to read the map, nor the map's key, in the document's
  description.
- `label` on the description region is its accessible name, the `aria-label`
  of the live region, `"Description"` by default. Pass your own words.

## Register the hook, and know what it costs

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

That import pulls in `assets/vendor/elk.bundled.js`, elkjs 0.9.3 under the
Eclipse Public License 2.0 (its licence ships beside it), and pulls it in
whole: 1,606,238 bytes as shipped and 466,990 bytes gzipped, none of which a
bundler can shake out.

## Give the hook its canvas

The hook draws into a child of its element marked `data-map-canvas`, which
`map_region/1` renders with `phx-update="ignore"` so that LiveView leaves the
drawing alone. If you attach the hook to an element of your own, give it
that child. An element without one is not supported: the hook draws into the
element itself, which LiveView patches, so a patch can take the drawing
away, and it warns once per mount in the browser console, naming the missing
child.

## Theme the Map

On a page of yours, both regions read the `--sb-*` palette from the page,
since neither sits inside the editor (the description region the editor
draws under its canvas reads the editor's own tokens instead). Set the
palette on an ancestor of the regions, or on `.sb-map__region` and
`.sb-map__description-frame` themselves (the frame holds the description
region and its hover layer).

The map's drawing reads the `--sb-map-*` tokens, declared on
`.sb-map__region` and mapped onto the palette, so a page that themes the
palette dresses the map too. To make one of them disagree with that mapping,
set it on `.sb-map__region` itself, or on a selector that reaches that
element: the region declares every `--sb-map-*` token on itself, so a value
set on an ancestor loses to that declaration. The drawing carries a fallback
for each, which is what the map looks like on a page that sets none.

[How to theme the editor](../theming.md) carries the rule for the editor's
own tokens and an example of the same override for the Map's.

## If you work on this repository

This section is for contributors to the package, not for a host. The package
bundles nothing, and a host needs no Node for the Map. This repository's own
tests do: the Map hook's layout tests run the hook through the vendored
elkjs outside the browser, so you need `node` on the path to run the full
`mix quality` gate (`mise.toml` pins the version CI uses).
