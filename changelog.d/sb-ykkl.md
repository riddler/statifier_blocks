### Added

- `StatifierBlocks.Editor.ConfigForm.config_form/1` takes an `event` attr,
  defaulting to `"config-change"`, which is written to both `phx-change` and
  `phx-submit`, so a host can draw one block's fields under its own
  `handle_event/3` instead of hand-writing the field pair. The block the
  params are about still arrives as the hidden `block-id` input the form
  already posted.

### Changed

- `config_form/1`'s `target` attr is optional and defaults to `nil`, which
  renders no `phx-target` anywhere - the case of a host whose form posts to
  the LiveView it is mounted in. Every present caller passes a target and is
  unchanged.
