### Fixed

- `StatifierBlocks.Describe.render/2` reads a timer or interrupt edge whose event is blank as "its event", as it already did for an edge with no event, instead of leaving a gap in the line.
