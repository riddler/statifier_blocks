### Added

- `StatifierBlocks.Palette.from_modules/2`, the registration API a host uses
  to contribute its own block types: an ordered, explicit list of
  `{type_name, module}` registrations, with `core: true` to sit on top of
  the `core.*` vocabulary. Later entries win. It is still a value - no
  global registry, no application-configuration lookup, and no discovery
  pass.
- A palette entry may declare `badge`, a short chip for the card header, and
  `join_label`, a one-argument function of the block's config phrasing the
  join marker under a side-by-side arrangement (ADR-0002 amendment B).
  `StatifierBlocks.BlockType.badge/1` and `join_label/2` read them.
- Both readers are total and **refuse rather than repair**: a chip that is
  blank, carries a newline or tab, or runs past 24 characters is dropped,
  not clipped, and a `join_label` that raises degrades to the editor's own
  word rather than taking the canvas down.
- `accent_token`, `badge` and `join_label` are admitted keys of
  `t:StatifierBlocks.BlockType.palette_entry/0`.
- The README carries a worked host example - a `myapp.risk_hold` block type
  registered beside the core vocabulary, with a badge and an accent token -
  and it is executed on every build rather than trusted.
