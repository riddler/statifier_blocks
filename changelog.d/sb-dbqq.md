### Changed

- The inspector's Findings tab reads the whole document when nothing is
  selected: the count beside the tab is the document's findings number - the
  same one the drawer's strip and `StatifierBlocks.Editor.findings_count/3`
  report - and the panel lists those findings grouped by block, each row
  selecting its block. Findings anchored to a block the document no longer
  holds get an `Unanchored` group of their own, since they are inside the
  count. With a block selected the tab is that block's findings, unchanged.
  A host styling the panel has three new classes: `.sb-inspector__groups`,
  `.sb-inspector__group` (with `data-block-id` and `data-unanchored`) and
  `.sb-inspector__group-title`, plus `.sb-inspector__group-row` on the rows.

### Added

- `StatifierBlocks.Shell.findings_groups/3` groups a document's findings by
  the block each is anchored to, unanchored ones last, without dropping any -
  the grouping behind that panel, and headless like the rest of `Shell`.
