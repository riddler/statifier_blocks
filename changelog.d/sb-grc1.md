### Added

- `StatifierBlocks.Runtime.Marks.from_trace/2` turns a statifier-ui trace read model and a provenance map into the run marks the editor canvas already accepts, so a host observing a run marks the blocks a configuration is inside without naming them itself.

### Changed

- `statifier_ui` is now an optional dependency at `~> 0.9`, the release that added the state-id reads `from_trace/2` composes; hosts on `0.8` upgrade the package to use the new module and are otherwise unaffected.
