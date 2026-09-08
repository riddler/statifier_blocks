### Changed

- The summary-chip presentation cap is 32 characters, up from 24. Every
  message that quotes the cap follows the number; `--sb-card-width` is
  unchanged, because the cap is a legibility number rather than a
  measurement of the card.
- A summary chip past the cap is now drawn clipped, with an ellipsis in its
  last position and its full text on the chip's `title`, instead of being
  dropped. A blank, multiline or non-string chip is still refused. The
  `:lint` finding that reports the length stays, and its sentence now ends
  "so it is drawn clipped".
- `StatifierBlocks.BlockType.badge/1` is unaffected: an over-long badge is
  still dropped rather than clipped.
- A presentation-cap `:lint` finding no longer draws on the card face; it is
  read in the drawer's Findings tab, and still counts toward a card's
  findings rollup. Every other finding a card carries draws where it did.
- A finding that does draw on a card face is laid out inside the card's own
  box. On a container it previously drew full-width between the card and the
  slot label below it, where it read as belonging to the slot. A host
  stylesheet targeting `.sb-node > .sb-finding` should target
  `.sb-node__chrome > .sb-finding` instead.

### Added

- `StatifierBlocks.BlockType.summary_refusal_message?/1` says whether a
  message is one `summary_refusal_message/4` wrote, which is how a surface
  tells a presentation-cap diagnostic from every other `:lint` finding.
