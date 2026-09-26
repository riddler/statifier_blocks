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
  """

  @source Path.expand("../../priv/schemas/block-document.schema.json", __DIR__)
  @external_resource @source
  @json File.read!(@source)

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
end
