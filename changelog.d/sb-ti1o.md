### Changed

- A `StatifierBlocks.Graph` finding on a `core.subchart` or `core.map` that a composite's expansion placed is now anchored `{:block, composite_id}` on the composite block the stored document holds, and the compiled `interface` records that reference under the composite with the expanded member's id as `expanded_from`, in place of the member's id, which the stored document does not hold.
