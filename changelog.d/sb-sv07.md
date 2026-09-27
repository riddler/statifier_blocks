### Fixed

- `StatifierBlocks.Describe.outline/3` draws the interrupt edge to the group's end for an abandon handler that names `finish_as`, keying the edge on the handler's `outcome` select rather than on the name it finishes with.
