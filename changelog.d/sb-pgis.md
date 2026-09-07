### Added

- `ConfigForm.config_form/1` and `Field.field/1` take a `debounce` attr,
  written as `phx-debounce` onto every control the form draws, so a host
  that persists what the form posts can ask for something slower than one
  write per keystroke. It takes what LiveView takes - milliseconds, or
  `:blur` - and defaults to no attribute, which is what every existing
  caller already renders. Controls drawn by an `expression_component`
  override are that component's own and are not covered.
