### Changed

- A compile refusal now carries the findings of the **Config and Structure
  stages together**, instead of the first of the two that failed. A mis-typed
  field on one card no longer hides an unsatisfied read on another, so an
  author sees both in one refusal rather than one per round trip. Refusal
  semantics are unchanged: such a document still does not compile, and every
  stage after Structure still stops the pipeline at its first failure.
- A block whose config the Config stage refused is skipped by id in the
  Structure stage: it reports no structure finding of its own, and its
  declared writes leave no entry in the typed environment, because a write
  signature is read off the config that was refused. The walk continues past
  it - its siblings and its children are checked exactly as before.

### Added

- `StatifierBlocks.Environment`'s context accepts `:skip_blocks`, a set of
  block ids whose declared writes the walk leaves out. Absent, as it is for
  every editor query, nothing is skipped.
