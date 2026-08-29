defmodule StatifierBlocks.Compiler.Cancels do
  @moduledoc """
  The scope-shaped cancel: a delayed send armed by a child block is
  cancelled in the `<onexit>` of the state that armed it (ADR-0004's
  2026-08-29 amendment, "a delayed send's cancel, emitted in the arming
  state's `<onexit>`").

  ## Which state is "the state that armed the send"

  The **nearest enclosing scope state**: the innermost `<state>` in the
  parent's own emission that contains the child, whichever state that
  turns out to be.

  For most block types that is the parent block's own state, because
  ADR-0004 decision 2 gives one block exactly one state and a child's
  emission is spliced directly inside it: a `core.send` in a
  `core.sequence` body is cancelled by the sequence, and one nested a
  sequence deep inside a `core.group` is cancelled by the sequence rather
  than the group, because the sequence is nearer.

  A block type whose emission puts its children inside a **region** is the
  case that makes "nearest" do work of its own, and there are two of them
  in this vocabulary. An interruptible `core.group` puts its body in a
  region, and abandoning the group takes an *internal* transition to the
  group's own final - which exits the body region without exiting the
  group, so a cancel on the group's `<onexit>` never fired for it. That one
  is a fix as much as a move. `core.parallel`'s lanes are
  regions of its `<parallel>`, and a lane is a scope: leaving the lane -
  which under `complete: first` is exactly what the losing lanes do - has
  to reach the sends that lane armed. So a lane child's cancel is emitted
  in the *region's* `<onexit>`, not the wrapper's, and that is ADR-0004's
  `complete: first` amendment, P3, applied to both completion rules at
  once. A delayed send in a lane of an `all` parallel is cancelled when its
  region is exited for exactly the same reason.

  Only a `<state>` claims. A `<parallel>` between the child and its nearest
  state does not, which is what keeps an interrupt rail's cancel on the
  enclosing group's state where the record puts it ("the enclosing group
  for a rail"): a rail child is a region of the group's `<parallel>`, and
  the nearest *state* above it is the group's own. The one exception is a
  block whose emission is itself rooted at a `<parallel>` - not something
  this package emits, since decision 2 makes every block's emission a
  `<state>` - which is still offered the cancels rather than dropping them
  on the floor, in the same spirit as decision 1's "a finding, never a
  raise".

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
  emits one `<cancel sendid="...">` per hit in the scope's `<onexit>`.

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

  ## Which scope a child belongs to, and how it is found

  The parent's emission carries a `{:child, block_id}` placeholder wherever
  a child's subtree will be spliced, so the parent has already said where
  each child sits. The walk below reads that: one post-order pass over the
  emission, in which a placeholder reports its own block id upward and each
  `<state>` claims the armed ids reported from inside it before the rest
  travel further up. Nothing here reads a slot name, and nothing names a
  block type - a host type that arranges its children into regions of its
  own gets per-region cancels by placing its placeholders, exactly as
  `core.parallel` does.

  ## Determinism

  Children are visited in slot-declaration order and then document order -
  the order `StatifierBlocks.Compiler` already hands them over - and within
  one scope the cancels are emitted in that order, so ADR-0004 decision 6
  holds. The `<onexit>` is prepended to its scope state's children, ahead
  of the transitions the type wrote, which is one fixed position rather
  than a position that depends on what the type emitted. A block type that
  wrote an `<onexit>` of its own keeps it; SCXML runs both.

  The pass runs on the parent's own emission *before*
  `StatifierBlocks.Compiler.Attribution` stamps it, so the `<onexit>` and
  its cancels are owned by the scope block and carry the scope state's
  role, which is the block an author would recognise: the cancel is a
  consequence of where the send sits in that scope, not of the send block
  itself. That stays true when the scope is a region: the region is a state
  the same block emitted.
  """

  alias StatifierBlocks.{Block, Emission}
  alias StatifierBlocks.Compiler.StateId

  @role "send"

  # The element that claims a child's cancel: the nearest enclosing
  # `<state>`. A `<parallel>` deliberately does not claim - see the
  # moduledoc's rail case.
  @scope "state"

  # The elements an `<onexit>` may hang off at all. ADR-0004 decision 2
  # makes every block's emission a `<state>`, so the `"parallel"` arm is
  # unreachable in this package; it stays total rather than raising on a
  # host type that returns something else.
  @roots ["state", "parallel"]

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
  Adds the scope `<onexit>` cancels to `emission`, the emission of the
  block that `compiled_children` are the direct children of.

  `compiled_children` is the `{block id, emission}` list the compiler
  already holds after emitting the children. Returns `emission` unchanged
  when no direct child armed a delayed send - which is every scope in
  every document that contains no `core.send`, so no existing chart moves
  a byte.
  """
  @spec arm(Emission.t(), [{Block.id(), Emission.t()}]) :: Emission.t()
  def arm(%Emission{} = emission, compiled_children) when is_list(compiled_children) do
    case armed(compiled_children) do
      [] -> emission
      armed -> place(emission, armed)
    end
  end

  # Every `{block id, send id}` this scope's direct children armed, in the
  # order the compiler hands the children over.
  @spec armed([{Block.id(), Emission.t()}]) :: [{Block.id(), String.t()}]
  defp armed(compiled_children) do
    compiled_children
    |> Enum.flat_map(fn {id, child} -> Enum.map(armed_sends(child, id), &{id, &1}) end)
    |> Enum.uniq()
  end

  # The walk. Anything no enclosing `<state>` claimed lands on the root,
  # which covers a host emission rooted at a `<parallel>`.
  @spec place(Emission.t(), [{Block.id(), String.t()}]) :: Emission.t()
  defp place(emission, armed) do
    {placed, unclaimed} = descend(emission, armed)

    case sends_for(armed, unclaimed) do
      [] -> placed
      ids -> onexit(placed, ids)
    end
  end

  # Post-order: `{the node, the block ids under it no scope has claimed}`.
  @spec descend(Emission.node_t(), [{Block.id(), String.t()}]) ::
          {Emission.node_t(), MapSet.t(Block.id())}
  defp descend({:child, block_id}, _armed), do: {{:child, block_id}, MapSet.new([block_id])}

  defp descend(%Emission{} = emission, armed) do
    {children, unclaimed} =
      Enum.map_reduce(emission.children, MapSet.new(), fn child, seen ->
        {placed, ids} = descend(child, armed)
        {placed, MapSet.union(seen, ids)}
      end)

    claim(%{emission | children: children}, armed, unclaimed)
  end

  @spec claim(Emission.t(), [{Block.id(), String.t()}], MapSet.t(Block.id())) ::
          {Emission.t(), MapSet.t(Block.id())}
  defp claim(%Emission{name: @scope} = emission, armed, unclaimed) do
    case sends_for(armed, unclaimed) do
      [] -> {emission, unclaimed}
      ids -> {onexit(emission, ids), MapSet.difference(unclaimed, arming_blocks(armed))}
    end
  end

  defp claim(%Emission{} = emission, _armed, unclaimed), do: {emission, unclaimed}

  # The send ids of every arming block in `blocks`, in `armed` order.
  @spec sends_for([{Block.id(), String.t()}], MapSet.t(Block.id())) :: [String.t()]
  defp sends_for(armed, blocks) do
    for {block_id, send_id} <- armed, MapSet.member?(blocks, block_id), do: send_id
  end

  @spec arming_blocks([{Block.id(), String.t()}]) :: MapSet.t(Block.id())
  defp arming_blocks(armed), do: MapSet.new(armed, fn {block_id, _send_id} -> block_id end)

  @spec onexit(Emission.t(), [String.t()]) :: Emission.t()
  defp onexit(%Emission{name: name} = emission, ids) when name in @roots do
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
