# How to embed the editor in a LiveView host

This guide shows you how to put the block editor on a page of your own
LiveView app: register its hooks, import its stylesheet, render the
component, and connect the optional pieces a host usually wants.

The example host is a library's staff app, where a librarian edits the
patron registration document - the screens a visitor goes through to become
a library patron - and the app saves each draft.

Every assign, seam and limit this guide mentions is listed in
[Editor assigns and host seams](../reference/editor-assigns-and-host-seams.md).

## Before you start

The editor needs `phoenix_live_view`, which this package declares as an
**optional** dependency and does not add for you. A host that wants the
editor already has LiveView, so it adds nothing to `mix.exs`. Without
`phoenix_live_view` no module under `StatifierBlocks.Editor.*` compiles, so
an app that only compiles documents - a background job, a test suite, a
migration script - compiles no editor code.

## Register the hooks

The package's client-side surface is two hooks, and the default export
carries both, so registering them is one line. How the import specifier
resolves depends on whether your app runs `npm install` at all.

- *If it does*, declare the dependency in `assets/package.json`. Point it at
  the package's `assets/` directory, which is where the `package.json` lives -
  the package ships no manifest at its root, so `file:../deps/statifier_blocks`
  names a directory npm cannot read:

  ```json
  { "dependencies": { "statifier_blocks": "file:../deps/statifier_blocks/assets" } }
  ```

- *If it does not* - the default for an app from the Phoenix generator, which
  has no `assets/package.json` and no npm step - let esbuild resolve it the
  same way it already resolves `phoenix` and `phoenix_live_view`, through
  `NODE_PATH` pointed at `deps`:

  ```elixir
  config :esbuild,
    my_app: [
      args: ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js),
      cd: Path.expand("../assets", __DIR__),
      env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
    ]
  ```

  On this route the specifier is the path into the package rather than the
  bare name, because `NODE_PATH` resolution walks `deps/` as a module
  directory and does not read `assets/package.json`:

  ```javascript
  import StatifierBlocks from "statifier_blocks/assets/js/statifier_blocks.js";
  ```

Then register the hooks. Registration is the same on either route - only the
specifier differs, and the bare name below is the npm one:

```javascript
import StatifierBlocks from "statifier_blocks";

let liveSocket = new LiveSocket("/live", Socket, {
  hooks: { ...StatifierBlocks },
});
```

Register **both**: `StatifierBlocksDrag` turns pointer gestures into commands,
and `StatifierBlocksMeasure` reports the laid-out geometry the server draws the
connectors from - without it nothing measures the browser's boxes, so no
connectors are drawn and the editor renders as stacked rows with no flow lines.
Both are still available as named exports, and a host that wants measurement
alone can import it from `statifier_blocks/measure` on the npm route, or from
`statifier_blocks/assets/js/statifier_blocks_measure.js` on the `NODE_PATH`
one (ADR-0005 decision 7 and its 2026-08-29 amendment, "a second hook that
only measures").

## Import the stylesheet

The stylesheet is structural CSS only - the column layout, the drag
affordances, the finding treatments - with no visual opinion and no
framework:

```css
@import "../../deps/statifier_blocks/assets/css/statifier_blocks.css";
```

## Render the component

Mount `StatifierBlocks.Editor` with the document, the palette it is edited
against, and the function that saves each change:

```heex
<.live_component
  module={StatifierBlocks.Editor}
  id="registration-editor"
  document={@registration}
  palette={@palette}
  on_change={&save_registration_draft/1}
/>
```

Every other assign is optional; the reference lists what each one does.

## Follow the selection in a panel of your own

If a drawer tab, a preview or a detail pane of yours should follow the canvas,
pass `on_select`. It is a one-argument function called with each new
selection: a descriptor `%{id:, type:, label:}`, where `label` is the line the
card draws, or `nil` when nothing is selected, which is your panel's cue to
empty itself. It fires when the selection changes and not otherwise. The
block's config is not in it: you already hold the document you passed in.

If your own surface chooses the block, pass `selected_id` on the update that
carries the choice. The result comes back on `on_select` like any other
selection, and an update that does not carry `selected_id` leaves the author's
selection alone.

## Use statifier_ui for expression fields

An `:expression` config field renders a plain source input unless
[statifier_ui](https://github.com/riddler/statifier-ui) is on your load path.
With it, the field renders that package's expression editor: picklists of
field, operator and value while the source is inside the subset predicator
can round-trip, and a text input over everything else. The document still
stores your author's text.

1. Add the dependency. This package declares it optional,
   `{:statifier_ui, "~> 0.8", optional: true}`, and nothing adds it for you.
2. On the npm route, add a second `file:` entry beside this package's.
   statifier-ui ships its JavaScript as source too (statifier-ui
   `docs/adr/0009-javascript-ships-as-source.md`), and both point at the
   package's `assets/` directory:

   ```json
   {
     "dependencies": {
       "statifier_blocks": "file:../deps/statifier_blocks/assets",
       "statifier_ui": "file:../deps/statifier_ui/assets"
     }
   }
   ```

   That record documents this route and no other; statifier-ui's
   `assets/package.json` names `js/index.js` as the entry point, which is the
   file any other specifier would have to reach.
3. Register its hooks beside this package's. The two packages' hooks are
   separate objects, and registering one does not register the other:

   ```javascript
   import StatifierBlocks from "statifier_blocks";
   import { StatifierUIHooks } from "statifier_ui";

   let liveSocket = new LiveSocket("/live", Socket, {
     hooks: { ...StatifierBlocks, ...StatifierUIHooks },
   });
   ```

   `StatifierUIHooks` is `StatifierUIExpressionInput` and
   `StatifierUIExpressionPicklist`; a host that wants one of them imports it
   by name instead.

What the field renders with the dependency absent, present without its
hooks, and present with them is in the reference's
[`:expression` field table](../reference/editor-assigns-and-host-seams.md#what-an-expression-field-renders).
To replace the control entirely, pass your own function component as
`expression_component`; it wins whether or not `statifier_ui` is present.

If you pass a datamodel **document**, the kinds it declares reach that editor
too: a clause on a path declared `integer` offers the numeric operators, and
one on a `date` path the date set.

## Use your own icons

You do not have to pass `icon`: the package ships
`StatifierBlocks.Editor.Icons`, inline SVGs for the names the core block types
declare, and the editor uses them when you pass nothing. To recolour them, set
the two tokens the tile reads, `--sb-block-accent` and
`--sb-block-accent-tint` (see [How to theme the editor](../theming.md)).

If you have an icon set of your own, pass a component taking `name` and
`class`; the *name* is what the block type declared, and yours wins on every
tile, the canvas cards and the palette rows alike:

```heex
<.live_component
  module={StatifierBlocks.Editor}
  id="registration-editor"
  document={@registration}
  palette={@palette}
  icon={&icon/1}
/>
```

```elixir
# A heroicons-style component: the name in, your markup out. The core types
# name heroicons ("clock", "bars-3", "arrow-path", ...), so a host already
# using them resolves every one by prefixing.
attr :name, :string, required: true
attr :class, :string, default: nil

def icon(assigns) do
  ~H"""
  <span class={[@class, "hero-" <> @name]} aria-hidden="true" />
  """
end
```

Yours is rendered as a **function component**, exactly as if the editor had
written `<.icon name={...} class={...} />` against it, so every
`Phoenix.Component` helper works inside it. It has to return a `~H` template.
It is never called with a `nil` name: a block type that declares no icon gets
no tile.

## Route compile findings into the drawer

Adapt the compiler's warnings, then pass the anchored ones as the `findings`
assign (or straight into `StatifierBlocks.ViewModel.build/3` if you drive the
view model yourself):

```elixir
{lint_findings, _refused} =
  StatifierBlocks.Finding.from_compiler_all(compiled.warnings)
```

`from_compiler_all/2` returns the findings it could anchor and, separately,
the ones it refused with the reason: a finding that names no block has
nowhere in the editor to land.

## Check a stored document before an author opens it

For a document that did not come out of the editor - a stored master, one
built in code - ask whether the palette you are about to mount can express
it:

- `StatifierBlocks.Plan.expressible(document, palette)` answers `:ok`, or
  `{:no, reasons}` with each reason naming the rule and the block.
- `StatifierBlocks.Plan.expressible?(document, palette)` answers `true` or
  `false`, if you only need the yes or no.

Both take the assignability context as an optional third argument.

## Offer "Save as a step"

Pass `on_collapse` to draw the **"Save as a step"** control on a selected
arrangement. Your function receives the `Composite.Data` declaration
`StatifierBlocks.Composite.Collapse.propose/3` answers - the params, the
subtree template, and a pass-through slot for an unfilled slot inside the
selection. The gesture edits no document and the package persists nothing:

1. Name the new type and store the declaration where your app keeps them.
2. Register it in the palette you mount.
3. To swap the arrangement for the new type, take the compound edit
   `Collapse.replacement/4` answers and commit it yourself through
   `StatifierBlocks.Edit`.

The inverse gesture, **"Replace with its steps"** on a composite's card, needs
nothing from you.

## Size and theme the editor

By default the editor is as tall as the document in it and your page
scrolls, which puts the drawer below the fold on a long document. To bound
it, set `--sb-editor-height` to a length - `calc(100vh - 4rem)`, or `100%`
inside a box your own layout has already sized; the panes then scroll in
their own boxes and the drawer stays pinned at the bottom.

Set any other `--sb-*` property through the `theme` assign, or in your own
CSS against the `sb-` class prefix:

```heex
<.live_component
  module={StatifierBlocks.Editor}
  id="registration-editor"
  theme={%{"--sb-accent" => "var(--brand-500)", "--sb-radius" => "10px"}}
  ...
/>
```

[How to theme the editor](../theming.md) is the full guide, with a complete
host theme you can copy. To mount the editor for one audience - fewer
surfaces, or read-only - see [How to mount the editor for one
audience](../profiles.md).

## Drive edits from something other than the editor

The component sits over a pure command algebra - `StatifierBlocks.Edit`
(insert, remove, move, update config, each with its inverse) over
`StatifierBlocks.ViewModel` - with no UI framework dependency. Call those
modules directly to edit a document from your own surface.
