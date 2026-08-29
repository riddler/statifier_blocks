defmodule StatifierBlocks.Predicates.TruthTableTest do
  use ExUnit.Case, async: true

  alias StatifierBlocks.Predicates.TruthTable
  alias StatifierBlocks.Predicates.TruthTable.{Cell, Row}

  @authorization_spec %{
    name: "Authorization branch",
    columns: [
      %{key: "arm_declined", label: "Declined", source: "transaction.amount > 500"},
      %{key: "arm_approved", label: "Approved", source: "customer.verified"},
      %{key: "otherwise", label: "Otherwise", source: nil}
    ]
  }

  describe "build/2 - a well-formed table" do
    # sabotage: in `select_one/2`, changed `otherwise_column?(column, outcome)
    # or outcome == {:ok, true}` to `outcome == {:ok, true}` only, so the
    # otherwise column never self-selects - the "no arm matched" row's
    # statuses went red (arm_declined false/false/expected true became
    # mismatch instead of match), reverted.
    test "four rows over two arms and otherwise all match their expectations" do
      rows = [
        %{
          name: "Small, verified",
          bindings: %{"transaction.amount" => "120", "customer.verified" => "true"},
          expected: %{"arm_declined" => false, "arm_approved" => true, "otherwise" => false}
        },
        %{
          name: "Large, verified",
          bindings: %{"transaction.amount" => "900", "customer.verified" => "true"},
          expected: %{"arm_declined" => true, "arm_approved" => false, "otherwise" => false}
        },
        %{
          name: "Small, unverified",
          bindings: %{"transaction.amount" => "120", "customer.verified" => "false"},
          expected: %{"arm_declined" => false, "arm_approved" => false, "otherwise" => true}
        },
        %{
          name: "Large, unverified",
          bindings: %{"transaction.amount" => "900", "customer.verified" => "false"},
          expected: %{"arm_declined" => true, "arm_approved" => false, "otherwise" => false}
        }
      ]

      assert {:ok, table} = TruthTable.build(@authorization_spec, rows)
      assert table |> TruthTable.statuses() |> Enum.uniq() == [:match]
    end

    # sabotage: in `select_one/2`, changed the `already_selected? ->` clause
    # to fall through and re-evaluate `outcome == {:ok, true}` (removed the
    # early "already selected" short-circuit), so a second true arm was
    # selected too - this test's `selected?: false` assertion on the second
    # arm went red (got `true`), reverted.
    test "first-match-wins: two arms raw-evaluate true, only the first is selected" do
      # customer.verified is true (arm_approved raw-true) AND the amount is
      # also over the declined threshold (arm_declined raw-true, and listed
      # first) - the declined arm must win.
      spec = %{
        name: "Authorization branch",
        columns: [
          %{key: "arm_declined", label: "Declined", source: "transaction.amount > 500"},
          %{key: "arm_approved", label: "Approved", source: "customer.verified"},
          %{key: "otherwise", label: "Otherwise", source: nil}
        ]
      }

      rows = [
        %{
          name: "Large but verified",
          bindings: %{"transaction.amount" => "900", "customer.verified" => "true"}
        }
      ]

      assert {:ok, table} = TruthTable.build(spec, rows)
      assert [%Row{cells: [declined_cell, approved_cell, _otherwise_cell]}] = table.rows

      assert %Cell{column_key: "arm_declined", outcome: {:ok, true}, selected?: true} =
               declined_cell

      assert %Cell{column_key: "arm_approved", outcome: {:ok, true}, selected?: false} =
               approved_cell
    end

    # sabotage: in `otherwise_column?/2`, changed the `%Column{source: nil},
    # nil -> true` clause to `false`, so the otherwise column never
    # self-selects on its own recognition - this test's `selected?: true`
    # assertion went red (got `false`), reverted.
    test "an otherwise row: no arm matches, otherwise is selected" do
      rows = [
        %{
          name: "Large, unverified",
          bindings: %{"transaction.amount" => "20", "customer.verified" => "false"}
        }
      ]

      assert {:ok, table} = TruthTable.build(@authorization_spec, rows)
      assert [%Row{cells: [_declined_cell, _approved_cell, otherwise_cell]}] = table.rows
      assert %Cell{column_key: "otherwise", outcome: nil, selected?: true} = otherwise_cell
    end

    # sabotage: in `status_for/3`, swapped the `:match`/`:mismatch` clause
    # bodies (matched selected? == expected returned :mismatch and the
    # differing clause returned :match) - this test's :mismatch assertion
    # went red (got :match), reverted.
    test "a declared expectation the evaluation contradicts is a mismatch" do
      rows = [
        %{
          name: "Small, verified but expected declined",
          bindings: %{"transaction.amount" => "120", "customer.verified" => "true"},
          expected: %{"arm_declined" => true}
        }
      ]

      assert {:ok, table} = TruthTable.build(@authorization_spec, rows)
      assert [%Row{cells: [declined_cell | _rest]}] = table.rows
      assert %Cell{column_key: "arm_declined", status: :mismatch} = declined_cell
    end

    # sabotage: in `status_for/3`, changed the `is_boolean(selected?) and
    # expected == nil` clause to `is_boolean(selected?)` (dropped the nil
    # check, catching everything before the :match/:mismatch clauses) - this
    # test's :unchecked assertion still passed by coincidence for the
    # unchecked column, but the "four rows... all match" test above went red
    # (every status became :unchecked instead of :match), reverted.
    test "a column with no declared expectation is unchecked" do
      rows = [
        %{
          name: "Small, verified, no expectation on approved",
          bindings: %{"transaction.amount" => "120", "customer.verified" => "true"},
          expected: %{"arm_declined" => false}
        }
      ]

      assert {:ok, table} = TruthTable.build(@authorization_spec, rows)
      assert [%Row{cells: [_declined_cell, approved_cell, _otherwise_cell]}] = table.rows
      assert %Cell{column_key: "arm_approved", status: :unchecked, expected: nil} = approved_cell
    end

    # sabotage: in `status_for/3`, changed the leading
    # `status_for({:error, _reason}, _selected?, _expected), do: :error`
    # clause's return to `:unchecked` - this test's :error assertion went
    # red (got :unchecked), reverted.
    test "a column whose source fails to parse is an error cell" do
      spec = %{
        name: "Broken column",
        columns: [
          %{key: "arm_broken", label: "Broken", source: "amount >"}
        ]
      }

      rows = [
        %{name: "Any row", bindings: %{}}
      ]

      assert {:ok, table} = TruthTable.build(spec, rows)
      assert [%Row{cells: [broken_cell]}] = table.rows

      assert %Cell{
               column_key: "arm_broken",
               outcome: {:error, {:parse_error, %Predicator.Errors.ParseError{}}},
               status: :error
             } = broken_cell
    end

    # sabotage: in `select_one/2`, changed the `match?({:error, _reason},
    # outcome) -> {..., true}` clause's undecidable-flag element from `true`
    # to `undecidable?` (never turns undecidable on), so the later column
    # stayed `selected?: false` and `status: :mismatch`/`:unchecked` instead
    # of `:undecidable` - this test went red, reverted.
    test "a later column after an erroring one is undecidable" do
      spec = %{
        name: "Broken then otherwise",
        columns: [
          %{key: "arm_broken", label: "Broken", source: "amount >"},
          %{key: "otherwise", label: "Otherwise", source: nil}
        ]
      }

      rows = [
        %{name: "Any row", bindings: %{}}
      ]

      assert {:ok, table} = TruthTable.build(spec, rows)
      assert [%Row{cells: [_broken_cell, otherwise_cell]}] = table.rows

      assert %Cell{column_key: "otherwise", selected?: :undecidable, status: :undecidable} =
               otherwise_cell
    end

    # sabotage: in `build_row/2`, changed the `{:error, reason} -> %Row{...,
    # error: reason, cells: []}` clause to build cells anyway (dropped the
    # error branch, treating the failed context as `%{}`) - this test's
    # `error: {:binding, _, _}, cells: []` assertion went red, reverted.
    test "a row whose bindings fail to build a context carries a row-level error" do
      rows = [
        %{
          name: "Undefined variable in a binding",
          bindings: %{"transaction.amount" => "missing_thing"}
        }
      ]

      assert {:ok, table} = TruthTable.build(@authorization_spec, rows)
      assert [%Row{error: {:binding, "transaction.amount", _reason}, cells: []}] = table.rows
    end

    # sabotage: in `put_path/4`'s two-segment clause, changed the guard from
    # `when is_map(nested)` to `when true`, so a non-map value at an
    # intermediate key is treated as nestable instead of a conflict - this
    # test raised `BadMapError` instead of returning the row's
    # `binding_conflict` error, reverted.
    test "a row with a binding conflict carries a binding_conflict row error" do
      rows = [
        %{
          name: "Conflicting bindings",
          bindings: %{"transaction" => "120", "transaction.amount" => "5"}
        }
      ]

      assert {:ok, table} = TruthTable.build(@authorization_spec, rows)
      assert [%Row{error: {:binding_conflict, "transaction.amount"}, cells: []}] = table.rows
    end

    # sabotage: in `build_row/2`'s success clause, changed `note: note` to
    # `note: nil`, dropping the row spec's note on the way into the struct -
    # this test's `note: "the happy path"` assertion went red (got `nil`),
    # reverted.
    test "a row's note survives onto the Row struct" do
      rows = [
        %{
          name: "Small, verified",
          bindings: %{"transaction.amount" => "120", "customer.verified" => "true"},
          note: "the happy path"
        }
      ]

      assert {:ok, table} = TruthTable.build(@authorization_spec, rows)
      assert [%Row{note: "the happy path"}] = table.rows
    end
  end

  describe "build/2 - spec validation" do
    # sabotage: in `validate_unique/1`, changed the `MapSet.member?(seen,
    # key)` guard to `not MapSet.member?(seen, key)`, inverting the
    # duplicate check - this test went red (got {:ok, %TruthTable{}}
    # instead of the error), reverted.
    test "rejects a spec with a duplicate column key" do
      spec = %{
        name: "Duplicate columns",
        columns: [
          %{key: "arm_a", label: "A", source: "true"},
          %{key: "arm_a", label: "A again", source: "false"}
        ]
      }

      assert TruthTable.build(spec, []) == {:error, {:duplicate_column, "arm_a"}}
    end

    # sabotage: in `validate_otherwise_last/1`, changed `index != last_index`
    # to `index == last_index`, inverting which position is treated as
    # misplaced - this test went red (got {:ok, %TruthTable{}} instead of
    # the error), reverted.
    test "rejects an otherwise column that is not last" do
      spec = %{
        name: "Misplaced otherwise",
        columns: [
          %{key: "otherwise", label: "Otherwise", source: nil},
          %{key: "arm_a", label: "A", source: "true"}
        ]
      }

      assert TruthTable.build(spec, []) == {:error, {:otherwise_not_last, "otherwise"}}
    end

    # sabotage: in `validate_sources/1`, changed `is_binary(source) or
    # is_nil(source)` to `is_binary(source) or not is_nil(source)` (accepts
    # anything non-nil, including a non-binary), so the invalid-source test
    # went red (got {:ok, %TruthTable{}} instead of the error), reverted.
    test "rejects a spec whose column source is neither a binary nor nil" do
      spec = %{
        name: "Bad source type",
        columns: [
          %{key: "arm_a", label: "A", source: 123}
        ]
      }

      assert TruthTable.build(spec, []) == {:error, {:invalid_source, "arm_a"}}
    end
  end

  describe "build/2 - paths" do
    # sabotage: in `paths/2`'s nil-spec branch, dropped the trailing
    # `|> Enum.sort()`, leaving derived paths in flat-map/row order - this
    # test's sorted-order assertion went red (got
    # ["transaction.amount", "customer.verified"]), reverted.
    test "derives paths as the sorted union of the rows' binding keys when the spec omits them" do
      rows = [
        %{name: "Row 1", bindings: %{"transaction.amount" => "120"}},
        %{name: "Row 2", bindings: %{"customer.verified" => "true"}}
      ]

      assert {:ok, table} = TruthTable.build(@authorization_spec, rows)
      assert table.paths == ["customer.verified", "transaction.amount"]
    end

    # sabotage: in `paths/2`'s declared-paths branch, changed `paths -> paths`
    # to `paths -> Enum.sort(paths)`, sorting the spec's declared order
    # instead of passing it through unaltered - this test's assertion on the
    # given (unsorted) order went red, reverted.
    test "uses the spec's declared paths when given" do
      spec = Map.put(@authorization_spec, :paths, ["transaction.amount", "customer.verified"])

      assert {:ok, table} = TruthTable.build(spec, [])
      assert table.paths == ["transaction.amount", "customer.verified"]
    end
  end

  describe "statuses/1" do
    # sabotage: in `statuses/1`, appended `|> Enum.reverse()` to the
    # flat-mapped list, flipping the whole result end to end (a within-row
    # reversal alone did not catch it, since both fixture rows' statuses are
    # uniform within the row) - this test's row-then-column order assertion
    # went red, reverted.
    test "flattens every cell's status in row-then-column order" do
      rows = [
        %{
          name: "Small, verified",
          bindings: %{"transaction.amount" => "120", "customer.verified" => "true"},
          expected: %{"arm_declined" => false, "arm_approved" => true, "otherwise" => false}
        },
        %{
          name: "No expectations",
          bindings: %{"transaction.amount" => "120", "customer.verified" => "false"}
        }
      ]

      assert {:ok, table} = TruthTable.build(@authorization_spec, rows)

      assert TruthTable.statuses(table) == [
               :match,
               :match,
               :match,
               :unchecked,
               :unchecked,
               :unchecked
             ]
    end
  end
end
