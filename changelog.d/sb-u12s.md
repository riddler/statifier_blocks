### Changed

- The editor's config form draws `StatifierBlocks.ViewModel.shown_fields/1`'s
  list, so a host surface drawing its own form reads the same filter the
  package's own form reads rather than a second copy of it.
