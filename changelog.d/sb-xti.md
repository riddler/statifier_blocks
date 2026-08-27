### Added

- `StatifierBlocks.Document.validate/1` checks a block document's structure: schema version, envelope shape, per-block shape, and document-wide id uniqueness.
- `StatifierBlocks.Document.to_json/1` encodes a document to ADR-0001's deterministic canonical JSON: sorted object keys, no insignificant whitespace, empty `slots`/`config`/`metadata` omitted, no floats.
- `StatifierBlocks.Document.content_hash/1` returns a `"sha256:" <> hex` document identity over `to_json/1`'s canonical bytes.
- `StatifierBlocks.Document.from_json/1` decodes canonical JSON back into a document, structurally and registry-free: unknown block types decode successfully, and every refusal is one of ADR-0001's typed error arms.
