defmodule StatifierBlocks.Runtime.FixtureRunsTest do
  @moduledoc """
  Headless unit coverage of `StatifierBlocks.Runtime.FixtureRuns`, every
  status and every verdict.

  `async: true`, **not** tagged `:liveview` and not
  `use StatifierBlocks.EditorLiveCase` - the whole point of this module's
  placement is that it runs with LiveView entirely absent.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{Block, Compiler.Finding, Document, Palette}
  alias StatifierBlocks.Predicates.TruthTable
  alias StatifierBlocks.Runtime.FixtureRuns
  alias StatifierBlocks.Runtime.FixtureRuns.Run

  describe "no_fixtures" do
    # Sabotage: had `no_fixtures?/1` always return `false` -> `nil` fixtures
    # reached `Compiler.compile/3` instead of short-circuiting, and this
    # went red (verified).
    test "fixtures: nil answers :no_fixtures with no runs" do
      document = Document.new(container("blk_ROOT"), id: "bdoc_T")

      assert %FixtureRuns{status: :no_fixtures, runs: []} =
               FixtureRuns.run(document, Palette.core(), nil)
    end

    # Sabotage: had `no_fixtures?/1` always return `false` (same mutation as
    # above) -> `%{}` fixtures reached the compile-and-drive path instead of
    # short-circuiting, and this went red (verified).
    test "fixtures: %{} answers :no_fixtures with no runs" do
      document = Document.new(container("blk_ROOT"), id: "bdoc_T")

      assert %FixtureRuns{status: :no_fixtures, runs: []} =
               FixtureRuns.run(document, Palette.core(), %{})
    end
  end

  describe "compile_error" do
    # Sabotage: had `run/4`'s `{:error, _findings}` clause swallow the
    # findings and return `%__MODULE__{status: :ready}` -> this test went
    # red (verified).
    test "a document that does not compile answers :compile_error with findings" do
      document = Document.new(Block.new("core.nonexistent_type", id: "blk_BAD"), id: "bdoc_T")
      fixtures = %{"blk_BAD" => [passthrough_table()]}

      assert %FixtureRuns{status: :compile_error, runs: [], findings: [%Finding{} | _]} =
               FixtureRuns.run(document, Palette.core(), fixtures)
    end
  end

  describe "a passing row" do
    # Sabotage: swapped the `:pass`/`:fail` branches in `resolve_taken/3`'s
    # `if taken == expected` -> this test went red (verified).
    test "verdict is :pass when the row's expected slot is the slot the chart took" do
      document = branch_document()
      fixtures = %{"blk_BR" => [branch_table([row("over", "150", "arm_a")])]}

      assert %FixtureRuns{status: :ready, row_count: 1, failure_count: 0, runs: [run]} =
               FixtureRuns.run(document, Palette.core(), fixtures)

      assert %Run{
               block_id: "blk_BR",
               expected_slot: "arm_a",
               taken_slot: "arm_a",
               verdict: :pass
             } = run
    end
  end

  describe "a failing row" do
    # Sabotage: made `owner_ids/2` always return an empty `MapSet` (as if
    # provenance never resolved any owner) -> `taken_slot/2` found no
    # matching slot and fell to the elimination fallback, which itself
    # bailed to `:unreached` because the block's own id was no longer
    # "entered" -> verdict read :unreached instead of :fail (verified red).
    test "verdict is :fail when the row expects the arm not taken" do
      document = branch_document()

      # amount = 150 takes "arm_a" (150 > 100); the row wrongly expects
      # "otherwise" instead.
      fixtures = %{"blk_BR" => [branch_table([row("wrong", "150", "otherwise")])]}

      assert %FixtureRuns{status: :ready, row_count: 1, failure_count: 1, runs: [run]} =
               FixtureRuns.run(document, Palette.core(), fixtures)

      assert %Run{expected_slot: "otherwise", taken_slot: "arm_a", verdict: :fail} = run
    end
  end

  describe "a row whose bindings error" do
    # Sabotage: checked `row.error` after driving instead of before ->
    # `Statifier.initialize/2` would have been called with `row.context`
    # (`nil` for an errored row) and raised, rather than this test's
    # `:row_error` verdict being reached at all (verified red: the whole
    # run/4 call raised).
    test "verdict is :row_error before any driving happens" do
      document = branch_document()

      bad_row_spec = %{
        name: "undefined_binding",
        bindings: %{"amount" => "totally_undefined_variable"},
        expected: %{"arm_a" => true}
      }

      {:ok, table} = TruthTable.build(branch_table_spec(), [bad_row_spec])
      fixtures = %{"blk_BR" => [table]}

      assert %FixtureRuns{status: :ready, runs: [run]} =
               FixtureRuns.run(document, Palette.core(), fixtures)

      assert %Run{verdict: :row_error, detail: detail} = run

      assert match?(
               {:binding, "amount", {:undefined_variable, "totally_undefined_variable", _}},
               detail
             )
    end

    # Sabotage: removed the `rescue e in ArgumentError` clause from
    # `drive_row/6` -> a row whose context carries a non-string key raised
    # `ArgumentError` straight out of `run/4` instead of yielding a
    # `:row_error` verdict (verified red).
    test "a raise from Statifier.initialize/2's :datamodel option becomes :row_error, not a crash" do
      document = branch_document()
      table = hand_built_table_with_bad_context()
      fixtures = %{"blk_BR" => [table]}

      assert %FixtureRuns{status: :ready, runs: [run]} =
               FixtureRuns.run(document, Palette.core(), fixtures)

      assert %Run{verdict: :row_error, detail: detail} = run
      assert is_binary(detail)
    end
  end

  describe "a row declaring no expected: true" do
    # Sabotage: made `verdict_for/3`'s `{:error, reason}` clause return
    # `:fail` instead of `:no_expectation` -> this test went red (verified).
    test "verdict is :no_expectation" do
      document = branch_document()

      row_spec = %{name: "unmarked", bindings: %{"amount" => "150"}, expected: %{}}
      {:ok, table} = TruthTable.build(branch_table_spec(), [row_spec])
      fixtures = %{"blk_BR" => [table]}

      assert %FixtureRuns{status: :ready, runs: [%Run{verdict: :no_expectation}]} =
               FixtureRuns.run(document, Palette.core(), fixtures)
    end
  end

  describe "a table attached to a block that is not a core.branch" do
    # Sabotage: skipped the `expected in declared_names` check entirely and
    # went straight to `resolve_taken/3` -> the real slot the chart took
    # ("body") was compared against the bogus expected key ("not_a_slot")
    # and this read :fail instead of :not_comparable (verified red).
    test "verdict is :not_comparable when the expected column names no declared slot" do
      root = sequence([container("blk_A")])
      document = Document.new(root, id: "bdoc_T")

      spec = %{name: "not a branch", columns: [%{key: "not_a_slot", source: "true"}]}
      {:ok, table} = TruthTable.build(spec, [%{name: "row", expected: %{"not_a_slot" => true}}])
      fixtures = %{"blk_SEQ" => [table]}

      assert %FixtureRuns{status: :ready, runs: [run]} =
               FixtureRuns.run(document, Palette.core(), fixtures)

      assert %Run{verdict: :not_comparable, expected_slot: "not_a_slot", taken_slot: nil} = run
    end
  end

  describe "a branch nested under an unreachable arm" do
    # Sabotage: inverted `taken_slot_by_elimination/2`'s
    # `not MapSet.member?(entered_block_ids, block_id)` guard (dropped the
    # `not`) -> a block that was never entered was treated as entered, so
    # this test read `:not_comparable` (from the ambiguous-empty-slots
    # fallback, since neither of the inner branch's own arms is actually
    # empty) instead of `:unreached` (verified red).
    test "verdict is :unreached" do
      inner =
        Block.new("core.branch",
          id: "blk_INNER",
          config: %{"arms" => [%{"slot" => "arm_y", "cond" => "true"}]},
          slots: %{
            "arm_y" => [container("blk_Y")],
            "otherwise" => [container("blk_Z")]
          }
        )

      outer =
        Block.new("core.branch",
          id: "blk_OUTER",
          config: %{"arms" => [%{"slot" => "arm_x", "cond" => "trigger"}]},
          slots: %{
            "arm_x" => [inner],
            "otherwise" => [container("blk_OTH")]
          }
        )

      document = Document.new(outer, id: "bdoc_T")

      spec = %{
        name: "inner",
        columns: [
          %{key: "arm_y", source: "true"},
          %{key: "otherwise", source: nil}
        ]
      }

      row_spec = %{
        name: "outer takes otherwise",
        bindings: %{"trigger" => "false"},
        expected: %{"arm_y" => true}
      }

      {:ok, table} = TruthTable.build(spec, [row_spec])
      fixtures = %{"blk_INNER" => [table]}

      assert %FixtureRuns{status: :ready, runs: [run]} =
               FixtureRuns.run(document, Palette.core(), fixtures)

      assert %Run{verdict: :unreached, taken_slot: nil} = run
    end
  end

  describe "an empty otherwise taken by elimination" do
    # Sabotage: had `taken_slot_by_elimination/2` require the empty slot's
    # name to literally be `"otherwise"` instead of finding it by
    # `children == []` -> this test's arm (`"arm_full"`, not named
    # "otherwise" for this assertion's own children shape) still passed by
    # coincidence, so the mutation was instead: swap `== []` for `== nil` in
    # the filter, which never matches an ordinary `%Slot{children: []}` and
    # turned every case here into `:not_comparable` (verified red).
    test "the empty declared-but-unfilled slot is taken by elimination" do
      root =
        Block.new("core.branch",
          id: "blk_ELIM",
          config: %{"arms" => [%{"slot" => "arm_full", "cond" => "false"}]},
          slots: %{"arm_full" => [container("blk_FULL")]}
        )

      document = Document.new(root, id: "bdoc_T")

      spec = %{
        name: "elim",
        columns: [
          %{key: "arm_full", source: "false"},
          %{key: "otherwise", source: nil}
        ]
      }

      row_spec = %{name: "falls through", bindings: %{}, expected: %{"otherwise" => true}}
      {:ok, table} = TruthTable.build(spec, [row_spec])
      fixtures = %{"blk_ELIM" => [table]}

      assert %FixtureRuns{status: :ready, runs: [run]} =
               FixtureRuns.run(document, Palette.core(), fixtures)

      assert %Run{expected_slot: "otherwise", taken_slot: "otherwise", verdict: :pass} = run
    end
  end

  describe "row_count and failure_count" do
    # Sabotage: computed `failure_count` as `Enum.count(runs, &(&1.verdict == :pass))`
    # instead of `== :fail` -> this test's failure_count read 2 (the two
    # passing rows) instead of 1 (verified red).
    test "row_count is every row across every table, failure_count only :fail" do
      document = branch_document()

      rows = [
        row("pass_1", "150", "arm_a"),
        row("pass_2", "50", "otherwise"),
        row("fail_1", "150", "otherwise")
      ]

      fixtures = %{"blk_BR" => [branch_table(rows)]}

      assert %FixtureRuns{status: :ready, row_count: 3, failure_count: 1} =
               FixtureRuns.run(document, Palette.core(), fixtures)
    end
  end

  describe "the taken arm depends on the datamodel" do
    # Sabotage: passed `row.bindings` instead of `row.context` as the
    # `:datamodel` option to `Statifier.initialize/2` -> `bindings` is
    # `%{"amount" => "150"}` (source text, unevaluated), which
    # `checked_datamodel!/1` accepts as a plain string value but which the
    # arm's own `"amount > 100"` expression cannot compare numerically, so
    # every row landed on the same (wrong) arm every time (verified red:
    # both rows below took the same slot).
    test "two rows in the same document take two different slots" do
      document = branch_document()

      fixtures = %{
        "blk_BR" => [branch_table([row("over", "150", "arm_a"), row("under", "50", "otherwise")])]
      }

      assert %FixtureRuns{status: :ready, runs: [over, under]} =
               FixtureRuns.run(document, Palette.core(), fixtures)

      assert over.taken_slot == "arm_a"
      assert under.taken_slot == "otherwise"
      assert over.taken_slot != under.taken_slot
    end
  end

  # -- helpers ---------------------------------------------------------------

  defp branch_document do
    root =
      Block.new("core.branch",
        id: "blk_BR",
        config: %{"arms" => [%{"slot" => "arm_a", "cond" => "amount > 100"}]},
        slots: %{
          "arm_a" => [container("blk_A")],
          "otherwise" => [container("blk_B")]
        }
      )

    Document.new(root, id: "bdoc_T")
  end

  defp branch_table_spec do
    %{
      name: "arms",
      columns: [
        %{key: "arm_a", source: "amount > 100"},
        %{key: "otherwise", source: nil}
      ]
    }
  end

  defp branch_table(rows) do
    {:ok, table} = TruthTable.build(branch_table_spec(), rows)
    table
  end

  defp row(name, amount, expected_column) do
    %{name: name, bindings: %{"amount" => amount}, expected: %{expected_column => true}}
  end

  defp passthrough_table do
    {:ok, table} = TruthTable.build(%{name: "t", columns: []}, [])
    table
  end

  # A row hand-built outside `TruthTable.build/2` (which only ever produces
  # a string-keyed `context` via `Predicates.context/1`): its `context`
  # carries a non-string top-level key, which is exactly what
  # `Statifier.MachineState.checked_datamodel!/1` raises `ArgumentError` on.
  defp hand_built_table_with_bad_context do
    %TruthTable{
      name: "bad context",
      columns: [],
      paths: [],
      rows: [
        %TruthTable.Row{
          name: "bad_context",
          bindings: %{},
          context: %{bad_key: 1},
          error: nil,
          cells: [
            %TruthTable.Cell{
              column_key: "arm_a",
              outcome: {:ok, true},
              selected?: true,
              expected: true,
              status: :match
            }
          ]
        }
      ]
    }
  end

  defp sequence(children),
    do: Block.new("core.sequence", id: "blk_SEQ", slots: %{"body" => children})

  defp container(id), do: Block.new("core.sequence", id: id)
end
