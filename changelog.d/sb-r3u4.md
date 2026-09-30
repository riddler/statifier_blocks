### Changed

- A host's `:phrase` words for its event names (`StatifierBlocks.Map.graph/2` and the Map's description region) now reword a name only in event position - after "Send" or a delayed send's "send", after "Wait for", or after a rule's "When" - and leave a known name anywhere else as written, such as a path a step sets, a name after a send or wait word glued to a dotted prefix, or the event a timer edge's line names before "reaches"; a host that relied on a name reading as words elsewhere now sees the name.
