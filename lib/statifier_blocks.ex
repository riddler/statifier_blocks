defmodule StatifierBlocks do
  @moduledoc """
  Block document model, one-way SCXML compiler, and LiveView editor
  components for composing [Statifier](https://github.com/riddler/statifier-ex)
  statecharts from typed blocks.

  A block document is the authoring artifact: a tree of typed blocks that a
  person composes in an editor. The compiler turns that document into SCXML
  in one direction only - the document is the source of truth, and the chart
  it produces is a build product. Nothing decompiles a chart back into blocks.

  This module is the package's root and carries no functions. The map below
  is where to start; the README's worked example runs the whole path end to
  end.

  ## The model

  | Module | What it is |
  |---|---|
  | `StatifierBlocks.Block` | one node: `{type, id, type_version, config, slots}` and nothing else (ADR-0001) |
  | `StatifierBlocks.Document` | the tree plus its envelope: the pre-order walk, path lookup, validation, canonical JSON, content hash, decode |
  | `StatifierBlocks.BlockType` | the behaviour a block type implements, including `config_schema/1` and its optional `value_path` (ADR-0002) |
  | `StatifierBlocks.Palette` | a caller-supplied `type_name => module` value - never application config, never a named process |
  | `StatifierBlocks.Core` | the eight `core.*` structural types this package ships |
  | `StatifierBlocks.Assignability` | may this block land in this slot, by kind tag and by host-widened data-flow type (ADR-0003) |

  ## The compile

  | Module | What it is |
  |---|---|
  | `StatifierBlocks.Compiler` | `compile/3`: a total function of `{document, palette}` (ADR-0004) |
  | `StatifierBlocks.Compiled` | what one successful compile produced |
  | `StatifierBlocks.Provenance` | which generated element came from which block, keyed by state id and by byte span |
  | `StatifierBlocks.CompilationRecord` | the join between document identity and chart identity |

  ## The editor

  | Module | What it is |
  |---|---|
  | `StatifierBlocks.Edit` | the pure command algebra - insert, remove, move, update config, each with its inverse (ADR-0005) |
  | `StatifierBlocks.Edit.History` | the undo/redo stack over that algebra, and the palette-aware gate on it |
  | `StatifierBlocks.ViewModel` | everything a renderer needs, derived from `{document, palette}` and stored nowhere |
  | `StatifierBlocks.Editor` | the LiveView component a host embeds |

  LiveView is an optional dependency and every `Editor.*` module is compiled
  behind a presence guard, so a host that only compiles documents pulls in
  none of it and compiles no editor code at all. Everything above the editor
  row is available in that tree.
  """
end
