### Added

- The compiler refuses a `core.subchart` whose `chart` names the document the
  block sits in, as an `:emit`-stage `:self_reference` finding against that
  block: a document cannot run itself. A cycle through two or more documents
  needs the host's document graph and stays the host resolver's to refuse.
