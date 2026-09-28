defmodule StatifierBlocks.Describe.Edge do
  @moduledoc """
  One way control passes between blocks in a `StatifierBlocks.Describe`
  outline, in the vocabulary of the package's note on the block-level flow
  graph, `docs/block-level-flow-graph.md` (ADR-0016 decision 1).

  `container` is the block whose structure produced the edge. An endpoint
  names a block and which part of it the edge touches: `{:block, id}` the
  block itself, `{:entry, id}` and `{:exit, id}` a container's entry and
  exit, and `{:body, id}` a group's body.

  | `kind` | From | To | Carries |
  |---|---|---|---|
  | `:entry` | `{:entry, container}` | the first child, or `{:exit, container}` for an empty body | nothing |
  | `:sequence` | a child | the next child in the same slot | `outcomes` |
  | `:exit` | the last child of a slot | `{:exit, container}` | `outcomes` |
  | `:branch` | `{:entry, branch}` | an arm's first child, or `{:exit, branch}` for an empty arm | `condition` |
  | `:interrupt` | a handler | `{:exit, group}` to abandon, `{:body, group}` to resume | `event`, `history` |
  | `:timer` | a delayed `core.send` | `{:block, id}`, a `core.on_event` or `core.await` naming the sent event | `event`, `delay` |

  `outcomes` is every outcome name the source block's type declares, on
  the one edge. `condition` is the arm's condition as its config holds it
  (`nil` when none is written), `:otherwise`, or `:undecided`. `history` is
  `:shallow` or `:deep` for a resume into a `core.resumable_group`, and
  `nil` otherwise: a resume into a `core.group` restarts its body from the
  first step.

  A `:timer` edge is the one edge that joins two blocks by an event name
  (ADR-0016's amendment of 2026-09-27, ADR-0017 decision 3): it is not a
  transition, it says that the send arms an event the other block waits
  for. Its `container` is the send's parent, `event` is the sent event, and
  `delay` is the send's delay as its config holds it, the edge's label.
  `delay` is `nil` on every other kind of edge.
  """

  alias StatifierBlocks.Block

  @type kind :: :entry | :sequence | :exit | :branch | :interrupt | :timer

  @type endpoint ::
          {:block, Block.id()} | {:entry, Block.id()} | {:exit, Block.id()} | {:body, Block.id()}

  @type condition :: String.t() | :otherwise | :undecided | nil

  @type t :: %__MODULE__{
          kind: kind(),
          container: Block.id(),
          from: endpoint(),
          to: endpoint(),
          outcomes: [String.t()],
          condition: condition(),
          event: String.t() | nil,
          history: :shallow | :deep | nil,
          delay: String.t() | nil
        }

  @enforce_keys [:kind, :container, :from, :to]
  defstruct [
    :kind,
    :container,
    :from,
    :to,
    outcomes: [],
    condition: nil,
    event: nil,
    history: nil,
    delay: nil
  ]
end
