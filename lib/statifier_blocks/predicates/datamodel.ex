defmodule StatifierBlocks.Predicates.Datamodel do
  @moduledoc """
  The path/type index over a datamodel document (sb ADR-0006, accepted
  2026-08-29), and the projections that record promises.

  ADR-0006 defines the document: a `version` plus three scopes - `global`,
  `local`, `event` - each carrying entries with `name`, `path`, `type` and
  `label`, plus the optional `fields`, `item_type`, `example`, `note` and
  `one_of`. Decision 5 makes every path absolute and globally addressable
  (an event entry spells its own `event.` prefix), and decision 6 gives the
  one total function from the document to the declared-path set.

  This module is that record's reader. `index/1` admits a decoded document
  and flattens it to `path -> entry`, at every nesting depth; the lookups
  answer what a path's type is, what lies under a prefix, and whether a
  path is declared at all; `declared_paths/1` is decision 6's projection.

  ## Advisory, never a gate

  Decision 9 is the stance this module is built to keep: **an undeclared
  path is unknown, not wrong.** Nothing here returns a verdict, produces a
  `StatifierBlocks.Finding`, or refuses anything. `declared?/2` answers a
  question about the document, not about the author, and `type/2` returns
  `nil` for a path the document does not declare rather than an error -
  absence of a declaration is not a claim that the path is bad.

  Making an undeclared path a validation failure needs a record saying so,
  which is what `sb-oiq` asked for from the start and what decision 9
  granted. Two consumers already read a datamodel and neither gates on
  declaredness: `StatifierBlocks.Datamodel` reports `:info` (ADR-0005
  `11e`), and `StatifierBlocks.Compiler.SensitivePaths` refuses only on the
  separate `sensitive?` claim, which is a claim the host made rather than
  one this package inferred.

  ## The admission step is `index/1`

  Decision 6 states its totality "over *admitted* documents: a malformed
  input is a loader concern, rejected before this function is reached,
  which is why the function has no `{:error, _}` arm to explain". `index/1`
  is that loader. It is itself total - an input it cannot admit returns
  `nil`, on ADR-0002 amendment B3's total-normalizer discipline, the same
  way `StatifierBlocks.Datamodel.declared_paths/1` treats a shape it does
  not know - and every function taking a `t:t/0` is then total by
  construction.

  So the record's `declared_paths(document)` is spelled here as

      document |> index() |> declared_paths()

  with the `nil` case being *this input is not a datamodel document*, which
  is a different thing from *the document declares nothing*. That
  distinction is decision 6's, stated there for exactly the same pair of
  values: `nil` is no datamodel supplied, `MapSet.new()` is a host claim
  that nothing is declared.

  ## What normalization does, and what it declines to decide

  Keys are read as the record writes them, from a decoded JSON map with
  string keys.

    * **Scope names contribute nothing to a path** (decision 6), so a scope
      map naming something other than the three is not rejected: its
      entries are indexed with `scope: nil`. Paths are already absolute,
      and dropping entries over a scope label would lose declared paths
      the projection is required to contain.
    * **An entry whose `path` is not a non-empty string contributes no
      path**, and its `fields` are still walked. That is the only place
      this module departs from decision 6's literal code, which would put
      a `nil` in the set; a set with a `nil` in it is not a set of declared
      paths, and the record admits no such entry in the first place.
    * **The type set is closed** (decision 4). A `type` or `item_type`
      outside the eight normalizes to `nil` - unknown, on the same stance
      as an undeclared path - rather than being carried through as a ninth
      type this package would then be rendering.
    * **A repeated path keeps its first occurrence** in document order.
      This is not a ruling on the record's open question about collisions
      across scopes: the declared-path set is a set either way, and a
      document that needs the question answered needs a loader lint, which
      is where the record leaves it.
    * **`name` is read and stored, and nothing here consumes it.** The
      record carries an open question on how an event entry spells it; this
      module reads `path` alone for every derivation, exactly as decision 6
      does, so the question stays open rather than being answered by use.

  ## `sensitive?`, and why it is derived here rather than projected

  ADR-0006 decision 7 says the entry map is where a per-path annotation
  lives, in ADR-0002's optional-boolean convention, and that decision 6's
  projection **deliberately drops it**: "a consumer that needs to know
  whether a path is sensitive reads the document, never the set". ADR-0002's
  accepted `sensitive?` amendment says the same from the other side - if the
  document record lands, "the same boolean belongs on its per-entry shape".

  `sensitive_paths/1` is that read, and it is a second projection rather
  than a widening of the first: `declared_paths/1` returns paths and
  nothing else, exactly as decision 6 specifies. `datamodel/1` pairs the
  two into the `%{declared: MapSet, sensitive: MapSet}` shape
  `StatifierBlocks.Compiler.SensitivePaths.datamodel/1` already normalizes,
  so a host with a document can reach that pass without a second input.

  An entry's flag is read literally, per entry. An `object` entry marked
  sensitive does **not** stamp its fields, and does not need to: the
  sensitive-path matcher already treats a read of a prefix as a read of
  everything under it ("a prefix read is the same leak spelled shorter"),
  so inheritance here would restate the matcher and, where the two
  disagreed, would decide a rule no record has drawn.

  ## Not wired to anything

  This module has no consumer in this package, on purpose. `sb-oiq` filed
  itself as "file this when something actually needs a path/type index",
  and what needs it today is the derivation the accepted record promised -
  not a fixtures or completion pane, which ADR-0005 decision 15 lists among
  the things that record explicitly does not decide. The one seam taken is
  the additive `StatifierBlocks.Datamodel.declared_paths/1` clause, which
  discharges `11f`'s promise for a host that has a document instead of a
  set.
  """

  @typedoc """
  ADR-0006 decision 4's closed type set. No floats anywhere: money is
  integer minor units, and a `decimal`, a `datetime` and a `duration` are
  all carried as strings (ADR-0001 decision 6).

  A `duration` value - and the `example` beside it - is a duration string
  the expression language reads, `30s` or `1h30m`, the same string an
  author types into the `:duration` field this record's paths feed. That
  is decision 4 as amended 2026-09-05 (clauses 4a and 4d). Which strings
  parse is `Predicator.Duration`'s to define; this module stores whatever
  the document holds and parses none of it.
  """
  @type type ::
          :string | :integer | :decimal | :boolean | :datetime | :duration | :object | :list

  @typedoc "ADR-0006 decision 5's three scopes, or `nil` for a scope map naming none of them."
  @type scope :: :global | :local | :event | nil

  @typedoc """
  One declared path, flattened out of the document.

  `depth` is the nesting level `fields` reached it at - `0` for a
  top-level entry - and is what a pane groups by when it renders an object
  and its members together.
  """
  @type entry :: %{
          path: String.t(),
          name: String.t() | nil,
          type: type() | nil,
          label: String.t() | nil,
          scope: scope(),
          depth: non_neg_integer(),
          item_type: type() | nil,
          example: term(),
          note: String.t() | nil,
          one_of: [term()] | nil,
          sensitive?: boolean()
        }

  @typedoc """
  The index: the document's `version`, its entries by path, and the paths
  in document order.
  """
  @type t :: %__MODULE__{
          version: integer(),
          entries: %{optional(String.t()) => entry()},
          order: [String.t()]
        }

  defstruct version: 1, entries: %{}, order: []

  # ADR-0006 decision 4's eight, and decision 5's three, spelled as
  # literal pairs rather than converted: the record's sets are closed, so a
  # closed match is what reads them.
  @types %{
    "string" => :string,
    "integer" => :integer,
    "decimal" => :decimal,
    "boolean" => :boolean,
    "datetime" => :datetime,
    "duration" => :duration,
    "object" => :object,
    "list" => :list
  }

  @scopes %{"global" => :global, "local" => :local, "event" => :event}

  @doc """
  Admits a decoded ADR-0006 document and indexes it, or returns `nil`.

  Total: every input has an answer and none of them raise. A map carrying
  a list under `"scopes"` is a document; anything else - a set, a list of
  paths, a bare map, a number - is not one, and gets `nil` rather than an
  empty index, so *not a document* stays distinguishable from *a document
  declaring nothing*.

      iex> alias StatifierBlocks.Predicates.Datamodel
      iex> index = Datamodel.index(%{"version" => 1, "scopes" => [
      ...>   %{"scope" => "local", "entries" => [
      ...>     %{"name" => "card", "path" => "card", "type" => "object", "label" => "Card",
      ...>       "fields" => [
      ...>         %{"name" => "brand", "path" => "card.brand", "type" => "string",
      ...>           "label" => "Brand"}]}]}]})
      iex> index.order
      ["card", "card.brand"]
      iex> Datamodel.type(index, "card.brand")
      :string

      iex> StatifierBlocks.Predicates.Datamodel.index(["card.brand"])
      nil
  """
  @spec index(term()) :: t() | nil
  def index(%{"scopes" => scopes} = document) when is_list(scopes) do
    entries = Enum.flat_map(scopes, &scope_entries/1)

    %__MODULE__{
      version: version(Map.get(document, "version")),
      entries: dedupe(entries),
      order: entries |> Enum.map(& &1.path) |> Enum.uniq()
    }
  end

  def index(_unrecognized), do: nil

  @doc """
  ADR-0006 decision 6's projection: every entry's own `path`, at every
  nesting depth, and nothing else.

  An `object` entry contributes its own path *and*, recursively, its
  fields'. A `list` entry contributes its own path alone - `item_type`
  names an element type and no record decides an index syntax, so there is
  no element path to contribute.

      iex> alias StatifierBlocks.Predicates.Datamodel
      iex> %{"scopes" => [%{"scope" => "local", "entries" => [
      ...>   %{"path" => "risk_reasons", "type" => "list", "item_type" => "string"},
      ...>   %{"path" => "card", "type" => "object", "fields" => [%{"path" => "card.brand"}]}]}]}
      ...> |> Datamodel.index()
      ...> |> Datamodel.declared_paths()
      MapSet.new(["card", "card.brand", "risk_reasons"])
  """
  @spec declared_paths(t()) :: MapSet.t(String.t())
  def declared_paths(%__MODULE__{order: order}), do: MapSet.new(order)

  @doc """
  The declared paths the document annotates `sensitive?: true` (ADR-0006
  decision 7, ADR-0002's `sensitive?` amendment).

  Read per entry and literally: an `object` marked sensitive does not
  stamp its fields. See the moduledoc for why that is the matcher's job
  rather than this one's.

      iex> alias StatifierBlocks.Predicates.Datamodel
      iex> %{"scopes" => [%{"scope" => "local", "entries" => [
      ...>   %{"path" => "card.token_id", "type" => "string"},
      ...>   %{"path" => "card.number", "type" => "string", "sensitive?" => true}]}]}
      ...> |> Datamodel.index()
      ...> |> Datamodel.sensitive_paths()
      MapSet.new(["card.number"])
  """
  @spec sensitive_paths(t()) :: MapSet.t(String.t())
  def sensitive_paths(%__MODULE__{} = index) do
    index
    |> entries()
    |> Enum.filter(& &1.sensitive?)
    |> MapSet.new(& &1.path)
  end

  @doc """
  Both projections in the shape
  `StatifierBlocks.Compiler.SensitivePaths.datamodel/1` normalizes, so a
  host that has a document supplies one input rather than two.

  Nothing in this package calls it yet; it is the derivation the record
  promised, at the shape the pass that would consume it already takes.
  """
  @spec datamodel(t()) :: %{declared: MapSet.t(String.t()), sensitive: MapSet.t(String.t())}
  def datamodel(%__MODULE__{} = index) do
    %{declared: declared_paths(index), sensitive: sensitive_paths(index)}
  end

  @doc """
  Every entry, in document order.
  """
  @spec entries(t()) :: [entry()]
  def entries(%__MODULE__{entries: entries, order: order}) do
    Enum.map(order, &Map.fetch!(entries, &1))
  end

  @doc """
  The entry declared at `path`.

      iex> alias StatifierBlocks.Predicates.Datamodel
      iex> index = Datamodel.index(%{"scopes" => [
      ...>   %{"scope" => "local", "entries" => [%{"path" => "amount_cents", "type" => "integer"}]}]})
      iex> {:ok, entry} = Datamodel.fetch(index, "amount_cents")
      iex> entry.type
      :integer
      iex> Datamodel.fetch(index, "amount_dollars")
      :error
  """
  @spec fetch(t(), term()) :: {:ok, entry()} | :error
  def fetch(%__MODULE__{entries: entries}, path) when is_binary(path) do
    Map.fetch(entries, path)
  end

  def fetch(%__MODULE__{}, _path), do: :error

  @doc """
  The declared type of `path`, or `nil` when the document does not declare
  it - unknown, never wrong (ADR-0006 decision 9).

  `nil` is also what a declared entry whose `type` is outside the closed
  set of eight gets, for the same reason: this module reports what it can
  name and claims nothing about the rest.
  """
  @spec type(t(), term()) :: type() | nil
  def type(%__MODULE__{} = index, path) do
    case fetch(index, path) do
      {:ok, entry} -> entry.type
      :error -> nil
    end
  end

  @doc """
  Whether the document declares `path`.

  A `false` here is *this document does not declare it*, which is the
  input to `11e`'s `:info` advisory and to nothing that refuses anything.
  """
  @spec declared?(t(), term()) :: boolean()
  def declared?(%__MODULE__{} = index, path) do
    match?({:ok, _entry}, fetch(index, path))
  end

  @doc """
  Every entry strictly under `prefix`, at any depth, in document order -
  the completion query.

  The entry at `prefix` itself is not among them; `fetch/2` is how a
  caller asks about the prefix. A caller wanting one level only filters
  the result on `depth`.

      iex> alias StatifierBlocks.Predicates.Datamodel
      iex> index = Datamodel.index(%{"scopes" => [%{"scope" => "local", "entries" => [
      ...>   %{"path" => "card", "type" => "object", "fields" => [
      ...>     %{"path" => "card.brand"}, %{"path" => "card.last4"}]},
      ...>   %{"path" => "cardholder"}]}]})
      iex> index |> Datamodel.under("card") |> Enum.map(& &1.path)
      ["card.brand", "card.last4"]
  """
  @spec under(t(), term()) :: [entry()]
  def under(%__MODULE__{} = index, prefix) when is_binary(prefix) and prefix != "" do
    index
    |> entries()
    |> Enum.filter(&String.starts_with?(&1.path, prefix <> "."))
  end

  def under(%__MODULE__{}, _prefix), do: []

  # -- normalization ---------------------------------------------------------

  @spec version(term()) :: integer()
  defp version(v) when is_integer(v), do: v
  defp version(_absent_or_malformed), do: 1

  @spec scope_entries(term()) :: [entry()]
  defp scope_entries(%{"entries" => entries} = scope) when is_list(entries) do
    name = scope_name(Map.get(scope, "scope"))
    Enum.flat_map(entries, &entry(&1, name, 0))
  end

  defp scope_entries(_unrecognized), do: []

  @spec scope_name(term()) :: scope()
  defp scope_name(name) when is_binary(name), do: Map.get(@scopes, name)
  defp scope_name(_other), do: nil

  # Decision 6's `entry_paths/1`, carrying the whole entry rather than its
  # path alone: an entry contributes itself when it has a path, and its
  # `fields` are walked either way.
  @spec entry(term(), scope(), non_neg_integer()) :: [entry()]
  defp entry(%{} = raw, scope, depth) do
    own =
      case Map.get(raw, "path") do
        path when is_binary(path) and path != "" -> [normalize(raw, path, scope, depth)]
        _absent_or_malformed -> []
      end

    own ++ fields(Map.get(raw, "fields"), scope, depth + 1)
  end

  defp entry(_unrecognized, _scope, _depth), do: []

  @spec fields(term(), scope(), non_neg_integer()) :: [entry()]
  defp fields(fields, scope, depth) when is_list(fields) do
    Enum.flat_map(fields, &entry(&1, scope, depth))
  end

  defp fields(_absent, _scope, _depth), do: []

  @spec normalize(map(), String.t(), scope(), non_neg_integer()) :: entry()
  defp normalize(raw, path, scope, depth) do
    %{
      path: path,
      name: string(Map.get(raw, "name")),
      type: entry_type(Map.get(raw, "type")),
      label: string(Map.get(raw, "label")),
      scope: scope,
      depth: depth,
      item_type: entry_type(Map.get(raw, "item_type")),
      example: Map.get(raw, "example"),
      note: string(Map.get(raw, "note")),
      one_of: list(Map.get(raw, "one_of")),
      sensitive?: Map.get(raw, "sensitive?") == true
    }
  end

  @spec entry_type(term()) :: type() | nil
  defp entry_type(t) when is_binary(t), do: Map.get(@types, t)
  defp entry_type(_outside_the_closed_set), do: nil

  @spec string(term()) :: String.t() | nil
  defp string(value) when is_binary(value), do: value
  defp string(_other), do: nil

  @spec list(term()) :: [term()] | nil
  defp list(value) when is_list(value), do: value
  defp list(_other), do: nil

  # First occurrence wins, so the index agrees with `order`.
  @spec dedupe([entry()]) :: %{optional(String.t()) => entry()}
  defp dedupe(entries) do
    Enum.reduce(entries, %{}, fn entry, acc ->
      Map.put_new(acc, entry.path, entry)
    end)
  end
end
