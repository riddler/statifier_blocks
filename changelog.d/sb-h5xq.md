### Added

- `StatifierBlocks.Edit.Targets.admits_at?/5` answers whether one block type
  would be accepted at one `{parent_id, slot}` target, with one probe and one
  `StatifierBlocks.Assignability.check/5` at the slot's append gap instead of
  the whole-document walk `accepted_types/4` runs per candidate - the call a
  "+" chooser at a gap should make.
- `StatifierBlocks.Edit.Targets.accepted_types_at/5` asks that question over a
  candidate list, defaulting to the palette's own types, so a surface with a
  shortlist pays for the shortlist. `accepted_types/4` is unchanged and stays
  the sweep; the module's moduledoc says which of the three to call.
