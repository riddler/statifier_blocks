defmodule StatifierBlocks.Describe.Node do
  @moduledoc """
  One block in a `StatifierBlocks.Describe` outline (ADR-0016 decision 1).

  | Field | What it holds |
  |---|---|
  | `id` | the block's id |
  | `type` | the block's type name, as the document stores it |
  | `parent` | the id of the block whose slot holds this one; `nil` for the root |
  | `depth` | `StatifierBlocks.ViewModel.outline/1`'s depth; the root is `0` |
  | `kind` | `outline/1`'s kind: `:step`, `:arm`, `:rail` or `:tray` |
  | `sentence` | `StatifierBlocks.ViewModel.sentence/1` of the block's view-model node |
  | `outcomes` | the outcome names `StatifierBlocks.BlockType.outcomes/2` declares for the block's config, in declaration order |
  | `summary` | the block's summary chips, kept apart from `sentence` and never joined into it |
  | `fan_label` | `StatifierBlocks.ViewModel.fan_label/1`: `"one of"`, `"all of"` or `nil` |

  A block whose type the palette cannot resolve is its placeholder: its
  type name as its sentence, no chips, and the one `"done"` outcome a type
  declaring no `outcomes/1` has.
  """

  alias StatifierBlocks.{Block, ViewModel}

  @type t :: %__MODULE__{
          id: Block.id(),
          type: Block.type_name(),
          parent: Block.id() | nil,
          depth: non_neg_integer(),
          kind: ViewModel.kind(),
          sentence: String.t(),
          outcomes: [String.t()],
          summary: [String.t()],
          fan_label: String.t() | nil
        }

  @enforce_keys [:id, :type, :depth, :kind, :sentence]
  defstruct [
    :id,
    :type,
    :depth,
    :kind,
    :sentence,
    parent: nil,
    outcomes: [],
    summary: [],
    fan_label: nil
  ]
end
