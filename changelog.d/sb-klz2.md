### Changed

- Decode admits an optional `note` string on a block, a key it refused
  before: `StatifierBlocks.Block` gains a `note` field (default `""`, the
  absent note) that `Block.new/2` takes as `:note`, canonical form omits an
  empty note, the shipped schema describes it, and a non-string note is
  refused as `{:malformed_block, id, {:note, :not_a_string}}`. A note
  changes the document hash, not the compiled chart.
