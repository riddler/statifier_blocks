### Added

- `StatifierBlocks.Editor.Icons`, a default icon set the editor uses when the
  host passes no `icon` component. Inline SVG for the eleven names the core
  block types declare, with no font, no CDN and nothing to register in a
  host's asset pipeline. Every glyph paints with `currentColor` and fills its
  tile, so `--sb-block-accent` and `--sb-block-accent-tint` still decide the
  colour and a per-block-type `accent_token` still moves a type's tile with
  its stripe.
- Palette entries render their icon. The `icon` assign the editor passes the
  palette browser was declared and never rendered, so no host could put an
  icon on a palette row; a type now looks the same in the palette as on the
  card the pick produces.

### Changed

- An entry that declares no icon renders no tile, rather than an empty one,
  and a host's `icon` component is never called with a `nil` name.
- An icon name the shipped set does not have renders a neutral mark with the
  name in `data-icon`.

### Fixed

- The editor no longer renders a `U+25A1` white square in every icon tile when
  the host passes no `icon`. Passing one still overrides every tile, on the
  canvas cards and the palette rows alike.
