defmodule StatifierBlocks.Compiler.Context do
  @moduledoc """
  What a block type is entitled to know while emitting, and nothing more
  (ADR-0004 decision 4).

  The compiler walks the document bottom-up and calls `emit/2` with the
  children already compiled. The context it passes carries four things:

    * `block_id` and `state_id` - the block's own, precomputed;
    * `children` - slot name to the ordered list of child summaries, each
      carrying only `block_id`, `state_id` and `done_event`. A child's
      emitted SCXML is deliberately absent: a parent that could read it
      would be a parent that could depend on it, and decision 2 exists to
      prevent that;
    * `document_id` - for the rare type that names the document in a send
      target;
    * `role_id/2` - decision 3's minting function, reached through this
      struct so the compiler owns the namespacing.

  The palette is deliberately absent. A block type resolving another block
  type would be a block type compiling its own children, which is the
  compiler's job, and would make `emit/2`'s purity depend on a value it did
  not receive.

  ## The `"done"` role is conventional, not reserved

  Decision 2 makes every block's state compound with a `<final>` child, so
  that entering the final raises `done.state.<state id>` and a parent needs
  nothing but the child's id to wire it. `done_id/1` mints that child's id
  under the role `"done"`; the core vocabulary uses it uniformly. Nothing
  stops a host type from minting the same role itself - it is the same id -
  or from using a different one, so long as some final child is reachable.
  A block whose state can never reach a final is a block no parent can
  sequence after.
  """

  alias StatifierBlocks.{Block, Document}
  alias StatifierBlocks.Compiler.StateId

  @typedoc """
  Everything a parent may know about one compiled child: its block id, the
  state it compiled to, and the event that state raises when it is done.
  """
  @type child_summary :: %{
          block_id: Block.id(),
          state_id: StateId.t(),
          done_event: String.t()
        }

  @type t :: %__MODULE__{
          block_id: Block.id(),
          state_id: StateId.t(),
          document_id: Document.id(),
          children: %{optional(Block.slot_name()) => [child_summary()]}
        }

  @enforce_keys [:block_id, :state_id, :document_id]
  defstruct [:block_id, :state_id, :document_id, children: %{}]

  @doc """
  Builds the context for `block_id` under `document_id`, with `children`
  keyed by slot name in the order `slots/1` declared them.
  """
  @spec new(Block.id(), Document.id(), %{
          optional(Block.slot_name()) => [child_summary()]
        }) :: t()
  def new(block_id, document_id, children \\ %{}) do
    %__MODULE__{
      block_id: block_id,
      state_id: StateId.state_id(block_id),
      document_id: document_id,
      children: children
    }
  end

  @doc """
  The summary of one compiled child, for a parent building a summary of its
  own or wiring a transition to a sibling.
  """
  @spec summary(Block.id()) :: child_summary()
  def summary(block_id) do
    state_id = StateId.state_id(block_id)
    %{block_id: block_id, state_id: state_id, done_event: StateId.done_event(state_id)}
  end

  @doc """
  The ordered child summaries in `slot`, or `[]` for a slot with no
  children - including one the document never wrote.
  """
  @spec children(t(), Block.slot_name()) :: [child_summary()]
  def children(%__MODULE__{children: children}, slot), do: Map.get(children, slot, [])

  @doc """
  Mints the id of an auxiliary state this block emits **inside its own
  state**, under `role` (decision 3).

  Returns `{:error, {:invalid_role, block_id, role}}` for a role the
  compiler could not invert; a block type that passes a literal role never
  sees that arm, and one that builds a role from config handles it as the
  ordinary Emit finding it is.
  """
  @spec role_id(t(), StateId.role()) ::
          {:ok, StateId.t()} | {:error, {:invalid_role, Block.id(), StateId.role()}}
  def role_id(%__MODULE__{block_id: block_id}, role), do: StateId.state_id(block_id, role)

  @doc """
  The id of this block's conventional `<final>` child - `role_id(ctx,
  "done")` with the error arm discharged, since `"done"` is a literal role
  this module knows is valid.
  """
  @spec done_id(t()) :: StateId.t()
  def done_id(%__MODULE__{block_id: block_id}) do
    {:ok, id} = StateId.state_id(block_id, "done")
    id
  end

  @doc """
  The `done.state` event this block's state raises, for a block type that
  needs to name its own completion.
  """
  @spec done_event(t()) :: String.t()
  def done_event(%__MODULE__{state_id: state_id}), do: StateId.done_event(state_id)
end
