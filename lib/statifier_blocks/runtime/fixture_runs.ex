defmodule StatifierBlocks.Runtime.FixtureRuns do
  @moduledoc """
  Turns `(document, palette, fixtures)` into a list of per-row verdicts, by
  compiling the document once and driving the compiled chart once per
  fixture row (`sb-4yze`, Phase 1).

  ## Namespace: `StatifierBlocks.Runtime.*`, not `StatifierBlocks.Fixtures.*`

  This module runs a chart at session time - `Statifier.compile/2` plus one
  `Statifier.initialize/2` per row - rather than authoring anything, and
  `lib/statifier_blocks/runtime/subchart.ex`'s moduledoc already set the
  precedent for what that half of the package is called:
  `StatifierBlocks.Runtime.*` reads as "the half that runs", set against the
  authoring half that is everything else in `lib/`.

  ## Unguarded, on purpose

  Every LiveView module in this package sits behind an
  `Code.ensure_loaded?(...)` presence check on the LiveView library itself
  (ADR-0005 decision 1). This module carries no such guard and names no
  LiveView module, because it is not a LiveView concern - it is a pure
  function of a document, a palette and a fixtures source, and
  `StatifierBlocks.Shell`'s own moduledoc states the rule this follows:
  "what is worth testing goes in `lib/statifier_blocks/`, unguarded." The
  headless suite (the one CI job proves compiles and passes with that
  library entirely absent) exercises this module directly.

  ## Why this calls `Statifier.compile/2` and `Statifier.initialize/2` directly

  `Statifier.Testing.Case` is the ExUnit case template that names the
  four-function driving surface (`compile/2`, `initialize/2`, `send_event/2`,
  `active_leaf_states/1` - ADR-0053, ADR-0006). It is `use`-able only from a
  test, and its own moduledoc forbids any module under `lib/` outside
  `Statifier.Testing.*` from referencing anything inside it. So this module
  calls the four functions on `Statifier` itself - that direct call *is* the
  ADR-0053 surface, not a way around it - and the test suite below is free
  to `use Statifier.Testing.Case` where that helps.

  ## `:declare` is the host's raw list, never `host_roots`

  `opts[:declare]` is forwarded verbatim to `StatifierBlocks.Compiler.compile/3`
  as its own `:declare` option: the host's raw `{id, expr}` declaration
  **list**. It is never the derived `host_roots` a LiveView editor keeps (a
  `MapSet.t(String.t())` of root ids, built for undeclared-path advisories) -
  `StatifierBlocks.Compiler.DeclaredRoots.declarations/1` answers a `MapSet`
  with `{:error, [{:invalid_declaration, _}]}`, so passing one here would
  fail every compile.
  """

  alias Statifier.Machine
  alias StatifierBlocks.{Compiled, Compiler, Document, Palette, Provenance, Shell, ViewModel}
  alias StatifierBlocks.Compiler.Finding
  alias StatifierBlocks.Predicates.TruthTable

  defmodule Run do
    @moduledoc """
    One fixture row driven through the compiled chart, and what happened.

    See `StatifierBlocks.Runtime.FixtureRuns`'s moduledoc for what each
    `verdict` value means.
    """

    @type verdict ::
            :pass | :fail | :row_error | :no_expectation | :not_comparable | :unreached

    @type t :: %__MODULE__{
            block_id: StatifierBlocks.Block.id(),
            table_name: String.t() | nil,
            row_name: String.t() | nil,
            expected_slot: String.t() | nil,
            taken_slot: String.t() | nil,
            verdict: verdict(),
            detail: term(),
            bindings: %{optional(String.t()) => String.t()}
          }

    @enforce_keys [:block_id, :table_name, :row_name, :verdict]
    defstruct [
      :block_id,
      :table_name,
      :row_name,
      :expected_slot,
      :taken_slot,
      :verdict,
      :detail,
      bindings: %{}
    ]
  end

  @typedoc """
  `:no_fixtures` - the fixtures source is `nil`, or holds no table for any
  block. `:compile_error` - the document does not compile (normal mid-edit,
  not exceptional); `findings` carries why. `:ready` - every row in `runs`
  was driven.
  """
  @type status :: :no_fixtures | :compile_error | :ready

  @type t :: %__MODULE__{
          status: status(),
          runs: [Run.t()],
          findings: [Finding.t()],
          row_count: non_neg_integer(),
          failure_count: non_neg_integer()
        }

  defstruct status: :no_fixtures, runs: [], findings: [], row_count: 0, failure_count: 0

  @doc """
  Compiles `document` against `palette` once and drives every fixture row
  in `fixtures` once, returning a `t()`.

  `opts`:

    * `:declare` - forwarded verbatim to `StatifierBlocks.Compiler.compile/3`
      as its own `:declare` option. Defaults to `[]`. This is the host's raw
      `{id, expr}` declaration list, **never** the derived `host_roots`
      `MapSet` a LiveView editor keeps - see the moduledoc.
    * `:view_model` - an already-built `%StatifierBlocks.ViewModel{}`. A
      caller that already has one (an editor always does) should pass it
      rather than have this function build a second one. When absent, this
      function builds its own with `ViewModel.build(document, palette, [])`.
  """
  @spec run(Document.t(), Palette.t(), Shell.fixtures(), keyword()) :: t()
  def run(%Document{} = document, %Palette{} = palette, fixtures, opts \\ [])
      when is_list(opts) do
    if no_fixtures?(fixtures) do
      %__MODULE__{status: :no_fixtures}
    else
      declare = Keyword.get(opts, :declare, [])

      case Compiler.compile(document, palette, declare: declare) do
        {:error, findings} ->
          %__MODULE__{status: :compile_error, findings: findings}

        {:ok, %Compiled{scxml: scxml, provenance: provenance}} ->
          build_result(document, palette, fixtures, scxml, provenance, opts)
      end
    end
  end

  @spec build_result(
          Document.t(),
          Palette.t(),
          Shell.fixtures(),
          binary(),
          Provenance.t(),
          keyword()
        ) ::
          t()
  defp build_result(document, palette, fixtures, scxml, provenance, opts) do
    case Statifier.compile(scxml, chart_name: document.id) do
      {:error, _errors} ->
        %__MODULE__{status: :compile_error, findings: [generated_chart_finding(document)]}

      {:ok, machine} ->
        view_model =
          Keyword.get_lazy(opts, :view_model, fn -> ViewModel.build(document, palette, []) end)

        runs = drive_all(fixtures, machine, provenance, view_model)

        %__MODULE__{
          status: :ready,
          runs: runs,
          row_count: length(runs),
          failure_count: Enum.count(runs, &(&1.verdict == :fail))
        }
    end
  end

  # The document's own compile already ran these bytes through
  # `Statifier.compile/2` (the Chart stage, `StatifierBlocks.Compiler.Chart`),
  # so this branch is defensive rather than expected to fire in practice -
  # but a generated-bytes bug in this package would otherwise raise inside
  # `Statifier.compile/2` below rather than reporting a finding, which is
  # exactly the crashed-editor outcome this whole module exists to avoid.
  @spec generated_chart_finding(Document.t()) :: Finding.t()
  defp generated_chart_finding(%Document{root: root}) do
    Finding.new(
      :chart,
      :generated_chart_invalid,
      "The generated chart did not compile.",
      block_id: root.id,
      fault: :package
    )
  end

  @spec no_fixtures?(Shell.fixtures()) :: boolean()
  defp no_fixtures?(fixtures), do: Shell.table_block_ids(fixtures) == []

  @spec drive_all(Shell.fixtures(), Machine.t(), Provenance.t(), ViewModel.t()) :: [Run.t()]
  defp drive_all(fixtures, machine, provenance, view_model) do
    for block_id <- Shell.table_block_ids(fixtures),
        table <- Shell.tables_for(fixtures, block_id),
        row <- table.rows do
      drive_row(block_id, table, row, machine, provenance, view_model)
    end
  end

  @spec drive_row(
          StatifierBlocks.Block.id(),
          TruthTable.t(),
          TruthTable.Row.t(),
          Machine.t(),
          Provenance.t(),
          ViewModel.t()
        ) :: Run.t()
  defp drive_row(
         block_id,
         table,
         %TruthTable.Row{error: error} = row,
         _machine,
         _provenance,
         _view_model
       )
       when not is_nil(error) do
    # A row whose bindings themselves failed to build a context is checked
    # first, before any driving - `TruthTable`'s own moduledoc prescribes
    # this order for a renderer: check `row.error` before looking at cells.
    %Run{
      block_id: block_id,
      table_name: table.name,
      row_name: row.name,
      verdict: :row_error,
      detail: error,
      bindings: row.bindings
    }
  end

  defp drive_row(block_id, table, %TruthTable.Row{} = row, machine, provenance, view_model) do
    entered_ids = enter_row(machine, row)
    entered_block_ids = owner_ids(provenance, entered_ids)
    node = find_node(view_model.root, block_id)

    {verdict, expected_slot, taken_slot, detail} =
      verdict_for(node, row, entered_block_ids)

    %Run{
      block_id: block_id,
      table_name: table.name,
      row_name: row.name,
      expected_slot: expected_slot,
      taken_slot: taken_slot,
      verdict: verdict,
      detail: detail,
      bindings: row.bindings
    }
  rescue
    # `Statifier.initialize/2`'s `:datamodel` option raises `ArgumentError`
    # unless every key is a string at every level
    # (`Statifier.MachineState.checked_datamodel!/1`).
    # `StatifierBlocks.Predicates.context/1` always produces a string-keyed
    # map, but a host builds these tables, so the guard stays: a raise here
    # becomes a `:row_error` verdict, never a crashed editor.
    e in ArgumentError ->
      %Run{
        block_id: block_id,
        table_name: table.name,
        row_name: row.name,
        verdict: :row_error,
        detail: Exception.message(e),
        bindings: row.bindings
      }
  end

  # No `Statifier.send_event/2` call: a `%TruthTable.Row{}` carries bindings
  # and a context, never an event, and `core.branch` compiles to a compound
  # state whose `initial` is a transient `pick` state
  # (`StatifierBlocks.Core.Branch`) - the pick fires inside `initialize/2`'s
  # own macrostep. `send_event/2` is the seam for the day a row carries an
  # event; nothing here reaches for it.
  @spec enter_row(Machine.t(), TruthTable.Row.t()) :: [String.t()]
  defp enter_row(machine, %TruthTable.Row{context: context}) do
    {machine_state, _effects} = Statifier.initialize(machine, datamodel: context)

    machine_state.entered_states
    |> Enum.map(&Machine.id(machine, &1))
    |> Enum.reject(&is_nil/1)
  end

  @spec owner_ids(Provenance.t(), [String.t()]) :: MapSet.t(StatifierBlocks.Block.id())
  defp owner_ids(provenance, entered_ids) do
    provenance
    |> Provenance.owners_of_states(entered_ids)
    |> MapSet.new(& &1.block_id)
  end

  @spec verdict_for(
          ViewModel.Node.t() | nil,
          TruthTable.Row.t(),
          MapSet.t(StatifierBlocks.Block.id())
        ) ::
          {Run.verdict(), String.t() | nil, String.t() | nil, term()}
  defp verdict_for(nil, _row, _entered_block_ids) do
    {:not_comparable, nil, nil, :block_not_in_view_model}
  end

  defp verdict_for(%ViewModel.Node{} = node, row, entered_block_ids) do
    case expected_slot(row) do
      {:error, reason} ->
        {:no_expectation, nil, nil, reason}

      {:ok, expected} ->
        declared_names = Enum.map(node.slots, & &1.name)

        if expected in declared_names do
          resolve_taken(node, expected, entered_block_ids)
        else
          {:not_comparable, expected, nil, {:unknown_slot, expected}}
        end
    end
  end

  @spec resolve_taken(ViewModel.Node.t(), String.t(), MapSet.t(StatifierBlocks.Block.id())) ::
          {Run.verdict(), String.t(), String.t() | nil, term()}
  defp resolve_taken(node, expected, entered_block_ids) do
    case taken_slot(node, entered_block_ids) do
      {:ok, taken} ->
        verdict = if taken == expected, do: :pass, else: :fail
        {verdict, expected, taken, nil}

      :unreached ->
        {:unreached, expected, nil, nil}

      {:not_comparable, detail} ->
        {:not_comparable, expected, nil, detail}
    end
  end

  # A row's declared answer for one column: the `column_key` of the single
  # cell whose `expected` is `true`. None -> nothing to compare against
  # (`:no_expectation`). More than one is impossible under first-match-wins
  # but is folded to `:no_expectation` rather than raised on.
  @spec expected_slot(TruthTable.Row.t()) :: {:ok, String.t()} | {:error, term()}
  defp expected_slot(%TruthTable.Row{cells: cells}) do
    case Enum.filter(cells, &(&1.expected == true)) do
      [%TruthTable.Cell{column_key: key}] -> {:ok, key}
      [] -> {:error, :no_expected_column}
      many -> {:error, {:ambiguous_expected_columns, Enum.map(many, & &1.column_key)}}
    end
  end

  # Walks the fixture block's declared slots in declaration order and
  # returns the name of the first slot any of whose descendant blocks, at
  # any depth, is in `entered_block_ids`.
  #
  # Two fallbacks when no slot matches directly:
  #
  #   * the block's own id is entered and exactly one slot is empty -> that
  #     slot, by elimination. This is the empty `otherwise` case:
  #     `Core.Branch.emit/2` targets an empty arm's transition straight at
  #     the block's own `<final>`, minting no state of its own, so an empty
  #     arm can only be identified this way. Two or more empty slots is
  #     `:not_comparable` - arms are `:at_least_one` and `otherwise` is
  #     `:any`, so at most one slot is ever empty in a valid document, and
  #     seeing more than one here means the block is not the single-empty-arm
  #     shape this inference is sound for. `core.branch`'s `undecided` slot
  #     is excluded from the count when it is empty, for the reason
  #     `candidate_empty_slot?/2` gives.
  #   * the block's own id is not entered -> `:unreached`. The chart never
  #     got to this block with this row's datamodel.
  @spec taken_slot(ViewModel.Node.t(), MapSet.t(StatifierBlocks.Block.id())) ::
          {:ok, String.t()} | :unreached | {:not_comparable, term()}
  defp taken_slot(%ViewModel.Node{slots: slots} = node, entered_block_ids) do
    case Enum.find(slots, &slot_entered?(&1, entered_block_ids)) do
      %ViewModel.Slot{name: name} -> {:ok, name}
      nil -> taken_slot_by_elimination(node, entered_block_ids)
    end
  end

  defp taken_slot_by_elimination(
         %ViewModel.Node{block_id: block_id, slots: slots} = node,
         entered_block_ids
       ) do
    if MapSet.member?(entered_block_ids, block_id) do
      case Enum.filter(slots, &(&1.children == [] and candidate_empty_slot?(node, &1))) do
        [%ViewModel.Slot{name: name}] ->
          {:ok, name}

        empty_slots ->
          {:not_comparable, {:ambiguous_empty_slots, Enum.map(empty_slots, & &1.name)}}
      end
    else
      :unreached
    end
  end

  # Whether an empty slot is a destination the emission could have taken,
  # and so a candidate for the elimination above.
  #
  # Every empty slot is one, with a single exception. `core.branch`'s
  # `undecided` slot emits **no transition at all** while it holds no
  # children (ADR-0012 decision 3): an undecided condition then falls to
  # `otherwise` exactly as it did at 0.20.0, and decision 9 names the empty
  # slot in those words - "not a path out of the block". Counting it would
  # make every branch with an empty `otherwise` - the shape this inference
  # exists for - read `:ambiguous_empty_slots` instead.
  #
  # A **wired** `undecided` slot is not empty, so it never reaches here: it
  # holds children, and the walk above finds it the ordinary way.
  @spec candidate_empty_slot?(ViewModel.Node.t(), ViewModel.Slot.t()) :: boolean()
  defp candidate_empty_slot?(%ViewModel.Node{type: "core.branch"}, %ViewModel.Slot{
         name: "undecided"
       }),
       do: false

  defp candidate_empty_slot?(_node, _slot), do: true

  @spec slot_entered?(ViewModel.Slot.t(), MapSet.t(StatifierBlocks.Block.id())) :: boolean()
  defp slot_entered?(%ViewModel.Slot{children: children}, entered_block_ids) do
    Enum.any?(children, &node_entered?(&1, entered_block_ids))
  end

  @spec node_entered?(ViewModel.Node.t(), MapSet.t(StatifierBlocks.Block.id())) :: boolean()
  defp node_entered?(%ViewModel.Node{block_id: block_id, slots: slots}, entered_block_ids) do
    MapSet.member?(entered_block_ids, block_id) or
      Enum.any?(slots, &slot_entered?(&1, entered_block_ids))
  end

  @spec find_node(ViewModel.Node.t(), StatifierBlocks.Block.id()) :: ViewModel.Node.t() | nil
  defp find_node(%ViewModel.Node{block_id: id} = node, id), do: node

  defp find_node(%ViewModel.Node{slots: slots}, id) do
    Enum.find_value(slots, fn %ViewModel.Slot{children: children} ->
      Enum.find_value(children, &find_node(&1, id))
    end)
  end
end
