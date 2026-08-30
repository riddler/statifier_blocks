### Changed

- The palette's search field is drawn by the package - a border, a surface, padding and a radius, all from `--sb-*` tokens - rather than left to whatever box the host's browser paints inside the pane.
- A gap's "+" wears the editor's button chrome at rest, so an insertion point reads as a control without being hovered first. Its hover, armed and drag states are unchanged.

### Removed

- The canvas toolbar's "Cancel insert" button. Leaving an insert is the palette's Cancel, beside the line that names the slot the next pick fills, or Escape.
