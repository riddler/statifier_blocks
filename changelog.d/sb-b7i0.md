### Fixed

- An empty slot on a read-only editor mount now draws a non-interactive
  placeholder. The mark that says "nothing is here yet" was styled on the gap's
  "+" button, which a read-only mount does not draw, so an empty arm rendered as
  a slot header and nothing else.
