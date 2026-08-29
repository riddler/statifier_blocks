### Changed

- The editor's stylesheet carries a scoped reset, and every selector in it
  matches the container through `:where(.sb-editor)` so a component rule
  always wins (ADR-0005 amendment 14b).
- `--sb-color-scheme` is declared and read as `color-scheme` on the editor's
  own container, so the parts of a control the browser paints - a `<select>`'s
  drop-down, the scrollbars, the caret - follow the theme (14a).
- The `--sb-*` surface gains the space, type and shape scales, a third text
  step, a strong border, status tints, the drag seam's drag-time height, and
  the canvas sizing constants that were literals in rules.
- `--sb-drop-no-opacity` is **retired**. A drag now marks the slots that
  accept the block and leaves the rest alone rather than dimming them; the
  disabled-control opacity it doubled as is `--sb-disabled-opacity`.

### Added

- A theme audit test over the stylesheet, failing in both directions: a
  `var(--sb-*)` with no declaration, and a declared token no rule reads (14e).
