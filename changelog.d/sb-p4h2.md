### Changed

- `StatifierBlocks.Map.graph/2` sets a wrapped arm entry apart on a branch's header: every line after the entry's first now starts with no-break spaces as wide as the entry's number (`"1. "`, `"10. "`), so the map draws it indented under the arm's label and a wrapped condition no longer reads as an entry of its own. An entry that fits on one line, and every other box's lines, are unchanged. A host that reads a branch node's `lines` finds the indent at the start of each continuation line.
