# How to validate a document against the schema from any language

This guide shows you how to check a stored block document against the
package's JSON Schema from a service that is not written in Elixir, how to
ask for a stricter schema built from your own palette, and how to check that
your palette is ready for a package version that holds every config to its
declared field types.

The validation reads a saved document and never compiles it. The package
ships the schema and no validator: you check a document with a draft-07
validator in your own language.
`StatifierBlocks.Schema`'s docs list every
difference between the schema and the decoder, and
[ADR-0015](https://github.com/riddler/statifier_blocks/blob/main/docs/adr/0015-block-document-json-schema.md)
is the record.

The example is patron registration: a visitor becomes a library patron
through a few screens, and a service stores the document that describes
them as JSON.

Every snippet on this page runs, in order, as one script:
[`test/statifier_blocks/describing_a_document_guide_test.exs`](https://github.com/riddler/statifier_blocks/blob/main/test/statifier_blocks/describing_a_document_guide_test.exs)
evaluates them on every build and asserts every `#=>` output against what
the code answers.

## Hand the schema file to your service

The schema (draft-07) is at `priv/schemas/block-document.schema.json`.
`StatifierBlocks.Schema.path/0` names the installed file, so a build step can
copy it into a service written in another language, and
`StatifierBlocks.Schema.json/0` hands over its content.

```elixir
alias StatifierBlocks.Schema

same_file = File.read!(Schema.path()) == Schema.json()
#=> true

draft = Schema.json() |> JSON.decode!() |> Map.fetch!("$schema")
#=> "http://json-schema.org/draft-07/schema#"
```

## Check a stored document

Any draft-07 validator reads the file. The snippets here use ex_json_schema,
the one this package's own tests use (a test-only dependency, never a
dependency of this package at runtime). Add it to your own project the same
way, or use the validator of your service's language; the schema is the same
file either way.

This one checks a patron registration document that a service stored as JSON,
then the same document with its root removed:

```elixir
schema = Schema.path() |> File.read!() |> JSON.decode!() |> ExJsonSchema.Schema.resolve()

stored = ~s({
  "schema_version": 1,
  "id": "bdoc_patron_registration",
  "revision": 3,
  "root": {
    "id": "submit",
    "type": "core.send",
    "type_version": 1,
    "config": {"event": "registration.submitted"}
  }
})

checked = ExJsonSchema.Validator.validate(schema, JSON.decode!(stored))
#=> :ok

missing_root = stored |> JSON.decode!() |> Map.delete("root")
refused = match?({:error, [_ | _]}, ExJsonSchema.Validator.validate(schema, missing_root))
#=> true
```

## Know what the schema admits that the decoder refuses

The schema never refuses a document `StatifierBlocks.Document.from_json/1`
accepts, but it admits some that `from_json/1` refuses: a document that
repeats a block id or a datamodel entry id, and a whole number spelled with a
fraction or an exponent (`1.0`, `1e2`) where an integer is read. A document
that passes the schema is worth handing to `from_json/1`; only `from_json/1`
says it is one.

The typed `config` and `slots` descriptions of the `core.*` types sit under
`definitions/core` and the root does not apply them, so a block of a host
type validates.

## Ask for a stricter schema for your palette

A host that knows its palette can ask for a stricter schema.
`StatifierBlocks.Schema.for_palette/1` answers the same root with every block
also judged by its own type's definition: a `core.*` type's from
`definitions/core`, and a host type's generated from its declared
`config_schema/1` and `slots/1`, each declared field typed from its declared
field type (or `null`) with its label as `title` and its default as
`default`. A `core.*` type is judged by its `definitions/core` entry as
shipped, required keys and identifier patterns included. For a host type,
nothing past a field's declared type is checked: bounds, cross-field rules and
whether a field must be present stay with the type's `validate_config/1`. A
block of a type the palette does not carry is judged by the generic shape
alone.

The stored document passes both schemas. A document whose `send` event is the
number 5 passes the root and is refused by the palette's schema:

```elixir
palette_schema =
  StatifierBlocks.Palette.core() |> Schema.for_palette() |> ExJsonSchema.Schema.resolve()

typed = ExJsonSchema.Validator.validate(palette_schema, JSON.decode!(stored))
#=> :ok

numbered = put_in(JSON.decode!(stored), ["root", "config", "event"], 5)
root_admits = ExJsonSchema.Validator.validate(schema, numbered)
#=> :ok

palette_refuses =
  match?({:error, [_ | _]}, ExJsonSchema.Validator.validate(palette_schema, numbered))
#=> true
```

## Check your palette before taking a stricter package version

The package holds a config to the same declared field types: a value its
field's declared type does not admit is refused at compile, at the edit gate
and in the view model, ahead of the type's own `validate_config/1` findings.

Before taking the version that made that so, run
`StatifierBlocks.Palette.preflight/1` over your palette. It lists every host
type whose own defaults, or the block `Palette.new_block/2` builds from them,
disagree with their declared field types, each finding naming the type, the
field's key, its declared type and the value; a type whose callbacks raise is
listed, not raised. `StatifierBlocks.Palette.preflight/2` takes the documents
you store as well and also lists every block of a type the palette carries
whose config would be refused, by block id. An empty list means you are ready.
