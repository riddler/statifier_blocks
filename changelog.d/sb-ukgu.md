### Added

- `StatifierBlocks.Editor.findings_count/3` returns the number of findings the
  editor's Findings tab reports for a document, from the same `document`,
  `palette`, `findings` and `datamodel` a host already passes the component, so
  a host header and the drawer cannot show two different numbers.
