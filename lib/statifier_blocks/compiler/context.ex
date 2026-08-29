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

  ## The conventional `<final>` is the default outcome's final

  Decision 2 makes every block's state compound with a `<final>` child, so
  that entering the final raises `done.state.<state id>` and a parent needs
  nothing but the child's id to wire it. Under ADR-0004's outcome
  amendment that child is the **default outcome's** final: a block type
  that declares no outcomes has exactly one, named `"done"`, so the
  conventional final is `outcome_id(ctx, "done")` and lives in the
  reserved `o_` namespace below rather than under an ordinary role.
  `done_id/1` is its minting function and the core vocabulary uses it
  uniformly. A block whose state can never reach a final is a block no
  parent can sequence after.

  ## The `o_` role namespace is reserved

  A block type with more than one way to finish emits one `<final>` per
  outcome it reaches (ADR-0004's outcome amendment). Those finals live in
  the role namespace under the prefix `"o_"`, they are minted only by
  `outcome_id/2`, and `role_id/2` refuses the prefix outright - without the
  reservation an outcome final and a hand-minted role could produce the
  same id and provenance could not say which it was.
  """

  alias StatifierBlocks.{Block, Document}
  alias StatifierBlocks.Compiler.StateId

  # ADR-0004's outcome amendment reserves this role prefix: an outcome
  # final is minted only by `outcome_id/2`, and `role_id/2` refuses it, so
  # an outcome final and a hand-minted role can never produce the same id.
  # Read from `StateId`, which owns the derivation the prefix is part of.
  @outcome_prefix StateId.outcome_prefix()

  @typedoc """
  One of a child's declared outcomes: its name, the `<final>` its block
  compiled that outcome to, and the event entering that final raises
  (ADR-0004's outcome amendment, 2e).
  """
  @type outcome :: %{
          name: String.t(),
          state_id: StateId.t(),
          done_event: String.t()
        }

  @typedoc """
  Everything a parent may know about one compiled child: its block id, the
  state it compiled to, the event that state raises when it is done, and
  its declared outcomes.

  `done_event` keeps its accepted meaning - `done.state.<state id>`, the
  "finished, do not care how" signal - so a structural parent written
  before outcomes existed still compiles and still behaves identically.
  `outcomes` is in the type's declaration order, is always non-empty, and
  holds exactly one entry, `done`, for a type that declared none.
  """
  @type child_summary :: %{
          block_id: Block.id(),
          state_id: StateId.t(),
          done_event: String.t(),
          outcomes: [outcome()]
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

  `summary/1` is the ordinary case: a child whose type declares no
  outcomes, which is the single default outcome named `"done"`. The
  default lives in one place - this delegation - so a caller that does not
  know a child's module still produces a summary of the same shape.
  """
  @spec summary(Block.id()) :: child_summary()
  def summary(block_id), do: summary(block_id, ["done"])

  @doc """
  The summary of one compiled child whose type declared `outcome_names`,
  in declaration order (ADR-0004's outcome amendment, 2e).

  Order is preserved and never sorted: it is decision 6's byte determinism
  that depends on it. Every entry's `state_id` and `done_event` are
  computed against the **child's** block id through `outcome_id/2` and
  `outcome_event/2`, so a summary can name only ids and events the child
  itself would mint.

  A name that is not role-shaped is dropped rather than raising, which
  keeps this function total. It is unreachable in the compiler: the Emit
  stage refuses a malformed or duplicated outcome name with an
  `:invalid_outcome` finding on the misbehaving block's own pass, before
  any parent sees it in a summary.
  """
  @spec summary(Block.id(), [String.t()]) :: child_summary()
  def summary(block_id, outcome_names) when is_list(outcome_names) do
    state_id = StateId.state_id(block_id)

    %{
      block_id: block_id,
      state_id: state_id,
      done_event: StateId.done_event(state_id),
      outcomes: Enum.flat_map(outcome_names, &outcome_summary(block_id, &1))
    }
  end

  @spec outcome_summary(Block.id(), String.t()) :: [outcome()]
  defp outcome_summary(block_id, name) do
    with {:ok, id} <- outcome_id_for(block_id, name),
         {:ok, event} <- outcome_event_for(block_id, name) do
      [%{name: name, state_id: id, done_event: event}]
    else
      {:error, _not_an_outcome} -> []
    end
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

  A role beginning with `"o_"` is refused with `{:error, {:reserved_role,
  block_id, role}}`: that namespace belongs to outcome finals and
  `outcome_id/2` is the only way into it.
  """
  @spec role_id(t(), StateId.role()) ::
          {:ok, StateId.t()}
          | {:error, {:invalid_role, Block.id(), StateId.role()}}
          | {:error, {:reserved_role, Block.id(), StateId.role()}}
  def role_id(%__MODULE__{block_id: block_id}, @outcome_prefix <> _rest = role),
    do: {:error, {:reserved_role, block_id, role}}

  def role_id(%__MODULE__{block_id: block_id}, role), do: StateId.state_id(block_id, role)

  @doc """
  The id of this block's conventional `<final>` child - the **default
  outcome's** final, `outcome_id(ctx, "done")` with the error arm
  discharged, since `"done"` is a literal outcome name this module knows
  is valid.

  Under ADR-0004's outcome amendment (2b) that id is
  `"s_" <> block_id <> "__o_done"`. It moved there from the ad-hoc role
  `"done"` the core vocabulary used before, which is what makes the
  amendment move compiled bytes for every document. The name and arity are
  unchanged, so no block type had to be edited to follow it.
  """
  @spec done_id(t()) :: StateId.t()
  def done_id(%__MODULE__{block_id: block_id}) do
    {:ok, id} = outcome_id_for(block_id, "done")
    id
  end

  @doc """
  The `done.state` event this block's state raises, for a block type that
  needs to name its own completion.
  """
  @spec done_event(t()) :: String.t()
  def done_event(%__MODULE__{state_id: state_id}), do: StateId.done_event(state_id)

  @doc """
  Mints the `<final>` id for one declared outcome (ADR-0004's outcome
  amendment, 2b):

      outcome_id(block_id, outcome) = "s_" <> block_id <> "__o_" <> outcome

  This is the **only** home for an outcome final's id. A block type with
  more than one way to finish emits one `<final>` per outcome it reaches
  and mints every one of them here rather than by string concatenation, for
  decision 3's reason: the ids stay injective, `unstate_id/1` still inverts
  them, and provenance can still say which block a final came from.

  `outcome` is a name in the role shape - `~r/\\A[a-z][a-z0-9_]*\\z/`, no
  `"__"` - and one that is not is refused with `{:error, {:invalid_outcome,
  block_id, outcome}}` rather than raising.

  > #### The tagged return is the ratified shape {: .info}
  >
  > 2e's original sketch wrote the signature as returning a bare
  > `String.t()`. It cannot, and stay honest: 2f requires an
  > `:invalid_outcome` Emit finding for a name failing the role shape, and
  > decision 1 forbids `emit/2` raising, so the error has to be reachable
  > through a return value. The `{:ok, _}` arm carries exactly the id 2e
  > names. 2e was amended to this signature on 2026-08-29 (operator
  > ruling); see its "Amended 2026-08-29" paragraph.
  """
  @spec outcome_id(t(), String.t()) ::
          {:ok, StateId.t()} | {:error, {:invalid_outcome, Block.id(), String.t()}}
  def outcome_id(%__MODULE__{block_id: block_id}, outcome),
    do: outcome_id_for(block_id, outcome)

  # The block-id-level half of `outcome_id/2`, shared with `summary/2`,
  # which builds an outcome entry for a **child** and so has no context of
  # its own to mint through.
  @spec outcome_id_for(Block.id(), String.t()) ::
          {:ok, StateId.t()} | {:error, {:invalid_outcome, Block.id(), String.t()}}
  defp outcome_id_for(block_id, outcome) do
    with true <- StateId.role?(outcome),
         {:ok, id} <- StateId.state_id(block_id, @outcome_prefix <> outcome) do
      {:ok, id}
    else
      _not_an_outcome -> {:error, {:invalid_outcome, block_id, outcome}}
    end
  end

  @doc """
  The completion event a parent wires on for one outcome:
  `done.outcome.<state id>.<outcome>` (ADR-0004's outcome amendment, 2c).

  The tag rides on an event rather than on the final's identity, because
  `done.state.<state id>` is generated whichever final is entered and a
  parent can therefore not see which one it was. A parent that does not
  care wires the prefix `done.outcome.<state id>` and matches every outcome
  of that child; one that discriminates names the full event. Refuses a
  malformed outcome name for the same reason `outcome_id/2` does.
  """
  @spec outcome_event(t(), String.t()) ::
          {:ok, String.t()} | {:error, {:invalid_outcome, Block.id(), String.t()}}
  def outcome_event(%__MODULE__{block_id: block_id}, outcome),
    do: outcome_event_for(block_id, outcome)

  # The block-id-level half of `outcome_event/2`, shared with `summary/2`
  # for `outcome_id_for/2`'s reason.
  @spec outcome_event_for(Block.id(), String.t()) ::
          {:ok, String.t()} | {:error, {:invalid_outcome, Block.id(), String.t()}}
  defp outcome_event_for(block_id, outcome) do
    if StateId.role?(outcome) do
      {:ok, StateId.outcome_event(StateId.state_id(block_id), outcome)}
    else
      {:error, {:invalid_outcome, block_id, outcome}}
    end
  end
end
