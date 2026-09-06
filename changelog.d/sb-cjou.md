### Changed

- `core.map`'s `collect` accepts any datamodel path, not only a bare lowercase
  identifier, so a fan-out can assemble its answers at `cards.batch` and not
  only at `batch`. All four fields this package writes an
  `<assign location="...">` from now read one grammar and one refusal wording.
