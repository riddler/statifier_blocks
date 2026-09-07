### Added

- A palette entry may now be `{module, state}` beside a bare module, so a host
  whose *users* save block types can register a declaration held as data.
  `StatifierBlocks.Palette.call/4` is the one seam every callback on an entry
  goes through: it prepends the state, asks about the arity a stateful module
  actually exports, and answers a caller-supplied default when the entry
  declares nothing. `StatifierBlocks.Palette.declares?/3` answers declaredness
  alone for the two presentation branches that need it rather than a value.
- `StatifierBlocks.Composite.Data` derives a composite block type from a
  JSON-shaped declaration - params, a subtree template with one `"$param"`
  placeholder arm and one `"$literal"` escape, and an optional sentence and
  palette entry - through the same `StatifierBlocks.Composite.expand/2` a
  `use StatifierBlocks.Composite` module goes through. A data composite and
  the module composite of the same shape expand to the same blocks and compile
  to the same bytes. `Composite.Data.declaration/1` refuses a malformed
  declaration before it reaches a palette, which is the last moment a callback
  can still be pure and total.

### Changed

- `StatifierBlocks.Palette.fetch/2` and `resolve/2` answer the entry **as
  stored**: neither normalizes a bare module into a pair nor unwraps a pair
  into its module, so a host that registered no stateful entry can be handed
  none and its existing `{:ok, module}` matches still match. `manifest/1`,
  `new_block/2` and `from_modules/2` read a stateful entry through the seam,
  including `from_modules/2`'s duplicate-`order` check - a stateful entry
  collides with a bare one at the same order and is refused, rather than
  silently dropping out of the check.
- `StatifierBlocks.Composite.expand/2` and `composite?/1` take a palette entry
  where they took a module. The existing module-only calls are unchanged.

### Note

- `StatifierBlocks.Composite.Data` fixes no migration key, so bumping a
  declaration's `"version"` with stored blocks refuses them through ADR-0007's
  injected `migrate_config/2`, unchanged and deliberately not papered over.
