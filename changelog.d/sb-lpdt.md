### Added

- The editor takes drawer tabs from its host: `drawer_tabs` is a list of
  `%{id:, title:, content:}` descriptors, with an optional `count:`, and each
  one is drawn beside the package's own Truth tables and Findings tabs and
  activates the same way. `content` is a function component, the same seam
  shape `icon` and `expression_component` use, called when its tab is the
  active one. The descriptors are ordinary editor state, so a host pushes them
  with `Phoenix.LiveView.send_update/3` and a feed the host is appending to
  redraws as it grows - a tab whose content changes under the host is what the
  seam exists for.
- The collapsed strip and the unchosen-tab resolution reach host tabs too: a
  document with no truth tables and no findings and a running feed opens on
  the feed rather than on an empty `Truth tables 0`, and a collapsed drawer
  names it.
- `StatifierBlocks.Shell.host_tabs/1` is the admission rule, and
  `StatifierBlocks.Shell.drawer_tab/2` resolves a tab name against the
  package's tabs and the host's together. A host tab named for one of the
  package's own, or repeating an id already used, is not drawn: the id is
  stamped into the tab's DOM id and its panel's. No tab name is ever turned
  into an atom, so a crafted `phx-value-tab` reaches at worst a tab the host
  declared.

The package's own tabs, the drawer's five states, its resize and its collapse
are unchanged, and a host that contributes no tabs gets the drawer it had.
