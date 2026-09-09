### Fixed

- An `:expression` field served through the `expression_component` seam is
  handed the values the host offered for that field ahead of the document's
  declared paths - one de-duplicated `candidates` list - instead of the
  declared paths alone. A host that named values for the field now sees them
  in its own control, the way the plain input this package renders itself has
  always shown them; a host that named none sees the declared paths exactly as
  before.
