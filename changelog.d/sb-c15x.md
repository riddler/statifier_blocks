### Changed

- The Map's key of its marks is titled "Legend", and `StatifierBlocks.Map.Info.idle/4` answers the key's lines as its last fact under the label "Legend" rather than "Key"; `StatifierBlocks.Editor.MapRegions.description_region/1` with `map={false}` leaves that fact out as before. The key's lines and the paragraph on how to read the map are unchanged. A host that matches the idle description's facts by label reads "Legend".
