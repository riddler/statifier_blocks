### Changed

- A `{:list, {:path, opts}}` field's rows now get what a `{:path, opts}` field gets: `StatifierBlocks.Datamodel.findings/4` returns the `:info` undeclared-path advisory for each undeclared row, anchored on the list field's key, and the editor binds each row's input to a `<datalist>` of `path_candidates`; `BlockType.datamodel_path?/1` still answers false for a list.
