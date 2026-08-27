defmodule StatifierBlocks.Edit do
  @moduledoc """
  The editor's command algebra. Pure, serializable, invertible - and
  deliberately free of any UI framework dependency, so it is tested with
  no editor shell present at all (ADR-0005 decision 1).

  `apply/2` takes no palette (ADR-0005 decision 3's spec), so it is a purely
  **structural** rewrite: it never consults a block-type registry, never
  runs `validate_config/1`, and never checks whether a slot is declared.
  That gate lives one layer up, in `check_config/3` and `Edit.History`.

  ## The four structural rules

  1. **A target's index is read against the slot's current children**,
     where an absent slot key means `[]`. Valid indices are
     `0..length(children)` inclusive; anything else is
     `{:error, {:index_out_of_range, target}}`.
  2. **An absent slot key is created by an insert or a move into it.** This
     is not optional: a declared slot with no children carries no key in
     the document's `slots` map (`Document.to_json/1` omits it, ADR-0001
     decision 8), so refusing to create it would break the commonest drop
     there is.
  3. **A remove prunes a slot key that it empties.** Symmetric with rule 2
     and with canonical JSON's omission of empty slots, and it is what
     makes `apply(apply(d, e), inverse) == d` hold as **struct equality**,
     not merely as equal canonical bytes.
  4. **`:move` reads its target index against the slot with the moved
     block already removed** (decision 4). Concretely: detach, then
     insert. The inverse of a move from `{P, s, i}` to `{Q, t, j}` is a
     move to `{P, s, i}` - the same `i`, because removing at `i` and
     re-inserting at `i` in the shortened list is the identity, and that
     is true whether or not `P == Q and s == t`.

  ## The four inverses

  | Command | Inverse |
  |---|---|
  | `{:insert, target, block}` | `{:remove, block.id}` |
  | `{:remove, id}` | `{:insert, original_target, detached_subtree}` |
  | `{:move, id, target}` | `{:move, id, original_target}` |
  | `{:update_config, id, config}` | `{:update_config, id, previous_config}` |

  ## The deliberate widening

  The record's typespec block lists four error arms. This module ships two
  more, and neither contradicts a decision - each names a case the record's
  list does not enumerate:

    * **`{:duplicate_block_id, Block.id()}`** - an `:insert` whose block (or
      whose subtree) carries an id already present in the document.
      ADR-0001 decision 1 makes document-wide id uniqueness an invariant
      and `Document.validate/1` enforces it, so `apply/2` must refuse
      rather than produce a document that fails its own validator. The
      spelling matches `Decode`'s existing `{:duplicate_block_id, id}`.
    * **`{:cannot_remove_root, Block.id()}`** - a `:remove` or `:move`
      naming the document root. The root occupies no slot, so there is no
      position to detach it from and no inverse to write.
      `{:no_such_block, id}` would be a lie about a block that plainly
      exists.

  The record's own `{:no_such_slot, block_id, slot_name}` arm is given the
  one meaning left to it once rule 2 above allows slot creation: a target
  whose slot name is not a usable slot key - not a binary, or empty.
  Commands are serializable values that can arrive from a replayed log, so
  this is a real arm, not a dead one.
  """

  alias StatifierBlocks.{Block, Document}

  @typedoc "A position, not a block. ADR-0001 decision 5's path element."
  @type target :: {Block.id(), Block.slot_name(), non_neg_integer()}

  @typedoc """
  Ids in an `:insert`ed block are already minted, which is what keeps the
  command replayable (ADR-0005 decision 2).
  """
  @type t ::
          {:insert, target(), Block.t()}
          | {:remove, Block.id()}
          | {:move, Block.id(), target()}
          | {:update_config, Block.id(), Block.config()}

  @doc """
  Applies one command, returning the new document and the command that
  undoes it. Total: refuses rather than raises. See the moduledoc's four
  structural rules and four inverses.
  """
  @spec apply(Document.t(), t()) ::
          {:ok, Document.t(), t()}
          | {:error, {:no_such_block, Block.id()}}
          | {:error, {:no_such_slot, Block.id(), Block.slot_name()}}
          | {:error, {:index_out_of_range, target()}}
          | {:error, {:would_cycle, Block.id()}}
          | {:error, {:duplicate_block_id, Block.id()}}
          | {:error, {:cannot_remove_root, Block.id()}}
  def apply(%Document{} = document, {:insert, {parent_id, slot_name, index}, %Block{} = block}) do
    target = {parent_id, slot_name, index}

    with :ok <- check_slot_name(parent_id, slot_name),
         {:ok, parent} <- find_block(document, parent_id),
         :ok <- check_no_duplicates(document, block),
         :ok <- check_index(parent, slot_name, index, target) do
      new_document =
        replace_at_id(document, parent_id, insert_child(parent, slot_name, index, block))

      {:ok, new_document, {:remove, block.id}}
    end
  end

  def apply(%Document{} = document, {:remove, id}) do
    with {:ok, _block} <- find_block(document, id),
         :ok <- check_not_root(document, id) do
      {new_document, detached, original_target} = detach(document, id)
      {:ok, new_document, {:insert, original_target, detached}}
    end
  end

  def apply(%Document{} = document, {:move, id, {to_parent, to_slot, to_index} = to_target}) do
    with {:ok, moved} <- find_block(document, id),
         :ok <- check_not_root(document, id),
         :ok <- check_not_cycle(moved, to_parent),
         :ok <- check_slot_name(to_parent, to_slot) do
      {without, detached, original_target} = detach(document, id)

      with {:ok, parent} <- find_block(without, to_parent),
           :ok <- check_index(parent, to_slot, to_index, to_target) do
        new_parent = insert_child(parent, to_slot, to_index, detached)
        final_document = replace_at_id(without, to_parent, new_parent)
        {:ok, final_document, {:move, id, original_target}}
      end
    end
  end

  def apply(%Document{} = document, {:update_config, id, config}) do
    with {:ok, block} <- find_block(document, id) do
      new_document = replace_at_id(document, id, %{block | config: config})
      {:ok, new_document, {:update_config, id, block.config}}
    end
  end

  @spec check_slot_name(Block.id(), term()) ::
          :ok | {:error, {:no_such_slot, Block.id(), term()}}
  defp check_slot_name(_parent_id, slot_name) when is_binary(slot_name) and slot_name != "",
    do: :ok

  defp check_slot_name(parent_id, slot_name), do: {:error, {:no_such_slot, parent_id, slot_name}}

  @spec check_not_root(Document.t(), Block.id()) ::
          :ok | {:error, {:cannot_remove_root, Block.id()}}
  defp check_not_root(%Document{root: %Block{id: id}}, id),
    do: {:error, {:cannot_remove_root, id}}

  defp check_not_root(%Document{}, _id), do: :ok

  @spec check_not_cycle(Block.t(), Block.id()) :: :ok | {:error, {:would_cycle, Block.id()}}
  defp check_not_cycle(%Block{} = moved, to_parent) do
    if MapSet.member?(subtree_ids(moved), to_parent) do
      {:error, {:would_cycle, moved.id}}
    else
      :ok
    end
  end

  @spec check_no_duplicates(Document.t(), Block.t()) ::
          :ok | {:error, {:duplicate_block_id, Block.id()}}
  defp check_no_duplicates(%Document{} = document, %Block{} = inserted) do
    existing_ids = document |> Document.blocks() |> MapSet.new(& &1.id)

    inserted
    |> subtree_ids()
    |> Enum.find(&MapSet.member?(existing_ids, &1))
    |> case do
      nil -> :ok
      dup_id -> {:error, {:duplicate_block_id, dup_id}}
    end
  end

  @spec check_index(Block.t(), Block.slot_name(), term(), target()) ::
          :ok | {:error, {:index_out_of_range, target()}}
  defp check_index(%Block{} = parent, slot_name, index, target) do
    children = Map.get(parent.slots, slot_name, [])

    if is_integer(index) and index >= 0 and index <= length(children) do
      :ok
    else
      {:error, {:index_out_of_range, target}}
    end
  end

  @spec find_block(Document.t(), Block.id()) ::
          {:ok, Block.t()} | {:error, {:no_such_block, Block.id()}}
  defp find_block(%Document{} = document, id) do
    case Enum.find(Document.blocks(document), &(&1.id == id)) do
      nil -> {:error, {:no_such_block, id}}
      block -> {:ok, block}
    end
  end

  @spec subtree_ids(Block.t()) :: MapSet.t(Block.id())
  defp subtree_ids(%Block{id: id, slots: slots}) do
    slots
    |> Map.values()
    |> List.flatten()
    |> Enum.reduce(MapSet.new([id]), fn child, acc -> MapSet.union(acc, subtree_ids(child)) end)
  end

  @spec insert_child(Block.t(), Block.slot_name(), non_neg_integer(), Block.t()) :: Block.t()
  defp insert_child(%Block{} = parent, slot_name, index, %Block{} = child) do
    children = Map.get(parent.slots, slot_name, [])
    {before, rest} = Enum.split(children, index)
    %{parent | slots: Map.put(parent.slots, slot_name, before ++ [child] ++ rest)}
  end

  # Replaces the block carrying `id` (root or nested) with `new_block`. `id`
  # is always a block already present in `document`, found via its own
  # `apply/2` clause above, so `fetch_path/2` cannot return `:error` here.
  @spec replace_at_id(Document.t(), Block.id(), Block.t()) :: Document.t()
  defp replace_at_id(%Document{root: root} = document, id, new_block) do
    {:ok, path} = Document.fetch_path(document, id)
    %{document | root: update_at_path(root, path, fn _old -> new_block end)}
  end

  @spec update_at_path(Block.t(), Document.path(), (Block.t() -> Block.t())) :: Block.t()
  defp update_at_path(%Block{} = block, [], fun), do: fun.(block)

  defp update_at_path(%Block{slots: slots} = block, [{_parent_id, slot_name, index} | rest], fun) do
    children = Map.fetch!(slots, slot_name)
    {before, [child | after_children]} = Enum.split(children, index)
    new_child = update_at_path(child, rest, fun)
    %{block | slots: Map.put(slots, slot_name, before ++ [new_child] ++ after_children)}
  end

  # Detaches the block carrying `id` from `document`, pruning the slot key
  # it emptied (rule 3). Returns the resulting document, the detached
  # subtree, and the `target()` it used to occupy (its inverse's target).
  @spec detach(Document.t(), Block.id()) :: {Document.t(), Block.t(), target()}
  defp detach(%Document{root: root} = document, id) do
    {:ok, path} = Document.fetch_path(document, id)
    {new_root, detached, original_target} = remove_at_path(root, path)
    {%{document | root: new_root}, detached, original_target}
  end

  @spec remove_at_path(Block.t(), Document.path()) :: {Block.t(), Block.t(), target()}
  defp remove_at_path(%Block{slots: slots} = block, [{_parent_id, slot_name, index}]) do
    children = Map.fetch!(slots, slot_name)
    {before, [detached | after_children]} = Enum.split(children, index)
    new_children = before ++ after_children

    new_slots =
      if new_children == [],
        do: Map.delete(slots, slot_name),
        else: Map.put(slots, slot_name, new_children)

    {%{block | slots: new_slots}, detached, {block.id, slot_name, index}}
  end

  defp remove_at_path(%Block{slots: slots} = block, [{_parent_id, slot_name, index} | rest]) do
    children = Map.fetch!(slots, slot_name)
    {before, [child | after_children]} = Enum.split(children, index)
    {new_child, detached, original_target} = remove_at_path(child, rest)
    new_children = before ++ [new_child] ++ after_children
    {%{block | slots: Map.put(slots, slot_name, new_children)}, detached, original_target}
  end
end
