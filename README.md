# StatifierBlocks

[![CI](https://github.com/riddler/statifier_blocks/actions/workflows/ci.yml/badge.svg)](https://github.com/riddler/statifier_blocks/actions/workflows/ci.yml)
[![Hex.pm Version](https://img.shields.io/hexpm/v/statifier_blocks.svg)](https://hex.pm/packages/statifier_blocks)
[![Hex Downloads](https://img.shields.io/hexpm/dt/statifier_blocks.svg)](https://hex.pm/packages/statifier_blocks)
[![Hex Docs](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/statifier_blocks/)
[![License](https://img.shields.io/hexpm/l/statifier_blocks.svg)](https://github.com/riddler/statifier_blocks/blob/main/LICENSE)

Block document model, one-way SCXML compiler, and LiveView editor components
for composing [Statifier](https://github.com/riddler/statifier-ex) statecharts
from typed blocks.

> **Pre-1.0.** Until `statifier_blocks` reaches v1.0, its public surface may change
> between minor releases, sometimes drastically: a release may rename modules,
> callbacks, table columns, telemetry events or error vocabulary with no
> compatibility shim. Every such change is recorded in
> [CHANGELOG.md](CHANGELOG.md) under a bold **Breaking** heading that says what
> to do about it. Pinning to an exact minor - `~> X.Y.0` - is the recommended way
> to consume the package until 1.0.

## Why a block layer

Statecharts are the right execution model for long-running workflows, and
SCXML is the right interchange format for them - but neither is something a
non-engineer will author by hand. This package is the authoring layer:

- **A block document model.** A document is a tree of typed blocks, each with
  a declared shape rather than free-form XML. The document, not the chart, is
  what people edit and you store, one revision per saved edit.
- **A one-way SCXML compiler.** A document compiles to an SCXML chart that
  Statifier runs, with a provenance map that points a running position back
  at the block that produced it. Nothing decompiles a chart into blocks.
- **LiveView editor components.** The components a host embeds so people can
  compose, rearrange and validate a document in a browser.

Blocks are typed and host-pluggable: a host registers the block types its own
domain needs, and the compiler and editor work off that palette rather than
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

## Basic usage

A visitor becomes a library patron through a few screens. Declare one step of
your own, put it after a `core.invoke` step that names your check of the
visitor's details, and compile the document to a chart:

```elixir
defmodule MyApp.Blocks.SendWelcome do
  @moduledoc "myapp.send_welcome: sends the new patron a welcome message."
  use StatifierBlocks.InvokeStep,
    invoke_type: "myapp:send_welcome",
    palette: %{label: "Send welcome", group: "Registration"}
end

alias StatifierBlocks.{Block, Compiler, Document, Palette}

palette = Palette.from_modules([{"myapp.send_welcome", MyApp.Blocks.SendWelcome}], core: true)

document =
  Document.new(
    Block.new("core.sequence",
      id: "blk_root",
      slots: %{
        "body" => [
          Block.new("core.invoke",
            id: "blk_check_details",
            config: %{"invoke_type" => "myapp:check_details"}
          ),
          Block.new("myapp.send_welcome", id: "blk_send_welcome")
        ]
      }
    ),
    id: "bdoc_patron_registration"
  )

{:ok, compiled} = Compiler.compile(document, palette)

compiled.invoke_types
#=> ["myapp:check_details", "myapp:send_welcome"]

compiled.scxml =~ ~s(<invoke type="myapp:send_welcome"/>)
#=> true
```

`compiled.scxml` is a chart Statifier runs as-is; your host runs the two
invoke types it names.
[How to build a block document and compile it to a chart](docs/guides/build-and-compile.md)
walks the same path with a branch, a declared datamodel and the provenance map.

## Documentation

- Learn
  - [Basic usage](#basic-usage) - one host step and one core step composed into a document and compiled to a chart
- Do
  - [How to build a block document and compile it to a chart](docs/guides/build-and-compile.md) - write two block types, compose a document, compile it and point a running position back at its blocks
  - [How to register your own block types](docs/guides/register-block-types.md) - write a block type, declare one from a base or a subtree, and build a palette from your own types beside the core vocabulary
  - [How to type a palette](docs/typing-a-palette.md) - declare what each block type reads and writes at a datamodel path, and check a document against the records and shapes your host declares
  - [How to build common flow patterns](docs/guides/flow-patterns.md) - build the shapes a workflow commonly needs out of the core block types, starting with a step that must finish within a bound
  - [How to publish a document](docs/guides/publish-a-document.md) - call the checks a publish step runs, in order, and decide on each finding by its severity
  - [How to write a host advisory finding](docs/host-validators.md) - put one of your own rules on the author's screen as a warning, without stopping the document from compiling
  - [How to validate a document against the schema from any language](docs/guides/validate-a-document-against-the-schema.md) - hand the JSON Schema to a service in another language and check a stored document against it
  - [How to describe a document in words](docs/describing-a-document.md) - outline a document, write the outline as lines of English and reword them in your own voice
  - [How to migrate a document from 0.27 to 0.34](docs/guides/migrating-documents-0.27-to-0.34.md) - move a document onto the outcome vocabulary: declared outcomes, a handler's `finish_as` and the `on_<name>` slots
  - [How to embed the editor in a LiveView host](docs/guides/embed-the-editor.md) - register the hooks, import the stylesheet, render the editor component and connect selection, icons, findings and saved steps
  - [How to mount the editor for one audience](docs/profiles.md) - say which of the editor's surfaces a mount draws, and mount it read-only
  - [How to theme the editor](docs/theming.md) - make the editor look like your product without forking it
  - [How to mount the Map](docs/guides/mount-the-map.md) - render the Map and its description beside your list of steps and register the Map hook
- Look up
  - [Cheatsheet](docs/reference/cheatsheet.cheatmd) - the calls a host makes most, for the document, the palette, compile, publish and the editor mount
  - [Config fields and the handlers this package ships](docs/reference/config-fields-and-handlers.md) - where a config field's value is stored, and the invoke handler the package ships for `core.subchart`
  - [Editor assigns and host seams](docs/reference/editor-assigns-and-host-seams.md) - what the mounted editor holds, every seam a host declares, and the limits the canvas draws within
  - [Upgrading a host from 0.31 to 0.44](docs/upgrading.md) - what a host changes at each minor, and the calls a publish step makes
  - [The changelog](CHANGELOG.md) - what changed in each version, with a **Breaking** heading for what a host must do
- Understand
  - [Documents, revisions, charts and executions, and why blocks compile to a chart](docs/explanation/documents-revisions-charts-and-executions.md) - what each of the four nouns is, how a compile joins a revision to its chart, and why the compile runs one way
  - [The block-level flow graph](docs/block-level-flow-graph.md) - one node per block and one edge per way control passes between blocks, lifted from the compiled chart
  - [Design records](https://github.com/riddler/statifier_blocks/blob/main/docs/adr/README.md) - the decisions this package is built out of; when a record and the code disagree, the record is the contract

## Compatibility

- Elixir `~> 1.18`.
- Statifier `~> 2.2`, `statifier_datamodel ~> 0.4` and `predicator ~> 9.4 and >= 9.4.1`.
- `phoenix_live_view ~> 1.0` is optional; without it no editor module
  compiles, and the rest of the package compiles and runs.
  `statifier_ui ~> 0.9` is optional too; with it an `:expression` field gets
  its expression editor.
- Pre-1.0: pin an exact minor (`~> 0.44.0`) until 1.0, and read the
  [CHANGELOG](CHANGELOG.md)'s **Breaking** headings when you move it.

## License

MIT - see
[LICENSE](https://github.com/riddler/statifier_blocks/blob/main/LICENSE).

One file is not: `assets/vendor/elk.bundled.js`, elkjs 0.9.3 vendored
unmodified for the Map hook, is under the Eclipse Public License 2.0, and its
licence text ships beside it as `assets/vendor/elkjs-LICENSE.md`.
