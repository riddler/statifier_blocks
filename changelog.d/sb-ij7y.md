### Fixed

- A composite's expansion is compiled at each member type's **current**
  version, so a config value a subtree writes reaches the chart as written
  rather than through that type's `migrate_config/2`. A subtree naming
  `core.send` or `core.wait` - the two core types past version 1 - used to
  have its `delay` or `duration` read as a stored value at version 1 and
  silently rewritten; such a value is now the author's to write in the
  accepted spelling, and one that is not is refused by name. A block the
  document stores is untouched: it still migrates.
