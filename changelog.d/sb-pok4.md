### Added

- `StatifierBlocks.Connectors.slots_anchor/1`, the anchor key for a
  container's body box. The editor stamps it on the element holding a
  container's slots, and an interrupt channel is now offset from that box
  rather than from the container's whole node box.

### Fixed

- Connector arrowheads keep one size at every stroke width and land their tip
  on the endpoint, rather than being scaled by the stroke of the path that
  references them and overshooting the card they point at.
- A flow edge whose head was measured above its tail is drawn level instead of
  ascending, so no arrowhead points back at the block the flow just left.
- An interrupt edge clears the container it exits instead of turning down
  inside it. A container is now as wide as what it holds rather than as wide
  as the box around it, so the box the routing is measured from means what it
  encloses.
- A gap's insertion marker masks the flow line it sits on, and its glyph stays
  legible when the canvas is zoomed out. The dashed placeholder ring stays on
  empty slots only.
