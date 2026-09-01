### Fixed

- An arranged container whose slot ends in a drafts shelf drew its rejoin
  edge from the shelf's own outlet, asserting flow out of the one card
  nothing enters and nothing leaves. The rejoin now leaves the last step in
  the slot, and a slot holding nothing but a shelf rejoins from its header,
  the same as an empty one.
