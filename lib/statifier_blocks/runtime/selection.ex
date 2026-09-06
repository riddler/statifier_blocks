defmodule StatifierBlocks.Runtime.Selection do
  @moduledoc """
  Where a run is being watched from: the scrubber's four moves, and a direct
  pick of one macrostep.

  `StatifierBlocks.Runtime.Marks` reads a run's selection and resolves it to
  blocks. Something has to *move* that selection when an author presses Prev
  or clicks a step, and this is it. It is a separate module from `Marks` for
  the reason `Marks` is separate from the editor: the editor's handler should
  be one line, and what that line does is worth testing without LiveView.

  ## One of the two moves needs statifier-ui and the other does not

  Picking a macrostep is a field write. `selection` is a public field of
  `StatifierUI.Live.State` and its `{:macrostep, n}` shape is published in
  the same typespec `Marks` already reads `messages` and
  `initial_configuration` from, so `select/2` writes it directly and costs no
  dependency at all.

  Scrubbing is not, because *where* Prev lands is a decision about the
  stream: which macrosteps are points, whether the one below the current is
  the oldest, and what "next" means at the tip. statifier-ui decides that in
  `StatifierUI.Inspector.step/3` and this package must not answer it a second
  time - a scrubber that disagreed with the note beside it about which point
  is on screen is the drift the whole seam is arranged to prevent. So the two
  reads are dispatched dynamically out of `:statifier_blocks,
  :trace_inspector_module`, the same key `Marks` resolves and defaulting to
  the same module, checked with `function_exported?/3`. Without a resolvable
  inspector a scrub does nothing, which is what a scrubber over a stream
  nothing can read should do.
  """

  @moves [:first, :prev, :next, :live]

  @doc """
  `state` with its selection moved one scrubber step.

  `move` is one of `:first`, `:prev`, `:next`, `:live`. The state is returned
  unchanged for anything else, for a value carrying no `messages`, and for a
  tree where the reads do not resolve.
  """
  @spec scrub(map(), atom()) :: map()
  def scrub(state, move)

  def scrub(%{messages: messages} = state, move)
      when is_list(messages) and move in @moves do
    case inspector_module() do
      nil -> state
      inspector -> move_selection(inspector, state, messages, move)
    end
  end

  def scrub(state, _move), do: state

  @doc """
  `state` selecting macrostep `n` - what clicking an event-log entry does.

  A macrostep the stream holds no bucket for is not an error here any more
  than it is in statifier-ui: it resolves against whatever sits below it when
  something comes to read it.
  """
  @spec select(map(), non_neg_integer()) :: map()
  def select(state, n)

  def select(%{selection: _current} = state, n) when is_integer(n) and n >= 0 do
    Map.put(state, :selection, {:macrostep, n})
  end

  def select(state, _n), do: state

  @spec move_selection(module(), map(), [term()], atom()) :: map()
  defp move_selection(inspector, state, messages, move) do
    selection = Map.get(state, :selection, :live)

    Map.put(state, :selection, inspector.step(selection, inspector.points(messages), move))
  end

  @spec inspector_module() :: module() | nil
  defp inspector_module do
    module =
      Application.get_env(
        :statifier_blocks,
        :trace_inspector_module,
        StatifierUI.Inspector
      )

    if Code.ensure_loaded?(module) and function_exported?(module, :step, 3) and
         function_exported?(module, :points, 1) do
      module
    end
  end
end
