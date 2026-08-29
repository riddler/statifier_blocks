### Changed

- A `core.wait` mints its delayed send under the reserved `send` role, so a
  chart containing one now compiles to `s_<block id>__send` where it compiled
  to `s_<block id>__timer`.

### Fixed

- Leaving the scope around a `core.wait` cancels the wait's delayed timer, so
  a wait abandoned before its duration elapses no longer leaves an armed timer
  behind in a durable host.
