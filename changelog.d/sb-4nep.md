### Added

- A palette entry can be dragged onto a gap on the canvas to insert a block of
  that type there. The slots that accept the dragged type highlight as soon as
  the drag starts, exactly as they do when a card is dragged, and the drop
  produces the same insert a "+" and a pick produce.

### Fixed

- A slot that refuses the block being dragged no longer accepts a drop when it
  sits inside a slot that accepts it. The gaps in the refused slot were live
  targets, and dropping on one put the block in the slot that had said no.
