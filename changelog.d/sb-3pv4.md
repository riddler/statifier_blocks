### Added

- `StatifierBlocks.Finding`'s `source` gains `:compile`, and
  `from_compiler/2` maps any compiler finding its by-stage rule cannot place
  onto it instead of refusing, so a compile error raised against generated
  SCXML or against the document envelope can be rendered by the editor.

### Removed

- `:arity` leaves `StatifierBlocks.Finding`'s `source` type. Nothing ever
  produced it: slot arity and undeclared-slot violations arrive through the
  compiler's `:structure` stage and have always carried `:assignability`.
  Pass `:assignability` where you passed `source: :arity`; the finding's
  `{:slot, block_id, slot_name}` anchor, and so where it renders, is
  unchanged.
