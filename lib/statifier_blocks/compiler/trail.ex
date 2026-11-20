defmodule StatifierBlocks.Compiler.Trail do
  @moduledoc """
  The trail of returnable steps, kept in the chart's own datamodel, and
  Back over it (ADR-0004's Amendment of 2026-11-20, `L1` to `L8`, except
  `L6`'s `core.checkpoint` row).

  A **returnable step** is a block for which
  `StatifierBlocks.BlockType.returnable?/2` answers `true` (ADR-0002's
  `C12`). This pass adds five things to a compiled emission, and nothing
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

    * **Back on the scope state (`L3`, `L4`'s first family).** One
      transition on the reserved event `statifier_blocks.back` per
      returnable step `S` of the scope, in document order, placed after
      the scope state's existing transitions. It re-enters the trail's top
      step and pops it:

          <transition cond="T[0] === 'S'" event="statifier_blocks.back" target="S" type="internal">
            <assign expr="T[1]" location="T"/>
          </transition>

    * **Back on each step's state (`L4`'s second family).** Inside a
      returnable step its own entry is the top, so Back goes to the step
      below it: one transition per other returnable step `S` of the same
      scope, in document order, then one with no target and no condition,
      all placed right after the push, before what the step's type
      emitted:

          <transition cond="T[1][0] === 'S'" event="statifier_blocks.back" target="S">
            <assign expr="T[1][1]" location="T"/>
          </transition>
          <transition event="statifier_blocks.back"/>

      A descendant's enabled transition is selected before its ancestor's,
      so the last one keeps the event from reaching the scope state when
      nothing is behind the step (`L5`). When the root block is itself the
      one returnable step, its state is both the scope state and the
      step's, every position is inside the step, and only this family is
      emitted there.

    * **The clears (`L6`).** `<assign expr="[]" location="T"/>`, emitted
      only into a scope whose trail root this pass declares:

      | Boundary | Where the clear sits | Which trail |
      |---|---|---|
      | `core.subchart`, `core.map`, `core.foreach`, `core.parallel` | its state's `<onentry>` and `<onexit>` | the scope the block belongs to |
      | a loop iteration | the body state's `<onentry>` | the body's |
      | a parallel lane | the lane region's `<onentry>` | the lane's |
      | the scope's own final | each `<final>` child of the scope state, in its `<onentry>` | that scope's |

      A clear goes first in the element's first existing `<onentry>` or
      `<onexit>`, ahead of what was there, a final's outcome raise
      included. A state with no `<onentry>` gets one holding only the
      clear, first among its children after its `<data>`; a state with no
      `<onexit>` gets one holding only the clear, right after that
      `<onentry>`. A `<final>` at the top level of the chart ends the
      execution and gets no clear. The `core.checkpoint` row of `L6` is
      not built here.

  So no Back crosses a boundary, and a finished document or lane holds an
  empty trail: no condition above holds on `[]`, the engine discards the
  event, and nothing is exited, entered or assigned (`L5`).

  ## The trail holds state ids and never responses (`L7`)

  Every value this pass writes into a trail is a string literal it writes
  (a returnable step's own state id), `[]`, or a part of the trail itself.
  No expression here reads any other datamodel location or any event's
  data, so nothing a person submits at a step, nothing a host writes into
  the datamodel and no event payload can reach a trail root.

  ## No returnable step, no bytes (`L8`)

  A document none of whose blocks answers `returnable?/2` with `true` has
  no scope with a step in it, so `lay/2` returns the emission it was
  handed, untouched, and the document compiles to the bytes it compiled to
  before this pass existed. A boundary in a scope with no step adds no
  clear.

  ## Provenance (decision 5) and determinism (decision 6)

  A trail root, a clear on a scope state's own `<final>` and the clear on a
  loop body's or a lane region's entry belong to the block that owns the
  scope state - the root block, the `core.foreach` block or the
  `core.parallel` block. A push belongs to its returnable step; a Back
  transition on the scope state to the step it targets; a Back transition
  on a step's state to that step; a boundary's clear to the boundary
  block. None carries a config key: no field an author typed names them.
  All are recorded under the role `":trail"`, whose leading colon
  `StatifierBlocks.Compiler.StateId.role?/1` rejects, so it cannot equal a
  role any block mints - the shape of the `:declare` compile option's own
  role.

  The scopes, their steps and their boundaries are collected in document
  pre-order over the resolved tree, and the emission is rewritten in
  place, so the same document compiles to the same bytes.
  """

  alias StatifierBlocks.{Block, BlockType, Emission, Palette, Provenance}
  alias StatifierBlocks.Compiler.{DeclaredRoots, StateId}
  alias StatifierBlocks.Core.{Emit, Foreach, Parallel, Subchart}

  @role ":trail"
  @suffix "__trail"
  @body_slot "body"
  @lane_prefix "lane_"
  @back "statifier_blocks.back"

  # The blocks whose state's entry and exit clear the trail of the scope
  # they belong to (`L6`): the sub-paths, the loop and the parallel.
  @boundaries [Subchart, StatifierBlocks.Core.Map, Foreach, Parallel]

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
  def scopes(node) do
    node
    |> survey()
    |> Enum.map(&Map.take(&1, [:state_id, :owner, :steps]))
  end

  @doc """
  Adds the trail roots, the pushes, the Back transitions and the clears
  the returnable steps of `node` call for to `emission`, the root block's
  assembled emission.

  Returns `emission` itself when `node` holds no returnable step.
  """
  @spec lay(Emission.t(), node_t()) :: Emission.t()
  def lay(%Emission{} = emission, node) do
    case survey(node) do
      [] -> emission
      scopes -> rewrite(emission, additions(scopes))
    end
  end

  # -- Collecting the scopes ----------------------------------------------------

  # The scopes holding a step, each with its steps and the boundary blocks
  # that belong to it, as `{block id, state id}` pairs in document order.
  defp survey(%{block: %Block{id: root_id}} = node) do
    root_scope = {StateId.state_id(root_id), root_id}

    node
    |> collect(root_scope, {[], %{}, %{}})
    |> finish(StateId.state_id(root_id))
  end

  # `order` is the scope state ids in first-step order, reversed; `found`
  # maps each to its owner and its steps, reversed; `bounds` maps any scope
  # state id to the boundary blocks in it, reversed.
  defp collect(%{block: block, module: ref, slots: slots}, {scope_id, _owner} = scope, acc) do
    module = module_of(ref)
    pair = {block.id, StateId.state_id(block.id)}

    acc =
      if BlockType.returnable?(ref, block.config), do: add_step(acc, scope, pair), else: acc

    acc = if module in @boundaries, do: add_boundary(acc, scope_id, pair), else: acc

    Enum.reduce(slots, acc, fn {slot, children}, acc ->
      child_scope = child_scope(module, block.id, slot) || scope

      Enum.reduce(children, acc, &collect(&1, child_scope, &2))
    end)
  end

  defp add_step({order, found, bounds}, {scope_id, owner}, step) do
    case Map.fetch(found, scope_id) do
      {:ok, %{steps: steps} = entry} ->
        {order, Map.put(found, scope_id, %{entry | steps: [step | steps]}), bounds}

      :error ->
        {[scope_id | order], Map.put(found, scope_id, %{owner: owner, steps: [step]}), bounds}
    end
  end

  defp add_boundary({order, found, bounds}, scope_id, pair),
    do: {order, found, Map.update(bounds, scope_id, [pair], &[pair | &1])}

  defp finish({order, found, bounds}, document_state_id) do
    order
    |> Enum.reverse()
    |> Enum.map(fn scope_id ->
      %{owner: owner, steps: steps} = Map.fetch!(found, scope_id)

      %{
        state_id: scope_id,
        owner: owner,
        steps: Enum.reverse(steps),
        boundaries: bounds |> Map.get(scope_id, []) |> Enum.reverse(),
        document?: scope_id == document_state_id
      }
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

  # -- What each state gains ----------------------------------------------------

  # State id => what that state gains, by key: `:root` (the trail root),
  # `:push`, `:steps_back` (`L4`'s second family, on a step's state),
  # `:scope_back` (the first family, on the scope state), `:entry` and
  # `:exit` (clears on the state's own entry and exit) and `:finals` (the
  # clear each of the state's `<final>` children opens with).
  defp additions(scopes) do
    Enum.reduce(scopes, %{}, fn scope, acc ->
      acc
      |> scope_additions(scope)
      |> steps_additions(scope)
      |> boundary_additions(scope)
    end)
  end

  defp scope_additions(acc, %{state_id: scope_id, owner: owner, steps: steps} = scope) do
    trail = root_id(scope_id)

    acc =
      acc
      |> put(scope_id, :root, root(trail, owner))
      |> put(scope_id, :finals, clear(trail, owner))

    acc = if scope.document?, do: acc, else: append(acc, scope_id, :entry, clear(trail, owner))

    case steps do
      [{_step, ^scope_id}] ->
        acc

      steps ->
        put(acc, scope_id, :scope_back, Enum.map(steps, &scope_back(trail, &1)))
    end
  end

  defp steps_additions(acc, %{state_id: scope_id, steps: steps}) do
    trail = root_id(scope_id)

    Enum.reduce(steps, acc, fn {step_id, state_id} = step, acc ->
      others = for {_id, other} <- steps, other != state_id, do: other

      acc
      |> put(state_id, :push, push(trail, state_id, step_id))
      |> put(state_id, :steps_back, step_back(trail, step, others))
    end)
  end

  defp boundary_additions(acc, %{state_id: scope_id, boundaries: boundaries}) do
    trail = root_id(scope_id)

    Enum.reduce(boundaries, acc, fn {block_id, state_id}, acc ->
      acc
      |> append(state_id, :entry, clear(trail, block_id))
      |> append(state_id, :exit, clear(trail, block_id))
    end)
  end

  defp put(acc, state_id, key, value),
    do: Map.update(acc, state_id, %{key => value}, &Map.put(&1, key, value))

  defp append(acc, state_id, key, element),
    do:
      Map.update(
        acc,
        state_id,
        %{key => [element]},
        &Map.update(&1, key, [element], fn list -> list ++ [element] end)
      )

  # -- Rewriting the emission ---------------------------------------------------

  defp rewrite({:child, _block_id} = placeholder, _additions), do: placeholder

  defp rewrite(%Emission{children: children} = emission, additions) do
    children = Enum.map(children, &rewrite(&1, additions))

    case Map.fetch(additions, state_id(emission)) do
      {:ok, added} -> %{emission | children: place(children, added)}
      :error -> %{emission | children: children}
    end
  end

  # The trail root after the state's own `<data>`, then the push, then the
  # step's own Back transitions, then everything else: the clears go into
  # its `<onentry>`, `<onexit>` and `<final>` children, and the scope
  # state's Back transitions after its last existing transition. The hoist
  # lifts every `<data>` out, so after it the push is the state's first
  # child.
  defp place(children, added) do
    {data, rest} = Enum.split_with(children, &data?/1)

    rest =
      rest
      |> clear_in("onentry", Map.get(added, :entry, []), nil)
      |> clear_in("onexit", Map.get(added, :exit, []), "onentry")
      |> clear_finals(Map.get(added, :finals))
      |> after_transitions(Map.get(added, :scope_back, []))

    data ++
      List.wrap(Map.get(added, :root)) ++
      List.wrap(Map.get(added, :push)) ++ Map.get(added, :steps_back, []) ++ rest
  end

  # The clears go first in the first `<name>` child; with none, a new one
  # holding only them goes right after the first `after` child, or first
  # when `after` is nil or absent.
  defp clear_in(children, _name, [], _after), do: children

  defp clear_in(children, name, clears, after_name) do
    case Enum.find_index(children, &named?(&1, name)) do
      nil ->
        at =
          case after_name && Enum.find_index(children, &named?(&1, after_name)) do
            nil -> 0
            index -> index + 1
          end

        List.insert_at(children, at, Emission.element(name, [], clears))

      index ->
        List.update_at(children, index, &%{&1 | children: clears ++ &1.children})
    end
  end

  defp clear_finals(children, nil), do: children

  defp clear_finals(children, clear) do
    Enum.map(children, fn
      %Emission{name: "final", children: final_children} = final ->
        %{final | children: clear_in(final_children, "onentry", [clear], nil)}

      other ->
        other
    end)
  end

  defp after_transitions(children, []), do: children

  defp after_transitions(children, transitions) do
    at =
      case last_index(children, &named?(&1, "transition")) do
        nil -> leading(children, ["onentry", "onexit"])
        index -> index + 1
      end

    {before, rest} = Enum.split(children, at)
    before ++ transitions ++ rest
  end

  defp last_index(list, fun) do
    list
    |> Enum.with_index()
    |> Enum.reduce(nil, fn {item, index}, acc -> if fun.(item), do: index, else: acc end)
  end

  defp leading(children, names),
    do:
      Enum.count(Enum.take_while(children, fn child -> Enum.any?(names, &named?(child, &1)) end))

  defp state_id(%Emission{name: "state", attributes: attributes}) do
    case List.keyfind(attributes, "id", 0) do
      {"id", id} -> id
      nil -> nil
    end
  end

  defp state_id(%Emission{}), do: nil

  defp data?(node), do: named?(node, "data")

  defp named?(%Emission{name: name}, name), do: true
  defp named?(_node, _name), do: false

  # -- The elements -------------------------------------------------------------

  defp root(trail, owner) do
    trail
    |> DeclaredRoots.declare("[]")
    |> owned(owner)
  end

  defp push(trail, state_id, step_id) do
    assign =
      Emission.element("assign", [{"expr", "['#{state_id}', #{trail}]"}, {"location", trail}])

    test = Emission.element("if", [{"cond", "#{trail}[0] !== '#{state_id}'"}], [assign])

    "onentry"
    |> Emission.element([], [test])
    |> owned(step_id)
  end

  # `L4`'s first family: re-enter the top step and pop it. Belongs to the
  # step it targets.
  defp scope_back(trail, {step_id, state_id}) do
    [event: @back, cond: "#{trail}[0] === '#{state_id}'", target: state_id, internal: true]
    |> Emit.transition([assign(trail, "#{trail}[1]")])
    |> owned(step_id)
  end

  # `L4`'s second family: pop the step's own entry, re-enter the step below
  # it and pop that too; then the catch-all. Belongs to the step whose state
  # carries it.
  defp step_back(trail, {step_id, _state_id}, others) do
    to_others =
      Enum.map(others, fn other ->
        Emit.transition([event: @back, cond: "#{trail}[1][0] === '#{other}'", target: other], [
          assign(trail, "#{trail}[1][1]")
        ])
      end)

    Enum.map(to_others ++ [Emit.transition(event: @back)], &owned(&1, step_id))
  end

  defp clear(trail, owner), do: trail |> assign("[]") |> owned(owner)

  defp assign(trail, expr), do: Emission.element("assign", [{"expr", expr}, {"location", trail}])

  defp owned(%Emission{} = emission, block_id) when is_binary(block_id),
    do: owned(emission, Provenance.owner(block_id, role: @role))

  defp owned(%Emission{children: children} = emission, owner),
    do: %{emission | owner: owner, children: Enum.map(children, &owned(&1, owner))}
end
