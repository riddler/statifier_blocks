### Changed

- `StatifierBlocks.Editor.MapRegions.map_region/1` and `description_region/1` refuse a `phrase` that is neither `nil` nor a function of one argument with an `ArgumentError` naming the attr, where they raised a `FunctionClauseError` from a private function; `nil` and a one-argument function render as before.
