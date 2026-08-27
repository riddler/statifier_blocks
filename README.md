# StatifierBlocks

[![CI](https://github.com/riddler/statifier_blocks/actions/workflows/ci.yml/badge.svg)](https://github.com/riddler/statifier_blocks/actions/workflows/ci.yml)
[![Hex.pm Version](https://img.shields.io/hexpm/v/statifier_blocks.svg)](https://hex.pm/packages/statifier_blocks)
[![Hex Downloads](https://img.shields.io/hexpm/dt/statifier_blocks.svg)](https://hex.pm/packages/statifier_blocks)
[![Hex Docs](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/statifier_blocks/)
[![License](https://img.shields.io/hexpm/l/statifier_blocks.svg)](https://github.com/riddler/statifier_blocks/blob/main/LICENSE)

Block document model, one-way SCXML compiler, and LiveView editor components
for composing [Statifier](https://github.com/riddler/statifier-ex) statecharts
from typed blocks.

**Status: scaffold.** Nothing is implemented yet. The package skeleton is in
place; the contracts below are being decided in ADRs before any of them is
built.

## The charter

Statecharts are the right execution model for long-running workflows, and
SCXML is the right interchange format for them - but neither is something a
non-engineer will author by hand. This package is the authoring layer:

- **A block document model.** The authoring artifact is a document: a tree of
  typed blocks that a person composes, each block a unit with a declared
  shape rather than free-form XML. The document, not the chart, is the source
  of truth that gets stored, versioned, and edited.

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
    {:statifier_blocks, "~> 0.1"}
  ]
end
```

Not yet published to Hex.

## Using the editor

The editor ships in this package, and a host that never renders anything must
not pay for it. `phoenix_live_view` is therefore an **optional** dependency,
and every module under `StatifierBlocks.Editor.*` is compiled behind a
presence guard: an authoring API that compiles documents in a background job,
a test suite that exercises validation, a migration script - none of them drag
in Phoenix, and none of them compile a line of editor code.

A host that wants the editor already has LiveView, since there is nowhere else
to put the editor, so it adds nothing to `mix.exs`. It does three things:

**1. Import the hook.** The package's entire client-side surface is one hook.
Add the package to `assets/package.json`:

```json
{ "dependencies": { "statifier_blocks": "file:../deps/statifier_blocks" } }
```

and register it in `app.js`:

```javascript
import { StatifierBlocksDrag } from "statifier_blocks";

let liveSocket = new LiveSocket("/live", Socket, {
  hooks: { StatifierBlocksDrag },
});
```

**2. Import the stylesheet.** It is structural CSS only - the column layout,
the drag affordances, the finding treatments - with no visual opinion and no
framework:

```css
@import "../../deps/statifier_blocks/assets/css/statifier_blocks.css";
```

**3. Render the component.**

```heex
<.live_component
  module={StatifierBlocks.Editor}
  id="editor"
  document={@document}
  palette={@palette}
  on_change={&save_draft/1}
/>
```

Optional assigns: `findings` (yours, merged with the ones the view model
derives), `icon` (a function component that turns an icon *name* into markup -
this package never emits an icon set of its own), `expression_component` (an
override for `:expression` fields), `theme`, and `class`.

### Theming

Every class the package emits is prefixed `sb-`, and every color, space,
radius and drag treatment is a `--sb-*` custom property with a default. Set
them through the `theme` assign, or in your own CSS against the prefix:

```heex
<.live_component
  module={StatifierBlocks.Editor}
  id="editor"
  theme={%{"--sb-accent" => "var(--brand-500)", "--sb-radius" => "10px"}}
  ...
/>
```

Enough that a host can make the editor look like its own product without
forking it, and not so much that the package acquires a theming DSL.

### What stays yours

Which palette entries a tenant may use, who may edit or publish a document,
where it is stored, and what publishing means. The editor is also a
single-session component: it surfaces the `revision` it loaded so you can do
optimistic concurrency on save, and it does not merge or resolve anything.

## License

MIT - see
[LICENSE](https://github.com/riddler/statifier_blocks/blob/main/LICENSE).
