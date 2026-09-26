# ADR-0015: The block document ships a JSON Schema whose root admits exactly what the package admits, and a palette can generate its own

Status: proposed (2026-09-26, drafted under the operator's campaign consent;
the rulings it records were taken by the operator on 2026-09-26). It merges
at proposed; flipping it to accepted is a separate request through the same
`docs/adr/` gate, after the code that builds it has shipped in a published
version.

Code cites below were read at `2033622` and carry their anchors; re-locate
by anchor, not by number.

## Context

**The document is language-neutral, and its grammar is written only in
Elixir.** ADR-0001 decision 8 made JSON the canonical form precisely so that
"non-Elixir tooling in the host" can read a stored document, and decision 9
made loading it a structural, registry-free check. That check exists today as
two modules and nothing else: `StatifierBlocks.Decode`
(`lib/statifier_blocks/decode.ex:55`, `def decode/1`) refuses bytes the
encoder would never write - an unknown envelope key (`@envelope_keys` at
`:51`, enforced by `defp ensure_known_envelope_keys/1` at `:113`), an unknown
block key (`@block_keys` at `:50`, `defp decode_block/1` at `:128`), an
unknown or explicitly `null` datamodel entry key (`@entry_keys` at `:52`,
`defp reject_explicit_null/4` at `:274`) - and hands everything else to
`StatifierBlocks.Validation` (`lib/statifier_blocks/validation.ex:50`,
`def validate/1`), which checks the envelope, every block pre-order, and id
uniqueness. A host writing a document from a form in another language, a
review tool linting a stored document, or an editor outside this package has
no statement of that grammar it can run. It re-derives one from the Elixir,
and a re-derived grammar drifts.

**JSON Schema can say most of it, and exactly which part it cannot is
knowable.** Every field shape Validation checks - `schema_version` equal to
`1` (`defp check_schema_version/1`, `:72`), a non-empty `id`, a non-negative
integer `revision` (`defp check_revision/1`, `:90`), `metadata` and `config`
as JSON objects with no float anywhere inside them (`defp
canonical_json_check/2`'s float arm, `:416`), `datamodel` entries of
ADR-0001 11b's grammar, `accepts` as ADR-0014 decision 2's list of non-empty
strings, a slot as a list of blocks under a non-empty name (`defp
validate_slot/4`, `:354`) - is a JSON Schema keyword. Some things are not:
the canonical form's key order and whitespace (`CanonicalJson.encode/1`,
`lib/statifier_blocks/canonical_json.ex:33`), the SHA-256 identity over those
bytes, block-id uniqueness across the whole tree (`defp
validate_unique_ids/1`, `validation.ex:380`), datamodel-id uniqueness within
the key (`defp check_datamodel_unique_ids/1`, `:193`), and a slot's arity
against its parent's config. Duplicate `accepts` names are the exception in
that family: `accepts` entries are bare strings, so `uniqueItems` expresses
`defp check_accepts_unique/1` (`:258`) exactly, while two datamodel entries
sharing an `id` but differing in `expr` are distinct items to `uniqueItems`.

**A block type's config has two descriptions, and only one is the
authority.** ADR-0002 decision 7 gives every block type a `config_schema/1`
(`lib/statifier_blocks/block_type.ex:462`, `@callback config_schema`) and a
`validate_config/1` (`:470`, `@callback validate_config`), and says in terms
that "`validate_config/1` is the authority" and the schema "a rendering hint
that happens to catch the easy cases early". `config_schema/1` is a list of
form fields, parameterized by the config itself, whose entries may live at a
`value_path` rather than at `config[key]` - `core.branch`'s per-arm condition
fields are keyed by slot name and stored under `arms` - so it is not a JSON
Schema and cannot be mechanically read as one. `slots/1` (`:335`, `@callback
slots`) is likewise parameterized by config: a branch has one slot per arm.

**And the package admits documents whose blocks their own types would
refuse.** Decoding and validation never resolve a type (ADR-0001 decision 9;
the moduledoc comment at the head of `validation.ex`). A `core.wait` whose
config lacks `duration` is refused by `Core.Wait.validate_config/1`
(`lib/statifier_blocks/core/wait.ex:79`) and admitted by `from_json/1`; the
document generator the round-trip properties run on draws `core.*` type
names with arbitrary config and arbitrary slot names
(`test/support/document_generator.ex:285`, `defp gen_block/1`, over
`@type_names` at `:50`), and every document it builds is one the package
admits. A schema that typed each core block's config at the root would refuse
those documents.

## Decision

**1. Draft-07, and the validator is test-only.** The schema is written to
JSON Schema draft-07 (`"$schema": "http://json-schema.org/draft-07/schema#"`),
the draft with the widest validator support across the languages a host is
likely to read the document in. This package validates against it with
`ex_json_schema ~> 0.11`, declared `only: :test`: it lands in `mix.lock`, it
resolves in the headless tree (ADR-0005 decision 1) like every other
test dependency, and no host gains a runtime dependency. Nothing in `lib/`
calls a validator; the package's own refusal remains `Decode` plus
`Validation`, unchanged.

**2. The file is hand-written, and a drift test holds it to the package.**
The shipped file is authored by hand, not generated from `config_schema/1`,
for the reason the Context gives: `config_schema/1` is a rendering hint list,
parameterized by config, whose branch arms are keyed by slot name and stored
at a value path, and a generator reading it would encode a second guess at
what `validate_config/1` accepts. The drift test (`ex_json_schema` in the
`:test` env) fails when the file and the package disagree, in both
directions:

- every document the package admits validates against the root - the byte
  corpus, the document fixtures, and the document generator's output;
- every refusal of `Decode` or `Validation` that JSON Schema can express is
  a refusal of the root too, one case per expressible refusal arm;
- the root's `$id` names the `schema_version` the package writes, and the
  set of names under `definitions/core` equals the keys of
  `Palette.core_types/0` (`lib/statifier_blocks/palette.ex:219`).

A request that changes what `Decode` or `Validation` admits edits the file in
the same request; the drift test is what makes that a gate rather than a
convention.

**3. The root admits exactly what `Decode` plus `Validation` admit, judged on
documents as the package decodes them, and never refuses a document the
package accepts.** The root describes, with `additionalProperties: false`
wherever the decoder refuses an unknown key:

- **The envelope.** Required `schema_version` (`const: 1`), `id` (string,
  `minLength: 1`), `revision` (integer, `minimum: 0`), `root` (a block).
  Optional `metadata` (an object of JSON values), `datamodel`, `accepts`. No
  other key.
- **A block.** Required `id` and `type` (strings, `minLength: 1`) and
  `type_version` (integer, `minimum: 1` - the decoder reads it with no
  default, so an absent one is refused). Optional `config` (an object of JSON
  values) and `slots` (an object whose property names have `minLength: 1` and
  whose values are arrays of blocks, empty arrays included). No other key.
  `type` is any non-empty string: an unknown block type validates against
  this generic block shape, as it decodes (ADR-0001 decision 9).
- **A JSON value** (inside `metadata` and `config`, recursively): `null`, a
  boolean, an `integer`, a string, an array of JSON values, or an object of
  them. The no-floats rule of ADR-0001 decision 6 is `type: integer`, and it
  holds in `metadata` exactly as in `config`, because `defp check_metadata/1`
  (`validation.ex:99`) runs the same value check as `defp check_config/2`.
- **`datamodel`** - described in this file itself (Decision 5): an array of
  objects with a required `id`, a string matching `^[a-z][a-z0-9_]*$`;
  optional `expr` and `description`, strings with `minLength: 1` (an
  explicit `null` is refused, as `reject_explicit_null/4` refuses it); and
  no other key.
- **`accepts`** - an array of strings with `minLength: 1` and `uniqueItems:
  true`.

"Exactly" is judged on documents as the package decodes them. Draft-06 and
draft-07 define an integer as any number with a zero fractional part, so a
validator reading the bytes `1.0` - or any number spelled with a fraction or
an exponent whose value is whole - treats them as the integer `1`, while the
package decodes them as a float and refuses them - as `schema_version`, as
`revision`, as `type_version`, and inside `metadata` or `config`. Those
spellings are where a draft-07 validator reading raw bytes differs from the
package because of how the bytes are read rather than because of anything
JSON Schema cannot say; the encoder never writes them (ADR-0001 decision 8),
and in no case does the root refuse what the package accepts.

What JSON Schema cannot say stays with the code that says it today, and the
root does not pretend to it:

- key order, whitespace and the SHA-256 identity are the encoder's
  (`CanonicalJson.encode/1`, `Document.content_hash/1`); the decoder admits
  any key order and whitespace, and so does the root;
- block-id uniqueness across the tree and datamodel-id uniqueness within the
  key are `Validation`'s, so a document the root admits may still be
  refused by `from_json/1` for a repeated id;
- a slot's arity against its parent's config, and a slot name its type does
  not declare, are neither the root's nor decode's: they are the
  palette-aware findings of `StatifierBlocks.SlotValidation.validate/2`
  (`lib/statifier_blocks/slot_validation.ex:64`), which runs after a type is
  resolved.

Nothing in that list is a document the root refuses and the package admits.

**4. The core types get typed definitions that the root does not apply.**
The file carries, under `definitions/core`, one definition per `core.*`
block type in `Palette.core_types/0`: its config keys typed as its
`validate_config/1` requires them, and its slots named as its `slots/1`
declares them. The root never references them. Validation is registry-free,
so a typed per-type config at the root would refuse a document the package
accepts - a `core.wait` without `duration`, or any of the generator's core
blocks with arbitrary config (Context).

Each core definition stays open wherever `validate_config/1` and `Validation`
are open: a config key the type's `validate_config/1` ignores is admitted
(`additionalProperties` is not `false` on a core config), a value it does not
check is left untyped, and a slot name `slots/1` does not declare is still
admitted as a list of blocks, because `Validation` admits it and an
undeclared slot is `SlotValidation.validate/2`'s finding, not a decode
refusal. That openness is what makes Decision 6's invariant hold.

**5. The `datamodel` key is described here, with no reference to the
datamodel package's schema.** ADR-0001 11g says in as many words that the
block document's `datamodel` key and the host's datamodel document are two
different artifacts answering two different questions: one declares roots
that must exist at run time, the other describes a typed vocabulary. The
key's grammar is ADR-0001 11b's `{id, expr, description}` and is described
inline in this file. There is no `$ref` into `statifier_datamodel`'s schema:
a cross-package reference would make this file unresolvable without the
other package's file at a matching version, for a key that shares nothing
with that document but the word.

**6. `for_palette/1` generates a schema for a palette, and never refuses a
document the package admits and every block's `validate_config/1` accepts.**
`StatifierBlocks.Schema.for_palette/1` takes a `%StatifierBlocks.Palette{}`
and returns a draft-07 schema, as a map with string keys that `JSON.encode!/1`
serializes, whose block shape applies a definition per palette entry:

- **A core entry** - a name whose palette entry is the module
  `Palette.core_types/0` maps it to - takes its definition from the shipped
  file's `definitions/core`, verbatim.
- **Any other entry** - a host type, or a host module mounted under a `core.`
  name, which `Palette.core_types/0`'s documentation allows - takes a
  definition generated from its declared `config_schema/1` and `slots/1`,
  each asked about the config `Palette.new_block/2` (`palette.ex:690`) builds
  for that type - the `config_schema(%{})` defaults - and reached through
  `Palette.call/4` (`palette.ex:606`) so that a stateful `{module, state}`
  entry is read the way every other caller reads it. The generated definition
  names each declared field whose value lives at `config[key]` (a field with
  a `value_path` is not named) and each declared slot, with its label as
  `title` and its default as `default`, and constrains nothing the generic
  block shape does not: `config_schema/1` is a rendering hint
  (ADR-0002 decision 7) that the package never holds to `validate_config/1`,
  so a type constraint read from it could refuse a config the type accepts.
- **A name the palette does not carry** takes the generic block shape of
  Decision 3, as it decodes.

Each definition is applied with a draft-07 `if`/`then` keyed on the block's
`type`, over the generic block shape, so every block in the tree - the root
block and every slot's children - is judged by its own type's definition. A
palette with no entries answers a schema that admits exactly what the
shipped root admits.

The invariant, stated as the test that holds it: for `Palette.core()` and
for a palette carrying test-only host types, every document the package
admits, and in which every block whose type the palette carries answers
`:ok` from its `validate_config/1`, validates against `for_palette/1`'s
schema. The core definitions' openness (Decision 4) is what makes that hold for core
types; the generated definitions' constraining nothing past the generic shape
is what makes it hold for host types.

**7. The module, the file, the `$id`, and the package.**

- The file is `priv/schemas/block-document.schema.json`, and `priv/schemas`
  joins the Hex `files:` list in `defp package/0` (`mix.exs:104`), which
  today ships `lib/statifier_blocks`, `lib/statifier_blocks.ex`, `assets` and
  the top-level files only.
- Its `$id` is `urn:statifier-blocks:block-document:1`, keyed on the
  document's `schema_version`, never on the package version: a patch or
  minor release that changes no byte of ADR-0001's envelope ships the same
  `$id`. The URN resolves nowhere by design; a validator loads the file the
  package carries.
- The public reader is `StatifierBlocks.Schema`:
  - `Schema.path/0` - the absolute path of the shipped file, through the
    application's `priv` directory;
  - `Schema.json/0` - the file's contents, byte for byte, as a binary;
  - `Schema.for_palette/1` - Decision 6.

  None of the three consults a validator, a network or a clock. No existing
  function changes what it answers.

**8. When the schema changes.** An amendment to ADR-0001 that changes bytes
bumps `schema_version` (ADR-0001 decision 7) and ships a second file with its
own `$id` beside this one; the record taking that bump names the second
file and which of the two `path/0` and `json/0` answer. A record that adds an
envelope key without a bump, as ADR-0001 11e and ADR-0014 decision 2 each
did, edits this file in place under the same `$id`, in the same request as
the decoder change. A validator holding the older copy then refuses the new
key, which is 11e's old-reader property carried into the schema: it refuses
loudly rather than admitting a key it cannot describe.

## Consequences

- A host in any language can check a stored or outbound document against a
  file the package ships and tests, and gets the same verdict `from_json/1`
  gives on every point JSON Schema can express. What it cannot express is
  named in the record, so no one reads a schema pass as an identity or
  uniqueness check.
- The file is a second statement of the grammar, and the drift test is the
  price of that: every change to `Decode` or `Validation` touches the file
  and its cases in the same request.
- The shipped root stays as permissive as the package on block types.
  A host wanting type-level checks asks for `for_palette/1`; a host wanting
  the core types' own definitions reads them under `definitions/core`
  without either the root or the package applying them.
- For host types, `for_palette/1` adds names, titles and defaults and no
  refusals. A host wanting stricter checks on its own types writes them in
  its own schema over the generated one; this record does not add a way for
  a block type to declare a JSON Schema of its own.
- `ex_json_schema` enters `mix.lock` as a test-only dependency; no runtime
  dependency is added and no floor moves.
- The block document's `datamodel` key and the datamodel package's document
  can version independently: nothing in this file changes when that package's
  schema does.
