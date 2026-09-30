### Changed

- The editor's note field now stores each CRLF line break a browser posts as LF, so a note written in the editor holds the same bytes as the same note written by a host, and a change of line endings alone is no longer an undo entry; a lone CR is stored as posted, and the `{:update_note, id, note}` command a host issues itself still stores the note as written.
