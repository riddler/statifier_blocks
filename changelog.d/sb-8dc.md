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
- A `:secondary` and a `:failure` slot are both placed as attached rails,
  and a container declaring either is drawn as a boundary box - the rail
  partition, not the `:secondary` partition (amendments 10c and 10h).
- `--sb-drop-no-opacity` is **retired**. A drag now marks the slots that
  accept the block and leaves the rest alone rather than dimming them; the
  disabled-control opacity it doubled as is `--sb-disabled-opacity`.

### Added

- A block type may declare `accent_token`, the NAME of a `--sb-*` property,
  and the editor stamps it on that type's cards and palette rows. Two rules
  in the stylesheet read it; no rule and no module names a block type
  (ADR-0005 amendment 14d, consumption side).
- `StatifierBlocks.Finding.severity_class/1`, and `:info` as a third
  severity for advisory findings (decision 11, amended 2026-08-29). Nothing
  emits one yet; only `:lint` may.
- A form whose config the gate has not accepted names the fields that are
  outstanding, says why nothing is stored, and offers "Discard edits". A
  draft was never a command, so it cannot be undone - it can only be thrown
  away, and that gesture had nowhere to live.
- `:expression` and `:duration` controls carry a placeholder. A bare
  `:string` still carries none: there is nothing a type that wide can
  suggest.
- A theme audit test over the stylesheet, failing in both directions: a
  `var(--sb-*)` with no declaration, and a declared token no rule reads (14e).
