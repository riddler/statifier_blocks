### Changed

- The `statifier_datamodel` floor moves to `~> 0.3`, so a datamodel entry
  whose `type` names a declaration contributes the declaration's fields as
  declared paths beneath its own: they are offered as expression candidates,
  they carry their declared types in the Datamodel tab, and a block that
  writes one gets no undeclared-path advisory, exactly as an inlined `object`
  entry's `fields` do. A host on `statifier_datamodel` 0.1 or 0.2 updates it
  with the rest of the dependency tree.
- The Datamodel tab renders an entry typed by a declaration as the name it
  names, rather than raising on the `{:declared, name}` that release added.
