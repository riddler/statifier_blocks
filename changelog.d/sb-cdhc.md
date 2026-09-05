### Added

- `StatifierBlocks.ViewModel.summary_chip_titles/1` gives the raw text behind
  each summary chip, `nil` where the chip is drawn as its type declared it.
- `StatifierBlocks.Compiler.StateId.undone_event/1` inverts a generated
  `done.state` or `done.outcome` event name back to the block it names, or
  answers `:error` for a name that does not invert unambiguously.

### Changed

- A summary chip whose text has the shape of a generated done-event name is
  drawn as the named block's label and the outcome, with the raw name on the
  chip's `title` attribute, so a card no longer shows the compiler's spelling
  of a fact the author stated (ADR-0005 decision 10w).
- The presentation cap measures the drawn chip rather than the generated one,
  so the cap lint no longer names a string the author cannot shorten. A
  translated chip that is still over the cap is refused exactly as before.
- `summary/2`, `summary_refusals/2` and `summary_refusal_message/3` take an
  optional trailing map of block labels. A call that passes none behaves
  exactly as it did: without labels nothing is translated.
