### Added

- The palette and the inspector render as framed panes with a header row. The
  palette's names the pane and carries a chevron that folds it to a rail,
  giving its width back to the canvas; the inspector's names the pane and
  states its subject on the right - the selected block type's label, or
  `no selection`.
- `--sb-palette-collapsed-width`, the width the folded palette narrows to
  (tier 2, default `2.25rem`).

### Changed

- `StatifierBlocks.Editor.PaletteBrowser` takes a `collapsed` attribute, and
  the editor answers a `palette-collapse` event with one boolean and no hook,
  in the same shape as the shell amendment's other gestures. The fold is not
  reset when the host swaps the open document: it is a preference about the
  pane rather than state about the document.
- The narrow arrangement (ADR-0005 ruling 7A) is unchanged. Below a container
  width of 780 the strip and its sheet are still the palette's whole chrome
  and the pane header stands down, so the fold has nothing to do there.
