defmodule StatifierBlocks.Compiler.Trail do
  @moduledoc """
  The trail of returnable steps, kept in the chart's own datamodel
  (ADR-0004's Amendment of 2026-11-20, `L1`, `L2`, `L7` and `L8`).

  A **returnable step** is a block for which
  `StatifierBlocks.BlockType.returnable?/2` answers `true` (ADR-0002's
  `C12`). This pass adds two things to a compiled emission, and nothing
  else:

    * **The trail root (`L1`).** One `<data>` root per **trail scope**
      that at least one returnable step belongs to, named for the scope
      state with `__trail` appended and declared with `expr="[]"`:

      | Trail scope | Its scope state |
      |---|---|
      | the document | the root block's state, `s_<root block id>` |
      | a `core.foreach` body | `s_<foreach block id>__body` |
      | a `core.parallel` lane | `s_<parallel block id>__lane_<lane>` |

      A step belongs to the nearest scope that encloses it. The root is
      declared among the scope state's own children, after any `<data>`
      the state already carries, so
      `StatifierBlocks.Compiler.DeclaredRoots.hoist/1` lifts it into the
      one top-level `<datamodel>` in document order with every other root.

    * **The push (`L2`).** One `<onentry>` placed first among each
      returnable step's state's children, which pushes the step's state
      id onto its scope's trail unless it is already on top:

          <onentry>
            <if cond="T[0] !== 'S'">
              <assign expr="['S', T]" location="T"/>
            </if>
          </onentry>

      The trail is a pair list - `[]` is empty, and a push makes the new
      state id and the trail as it was - so the top is `T[0]` and what is
      below it is `T[1]`, read without a list length, which predicator
      does not have.

  ## The trail holds state ids and never responses (`L7`)

  Every value the push writes is a string literal this module writes (a
  returnable step's own state id), `[]`, or the trail itself. No
  expression here reads any other datamodel location or any event's data,
  so nothing a person submits at a step, nothing a host writes into the
  datamodel and no event payload can reach a trail root.

  ## No returnable step, no bytes (`L8`)

  A document none of whose blocks answers `returnable?/2` with `true` has
  no scope with a step in it, so `lay/2` returns the emission it was
  handed, untouched, and the document compiles to the bytes it compiled to
  before this pass existed.

  ## Provenance (decision 5) and determinism (decision 6)

  A trail root belongs to the block that owns its scope state - the root
  block, the `core.foreach` block or the `core.parallel` block - and a
  push to its returnable step. Neither carries a config key: no field an
  author typed names them. Both are recorded under the role `":trail"`,
  whose leading colon `StatifierBlocks.Compiler.StateId.role?/1` rejects,
  so it cannot equal a role any block mints - the shape of the `:declare`
  compile option's own role.

  The scopes and their steps are collected in document pre-order over the
  resolved tree, and the emission is rewritten in place, so the same
  document compiles to the same bytes.
  """

  alias StatifierBlocks.{Block, BlockType, Emission, Palette, Provenance}
  alias StatifierBlocks.Compiler.{DeclaredRoots, StateId}
  alias StatifierBlocks.Core.{Foreach, Parallel}

  @role ":trail"
  @suffix "__trail"
  @body_slot "body"
  @lane_prefix "lane_"

  @typedoc """
  A resolved node, as `StatifierBlocks.Compiler` threads it: a block, the
  type reference it resolved to, and its resolved children by slot.
  """
  @type node_t :: %{
          required(:block) => Block.t(),
          required(:module) => Palette.type_ref(),
          required(:slots) => [{Block.slot_name(), [node_t()]}],
          optional(atom()) => term()
        }

  @typedoc """
  One trail scope that at least one returnable step belongs to: its scope
  state's id, the block that owns that state, and its returnable steps as
  `{block id, state id}` pairs in document order.
  """
  @type scope :: %{
          state_id: StateId.t(),
          owner: Block.id(),
          steps: [{Block.id(), StateId.t()}]
        }

  @doc """
  The trail root id of the scope whose state is `scope_state_id`.

      iex> StatifierBlocks.Compiler.Trail.root_id("s_blk_ROOT")
      "s_blk_ROOT__trail"
  """
  @spec root_id(StateId.t()) :: String.t()
  def root_id(scope_state_id) when is_binary(scope_state_id), do: scope_state_id <> @suffix

  @doc """
  The trail scopes of the resolved tree `node` that hold at least one
  returnable step, in the document order of their first step.

  `[]` for a document with no returnable step.
  """
  @spec scopes(node_t()) :: [scope()]
  def scopes(%{block: %Block{id: root_id}} = node) do
    root_scope = {StateId.state_id(root_id), root_id}

    node
    |> collect(root_scope, {[], %{}})
    |> finish()
  end

  @doc """
  Adds the trail roots and the pushes the returnable steps of `node` call
  for to `emission`, the root block's assembled emission.

  Returns `emission` itself when `node` holds no returnable step.
  """
  @spec lay(Emission.t(), node_t()) :: Emission.t()
  def lay(%Emission{} = emission, node) do
    case scopes(node) do
      [] -> emission
      scopes -> rewrite(emission, additions(scopes))
    end
  end

  # -- Collecting the scopes ----------------------------------------------------

  # `order` is the scope state ids in first-step order, reversed; `found`
  # maps each to its owner and its steps, reversed.
  defp collect(%{block: block, module: ref, slots: slots}, {scope_id, _owner} = scope, acc) do
    acc =
      if BlockType.returnable?(ref, block.config) do
        add_step(acc, scope, {block.id, StateId.state_id(block.id)})
      else
        acc
      end

    Enum.reduce(slots, acc, fn {slot, children}, acc ->
      child_scope = child_scope(module_of(ref), block.id, slot) || {scope_id, elem(scope, 1)}

      Enum.reduce(children, acc, &collect(&1, child_scope, &2))
    end)
  end

  defp add_step({order, found}, {scope_id, owner}, step) do
    case Map.fetch(found, scope_id) do
      {:ok, %{steps: steps} = entry} ->
        {order, Map.put(found, scope_id, %{entry | steps: [step | steps]})}

      :error ->
        {[scope_id | order], Map.put(found, scope_id, %{owner: owner, steps: [step]})}
    end
  end

  defp finish({order, found}) do
    order
    |> Enum.reverse()
    |> Enum.map(fn scope_id ->
      %{owner: owner, steps: steps} = Map.fetch!(found, scope_id)
      %{state_id: scope_id, owner: owner, steps: Enum.reverse(steps)}
    end)
  end

  # A `core.foreach` body and each `core.parallel` lane open a scope of
  # their own; every other slot stays in its parent's. Recognized by
  # module rather than by type name, so a host palette mapping another name
  # onto either module is covered.
  defp child_scope(Foreach, block_id, @body_slot), do: scope_state(block_id, @body_slot)

  defp child_scope(Parallel, block_id, @lane_prefix <> _lane = slot),
    do: scope_state(block_id, slot)

  defp child_scope(_module, _block_id, _slot), do: nil

  defp scope_state(block_id, role) do
    case StateId.state_id(block_id, role) do
      {:ok, state_id} -> {state_id, block_id}
      {:error, _invalid_role} -> nil
    end
  end

  defp module_of({module, _state}), do: module
  defp module_of(module), do: module

  # -- Rewriting the emission ---------------------------------------------------

  # State id => the elements to add to that state: a trail root for a scope
  # state, a push for a step's state, or both when the root block is itself
  # a returnable step.
  defp additions(scopes) do
    Enum.reduce(scopes, %{}, fn %{state_id: scope_id, owner: owner, steps: steps}, acc ->
      trail = root_id(scope_id)
      acc = add(acc, scope_id, :root, root(trail, owner))

      Enum.reduce(steps, acc, fn {step_id, state_id}, acc ->
        add(acc, state_id, :push, push(trail, state_id, step_id))
      end)
    end)
  end

  defp add(acc, state_id, key, element),
    do: Map.update(acc, state_id, %{key => element}, &Map.put(&1, key, element))

  defp rewrite({:child, _block_id} = placeholder, _additions), do: placeholder

  defp rewrite(%Emission{children: children} = emission, additions) do
    children = Enum.map(children, &rewrite(&1, additions))

    case Map.fetch(additions, state_id(emission)) do
      {:ok, added} -> %{emission | children: place(children, added)}
      :error -> %{emission | children: children}
    end
  end

  # The trail root after the state's own `<data>`, the push first among
  # everything else. The hoist lifts every `<data>` out, so after it the
  # push is the state's first child.
  defp place(children, added) do
    {data, rest} = Enum.split_with(children, &data?/1)

    data ++ List.wrap(Map.get(added, :root)) ++ List.wrap(Map.get(added, :push)) ++ rest
  end

  defp state_id(%Emission{name: "state", attributes: attributes}) do
    case List.keyfind(attributes, "id", 0) do
      {"id", id} -> id
      nil -> nil
    end
  end

  defp state_id(%Emission{}), do: nil

  defp data?(%Emission{name: "data"}), do: true
  defp data?(_node), do: false

  defp root(trail, owner) do
    trail
    |> DeclaredRoots.declare("[]")
    |> owned(Provenance.owner(owner, role: @role))
  end

  defp push(trail, state_id, step_id) do
    assign =
      Emission.element("assign", [{"expr", "['#{state_id}', #{trail}]"}, {"location", trail}])

    test = Emission.element("if", [{"cond", "#{trail}[0] !== '#{state_id}'"}], [assign])

    "onentry"
    |> Emission.element([], [test])
    |> owned(Provenance.owner(step_id, role: @role))
  end

  defp owned(%Emission{children: children} = emission, owner),
    do: %{emission | owner: owner, children: Enum.map(children, &owned(&1, owner))}
end
