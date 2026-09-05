defmodule StatifierBlocks.Recipe do
  @moduledoc """
  A palette entry that puts down an **arrangement** rather than a block
  (ADR-0005 clauses 1C and 2C).

  A block type answers "what is this block". A recipe answers "how do these
  blocks go together": it is handed the position the author armed and the
  document, and it returns the commands that build the arrangement. The
  caller wraps them in one `{:compound, commands}` and commits, so the
  arrangement is one gesture in and one gesture out.

  A recipe is **not** a block type. It has no `type_name`, it appears in no
  document, and nothing resolves a block against it - `StatifierBlocks.Palette`
  keeps recipes in a second map for exactly that reason, and the two maps are
  two namespaces rather than one. A recipe named `"deadline"` and a block type
  named `"deadline"` do not collide.

  ## The two callbacks

  `palette_entry/0` is `StatifierBlocks.BlockType`'s callback, in every
  particular: the same optional keys, the same total normalizers, the same
  fallback to the entry's name when a key is absent. A recipe draws in the
  palette browser the way a type draws, which is deliberate - an author
  picking a deadline is not doing a different kind of thing from an author
  picking a send.

  `insert/2` is where a recipe differs. It is **pure**: it reads the document
  rather than writing it, mints no ids beyond the ones ADR-0005 decision 2
  already requires an `:insert` to carry, and may refuse. A refusal is the
  ordinary case where the arrangement does not fit the position the author
  armed, and it is an error term, never an exception.

  ## What a recipe may reach

  Clause 3C bounds the commands `insert/2` returns to the armed position
  itself and **any slot of the block that encloses it** - the block the
  armed target names as its parent - and nothing above that. A recipe that
  could write two levels up would move blocks into a region the author is
  not looking at.

  The bound is the caller's to enforce: `insert/2` is a pure function
  answering with commands, and it is `StatifierBlocks.Recipe.within_reach?/2`
  that says whether a returned list stays inside it.
  """

  alias StatifierBlocks.{Block, BlockType, Document, Edit}

  @doc """
  The commands that build the arrangement at `target`, or a refusal.

  Called with the armed position and the document as it stands. Pure.
  """
  @callback insert(target :: Edit.target(), document :: Document.t()) ::
              {:ok, [Edit.t()]} | {:error, term()}

  @doc """
  How the recipe draws in the palette browser. ADR-0005 decision 10's map,
  unchanged.
  """
  @callback palette_entry() :: BlockType.palette_entry()

  @doc """
  Whether every command in `commands` stays inside clause 3C's bound for an
  insertion armed at `target`.

  The bound is two positions wide: the armed position itself, and any slot
  of the block that encloses it. Both are named by the same block id - the
  parent in `target` - so the check is that every command naming a position
  names that block, and that every command naming a block names one this
  compound itself inserted.

      iex> StatifierBlocks.Recipe.within_reach?({"blk_g", "body", 0}, [])
      true

      iex> block = StatifierBlocks.Block.new("core.send", id: "blk_s")
      iex> StatifierBlocks.Recipe.within_reach?(
      ...>   {"blk_g", "body", 0},
      ...>   [{:insert, {"blk_g", "interrupts", 0}, block}]
      ...> )
      true

      iex> block = StatifierBlocks.Block.new("core.send", id: "blk_s")
      iex> StatifierBlocks.Recipe.within_reach?(
      ...>   {"blk_g", "body", 0},
      ...>   [{:insert, {"blk_elsewhere", "body", 0}, block}]
      ...> )
      false
  """
  @spec within_reach?(Edit.target(), [Edit.t()]) :: boolean()
  def within_reach?({enclosing_id, _slot, _index}, commands) when is_list(commands) do
    Enum.reduce_while(commands, MapSet.new(), &reach(&1, &2, enclosing_id)) != :out_of_reach
  end

  @spec reach(Edit.t(), MapSet.t(Block.id()), Block.id()) ::
          {:cont, MapSet.t(Block.id())} | {:halt, :out_of_reach}
  defp reach({:insert, {parent_id, _slot, _index}, %Block{} = block}, minted, enclosing_id) do
    if parent_id == enclosing_id or MapSet.member?(minted, parent_id) do
      {:cont, MapSet.put(minted, block.id)}
    else
      {:halt, :out_of_reach}
    end
  end

  defp reach({tag, id, _target_or_config}, minted, _enclosing_id)
       when tag in [:move, :update_config] do
    if MapSet.member?(minted, id), do: {:cont, minted}, else: {:halt, :out_of_reach}
  end

  defp reach({:remove, id}, minted, _enclosing_id) do
    if MapSet.member?(minted, id), do: {:cont, minted}, else: {:halt, :out_of_reach}
  end

  # A declaration is not a position, and the document's datamodel is not a
  # slot of anything - so there is no reach for this command to exceed, and
  # nothing for a recipe to reach past by writing one.
  defp reach({:set_datamodel, _entries}, minted, _enclosing_id), do: {:cont, minted}

  defp reach(_other, _minted, _enclosing_id), do: {:halt, :out_of_reach}
end
