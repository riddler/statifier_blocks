### Added

- A slot declaring `slot_style: :failure` renders in its own vocabulary - a
  solid error-family edge, its own `sb-slot--failure` class, and an ordinary
  flow edge where an interrupt rail draws a dashed escape.
- `StatifierBlocks.ViewModel.exit_edge/1` says which edge vocabulary a slot's
  exit is drawn in, and the editor stamps it as `data-exit-edge`.

### Changed

- A `slot_style` this editor does not recognize renders as an ordinary body
  slot instead of reaching the markup unresolved; its children are still
  rendered, still selectable and still saved.
