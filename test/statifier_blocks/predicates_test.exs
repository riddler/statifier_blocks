defmodule StatifierBlocks.PredicatesTest do
  use ExUnit.Case, async: true

  alias StatifierBlocks.Predicates

  describe "evaluate/2" do
    # sabotage: changed `defp classify({:ok, true}, _source), do: {:ok, true}`
    # to `do: {:ok, false}` - test went red, reverted.
    test "returns {:ok, true} for a true condition" do
      assert Predicates.evaluate("customer.verified", %{"customer" => %{"verified" => true}}) ==
               {:ok, true}
    end

    # sabotage: changed `defp classify({:ok, false}, _source), do: {:ok, false}`
    # to `do: {:ok, true}` - test went red, reverted.
    test "returns {:ok, false} for a false condition" do
      assert Predicates.evaluate("transaction.amount > 500", %{
               "transaction" => %{"amount" => 120}
             }) == {:ok, false}
    end

    # sabotage: changed the `{:ok, :undefined}` classify clause to return
    # `{:ok, false}` instead of the error tuple - test went red, reverted.
    test "returns {:error, {:undefined_result, source}} for a cross-type comparison" do
      source = "transaction.amount > 'usd'"

      assert Predicates.evaluate(source, %{"transaction" => %{"amount" => 120}}) ==
               {:error, {:undefined_result, source}}
    end

    # sabotage: changed `defp classify({:ok, value}, _source), do: {:error, {:non_boolean, value}}`
    # to `do: {:ok, true}` - test went red, reverted.
    test "returns {:error, {:non_boolean, value}} for a non-boolean result" do
      assert Predicates.evaluate("transaction.amount", %{"transaction" => %{"amount" => 120}}) ==
               {:error, {:non_boolean, 120}}
    end

    # sabotage: changed the ParseError classify clause's tag from :parse_error
    # to :evaluation_error - test went red, reverted.
    test "returns {:error, {:parse_error, e}} for unparseable source" do
      assert {:error, {:parse_error, %Predicator.Errors.ParseError{}}} =
               Predicates.evaluate("amount >", %{})
    end

    # sabotage: changed the UndefinedVariableError classify clause to drop the
    # lifted variable name, matching `{:error, %UndefinedVariableError{} = e}`
    # and returning `{:error, {:undefined_variable, nil, e}}` - test went red
    # (asserted variable name "missing"), reverted.
    test "returns {:error, {:undefined_variable, v, e}} for a missing binding" do
      assert {:error,
              {:undefined_variable, "missing", %Predicator.Errors.UndefinedVariableError{}}} =
               Predicates.evaluate("missing.thing > 1", %{})
    end

    # sabotage: deleted the fallback `defp classify({:error, e}, _source), do:
    # {:error, {:evaluation_error, e}}` clause entirely, causing a
    # FunctionClauseError instead - test went red (raised), reverted.
    #
    # Reachability: probed predicator 9.0.1 live (`mix run`, empty context).
    # "true + 1" yields %Predicator.Errors.TypeMismatchError{} and "1 / 0"
    # yields %Predicator.Errors.EvaluationError{}, both from ordinary binary
    # source - so this clause is proven reachable, not dead code, and no
    # coverage pragma is needed.
    test "returns {:error, {:evaluation_error, e}} for any other predicator error" do
      assert {:error, {:evaluation_error, %Predicator.Errors.TypeMismatchError{}}} =
               Predicates.evaluate("true + 1", %{})
    end

    # sabotage: changed the default `context \\ %{}` to a non-empty default
    # binding a fake `transaction.amount` - test went red (matched {:ok,
    # true} instead of the undefined-variable error), reverted.
    test "defaults context to an empty map" do
      assert {:error, {:undefined_variable, "transaction", _e}} =
               Predicates.evaluate("transaction.amount > 500")
    end
  end

  describe "evaluate_value/1" do
    # sabotage: changed the passthrough clause
    # `{:ok, value} -> {:ok, value}` to `{:ok, _value} -> {:ok, :sabotaged}`
    # - this test and the four below went red together, reverted.
    test "evaluates an integer literal" do
      assert Predicates.evaluate_value("120") == {:ok, 120}
    end

    # sabotage: the same passthrough-clause mutation noted above - red, reverted.
    test "evaluates a string literal" do
      assert Predicates.evaluate_value("'clear'") == {:ok, "clear"}
    end

    # sabotage: the same passthrough-clause mutation noted above - red, reverted.
    test "evaluates a boolean literal" do
      assert Predicates.evaluate_value("true") == {:ok, true}
    end

    # Duration literals are `15m`, not the ISO-8601 `PT15M` block config uses
    # (see the moduledoc caution).
    # sabotage: the same passthrough-clause mutation noted above - red, reverted.
    test "evaluates a duration literal" do
      assert {:ok, %{minutes: 15}} = Predicates.evaluate_value("15m")
    end

    # sabotage: the same passthrough-clause mutation noted above - red, reverted.
    test "evaluates a date literal" do
      assert Predicates.evaluate_value("#2026-08-28#") == {:ok, ~D[2026-08-28]}
    end

    # sabotage: changed `{:ok, :undefined} -> {:error, {:undefined_result, source}}`
    # to `{:ok, :undefined} -> {:ok, :undefined}` - test went red, reverted.
    test "returns an error rather than :undefined for a cross-type comparison" do
      source = "1 > 'usd'"

      assert Predicates.evaluate_value(source) ==
               {:error, {:undefined_result, source}}
    end

    # sabotage: changed evaluate_value's ParseError clause tag from
    # :parse_error to :evaluation_error - test went red, reverted.
    test "returns a parse error for unparseable source" do
      assert {:error, {:parse_error, %Predicator.Errors.ParseError{}}} =
               Predicates.evaluate_value("amount >")
    end
  end

  describe "context/1" do
    # sabotage: swapped `String.split(path, ".")` for a hard-coded `[path]`
    # so no path ever nests - the nesting assertion went red, reverted.
    test "nests two dotted paths into a string-keyed map" do
      assert Predicates.context(%{
               "transaction.amount" => "120",
               "customer.verified" => "true"
             }) ==
               {:ok,
                %{
                  "transaction" => %{"amount" => 120},
                  "customer" => %{"verified" => true}
                }}
    end

    # sabotage: covered by the same passthrough-clause mutation noted at the
    # top of the evaluate_value/1 tests above (this test went red alongside
    # the literal tests), reverted.
    test "supports a bare top-level path" do
      assert Predicates.context(%{"flag" => "true"}) == {:ok, %{"flag" => true}}
    end

    # sabotage: changed `{:error, reason} -> {:error, {:binding, path, reason}}`
    # in `build_binding/3` to `{:error, reason} -> {:error, reason}`, dropping
    # the path - the pattern match on the wrapped tuple went red, reverted.
    test "returns {:error, {:binding, path, reason}} when a binding source fails" do
      assert {:error,
              {:binding, "transaction.amount", {:parse_error, %Predicator.Errors.ParseError{}}}} =
               Predicates.context(%{"transaction.amount" => "amount >"})
    end

    # sabotage: in `put_path/4`'s two-segment clause, changed the guard from
    # `when is_map(nested)` to `when true`, so a non-map value at the
    # intermediate key is treated as nestable instead of a conflict - test
    # went red (got {:ok, ...} instead of the error tuple), reverted.
    test "returns {:error, {:binding_conflict, path}} when two paths cannot both nest" do
      assert Predicates.context(%{"transaction" => "120", "transaction.amount" => "5"}) ==
               {:error, {:binding_conflict, "transaction.amount"}}
    end

    # sabotage: in `context/1`, changed `Enum.sort()` to `Enum.sort(:desc)`,
    # processing paths in reverse-sorted order - this test's assertion that
    # "customer.verified" (not "transaction.amount") fails first went red
    # (got the "transaction.amount" binding error instead), reverted.
    test "processes paths in sorted order for deterministic error reporting" do
      # Two bad bindings; sorted order means "customer.verified" (c < t) is
      # evaluated, and fails, before "transaction.amount" is ever reached.
      assert {:error, {:binding, "customer.verified", _reason}} =
               Predicates.context(%{
                 "transaction.amount" => "amount >",
                 "customer.verified" => "also >"
               })
    end
  end
end
