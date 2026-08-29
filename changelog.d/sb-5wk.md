### Added

- `core.send` sends an event, now or after a delay.

### Changed

- `predicator` is now a direct dependency (`~> 9.0`), because
  `StatifierBlocks.Core.Duration` calls `Predicator.Duration.parse/1`. It
  already resolved transitively through `statifier`, so the resolved version
  does not move; naming it records the call.
