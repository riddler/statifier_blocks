### Added

- `StatifierBlocks.Plan.expressible?/2` checks a whole document against a
  palette before it reaches the editor: `:ok` when every block's type resolves,
  every block sits in a slot the editor would let an author drop it into
  (declared, with room, admitting its kinds), and every empty required slot is
  one the palette can fill; otherwise `{:no, reasons}` with one reason per
  refusal naming the rule and the block. A read type mismatch is not a reason,
  since the editor flags it rather than refusing the drop. An optional third
  argument is the assignability context, defaulting to `%{}` as
  `Edit.Targets.admits_at?/5` defaults it.
