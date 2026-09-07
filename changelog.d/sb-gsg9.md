### Added

- The editor's Datamodel tab draws a **Values** column beside each declared
  path: the `one_of` enumeration the ADR-0006 document declares there, cut at
  eight values with the remainder counted ("+3 more"). It reports the
  declaration and not a host's `value_candidates` override, so a reader can
  answer "where did this picklist come from" from the table rather than by
  opening a condition. A path that declares no enumeration draws an empty
  cell.
