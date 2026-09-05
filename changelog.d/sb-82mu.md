### Added

- The editor offers value candidates on `core.on_event`'s `event` field: the
  completion events the blocks in the handler's enclosing body raise, written
  as the generated `done.outcome.<state id>.<outcome>` names the compiler
  mints and labelled by each block's own card label and outcome. The body is
  read through the enclosing type's `slot_accepts` declaration - a slot that
  admits ADR-0003's `:step` kind - so a host group is offered on the same
  terms a `core.group` is, and only blocks that implement `outcomes/1`
  contribute. The field is still a plain `:string`: the list is a
  `<datalist>` that suggests and never constrains, a free-typed event name
  validates exactly as it did, and a body with nothing to offer draws the
  plain input rather than an empty picker.
