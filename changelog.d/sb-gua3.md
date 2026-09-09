### Changed

- `StatifierBlocks.Composite.expand/2` blames a member carrying more than one
  param's value on the first param in declaration order, instead of answering
  `nil` for it; a finding re-anchored onto the composite now names a field to
  open. A member carrying no param value still answers `nil`.
