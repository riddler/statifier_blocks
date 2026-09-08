defmodule StatifierBlocks.Compiler.Interrupts do
  @moduledoc """
  The group-scoped interrupt pair: a `<raise>` of the interrupt protocol
  emitted inside a group's rail is rewritten to that group's own salted
  event name (ADR-0010 decision 8).

  ## The defect this closes

  The protocol is two strings - `StatifierBlocks.Core.Emit`'s
  `interrupt_events/0` - and before decision 8 every interruptible group
  emitted the same two transitions matching them. One name at every nesting
  depth means the rails of two nested groups listen for the same event, and
  only the raise's position in the active configuration decides which of
  them takes it. That is right for a raise from the inner group's own rail
  and wrong for a raise from the *outer* group's rail while a second railed
  group is active in the outer group's body: the inner rail's source sits
  deeper, so it takes the outer group's resume and the outer group's
  history re-entry - the whole point of `core.resumable_group` - never
  fires.

  `StatifierBlocks.Core.Emit.interruptible/2` emits the group's own two
  transitions already salted with its state id. This pass is the other
  half: the raises inside the rail, which the group cannot reach when it
  emits, because a parent never receives its children's SCXML (ADR-0004
  decision 4) - what it emits in a handler's place is a `{:child, block id}`
  placeholder. By the time the compiler has the children's compiled
  emissions in hand, it also has the parent's own emission saying where
  each of them sits, and that is exactly what this pass reads.

  ## Which raises are a rail's, structurally

  Nothing here names a block type, in the same spirit as
  `StatifierBlocks.Compiler.Cancels`. The parent's own emission is walked
  for a `<state id="X">` that carries a transition on
  `Emit.interrupt_events(X)` - a state matching its own salted pair is a
  group's rail-bearing state, and `X` is the salt. Its rail children are
  the `{:child, _}` placeholders sitting directly in the `<parallel>` under
  it: the body is a `<state>` region the group emitted, so a body child's
  placeholder is nested inside that state and is never one of these. A host
  group type that builds its rail through `Emit.interruptible/2` gets the
  scoping for free, and one that arranges regions of its own gets it by
  placing its placeholders the same way.

  Every `<raise>` of the bare pair *anywhere* under a rail child - the
  handler's own state, and any depth within it - is rewritten. That is
  decision 8b's "anywhere inside that group's rail subtree", and it is what
  makes a host block type on a rail scoped on exactly the same rule as
  `core.on_event` (8d): the rewrite is a property of the position in the
  emitted chart, not of which type emitted the raise.

  ## Why it is idempotent, and why nesting composes

  A child's own pass has already run by the time its parent sees it, so an
  inner group's rail raises arrive here already salted with the *inner*
  group's id. Those names are not the bare pair, so this pass does not
  touch them: an inner rail keeps its own salt and the outer salt is
  applied only to what is still bare. The two halves - the transitions in
  `Emit` and the raises here - therefore move together at every depth.

  ## What is not rewritten

  A raise of the bare pair that is not inside a rail (decision 8c). It
  reaches no rail today and none after, and leaving it alone is what keeps
  the compiled bytes of a document with no interruptible group identical to
  what they were before this pass existed - a document with no rail has no
  rail child, so `scope/2` answers with the children it was handed.
  """

  alias StatifierBlocks.{Block, Emission}
  alias StatifierBlocks.Core.Emit

  @rail "parallel"
  @scope "state"

  @doc """
  Salts the interrupt raises inside `emission`'s rail children.

  `emission` is one block's own emission, before its children are spliced
  in, and `compiled_children` is the `{block id, emission}` list the
  compiler already holds after emitting them. Returns `compiled_children`
  with each rail child's subtree rewritten, and returns it unchanged when
  `emission` carries no rail - which is every block in every document that
  holds no interruptible group, so no such chart moves a byte.
  """
  @spec scope(Emission.t(), [{Block.id(), Emission.t()}]) :: [{Block.id(), Emission.t()}]
  def scope(%Emission{} = emission, compiled_children) when is_list(compiled_children) do
    case rails(emission) do
      [] -> compiled_children
      rails -> Enum.map(compiled_children, &scoped(&1, Map.new(rails)))
    end
  end

  @spec scoped({Block.id(), Emission.t()}, %{optional(Block.id()) => String.t()}) ::
          {Block.id(), Emission.t()}
  defp scoped({id, child}, salts) do
    case Map.fetch(salts, id) do
      {:ok, salt} -> {id, rewrite(child, salted(salt))}
      :error -> {id, child}
    end
  end

  # Every `{rail child block id, salt}` pair the emission places, from a
  # walk of the whole tree rather than of the root alone: a block type is
  # free to emit its group below its own state.
  @spec rails(Emission.node_t()) :: [{Block.id(), String.t()}]
  defp rails({:child, _block_id}), do: []

  defp rails(%Emission{} = emission) do
    own =
      case salt(emission) do
        nil -> []
        salt -> Enum.map(rail_children(emission), &{&1, salt})
      end

    own ++ Enum.flat_map(emission.children, &rails/1)
  end

  # The salt a state carries, or `nil`: the state's own id, when the state
  # transitions on the salted pair that id names.
  @spec salt(Emission.t()) :: String.t() | nil
  defp salt(%Emission{name: @scope, attributes: attributes, children: children}) do
    with {"id", id} <- List.keyfind(attributes, "id", 0),
         %{abandon: abandon, resume: resume} <- Emit.interrupt_events(id),
         true <- Enum.any?(children, &transition_on?(&1, [abandon, resume])) do
      id
    else
      _not_a_rail -> nil
    end
  end

  defp salt(%Emission{}), do: nil

  @spec transition_on?(Emission.node_t(), [String.t()]) :: boolean()
  defp transition_on?(%Emission{name: "transition", attributes: attributes}, events) do
    case List.keyfind(attributes, "event", 0) do
      {"event", event} -> event in events
      nil -> false
    end
  end

  defp transition_on?(_node, _events), do: false

  # The rail regions: a child placeholder sitting directly in the group's
  # `<parallel>`. The body is a `<state>` region, so a body child's
  # placeholder is nested inside it and is not one of these.
  @spec rail_children(Emission.t()) :: [Block.id()]
  defp rail_children(%Emission{children: children}) do
    for %Emission{name: @rail, children: regions} <- children,
        {:child, block_id} <- regions,
        do: block_id
  end

  @spec salted(String.t()) :: %{String.t() => String.t()}
  defp salted(salt) do
    bare = Emit.interrupt_events()
    scoped = Emit.interrupt_events(salt)

    %{bare.abandon => scoped.abandon, bare.resume => scoped.resume}
  end

  @spec rewrite(Emission.node_t(), %{String.t() => String.t()}) :: Emission.node_t()
  defp rewrite({:child, block_id}, _scoped), do: {:child, block_id}

  defp rewrite(%Emission{children: children} = emission, scoped) do
    %{raised(emission, scoped) | children: Enum.map(children, &rewrite(&1, scoped))}
  end

  @spec raised(Emission.t(), %{String.t() => String.t()}) :: Emission.t()
  defp raised(%Emission{name: "raise", attributes: attributes} = emission, scoped) do
    with {"event", event} <- List.keyfind(attributes, "event", 0),
         {:ok, salted} <- Map.fetch(scoped, event) do
      %{emission | attributes: List.keystore(attributes, "event", 0, {"event", salted})}
    else
      _not_the_pair -> emission
    end
  end

  defp raised(%Emission{} = emission, _scoped), do: emission
end
