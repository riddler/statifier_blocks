### Added

- `StatifierBlocks.Migration.plan/2` maps the states of one compiled revision
  of a document onto another's through their block ids, roles included, and
  answers plain string-keyed data in the migration plan's `states`, `history`
  and `invocations` fields. Every old state with no counterpart - each state of
  a deleted block, and each final of an outcome a block no longer declares -
  is listed under `unmapped` and mapped nowhere. Two artifacts of different
  documents are refused with `{:error, :different_documents}`. It moves no
  execution and reads no timer.
