### Added

- `StatifierBlocks.Composite.Collapse.propose/3` reads a selected arrangement back as the `Composite.Data` declaration that stands for it, without naming it - naming the type stays the host's act.
- `StatifierBlocks.Composite.Collapse.replacement/4` answers the compound that swaps an arrangement for a composite of the name a host registered; the host commits it, and nothing in the package does.
- The editor's "Save as a step" control on the selected card, with a marking tray for the values the saved step should ask for, handing the proposal to a new `on_collapse` callback. The gesture edits no document and the package persists nothing.
- All nine field types now have a JSON spelling in a `Composite.Data` declaration: `select`, `path`, `list` and `type_expr` are the type's name plus an optional `"options"` key.
