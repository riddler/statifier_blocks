### Changed

- The Map hook draws a resume edge clear of its own rule's box when the middle of the head of the group's body is not well above the rule's top: the edge still leaves the top of the rule and ends on the head's side, but it now goes up a short way, left past the rule's side and down to the head's height before it turns in, where it ran straight down through the rule's box. A resume edge whose head stands well above the rule is drawn as before. Only the hook's drawing moves; `StatifierBlocks.Map.graph/2` answers the same graph.
