### Changed

- The family's two worked examples - the ADR-0001 card authorization
  document and the signup wizard - now declare the `<data>` roots their
  own guards read through ADR-0001 decision 11's document `datamodel`
  key, rather than leaving them to whichever host compiles them. Each
  declares exactly what it reads and no more: `budget_remaining` and
  `amount` for the first, `variant` for the second, none of them carrying
  an `expr`, since all three are per-run values a host seeds or a step
  assigns. Either document now compiles on its own, with no `:declare`
  option, without its guard raising `error.execution` over a root nothing
  declared.
- Both documents' canonical bytes move with the key, and so do their
  document hashes and the worked example's pinned chart identity. The
  identity move was verified rather than accepted: deleting the one
  `<datamodel>` element from the new bytes reproduces the previously
  pinned hash exactly, so nothing else in either emission changed. Only
  the test fixtures ship these documents; no packaged code moved.
