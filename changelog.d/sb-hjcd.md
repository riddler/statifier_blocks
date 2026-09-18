### Changed

- The editor view model reads a `core.on_event` handler that names the
  outcome it finishes with under `finish_as` as that name; a handler naming
  none still reads as its `outcome` select value.
