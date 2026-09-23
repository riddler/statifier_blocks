defmodule StatifierBlocks.Migration do
  @moduledoc """
  The state mapping between two compiled revisions of one document (ADR-0004's
  amendment of 2026-09-23, clauses M1 to M6).

  "Migration" here means moving a waiting **execution** from one chart to
  another, the act `sp-ADR-0013` (statifier_persistence,
  `docs/adr/0013-the-migration-plan.md`) decides. It is not a block type's
  config migration: `c:StatifierBlocks.BlockType.migrate_config/2` rewrites an
  old block's stored config as the block resolves, and has nothing to do with
  this module.

  This package does not migrate anything. `plan/2` reads two
  `%StatifierBlocks.Compiled{}` artifacts and answers plain data a host copies
  into the migration plan it writes; saving, compiling or publishing a document
  never produces one, and applying a plan is the persistence layer's. The
  answer names no timer, datamodel change, drop or chart hash: those are the
  plan author's (M5, M6).
  """

  alias Statifier.Parser
  alias Statifier.Parser.DOM
  alias StatifierBlocks.{Compiled, Provenance}

  @typedoc """
  One state of the from chart with no counterpart in the to chart (M3): the
  state id, and the block and role that owned it by the from side's provenance
  map. `"role"` is `nil` for a block's own state.
  """
  @type unmapped :: %{String.t() => String.t() | nil}

  @typedoc """
  One moved invocation, `[from_state_id, from_ordinal, to_state_id,
  to_ordinal]`: `sp-ADR-0013` decision 1's encoding of an invocation key. An
  ordinal is the zero-based, document-order position of an `<invoke>` among
  its state's own `<invoke>` children.
  """
  @type invocation :: [String.t() | non_neg_integer()]

  @typedoc """
  The mapping (M5), with string keys and plain data only, so it encodes as JSON
  as it stands.

    * `"states"` - from state id to to state id, for every mapped state that
      is not a history pseudo-state.
    * `"history"` - the same, for every mapped history pseudo-state.
    * `"invocations"` - `t:invocation/0` entries, ordered by from state id and
      then ordinal.
    * `"unmapped"` - `t:unmapped/0` entries, ordered by state id.
  """
  @type mapping :: %{
          String.t() => %{String.t() => String.t()} | [invocation()] | [unmapped()]
        }

  # The elements of a chart that are states (M1). `<scxml>`, `<state>` and
  # `<parallel>` are the ones that hold more of them; nothing below an
  # `<invoke>`, an `<onentry>` or any other element is a state of this chart.
  @states ~w(state parallel final history)
  @containers ~w(scxml state parallel)

  @doc """
  Maps the states of `from`'s chart onto the states of `to`'s chart, for two
  compiled revisions of one document.

  The clauses of ADR-0004's amendment of 2026-09-23, each as this function
  applies it:

    * **M1.** A from state corresponds to a to state when both carry the same
      state id and each side's `by_state_id` names the same block id and the
      same role for it; equal ids whose owners differ do not correspond. The
      states are the from chart's `<state>`, `<parallel>`, `<final>` and
      `<history>` elements, read from its SCXML: `by_state_id` also keys a
      delayed `<send>`'s id, which is not a state. Only the two artifacts are
      read, and equal inputs give an equal answer.
    * **M2.** Every from state with a counterpart maps to it, roles included,
      and each identity entry is written out. An `<invoke>` of a mapped state
      maps to the `<invoke>` at the same ordinal of the state it maps to, when
      that state has one; otherwise it gets no entry.
    * **M3.** Every other from state - each state of a deleted block, and each
      auxiliary state a surviving block no longer mints - is listed under
      `"unmapped"` with its owner and appears in no other field. A to state
      with no from counterpart appears nowhere.
    * **M4.** Two artifacts whose compilation records carry different
      `document_id`s are refused with `{:error, :different_documents}`, and
      nothing else is computed. Revisions are not compared: two artifacts of
      one document map in either order.
    * **M5.** `"states"`, `"history"` and `"invocations"` carry
      `sp-ADR-0013`'s field names and its map form (statifier_persistence,
      `docs/adr/0013-the-migration-plan.md`, decision 1), so a host copies them
      into its plan unchanged. `"unmapped"` is a report, not a plan field.

  Raises `ArgumentError` for an artifact `StatifierBlocks.Compiler.compile/3`
  never produces: one whose `scxml` is not well-formed XML, or whose from
  chart holds a state its own provenance map does not own.
  """
  @spec plan(Compiled.t(), Compiled.t()) :: {:ok, mapping()} | {:error, :different_documents}
  def plan(%Compiled{record: %{document_id: from_doc}}, %Compiled{record: %{document_id: to_doc}})
      when from_doc != to_doc,
      do: {:error, :different_documents}

  def plan(%Compiled{} = from, %Compiled{} = to) do
    from_states = chart_states(from)
    to_states = Map.new(chart_states(to), &{&1.id, &1})

    {mapped, unmapped} =
      Enum.split_with(from_states, &counterpart?(&1, from.provenance, to_states, to.provenance))

    {history, states} = Enum.split_with(mapped, &(&1.kind == "history"))

    {:ok,
     %{
       "states" => identity_map(states),
       "history" => identity_map(history),
       "invocations" => invocations(states, to_states),
       "unmapped" => unmapped |> Enum.map(&unmapped_entry(&1, from.provenance)) |> sort_by_id()
     }}
  end

  @spec counterpart?(map(), Provenance.t(), %{String.t() => map()}, Provenance.t()) :: boolean()
  defp counterpart?(%{id: id}, from_provenance, to_states, to_provenance) do
    with %{} <- Map.get(to_states, id),
         {:ok, owner} <- Provenance.owner_of_state(from_provenance, id),
         {:ok, to_owner} <- Provenance.owner_of_state(to_provenance, id) do
      same_owner?(owner, to_owner)
    else
      _no_counterpart -> false
    end
  end

  # Block and role, never `config_key`: a state's own entry carries none, and a
  # config key names where an attribute came from, not who owns the state.
  @spec same_owner?(Provenance.owner(), Provenance.owner()) :: boolean()
  defp same_owner?(%{block_id: block_id, role: role}, %{block_id: block_id, role: role}),
    do: true

  defp same_owner?(_owner, _other), do: false

  @spec identity_map([map()]) :: %{String.t() => String.t()}
  defp identity_map(states), do: Map.new(states, &{&1.id, &1.id})

  @spec invocations([map()], %{String.t() => map()}) :: [invocation()]
  defp invocations(states, to_states) do
    for %{id: id, invokes: count} <- Enum.sort_by(states, & &1.id),
        ordinal <- ordinals(min(count, Map.fetch!(to_states, id).invokes)),
        do: [id, ordinal, id, ordinal]
  end

  @spec ordinals(non_neg_integer()) :: Range.t()
  defp ordinals(count), do: 0..(count - 1)//1

  @spec unmapped_entry(map(), Provenance.t()) :: unmapped()
  defp unmapped_entry(%{id: id}, provenance) do
    case Provenance.owner_of_state(provenance, id) do
      {:ok, %{block_id: block_id, role: role}} ->
        %{"state_id" => id, "block_id" => block_id, "role" => role}

      :error ->
        raise ArgumentError,
              "the from chart's state #{inspect(id)} has no owner in its provenance map"
    end
  end

  @spec sort_by_id([unmapped()]) :: [unmapped()]
  defp sort_by_id(entries), do: Enum.sort_by(entries, & &1["state_id"])

  # Every state element of the chart, in document order, with its kind and the
  # number of `<invoke>` elements among its own children.
  @spec chart_states(Compiled.t()) :: [
          %{id: String.t(), kind: String.t(), invokes: non_neg_integer()}
        ]
  defp chart_states(%Compiled{scxml: scxml}) do
    case Parser.parse(scxml) do
      {:ok, root} ->
        root |> collect([]) |> Enum.reverse()

      {:error, error} ->
        raise ArgumentError, "the artifact's scxml does not parse: " <> Exception.message(error)
    end
  end

  @spec collect(DOM.Element.t(), [map()]) :: [map()]
  defp collect(%DOM.Element{name: name} = element, acc) when name in @containers do
    element
    |> DOM.elements()
    |> Enum.reduce(acc, fn child, acc -> collect(child, collect_state(child) ++ acc) end)
  end

  defp collect(%DOM.Element{}, acc), do: acc

  @spec collect_state(DOM.Element.t()) :: [map()]
  defp collect_state(%DOM.Element{name: name} = element) when name in @states do
    case DOM.attribute(element, "id") do
      %DOM.Attribute{value: id} ->
        invokes = element |> DOM.elements() |> Enum.count(&(&1.name == "invoke"))
        [%{id: id, kind: name, invokes: invokes}]

      nil ->
        []
    end
  end

  defp collect_state(%DOM.Element{}), do: []
end
