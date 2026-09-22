### Added

- A document can declare the external events it accepts, as an `accepts` list
  of event names on the envelope beside `datamodel`. `Document.validate/1`
  refuses a value that is not a list, an entry that is not a string, an empty
  name and a repeated name, each as a `{:malformed_envelope, {:accepts, _}}`
  reason. An empty or absent list encodes to the same bytes as before, so no
  existing document's `content_hash/1` changes; a reader from an earlier
  release refuses a document that declares one.
- `Compiler.compile/3` carries the document's `accepts` list, exactly as
  written, onto `%Compiled{}` and `%CompilationRecord{}` as a new `accepts`
  field. The compile reads nothing from it and the SCXML and chart identity do
  not change with it; whether each name is one the chart can take is for a
  host's publish step to check.
- The edit command `{:set_accepts, names}` replaces a document's whole
  `accepts` list, with the previous list as its inverse, and the editor's
  Declarations tab gains an accepted-events row where an author adds, renames,
  reorders and removes them.
