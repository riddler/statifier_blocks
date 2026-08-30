### Added

- `StatifierBlocks.BlockType.summary_refusals/2` reports the summary chips the
  24-character presentation cap dropped, as `{index, reason}` with `reason` in
  `:too_long`, `:blank`, `:multiline` or `:not_a_string`, and
  `summary_refusal_message/3` puts one into the words an author reads.

### Changed

- The view model raises a `:lint` warning against a block for every summary
  chip the presentation cap refused, so a card that draws no second line can
  be told apart from a type that declared none. A well-formed document gains
  no findings.
