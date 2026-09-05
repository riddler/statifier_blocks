### Added

- `{:path, opts}` is the eighth value in a block type's closed field-type set.
  A field declared with it holds a path into the host's datamodel, and the
  editor reaches its control by the type alone: a text input bound to a
  `<datalist>` of the declared paths, and the `:info` advisory for a path the
  datamodel does not declare, anchored on the field. `opts` carries no defined
  key today, so a declaration writes `type: {:path, %{}}`. It suggests and
  never constrains - free text stays valid and `validate_config/1` remains the
  only authority on what a value may be.

### Changed

- `core.subchart`'s `assign_to` is declared `{:path, %{}}` rather than
  `:string`, so it offers the declared datamodel paths as candidates and gets
  the undeclared-path advisory. What it accepts is unchanged - a bare
  lowercase identifier, which is a one-segment path - and it compiles to the
  same `<assign location=...>` it always did.
- `StatifierBlocks.BlockType.datamodel_path?/1` answers `true` for a
  `{:path, opts}` field by construction. The `datamodel_path?: true` key is
  not withdrawn: it keeps its meaning, its control and its advisory, a
  declaration carrying both spellings says one thing twice rather than
  contradicting itself, and every declaration written before the type behaves
  exactly as it did.
