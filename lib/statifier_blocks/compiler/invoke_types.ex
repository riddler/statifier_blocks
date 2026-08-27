defmodule StatifierBlocks.Compiler.InvokeTypes do
  @moduledoc """
  The two-registry gap, surfaced as data and linted only on request
  (ADR-0004 decision 8).

  A block type whose emitted invoke type has no handler registered under
  st-ADR-0051 fails at runtime with `error.execution`, not at authoring
  time. That gap is real, and this module is the whole of what the
  compiler does about it.

  ## Always published, because it is a fact about the compile

  `collect/1` returns every `<invoke type="...">` in the generated chart
  with the block that emitted it, and
  `StatifierBlocks.Compiled`'s `invoke_types` is the sorted set of those
  strings. That part is unconditionally right and needs no opt-in: the
  host compares it against its own registration at **deploy time**, when
  it knows both, and this field is what makes that a one-liner.

  A `typeexpr` is deliberately not collected. It names a type computed at
  run time out of the datamodel, so there is no string here to compare
  against a registration, and reporting the expression source as though it
  were a type would be worse than reporting nothing.

  ## Linted only on request, and only ever a warning

  `lint/3` runs when the caller passes `:known_invoke_types`, and it emits
  a **warning** naming the block and the type for each emitted type absent
  from the set. Never an error, and the reason is a lifetime mismatch
  rather than timidity:

  st-ADR-0051 made the handler set **deployment state, supplied per
  session and fixed for the session's lifetime**. The palette is authoring
  state, supplied per operation. An authoring server that never runs a
  chart has no handler map at all, and if a missing handler failed the
  compile that host could not compile - this package would have made a
  runtime concern a precondition of authoring. Worse, it would be *wrong*
  even where a set is available: a host may compile in an authoring
  service and run in a worker with a different registration, so any set
  handed to the compiler is one deployment's belief, not ground truth. A
  warning is the strongest claim the evidence supports.

  The set a host passes is exactly `Map.keys(invoke_handlers)` from its
  `Statifier.Session` options - the same map st-ADR-0051 turns into
  `Statifier.Invoke.Types` - so the comparison is over the same strings
  the runtime classifier will use.
  """

  alias StatifierBlocks.Compiler.Finding
  alias StatifierBlocks.{Emission, Provenance}

  @typedoc "An emitted invoke type and the block whose emission carries it."
  @type emitted :: {String.t(), Provenance.owner()}

  @doc """
  Every literal invoke type in `emission`, with its owner, in document
  order. The same type emitted by two blocks appears twice.
  """
  @spec collect(Emission.t()) :: [emitted()]
  def collect(%Emission{} = emission), do: emission |> walk() |> Enum.reverse()

  @doc "The sorted, deduplicated type strings of `collect/1`'s result."
  @spec types([emitted()]) :: [String.t()]
  def types(emitted) do
    emitted |> Enum.map(&elem(&1, 0)) |> Enum.uniq() |> Enum.sort()
  end

  @doc """
  One warning per emitted type absent from `known`.

  `known` may be a `MapSet` or a list; a caller reading
  `Map.keys(invoke_handlers)` should not have to wrap it. Each type is
  reported once per block that emits it, because that is the granularity
  an editor annotates at.
  """
  @spec lint([emitted()], Enumerable.t()) :: [Finding.t()]
  def lint(emitted, known) do
    known = MapSet.new(known)

    emitted
    |> Enum.uniq()
    |> Enum.reject(fn {type, _owner} -> MapSet.member?(known, type) end)
    |> Enum.map(fn {type, owner} -> warning(type, owner) end)
  end

  @spec warning(String.t(), Provenance.owner()) :: Finding.t()
  defp warning(type, owner) do
    Finding.new(
      :chart,
      {:no_registered_invoke_handler, type},
      ~s(no handler registered for invoke type "#{type}"),
      block_id: owner.block_id,
      severity: :warning,
      fault: :author
    )
  end

  @spec walk(Emission.node_t(), [emitted()]) :: [emitted()]
  defp walk(node, acc \\ [])

  defp walk(%Emission{} = emission, acc) do
    Enum.reduce(emission.children, own(emission, acc), &walk/2)
  end

  defp walk({:child, _block_id}, acc), do: acc

  @spec own(Emission.t(), [emitted()]) :: [emitted()]
  defp own(%Emission{name: "invoke", owner: %{} = owner} = emission, acc) do
    case List.keyfind(emission.attributes, "type", 0) do
      {"type", type} when type != "" -> [{type, owner} | acc]
      _no_literal_type -> acc
    end
  end

  defp own(%Emission{}, acc), do: acc
end
