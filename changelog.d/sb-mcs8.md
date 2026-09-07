### Added

- `StatifierBlocks.Edit.Session` is the commit funnel as a value: `commit/2`,
  `change_config/3`, `step/2`, `update_list/4` and `apply_gesture/2` over a
  document, a history and the drafts, with no socket in them. Each answers
  `{:ok, session}` or `{:error, session}`, and the tag says whether the
  document moved - which is when a host stores or notifies. Holding a refused
  config as that block's draft, and dropping every draft across an undo, are
  the package's decisions rather than each surface's.
- `StatifierBlocks.Edit.Targets.accepted_types/4` answers which of a palette's
  block types fit a `{parent_id, slot}` target, and `probe/2` builds the block
  it asks about: `Palette.new_block/2`'s, with the type's `palette_entry/0`
  `default_config` merged over it. A surface filtering a palette without that
  merge answers differently, for any type whose read depends on its config,
  than the canvas's own drag stamp does.
- `StatifierBlocks.Assignability.context/1` builds the assignability context
  from a host's `:datamodel`, so the drop check, the environment walk and a
  datamodel view are handed the same one.
