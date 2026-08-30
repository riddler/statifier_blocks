### Changed

- The finding count badge no longer renders on a container's face. ADR-0005
  places it on a collapsed subtree and the editor has no collapse command yet,
  so a badge on every container read as an error on every card while the counts
  multiplied up the tree. Every finding is still reachable: the node keeps its
  subtree rollup in `data-findings-count`, and the drawer's Findings tab and the
  inspector both list them. A host styling `.sb-badge` should know the class is
  now rendered by nothing.
