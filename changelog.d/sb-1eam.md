### Added

- `StatifierBlocks.Environment.with_writes/5` is public: `env` with one
  block's own writes applied, member expansion included. The declarations
  argument carries a default, so `with_writes/4` is the spelling a caller
  writes.

### Fixed

- The editor's drop-check preview no longer under-reports a member mismatch
  the drop would introduce. It applied a candidate's writes without the
  member expansion the walk runs, so a read of `record.member` was answered
  with an advisory before the drop and an error the moment it landed. The
  preview and the walk are now one codepath, and they agree.
