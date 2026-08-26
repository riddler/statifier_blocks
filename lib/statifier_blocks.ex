defmodule StatifierBlocks do
  @moduledoc """
  Block document model, one-way SCXML compiler, and LiveView editor
  components for composing [Statifier](https://github.com/riddler/statifier-ex)
  statecharts from typed blocks.

  A block document is the authoring artifact: a tree of typed blocks that a
  person composes in an editor. The compiler turns that document into SCXML
  in one direction only - the document is the source of truth, and the chart
  it produces is a build product. Nothing decompiles a chart back into blocks.

  Nothing is implemented yet. This module exists so the package has a root;
  the block schema, the block-type behaviour, the compiler and its
  provenance map, and the LiveView editor architecture are each being
  decided in an ADR before any of them is built.
  """
end
