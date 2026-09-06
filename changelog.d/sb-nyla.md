### Added

- A host can state a rule about a whole document, not just about one block's config: `StatifierBlocks.DocumentValidator` is the behaviour, `validate_document/1` its one callback, and a module implementing it goes in the palette's new `validators` list (`StatifierBlocks.Palette.new/2`'s `:validators` option, defaulting to `[]`).
- A validator says where and what - `{anchor, message}` or `{anchor, message, severity: ...}` on decision 11's existing anchors - and the package stamps the source `:lint` and defaults the severity to `:warning`. The findings render in the editor's Findings drawer tab and count toward `StatifierBlocks.Editor.findings_count/3` like every other finding.

### Changed

- A palette entry's `singleton` declaration is now derived through the same document-rule path a validator's findings take, and runs first among them. Its findings are unchanged: still `:config`, still `:error`, still anchored at the root.
