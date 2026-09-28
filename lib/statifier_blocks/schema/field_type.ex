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
  # `default` or any pattern: `validate_config/1` is the authority on
  # everything past a field's type, and a stored "none" spelled `null` is a
  # type's own to admit or refuse.
  #
  # A field's declared type is binding (ADR-0002 decision 7, amended
  # 2026-09-28), and the package judges it through this mapping:
  # `binding_schema/1` is the fragment a value is held to and `admits?/2`
  # reads it. `StatifierBlocks.BlockType`'s binding check and a generated
  # host definition both take `binding_schema/1`, so what the package
  # refuses and what a per-palette schema refuses are one reading.

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

  # The fragment a stored value is held to: `json_schema/1`'s, with a
  # `{:type_expr, opts}` value judged by its JSON type alone, at the top and
  # inside a list's items. A member's own shape is not the package's to type
  # (the amendment's T4), so the mapping's member constraint is dropped.
  @doc false
  @spec binding_schema(BlockType.field_type() | term()) :: {:ok, map()} | :error
  def binding_schema(type) do
    case json_schema(type) do
      {:ok, fragment} -> {:ok, loosen(type, fragment)}
      :error -> :error
    end
  end

  defp loosen({:type_expr, _opts}, fragment), do: Map.delete(fragment, "items")

  defp loosen({:list, inner}, %{"items" => items} = fragment),
    do: Map.put(fragment, "items", loosen(inner, items))

  defp loosen(_type, fragment), do: fragment

  # Whether `value` satisfies a fragment this module answers. Only the three
  # keywords the mapping writes are read - `type`, `enum` and `items` - each
  # as draft-07 reads it, so a value this admits is a value the fragment
  # admits under a JSON Schema validator.
  @doc false
  @spec admits?(map(), term()) :: boolean()
  def admits?(fragment, value) do
    type_admits?(Map.get(fragment, "type"), value) and
      enum_admits?(Map.get(fragment, "enum"), value) and
      items_admit?(Map.get(fragment, "items"), value)
  end

  defp type_admits?(nil, _value), do: true

  defp type_admits?(types, value) when is_list(types),
    do: Enum.any?(types, &json_type?(&1, value))

  defp type_admits?(type, value), do: json_type?(type, value)

  defp json_type?("string", value), do: is_binary(value)
  defp json_type?("integer", value), do: is_integer(value)
  defp json_type?("boolean", value), do: is_boolean(value)
  defp json_type?("array", value), do: is_list(value)
  defp json_type?("object", value), do: is_map(value)
  defp json_type?("null", value), do: is_nil(value)
  defp json_type?(_other, _value), do: false

  defp enum_admits?(nil, _value), do: true
  defp enum_admits?(values, value), do: value in values

  defp items_admit?(items, values) when is_map(items) and is_list(values),
    do: Enum.all?(values, &admits?(items, &1))

  defp items_admit?(_items, _value), do: true
end
