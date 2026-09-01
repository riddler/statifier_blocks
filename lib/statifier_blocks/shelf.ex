defmodule StatifierBlocks.Shelf do
  @moduledoc """
  The two placement facts `io/1` cannot carry, and the identity every other
  surface asks about the shelf and the gap marker.

  ADR-0002's amendment of 2026-08-31, section G12, states the two facts and
  campaign-024 ruling R-b puts their enforcement in the compiler's
  Structure stage; ADR-0004's amendment of the same date, section D3, names
  the two codes. This module owns both, and owns nothing else: kind
  admission, slot arity and the data-flow walk are unchanged and are still
  `StatifierBlocks.Assignability`'s and `StatifierBlocks.SlotValidation`'s.

  ## Why this module is small on purpose

  `:draft_shelf` does the placement work. Every slot in the shipped `core.*`
  vocabulary accepts `[:step]` or `[:interrupt_handler]`, so a block
  declaring only that kind is refused by all of them through the
  intersection ADR-0003 decision 3 already performs, with no new rule, no
  per-type list, and nothing in this module. What is left over is exactly
  two things the intersection cannot express, and they are the only two
  rules here:

  | Finding | Fact |
  |---|---|
  | `:drafts_block_misplaced` | a shelf is a **direct child of the root block's `body` slot** and nowhere else - a constraint on *depth*, which is a property of the document rather than of either block (G12a) |
  | `:duplicate_drafts_block` | a document carries **at most one** shelf - cardinality across a document, closest in shape to ADR-0001 decision 3's document-unique ids and checked the same way (G12b) |

  Both refuse documents that would otherwise be admitted and neither changes
  the meaning of a document that is already valid, so relaxing either later
  is additive (G12c).

  ## Why the type name and not the module

  Every predicate here matches `Block.type`, the string ADR-0002 decision 1
  puts in the document, rather than resolving a palette entry and comparing
  modules. The record says "a `core.drafts` block" throughout and `core.` is
  the reserved namespace decision 4 provides for, so the name is what is
  being talked about; a name test needs no palette, cannot disagree with one,
  and leaves the compiler and the editor with no dependency on a core type
  module. A host that wants its own shelf mints its own kind, its own
  container and its own structure rule, which ADR-0003's amendment of this
  date already records as the intended path.

  ## The second block, not the first

  `:duplicate_drafts_block` names the second and every later shelf in
  document order. The first is the one the author almost certainly means to
  keep, and a finding on it would ask them to fix the block that is not the
  problem - the same reasoning ADR-0001 decision 11f applies to a shadowed
  root, arriving at a different rule for the same reason (D3).
  """

  alias StatifierBlocks.{Block, Document}

  @drafts_type "core.drafts"
  @placeholder_type "core.placeholder"
  @root_slot "body"

  @typedoc """
  A placement violation, in the tuple shape `StatifierBlocks.Compiler`
  adapts into a `:structure` finding. The first element is the code
  ADR-0004's amendment of 2026-08-31, section D3, names.
  """
  @type finding ::
          {:drafts_block_misplaced, Block.id()}
          | {:duplicate_drafts_block, Block.id()}

  @doc "The type name a shelf is stored under."
  @spec drafts_type() :: Block.type_name()
  def drafts_type, do: @drafts_type

  @doc "The type name a gap marker is stored under."
  @spec placeholder_type() :: Block.type_name()
  def placeholder_type, do: @placeholder_type

  @doc "Whether this type name is the shelf's."
  @spec shelf_type?(Block.type_name()) :: boolean()
  def shelf_type?(@drafts_type), do: true
  def shelf_type?(type) when is_binary(type), do: false

  @doc "Whether this type name is the gap marker's."
  @spec marker_type?(Block.type_name()) :: boolean()
  def marker_type?(@placeholder_type), do: true
  def marker_type?(type) when is_binary(type), do: false

  @doc "Whether this block is the shelf."
  @spec shelf?(Block.t()) :: boolean()
  def shelf?(%Block{type: type}), do: shelf_type?(type)

  @doc "Whether this block is a gap marker."
  @spec marker?(Block.t()) :: boolean()
  def marker?(%Block{type: type}), do: marker_type?(type)

  @doc """
  Whether `{parent_id, slot}` is the one position a shelf is admitted in:
  the root block's `body` slot (G12a).

  This is the *admission* half of the depth rule, and it has to exist as
  well as the refusal half. Every container in the shipped vocabulary
  declares `slot_accepts` `[:step]` or `[:interrupt_handler]`, the root
  included, so the ordinary intersection refuses a `:draft_shelf`
  everywhere - at the one position the record admits it as well as at every
  position it does not. G12a is what says the root's `body` admits one
  anyway, and `StatifierBlocks.Assignability` consults this to say so.

  Reaching it through assignability rather than through a filter on the
  compiler's findings is deliberate: `valid_targets/4` is the same
  decision, so an author dragging a shelf onto the root's body is offered
  the position for the same reason a shelf already there does not refuse.
  Two answers would be two chances to disagree.
  """
  @spec root_body?(Document.t(), Block.id(), Block.slot_name()) :: boolean()
  def root_body?(%Document{root: %Block{id: root_id}}, parent_id, slot),
    do: parent_id == root_id and slot == @root_slot

  @doc """
  Every shelf in `document`, in `Document.blocks/1` pre-order.

  A document is well-formed with none and with exactly one; more than one
  is `validate/1`'s business, not this function's.
  """
  @spec shelves(Document.t()) :: [Block.t()]
  def shelves(%Document{} = document) do
    document
    |> Document.blocks()
    |> Enum.filter(&shelf?/1)
  end

  @doc """
  Every placement violation in `document`, in document order. `:ok` when
  there are none.

  The two rules are independent and both are reported: a second shelf that
  is also nested inside a group carries both codes, which is ADR-0004
  decision 10's "within a stage every finding is reported" - the two are
  siblings rather than one being a consequence of the other.
  """
  @spec validate(Document.t()) :: :ok | {:error, [finding()]}
  def validate(%Document{} = document) do
    findings =
      document
      |> shelves()
      |> Enum.with_index()
      |> Enum.flat_map(&block_findings(&1, document))

    case findings do
      [] -> :ok
      findings -> {:error, findings}
    end
  end

  @spec block_findings({Block.t(), non_neg_integer()}, Document.t()) :: [finding()]
  defp block_findings({%Block{id: id} = block, index}, document) do
    misplaced = if at_root_body?(document, block), do: [], else: [{:drafts_block_misplaced, id}]
    duplicate = if index == 0, do: [], else: [{:duplicate_drafts_block, id}]

    misplaced ++ duplicate
  end

  # The root itself carries the empty path, so a document whose *root* is a
  # shelf is misplaced too - G12a says "a direct child of the root block's
  # `body` slot", and the root is not a child of itself.
  @spec at_root_body?(Document.t(), Block.t()) :: boolean()
  defp at_root_body?(%Document{root: %Block{id: root_id}} = document, %Block{id: id}) do
    case Document.fetch_path(document, id) do
      {:ok, [{^root_id, @root_slot, _index}]} -> true
      _other -> false
    end
  end
end
