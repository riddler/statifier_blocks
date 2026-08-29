defmodule StatifierBlocks.Compiler.SensitivePaths do
  @moduledoc """
  The secrets rule, checked against a document: a declared-sensitive
  datamodel path may not be read into a trace-visible position (ADR-0002,
  the accepted 2026-08-29 amendment "decision 7, an optional `sensitive?`
  key, and the secrets rule behind it").

  The rule the key serves is a rule about hosts: **credentials, API keys
  and other secrets never enter a chart datamodel.** A secret is
  referenced by an identifier and fetched by the invoke handler at effect
  time. This package emits SCXML and never sees a value, so it cannot
  protect one; what it can do is refuse to compile a document that would
  carry a value it has been told is a secret into a position one of the
  five leak surfaces reads - traces, telemetry, job payloads, the editor's
  fixtures and truth tables, LiveView diffs.

  Findings, not runtime checks. Every word here is about what a document
  says, checked at compile time.

  ## No datamodel supplied, nothing produced

  The check runs only when the caller supplies a datamodel that declares
  at least one path sensitive. With none, `check/2` returns `[]`, makes no
  claim, and reports nothing anywhere - the qualifier ADR-0005's `11f`
  states for the undeclared-path advisories, in `11f`'s own words:
  absence is not unknown-ness. A host that has described nothing has
  claimed nothing.

  ## The criterion, and why it is not a list of block types

  A hard-coded list of `core.*` fields would have to be edited every time
  the vocabulary grew, and a type added without that edit would leak
  silently. So the pass never looks at a block type's name. It walks the
  **emission** - the SCXML this compile is about to serialize, already
  attributed back to the config fields the author typed (ADR-0004
  decision 9) - and classifies each attribute by SCXML's own declared
  semantics: is this an attribute the engine **evaluates against the
  datamodel**?

  `datamodel_position?/1` is that criterion. `cond`, `location`,
  `namelist`, `idlocation` and every `*expr` attribute (`expr` itself,
  `eventexpr`, `targetexpr`, `delayexpr`, `typeexpr`, `srcexpr`) are
  datamodel positions; every other attribute is literal chart text the
  engine never resolves against the datamodel. A block type that lands
  tomorrow and writes a sensitive path into an `expr` is refused without
  this module having heard of it.

  The record's four refused positions all fall out of that one criterion,
  which is the check that it is the right criterion rather than a
  rephrasing of the list:

  | Record's position | The emission it lands in |
  |---|---|
  | a `core.invoke` param | `<param expr="card.number" name="amount"/>` |
  | a `core.send` payload | the `expr` it will carry when the row lands |
  | a `core.assign` target | `<assign location="card.number"/>` |
  | a `core.assign` source | `<assign expr="card.number"/>` |
  | a `core.branch` arm predicate | `<transition cond="card.number > 0"/>` |

  ## `core.invoke`'s `assign_to`, classified

  The record's reviewer left this one explicitly to the compiler half, and
  the criterion answers it without a special case: `assign_to` emits
  `<assign expr="_event.data" location="authorization"/>`, and `location`
  is a datamodel position. **`assign_to` is a datamodel WRITE target, the
  exact analogue of `core.assign`'s target, and it is refused on the same
  side of the line for the same reason** - the record's `core.assign`
  clause is "either direction: writing a sensitive value somewhere else
  spreads it, reading one out publishes it", and a write is a write
  whichever type spells it. Nothing in this module distinguishes the two,
  which is the point.

  ## What is not refused

  A read of a sensitive path in a position that never leaves the session.
  The criterion is stated as a criterion because in today's accepted
  `core.*` vocabulary that side of the line is **empty**: every position
  this package emits that can address the datamodel at all is a datamodel
  position by the rule above. Two things are clearly on that side and are
  not reads at all, so they are not refused:

    * **The declaration itself.** Annotating a path is not a read of it.
    * **The identifier pattern the rule prescribes.** A param reading
      `card.token_id` - a declared path that is not sensitive, holding the
      identifier the handler exchanges at effect time - is not a read of a
      sensitive path. The refusal must not grow into a suspicion of any
      field near a secret, and it does not: only a path the datamodel
      declares sensitive is ever matched.

  A genuinely session-local position arrives by an amendment naming it and
  the surfaces it is shown to miss, per the record. It does not arrive by
  this module reading the criterion generously.

  ## Severity: `:error`

  The record named the severity as this half's question. It is `:error`.
  ADR-0005 `11a`'s own wording fixes it: "`:error` says the document does
  not compile", and a refusal stops the compile - that is what makes it a
  refusal rather than an advisory. `:info` is excluded by `11a` and `11c`
  together (an advisory changes no verdict; this changes the verdict), and
  `:warning` is excluded because a warning rides on
  `StatifierBlocks.Compiled`'s `warnings` and lets the document through,
  which would emit the leak it exists to prevent.

  Decision 11's source list puts this at `:lint`: the rule lives neither
  in `validate_config/1` (which is handed one config and has no datamodel
  to check it against) nor in arity, assignability or resolution.
  Decision 11 fixes `:lint` as the only source permitted to produce a
  severity other than `:error`; it does not forbid `:lint` producing one,
  and `11b`/`11e` reserve `:info` to `:lint` without making `:lint`
  advisory-only.

  `StatifierBlocks.Finding.from_compiler/2`'s **default** derivation
  cannot reach `{source: :lint, severity: :error}` - its rule 2 maps only
  a non-error to `:lint`, and this finding's `:emit` stage has no default
  source. That is what `opts[:source]` is documented for ("lets a caller
  that knows better than the default rule say so explicitly"), so a caller
  adapting these findings for presentation passes it:

      {presentation, []} =
        StatifierBlocks.Finding.from_compiler_all(findings, source: :lint)

  Widening the default derivation would mean switching on `code`, which
  `StatifierBlocks.Finding` forbids by construction; the seam is named
  here rather than bent.
  """

  alias StatifierBlocks.{Block, Emission}
  alias StatifierBlocks.Compiler.Finding

  @typedoc """
  The host's declared datamodel, normalized.

  `declared` is the declared-path set - the shipped editor's normalized
  input, and what ADR-0005 `11f` names as the shape this check needs.
  `sensitive` is the subset those declarations annotate `sensitive?: true`
  (ADR-0002 decision 7's key).

  This pass reads `sensitive`. `declared` is carried because it is the
  same input the undeclared-path advisory of `11e` reads, so a host
  supplies one datamodel rather than two, and because the typed scoped
  datamodel document (`sb-g8m`) derives both by one total function if it
  lands.
  """
  @type datamodel :: %{declared: MapSet.t(String.t()), sensitive: MapSet.t(String.t())}

  # SCXML's datamodel-evaluated attributes that are not spelled `*expr`.
  # `cond` is a predicate, `location` a write target, `namelist` a list of
  # locations, `idlocation` where the engine writes a minted id.
  @named_positions ~w(cond location namelist idlocation)

  # A dotted run of identifiers: what a datamodel path looks like wherever
  # one appears, whether the attribute holds a bare path or an expression
  # around one.
  @token ~r/[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*/

  # Quoted spans are literals, not reads. `core.assign`'s `value` field
  # stores source text, so `"card.number"` in an `expr` is the six-word
  # string, not the path.
  @quoted ~r/"[^"]*"|'[^']*'/

  @doc """
  Normalizes a caller-supplied datamodel into `t:datamodel/0`.

  Total, and lenient about shape rather than about content: only non-empty
  binaries are taken as paths, and anything else in a supplied collection
  is ignored. Accepted shapes:

    * `nil` - no datamodel. Both sets empty; the check does not run.
    * a list or `MapSet` of paths - the declared-path set, with nothing
      annotated sensitive. Nothing is produced, which is correct: a host
      that declared paths and annotated none has claimed no secrets.
    * a map with `:declared` and/or `:sensitive`, each a list or `MapSet`.

  A path in `sensitive` that is absent from `declared` is still sensitive.
  This pass does not adjudicate declaredness - that is `11e`'s advisory
  and a different finding - and dropping an annotated path because the
  declared set did not repeat it would silently disable the refusal.

      iex> alias StatifierBlocks.Compiler.SensitivePaths
      iex> SensitivePaths.datamodel(%{sensitive: ["card.number"]}).sensitive |> MapSet.to_list()
      ["card.number"]
      iex> SensitivePaths.datamodel(nil).sensitive |> MapSet.size()
      0
  """
  @spec datamodel(term()) :: datamodel()
  def datamodel(nil), do: %{declared: MapSet.new(), sensitive: MapSet.new()}

  def datamodel(%{} = supplied) when not is_struct(supplied) do
    %{
      declared: path_set(Map.get(supplied, :declared)),
      sensitive: path_set(Map.get(supplied, :sensitive))
    }
  end

  def datamodel(supplied), do: %{declared: path_set(supplied), sensitive: MapSet.new()}

  @doc """
  Every refusal `emission` earns against `supplied`, in the order the
  emission is walked (document order over blocks, attributes sorted by
  name, which is `StatifierBlocks.Emission.element/3`'s normalization).

  `supplied` is the raw option value; it is normalized through
  `datamodel/1` here so a caller passes what it has. With no sensitive
  path in it the walk is skipped entirely and `[]` is returned.
  """
  @spec check(Emission.t(), term()) :: [Finding.t()]
  def check(%Emission{} = emission, supplied) do
    %{sensitive: sensitive} = datamodel(supplied)
    check_against(emission, sensitive)
  end

  @doc """
  Whether an attribute of that name is a position the engine evaluates
  against the datamodel. See the moduledoc; this is the criterion, and the
  only thing that decides what is refused.

      iex> alias StatifierBlocks.Compiler.SensitivePaths
      iex> {SensitivePaths.datamodel_position?("expr"), SensitivePaths.datamodel_position?("cond")}
      {true, true}
      iex> {SensitivePaths.datamodel_position?("eventexpr"), SensitivePaths.datamodel_position?("event")}
      {true, false}
  """
  @spec datamodel_position?(String.t()) :: boolean()
  def datamodel_position?(attribute) when is_binary(attribute) do
    attribute in @named_positions or String.ends_with?(attribute, "expr")
  end

  @doc """
  The sensitive paths `value` reads, sorted, with how each one was
  reached.

  `{:exact, path}` is the path itself or something under it;
  `{:prefix, token, path}` is a read of a prefix, which "drags the
  sensitive leaf along with everything else under it, so a prefix read is
  the same leak spelled shorter".

  Public because the tests assert the matcher directly - a matcher that
  only ever runs behind a whole compile is one whose edge cases are
  asserted by proxy.
  """
  @spec reads(String.t(), MapSet.t(String.t())) ::
          [{:exact, String.t()} | {:prefix, String.t(), String.t()}]
  def reads(value, %MapSet{} = sensitive) when is_binary(value) do
    value
    |> tokens()
    |> Enum.flat_map(fn token -> Enum.flat_map(sensitive, &match(token, &1)) end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  # -- the walk --------------------------------------------------------------

  @spec check_against(Emission.t(), MapSet.t(String.t())) :: [Finding.t()]
  defp check_against(emission, sensitive) do
    if MapSet.size(sensitive) == 0 do
      []
    else
      walk(emission, sensitive)
    end
  end

  @spec walk(Emission.node_t(), MapSet.t(String.t())) :: [Finding.t()]
  defp walk(%Emission{} = emission, sensitive) do
    element_findings(emission, sensitive) ++
      Enum.flat_map(emission.children, &walk(&1, sensitive))
  end

  # A `{:child, id}` placeholder is a hole the compiler has already filled
  # with that child's own stamped subtree by the time this pass runs; one
  # surviving here is a compiler bug the Emit stage reports, not a
  # position to check.
  defp walk({:child, _block_id}, _sensitive), do: []

  @spec element_findings(Emission.t(), MapSet.t(String.t())) :: [Finding.t()]
  defp element_findings(%Emission{} = emission, sensitive) do
    Enum.flat_map(emission.attributes, fn {name, value} ->
      if datamodel_position?(name) do
        attribute_findings(emission, name, value, sensitive)
      else
        []
      end
    end)
  end

  @spec attribute_findings(Emission.t(), String.t(), String.t(), MapSet.t(String.t())) ::
          [Finding.t()]
  defp attribute_findings(emission, name, value, sensitive) do
    value
    |> reads(sensitive)
    |> Enum.map(&finding(emission, name, &1))
  end

  @spec finding(
          Emission.t(),
          String.t(),
          {:exact, String.t()} | {:prefix, String.t(), String.t()}
        ) :: Finding.t()
  defp finding(emission, attribute, read) do
    Finding.new(
      :emit,
      {:sensitive_path_read, path(read)},
      message(read, attribute),
      block_id: block_id(emission),
      config_key: config_key(emission, attribute),
      severity: :error
    )
  end

  @spec message({:exact, String.t()} | {:prefix, String.t(), String.t()}, String.t()) ::
          String.t()
  defp message(read, attribute) do
    "#{subject(read)} into #{attribute}, a position the chart evaluates against " <>
      "the datamodel. A datamodel value also flows into traces, telemetry, job " <>
      "payloads, the editor's fixtures and LiveView diffs, so a secret must not be " <>
      "there to be read: reference it by an identifier and let the handler fetch it " <>
      "at effect time (ADR-0002 decision 7, the secrets rule)."
  end

  @spec subject({:exact, String.t()} | {:prefix, String.t(), String.t()}) :: String.t()
  defp subject({:exact, path}),
    do: ~s(reads "#{path}", which the supplied datamodel declares sensitive,)

  defp subject({:prefix, token, path}),
    do:
      ~s(reads "#{token}", which carries the sensitive path "#{path}" underneath it,) <>
        " and so is the same read spelled shorter,"

  @spec path({:exact, String.t()} | {:prefix, String.t(), String.t()}) :: String.t()
  defp path({:exact, path}), do: path
  defp path({:prefix, _token, path}), do: path

  # The finer grain wins: an attribute value annotated back to a config
  # field anchors on that field, and only an element with no attribute
  # annotation falls back to the element's own key. Both come from
  # ADR-0004 decision 9's split, and today every emitted datamodel
  # position carries one or the other - a future type that carries
  # neither gets a block-anchored finding rather than silence.
  @spec config_key(Emission.t(), String.t()) :: String.t() | nil
  defp config_key(%Emission{attribute_owners: owners} = emission, attribute) do
    case List.keyfind(owners, attribute, 0) do
      {^attribute, key} -> key
      nil -> owner_config_key(emission)
    end
  end

  @spec owner_config_key(Emission.t()) :: String.t() | nil
  defp owner_config_key(%Emission{owner: %{config_key: key}}), do: key
  defp owner_config_key(%Emission{}), do: nil

  @spec block_id(Emission.t()) :: Block.id() | nil
  defp block_id(%Emission{owner: %{block_id: id}}), do: id
  defp block_id(%Emission{}), do: nil

  # -- matching --------------------------------------------------------------

  @spec tokens(String.t()) :: [String.t()]
  defp tokens(value) do
    value
    |> String.replace(@quoted, " ")
    |> then(&Regex.scan(@token, &1))
    |> Enum.map(&hd/1)
    |> Enum.uniq()
  end

  @spec match(String.t(), String.t()) ::
          [{:exact, String.t()} | {:prefix, String.t(), String.t()}]
  defp match(token, path) do
    cond do
      token == path -> [{:exact, path}]
      String.starts_with?(token, path <> ".") -> [{:exact, path}]
      String.starts_with?(path, token <> ".") -> [{:prefix, token, path}]
      true -> []
    end
  end

  @spec path_set(term()) :: MapSet.t(String.t())
  defp path_set(nil), do: MapSet.new()

  defp path_set(%MapSet{} = set), do: path_set(MapSet.to_list(set))

  defp path_set(paths) when is_list(paths) do
    paths
    |> Enum.filter(&(is_binary(&1) and &1 != ""))
    |> MapSet.new()
  end

  defp path_set(_other), do: MapSet.new()
end
