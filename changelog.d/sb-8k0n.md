### Added

- `StatifierBlocks.Describe` describes a block document in words: `outline/3` answers one node per block and the flow-graph edges between them, read from the document's structure without compiling it, and `render/2` writes one deterministic English line per node and per edge, which a host rewords through the `StatifierBlocks.Describe.Phrasing` behaviour.
