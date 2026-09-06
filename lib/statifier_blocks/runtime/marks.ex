defmodule StatifierBlocks.Runtime.Marks do
  @moduledoc """
  A trace read model and a provenance map become the canvas's run marks.

  The editor already draws run marks - `%{active: MapSet.t(block_id),
  invoke: {block_id, outcome} | nil}` threaded down `StatifierBlocks.Editor.Canvas`
  to every `StatifierBlocks.Editor.BlockNode` - but nothing in this package
  produced them: a host holding a run was expected to name the blocks itself.
  This is that step, done once and in the open, so the canvas can sit in the
  debugger's diagram seat rather than beside it.

  The input is a trace read model - statifier-ui's `StatifierUI.Live.State`,
  the struct an ops view already holds - and the provenance map the same
  document compiled to. The output is the marks map, or `nil` when there is
  nothing to mark, which is the same "no run over this document" the editor
  already threads.

  ## The seam is a read on one side and a resolution on the other

  statifier-ui answers where a run *is*, in the chart's own state ids
  (`StatifierUI.Inspector.active_configuration_ids/2` and `active_invokes/2`,
  both added in 0.9.0). This package answers which block a state id came
  from (`StatifierBlocks.Provenance.owners_of_states/2`). Neither half knows
  the other's vocabulary, and neither needed a callback to be handed one:
  the whole of the join is the two reads composed here.

  A state id the provenance map has never heard of is dropped rather than
  raised on, because `owners_of_states/2` drops it - a configuration naming
  a state from a *different* chart marks the blocks it can and no more.

  ## `invoke_type`, not an outcome

  The mark's second element is the canvas's `data-invoke-outcome`: how a
  call came back, `nil` while it is still out. statifier-ui's read pairs a
  live invocation with its **`invoke_type`** instead, and says why in its
  own docs: the wire format defines no outcome field for an invocation, and
  deciding when one has "finished" is the engine's call rather than a read's.
  So a live invocation is marked with `nil` - a call with no answer yet,
  which is precisely what a live invocation is - and the type is not stamped
  into an attribute that means something else. A block whose invocation has
  *ended* carries no mark at all, because it is no longer live.

  ## Unguarded, and no compile-time dependency on statifier-ui

  Like `StatifierBlocks.Runtime.FixtureRuns`, this module carries no
  LiveView presence wrapper and names no LiveView module: it is a pure
  function of a read model and a map, and the headless suite - the CI job
  that proves this package compiles and passes with LiveView absent -
  exercises it directly.

  `statifier_ui` is optional here for the same reason LiveView is, so the
  two reads are never named as call targets either. The module is read from
  application config and dispatched dynamically, the way
  `StatifierBlocks.Editor.Field` reaches statifier-ui's expression input and
  for the same reasons: the compiler stays quiet in a tree without the
  package, and a test can point the key at a module of its own to exercise
  the resolution with the package absent *or* present. Without a resolvable
  read, `from_trace/2` marks nothing.

  The read model itself is taken as **data** - `messages`, `selection` and
  `initial_configuration` are public fields of `StatifierUI.Live.State`, and
  reading them costs no dependency at all. That is also why the two reads go
  to `StatifierUI.Inspector` rather than to `State.configuration_ids/1`:
  `State` wraps the configuration read but exposes no invoke read, so one
  module answers both halves from the same options rather than one half
  coming from each.
  """

  alias StatifierBlocks.Provenance

  @typedoc """
  What the canvas accepts: the blocks a configuration is inside, and the
  block whose invocation is live.
  """
  @type t :: %{
          active: MapSet.t(String.t()),
          invoke: {String.t(), String.t() | nil} | nil
        }

  @doc """
  The run marks for `state`'s current selection, resolved through `provenance`.

  `state` is statifier-ui's `StatifierUI.Live.State` - anything carrying its
  `messages`, `selection` and `initial_configuration` fields - and the
  selection is whatever the scrubber left there: the live tip, or one
  macrostep. A macrostep that stamped no configuration of its own draws the
  newest one below it (statifier-ui's carried-configuration rule), so a
  carried point marks the same blocks the point it was carried from does.

  `nil` when there is nothing to mark: a stream carrying no `session.start`
  to resolve names through (the late-attach case, and the empty stream),
  a configuration naming no block this map owns, or a tree where the read
  itself does not resolve.
  """
  @spec from_trace(map(), Provenance.t()) :: t() | nil
  def from_trace(state, provenance)

  def from_trace(%{messages: messages} = state, %Provenance{} = provenance)
      when is_list(messages) do
    case inspector_module() do
      nil -> nil
      inspector -> read(inspector, messages, read_opts(state), provenance)
    end
  end

  def from_trace(_state, _provenance), do: nil

  @spec read(module(), [term()], keyword(), Provenance.t()) :: t() | nil
  defp read(inspector, messages, opts, provenance) do
    case inspector.active_configuration_ids(messages, opts) do
      {:ok, state_ids} ->
        marks(
          block_ids(provenance, state_ids),
          invoke_mark(provenance, inspector.active_invokes(messages, opts))
        )

      _no_names ->
        nil
    end
  end

  # Nothing at all when nothing is marked, which is the shape the editor's
  # own threading already uses: a document with no run over it threads `nil`
  # down the tree, and every node below skips the question rather than asking
  # a set it knows is empty.
  @spec marks(MapSet.t(String.t()), {String.t(), String.t() | nil} | nil) :: t() | nil
  defp marks(active, invoke) do
    if MapSet.size(active) == 0 and invoke == nil do
      nil
    else
      %{active: active, invoke: invoke}
    end
  end

  # A set rather than the list `owners_of_states/2` answers: two states of the
  # same block are one marked block, and the canvas asks a membership question.
  @spec block_ids(Provenance.t(), [String.t()]) :: MapSet.t(String.t())
  defp block_ids(provenance, state_ids) do
    provenance
    |> Provenance.owners_of_states(Enum.filter(state_ids, &is_binary/1))
    |> MapSet.new(& &1.block_id)
  end

  # Single-valued, because the mark is: the canvas draws one call at a time.
  # The first live invocation this map owns wins, and statifier-ui hands them
  # over in start order, so "first" is the oldest call still out rather than
  # whichever one a map happened to yield.
  @spec invoke_mark(Provenance.t(), term()) :: {String.t(), String.t() | nil} | nil
  defp invoke_mark(provenance, {:ok, invokes}) when is_list(invokes) do
    Enum.find_value(invokes, fn
      {state_id, _invoke_type} when is_binary(state_id) ->
        case Provenance.owner_of_state(provenance, state_id) do
          {:ok, %{block_id: block_id}} -> {block_id, nil}
          :error -> nil
        end

      _other ->
        nil
    end)
  end

  defp invoke_mark(_provenance, _other), do: nil

  # The options statifier-ui's folds take, rebuilt from the read model's own
  # public fields. `State` builds the same list privately; taking the fields
  # rather than calling for them is what keeps this module free of a
  # compile-time dependency on a package that is optional here.
  @spec read_opts(map()) :: keyword()
  defp read_opts(state) do
    [
      initial_configuration: Map.get(state, :initial_configuration, []),
      selection: Map.get(state, :selection, :live)
    ]
  end

  @spec inspector_module() :: module() | nil
  defp inspector_module do
    module =
      Application.get_env(
        :statifier_blocks,
        :trace_inspector_module,
        StatifierUI.Inspector
      )

    if Code.ensure_loaded?(module) and
         function_exported?(module, :active_configuration_ids, 2) and
         function_exported?(module, :active_invokes, 2) do
      module
    end
  end
end
