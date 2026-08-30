### Added

- Two theming tokens for the editor's nesting bands, `--sb-band-even` and
  `--sb-band-odd` (tier 2). Both default to a surface the theme already
  carries, so a host that restates `--sb-bg` and `--sb-bg-sunken` bands in its
  own palette without setting either one.

### Changed

- Every slot on the canvas carries `data-sb-depth`, its root-relative nesting
  depth, and the stylesheet paints a full-width band per nesting level,
  alternating by the depth's parity. Depth 0 is deliberately unbanded, so the
  canvas keeps its own dotted ground.
- The interrupt-rules rail has a ground of its own, in the warning family its
  dashed edge already uses.
