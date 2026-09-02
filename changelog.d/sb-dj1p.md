### Added

- Compiling a `core.resumable_group` whose `body` opens with a delayed `core.send` and whose `interrupts` rail carries a `resume` handler now produces an advisory warning: no deadline is re-armed after the first resume, and the two escapes are arming the deadline outside the group or using a `core.group`.
