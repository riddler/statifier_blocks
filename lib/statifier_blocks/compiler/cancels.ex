defmodule StatifierBlocks.Compiler.Cancels do
  @moduledoc """
  The scope-shaped cancel: a delayed send armed by a child block is
  cancelled in the `<onexit>` of the state that armed it (ADR-0004's
  2026-08-29 amendment, "a delayed send's cancel, emitted in the arming
  state's `<onexit>`").

  ## Which state is "the state that armed the send"

  The **nearest enclosing scope state**, which under ADR-0004 decision 2
  is the send block's *parent* block's state: one block compiles to
  exactly one state, and a child's state is spliced inside its parent's,
  so the closest state that contains the send and is not the send's own is
  the parent's. For a `core.send` sitting in a `core.sequence` body that
  is the sequence; for one nested a sequence deep inside a `core.group`
  it is the sequence, not the group, because the sequence is nearer. That
  is the operator's 2026-08-29 ruling on the shape - the send lives as long
  as the scope that meant it to - and it is what the record already says
  for a rail ("the enclosing group for a rail").

  A send block that is the document's root has no enclosing scope and
  therefore no cancel. Nothing above it is a state this package emits.

  ## How a scope learns what its children armed

  Not through the child's SCXML, which ADR-0004 decision 4 keeps out of a
  parent's reach, and not through a new `emit/2` callback either. Through
  the **send id**, which is a state id in disguise: ADR-0002's amendment
  of the same date fixes it as `<the send block's state id>__send`, and
  `StatifierBlocks.Compiler.StateId.unstate_id/1` inverts that back to
  `{block id, "send"}` exactly. So this pass reads each direct child's
  compiled emission, keeps every `<send>` whose `id` inverts to *that
  child's own block id* under the reserved role `"send"`, and
  emits one `<cancel sendid="...">` per hit in the parent's `<onexit>`.

  Three properties follow from reading the id rather than the emitter:

    * **A grandchild's send is not this scope's.** Its id names the
      grandchild, so it fails the direct-child test here and was already
      cancelled by the nearer scope on its own pass. No send is cancelled
      twice and none is missed.
    * **`core.wait`'s timer is untouched.** It mints its own delayed
      `<send>` under the role `"timer"` (a wait's timer is bounded by the
      wait's own state, which is why it has never leaked), so it does not
      match and no `core.wait` moves a byte.
    * **A host block type opts in by minting the same role.** Nothing here
      names `StatifierBlocks.Core.Send`, so a host type that arms a
      cancellable delayed send gets the scope cancel by using
      `role_id/2` the way `core.send` does.

  Only a send carrying a `delay` is cancelled. An undelayed `<send>` is on
  the external queue before the enclosing state can be exited, so a
  `<cancel>` for it would be bytes that can never match a pending timer.

  ## Determinism

  Children are visited in slot-declaration order and then document order -
  the order `StatifierBlocks.Compiler` already hands them over - and the
  cancels are emitted in that order, so ADR-0004 decision 6 holds. The
  `<onexit>` is prepended to the scope state's children, ahead of the
  transitions the type wrote, which is one fixed position rather than a
  position that depends on what the type emitted. A block type that wrote
  an `<onexit>` of its own keeps it; SCXML runs both.

  The pass runs on the parent's own emission *before*
  `StatifierBlocks.Compiler.Attribution` stamps it, so the `<onexit>` and
  its cancels are owned by the scope block and carry the scope state's
  role, which is the block an author would recognise: the cancel is a
  consequence of where the send sits in that scope, not of the send block
  itself.
  """

  alias StatifierBlocks.{Block, Emission}
  alias StatifierBlocks.Compiler.StateId

  @role "send"

  # The elements a `<onexit>` may hang off. ADR-0004 decision 2 makes every
  # block's emission a `<state>`, so the other arm is unreachable in this
  # package; it stays total rather than raising on a host type that returns
  # something else, in the same spirit as decision 1's "a finding, never a
  # raise".
  @scopes ["state", "parallel"]

  @doc """
  The role a cancellable armed send's id carries: `"send"`.

  `StatifierBlocks.Core.Send` mints its send id with
  `StatifierBlocks.Compiler.Context.role_id(context, armed_role())`, and
  this module reads it back, so the two halves of the convention name one
  string in one place.
  """
  @spec armed_role() :: String.t()
  def armed_role, do: @role

  @doc """
  Adds the scope's `<onexit>` cancels to `emission`, the emission of the
  block that `compiled_children` are the direct children of.

  `compiled_children` is the `{block id, emission}` list the compiler
  already holds after emitting the children. Returns `emission` unchanged
  when no direct child armed a delayed send - which is every scope in
  every document that contains no `core.send`, so no existing chart moves
  a byte.
  """
  @spec arm(Emission.t(), [{Block.id(), Emission.t()}]) :: Emission.t()
  def arm(%Emission{} = emission, compiled_children) when is_list(compiled_children) do
    case Enum.flat_map(compiled_children, fn {id, child} -> armed_sends(child, id) end) do
      [] -> emission
      ids -> onexit(emission, Enum.uniq(ids))
    end
  end

  @spec onexit(Emission.t(), [String.t()]) :: Emission.t()
  defp onexit(%Emission{name: name} = emission, ids) when name in @scopes do
    cancels = Enum.map(ids, &Emission.element("cancel", [{"sendid", &1}]))

    %{emission | children: [Emission.element("onexit", [], cancels) | emission.children]}
  end

  defp onexit(emission, _ids), do: emission

  # Every delayed `<send>` under `emission` whose id names `block_id` under
  # the reserved role - which is to say, the ones `block_id` armed in its
  # own state rather than the ones its own descendants armed.
  @spec armed_sends(Emission.node_t(), Block.id()) :: [String.t()]
  defp armed_sends(%Emission{} = emission, block_id) do
    own = if armed?(emission, block_id), do: [send_id(emission)], else: []

    own ++ Enum.flat_map(emission.children, &armed_sends(&1, block_id))
  end

  defp armed_sends({:child, _child_id}, _block_id), do: []

  @spec armed?(Emission.t(), Block.id()) :: boolean()
  defp armed?(%Emission{name: "send", attributes: attributes}, block_id) do
    with {"id", id} <- List.keyfind(attributes, "id", 0),
         true <- List.keymember?(attributes, "delay", 0),
         {:ok, {^block_id, @role}} <- StateId.unstate_id(id) do
      true
    else
      _not_an_armed_send -> false
    end
  end

  defp armed?(%Emission{}, _block_id), do: false

  @spec send_id(Emission.t()) :: String.t()
  defp send_id(%Emission{attributes: attributes}) do
    {"id", id} = List.keyfind(attributes, "id", 0)
    id
  end
end
