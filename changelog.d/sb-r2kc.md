### Changed

- The Map draws the clock mark on a timed wait (`core.wait`), as it does on
  a delayed send: the clock says time passes, and the hourglass on an
  await says a step waits for an event. The mark is a mark only; a wait
  still takes no part in a timer edge. The paragraph on how to read the
  map, in the idle description, says so.
