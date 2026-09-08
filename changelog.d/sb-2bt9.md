### Fixed

- The assigns map an `:expression` field hands a host's `expression_component`
  carries a `debounce` key - the field's own `debounce` value, and `nil` when
  the caller named none - so an override can rate-limit the way every other
  control in the same form does instead of posting per keystroke. Overrides
  that ignore the key are unchanged.
