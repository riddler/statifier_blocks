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
  - [How to mount the Map](docs/guides/mount-the-map.md) -
    render the Map and its description beside your list of steps, connect the
    list's events, register the Map hook and know what it adds to your bundle
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
