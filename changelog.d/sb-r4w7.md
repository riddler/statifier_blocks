### Added

- A `chart_outcomes` editor assign, `%{document id => [outcome]}`: what the
  host says each of the documents it compiles with `:child_use` finishes
  with. A `core.subchart` names a chart by document id and declares its
  outcomes by hand - a block type cannot read the document it references - so
  the assign is where that knowledge enters. Two things read it: the
  `outcomes` field offers the named chart's finals as a `<datalist>`, and
  `StatifierBlocks.ViewModel.outcome_findings/3` reports a disagreement
  between that list and what the block declares, anchored on the `outcomes`
  key and also reachable through `StatifierBlocks.Editor.findings_count/3`'s
  new `:chart_outcomes` option.
- The disagreement is a `:warning`, never an error: the document compiles
  either way, and what a mismatch costs is a conditioned `done.invoke`
  transition that can never match. A chart the map does not name produces
  nothing at all - unknown is not disagreement - and so does an entry holding
  an empty list, so `%{}` (the default) leaves the editor drawing exactly
  what it drew before. The field is still a plain `:string`: the list
  suggests and never constrains, and a free-typed name validates as it did.
