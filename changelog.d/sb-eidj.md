### Changed

- The Map hook now holds the SVG wide enough for a timer edge between two steps of one column, the run it draws past their right sides and its delay, when the drawing has no key; before, only a key beside the drawing widened the SVG for it.
- `StatifierBlocks.Map.caption/1` now answers the whole first sentence of the type's explanation for a branch and the two group types, never cut to one line and ended in "..." as a group's was; a host that drew `caption/1` itself should expect the longer text.
- A group's rules column in `StatifierBlocks.Map.graph/2` now carries `caption` "Rules: watch the steps while they run" in place of the group's sentence, and a new `explanation_lines` field, that sentence wrapped to a box's line; the Map hook draws the caption under the column's label and the lines under it, and the column grows to hold them.
