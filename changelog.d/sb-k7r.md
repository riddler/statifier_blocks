### Added

- The editor draws connectors. Adjacency inside a slot, a container's entry,
  the fan and rejoin around a container arranged side by side, and a rail's
  exit are rendered as SVG in the LiveView tree, derived from the document's
  shape rather than authored.
- A second JavaScript entry point, `statifier_blocks/measure`, exporting the
  `StatifierBlocksMeasure` LiveView hook. Its whole job is measurement: after
  a render it reads the boxes the browser laid out for the anchors the server
  stamped and pushes them, and it issues no commands and mutates no DOM. A
  host that wants connectors adds one import; a host that does not gets the
  editor it had before, minus the drawn connectors.
- `StatifierBlocks.Connectors`: the connector geometry as pure functions from
  measured rectangles to SVG path data, outside the Phoenix guard, so a host
  can route its own connectors and a test can assert them without a browser.
- Three `--sb-*` tokens for the connector layer: `--sb-edge`,
  `--sb-edge-interrupt` and `--sb-edge-width`.
