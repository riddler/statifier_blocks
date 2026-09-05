### Added

- The drawer's tab strip answers the WAI-ARIA tablist arrow keys. With the
  strip's one Tab stop focused, Left and Right move one tab and wrap, Home and
  End go to the ends, and the tab moved to is both selected and focused - so
  a tab past the clipped edge at the narrow breakpoint is reachable from the
  keyboard and is scrolled into view when it is reached. Host-contributed tabs
  are walked alongside the package's own, in the order the strip draws them.
  The movement is server-side and adds no JavaScript hook: the strip reports
  the key through `phx-keydown` and the editor picks the neighbour out of the
  same tab list a pointer pick reads.
