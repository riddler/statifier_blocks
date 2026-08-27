defmodule StatifierBlocks.Compiler.Attribution do
  @moduledoc """
  Resolves each element of one block's emission to the block an author
  would recognise (ADR-0004 decision 5).

  The compiler calls `stamp/2` on a block's own emission the moment
  `emit/2` returns it, **before** the children are spliced in. So each
  block stamps only what it wrote, every element ends up owned, and the
  spliced tree is total by construction rather than by a later sweep that
  would have to guess.

  ## The three rules

    * **Default.** An element belongs to the block that emitted it, with
      no config key.
    * **Role.** An element whose `id` is a state id this block minted
      (`StatifierBlocks.Compiler.StateId.unstate_id/1`) takes that role,
      and everything inside it inherits the role until another state
      changes it. That is what puts `s_blk_ENR__running`'s `<invoke>` on
      `blk_ENR` role `running` rather than on the block as a whole.
    * **Override.** `StatifierBlocks.Emission.attributed_to/2` moves an
      element and its subtree to another block and clears the role, which
      is the case decision 5 names: "attribution is a judgment, not a
      mechanism". `StatifierBlocks.Emission.from_config/2` and
      `attribute_from_config/3` set the config key that makes a finding
      the author's.

  ## An attribution has to name a block in this document

  A block type may only attribute an element to a block the compiler
  actually knows about - in practice, one of its own children, which is
  the only case decision 5 raises. `stamp/2` takes the set of block ids
  that are legitimate targets and refuses anything else, because an owner
  naming a block the document does not contain is an unresolvable entry in
  a map whose whole purpose is resolving.
  """

  alias StatifierBlocks.{Block, Emission, Provenance}
  alias StatifierBlocks.Compiler.StateId

  @doc """
  Stamps a resolved owner onto every element of `emission`.

  `known` is the set of block ids `Emission.attributed_to/2` may name -
  the emitting block and its compiled children. Descends into elements
  only; a `{:child, _}` placeholder is left alone, because the child
  stamped its own subtree when it was compiled.
  """
  @spec stamp(Emission.t(), Block.id(), MapSet.t(Block.id())) ::
          {:ok, Emission.t()} | {:error, {:unknown_attribution, Block.id()}}
  def stamp(%Emission{} = emission, block_id, %MapSet{} = known) do
    walk(emission, Provenance.owner(block_id), known)
  end

  @spec walk(Emission.node_t(), Provenance.owner(), MapSet.t(Block.id())) ::
          {:ok, Emission.node_t()} | {:error, {:unknown_attribution, Block.id()}}
  defp walk(%Emission{} = emission, inherited, known) do
    with {:ok, own} <- own_owner(emission, inherited, known),
         owner = role(own, emission),
         {:ok, children} <- walk_children(emission.children, owner, known) do
      {:ok, %{emission | owner: owner, children: children}}
    end
  end

  defp walk({:child, _block_id} = placeholder, _inherited, _known), do: {:ok, placeholder}

  @spec walk_children([Emission.node_t()], Provenance.owner(), MapSet.t(Block.id())) ::
          {:ok, [Emission.node_t()]} | {:error, {:unknown_attribution, Block.id()}}
  defp walk_children(children, owner, known) do
    children
    |> Enum.reduce_while({:ok, []}, fn child, {:ok, acc} ->
      case walk(child, owner, known) do
        {:ok, stamped} -> {:cont, {:ok, [stamped | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      {:error, reason} -> {:error, reason}
    end
  end

  # The hint the block type left, resolved against what it inherits.
  @spec own_owner(Emission.t(), Provenance.owner(), MapSet.t(Block.id())) ::
          {:ok, Provenance.owner()} | {:error, {:unknown_attribution, Block.id()}}
  defp own_owner(%Emission{owner: nil}, inherited, _known), do: {:ok, inherited}

  defp own_owner(%Emission{owner: %{block_id: nil, config_key: key}}, inherited, _known) do
    {:ok, %{inherited | config_key: key}}
  end

  defp own_owner(%Emission{owner: %{block_id: block_id, config_key: key}}, _inherited, known) do
    if MapSet.member?(known, block_id) do
      {:ok, Provenance.owner(block_id, config_key: key)}
    else
      {:error, {:unknown_attribution, block_id}}
    end
  end

  # A state whose id this owner's block minted refines the role; anything
  # else - a `<transition>`, an author's `<data id>`, an element with no id
  # at all - leaves it as inherited.
  @spec role(Provenance.owner(), Emission.t()) :: Provenance.owner()
  defp role(owner, %Emission{attributes: attributes}) do
    with {"id", id} <- List.keyfind(attributes, "id", 0),
         {:ok, {block_id, role}} <- StateId.unstate_id(id),
         true <- block_id == owner.block_id do
      %{owner | role: role}
    else
      _not_this_blocks_state -> owner
    end
  end
end
