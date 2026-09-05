### Fixed

- A document saved before the duration pivot opens clean instead of showing a
  refusal on every timer: `core.wait` and `core.send` are at `type_version` 2
  and rewrite a stored duration written in the older spelling into the one the
  field reads. The rewrite happens in memory as the block resolves and nothing
  is written back, so persisting it stays the host's decision.
