### Added

- A config field declaration may carry `hidden?: true`, which keeps the field
  out of every form while the compiler, the Source tab and `validate_config/1`
  see its value entirely unchanged.
- A config field declaration may carry `readonly?: true`, which renders the
  field as its value beside its label rather than as an input.
- `StatifierBlocks.ViewModel.Field` carries both flags, so a host drawing its
  own surface filters on the same two booleans the package's own config form
  reads.

### Changed

- A config field declared without a `default:` key is now refused at compile
  whatever its field type; before, only a `{:path, opts}` field was. A block
  type that omitted the key on another type must add it - the declaration was
  never well formed, and the value it produced was `nil`.
- A `hidden?: true` field whose `default:` is its type's empty value is refused
  at compile: it can carry nothing and no form can ever give it a value. A
  hidden `:boolean` defaulting to `false` is legal, `false` being a decided
  value rather than an absence.
- A form ignores any posted value for a `hidden?` or `readonly?` field, so a
  crafted payload cannot reach a key the form withheld.
