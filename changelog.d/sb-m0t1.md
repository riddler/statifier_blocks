### Added

- `core.await` joins the core vocabulary: an in-flow leaf that holds until a
  named event arrives, with an optional deadline. It is valid wherever
  `core.wait` is, takes `event` (required) and `timeout` (an optional
  duration), and declares two outcomes, `received` and `timed_out`, so a
  parent can route the two ways it can end. A configured `timeout` arms a
  cancel-scoped delayed send, so leaving the await early - because the event
  arrived, because an interrupt fired, because a group was abandoned - leaves
  no timer behind. Both outcomes are declared whether or not a deadline is
  stored; with no `timeout`, no timer is armed and no `timed_out` final is
  emitted.
