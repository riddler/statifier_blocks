### Added

- Two tier-2 theme tokens, `--sb-run-done` and `--sb-run-done-bg`, for the
  `done` outcome of an invoke run mark. A host that themes the editor now
  sets the "came back" colour directly instead of inheriting whatever it set
  `--sb-info` to.

### Changed

- An invoke mark whose outcome is `done` is drawn in `--sb-run-done` rather
  than `--sb-info`. In the shipped light palette `--sb-info` and
  `--sb-accent` are the same blue, so a block that was *active* and a block
  that had *come back* differed only in treatment - a halo outside the border
  against a border and a fill - and read as one state at a glance. They are
  now different hues in every theme the package ships or documents.

  This is a visual change for a host that did not override `--sb-info`, and
  a host that had retuned `--sb-info` specifically to colour its done marks
  should move that value to `--sb-run-done`. Nothing else reads the new
  tokens, and the `error` outcome still takes `--sb-error`.

  The complete host theme in `docs/theming.md` restates both tokens, as the
  theme audit requires of every colour token, and the accessibility
  discipline is unchanged: `--sb-run-done` is held to the 3:1 non-text
  threshold as a border that carries information, and `--sb-run-done-bg` is
  recorded as translucent and held to no ratio.
