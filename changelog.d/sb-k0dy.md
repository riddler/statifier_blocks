### Fixed

- A **root** block declaring an outcome named `failed` is now refused at
  compile with a `:config` finding naming the field the name was written in,
  rather than reaching `Statifier` as a duplicate state id reported against
  the package. The name is the one the shared final for an unhandled failure
  below the root already mints; rename the outcome. A block below the root is
  unaffected, and no other document's compiled bytes move.
