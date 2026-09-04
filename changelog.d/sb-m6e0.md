### Added

- An `:expression` field renders statifier-ui's expression editor - picklists of field, operator and value over the source it can round-trip, a text input over the rest - when `statifier_ui` is on the load path, and the plain source input when it is not.
- A `value_candidates` editor assign, `%{path => [%{label:, value:} | binary]}`, carrying the values a host offers per datamodel path through to the expression control.

### Changed

- `statifier_ui` is a new optional dependency, resolved the way `phoenix_live_view` already is: absent, nothing raises and an `:expression` renders exactly what it rendered before.
