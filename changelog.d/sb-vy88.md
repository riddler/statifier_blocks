### Changed

- `StatifierBlocks.ViewModel.overlay_findings/2` enforces the findings shape
  `validate_config/1` declares: a block type answering with anything but a list
  of `{key, message}` string pairs is refused with an error naming that type,
  rather than failing a clause head that named the view model.
