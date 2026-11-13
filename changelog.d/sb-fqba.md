### Added

- A module composite may define `subtree/2` instead of `subtree/1`: it is handed the params and an expansion context carrying the composite block's own id under `:block_id`, so a member's config can name the composite it was expanded from. `subtree/1` is unchanged, and a module defining both, or neither, does not compile.
