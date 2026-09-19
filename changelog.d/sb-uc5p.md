### Changed

- A block placed in a composite's pass-through slot, or in a declaring
  composite's `on_<name>` slot, whose id equals one the composite's expansion
  mints for its own members now draws a `:minted_id_collision` finding at the
  Resolve stage, against the composite block and naming the placed block;
  before, such a document was refused at the Chart stage with `:duplicate_id`
  findings when both blocks emitted a state, and a block in a pass-through
  slot could hide an `:outcome_not_raisable` finding. Give that block another
  id.
