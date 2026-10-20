### Fixed

- The editor's Expand gesture now writes each member of a composite at its block type's current version, so a member past version 1 (`core.send`, `core.wait`) is stored as authored at that version, instead of being stored at version 1 and migrated on the next compile: with a duration in an accepted spelling the expanded document compiles to the same chart the composite did, and with one in a retired spelling the composite and the expanded document both refuse the same field with the same message.
