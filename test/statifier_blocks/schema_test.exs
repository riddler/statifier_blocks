defmodule StatifierBlocks.SchemaTest do
  use ExUnit.Case, async: true

  alias StatifierBlocks.{Block, ByteCorpus, Document, DocumentGenerator, Palette, Schema}

  doctest StatifierBlocks.Schema

  @draft_07 "http://json-schema.org/draft-07/schema#"

  @fixtures_dir "test/fixtures/documents"

  # Composite data declarations (keys type_name, version, params,
  # palette_entry, subtree), not block documents: the migration guide's
  # test reads them as declarations, and the schema is not about them.
  @not_block_documents [
    "migrating_0_27_to_0_34/screen_before.json",
    "migrating_0_27_to_0_34/screen_after.json"
  ]

  @flow_graph_note "docs/block-level-flow-graph.md"
  @library_loan_heading "## Worked example: a library loan"
  @patron_registration "test/fixtures/documents/patron_registration.json"

  # Fixed, never seeded from the clock, so a red corpus run names an index
  # `DocumentGenerator.generate/2` regenerates exactly.
  @seed 515_151
  @corpus_size 100

  # --- helpers ---------------------------------------------------------------

  defp root_map, do: JSON.decode!(Schema.json())

  defp root_schema, do: ExJsonSchema.Schema.resolve(root_map())

  defp validate(schema, data), do: ExJsonSchema.Validator.validate(schema, data)

  # A schema applying `#/definitions/block` and one core definition
  # together, the way a definition is meant to be applied.
  defp definition_schema(type) do
    ExJsonSchema.Schema.resolve(%{
      "$schema" => @draft_07,
      "definitions" => root_map()["definitions"],
      "allOf" => [
        %{"$ref" => "#/definitions/block"},
        %{"$ref" => "#/definitions/core/" <> type}
      ]
    })
  end

  defp block_documents do
    @fixtures_dir
    |> Path.join("**/*.json")
    |> Path.wildcard()
    |> Enum.reject(&(Path.relative_to(&1, @fixtures_dir) in @not_block_documents))
    |> Enum.sort()
  end

  defp library_loan_json do
    [_before, after_heading] = String.split(File.read!(@flow_graph_note), @library_loan_heading)
    [_all, json] = Regex.run(~r/```json\n(.*?)\n```/s, after_heading)
    json
  end

  defp valid_document do
    %{
      "schema_version" => 1,
      "id" => "bdoc_01JSCHEMA",
      "revision" => 0,
      "metadata" => %{"name" => "Schema"},
      "datamodel" => [%{"id" => "patron", "description" => "The patron."}],
      "accepts" => ["loan.renewed"],
      "root" => %{
        "id" => "blk_ROOT",
        "type" => "core.sequence",
        "type_version" => 1,
        "slots" => %{
          "body" => [
            %{
              "id" => "blk_WAIT",
              "type" => "core.wait",
              "type_version" => 1,
              "config" => %{"duration" => "5m"}
            }
          ]
        }
      }
    }
  end

  defp put_root(document, key, value), do: put_in(document, ["root", key], value)

  # Every block object in a decoded JSON tree, pre-order.
  defp block_maps(%{} = block) do
    children =
      block
      |> Map.get("slots", %{})
      |> Map.values()
      |> Enum.flat_map(fn list -> Enum.flat_map(list, &block_maps/1) end)

    [block | children]
  end

  # --- a. the file itself -----------------------------------------------------

  # Sabotage: path/0 naming a different file under priv/ -> the File.read! raises.
  test "path/0 names the file json/0 embeds, which resolves as a draft-07 schema" do
    assert File.read!(Schema.path()) == Schema.json()
    assert root_map()["$schema"] == @draft_07
    assert %ExJsonSchema.Schema.Root{} = root_schema()
  end

  # --- b and c. the fixture documents -----------------------------------------

  # Sabotage: "additionalProperties": false added to json_value -> every fixture with nested config goes red.
  test "every block document fixture decodes with the package and validates" do
    documents = block_documents()
    assert documents != []
    schema = root_schema()

    for path <- documents do
      bytes = File.read!(path)
      assert {:ok, %Document{}} = Document.from_json(bytes), path
      assert validate(schema, JSON.decode!(bytes)) == :ok, path
    end
  end

  # Sabotage: root "required" gaining "datamodel" -> a fixture declaring no datamodel goes red.
  test "the package's canonical encoding of every fixture validates" do
    schema = root_schema()

    for path <- block_documents() do
      {:ok, document} = Document.from_json(File.read!(path))
      assert validate(schema, JSON.decode!(Document.to_json(document))) == :ok, path
    end
  end

  # Sabotage: json_value's "items" given "type": "string" -> an entry holding a list of objects goes red.
  test "the canonical encoding of every byte corpus document validates" do
    schema = root_schema()

    for {name, document, _palette} <- ByteCorpus.entries() do
      json = Document.to_json(document)
      assert {:ok, _document} = Document.from_json(json), name
      assert validate(schema, JSON.decode!(json)) == :ok, name
    end
  end

  # --- d. the flow-graph note's worked examples -------------------------------

  # Sabotage: "accepts" items narrowed to "maxLength": 5 -> the library loan's accepts go red.
  test "the flow-graph note's worked examples decode and validate" do
    schema = root_schema()
    loan = library_loan_json()

    assert {:ok, %Document{}} = Document.from_json(loan)
    assert validate(schema, JSON.decode!(loan)) == :ok
    assert validate(schema, @patron_registration |> File.read!() |> JSON.decode!()) == :ok
  end

  # --- e. the generated corpus ------------------------------------------------

  # Sabotage: json_value's type list losing "null" -> generated config holding null goes red.
  test "every generated document's canonical encoding validates" do
    schema = root_schema()

    for index <- 0..(@corpus_size - 1) do
      json = @seed |> DocumentGenerator.generate(index) |> Document.to_json()
      assert {:ok, _document} = Document.from_json(json), "index #{index}"
      assert validate(schema, JSON.decode!(json)) == :ok, "index #{index}"
    end
  end

  # --- f and g. registry-free validation --------------------------------------

  # Sabotage: block "type" given an enum of the core.* names -> the host type goes red.
  test "a block of an unknown host type validates" do
    document =
      put_root(valid_document(), "slots", %{
        "body" => [
          %{
            "id" => "blk_HOST",
            "type" => "myapp.notify",
            "type_version" => 3,
            "config" => %{"channel" => "email", "retries" => 2, "tags" => ["a", nil, true]}
          }
        ]
      })

    assert {:ok, _document} = Document.from_json(JSON.encode!(document))
    assert validate(root_schema(), document) == :ok
  end

  # Sabotage: core.wait's "duration" losing its "type": "string" -> the definition verdict goes red.
  test "a core block its own definition refuses still validates against the root" do
    wait = %{
      "id" => "blk_WAIT",
      "type" => "core.wait",
      "type_version" => 1,
      "config" => %{"duration" => 5}
    }

    document = put_root(valid_document(), "slots", %{"body" => [wait]})

    assert {:ok, _document} = Document.from_json(JSON.encode!(document))
    assert validate(root_schema(), document) == :ok
    assert {:error, _errors} = validate(definition_schema("core.wait"), wait)
  end

  # --- h. refusals the schema expresses ---------------------------------------

  @negatives [
    # Sabotage: "number" added to json_value's type list -> this case goes red.
    {"a float in config", ["root", "config"], %{"ratio" => 1.5}},
    # Sabotage: "number" added to json_value's type list -> this case goes red.
    {"a float in metadata", ["metadata"], %{"weight" => 0.25}},
    # Sabotage: the root's "additionalProperties": false deleted -> this case goes red.
    {"an unknown envelope key", ["extra"], true},
    # Sabotage: block's "additionalProperties": false deleted -> this case goes red.
    {"an unknown block key", ["root", "extra"], true},
    # Sabotage: schema_version's "const": 1 deleted -> this case goes red.
    {"schema_version 2", ["schema_version"], 2},
    # Sabotage: revision's "minimum": 0 deleted -> this case goes red.
    {"a negative revision", ["revision"], -1},
    # Sabotage: datamodel_entry id's "pattern" deleted -> this case goes red.
    {"a datamodel entry id with an upper-case letter", ["datamodel"], [%{"id" => "Patron"}]},
    # Sabotage: datamodel_entry id's "not" clause deleted -> this case goes red.
    {"a datamodel entry id ending in a newline", ["datamodel"], [%{"id" => "patron\n"}]},
    # Sabotage: expr's "$ref" to non_empty_string deleted -> this case goes red.
    {"an explicit null entry field", ["datamodel"], [%{"id" => "patron", "expr" => nil}]},
    # Sabotage: accepts' "uniqueItems": true deleted -> this case goes red.
    {"a duplicate accepts name", ["accepts"], ["loan.renewed", "loan.renewed"]},
    # Sabotage: slots' "propertyNames" deleted -> this case goes red.
    {"an empty slot name", ["root", "slots"], %{"" => []}},
    # Sabotage: type_version's "minimum": 1 deleted -> this case goes red.
    {"type_version 0", ["root", "type_version"], 0},
    # Sabotage: block id's "$ref" to non_empty_string deleted -> this case goes red.
    {"an empty block id", ["root", "id"], ""}
  ]

  # The negatives below each change one thing in this document, so it has
  # to be admitted by both sides or they would prove nothing.
  # Sabotage: the root's "accepts" items given "maxLength": 5 -> the schema verdict goes red.
  test "the document the negatives start from decodes and validates" do
    document = valid_document()

    assert {:ok, %Document{}} = Document.from_json(JSON.encode!(document))
    assert validate(root_schema(), document) == :ok
  end

  for {name, keys, value} <- @negatives do
    # Sabotage: per case, the note above its entry in @negatives.
    test "the package and the schema both refuse #{name}" do
      document = put_in(valid_document(), unquote(keys), unquote(Macro.escape(value)))

      assert {:error, _reason} = Document.from_json(JSON.encode!(document))
      assert {:error, _errors} = validate(root_schema(), document)
    end
  end

  # --- i. refusals only the decoder can make ----------------------------------

  # JSON Schema cannot compare values across the document, so these two
  # refusals are the decoder's alone: a block id used twice anywhere in
  # the tree, and a datamodel entry id declared twice. The schema admits
  # both; this test records the gap rather than hiding it.
  # Sabotage: Validation's duplicate block id check removed -> the from_json assertion goes red.
  test "a duplicate block id and a duplicate datamodel id are the decoder's refusals alone" do
    twice = %{"id" => "blk_ROOT", "type" => "core.wait", "type_version" => 1}
    duplicate_block = put_root(valid_document(), "slots", %{"body" => [twice]})

    duplicate_entry =
      Map.put(valid_document(), "datamodel", [%{"id" => "patron"}, %{"id" => "patron"}])

    schema = root_schema()

    for document <- [duplicate_block, duplicate_entry] do
      assert {:error, _reason} = Document.from_json(JSON.encode!(document))
      assert validate(schema, document) == :ok
    end
  end

  # --- j. the core definitions ------------------------------------------------

  # Sabotage: the "core.drafts" definition deleted -> the key comparison goes red.
  test "there is exactly one definition per core type, under definitions/core" do
    core_definitions = root_map() |> get_in(["definitions", "core"]) |> Map.keys() |> Enum.sort()

    assert core_definitions == Palette.core_types() |> Map.keys() |> Enum.sort()
  end

  # Sabotage: the $id's trailing schema_version changed to 2 -> the comparison goes red.
  test "the $id names the schema_version the package writes" do
    %Document{schema_version: version} =
      Document.new(%Block{id: "blk_A", type: "core.sequence", type_version: 1})

    assert root_map()["$id"] == "urn:statifier-blocks:block-document:#{version}"
  end

  # Sabotage: core.sequence's config gaining "additionalProperties": false -> generated core.sequence blocks go red.
  test "no core definition refuses a block its type's validate_config/1 accepts" do
    fixture_documents = Enum.map(block_documents(), &File.read!/1)

    generated =
      Enum.map(0..(@corpus_size - 1), fn index ->
        @seed |> DocumentGenerator.generate(index) |> Document.to_json()
      end)

    blocks =
      [library_loan_json() | fixture_documents ++ generated]
      |> Enum.flat_map(fn json ->
        json |> JSON.decode!() |> Map.fetch!("root") |> block_maps()
      end)

    core_types = Palette.core_types()
    schemas = Map.new(core_types, fn {type, _module} -> {type, definition_schema(type)} end)

    accepted =
      Enum.filter(blocks, fn block ->
        case Map.fetch(core_types, block["type"]) do
          {:ok, module} -> module.validate_config(Map.get(block, "config", %{})) == :ok
          :error -> false
        end
      end)

    assert accepted != []

    for block <- accepted do
      assert validate(Map.fetch!(schemas, block["type"]), block) == :ok, inspect(block)
    end
  end
end
