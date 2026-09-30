### Changed

- `StatifierBlocks.Editor.MapRegions.map_region/1` no longer stamps `data-info-region` on the map's element, which the `StatifierBlocksMap` hook has not read since 0.40.0 (it finds its hover layer by `data-info-hover` and its store by `data-info-store`), so the hover is unchanged. A host that stamps the attribute on its own element has nothing to do; a host that read it off the element finds it gone and takes the region's id from the `description` it passes.
