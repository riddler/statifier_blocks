### Fixed

- The editor's Expand gesture now writes each member of a composite at its block type's current version, so a member past version 1 (`core.send`, `core.wait`) is stored as authored at that version and the expanded document compiles to the same chart the composite did, instead of being stored at version 1 and migrated on the next compile.
