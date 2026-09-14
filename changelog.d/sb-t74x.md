### Changed

- A composite that declares `outcomes` now compiles to a state of its own with
  one `<final>` per declared name, so an enclosing body can route its
  completion, and it derives one `on_<name>` slot per declared outcome for the
  blocks that run when it finishes that way.
- A composite declaration whose `slots:` names a pass-through slot after one of
  its own declared outcomes is now refused, because the two kinds of slot
  cannot share a name; rename one of them.
