defmodule StatifierBlocks.Compiler.StateId do
  @moduledoc """
  State ids derived from block ids by a pure function (ADR-0004 decision 3).

      state_id(block_id)       = "s_" <> block_id
      state_id(block_id, role) = "s_" <> block_id <> "__" <> role

  A block id is already stable, document-unique, opaque and never reused
  (ADR-0001 decision 3), so a state id derived from it inherits all of that
  *per block* rather than per document: editing one block's config, or
  inserting a step at the top of a sequence, changes the ids of nothing
  else. That is what keeps a stored provenance map valid and a publish diff
  readable.

  ## Roles

  A `role` is a short, block-type-chosen local name for an auxiliary state
  a block emits **inside its own state**. Roles are minted here rather than
  by string concatenation inside a block type so this module owns the
  namespacing, and it refuses any role it could not invert:

    * it must match `~r/\\A[a-z][a-z0-9_]*\\z/`, and
    * it must not contain `__`, which is the separator itself.

  The second rule is not implied by the first - `a__b` matches the pattern -
  and without it `unstate_id/1` would have two readings of the same string.

  ## The three properties

    * **Uniqueness.** Block ids are document-unique, a `blk_`-prefixed UXID
      contains no `__`, and a role cannot either, so no two generated ids
      collide whatever a block type does. The `s_` prefix additionally keeps
      generated state ids out of the namespace an author's own config writes
      into, which matters because statifier checks uniqueness over *all*
      `ID`-typed attributes in one set.
    * **Invertibility.** `state_id/1` and `state_id/2` are injective and
      `unstate_id/1` inverts them without consulting the provenance map, so
      a human reading generated SCXML in a diff can still see which block a
      state came from.
    * **Totality.** Every generated state carries an id. Statifier permits
      nameless states, but `Statifier.Position.export/1` refuses an export
      containing one (`{:error, {:unnameable_states, indexes}}`) and
      `Statifier.active_leaf_states/1` drops it, so this package emits none.
  """

  alias StatifierBlocks.Block

  @prefix "s_"
  @separator "__"
  @role ~r/\A[a-z][a-z0-9_]*\z/

  @typedoc "A block-type-chosen local name for an auxiliary state."
  @type role :: String.t()

  @typedoc ~S(A generated SCXML state id: `"s_" <> block_id`, optionally `"__" <> role`.)
  @type t :: String.t()

  @doc ~S"""
  The state id of the state `block_id`'s block compiles to.

      iex> StatifierBlocks.Compiler.StateId.state_id("blk_ROOT")
      "s_blk_ROOT"
  """
  @spec state_id(Block.id()) :: t()
  def state_id(block_id) when is_binary(block_id), do: @prefix <> block_id

  @doc ~S"""
  The state id of an auxiliary state `block_id`'s block mints under `role`.

  Returns `{:error, {:invalid_role, block_id, role}}` rather than raising
  for a role this module cannot invert - an ordinary Emit-stage finding,
  since `emit/2` is a total function like every other callback.

      iex> StatifierBlocks.Compiler.StateId.state_id("blk_SEQ", "done")
      {:ok, "s_blk_SEQ__done"}

      iex> StatifierBlocks.Compiler.StateId.state_id("blk_SEQ", "a__b")
      {:error, {:invalid_role, "blk_SEQ", "a__b"}}
  """
  @spec state_id(Block.id(), role()) :: {:ok, t()} | {:error, {:invalid_role, Block.id(), role()}}
  def state_id(block_id, role) when is_binary(block_id) do
    if role?(role) do
      {:ok, @prefix <> block_id <> @separator <> role}
    else
      {:error, {:invalid_role, block_id, role}}
    end
  end

  @doc ~S"""
  Whether `role` is a role this module will mint an id for.

      iex> StatifierBlocks.Compiler.StateId.role?("lane_capture")
      true

      iex> StatifierBlocks.Compiler.StateId.role?("Done")
      false
  """
  @spec role?(term()) :: boolean()
  def role?(role) when is_binary(role) do
    Regex.match?(@role, role) and not String.contains?(role, @separator)
  end

  def role?(_role), do: false

  @doc ~S"""
  Inverts `state_id/1` and `state_id/2`.

      iex> StatifierBlocks.Compiler.StateId.unstate_id("s_blk_SEQ")
      {:ok, {"blk_SEQ", nil}}

      iex> StatifierBlocks.Compiler.StateId.unstate_id("s_blk_SEQ__done")
      {:ok, {"blk_SEQ", "done"}}

      iex> StatifierBlocks.Compiler.StateId.unstate_id("blk_SEQ")
      :error
  """
  @spec unstate_id(t()) :: {:ok, {Block.id(), role() | nil}} | :error
  def unstate_id(@prefix <> rest) when rest != "" do
    case String.split(rest, @separator, parts: 2) do
      [block_id] -> {:ok, {block_id, nil}}
      [block_id, role] -> {:ok, {block_id, role}}
    end
  end

  def unstate_id(_state_id), do: :error

  @doc ~S"""
  The `done.state` event a compound state raises when it enters a `<final>`
  child (ADR-0004 decision 2). This is the whole of what a parent needs to
  know about a child it did not compile.

      iex> StatifierBlocks.Compiler.StateId.done_event("s_blk_SEQ")
      "done.state.s_blk_SEQ"
  """
  @spec done_event(t()) :: String.t()
  def done_event(state_id) when is_binary(state_id), do: "done.state." <> state_id
end
