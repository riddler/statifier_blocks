### Added

- A slot's header shows the condition it is subject to: the expression source,
  read-only, in a monospaced chip under the slot's name, clipped to one line
  with the whole of it in the chip's `title`. A branch's arms on the canvas now
  say what picks between them instead of only naming themselves.
- `StatifierBlocks.ViewModel.Slot.condition` carries that source. It is derived
  from the container's own `:expression` config field keyed by the slot's name,
  read through the field's declared `value_path`, so a host block type that
  guards a slot the way `core.branch` guards an arm gets the same chip without
  the editor learning either type's name.

### Changed

- Slot labels are small, uppercased and letter-spaced - the treatment the fan
  pill and the join marker already carry for chrome that labels a structure.
  The transform is presentation only: the string a block type declares for a
  slot is unchanged, and every other reader still sees it as written.
- Concurrent lanes carry a rule in the block accent across the top of each
  lane's header, drawn off `data-arrangement="lanes"`. The pill above says
  `ALL OF` once; the rule is what carries that distinction down a document
  taller than one screen, where a set of lanes and a set of branch arms
  otherwise look alike.
- An interrupt rail's dashed edge and its heading take the colour the connector
  layer already draws an interrupt edge in, so the rail and the edge leaving it
  read as one thing.
