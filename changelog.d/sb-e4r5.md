### Changed

- The editor's `fit` attr is now spent once per open document rather than once
  per editor: a document the host swaps in is armed from the attr passed in
  that same update and fitted by the next measurement, exactly as at mount. A
  host re-render carrying the document already open still never re-fits, and
  `:manual` or an absent attr still arms nothing.
