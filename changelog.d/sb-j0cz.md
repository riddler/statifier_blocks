### Changed

- A `core.on_event` capture pair whose source is absent from the event payload
  no longer writes `:undefined`; the destination is left unwritten, so "not
  answered" and "answered with nothing" are different values and a reader tests
  a captured path by asking whether it is there. A document that captures by a
  path compiles to a different chart - each such pair's `<assign>` is now
  wrapped in an `<if>` that tests the path - so recompile stored documents; a
  handler that captures nothing, and a pair whose source is a literal, compile
  byte-identically. A reader that tested a captured path for `:undefined`
  should test it for presence instead.
