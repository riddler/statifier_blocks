### Fixed

- The editor's Source tab and its fixture runs now compile with the host's
  `compile_options`, as the provenance recompile already did. All three
  compiles pass one option list, so the listing, the fixture verdicts and the
  Run pane's marks are all about the chart the host actually compiled.

### Changed

- `compile_options` is required of any host that compiles with `terminate:`,
  `child_use:`, `known_invoke_types:` or `datamodel:`. Leaving it unset is not
  an error and never was: the editor compiles a different chart than the host
  does, and a run against that chart is silently unmarked, the Source tab
  lists a chart nobody runs, and the fixture verdicts are about neither. Pass
  the host's own option list.
- `StatifierBlocks.SourceView.build/3` and
  `StatifierBlocks.Runtime.FixtureRuns.run/4` forward their whole `opts` to
  the compiler rather than `:declare` alone, less the one key each keeps for
  itself (`:previous` and `:view_model`).
