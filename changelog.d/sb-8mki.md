### Fixed

- A block type that declares a datamodel-path field without a `default:` key is
  now refused at compile, as a `:config` finding naming the field, instead of
  raising a `FunctionClauseError` out of the view model when something rendered
  the block. The view model reads a declaration's `default:` permissively, so a
  field declared without one renders with no default rather than crashing the
  build.
