### Added

- `StatifierBlocks.Composite.io/2` and `outcomes/2` answer a composite block's
  io and outcomes with every member resolved through a palette you supply, so a
  composite rooted at a host block type is exact wherever a palette is in hand.
- A composite derives `summary/1`: one card chip per declared param that is not
  `hidden?: true`, drawn as `"<label>: <value>"` and overridable.
- `StatifierBlocks.BlockType.outcome_names/1` answers the names in an outcome
  list a caller already holds.

### Changed

- `StatifierBlocks.Assignability.produces/4` and the editor's `core.on_event`
  event candidates read a composite's io and outcomes through the palette they
  already hold rather than through the core-only fallback. The
  `c:StatifierBlocks.BlockType.io/1` and `outcomes/1` callbacks are unchanged
  and keep that fallback.
