### Added

- The editor draws a description region under its canvas: the selected
  block's description, its note first, or the document's name, description,
  what starts it and its counts when nothing is selected. It is the Map's
  `StatifierBlocks.Editor.MapRegions.description_region/1`, live and showing
  values only; the editor still draws no map. It is drawn in a read-only
  mount too, and no `profile` key hides it.
- `description_region/1` takes a `map` attr, `true` by default, saying
  whether a map is mounted beside the region; `false` renders no hover
  layer, no store and no how-to-read paragraph in the idle description. A
  host that passes nothing gets the region it had.
