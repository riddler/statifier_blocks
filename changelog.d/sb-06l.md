### Added

- The inspector's Config tab is two labelled sections. **Block** states the
  selected block's type label, its id and the slot it sits in, and renders with
  nothing selected too - three rows in the same place, reading as a dash.
- `StatifierBlocks.Shell.slot_label/2` answers which slot a block sits in, by
  the slot's label rather than its name, with `"root"` for the document root.

### Changed

- **Configuration**'s empty state is a box standing where the form stands,
  saying what selecting a block would let the author do, rather than the
  one-line sentence the other tabs use for having nothing to read.
- A required field is marked with the word `Required` beside its label instead
  of an asterisk on the end of it - the asterisk needed a legend the editor
  does not have and is read aloud as "star".
- The Findings tab's count is a pill in the error hue rather than a tinted
  rectangle, and it is still the block's own findings, never the subtree's.
