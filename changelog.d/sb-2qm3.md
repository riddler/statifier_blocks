### Added

- `StatifierBlocks.Editor.Field.field/1` takes a `variant` attribute
  (`:block`, the default and byte-identical to what it rendered before, or
  `:inline`), so a host placing one field inside a sentence of its own gets
  the same control, the same posted params and a label that is off the screen
  but still announced, without the editor gaining a layout mode.
