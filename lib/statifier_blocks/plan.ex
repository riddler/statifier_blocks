defmodule StatifierBlocks.Plan do
  @moduledoc """
  Whole-document questions a host asks before it hands a document to the
  editor.

  `expressible/3` asks whether every block in a document sits at a place
  the editor, mounted with a given palette, would itself have let an author
  put it, and whether every slot the document still has to fill is one that
  palette can fill. A host installing a document it did not author through
  the editor - a stored master, a document built in code, one migrated from
  an older palette - asks it once, and learns whether an author can go on
  editing that document with the palette they will be handed.
  `expressible?/3` asks the same question and answers a boolean, for a
  host that only needs the yes or no.

  ## The same predicate the editor uses, asked at each block's own position

  `StatifierBlocks.Edit.Targets` answers "may this block go here" for a gap
  an author is about to drop into, with four rules (ADR-0005 decision 5):
  the slot is declared, assignability accepts the block, the slot has room,
  and the slot is not inside the block's own subtree. This module asks the
  first three of those rules about a block that is **already** in the
  document, at its own `{parent_id, slot, index}`. The fourth cannot fail
  for a block already in a tree.

  Rule 2 is **kind admission** only: whether the block's kinds are ones its
  slot accepts (ADR-0003 decision 3). Its findings are read from
  `StatifierBlocks.Assignability.validate/3`, which checks every block at
  its own position once, and only its `:kind_not_admitted` findings are
  reasons here.

  A `:type_mismatch` - a read the environment at the block's position
  contradicts - is not a reason. It is a validation finding, and the editor
  does not refuse a drop for one: a slot is offered to a drag when any of its
  gaps accepts the block, a drop at another gap is committed and flagged,
  and the editor never blocks an edit for a validation reason (ADR-0005
  decision 5). A document holding such a read is one an author could have
  built in the editor, and can go on editing there.

  ## Reasons

  `expressible/3` answers `:ok`, or `{:no, reasons}` with one reason per
  thing the editor would refuse, in `StatifierBlocks.Document.blocks/1`
  pre-order and, within one block, in the order the table lists them. Every
  reason names the block an author has to look at second and the rule first:

  | Reason | The rule |
  |---|---|
  | `{:unresolved, block_id, error}` | the block's type does not resolve through the palette; `error` is `StatifierBlocks.Palette.resolve/2`'s |
  | `{:slot_not_declared, block_id, {parent_id, slot}}` | the block sits in a slot its parent's type does not declare (rule 1) |
  | `{:no_room, block_id, {parent_id, slot, index}}` | the block sits past the first child of an `:exactly_one` or `:zero_or_one` slot (rule 3) |
  | `{:not_admitted, block_id, finding}` | the block's slot does not admit its kinds (rule 2); `finding` is the `:kind_not_admitted` member of `t:StatifierBlocks.Assignability.finding/0` |
  | `{:unfillable_slot, block_id, slot}` | the block's `:exactly_one` or `:at_least_one` slot is empty, and no block type in the palette is admitted there |

  A block whose parent does not resolve is not checked against rules 1 and
  3 - there is no declared slot set to check against - and the parent's own
  `:unresolved` reason is the one an author acts on.

  ## What it does not ask

  - **Recipes.** `:unfillable_slot` asks the palette's block types, through
    `StatifierBlocks.Edit.Targets.accepted_types_at/5`, not its recipes.
  - **Profiles.** A mount's `profile` can hide palette groups from an
    author; this function sees the palette it is handed. A host that mounts
    the editor with a narrowed palette passes that palette here.
  - **Config validity, compile findings, or slot arity beyond room.** An
    optional slot left empty, or a required slot left empty that the palette
    can fill, is something an author can finish in the editor.
  """

  alias StatifierBlocks.{Assignability, Block, BlockType, Document, Palette}
  alias StatifierBlocks.Edit.Targets

  @typedoc "Why a document is not expressible through a palette. See the moduledoc's table."
  @type reason ::
          {:unresolved, Block.id(), term()}
          | {:slot_not_declared, Block.id(), {Block.id(), Block.slot_name()}}
          | {:no_room, Block.id(), Assignability.target()}
          | {:not_admitted, Block.id(), Assignability.finding()}
          | {:unfillable_slot, Block.id(), Block.slot_name()}

  @doc """
  `:ok` when every block in `document` sits where the editor, mounted with
  `palette`, admits it, and every required slot that is still empty is one
  some block type in `palette` could fill; otherwise `{:no, reasons}`.

  `ctx` is the `t:StatifierBlocks.Assignability.context/0` the assignability
  check is asked with, defaulting to `%{}` the way
  `StatifierBlocks.Edit.Targets.admits_at?/5` defaults it. A host that
  mounts the editor with a datamodel document passes the same context here
  (`StatifierBlocks.Assignability.context/1` builds it), so the two answer
  the same question.

  ## Examples

      iex> alias StatifierBlocks.{Block, Document, Palette, Plan}
      iex> wait = Block.new("core.wait", id: "blk_WAIT", config: %{"duration" => "48h"})
      iex> root = Block.new("core.sequence", id: "blk_ROOT", slots: %{"body" => [wait]})
      iex> Plan.expressible(Document.new(root, id: "doc_1"), Palette.core())
      :ok
      iex> Plan.expressible(Document.new(root, id: "doc_1"), Palette.new(%{"core.sequence" => StatifierBlocks.Core.Sequence}))
      {:no, [{:unresolved, "blk_WAIT", {:unknown_block_type, "core.wait"}}]}
  """
  @spec expressible(Document.t(), Palette.t(), Assignability.context()) ::
          :ok | {:no, [reason()]}
  def expressible(%Document{} = document, %Palette{} = palette, ctx \\ %{}) do
    admission = admission_findings(palette, document, ctx)

    reasons =
      Enum.flat_map(Document.blocks(document), fn block ->
        resolution_reasons(palette, block) ++
          placement_reasons(palette, document, block) ++
          Map.get(admission, block.id, []) ++
          unfillable_reasons(palette, document, block, ctx)
      end)

    case reasons do
      [] -> :ok
      reasons -> {:no, reasons}
    end
  end

  @doc """
  `true` exactly when `expressible/3` answers `:ok` for the same
  `document`, `palette` and `ctx`; `false` when it answers `{:no, reasons}`.

  The reasons are dropped. A host that shows an author why a document
  cannot be edited with a palette asks `expressible/3` instead.

  ## Examples

      iex> alias StatifierBlocks.{Block, Document, Palette, Plan}
      iex> wait = Block.new("core.wait", id: "blk_WAIT", config: %{"duration" => "48h"})
      iex> root = Block.new("core.sequence", id: "blk_ROOT", slots: %{"body" => [wait]})
      iex> Plan.expressible?(Document.new(root, id: "doc_1"), Palette.core())
      true
      iex> Plan.expressible?(Document.new(root, id: "doc_1"), Palette.new(%{"core.sequence" => StatifierBlocks.Core.Sequence}))
      false
  """
  @spec expressible?(Document.t(), Palette.t(), Assignability.context()) :: boolean()
  def expressible?(%Document{} = document, %Palette{} = palette, ctx \\ %{}) do
    expressible(document, palette, ctx) == :ok
  end

  # Rule 2 for every block at its own position - kind admission, and only
  # that: a `:type_mismatch` is a validation finding the editor flags rather
  # than refuses, so it is left out. Grouped by the block each finding names,
  # which a `:kind_not_admitted` carries second.
  @spec admission_findings(Palette.t(), Document.t(), Assignability.context()) ::
          %{optional(Block.id()) => [reason()]}
  defp admission_findings(palette, document, ctx) do
    case Assignability.validate(palette, document, ctx) do
      :ok ->
        %{}

      {:error, findings} ->
        findings
        |> Enum.filter(&(elem(&1, 0) == :kind_not_admitted))
        |> Enum.group_by(&elem(&1, 1), &{:not_admitted, elem(&1, 1), &1})
    end
  end

  @spec resolution_reasons(Palette.t(), Block.t()) :: [reason()]
  defp resolution_reasons(palette, %Block{} = block) do
    case Palette.resolve(palette, block) do
      {:ok, _ref, _resolved} -> []
      {:error, error} -> [{:unresolved, block.id, error}]
    end
  end

  # Rules 1 and 3 at the block's own position. The root occupies no slot.
  @spec placement_reasons(Palette.t(), Document.t(), Block.t()) :: [reason()]
  defp placement_reasons(palette, document, %Block{} = block) do
    with {:ok, [_first | _rest] = path} <- Document.fetch_path(document, block.id),
         {parent_id, slot, index} = position <- List.last(path),
         {:ok, parent} <- fetch_block(document, parent_id),
         {:ok, ref, resolved} <- Palette.resolve(palette, parent) do
      case declared_arity(ref, resolved, slot) do
        nil -> [{:slot_not_declared, block.id, {parent_id, slot}}]
        arity -> room_reasons(arity, block.id, position, index)
      end
    else
      _root_or_unresolved_parent -> []
    end
  end

  @spec room_reasons(
          BlockType.slot_arity(),
          Block.id(),
          Assignability.target(),
          non_neg_integer()
        ) ::
          [reason()]
  defp room_reasons(arity, id, position, index)
       when arity in [:exactly_one, :zero_or_one] and index >= 1,
       do: [{:no_room, id, position}]

  defp room_reasons(_arity, _id, _position, _index), do: []

  # A required slot with no child, which no palette type is admitted into.
  @spec unfillable_reasons(Palette.t(), Document.t(), Block.t(), Assignability.context()) ::
          [reason()]
  defp unfillable_reasons(palette, document, %Block{} = block, ctx) do
    case Palette.resolve(palette, block) do
      {:ok, ref, resolved} ->
        for {slot, arity, _label} <- Palette.call(ref, :slots, [resolved.config], []),
            arity in [:exactly_one, :at_least_one],
            Map.get(block.slots, slot, []) == [],
            Enum.empty?(Targets.accepted_types_at(document, palette, {block.id, slot}, nil, ctx)) do
          {:unfillable_slot, block.id, slot}
        end

      {:error, _error} ->
        []
    end
  end

  @spec declared_arity(Palette.type_ref(), Block.t(), Block.slot_name()) ::
          BlockType.slot_arity() | nil
  defp declared_arity(ref, %Block{config: config}, slot) do
    Enum.find_value(Palette.call(ref, :slots, [config], []), fn
      {^slot, arity, _label} -> arity
      _other -> nil
    end)
  end

  @spec fetch_block(Document.t(), Block.id()) :: {:ok, Block.t()} | :error
  defp fetch_block(document, id) do
    case Enum.find(Document.blocks(document), &(&1.id == id)) do
      nil -> :error
      block -> {:ok, block}
    end
  end
end
