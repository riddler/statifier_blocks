### Fixed

- A document whose blocks were built before blocks had a note, and that a host kept as a stored Erlang term rather than as JSON, now also goes through the note edit command `{:update_note, id, note}` (its inverse carrying the empty note), `StatifierBlocks.Map.Info`'s descriptions and the editor's note field as a note-free document, instead of raising `KeyError` or `CaseClauseError`.
