### Changed

- `StatifierBlocks.Graph.check/2` and `StatifierBlocks.Graph.consumers_broken/2` return a `:warning` finding on a `core.map` block's `collect_type` field when that field names a type and the parent was compiled without `:datamodel`, saying the done-data keys read there are unchecked, where they used to pass without a finding; each `interface` reference records the name in a new `unresolved` field. Pass `:datamodel` to the compile, or write the `collect_type` inline, to have the keys checked.
