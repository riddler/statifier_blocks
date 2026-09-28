defmodule StatifierBlocks.Schema.HostDefinition do
  @moduledoc false

  # The definition `StatifierBlocks.Schema.for_palette/1` generates for a
  # palette entry that is not a core entry: a host type, or a host module
  # mounted under a `core.` name.
  #
  # It is read from the entry's declared `config_schema/1` and `slots/1`,
  # each asked about the config `Palette.new_block/2` builds (the
  # `config_schema(%{})` defaults) and reached through `Palette.call/4`, so
  # a `{module, state}` entry is read the way every other caller reads it.
  #
  # Each declared field is typed through `StatifierBlocks.Schema.FieldType`,
  # the one field-type mapping, with `null` admitted beside the fragment,
  # its label as `title` and its default as `default`. `required?` is never
  # carried into `required`. A field whose `value_path` is all string keys
  # is named at that path; one with an integer segment is not named. A
  # declaration the mapping cannot read names the field with no type, and a
  # `{:type_expr, opts}` field carries no member constraint, so a definition
  # is never stricter than the package's own reading of the declaration.
  #
  # A callback that raises, throws or exits, or answers something that is
  # not a list of declarations, degrades to the generic definition: the
  # block is judged by the generic block shape alone, never a raise.

  alias StatifierBlocks.BlockType
  alias StatifierBlocks.Palette
  alias StatifierBlocks.Schema.FieldType

  @doc false
  @spec generate(Palette.type_ref(), String.t()) :: map()
  def generate(ref, type_name) do
    with {:ok, fields} <- read_fields(ref),
         {:ok, slots} <- read_slots(ref, default_config(fields)) do
      %{
        "description" =>
          "A #{type_name} block, typed from its declared config_schema/1 and slots/1. " <>
            "Applied together with #/definitions/block.",
        "properties" => %{
          "type" => %{"const" => type_name},
          "config" => %{"properties" => config_properties(fields)},
          "slots" => %{"properties" => slot_properties(slots)}
        }
      }
    else
      :error -> generic(type_name)
    end
  end

  @doc false
  @spec generic(String.t()) :: map()
  def generic(type_name) do
    %{
      "description" =>
        "A #{type_name} block whose declarations could not be read: " <>
          "judged by the generic block shape alone.",
      "properties" => %{"type" => %{"const" => type_name}}
    }
  end

  # --- reading the declarations ---------------------------------------------

  defp read_fields(ref) do
    case safe_call(ref, :config_schema, [%{}], []) do
      {:ok, fields} when is_list(fields) ->
        if Enum.all?(fields, &field?/1), do: {:ok, fields}, else: :error

      _other ->
        :error
    end
  end

  defp read_slots(ref, config) do
    case safe_call(ref, :slots, [config], []) do
      {:ok, slots} when is_list(slots) ->
        if Enum.all?(slots, &slot?/1), do: {:ok, slots}, else: :error

      _other ->
        :error
    end
  end

  defp field?(%{key: key, type: _type, label: label, default: _default})
       when is_binary(key) and is_binary(label),
       do: true

  defp field?(_other), do: false

  defp slot?({name, _arity, label}) when is_binary(name) and is_binary(label), do: true
  defp slot?(_other), do: false

  # `Palette.new_block/2`'s config: each declared field's default at its key.
  defp default_config(fields), do: Map.new(fields, &{&1.key, &1.default})

  # A bounded rescue on a reading path: a host callback that raises, throws
  # or exits costs its type the typed definition, never the whole schema.
  # The rescued value is never inspected.
  defp safe_call(ref, callback, args, default) do
    {:ok, Palette.call(ref, callback, args, default)}
  rescue
    _raised -> :error
  catch
    :throw, _thrown -> :error
    :exit, _reason -> :error
  end

  # --- config ------------------------------------------------------------------

  defp config_properties(fields) do
    Enum.reduce(fields, %{}, fn field, properties ->
      path = BlockType.value_path(field)

      if Enum.all?(path, &is_binary/1),
        do: put_at(properties, path, field_property(field)),
        else: properties
    end)
  end

  defp field_property(field) do
    base = %{"title" => field.label, "default" => field.default}

    case FieldType.json_schema(field.type) do
      {:ok, fragment} ->
        Map.put(base, "anyOf", [%{"type" => "null"}, loosen(field.type, fragment)])

      :error ->
        base
    end
  end

  # A `{:type_expr, opts}` value is judged by its JSON type alone; a
  # member's own shape is not the package's to type, so the mapping's
  # member constraint is dropped here, and inside a list's items.
  defp loosen({:type_expr, _opts}, fragment), do: Map.delete(fragment, "items")

  defp loosen({:list, inner}, %{"items" => items} = fragment),
    do: Map.put(fragment, "items", loosen(inner, items))

  defp loosen(_type, fragment), do: fragment

  # Names a field at its path as nested `properties`, giving the objects on
  # the way no type. A path named twice keeps the first declaration's
  # keywords and merges what lies beneath it.
  defp put_at(properties, [segment], property),
    do: Map.update(properties, segment, property, &Map.merge(property, &1))

  defp put_at(properties, [segment | rest], property) do
    Map.update(
      properties,
      segment,
      %{"properties" => put_at(%{}, rest, property)},
      fn existing ->
        Map.put(
          existing,
          "properties",
          put_at(Map.get(existing, "properties", %{}), rest, property)
        )
      end
    )
  end

  # --- slots -------------------------------------------------------------------

  defp slot_properties(slots) do
    Map.new(slots, fn {name, _arity, label} ->
      {name,
       %{"title" => label, "type" => "array", "items" => %{"$ref" => "#/definitions/block"}}}
    end)
  end
end
