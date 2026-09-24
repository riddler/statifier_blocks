### Added

- `StatifierBlocks.Plan.expressible?/2` checks a whole document against a
  palette before it reaches the editor: `:ok` when every block sits where the
  editor would admit it and every empty required slot is one the palette can
  fill, otherwise `{:no, reasons}` with one reason per refusal naming the rule
  and the block. An optional third argument is the assignability context,
  defaulting to `%{}` as `Edit.Targets.admits_at?/5` defaults it.
