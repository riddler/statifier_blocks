defmodule StatifierBlocks.SchemaDriftTest.WaitWithJitter do
  @moduledoc false
  # core.wait as a package that grew a field the schema file lacks.
  alias StatifierBlocks.Core.Wait

  def config_schema(config) do
    Wait.config_schema(config) ++
      [%{key: "jitter", type: :duration, label: "Jitter", required?: false, default: ""}]
  end

  def slots(config), do: Wait.slots(config)
end

defmodule StatifierBlocks.SchemaDriftTest.WaitWithIntegerDuration do
  @moduledoc false
  # core.wait as a package that changed a field's type.
  alias StatifierBlocks.Core.Wait

  def config_schema(config) do
    Enum.map(Wait.config_schema(config), fn
      %{key: "duration"} = field -> %{field | type: :integer}
      field -> field
    end)
  end

  def slots(config), do: Wait.slots(config)
end

defmodule StatifierBlocks.SchemaDriftTest.SequenceWithFinally do
  @moduledoc false
  # core.sequence as a package that grew a slot the schema file lacks.
  alias StatifierBlocks.Core.Sequence

  def config_schema(config), do: Sequence.config_schema(config)
  def slots(config), do: Sequence.slots(config) ++ [{"finally", :any, "Finally"}]
end

defmodule StatifierBlocks.SchemaDriftTest do
  # ADR-0015 decisions 2 and 4: the shipped schema file's core definitions
  # are hand-written, and this test holds them to each core type's own
  # declarations, in both directions:
  #
  #   * the names under definitions/core equal Palette.core_types/0's keys
  #     (this test is the one that checks them);
  #   * every field config_schema/1 declares, for every config below, lands
  #     by its value_path on a property its type's definition describes,
  #     with the JSON type StatifierBlocks.Schema.FieldType maps the field
  #     type to, and, where the mapped fragment describes an array's items,
  #     with items that agree in turn (a property with no items does not);
  #   * a property left untyped, which decision 4 allows for a value
  #     validate_config/1 does not check, is compatible with any field only
  #     where @untyped_by_design names it; any other untyped property a
  #     field lands on, an array's items included, is drift;
  #   * every property a definition describes on a declared field's
  #     value_path is some declared field's, apart from the keys
  #     @validated_not_declared names: the config's own properties, and
  #     those of every object a longer value_path passes through (a branch
  #     arm's, under config/arms/*);
  #   * every key either pin names is one the file describes, and every key
  #     @untyped_by_design names the file leaves untyped;
  #   * every slot slots/1 declares is named by its type's definition, and
  #     every slot name the definition gives is declared by slots/1.
  #
  # A path in a finding or a pin writes an array's items as *, so
  # arms/*/slot is the slot key of any arm.
  #
  # The configs are every core block's in every block document fixture,
  # each core type's defaults as Palette.new_block/2 builds them, and
  # @sample_configs, which reach the config-parameterized fields and slots.
  use ExUnit.Case, async: true

  alias StatifierBlocks.{BlockType, Palette, Schema}
  alias StatifierBlocks.Core.{Branch, Parallel, Subchart}
  alias StatifierBlocks.Schema.FieldType

  alias StatifierBlocks.SchemaDriftTest.{
    SequenceWithFinally,
    WaitWithIntegerDuration,
    WaitWithJitter
  }

  @schema_file "priv/schemas/block-document.schema.json"

  @fixtures_dir "test/fixtures/documents"

  # Composite data declarations (keys type_name, version, params,
  # palette_entry, subtree), not block documents.
  @not_block_documents [
    "migrating_0_27_to_0_34/screen_before.json",
    "migrating_0_27_to_0_34/screen_after.json"
  ]

  # Config keys a type's validate_config/1 reads and checks that its
  # config_schema/1 does not declare as a form field. Each is described in
  # the file because the definition types config as validate_config/1
  # requires it (ADR-0015 decision 4), and each has no field to hold it to.
  # A branch arm's slot is its condition field's key and its slot's name,
  # never a field of its own.
  @validated_not_declared %{
    "core.branch" => ["arms/*/slot"],
    "core.on_event" => ["capture"]
  }

  # Declared fields the file leaves untyped by design: each holds a value
  # validate_config/1 does not check, and the file types a config key only
  # as validate_config/1 requires it (ADR-0015 decision 4). Any other
  # untyped property a field lands on is drift.
  @untyped_by_design %{
    "core.map" => ["collect_type"],
    "core.on_event" => ["payload"]
  }

  # Configs reaching the fields and slots that exist only for some config:
  # a branch's per-arm condition field and arm slot, a parallel's lane
  # slot, and a subchart's per-outcome slots.
  @sample_configs [
    {"core.branch", %{"arms" => [%{"slot" => "arm_approved", "cond" => "approved"}]}},
    {"core.parallel", %{"lanes" => ["capture", "receipt"], "complete" => "all"}},
    {"core.subchart", %{"chart" => "card_settlement", "outcomes" => "settled\ndeclined"}}
  ]

  # --- the drift check ----------------------------------------------------------

  defp root_map, do: JSON.decode!(Schema.json())

  defp block_documents do
    @fixtures_dir
    |> Path.join("**/*.json")
    |> Path.wildcard()
    |> Enum.reject(&(Path.relative_to(&1, @fixtures_dir) in @not_block_documents))
    |> Enum.sort()
  end

  defp block_maps(%{} = block) do
    children =
      block
      |> Map.get("slots", %{})
      |> Map.values()
      |> Enum.flat_map(fn list -> Enum.flat_map(list, &block_maps/1) end)

    [block | children]
  end

  # {type, config} pairs: fixture blocks, defaults, samples.
  defp configs do
    fixture_blocks =
      Enum.flat_map(block_documents(), fn path ->
        path |> File.read!() |> JSON.decode!() |> Map.fetch!("root") |> block_maps()
      end)

    from_fixtures = Enum.map(fixture_blocks, &{&1["type"], Map.get(&1, "config", %{})})

    defaults =
      Enum.map(Palette.core_types(), fn {type, _module} ->
        {:ok, block} = Palette.new_block(Palette.core(), type)
        {type, block.config}
      end)

    Enum.uniq(from_fixtures ++ defaults ++ @sample_configs)
  end

  # Every disagreement between the schema file and the package, as one
  # author-facing line each, naming the file and the type.
  defp drift(root, core_types, configs) do
    definitions = get_in(root, ["definitions", "core"]) || %{}

    missing =
      for type <- Enum.sort(Map.keys(core_types)), not Map.has_key?(definitions, type) do
        "#{@schema_file}: #{type} is a core type in Palette.core_types/0 " <>
          "and has no definition under definitions/core"
      end

    extra =
      for type <- Enum.sort(Map.keys(definitions)), not Map.has_key?(core_types, type) do
        "#{@schema_file}: definitions/core describes #{type}, " <>
          "which is not a core type in Palette.core_types/0"
      end

    per_type =
      for {type, module} <- Enum.sort(core_types),
          definition = Map.get(definitions, type),
          definition != nil,
          finding <- type_drift(root, type, module, definition, configs_for(configs, type)) do
        finding
      end

    missing ++ extra ++ Enum.uniq(per_type)
  end

  defp configs_for(configs, type), do: for({^type, config} <- configs, do: config)

  defp type_drift(root, type, module, definition, configs) do
    fields = Enum.flat_map(configs, &module.config_schema/1)
    slots = configs |> Enum.flat_map(&module.slots/1) |> Enum.map(&elem(&1, 0)) |> Enum.uniq()

    Enum.flat_map(fields, &field_drift(root, type, definition, &1)) ++
      undeclared_properties(root, type, definition, fields) ++
      stale_pins(root, type, definition) ++
      Enum.flat_map(slots, &slot_drift(root, type, definition, &1)) ++
      undeclared_slots(root, type, definition, slots)
  end

  defp field_drift(root, type, definition, %{key: key, type: field_type} = field) do
    path = BlockType.value_path(field)
    where = "config/" <> Enum.map_join(path, "/", &to_string/1)

    untyped_allowed? = pattern(path) in Map.get(@untyped_by_design, type, [])

    with {:mapping, {:ok, wanted}} <- {:mapping, FieldType.json_schema(field_type)},
         {:ok, property} <- locate(root, definition, path),
         :ok <- compatible(root, property, wanted, untyped_allowed?) do
      []
    else
      {:mapping, :error} ->
        [
          "#{@schema_file}: #{type} declares field #{key} as #{inspect(field_type)}, " <>
            "which the field-type mapping cannot read"
        ]

      :missing ->
        [
          "#{@schema_file}: #{type}'s definition describes no property at #{where} " <>
            "for the field #{key} config_schema/1 declares"
        ]

      {:incompatible, have, want} ->
        [
          "#{@schema_file}: #{type}'s definition types #{where} as #{have}, " <>
            "and config_schema/1 declares #{key} as #{inspect(field_type)}, which is #{want}"
        ]

      {:untyped, want} ->
        [
          "#{@schema_file}: #{type}'s definition leaves #{where} untyped, " <>
            "and config_schema/1 declares #{key} as #{inspect(field_type)}, which is #{want}; " <>
            "only a key @untyped_by_design names may be untyped"
        ]
    end
  end

  # Every property the definition describes on a declared field's
  # value_path: the config's own, and those of each object a longer
  # value_path passes through. Paths are compared as pattern/1 writes them.
  defp undeclared_properties(root, type, definition, fields) do
    paths = Enum.map(fields, &segments(BlockType.value_path(&1)))
    declared = paths |> Enum.flat_map(&prefixes/1) |> MapSet.new()
    allowed = Map.get(@validated_not_declared, type, [])
    containers = Enum.uniq([[] | Enum.flat_map(paths, &(&1 |> prefixes() |> Enum.drop(-1)))])

    for container <- Enum.sort(containers),
        {:ok, node} <- [walk(root, definition, container)],
        name <- node |> Map.get("properties", %{}) |> Map.keys() |> Enum.sort(),
        path = container ++ [name],
        path not in declared,
        Enum.join(path, "/") not in allowed do
      "#{@schema_file}: #{type}'s definition describes config/#{Enum.join(path, "/")}, " <>
        "which no field config_schema/1 declares"
    end
  end

  # A pin that names nothing the file describes, or an untyped pin the file
  # has since typed, would hide the next drift at that key.
  defp stale_pins(root, type, definition) do
    validated =
      for pin <- Map.get(@validated_not_declared, type, []),
          walk(root, definition, String.split(pin, "/")) == :missing do
        "#{@schema_file}: #{type}'s definition does not describe config/#{pin}, " <>
          "which @validated_not_declared names"
      end

    untyped =
      for pin <- Map.get(@untyped_by_design, type, []),
          finding <- untyped_pin(root, type, definition, pin) do
        finding
      end

    validated ++ untyped
  end

  defp untyped_pin(root, type, definition, pin) do
    case walk(root, definition, String.split(pin, "/")) do
      :missing ->
        [
          "#{@schema_file}: #{type}'s definition does not describe config/#{pin}, " <>
            "which @untyped_by_design names"
        ]

      {:ok, property} ->
        if untyped?(property),
          do: [],
          else: [
            "#{@schema_file}: #{type}'s definition types config/#{pin}, " <>
              "which @untyped_by_design names as untyped"
          ]
    end
  end

  # A value_path as a pin or a finding writes it: a list position is *.
  defp segments(path), do: Enum.map(path, &if(is_integer(&1), do: "*", else: &1))
  defp pattern(path), do: path |> segments() |> Enum.join("/")

  # Every prefix of a path, the path itself included and [] excluded.
  defp prefixes(path), do: for(n <- 1..length(path)//1, do: Enum.take(path, n))

  # The node a segments/1 path reaches, effective: * reads an array's items.
  defp walk(root, definition, path) do
    case locate(root, definition, Enum.map(path, &if(&1 == "*", do: 0, else: &1))) do
      {:ok, node} -> {:ok, effective(root, node)}
      :missing -> :missing
    end
  end

  defp slot_drift(root, type, definition, slot) do
    {names, patterns} = slot_names(root, definition)

    if slot in names or Enum.any?(patterns, &Regex.match?(&1, slot)),
      do: [],
      else: [
        "#{@schema_file}: #{type}'s definition does not name the slot #{slot} slots/1 declares"
      ]
  end

  defp undeclared_slots(root, type, definition, slots) do
    {names, patterns} = slot_names(root, definition)

    named =
      for name <- Enum.sort(names), name not in slots do
        "#{@schema_file}: #{type}'s definition names the slot #{name}, which slots/1 does not declare"
      end

    patterned =
      for pattern <- patterns, not Enum.any?(slots, &Regex.match?(pattern, &1)) do
        "#{@schema_file}: #{type}'s definition names slots matching #{Regex.source(pattern)}, " <>
          "and slots/1 declares none"
      end

    named ++ patterned
  end

  defp slot_names(root, definition) do
    slots = effective(root, get_in(definition, ["properties", "slots"]) || %{})
    names = slots |> Map.get("properties", %{}) |> Map.keys()

    patterns =
      slots |> Map.get("patternProperties", %{}) |> Map.keys() |> Enum.map(&Regex.compile!/1)

    {names, patterns}
  end

  # The property a value_path lands on: a string segment reads a property,
  # an integer segment an array's items.
  defp locate(root, definition, path) do
    start = get_in(definition, ["properties", "config"]) || %{}

    Enum.reduce_while(path, {:ok, start}, fn segment, {:ok, node} ->
      node = effective(root, node)

      next =
        if is_integer(segment),
          do: Map.get(node, "items"),
          else: get_in(node, ["properties", segment])

      if next == nil, do: {:halt, :missing}, else: {:cont, {:ok, next}}
    end)
  end

  # A schema with its $ref and allOf folded in: the keys this test reads.
  defp effective(root, %{"$ref" => "#/" <> pointer} = schema) do
    target = get_in(root, String.split(pointer, "/"))
    merge(effective(root, target), effective(root, Map.delete(schema, "$ref")))
  end

  defp effective(root, %{"allOf" => parts} = schema) do
    Enum.reduce(parts, effective(root, Map.delete(schema, "allOf")), fn part, acc ->
      merge(acc, effective(root, part))
    end)
  end

  defp effective(_root, schema), do: schema

  defp merge(left, right) do
    Map.merge(left, right, fn
      "type", a, b -> intersect(List.wrap(a), List.wrap(b))
      "properties", a, b -> Map.merge(a, b)
      _key, _a, b -> b
    end)
  end

  defp intersect(a, b), do: Enum.filter(a, &(&1 in b))

  # A property is compatible with a mapped fragment when it admits exactly
  # the fragment's JSON types, plus null at most (a type's stored "none"),
  # an enum holds the same values, and, where the fragment describes an
  # array's items, the property describes items that agree in turn. A
  # property with neither type nor enum is untyped: it admits any field
  # where untyped_allowed? says a pin names it, and is drift anywhere else,
  # an array's items included.
  defp compatible(root, property, wanted, untyped_allowed?) do
    property = effective(root, property)

    cond do
      not untyped?(property) -> compare(root, property, wanted)
      untyped_allowed? -> :ok
      true -> {:untyped, json_summary(root, wanted)}
    end
  end

  defp untyped?(schema), do: not Map.has_key?(schema, "type") and not Map.has_key?(schema, "enum")

  defp compare(root, property, wanted) do
    cond do
      json_types(property) -- ["null"] != json_types(wanted) ->
        {:incompatible, json_summary(root, property), json_summary(root, wanted)}

      Map.has_key?(wanted, "enum") or Map.has_key?(property, "enum") ->
        if enum_values(property) == enum_values(wanted),
          do: :ok,
          else: {:incompatible, json_summary(root, property), json_summary(root, wanted)}

      Map.has_key?(wanted, "items") ->
        items = Map.get(property, "items")

        if items != nil and compatible(root, items, wanted["items"], false) == :ok,
          do: :ok,
          else: {:incompatible, json_summary(root, property), json_summary(root, wanted)}

      true ->
        :ok
    end
  end

  defp json_types(%{"type" => type}), do: type |> List.wrap() |> Enum.sort()

  defp json_types(%{"enum" => values}),
    do: values |> Enum.map(&json_type/1) |> Enum.uniq() |> Enum.sort()

  defp json_types(_untyped), do: []

  defp enum_values(schema),
    do: schema |> Map.get("enum", []) |> Enum.reject(&is_nil/1) |> Enum.sort()

  defp json_type(value) when is_binary(value), do: "string"
  defp json_type(value) when is_integer(value), do: "integer"
  defp json_type(value) when is_boolean(value), do: "boolean"
  defp json_type(nil), do: "null"
  defp json_type(value) when is_list(value), do: "array"
  defp json_type(value) when is_map(value), do: "object"

  defp json_summary(_root, %{"enum" => values}),
    do: "an enum of " <> Enum.map_join(values, ", ", &inspect/1)

  defp json_summary(root, schema) do
    types = json_types(schema)

    cond do
      untyped?(schema) -> "untyped"
      "array" not in types -> Enum.join(types, " or ")
      Map.has_key?(schema, "items") -> summary_array(root, types, schema["items"])
      true -> Enum.join(types, " or ") <> " with no items described"
    end
  end

  defp summary_array(root, types, items),
    do: Enum.join(types, " or ") <> " of " <> json_summary(root, effective(root, items))

  defp drift_message(findings),
    do: Enum.join(["the schema file and the package disagree:" | findings], "\n  ")

  # --- the shipped file agrees with the package -----------------------------------

  # Sabotage: the "core.drafts" definition deleted from the file -> red, naming core.drafts.
  # Sabotage: core.wait's "duration" given "type": "integer" in the file -> red, naming core.wait.
  # Sabotage: core.parallel's "lanes" losing its "items" in the file -> red, naming core.parallel.
  # Sabotage: the core.branch entry of @validated_not_declared deleted -> red, naming core.branch.
  # Sabotage: the core.map entry of @untyped_by_design deleted -> red, naming core.map.
  test "the file's core definitions agree with each core type's fields and slots" do
    findings = drift(root_map(), Palette.core_types(), configs())

    assert findings == [], drift_message(findings)
  end

  # Sabotage: configs/0 answering only the defaults -> each of the three assertions goes red.
  test "the configs reach every config-parameterized field and slot" do
    configs = configs()

    assert Enum.any?(configs_for(configs, "core.branch"), &(Branch.config_schema(&1) != []))
    assert Enum.any?(configs_for(configs, "core.parallel"), &(Parallel.slots(&1) != []))

    assert Enum.any?(configs_for(configs, "core.subchart"), fn config ->
             Enum.any?(Subchart.slots(config), &(elem(&1, 0) not in ["on_done", "on_error"]))
           end)
  end

  # --- each direction's failure message -------------------------------------------

  # Sabotage: the missing-definition comprehension returning [] -> this case goes red.
  test "a core type with no definition names the file and the type" do
    root = update_in(root_map(), ["definitions", "core"], &Map.delete(&1, "core.drafts"))

    assert drift(root, Palette.core_types(), configs()) == [
             "#{@schema_file}: core.drafts is a core type in Palette.core_types/0 " <>
               "and has no definition under definitions/core"
           ]
  end

  # Sabotage: the extra-definition comprehension returning [] -> this case goes red.
  test "a definition for a type the palette does not carry names the file and the type" do
    core_types = Map.delete(Palette.core_types(), "core.placeholder")

    assert drift(root_map(), core_types, configs()) == [
             "#{@schema_file}: definitions/core describes core.placeholder, " <>
               "which is not a core type in Palette.core_types/0"
           ]
  end

  # Sabotage: locate/3 answering the config node for any path -> this case goes red.
  test "a field the package declares and the file lacks names the file and the type" do
    core_types = Map.put(Palette.core_types(), "core.wait", WaitWithJitter)

    assert drift(root_map(), core_types, configs()) == [
             "#{@schema_file}: core.wait's definition describes no property at config/jitter " <>
               "for the field jitter config_schema/1 declares"
           ]
  end

  # Sabotage: undeclared_properties/4 returning [] -> this case goes red.
  test "a property the file describes and no field declares names the file and the type" do
    root =
      put_in(
        root_map(),
        ["definitions", "core", "core.wait", "properties", "config", "properties", "jitter"],
        %{"type" => "string"}
      )

    assert drift(root, Palette.core_types(), configs()) == [
             "#{@schema_file}: core.wait's definition describes config/jitter, " <>
               "which no field config_schema/1 declares"
           ]
  end

  # Sabotage: compatible/4 answering :ok whenever the property has a type -> this case goes red.
  test "a field type the package changed names the file and the type" do
    core_types = Map.put(Palette.core_types(), "core.wait", WaitWithIntegerDuration)

    assert drift(root_map(), core_types, configs()) == [
             "#{@schema_file}: core.wait's definition types config/duration as string, " <>
               "and config_schema/1 declares duration as :integer, which is integer"
           ]
  end

  # Sabotage: compatible/4 answering :ok whenever the property has a type -> this case goes red.
  test "a field type the file changed names the file and the type" do
    root =
      put_in(
        root_map(),
        ["definitions", "core", "core.wait", "properties", "config", "properties", "duration"],
        %{"type" => "integer"}
      )

    assert drift(root, Palette.core_types(), configs()) == [
             "#{@schema_file}: core.wait's definition types config/duration as integer, " <>
               "and config_schema/1 declares duration as :duration, which is string"
           ]
  end

  # Sabotage: the enum comparison in compare/3 dropped -> this case goes red.
  test "a select choice the file lacks names the file and the type" do
    root =
      put_in(
        root_map(),
        [
          "definitions",
          "core",
          "core.parallel",
          "properties",
          "config",
          "properties",
          "complete"
        ],
        %{"enum" => ["all"]}
      )

    assert drift(root, Palette.core_types(), configs()) == [
             "#{@schema_file}: core.parallel's definition types config/complete as an enum of \"all\", " <>
               "and config_schema/1 declares complete as " <>
               inspect(
                 {:select,
                  [
                    {"all", "All - when every lane is done"},
                    {"first", "First - when any one lane is done"}
                  ]}
               ) <> ", which is an enum of \"all\", \"first\""
           ]
  end

  # Sabotage: slot_drift/4 returning [] -> this case goes red.
  test "a slot the package declares and the file does not name names the file and the type" do
    core_types = Map.put(Palette.core_types(), "core.sequence", SequenceWithFinally)

    assert drift(root_map(), core_types, configs()) == [
             "#{@schema_file}: core.sequence's definition does not name the slot finally slots/1 declares"
           ]
  end

  # Sabotage: undeclared_slots/4's named comprehension returning [] -> this case goes red.
  test "a slot the file names and the package does not declare names the file and the type" do
    root =
      put_in(
        root_map(),
        ["definitions", "core", "core.sequence", "properties", "slots", "properties", "finally"],
        %{"$ref" => "#/definitions/block_list"}
      )

    assert drift(root, Palette.core_types(), configs()) == [
             "#{@schema_file}: core.sequence's definition names the slot finally, " <>
               "which slots/1 does not declare"
           ]
  end

  # --- array items, untyped properties and nested properties ------------------------

  # Sabotage: compare/3's items clause answering :ok when the property has no items -> this case goes red.
  test "an array property the file leaves without items names the file and the type" do
    root =
      update_in(
        root_map(),
        ["definitions", "core", "core.parallel", "properties", "config", "properties", "lanes"],
        &Map.delete(&1, "items")
      )

    assert drift(root, Palette.core_types(), configs()) == [
             "#{@schema_file}: core.parallel's definition types config/lanes as array " <>
               "with no items described, and config_schema/1 declares lanes as " <>
               "{:list, :string}, which is array of string"
           ]
  end

  # Sabotage: compatible/4 passing true for an array's items -> this case goes red.
  test "an array property whose items the file leaves untyped names the file and the type" do
    root =
      put_in(
        root_map(),
        [
          "definitions",
          "core",
          "core.parallel",
          "properties",
          "config",
          "properties",
          "lanes",
          "items"
        ],
        %{"description" => "A lane name."}
      )

    assert drift(root, Palette.core_types(), configs()) == [
             "#{@schema_file}: core.parallel's definition types config/lanes as array of untyped, " <>
               "and config_schema/1 declares lanes as {:list, :string}, which is array of string"
           ]
  end

  # Sabotage: compatible/4's untyped clause answering :ok whatever the pin says -> this case goes red.
  test "an untyped property no pin names names the file and the type" do
    root =
      put_in(
        root_map(),
        ["definitions", "core", "core.wait", "properties", "config", "properties", "duration"],
        %{"description" => "A predicator duration."}
      )

    assert drift(root, Palette.core_types(), configs()) == [
             "#{@schema_file}: core.wait's definition leaves config/duration untyped, " <>
               "and config_schema/1 declares duration as :duration, which is string; " <>
               "only a key @untyped_by_design names may be untyped"
           ]
  end

  # Sabotage: untyped_pin/4's typed arm answering [] -> this case goes red.
  test "a pinned untyped property the file has typed names the file and the type" do
    root =
      put_in(
        root_map(),
        ["definitions", "core", "core.on_event", "properties", "config", "properties", "payload"],
        %{"type" => ["string", "array"], "items" => %{"type" => "object"}}
      )

    assert drift(root, Palette.core_types(), configs()) == [
             "#{@schema_file}: core.on_event's definition types config/payload, " <>
               "which @untyped_by_design names as untyped"
           ]
  end

  # Sabotage: stale_pins/3's validated comprehension returning [] -> this case goes red.
  test "a validated-not-declared pin the file does not describe names the file and the type" do
    root =
      update_in(
        root_map(),
        ["definitions", "core", "core.on_event", "properties", "config", "properties"],
        &Map.delete(&1, "capture")
      )

    assert drift(root, Palette.core_types(), configs()) == [
             "#{@schema_file}: core.on_event's definition does not describe config/capture, " <>
               "which @validated_not_declared names"
           ]
  end

  # Sabotage: undeclared_properties/4 checking only the config's own properties -> this case goes red.
  test "a property the file describes on a value_path and no field declares names the file and the type" do
    root =
      put_in(
        root_map(),
        [
          "definitions",
          "core",
          "core.branch",
          "properties",
          "config",
          "properties",
          "arms",
          "items",
          "properties",
          "weight"
        ],
        %{"type" => "integer"}
      )

    assert drift(root, Palette.core_types(), configs()) == [
             "#{@schema_file}: core.branch's definition describes config/arms/*/weight, " <>
               "which no field config_schema/1 declares"
           ]
  end

  # --- the field-type mapping ------------------------------------------------------

  @mapping [
    {:string, %{"type" => "string"}},
    {:expression, %{"type" => "string"}},
    {:duration, %{"type" => "string"}},
    {{:path, %{}}, %{"type" => "string"}},
    {{:path, %{writes: "cards.settlement"}}, %{"type" => "string"}},
    {:integer, %{"type" => "integer"}},
    {:boolean, %{"type" => "boolean"}},
    {{:select, [{"all", "All"}, {"first", "First"}]}, %{"enum" => ["all", "first"]}},
    {{:list, :string}, %{"type" => "array", "items" => %{"type" => "string"}}},
    {{:list, {:list, :integer}},
     %{"type" => "array", "items" => %{"type" => "array", "items" => %{"type" => "integer"}}}},
    {{:type_expr, %{}}, %{"type" => ["string", "array"], "items" => %{"type" => "object"}}}
  ]

  # Sabotage: json_schema(:integer) answering "number" -> this case goes red.
  test "each field type maps to its JSON type" do
    for {field_type, fragment} <- @mapping do
      assert FieldType.json_schema(field_type) == {:ok, fragment}, inspect(field_type)
    end
  end

  # Sabotage: json_schema/1's catch-all clause deleted -> the FunctionClauseError turns this red.
  test "a field type the mapping cannot read answers :error, never a raise" do
    for field_type <- [
          :float,
          {:select, []},
          {:select, [{:all, "All"}]},
          {:list, :float},
          "string"
        ] do
      assert FieldType.json_schema(field_type) == :error, inspect(field_type)
    end
  end
end
