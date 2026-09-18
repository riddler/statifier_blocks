### Fixed

- A `core.on_event` handler that names a finishing outcome of `done` while
  it resumes its group now reports both of the refusals that apply, instead
  of only the first.
