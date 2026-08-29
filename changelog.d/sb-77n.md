### Added

- A block type may declare `slot_outcome_key` in its palette entry, naming the
  config key the blocks in one of its slots carry their outcome under, so a
  renderer can route an interrupt rule's escape without branching on a type
  name; the declaration reaches the view model as `Slot.outcome_key` and the
  resolved value as `Node.outcome`.
- `StatifierBlocks.BlockType.slot_outcome_key/2` and
  `StatifierBlocks.BlockType.outcome_name/2` read that declaration totally: a
  malformed declaration or value is refused rather than repaired, and reads as
  no declared outcome.
