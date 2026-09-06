defmodule StatifierBlocks.Runtime.Handled do
  @moduledoc """
  Which block's state handled a macrostep, from a trace read model and a
  provenance map.

  `StatifierBlocks.Runtime.Marks` answers where a run *is*. This answers
  where one macrostep *happened*: an author clicking an entry in a run's
  event log is pointing at a step, and the useful thing to select for them
  is the block whose state took the transition that step selected.

  The join is the same shape as `Marks`' and made of the same two halves.
  statifier-ui's trace wire format numbers every transition and every state,
  and its `session.start` manifest carries the table that turns a transition
  number into the index of the state that owns it. This package turns a
  state id into the block that produced it
  (`StatifierBlocks.Provenance.owner_of_state/2`). Composing the two is the
  whole of the resolution.

  ## The manifest is read as data, not through a module

  `statifier_ui` is optional here, so `Marks` takes the read model's
  `messages`, `selection` and `initial_configuration` as public fields
  rather than as calls. This module goes one step further and reads the
  wire format itself: `session.start`'s `transitions` table gives each
  transition's `source` state index, its `states` table gives that state's
  `id`, and `trace.transitions_selected`'s `t_indexes` names which
  transitions a round selected. Those are the format's own published
  fields, so nothing here names a statifier-ui module at all - the module
  is pure, carries no LiveView presence wrapper, and the headless suite
  exercises it directly.

  ## One transition, and the first one

  A round selects a list, and a macrostep holds several rounds. The answer
  is the **first** transition the **first** round with a non-empty selection
  chose, because that is the transition the macrostep's own event fired: the
  rounds below it are the internal cascade that transition started, and
  selecting the block that caused the cascade is what an author clicking the
  step meant. A macrostep whose every round selected nothing - the initialize
  step, which enters states rather than transitioning between them - has no
  handler and answers `:error`.
  """

  alias StatifierBlocks.Provenance

  @manifest "session.start"
  @selected "trace.transitions_selected"

  @doc """
  The block whose state handled `macrostep`, resolved through `provenance`.

  `state` is statifier-ui's `StatifierUI.Live.State` - anything carrying a
  `messages` list of wire-format messages.

  `:error` for every gap, and they are all ordinary rather than exceptional:
  a stream with no `session.start` to resolve numbers through, a macrostep
  no round of which selected a transition, a transition number the manifest
  does not carry, a source state that is anonymous, and a state id this
  provenance map does not own - a run over a different chart revision, which
  is exactly the case `owner_of_state/2` is written to refuse.
  """
  @spec block(map(), non_neg_integer(), Provenance.t()) :: {:ok, String.t()} | :error
  def block(state, macrostep, provenance)

  def block(%{messages: messages}, macrostep, %Provenance{} = provenance)
      when is_list(messages) and is_integer(macrostep) and macrostep >= 0 do
    with {:ok, manifest} <- manifest(messages),
         {:ok, t_index} <- selected_transition(messages, macrostep),
         {:ok, state_index} <- source_of(manifest, t_index),
         {:ok, state_id} <- state_id(manifest, state_index),
         {:ok, %{block_id: block_id}} <- Provenance.owner_of_state(provenance, state_id) do
      {:ok, block_id}
    else
      _no_answer -> :error
    end
  end

  def block(_state, _macrostep, _provenance), do: :error

  @spec manifest([term()]) :: {:ok, map()} | :error
  defp manifest(messages) do
    case Enum.find(messages, &match?(%{type: @manifest, payload: %{}}, &1)) do
      %{payload: payload} -> {:ok, payload}
      _no_manifest -> :error
    end
  end

  # The first non-empty selection in macrostep order, which is stream order:
  # the producer stamps `seq` monotonically and the subscriber keeps it, so
  # the first message this finds is the first round that selected anything.
  @spec selected_transition([term()], non_neg_integer()) :: {:ok, non_neg_integer()} | :error
  defp selected_transition(messages, macrostep) do
    messages
    |> Enum.find_value(fn
      %{type: @selected, macrostep: ^macrostep, payload: %{"t_indexes" => [t_index | _rest]}}
      when is_integer(t_index) ->
        {:ok, t_index}

      _other ->
        nil
    end)
    |> case do
      {:ok, t_index} -> {:ok, t_index}
      nil -> :error
    end
  end

  @spec source_of(map(), non_neg_integer()) :: {:ok, non_neg_integer()} | :error
  defp source_of(%{"transitions" => transitions}, t_index) when is_list(transitions) do
    transitions
    |> Enum.find(&match?(%{"t_index" => ^t_index}, &1))
    |> case do
      %{"source" => source} when is_integer(source) -> {:ok, source}
      _unknown -> :error
    end
  end

  defp source_of(_manifest, _t_index), do: :error

  # `id` is absent for an anonymous state and always absent at index 0, the
  # synthesized root. Neither is a block's state, so both are `:error` here
  # rather than a placeholder the provenance map would refuse anyway.
  @spec state_id(map(), non_neg_integer()) :: {:ok, String.t()} | :error
  defp state_id(%{"states" => states}, index) when is_list(states) do
    states
    |> Enum.find(&match?(%{"index" => ^index}, &1))
    |> case do
      %{"id" => id} when is_binary(id) -> {:ok, id}
      _anonymous -> :error
    end
  end

  defp state_id(_manifest, _index), do: :error
end
