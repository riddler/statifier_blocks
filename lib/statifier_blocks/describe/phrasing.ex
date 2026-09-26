defmodule StatifierBlocks.Describe.Phrasing do
  @moduledoc """
  The seam a host rewords a described document through (ADR-0016
  decision 3).

  `StatifierBlocks.Describe.render/2` writes a default line for every node
  and every edge. With `phrasing: module`, a module implementing this
  behaviour, each line is then offered to the callback for its node's
  `kind` or its edge's `kind`, handed the structured
  `StatifierBlocks.Describe.Node` or `StatifierBlocks.Describe.Edge` and the
  default line, and the callback answers its own line or `:default`.

  | Callback | Asked for |
  |---|---|
  | `step/2`, `arm/2`, `rail/2`, `tray/2` | a node of that `kind` |
  | `entry/2`, `sequence/2`, `branch/2`, `interrupt/2`, `exit/2` | an edge of that `kind` |

  Every callback is optional; an undeclared one keeps the default line.

  ## What an answer must be

  A line, held to the refusal set `StatifierBlocks.BlockType.sentence/2`
  holds a type's `sentence/1` to. A refused answer falls back to the
  default line for that one node or edge, never to an error:

  | The callback | The line |
  |---|---|
  | answers a non-blank binary carrying no newline, carriage return or tab | that binary, verbatim, uncapped |
  | answers `:default` | the default line |
  | answers a blank binary, one carrying a newline, carriage return or tab, or any other term | the default line |
  | raises, throws or exits | the default line |

  The seam rewords lines. It does not add, drop or reorder them, and it
  never sees or changes the structure `StatifierBlocks.Describe.outline/3`
  answered. For the render to stay byte-identical for equal input, a
  callback has to be a pure function of its arguments; that half of the
  contract is the host's.
  """

  alias StatifierBlocks.Describe.{Edge, Node}

  @typedoc "A callback's answer: its own line, or `:default` for the default line."
  @type answer :: String.t() | :default

  @doc "The line for a node reached as a step of its parent's body."
  @callback step(node :: Node.t(), default :: String.t()) :: answer()

  @doc "The line for a node in one of its parent's side-by-side columns."
  @callback arm(node :: Node.t(), default :: String.t()) :: answer()

  @doc "The line for a node on one of its parent's rails."
  @callback rail(node :: Node.t(), default :: String.t()) :: answer()

  @doc "The line for a node in one of its parent's trays."
  @callback tray(node :: Node.t(), default :: String.t()) :: answer()

  @doc "The line for an `:entry` edge."
  @callback entry(edge :: Edge.t(), default :: String.t()) :: answer()

  @doc "The line for a `:sequence` edge."
  @callback sequence(edge :: Edge.t(), default :: String.t()) :: answer()

  @doc "The line for a `:branch` edge."
  @callback branch(edge :: Edge.t(), default :: String.t()) :: answer()

  @doc "The line for an `:interrupt` edge."
  @callback interrupt(edge :: Edge.t(), default :: String.t()) :: answer()

  @doc "The line for an `:exit` edge."
  @callback exit(edge :: Edge.t(), default :: String.t()) :: answer()

  @optional_callbacks step: 2,
                      arm: 2,
                      rail: 2,
                      tray: 2,
                      entry: 2,
                      sequence: 2,
                      branch: 2,
                      interrupt: 2,
                      exit: 2
end
