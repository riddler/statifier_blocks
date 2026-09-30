### Fixed

- `StatifierBlocks.Editor.MapRegions.description_region/1` no longer raises when a composite in the document has a declaration that cannot expand: the region renders with no description in it instead of raising out of the host's render, as the editor already survives such a document.
