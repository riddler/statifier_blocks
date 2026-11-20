### Added

- `core.subchart` can name its child from data with the optional `chart_from` config key, a datamodel path whose value names the document to run when the invocation starts: it compiles to `<invoke srcexpr>` plus one reserved `statifier_blocks:outcomes` param carrying the block's declared outcomes, which both subchart handlers remove before the child starts. `chart` and `chart_from` are exclusive, a value that is not a string is refused `unknown_document` without the resolver being called, and a block that names its child by `chart` compiles to the same bytes as before.
