### Changed

- A container draws a box around its body only when it is a boundary - a
  container with a slot in the rail partition (ADR-0005 decision 10c, as
  amended by 10h). Every other container draws none: its own card stays at
  the head of its body and its children sit under it with the connectors,
  where a box around each of them turned a deep document into nested
  rectangles.
- A boundary's box is the border, the radius and the inset that enclose its
  body and its rail, rather than the border colour it was before.
- A container's card carries its own border, its accent stripe and its
  selection ring, so the block is still a card on the canvas when the box
  around its subtree is gone. A leaf card is unchanged.
