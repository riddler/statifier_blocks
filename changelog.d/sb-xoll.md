### Changed

- A `core.on_event` capture pair's literal source - `["const", value]` - now
  accepts a string carrying any character. The interim restriction that a
  literal string stay inside printable ASCII, tab, newline and carriage
  return is lifted: it was earned only while predicator 9.4.0's string lexer
  wrote a literal's codepoints back one byte at a time, and 9.4.1 fixed that
  lexer. A handler may now capture a label such as `"Café inscrit"` and the
  datamodel reads it back whole.

- Dependency floor: `predicator` moves from `~> 9.0` to `~> 9.4.1`. That is
  the version whose string lexer reads a literal back whole, which is what
  the lifted restriction above needs; 9.4.0 and below are excluded.
