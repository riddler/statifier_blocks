### Added

- `core.on_event` takes an optional `finish_as` key naming the outcome the
  handler finishes with when it abandons its group, so an enclosing composite
  can declare that outcome and route it through its derived `on_<name>` slot.
