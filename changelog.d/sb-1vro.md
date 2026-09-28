### Added

- `StatifierBlocks.Describe.outline/3` answers a new edge kind, `:timer`, from a delayed `core.send` to every `core.on_event` and `core.await` in the document that names its event, after every other edge and carrying the delay in `StatifierBlocks.Describe.Edge`'s new `delay` field; `render/2` writes it as `In 24 hours, registration.deadline reaches ...`, and a phrasing module rewords it through the new optional `StatifierBlocks.Describe.Phrasing.timer/2` callback. A document with no delayed send describes exactly as before.
