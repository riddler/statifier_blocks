defmodule StatifierBlocks.Predicates.TruthTable do
  @moduledoc """
  A table spec plus rows in, a struct with per-cell outcomes, first-match-wins
  selection and expectation status out.

  ## Why `expected` is compared against selection, not raw truth

  `core.branch` (`lib/statifier_blocks/core/branch.ex`, ADR-0002 decision 10)
  stores an ordered `arms` list and tries them in order: the first arm whose
  condition holds runs, and every later arm is skipped even if its own
  condition would also hold. That ordering is a config-level fact, not an
  implementation detail - the branch's moduledoc says arms are tried in order
  and `slots/1` returns them in that order followed by `otherwise`.

  So a truth table over a branch has to model the same thing a branch does:
  which arm is *taken*, not which arms are individually true. A cell here
  carries both readings. `outcome` is the raw `{:ok, boolean()} | {:error,
  reason}` from `Predicates.evaluate/2` - what the expression alone says.
  `selected?` is `true | false | :undecidable`, from one ordered
  first-match-wins pass over the row's columns, mirroring what `core.branch`
  would actually run. `expected`, a row's declared answer for one column, is
  compared against `selected?` rather than `outcome`, because "does this
  fixture behave like the branch it describes" is a question about which arm
  wins, not about which conditions are independently true. Two columns can
  both raw-evaluate `true` in the same row; at most one of them is selected.

  ## The `otherwise` column

  At most one column may carry `source: nil` - the `otherwise` column - and
  it is never evaluated as an expression (`outcome: nil`). It must be the
  last column if present, because it is the branch's fallback arm and a
  fallback that could still be overridden by a later real arm would not be a
  fallback. `build/2` rejects a spec that breaks either rule before touching
  any row.

  ## The five-value `status`

  `status` is deliberately wider than a `true | false | unset` tri-state,
  because "the row's expectation was contradicted" and "this cell's answer is
  unknowable" are different findings that a renderer, and an author reading
  one, need to tell apart:

    * `:match` - `selected?` is a boolean and equals `expected`.
    * `:mismatch` - `selected?` is a boolean and differs from `expected`.
    * `:unchecked` - `selected?` is a boolean but the row declares no
      `expected` value for this column.
    * `:error` - this column's own `outcome` is an error; nothing about
      selection can be said until the expression itself is fixed.
    * `:undecidable` - this column's own `outcome` is fine, but an *earlier*
      column in the row errored, so whether this column would even have been
      reached is unknown. Reporting `false` here would claim "no arm before
      this one matched", which is a guess this package does not make.

  A row's bindings can also fail to build a context at all (an undefined
  variable, a binding conflict). Then the whole row carries `error: reason`
  and `cells: []` rather than guessing at any column - a renderer checks
  `row.error` first.
  """

  alias StatifierBlocks.Predicates

  defmodule Column do
    @moduledoc """
    One truth-table column: a key, a display label, and a predicator source
    string, or `source: nil` for the `otherwise` column.
    """

    defstruct [:key, :label, :source]

    @type t :: %__MODULE__{key: String.t(), label: String.t(), source: String.t() | nil}
  end

  defmodule Cell do
    @moduledoc """
    One row/column intersection: the raw evaluation `outcome`, whether the
    column was `selected?` under first-match-wins, the row's declared
    `expected` answer (if any), and the derived `status`. See
    `StatifierBlocks.Predicates.TruthTable`'s moduledoc for what each
    `status` value means.
    """

    defstruct [:column_key, :outcome, :selected?, :expected, :status]

    @type status :: :match | :mismatch | :unchecked | :error | :undecidable

    @type t :: %__MODULE__{
            column_key: String.t(),
            outcome: {:ok, boolean()} | {:error, Predicates.reason()} | nil,
            selected?: boolean() | :undecidable,
            expected: boolean() | nil,
            status: status()
          }
  end

  defmodule Row do
    @moduledoc """
    One truth-table row: the bindings that build its context, the resulting
    cells (or a row-level `error` when the bindings themselves fail), and an
    optional author-facing `note`.
    """

    defstruct [:name, :bindings, :note, :context, :error, cells: []]

    @type t :: %__MODULE__{
            name: String.t(),
            bindings: %{optional(String.t()) => String.t()},
            note: String.t() | nil,
            context: Predicates.context() | nil,
            error: Predicates.reason() | nil,
            cells: [Cell.t()]
          }
  end

  defstruct [:name, :description, :columns, :paths, rows: []]

  @type t :: %__MODULE__{
          name: String.t(),
          description: String.t() | nil,
          columns: [Column.t()],
          paths: [String.t()],
          rows: [Row.t()]
        }

  @type build_error ::
          {:duplicate_column, String.t()}
          | {:otherwise_not_last, String.t()}
          | {:invalid_source, String.t()}

  @doc """
  Builds a `%TruthTable{}` from a table `spec` and a list of row `spec`s.

  Validates the spec first - column keys must be unique
  (`{:error, {:duplicate_column, key}}`), at most one column may have
  `source: nil` and it must be last (`{:error, {:otherwise_not_last, key}}`),
  and every column's `source` must be a binary or `nil`
  (`{:error, {:invalid_source, key}}`). A malformed spec is an error return;
  a failing *cell* is data, because showing which cells fail is the point of
  the table - rows still build and render around a bad cell or a bad row.
  """
  @spec build(spec :: map(), rows :: [map()]) :: {:ok, t()} | {:error, build_error()}
  def build(spec, rows) when is_map(spec) and is_list(rows) do
    columns = spec |> Map.get(:columns, []) |> Enum.map(&to_column/1)

    with :ok <- validate_unique(columns),
         :ok <- validate_otherwise_last(columns),
         :ok <- validate_sources(columns) do
      built_rows = Enum.map(rows, &build_row(&1, columns))

      {:ok,
       %__MODULE__{
         name: Map.get(spec, :name),
         description: Map.get(spec, :description),
         columns: columns,
         paths: paths(spec, rows),
         rows: built_rows
       }}
    end
  end

  @doc """
  Flattens every cell's `status` across every row, in row-then-column order,
  so a caller can assert a whole table's shape in one pattern match.
  """
  @spec statuses(t()) :: [Cell.status()]
  def statuses(%__MODULE__{rows: rows}) do
    Enum.flat_map(rows, fn %Row{cells: cells} -> Enum.map(cells, & &1.status) end)
  end

  defp to_column(%{key: key} = spec) do
    %Column{key: key, label: Map.get(spec, :label, key), source: Map.get(spec, :source)}
  end

  defp validate_unique(columns) do
    columns
    |> Enum.map(& &1.key)
    |> Enum.reduce_while(MapSet.new(), fn key, seen ->
      if MapSet.member?(seen, key) do
        {:halt, {:error, {:duplicate_column, key}}}
      else
        {:cont, MapSet.put(seen, key)}
      end
    end)
    |> case do
      {:error, _reason} = error -> error
      %MapSet{} -> :ok
    end
  end

  defp validate_otherwise_last(columns) do
    last_index = length(columns) - 1

    columns
    |> Enum.with_index()
    |> Enum.filter(fn {%Column{source: source}, _index} -> is_nil(source) end)
    |> Enum.find(fn {_column, index} -> index != last_index end)
    |> case do
      nil -> :ok
      {%Column{key: key}, _index} -> {:error, {:otherwise_not_last, key}}
    end
  end

  defp validate_sources(columns) do
    Enum.reduce_while(columns, :ok, fn %Column{key: key, source: source}, :ok ->
      if is_binary(source) or is_nil(source) do
        {:cont, :ok}
      else
        {:halt, {:error, {:invalid_source, key}}}
      end
    end)
  end

  defp paths(spec, rows) do
    case Map.get(spec, :paths) do
      nil ->
        rows
        |> Enum.flat_map(fn row -> row |> Map.get(:bindings, %{}) |> Map.keys() end)
        |> Enum.uniq()
        |> Enum.sort()

      paths ->
        paths
    end
  end

  defp build_row(row_spec, columns) do
    bindings = Map.get(row_spec, :bindings, %{})
    name = Map.get(row_spec, :name)
    note = Map.get(row_spec, :note)
    expected = Map.get(row_spec, :expected, %{})

    case Predicates.context(bindings) do
      {:ok, context} ->
        %Row{
          name: name,
          bindings: bindings,
          note: note,
          context: context,
          error: nil,
          cells: build_cells(columns, context, expected)
        }

      {:error, reason} ->
        %Row{name: name, bindings: bindings, note: note, context: nil, error: reason, cells: []}
    end
  end

  defp build_cells(columns, context, expected) do
    columns
    |> Enum.map(&outcome_for(&1, context))
    |> select()
    |> Enum.map(fn {column, outcome, selected?} ->
      cell_expected = Map.get(expected, column.key)

      %Cell{
        column_key: column.key,
        outcome: outcome,
        selected?: selected?,
        expected: cell_expected,
        status: status_for(outcome, selected?, cell_expected)
      }
    end)
  end

  defp outcome_for(%Column{source: nil} = column, _context), do: {column, nil, nil}

  defp outcome_for(%Column{source: source} = column, context) do
    {column, Predicates.evaluate(source, context), nil}
  end

  # First-match-wins, one ordered pass: a column is selected iff its outcome
  # is {:ok, true} and no earlier column in this row was already selected.
  # Once an earlier column's outcome is an error, selection for every later
  # column becomes :undecidable rather than false or true.
  defp select(outcome_triples) do
    {cells, _already_selected?, _undecidable?} =
      Enum.reduce(outcome_triples, {[], false, false}, &select_one/2)

    Enum.reverse(cells)
  end

  defp select_one({column, outcome, _}, {acc, already_selected?, undecidable?}) do
    cond do
      undecidable? ->
        {[{column, outcome, :undecidable} | acc], already_selected?, undecidable?}

      match?({:error, _reason}, outcome) ->
        {[{column, outcome, :undecidable} | acc], already_selected?, true}

      already_selected? ->
        {[{column, outcome, false} | acc], already_selected?, undecidable?}

      otherwise_column?(column, outcome) or outcome == {:ok, true} ->
        {[{column, outcome, true} | acc], true, undecidable?}

      true ->
        {[{column, outcome, false} | acc], already_selected?, undecidable?}
    end
  end

  defp otherwise_column?(%Column{source: nil}, nil), do: true
  defp otherwise_column?(_column, _outcome), do: false

  defp status_for({:error, _reason}, _selected?, _expected), do: :error
  defp status_for(_outcome, :undecidable, _expected), do: :undecidable
  defp status_for(_outcome, selected?, nil) when is_boolean(selected?), do: :unchecked

  defp status_for(_outcome, selected?, expected)
       when is_boolean(selected?) and selected? == expected,
       do: :match

  defp status_for(_outcome, selected?, _expected) when is_boolean(selected?), do: :mismatch
end
