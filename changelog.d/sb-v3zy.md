### Changed

- The Map's start dot now carries the word Start and every end mark the word End, whichever outcome it ends with; the outcome stays the caption on the arrow into the mark. In `StatifierBlocks.Map.graph/2` the start node and each end node carry the word as their one ELK `labels` entry, with `layoutOptions` asking the layout to place it outside the mark on its right, and the Map hook draws it there; a host drawing the graph itself finds the word in that label. The how-to-read paragraph `StatifierBlocks.Map.Info.idle/4` answers names the dot marked Start and the ring marked End.
