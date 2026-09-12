### Changed

- The compiled chart of a document with a failure-classed final changes: the
  reserved `<donedata>` param the compiler mints on such a final is now named
  `statifier_persistence:execution_status` instead of
  `statifier_persistence:run_status`. Upgrade a durable host to
  `statifier_persistence >= 0.12`, which is the floor for reading the new key;
  0.12 reads both keys for one release and 0.13.0 reads only the new one. A
  document with no failure-classed final compiles byte for byte to what it
  compiled to before. Both names stay refused for a `donedata_type/1`
  declaration while the old one is still read.
