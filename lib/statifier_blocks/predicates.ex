defmodule StatifierBlocks.Predicates do
  @moduledoc """
  The evaluation seam: a condition source string plus a binding context in,
  `{:ok, boolean()} | {:error, reason()}` out, through `predicator`.

  ## Why `Predicates`, not `Fixtures`

  ADR-0002 decision 9 (`docs/adr/0002-block-type-behaviour.md:250`) puts the
  fixture-bundle convention in statifier-ui (`StatifierUI.Fixtures.Bundle`)
  and says in as many words that this package does not invent a competing
  one. A module named `StatifierBlocks.Fixtures` would assert a contract this
  package does not own. `Predicates` names what this code actually is - the
  evaluation seam - and claims nothing about how a host packages a dataset.

  ## The error vocabulary

  `evaluate/2` classifies four predicator outcomes into a closed set of
  tagged tuples. Errors are events: nothing here is coerced to a default.

  | Predicator returns | `evaluate/2` returns | Why |
  |---|---|---|
  | `{:ok, true}` / `{:ok, false}` | `{:ok, boolean()}` | the only success |
  | `{:ok, :undefined}` | `{:error, {:undefined_result, source}}` | `:undefined` is predicator's absence sentinel, distinct from `nil` and from `false`. A cross-type comparison and an unbound operand (with `on_unbound: :undefined`) both produce it. Folding it to `false` would be the rescue-to-default the conventions forbid |
  | `{:ok, value}`, not a boolean | `{:error, {:non_boolean, value}}` | `"transaction.amount"` is valid predicator source that evaluates to `120`. A truthiness rule would be a second semantics this package invented on top of predicator's |
  | `{:error, %ParseError{}}` | `{:error, {:parse_error, e}}` | the source is not predicator source at all |
  | `{:error, %UndefinedVariableError{variable: v}}` | `{:error, {:undefined_variable, v, e}}` | the source is fine and the context is incomplete; the variable name is lifted out so a caller does not have to know predicator's struct |
  | any other predicator error struct | `{:error, {:evaluation_error, e}}` | a total fallback, so a predicator version that adds an error struct returns an event rather than raising a `FunctionClauseError` |

  Two further tags belong to the binding layer (`context/1`), not to
  `evaluate/2`:

  | Tag | Meaning |
  |---|---|
  | `{:binding, path, reason}` | a binding's source text did not produce a value; `reason` is one of the tags above |
  | `{:binding_conflict, path}` | two dotted paths cannot both be nested - `"transaction"` and `"transaction.amount"` bound together, or a duplicate |

  ## Durations are spelled one way here, and it is the same way as in config

  Block *config* stores the duration string the author typed (`"15m"`, see
  `StatifierBlocks.Core.Wait`), and a binding's source text here is
  predicator source rather than config - but the duration literal in that
  source is `15m` / `1h30m` too, out of the same lexer grammar. So a value
  a `:duration` field would accept is a value a binding reads the same
  way, and there is no second spelling either side has to be taught. What
  is *not* a duration in either place fails in the ordinary way: a bare
  token that names nothing parses as an identifier and fails with
  `{:undefined_variable, _, _}`.

  See `StatifierBlocks.Predicates.TruthTable` for the truth-table builder
  that composes `evaluate/2` and `context/1` over an ordered set of branch
  arms, with first-match-wins selection.

  ## Where this is not wired

  ADR-0005 decision 9 (`docs/adr/0005-liveview-editor.md:336`) ships
  `:expression` as a plain source input and hands rich expression editing,
  including inline evaluation against a dataset, to statifier-ui, with a
  host-supplied override component as the seam. ADR-0005 decision 15
  (`:567`) lists a per-palette-entry fixtures pane among the things the
  record explicitly does not decide, and the shipped editor
  (`lib/statifier_blocks/editor.ex`) has no fixtures pane and no assign or
  event a truth table would attach to. So this module is reached either
  directly by a host, or through statifier-ui's richer expression component -
  never through a LiveView file in this package.

  ## The `:evaluation_error` fallback is reachable, not dead code

  Probed live against predicator 9.0.1 (`mix run`, empty context):
  `"true + 1"` raises a `Predicator.Errors.TypeMismatchError` and `"1 / 0"`
  raises a `Predicator.Errors.EvaluationError`, both from ordinary binary
  source. The fallback clause is therefore proven reachable and is kept as a
  single catch-all clause after the `ParseError` and `UndefinedVariableError`
  clauses, tested against `"true + 1"`.
  """

  alias Predicator.Errors.{ParseError, UndefinedVariableError}

  @type reason ::
          {:undefined_result, String.t()}
          | {:non_boolean, term()}
          | {:parse_error, struct()}
          | {:undefined_variable, String.t(), struct()}
          | {:evaluation_error, struct()}
          | {:binding, String.t(), reason()}
          | {:binding_conflict, String.t()}

  @type context :: %{optional(String.t()) => term()}

  @doc """
  Evaluates `source` as a predicator condition against `context`, classifying
  the result per the error vocabulary above. `context` defaults to `%{}`.

  Argument order mirrors `Predicator.evaluate(input, context)`. The repo
  convention that puts a state/session first is about threading a
  `%Document{}` or a socket through a pipeline; a plain binding context is a
  value, not a session, so this stays aligned with the wrapped library's own
  order instead of diverging for its own sake.
  """
  @spec evaluate(String.t(), context()) :: {:ok, boolean()} | {:error, reason()}
  def evaluate(source, context \\ %{}) when is_binary(source) and is_map(context) do
    source
    |> Predicator.evaluate(context)
    |> classify(source)
  end

  @doc """
  Evaluates `source` as a predicator value expression against an empty
  context. Returns any `Predicator.Types.value()` except `:undefined`, which
  is an error - a binding source has to resolve to a real value.
  """
  @spec evaluate_value(String.t()) :: {:ok, term()} | {:error, reason()}
  def evaluate_value(source) when is_binary(source) do
    case Predicator.evaluate(source, %{}) do
      {:ok, :undefined} -> {:error, {:undefined_result, source}}
      {:ok, value} -> {:ok, value}
      {:error, %ParseError{} = e} -> {:error, {:parse_error, e}}
      {:error, %UndefinedVariableError{variable: v} = e} -> {:error, {:undefined_variable, v, e}}
      {:error, e} -> {:error, {:evaluation_error, e}}
    end
  end

  @doc """
  Folds a `%{dotted_path => source_text}` map into a nested string-keyed
  context map. Each source is evaluated through `evaluate_value/1`; a
  failure becomes `{:error, {:binding, path, reason}}`. Paths are processed
  in sorted order so the error reported for a map with several bad bindings
  is deterministic. A path that would nest under, or over, an already-bound
  non-map value is `{:error, {:binding_conflict, path}}`.
  """
  @spec context(%{optional(String.t()) => String.t()}) ::
          {:ok, context()} | {:error, reason()}
  def context(bindings) when is_map(bindings) do
    bindings
    |> Map.keys()
    |> Enum.sort()
    |> Enum.reduce_while({:ok, %{}}, fn path, {:ok, acc} ->
      case build_binding(acc, path, Map.fetch!(bindings, path)) do
        {:ok, acc} -> {:cont, {:ok, acc}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp build_binding(acc, path, source) do
    case evaluate_value(source) do
      {:ok, value} -> put_path(acc, String.split(path, "."), value, path)
      {:error, reason} -> {:error, {:binding, path, reason}}
    end
  end

  # No is_map/conflict check here: sorted processing always places a
  # structural prefix before its extensions (`"a"` sorts before `"a.b"`),
  # so any conflict is always caught first by the two-segment clause below,
  # via its `_non_map` branch. A check here could never fire.
  defp put_path(acc, [key], value, _path) do
    {:ok, Map.put(acc, key, value)}
  end

  defp put_path(acc, [key | rest], value, path) do
    case Map.get(acc, key, %{}) do
      nested when is_map(nested) ->
        case put_path(nested, rest, value, path) do
          {:ok, nested} -> {:ok, Map.put(acc, key, nested)}
          {:error, _reason} = error -> error
        end

      _non_map ->
        {:error, {:binding_conflict, path}}
    end
  end

  defp classify({:ok, true}, _source), do: {:ok, true}
  defp classify({:ok, false}, _source), do: {:ok, false}
  defp classify({:ok, :undefined}, source), do: {:error, {:undefined_result, source}}
  defp classify({:ok, value}, _source), do: {:error, {:non_boolean, value}}
  defp classify({:error, %ParseError{} = e}, _source), do: {:error, {:parse_error, e}}

  defp classify({:error, %UndefinedVariableError{variable: v} = e}, _source),
    do: {:error, {:undefined_variable, v, e}}

  defp classify({:error, e}, _source), do: {:error, {:evaluation_error, e}}
end
