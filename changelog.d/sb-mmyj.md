### Removed

- `StatifierBlocks.Finding.from_compiler/2` no longer declares the
  `:no_presentation_source` refusal in `from_compiler_error/0`; nothing has
  produced it since the adapter began mapping unplaced compiler findings to
  `:compile`, so a caller that matched on it can drop the clause and keep the
  `{:unanchorable, finding}` one.
