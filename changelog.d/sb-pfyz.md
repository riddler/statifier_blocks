### Fixed

- A child placed in a slot a composite's type does not declare now draws an
  `:undeclared_slot` finding even when that composite declares no outcomes;
  it used to compile green and be dropped with nothing to read.
