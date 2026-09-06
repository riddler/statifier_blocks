defmodule StatifierBlocks.Runtime.RunValues do
  @moduledoc """
  What a run is holding at the selected point, as display text keyed by
  datamodel path.

  The editor's Datamodel tab already answers what the document *declares* at
  a position - ADR-0011 decision 9's "what is known here", a path and a type.
  This is the other half of the same row: what a run actually had there when
  it was at the point the scrubber is on. The two beside each other are what
  makes a read that should not have been possible visible without a verdict:
  a path declared one type, holding something else.

  Nothing here decides anything. The Datamodel tab is read-only by decision 9
  and stays so; this module produces text, and a mismatch is something the
  reader sees rather than something the package rules on.

  ## The fold is statifier-ui's, the cut is this module's

  statifier-ui's `StatifierUI.DatamodelExplorer` folds the wire format's
  `session.datamodel` snapshot and every `effect.datamodel_change` after it
  into one set of entries; that fold is the contract and re-implementing it
  here would be a second answer to a question that already has one. It is
  reached the way `StatifierBlocks.Runtime.Marks` reaches the inspector and
  `StatifierBlocks.Editor.Field` reaches the expression input - out of
  application config, checked with `function_exported?/3`, never named as a
  call target - because `statifier_ui` is optional here.

  What this module does write is the cut. `StatifierUI.Inspector.datamodel/2`
  takes a selection and folds "the stream as it stood at the end of macrostep
  n", but the function that shortens the list is private there and what it
  returns is Markdown rather than entries. So the prefix is taken here, by
  the rule that read documents: every message the envelope stamps with no
  macrostep, plus every message stamped at or below the selected one. On
  `:live` there is no cut at all.

  ## Tiers 2 and 3 are not the document's datamodel

  Only `:data` and `:runtime` entries are kept - a `<data>` element the chart
  declares, and a location a run wrote that the snapshot did not name. The
  system variables and the provider functions the explorer also lists are
  real, and they are not what a block's declared environment is about: a row
  reading "declared string, held #Function<...>" would be noise beside every
  path an author actually declared.
  """

  @typedoc "Display text for each datamodel path the run is holding a value at."
  @type t :: %{optional(String.t()) => String.t()}

  @kept_tiers [:data, :runtime]

  @doc """
  The values `state`'s run holds at its selection, keyed by dotted path.

  `state` is statifier-ui's `StatifierUI.Live.State` - anything carrying its
  public `messages` and `selection` fields.

  `%{}` rather than an error for every gap: a tree with no resolvable
  explorer, a stream the fold refuses (more than one session on one
  timeline), and a run that has written nothing yet all mean the same thing
  to the caller, which is that there is no held value to draw beside a
  declared type.
  """
  @spec at(map()) :: t()
  def at(state)

  def at(%{messages: messages} = state) when is_list(messages) do
    case explorer_module() do
      nil -> %{}
      explorer -> read(explorer, in_view(messages, Map.get(state, :selection, :live)))
    end
  end

  def at(_state), do: %{}

  @spec read(module(), [term()]) :: t()
  defp read(explorer, messages) do
    case explorer.build_live(messages) do
      {:ok, %{entries: entries}} when is_list(entries) -> paths(entries)
      _refused -> %{}
    end
  end

  # A message with no macrostep is the session's own - the manifest and the
  # starting snapshot - and belongs in every prefix: cutting them out would
  # leave the fold with no names to seed from and no session to resolve.
  @spec in_view([term()], term()) :: [term()]
  defp in_view(messages, {:macrostep, n}) when is_integer(n) do
    Enum.filter(messages, fn message ->
      case Map.get(message, :macrostep) do
        nil -> true
        stamped when is_integer(stamped) -> stamped <= n
        _other -> true
      end
    end)
  end

  defp in_view(messages, _live), do: messages

  @spec paths([term()], String.t() | nil) :: t()
  defp paths(entries, prefix \\ nil) do
    entries
    |> Enum.filter(&keep?(&1, prefix))
    |> Enum.reduce(%{}, fn entry, acc ->
      path = join(prefix, entry.name)

      acc
      |> put_value(path, entry.value)
      |> Map.merge(paths(entry.children, path))
    end)
  end

  # The tier is declared on the root entry only; a child of a kept root is
  # kept with it, which is what makes a nested write reachable by its own
  # dotted path.
  @spec keep?(term(), String.t() | nil) :: boolean()
  defp keep?(%{tier: tier}, nil), do: tier in @kept_tiers
  defp keep?(_entry, _prefix), do: true

  @spec put_value(t(), String.t(), term()) :: t()
  defp put_value(acc, _path, :undefined), do: acc
  defp put_value(acc, path, value), do: Map.put(acc, path, inspect(value))

  @spec join(String.t() | nil, term()) :: String.t()
  defp join(nil, name), do: to_string(name)
  defp join(prefix, name), do: prefix <> "." <> to_string(name)

  @spec explorer_module() :: module() | nil
  defp explorer_module do
    module =
      Application.get_env(
        :statifier_blocks,
        :trace_datamodel_module,
        StatifierUI.DatamodelExplorer
      )

    if Code.ensure_loaded?(module) and function_exported?(module, :build_live, 1) do
      module
    end
  end
end
