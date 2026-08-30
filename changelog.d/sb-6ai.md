### Fixed

- Every zoom step in the editor toolbar now scales the canvas, and the panel scrolls the scaled size rather than the unscaled one.
- `Fit width` resolves to the largest zoom step at which the chart fits the canvas panel, instead of only recording that the fit was asked for.
- `Fit active` resolves to the largest zoom step at which the selected block fits, and scrolls that block to the centre of the panel.

### Changed

- The measurement hook's payload carries the canvas panel's usable box under a `viewport` key, read from the element the editor stamps `data-sb-anchor="viewport"`. A host that registers the hooks from the package's default export needs no change; a host that reimplemented the hook against the documented payload should send the new key for the fits to resolve to a number.
