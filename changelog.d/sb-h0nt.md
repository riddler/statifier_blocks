### Added

- `StatifierBlocks.Editor` takes a `debounce` assign and passes it to the
  inspector's config form, so a host that mounts the editor can say how often
  its controls post without composing `ConfigForm.config_form/1` itself.
