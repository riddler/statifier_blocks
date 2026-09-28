defmodule StatifierBlocks.SchemaForPaletteTest do
  use ExUnit.Case, async: true

  alias StatifierBlocks.{Block, BlockType, Document, DocumentGenerator, Palette, Schema}

  @fixtures_dir "test/fixtures/documents"

  # Composite data declarations (keys type_name, version, params,
  # palette_entry, subtree), not block documents: the schema is not about
  # them, so the fixture sweep leaves these two out by name.
  @not_block_documents [
    "migrating_0_27_to_0_34/screen_before.json",
    "migrating_0_27_to_0_34/screen_after.json"
  ]

  # Fixed, never seeded from the clock, so a red invariant run names an
  # index `DocumentGenerator.generate/2` regenerates exactly.
  @seed 515_151
  @corpus_size 300

  # --- test-only host block types --------------------------------------------

  defmodule OverdueNotice do
    @moduledoc false
    # A library-loan host type: one field of each of the four kinds the
    # acceptance names, one named slot, and a validate_config/1 that
    # agrees with the declared field types.
    use StatifierBlocks.BlockType

    @impl true
    def slots(_config), do: [{"escalation", :any, "If the notice goes unanswered"}]

    @impl true
    def config_schema(_config) do
      [
        %{key: "subject", type: :string, label: "Subject", required?: true, default: "Overdue"},
        %{key: "days_late", type: :integer, label: "Days late", required?: false, default: 1},
        %{
          key: "channel",
          type: {:select, [{"email", "Email"}, {"letter", "Letter"}]},
          label: "Channel",
          required?: true,
          default: "email"
        },
        %{key: "copies", type: {:list, :string}, label: "Copies", required?: false, default: []}
      ]
    end

    @impl true
    def validate_config(config) do
      case Map.get(config, "subject") do
        subject when is_binary(subject) or is_nil(subject) -> :ok
        _other -> {:error, [{"subject", "must be text"}]}
      end
    end

    @impl true
    def emit(%Block{id: id}, _context), do: {:ok, {:emitted, id}}
  end

  defmodule ParcelRoute do
    @moduledoc false
    # Where a field lives: at a path of string keys, at a list position,
    # a type expression, and a declaration the field-type mapping cannot
    # read.
    use StatifierBlocks.BlockType

    @impl true
    def config_schema(_config) do
      [
        %{
          key: "depot",
          type: :string,
          label: "Depot",
          required?: false,
          default: "",
          value_path: ["route", "origin", "depot"]
        },
        %{
          key: "first_stop",
          type: :string,
          label: "First stop",
          required?: false,
          default: "",
          value_path: ["stops", 0, "name"]
        },
        %{
          key: "manifest",
          type: {:type_expr, %{}},
          label: "Manifest",
          required?: false,
          default: ""
        },
        %{key: "speed", type: {:select, []}, label: "Speed", required?: false, default: "slow"}
      ]
    end

    @impl true
    def emit(%Block{id: id}, _context), do: {:ok, {:emitted, id}}
  end

  defmodule RaisingSchema do
    @moduledoc false
    use StatifierBlocks.BlockType

    @impl true
    def config_schema(_config), do: raise("no declaration today")

    @impl true
    def emit(%Block{id: id}, _context), do: {:ok, {:emitted, id}}
  end

  defmodule NonListSchema do
    @moduledoc false
    use StatifierBlocks.BlockType

    @impl true
    def config_schema(_config), do: %{"subject" => :string}

    @impl true
    def emit(%Block{id: id}, _context), do: {:ok, {:emitted, id}}
  end

  defmodule StatefulDesk do
    @moduledoc false
    # A `{module, state}` entry: the state names the one field it declares.
    # Each callback takes the state first, so none is the behaviour's arity.

    def slots(_state, _config), do: []

    def config_schema(field, _config),
      do: [%{key: field, type: :integer, label: "Desk", required?: false, default: 1}]

    def validate_config(_state, _config), do: :ok

    def current_version(_state), do: 1

    def emit(_state, %Block{id: id}, _context), do: {:ok, {:emitted, id}}
  end

  defmodule LaxRenewal do
    @moduledoc false
    # A library-loan host type whose validate_config/1 accepts every config,
    # so what the package refuses of it is the binding check's alone: one
    # field per arm of the closed field-type set, a field at a path of
    # string keys, one at a list position, and a list of type expressions.
    use StatifierBlocks.BlockType

    @impl true
    def config_schema(_config) do
      [
        field("note", :string, ""),
        field("renew_when", :expression, "true"),
        field("grace", :duration, "P7D"),
        field("patron_path", {:path, %{}}, "patron.email"),
        field("renewals", :integer, 0),
        field("auto", :boolean, false),
        field("channel", {:select, [{"email", "Email"}, {"letter", "Letter"}]}, "email"),
        field("branches", {:list, :string}, []),
        field("record", {:type_expr, %{}}, ""),
        field("records", {:list, {:type_expr, %{}}}, []),
        Map.put(field("desk", :string, ""), :value_path, ["counter", "desk"]),
        Map.put(field("first_title", :string, ""), :value_path, ["items", 0, "title"])
      ]
    end

    defp field(key, type, default),
      do: %{key: key, type: type, label: key, required?: false, default: default}

    @impl true
    def emit(%Block{id: id}, _context), do: {:ok, {:emitted, id}}
  end

  # --- helpers -----------------------------------------------------------------

  defp resolve(schema), do: ExJsonSchema.Schema.resolve(schema)

  defp validate(resolved, data), do: ExJsonSchema.Validator.validate(resolved, data)

  defp host_palette do
    Palette.new(
      Map.merge(Palette.core_types(), %{
        "library.overdue_notice" => OverdueNotice,
        "parcel.route" => ParcelRoute
      })
    )
  end

  # The definition `for_palette/1` applies to blocks of `type`.
  defp definition(schema, type) do
    schema
    |> get_in(["definitions", "block", "allOf"])
    |> Enum.find_value(fn %{"if" => condition, "then" => definition} ->
      if get_in(condition, ["properties", "type", "const"]) == type, do: definition
    end)
  end

  defp block_documents do
    @fixtures_dir
    |> Path.join("**/*.json")
    |> Path.wildcard()
    |> Enum.reject(&(Path.relative_to(&1, @fixtures_dir) in @not_block_documents))
    |> Enum.sort()
  end

  defp document(root) do
    %{"schema_version" => 1, "id" => "bdoc_library_notices", "revision" => 0, "root" => root}
  end

  defp notice(config) do
    %{
      "id" => "notice",
      "type" => "library.overdue_notice",
      "type_version" => 1,
      "config" => config,
      "slots" => %{
        "escalation" => [
          %{
            "id" => "escalate",
            "type" => "core.send",
            "type_version" => 1,
            "config" => %{"event" => "loan.escalated"}
          }
        ]
      }
    }
  end

  defp notice_config do
    %{
      "subject" => "Your loan is late",
      "days_late" => 3,
      "channel" => "letter",
      "copies" => ["branch"]
    }
  end

  defp all_blocks(%Block{slots: slots} = block),
    do: [
      block
      | slots |> Map.values() |> Enum.flat_map(&Enum.flat_map(&1, fn b -> all_blocks(b) end))
    ]

  # --- the core palette -------------------------------------------------------

  # Sabotage: definition/2 answering Map.put(shipped, "required", ["config", "slots"])
  # -> a fixture's leaf block with no slots goes red.
  test "for_palette(Palette.core()) validates every block document fixture and its encoding" do
    documents = block_documents()
    assert length(documents) > 2
    schema = Palette.core() |> Schema.for_palette() |> resolve()

    for path <- documents do
      bytes = File.read!(path)
      assert {:ok, document} = Document.from_json(bytes), path
      assert validate(schema, JSON.decode!(bytes)) == :ok, path
      assert validate(schema, JSON.decode!(Document.to_json(document))) == :ok, path
    end
  end

  # Sabotage: definition/2 generating every entry, core ones included ->
  # the verbatim comparison goes red.
  test "every core entry takes its shipped definition verbatim" do
    shipped = Schema.json() |> JSON.decode!() |> get_in(["definitions", "core"])
    schema = Schema.for_palette(Palette.core())

    for name <- Map.keys(Palette.core_types()) do
      assert definition(schema, name) == Map.fetch!(shipped, name), name
    end
  end

  # Sabotage: definition/2 matching a core name alone, whatever its module ->
  # the mounted host module takes core.wait's shipped definition and goes red.
  test "a host module mounted under a core name gets a generated definition" do
    palette = Palette.new(%{"core.wait" => OverdueNotice})
    wait = definition(Schema.for_palette(palette), "core.wait")

    assert get_in(wait, ["properties", "config", "properties", "subject", "title"]) == "Subject"
    refute Map.has_key?(wait, "required")
  end

  # Sabotage: the generated clauses left out of definitions/block (the root
  # returned unchanged) -> the core.wait refusal below goes red.
  test "the core definitions are applied to every block, the root's children included" do
    wait = %{
      "id" => "blk_WAIT",
      "type" => "core.wait",
      "type_version" => 1,
      "config" => %{"duration" => 5}
    }

    root = %{
      "id" => "blk_ROOT",
      "type" => "core.sequence",
      "type_version" => 1,
      "slots" => %{"body" => [wait]}
    }

    assert {:ok, _document} = Document.from_json(JSON.encode!(document(root)))
    assert validate(resolve(JSON.decode!(Schema.json())), document(root)) == :ok

    assert {:error, [_ | _]} =
             validate(Palette.core() |> Schema.for_palette() |> resolve(), document(root))
  end

  # --- the invariant ----------------------------------------------------------

  # The package's config check, as the invariant names it: the declared
  # field types (the `{:type_expr, opts}` arm's check and the binding check
  # for every other arm), then the type's own `validate_config/1`.
  defp package_accepts?(ref, config) do
    BlockType.type_expr_findings(ref, config) == [] and
      BlockType.field_type_findings(ref, config) == [] and
      Palette.call(ref, :validate_config, [config], :ok) == :ok
  end

  defp accepted_by(palette, document) do
    document.root
    |> all_blocks()
    |> Enum.all?(fn block ->
      case Map.fetch(palette.types, block.type) do
        {:ok, ref} -> package_accepts?(ref, block.config)
        :error -> true
      end
    end)
  end

  # Sabotage: definition/2 answering Map.put(shipped, "required", ["config"])
  # -> a generated core block with no config goes red.
  test "every generated document whose core blocks the package accepts validates" do
    palette = Palette.core()
    schema = palette |> Schema.for_palette() |> resolve()

    accepted =
      0..(@corpus_size - 1)
      |> Enum.map(&{&1, DocumentGenerator.generate(@seed, &1)})
      |> Enum.filter(fn {_index, document} -> accepted_by(palette, document) end)

    assert length(accepted) >= 20

    for {index, document} <- accepted do
      json = Document.to_json(document)
      assert {:ok, _document} = Document.from_json(json), "index #{index}"
      assert validate(schema, JSON.decode!(json)) == :ok, "index #{index}"
    end
  end

  # A generated corpus of host blocks, from a fixed seed: each declared field
  # absent, `null`, a value of its own declared type, or a value drawn from a
  # pool of every JSON type, written where the field's value lives.
  @host_values [
    "",
    "text",
    "pigeon",
    0,
    3,
    true,
    false,
    [],
    ["branch", 2],
    [nil],
    %{},
    %{"desk" => 4}
  ]

  @host_types %{
    "library.overdue_notice" => OverdueNotice,
    "library.lax_renewal" => LaxRenewal,
    "parcel.route" => ParcelRoute
  }

  defp corpus_palette, do: Palette.new(Map.merge(Palette.core_types(), @host_types))

  # A value its declared type admits.
  defp own_value(type) when type in [:string, :expression, :duration], do: "text"
  defp own_value({:path, _opts}), do: "patron.email"
  defp own_value(:integer), do: :rand.uniform(9)
  defp own_value(:boolean), do: :rand.uniform(2) == 1
  defp own_value({:select, [{value, _label} | _rest]}) when is_binary(value), do: value
  defp own_value({:select, _unreadable}), do: "slow"
  defp own_value({:list, inner}), do: Enum.map(1..:rand.uniform(2), fn _n -> own_value(inner) end)
  defp own_value({:type_expr, _opts}), do: Enum.random(["due", [%{"name" => "due"}]])

  defp field_value(type) do
    case :rand.uniform(10) do
      1 -> :absent
      2 -> nil
      n when n <= 8 -> own_value(type)
      _n -> Enum.random(@host_values)
    end
  end

  # Writes `value` at `path`, building an object for a key and a one-element
  # list for a position; a step that already holds something else is left
  # alone, which is the absent case for the field beneath it.
  defp put_path(_container, [], value), do: value

  defp put_path(config, [key | rest], value) when is_map(config) and is_binary(key),
    do: Map.put(config, key, put_path(Map.get(config, key, empty(rest)), rest, value))

  defp put_path([element], [0 | rest], value), do: [put_path(element, rest, value)]
  defp put_path(other, _path, _value), do: other

  defp empty([index | _rest]) when is_integer(index), do: [%{}]
  defp empty(_path), do: %{}

  defp host_config(ref) do
    ref
    |> Palette.call(:config_schema, [%{}], [])
    |> Enum.reduce(%{}, fn decl, config ->
      case field_value(decl.type) do
        :absent -> config
        value -> put_path(config, BlockType.value_path(decl), value)
      end
    end)
  end

  defp host_document(index) do
    :rand.seed(:exsss, {@seed, index, 7})

    blocks =
      for n <- 1..:rand.uniform(3) do
        {type, ref} = Enum.random(@host_types)
        %{"id" => "blk_#{n}", "type" => type, "type_version" => 1, "config" => host_config(ref)}
      end

    document(%{
      "id" => "blk_ROOT",
      "type" => "core.sequence",
      "type_version" => 1,
      "slots" => %{"body" => blocks}
    })
  end

  # Sabotage: FieldType's json_type?("integer", _) answering `true` -> the
  # binding check admits a string renewals the schema refuses, and this goes
  # red.
  test "every generated host document whose blocks the package accepts validates" do
    palette = corpus_palette()
    schema = palette |> Schema.for_palette() |> resolve()

    {accepted, refused} =
      0..(@corpus_size - 1)
      |> Enum.map(fn index ->
        json = JSON.encode!(host_document(index))
        assert {:ok, document} = Document.from_json(json), "index #{index}"
        {index, json, document}
      end)
      |> Enum.split_with(fn {_index, _json, document} -> accepted_by(palette, document) end)

    assert length(accepted) >= 20

    # The corpus reaches the binding check: some documents a lax
    # validate_config/1 accepts are refused by the declared types alone.
    assert Enum.any?(refused, fn {_index, _json, document} ->
             document.root
             |> all_blocks()
             |> Enum.any?(fn block ->
               block.type == "library.lax_renewal" and
                 BlockType.field_type_findings(LaxRenewal, block.config) != []
             end)
           end)

    for {index, json, _document} <- accepted do
      assert validate(schema, JSON.decode!(json)) == :ok, "index #{index}"
    end
  end

  # --- a host type ------------------------------------------------------------

  # Sabotage: the "null" arm dropped from field_property/1's anyOf -> the
  # null subject goes red.
  test "a document using the host type validates, a null in a declared field included" do
    schema = host_palette() |> Schema.for_palette() |> resolve()

    for config <- [notice_config(), %{}, Map.put(notice_config(), "subject", nil)] do
      doc = document(notice(config))
      assert {:ok, _document} = Document.from_json(JSON.encode!(doc))
      assert OverdueNotice.validate_config(config) == :ok
      assert validate(schema, doc) == :ok, inspect(config)
    end
  end

  # Sabotage: field_property/1's base without "title" -> the comparison goes red.
  test "the generated definition names each declared field and slot, with its title and default" do
    notice = definition(Schema.for_palette(host_palette()), "library.overdue_notice")
    fields = get_in(notice, ["properties", "config", "properties"])

    assert fields == %{
             "subject" => %{
               "title" => "Subject",
               "default" => "Overdue",
               "anyOf" => [%{"type" => "null"}, %{"type" => "string"}]
             },
             "days_late" => %{
               "title" => "Days late",
               "default" => 1,
               "anyOf" => [%{"type" => "null"}, %{"type" => "integer"}]
             },
             "channel" => %{
               "title" => "Channel",
               "default" => "email",
               "anyOf" => [%{"type" => "null"}, %{"enum" => ["email", "letter"]}]
             },
             "copies" => %{
               "title" => "Copies",
               "default" => [],
               "anyOf" => [
                 %{"type" => "null"},
                 %{"type" => "array", "items" => %{"type" => "string"}}
               ]
             }
           }

    assert get_in(notice, ["properties", "slots", "properties"]) == %{
             "escalation" => %{
               "title" => "If the notice goes unanswered",
               "type" => "array",
               "items" => %{"$ref" => "#/definitions/block"}
             }
           }

    refute Map.has_key?(get_in(notice, ["properties", "config"]), "required")
    refute Map.has_key?(get_in(notice, ["properties", "config"]), "additionalProperties")
  end

  # Sabotage: field_property/1's anyOf replaced by [%{}], typing nothing ->
  # the schema admits the integer subject and goes red.
  test "an integer in the declared string field is refused by the schema and by validate_config/1" do
    config = Map.put(notice_config(), "subject", 42)
    doc = document(notice(config))

    assert {:ok, _document} = Document.from_json(JSON.encode!(doc))
    assert {:error, [_ | _]} = OverdueNotice.validate_config(config)
    refute package_accepts?(OverdueNotice, config)
    assert {:error, [_ | _]} = validate(host_palette() |> Schema.for_palette() |> resolve(), doc)
  end

  # Sabotage: the `false <- FieldType.admits?/2` step of BlockType's
  # field_type_finding/2 answering `true` -> nothing is judged, the package
  # admits the integer note and the refute goes red.
  test "an integer in the declared string field is refused by the package even where validate_config/1 accepts it" do
    config = %{"note" => 42}

    doc =
      document(%{
        "id" => "renewal",
        "type" => "library.lax_renewal",
        "type_version" => 1,
        "config" => config
      })

    assert {:ok, _document} = Document.from_json(JSON.encode!(doc))
    assert LaxRenewal.validate_config(config) == :ok

    assert [{"note", "the note field is declared a string, and holds an integer"}] =
             BlockType.field_type_findings(LaxRenewal, config)

    refute package_accepts?(LaxRenewal, config)

    assert {:error, [_ | _]} =
             validate(corpus_palette() |> Schema.for_palette() |> resolve(), doc)
  end

  # Sabotage: FieldType's loosen/2 {:list, inner} clause answering "items" => %{} ->
  # the integer copy is admitted and this goes red.
  test "each declared field type refuses a value of the wrong JSON type" do
    schema = host_palette() |> Schema.for_palette() |> resolve()

    for {key, value} <- [{"days_late", "three"}, {"channel", "pigeon"}, {"copies", ["branch", 7]}] do
      doc = document(notice(Map.put(notice_config(), key, value)))
      assert match?({:error, [_ | _]}, validate(schema, doc)), key
    end
  end

  # Sabotage: put_at/3 naming the whole value_path as one flat key -> the
  # nested depot comparison goes red.
  test "a field is named at a string-key path, never at a list position" do
    route = definition(Schema.for_palette(host_palette()), "parcel.route")
    config = get_in(route, ["properties", "config", "properties"])

    assert get_in(config, ["route", "properties", "origin", "properties", "depot", "title"]) ==
             "Depot"

    refute Map.has_key?(config["route"], "type")
    refute Map.has_key?(config, "stops")
    refute Map.has_key?(config, "first_stop")

    schema = host_palette() |> Schema.for_palette() |> resolve()

    parcel = fn config ->
      document(%{"id" => "r", "type" => "parcel.route", "type_version" => 1, "config" => config})
    end

    assert validate(schema, parcel.(%{"route" => %{"origin" => %{"depot" => "north"}}})) == :ok
    assert validate(schema, parcel.(%{"route" => "direct", "stops" => [%{"name" => 4}]})) == :ok

    assert {:error, [_ | _]} =
             validate(schema, parcel.(%{"route" => %{"origin" => %{"depot" => 9}}}))
  end

  # Sabotage: FieldType's loosen/2 {:type_expr, _} clause answering the fragment as is
  # -> the manifest keeps the member constraint and the comparison goes red.
  test "a type_expr field carries no member constraint, and an unreadable declaration no type" do
    config =
      Schema.for_palette(host_palette())
      |> definition("parcel.route")
      |> get_in(["properties", "config", "properties"])

    assert config["manifest"]["anyOf"] == [%{"type" => "null"}, %{"type" => ["string", "array"]}]
    assert config["speed"] == %{"title" => "Speed", "default" => "slow"}
  end

  # --- degradation --------------------------------------------------------------

  # Sabotage: safe_call/4's rescue answering {:ok, []} rather than :error ->
  # the raising type gets an empty typed definition and this goes red.
  test "a host type whose config_schema/1 raises or answers a non-list gets the generic definition" do
    palette = Palette.new(%{"library.raising" => RaisingSchema, "library.map" => NonListSchema})
    schema = Schema.for_palette(palette)

    for name <- ["library.raising", "library.map"] do
      definition = definition(schema, name)
      assert definition["properties"] == %{"type" => %{"const" => name}}, name
    end

    block = %{
      "id" => "b",
      "type" => "library.raising",
      "type_version" => 1,
      "config" => %{"subject" => 1}
    }

    assert validate(resolve(schema), document(block)) == :ok
  end

  # Sabotage: safe_call/4 calling apply(ref, callback, args) rather than
  # Palette.call/4 -> the stateful entry degrades to generic and goes red.
  test "a {module, state} type ref is read through its state" do
    palette = Palette.new(%{"library.desk" => {StatefulDesk, "desk"}})
    schema = Schema.for_palette(palette)

    assert get_in(definition(schema, "library.desk"), [
             "properties",
             "config",
             "properties",
             "desk",
             "title"
           ]) ==
             "Desk"

    block = fn value ->
      document(%{
        "id" => "d",
        "type" => "library.desk",
        "type_version" => 1,
        "config" => %{"desk" => value}
      })
    end

    assert validate(resolve(schema), block.(2)) == :ok
    assert {:error, [_ | _]} = validate(resolve(schema), block.("front"))
  end

  # Sabotage: "else" => false added to each clause -> the unknown type goes red.
  test "a block of a type outside the palette validates" do
    block = %{
      "id" => "x",
      "type" => "parcel.unheard_of",
      "type_version" => 2,
      "config" => %{"a" => [1, nil]}
    }

    assert validate(host_palette() |> Schema.for_palette() |> resolve(), document(block)) == :ok
  end

  # --- the answer itself --------------------------------------------------------

  # Sabotage: for_palette/1's Enum.sort_by/2 replaced by Enum.to_list/1 ->
  # the order assertion goes red.
  test "equal palettes answer equal maps, in type-name order, which encode and resolve" do
    # More than 32 entries, so the palette's map does not iterate in name order.
    branches = Map.new(1..20, &{"library.branch_#{&1}", OverdueNotice})
    types = Map.merge(host_palette().types, branches)
    first = Schema.for_palette(Palette.new(types))
    second = Schema.for_palette(Palette.new(types |> Enum.reverse() |> Map.new()))

    assert first == second
    assert JSON.encode!(first) == JSON.encode!(second)
    assert first |> JSON.encode!() |> JSON.decode!() == first
    assert %ExJsonSchema.Schema.Root{} = resolve(first)
    assert %ExJsonSchema.Schema.Root{} = resolve(Schema.for_palette(Palette.core()))

    names =
      first
      |> get_in(["definitions", "block", "allOf"])
      |> Enum.map(&get_in(&1, ["if", "properties", "type", "const"]))

    assert length(names) == map_size(types)
    assert names == Enum.sort(names)
  end

  # Sabotage: for_palette/1's Map.delete("$id") deleting another key -> the refute goes red.
  test "an empty palette answers the shipped root's definitions, with no $id" do
    shipped = JSON.decode!(Schema.json())
    schema = Schema.for_palette(Palette.new())

    refute Map.has_key?(schema, "$id")
    assert schema["definitions"] == shipped["definitions"]

    assert Map.drop(schema, ["title", "description"]) ==
             Map.drop(shipped, ["$id", "title", "description"])
  end
end
