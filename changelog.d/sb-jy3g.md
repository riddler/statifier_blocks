### Added

- A document with a returnable step compiles with a trail in the chart's own datamodel: one root per trail scope that holds a returnable step (the document, a `core.foreach` body, a `core.parallel` lane), named for the scope state with `__trail` appended and declared empty, and an `<onentry>` first in each returnable step's state that pushes the step's state id unless it is already on top; the trail holds state ids only, and a document with no returnable step compiles to the same bytes as before.
