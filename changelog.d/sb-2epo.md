### Changed

- The config form's fields are dressed the way the palette's search box always
  was - a token-built box with a border, a radius and the pane's own fill -
  instead of being left to whatever the host's browser paints a bare `<input>`
  or `<select>` as. The two are now one rule rather than two, so a host
  retuning `--sb-border`, `--sb-radius-sm` or `--sb-bg` moves every control in
  the editor together.
- Placeholder text in those fields takes `--sb-fg-subtle`, and a disabled field
  is muted with `--sb-disabled-opacity`, which is what a disabled `sb-button`
  has always used. Boolean fields, which render a checkbox, are excluded from
  the box by selector and are unchanged.
