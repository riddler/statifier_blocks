### Changed

- The palette an armed "+" opens now filters recipes as well as block types. A
  recipe whose arrangement cannot land at the armed position - `insert/2`
  refuses it there, or the commands it answers with reach outside ADR-0005
  clause 3C's bound - is absent from the list rather than offered and then
  refused at the click, which wrote nothing and said nothing. The pick still
  runs both checks, so a stale pick is refused exactly as before.
