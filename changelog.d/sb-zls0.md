### Added

- The block document's JSON Schema (draft-07) ships in the package at `priv/schemas/block-document.schema.json`, with `StatifierBlocks.Schema.path/0` and `json/0` to read it: its root never refuses a document `StatifierBlocks.Document.from_json/1` accepts, and typed `config` and `slots` definitions for the `core.*` types sit under its `definitions/core`, which the root does not apply.
