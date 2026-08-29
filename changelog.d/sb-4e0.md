### Added

- `Compiler.compile/3` takes a `:datamodel` option and refuses a document that reads a path the host declared `sensitive?: true` into a position the chart evaluates against the datamodel; with no datamodel supplied nothing is produced.
