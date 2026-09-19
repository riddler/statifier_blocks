### Changed

- A block placed in a composite's pass-through slot whose id equals one the
  composite's expansion mints for its own members now draws a
  `:minted_id_collision` finding at the Resolve stage, against the composite
  block and naming the placed block; before, it passed as that member, could
  hide an `:outcome_not_raisable` finding, and was refused at the Chart stage
  as a `:duplicate_id` when both blocks emitted a state. Give that block
  another id.
