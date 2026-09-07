### Fixed

- The editor's Expand gesture refuses a composite whose declaration is too broken to expand - an empty or non-block `subtree/1`, a duplicated, `blk_`-prefixed or `__`-minting local id, or a pass-through slot mapped at something the subtree does not hold - naming the declaration error, instead of raising out of the author's LiveView. The compiler already answered the same case with a `:composite_expansion_failed` finding.
