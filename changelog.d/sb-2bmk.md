### Added

- `StatifierBlocks.Editor` takes an optional `profile` assign naming which of
  its surfaces a mount draws: `%{drawer_tabs:, inspector_tabs:, palette_groups:,
  toolbar:, read_only?:}`, every key optional and every list either `:all` or
  the ids it names. A mount that passes no profile renders exactly what it
  rendered before, and there is no arrangement of the map, `%{}` included, that
  removes a surface a host did not name.
- An id a profile lists that the package cannot resolve is dropped and the
  mount renders; a key whose value is neither a list nor `:all` resolves to
  that key's default. There is no `validate_profile/1` and a profile is never
  checked against the shell's ids at declaration.
- `profile: %{read_only?: true}` renders the document without offering any way
  to change it: no palette column, no drag hook on the canvas, config fields
  and declaration rows drawn as values rather than controls, Undo and Redo
  hidden rather than disabled, and every gesture that would reach the document
  answered with the socket unchanged, so `on_change` never fires. Selection,
  `on_select` and every findings surface are unchanged, and a document is never
  refused for being read-only.
- `StatifierBlocks.Shell.drawer_tabs/1` and
  `StatifierBlocks.Shell.inspector_tabs/1` answer the package's tabs a profile
  leaves, in the shell's own order; `StatifierBlocks.Shell.drawer_view/1` takes
  an optional `:profile` key and filters the host's contributed tabs by the
  same list.
- `docs/profiles.md` is the host-facing guide: the default, the ids each list
  draws from, the drop rule, a minimal mount and a read-only one.
