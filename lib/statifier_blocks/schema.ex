defmodule StatifierBlocks.Schema do
  @moduledoc """
  The block document's JSON Schema (draft-07), shipped in this package at
  `priv/schemas/block-document.schema.json`.

  A host that stores or receives block documents outside Elixir can check
  them against this file with a validator of its own choosing. This package
  ships no validator and runs none: `path/0` names the installed file and
  `json/0` hands over its content.

  ## What the root admits

  The root describes every check `StatifierBlocks.Document.from_json/1`
  makes that JSON Schema can express: the envelope, the generic block shape
  every type satisfies, the `datamodel` and `accepts` keys, and the
  canonical value grammar (integers, never floats, in `config` and
  `metadata`). It never refuses a document `from_json/1` accepts. Where it
  admits more, the section below says so.

  The typed `config` and `slots` descriptions for the `core.*` types sit
  under `definitions/core`, keyed by type name, and the root does **not**
  apply them. Validation is registry-free, so a block of an unknown host type
  validates, and so does a `core.*` block whose config its own definition
  would refuse. A definition is meant to be applied together with
  `#/definitions/block`, and it is never stricter than the type's
  `validate_config/1`.

  ## What the schema cannot say

  These stay the decoder's and the type's alone:

    * that block ids are unique across the whole document;
    * that datamodel entry ids are unique;
    * key order, whitespace, or anything else about canonical bytes;
    * a slot's arity (a definition names it in words, never enforces it);
    * whether a type's config is valid, which the type's
      `validate_config/1` owns.

  ## Where the root admits more than the package

  The root admits two kinds of document that `from_json/1` refuses:

    * a document that repeats a block id or a datamodel entry id, since
      uniqueness is one of the things above the schema cannot say;
    * a whole number spelled with a fraction or an exponent, such as `1.0`
      or `1e2`, wherever an integer is read: `schema_version`, `revision`,
      `type_version`, and inside `config` or `metadata`. Draft-07 counts a
      number with a zero fractional part as an integer, while this package
      decodes such a spelling as a float and refuses it. The canonical
      encoder never writes one.

  In the other direction there is no exception: the root refuses no
  document the package accepts.

  ## A schema for a palette

  `for_palette/1` answers a schema for one palette: the root above, with
  every block judged by its own type's definition as well as by the
  generic block shape. A `core.*` entry takes its definition from
  `definitions/core`, verbatim. Any other entry - a host type, or a host
  module mounted under a `core.` name - takes one generated from its
  `config_schema/1` and `slots/1` as declared for the config
  `StatifierBlocks.Palette.new_block/2` builds: each declared field named with
  its label as `title` and its default as `default`, and typed from its
  declared field type, with `null` admitted beside it; each declared slot
  named as a list of blocks. A name the palette does not carry takes the
  generic block shape alone, as it decodes.

  A generated definition never carries `required?` into `required`, never
  closes `config` or `slots` to keys it does not name, and never names a
  field whose `value_path` carries a list position. A `{:type_expr, opts}`
  field is typed as a string or an array, with no constraint on its
  members. An entry whose `config_schema/1` or `slots/1` raises, or
  answers something other than a list of declarations, gets the generic
  definition rather than a raise.
  """

  alias StatifierBlocks.Palette
  alias StatifierBlocks.Schema.HostDefinition

  @source Path.expand("../../priv/schemas/block-document.schema.json", __DIR__)
  @external_resource @source
  @json File.read!(@source)
  @root JSON.decode!(@json)

  @doc """
  The installed schema file's absolute path.

      iex> File.read!(StatifierBlocks.Schema.path()) == StatifierBlocks.Schema.json()
      true

  """
  @spec path() :: Path.t()
  def path, do: Application.app_dir(:statifier_blocks, "priv/schemas/block-document.schema.json")

  @doc """
  The schema's content, embedded when this package is compiled.

      iex> StatifierBlocks.Schema.json() |> JSON.decode!() |> Map.fetch!("$schema")
      "http://json-schema.org/draft-07/schema#"

  """
  @spec json() :: String.t()
  def json, do: @json

  @doc """
  A draft-07 schema for `palette`'s block types, as a map with string keys
  that `JSON.encode!/1` serializes.

  It is the shipped root with every block, the root block and every slot's
  children alike, also judged by a definition keyed on its `type`: a core
  entry's from `definitions/core`, any other entry's generated from its
  declared `config_schema/1` and `slots/1` (see "A schema for a palette"
  above). A block whose type the palette does not carry is judged by the
  generic block shape alone, and a palette with no entries answers a schema
  that admits exactly what the shipped root admits. The answer carries no
  `$id`: it is not the shipped file.

  It consults no validator, network or clock, and two calls on equal
  palettes answer equal maps. Every document the package admits validates
  against it when every block whose type the palette carries answers `:ok`
  from its `validate_config/1` and holds, in each field its
  `config_schema/1` declares for the config `Palette.new_block/2` builds, a
  value the field's type admits.

      iex> schema = StatifierBlocks.Schema.for_palette(StatifierBlocks.Palette.new())
      iex> {schema["$schema"], Map.has_key?(schema, "$id")}
      {"http://json-schema.org/draft-07/schema#", false}

  """
  @spec for_palette(Palette.t()) :: map()
  def for_palette(%Palette{types: types}) do
    clauses =
      types
      |> Enum.sort_by(fn {name, _ref} -> name end)
      |> Enum.map(fn {name, ref} ->
        %{
          "if" => %{"properties" => %{"type" => %{"const" => name}}, "required" => ["type"]},
          "then" => definition(name, ref)
        }
      end)

    root =
      @root
      |> Map.delete("$id")
      |> Map.put("title", "Block document, for a palette")
      |> Map.put(
        "description",
        "A statifier_blocks block document, schema_version 1, judged by the shipped root " <>
          "and, for every block whose type the palette carries, by that type's definition."
      )

    case clauses do
      [] -> root
      clauses -> put_in(root, ["definitions", "block", "allOf"], clauses)
    end
  end

  # A core entry is a name whose entry is the module `Palette.core_types/0`
  # maps it to; its definition is the shipped file's, verbatim.
  defp definition(name, ref) do
    with {:ok, ^ref} <- Map.fetch(Palette.core_types(), name),
         {:ok, shipped} <- Map.fetch(@root["definitions"]["core"], name) do
      shipped
    else
      _host -> HostDefinition.generate(ref, name)
    end
  end
end
