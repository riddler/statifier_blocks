### Added

- `ViewModel.order_palette_groups/2` puts palette groups in a reading order a
  caller names, keeping the groups it did not name after them by name.

### Changed

- The palette column draws its groups in the order a profile's
  `palette_groups` list gives them, rather than by name; a mount that names no
  list draws them by name as before.
