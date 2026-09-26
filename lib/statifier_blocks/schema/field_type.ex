defmodule StatifierBlocks.Schema.FieldType do
  @moduledoc false

  # The one mapping from a `config_schema/1` field type
  # (`t:StatifierBlocks.BlockType.field_type/0`) to the draft-07 fragment
  # describing the JSON a document stores for it.
  #
  # The shipped schema file's core definitions are hand-written (ADR-0015
  # decision 2), and the drift test holds each of their config properties
  # to this mapping; a schema generated for a palette reads the same
  # mapping, so the two can never describe one field type two ways.
  #
  # The fragment names JSON types only. It says nothing about `required?`,
  # `default` or any pattern: `validate_config/1` is the authority on a
  # field's value (ADR-0002 decision 7), and a stored "none" spelled `null`
  # is a type's own to admit or refuse.

  alias StatifierBlocks.BlockType

  @doc false
  @spec json_schema(BlockType.field_type() | term()) :: {:ok, map()} | :error
  def json_schema(type) when type in [:string, :expression, :duration],
    do: {:ok, %{"type" => "string"}}

  def json_schema({:path, opts}) when is_map(opts), do: {:ok, %{"type" => "string"}}
  def json_schema(:integer), do: {:ok, %{"type" => "integer"}}
  def json_schema(:boolean), do: {:ok, %{"type" => "boolean"}}

  def json_schema({:select, choices}) when is_list(choices) and choices != [] do
    if Enum.all?(choices, &match?({value, _label} when is_binary(value), &1)),
      do: {:ok, %{"enum" => Enum.map(choices, &elem(&1, 0))}},
      else: :error
  end

  def json_schema({:list, inner}) do
    case json_schema(inner) do
      {:ok, items} -> {:ok, %{"type" => "array", "items" => items}}
      :error -> :error
    end
  end

  # A declared type name as a string, or an inline shape as a list of
  # member objects; the JSON type alone tells the two arms apart.
  def json_schema({:type_expr, opts}) when is_map(opts),
    do: {:ok, %{"type" => ["string", "array"], "items" => %{"type" => "object"}}}

  def json_schema(_other), do: :error
end
