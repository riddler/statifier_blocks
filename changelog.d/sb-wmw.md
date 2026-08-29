### Added

- A `core.invoke` block type: it names an invoke type for the host to run,
  sends datamodel values along as `<param>`s, writes the result where its
  `assign_to` names, and takes an optional `on_error` subtree entered on a
  permanent invoke failure.
- `StatifierBlocks.Compiler.Context.outcome_id/2` and `outcome_event/2`, for a
  block type with more than one way to finish: one `<final>` per outcome, and
  the `done.outcome.<state id>.<outcome>` event a parent wires on.

### Changed

- `slot_style` admits a third value, `:failure`, for a slot whose children
  are an in-band continuation taken on a bad outcome; `core.invoke` declares
  it for `on_error`.

- The role namespace beginning `o_` is reserved for outcome finals;
  `Context.role_id/2` now refuses such a role with a `:reserved_role` finding.
