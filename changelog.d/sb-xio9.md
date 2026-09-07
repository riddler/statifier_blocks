### Added

- `use StatifierBlocks.Composite` declares a block type from params plus a
  pure `subtree/1`, deriving `config_schema/1`, `slots/1`, `io/1`,
  `outcomes/1`, `current_version/0`, `sentence/1`, `palette_entry/0` and a
  raising `emit/2`, and leaving only `sentence/1`, `palette_entry/0` and
  `validate_config/1` overridable.
- `StatifierBlocks.Composite.expand/2` answers the blocks a composite stands
  for, with ids minted deterministically from the composite block's own id,
  together with the param each expanded block is blamed on.
- A composite's declaration derives a `StatifierBlocks.Recipe` at
  `<Module>.Recipe` whose `insert/2` puts down one composite block.
- `StatifierBlocks.Environment.read_signatures/3` and `write_signatures/3`
  answer a composite with the union of its expansion's reads and writes, taken
  at the composite's one position in the document.

### Changed

- `nil` is refused as the `default:` of a `hidden?: true` field for every
  field type, not only `{:type_expr, opts}`.
