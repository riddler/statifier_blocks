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

## License

MIT - see
[LICENSE](https://github.com/riddler/statifier_blocks/blob/main/LICENSE).
