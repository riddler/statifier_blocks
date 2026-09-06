defmodule StatifierBlocks.Core.AssignLocation do
  @moduledoc false

  # The one refusal shape behind every authored `<assign location="...">`.
  #
  # Four fields name a location this package writes an `<assign>` to -
  # `core.invoke`'s and `StatifierBlocks.InvokeStep`'s `assign_to`,
  # `core.subchart`'s `assign_to`, and `core.map`'s `collect` - and each
  # spelled the same three-clause refusal itself: a blank value is the
  # author declining to store the answer and passes, a value the field's
  # rule accepts passes, and anything else is one finding anchored on the
  # field's own key (ADR-0005 decision 11). Four copies of three clauses is
  # three ways for one of them to drift, and ADR-0011 decision 13's
  # deferred list is what drift looks like when it has already happened.
  #
  # The shape is shared here; the rule and the wording are still passed in
  # by the field rather than fixed here, and all four now pass the same
  # one. `core.invoke`, `StatifierBlocks.InvokeStep`, `core.subchart` and
  # `core.map`'s `collect` all read
  # `StatifierBlocks.Core.Config.datamodel_path?/1` - the predicate
  # `core.assign` reads, for ADR-0011 decision 13's reason: the same
  # `<assign>` element writes the same datamodel, so one location rule.
  # `collect` was the last of the four to widen, and it widened as ADR-0009
  # decision 4's Amendment of 2026-09-06 rather than as this helper's
  # implication - which is what the rule being an argument, and not a
  # constant in here, is for.
  #
  # Both entry points exist because a field is checked twice: once by
  # `validate_config/1`, which accumulates findings, and once by `emit/2`,
  # which has to answer for a config `validate_config/1` would have
  # rejected. They read one rule so the two cannot disagree.

  alias StatifierBlocks.{Block, BlockType}

  @typedoc false
  @type rule :: (term() -> boolean())

  @doc false
  @spec check([BlockType.finding()], Block.config(), String.t(), rule(), String.t()) ::
          [BlockType.finding()]
  def check(findings, config, key, rule, message)
      when is_list(findings) and is_map(config) and is_binary(key) and is_function(rule, 1) and
             is_binary(message) do
    case location(Map.get(config, key), key, rule, message) do
      {:ok, _location} -> findings
      {:error, [finding]} -> [finding | findings]
    end
  end

  @doc false
  @spec location(term(), String.t(), rule(), String.t()) ::
          {:ok, String.t() | nil} | {:error, [BlockType.finding()]}
  def location(value, key, rule, message)

  def location(value, _key, _rule, _message) when value in [nil, ""], do: {:ok, nil}

  def location(value, key, rule, message) do
    if rule.(value), do: {:ok, value}, else: {:error, [{key, message}]}
  end
end
