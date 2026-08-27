### Fixed

- `StatifierBlocks.Assignability.check/5` and `valid_targets/4` no longer raise a `MatchError` when the candidate is the document root. `Document.fetch_path/2` answers `{:ok, []}` for the root, and the vacated-seam check now reads that as what it is - the root occupies no slot, so it leaves no seam behind - instead of calling `List.last/1` on the empty path. `StatifierBlocks.Edit.Targets.droppable_slots/3` answers `[]` for the root rather than crashing, so a caller no longer has to guard around it.
