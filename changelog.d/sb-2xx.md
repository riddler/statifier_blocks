### Changed

- The document-level findings list is the drawer's **Findings** tab, beside
  Truth tables, and no longer a block of text under the canvas (operator
  ruling R4, 2026-08-29, under ADR-0005 ruling 1A: a list of findings is a
  grid of rows about the whole document). Each row carries the finding's
  severity, the block it is about - label and id - and the message, and
  clicking one selects and reveals that block. The inspector's Findings tab
  is unaffected and stays the selected block's findings (3A), as do the
  per-card counts.
- The collapsed drawer strip reports the **active tab**. An author who has
  not picked a tab gets the first one that holds something, so a document
  with findings and no fixtures reads `Findings 4` rather than
  `Truth tables 0`; once a tab is picked the pick stands. A host swapping the
  open document resets the pick along with the drawer's open state.
- `StatifierBlocks.Shell.drawer_view/1` accepts `:tab`, `:findings` and
  `:orphan_findings`, and its result gains `tab`, `tabs`, `findings` and
  `orphans`. `title` and `count` now describe the active tab rather than the
  truth tables specifically; the truth-table `status` values are unchanged.
- `StatifierBlocks.Editor.Findings.findings/1` takes `findings`, `orphans`,
  `root` and `target` instead of `view_model`, and renders the tab's panel
  rather than a headed section: the tab is the heading.

### Added

- `StatifierBlocks.Shell.drawer_tabs/0`, `drawer_tab/1` and `drawer_title/1`,
  in the same shape as the inspector's tab helpers - an unknown tab from a
  crafted `phx-value-tab` resolves to the first one.
- `.sb-findings__row`, `__severity`, `__subject`, `__label`, `__id` and
  `__message`, the row's parts. The severity colour stays on `.sb-finding`
  and its severity modifier, so a host that had restyled one severity keeps
  that styling with no edit. No new custom property.
