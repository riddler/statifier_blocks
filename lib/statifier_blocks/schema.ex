defmodule StatifierBlocks.Schema do
  @moduledoc """
  The block document's JSON Schema (draft-07), shipped in this package at
  `priv/schemas/block-document.schema.json`.

  A host that stores or receives block documents outside Elixir can check
  them against this file with a validator of its own choosing. This package
  ships no validator and runs none: `path/0` names the installed file and
  `json/0` hands over its content.

  ## What the root admits

  The root admits exactly the documents `StatifierBlocks.Document.from_json/1`
  accepts, as this package decodes them: the envelope, the generic block
  shape every type satisfies, the `datamodel` and `accepts` keys, and the
  canonical value grammar (integers, never floats, in `config` and
  `metadata`).

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

  ## The 1.0 edge

  Draft-07 counts a number with a zero fractional part as an integer, so a
  validator admits a literal `1.0` in `config` or `metadata` wherever it
  admits `1`. This package decodes `1.0` as a float and refuses it. That is
  the one place the root admits a document the package refuses; it never
  refuses one the package accepts.
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
