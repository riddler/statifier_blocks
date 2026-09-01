# ADR-0007: A block type declares its defaults with `use`, and the leaf invoke step is one declaration

Status: accepted (2026-08-31, unqualified direction-agent verdict under the
operator campaign-023 gate grant, PR 196)

## Context

ADR-0002 decision 5 fixes the declaration surface at nine callbacks, five of
them required. It fixes *what a block type is*. It says nothing about how a
module comes to have those nine functions, because until now every module that
had them wrote them out by hand and there was nothing to say.

**The evidence that there is now.** The reference embedder
(`statifier_examples`) had to invent a helper of its own,
`StatifierExamples.Charts.Step`, before it could write its first host block
type: 332 lines holding the `invoke_type` field grammar, the `label` field, the
`done`/`error` outcomes, an emission modelled on `StatifierBlocks.Core.Invoke`
minus the `on_error` slot, and the palette-entry defaults its twelve types
share. Each of those twelve types is then a further 60 to 130 lines, almost all
of it delegation to that helper. What a host type of that shape actually
*decides* is three facts: the invoke type it names, what its answer produces,
and how the palette draws it.

Two different costs are stacked there and they are worth separating:

1. **Every block type, host or core, restates the answers it has none of.** A
   leaf type with no children still writes `slots(_config), do: []`; a type
   with nothing to refuse still writes `validate_config(_config), do: :ok`; a
   type that has never changed shape still writes `current_version, do: 1`.
   Five of the nine callbacks are required, so a type cannot simply omit them.
2. **The leaf "call the host and wait" step is a shape, not a type.** It is not
   in the `core.*` vocabulary and it should not be - ADR-0002 decision 10's
   vocabulary is structural, and `myapp:capture` is nobody's structure. But it
   is the same hundred lines in every host that has one, and the first
   embedder proved that by writing them.

**What ADR-0002 already permits.** Nothing in it requires a callback to be
typed out in the module that exports it. Decision 5 owns the surface; decision
4 owns purity; neither is a statement about authorship. A macro that defines
ordinary functions produces a module indistinguishable from a hand-written one,
which is why this record is additive rather than a reopening.

**Why this is its own record.** It is what campaign-023 ruling R-a settled:
this ships a new record that cross-references ADR-0002 rather than an
amendment to it. The substantive reason matches the procedural one.
ADR-0002 decides what a block type *is*; this decides a convenience layer
*above* it that any type may ignore entirely, and folding it into ADR-0002
would suggest the behaviour
contract moved. It did not - see decision 4 below.

## Decision

### 1. `use StatifierBlocks.BlockType` declares the behaviour and injects overridable defaults

`use StatifierBlocks.BlockType` is equivalent to `@behaviour
StatifierBlocks.BlockType` plus one definition per callback whose absence has
an obvious answer:

| Callback | Injected default | Why that answer |
|---|---|---|
| `slots/1` | `[]` | a type with no children declares no slots |
| `config_schema/1` | `[]` | a type with nothing to fill in renders no form |
| `validate_config/1` | `:ok` | a type with nothing to refuse refuses nothing |
| `current_version/0` | `1` | ADR-0001 decision 4's starting version |
| `io/1` | `%{}` | every key of `t:StatifierBlocks.Assignability.io/0` is optional, so this is exactly what ADR-0003 says an absent `io/1` means |
| `migrate_config/2` | `{:error, {:no_migration_from, from}}` | see below |

Every one is `defoverridable`. A type writes only the rows where it differs,
and a type that writes all nine out by hand is unaffected.

**`emit/2` is deliberately not among them.** There is no emission a block type
can default to. One injected here - an empty state, a bare `<final>` - would
let a type that forgot to compile anything look complete instead of failing to,
and the failure would surface as a chart missing a step rather than as a
compile warning naming the module. `emit/2` stays required, so leaving it out
is a warning at the module that left it out.

**`migrate_config/2` refuses rather than answering `{:ok, config}`.** A no-op
migration reads as harmless and is not: a type at `current_version` 1 has no
older shape, so every `from` that reaches the default names a version the
module has never had, and answering "it is already current" is how a document
carrying a version this deployment does not understand compiles as though it
were understood. ADR-0002 decision 8 has migration in memory only and never
written back; the default preserves that by declining, which is the same answer
the absent callback gives.

**`outcomes/1`, `palette_entry/0`, `fixtures/0` and `summary/1` are not
injected.** Each already has a stated default that lives in a *resolver* -
ADR-0002 amendment A1's `[{"done", "Done"}]`, the palette's fallback to the
type name, and amendment H1's `nil` - and those resolvers answer for a module
that does not export the callback. Injecting a definition would move the
default out of the one place it is written down and into every module that
`use`s this, so that a change to the default would no longer reach modules
already compiled. The defaults above are injected precisely because they have
no resolver: the callback is required, or its absence is only meaningful to a
caller that already knows to look.

**Purity (ADR-0002 decision 4) holds unchanged.** Each injected function is a
constant function of its arguments. The macro runs at compile time and reads
nothing but its own options, so a `use`-ing type reaches for the process
dictionary, application configuration, IO, the clock and randomness exactly as
often as a hand-written one does: never.

### 2. `StatifierBlocks.InvokeStep` is the leaf-step base, declared not spelled

`use StatifierBlocks.InvokeStep` builds on decision 1 and fills in the rest
from a declaration:

```elixir
defmodule MyApp.Blocks.Capture do
  use StatifierBlocks.InvokeStep,
    invoke_type: "myapp:capture",
    produces: "myapp.capture",
    palette: %{label: "Capture", group: "Payments", icon: "banknotes"}
end
```

| Option | Meaning | Absent means |
|---|---|---|
| `:invoke_type` | the invoke type this step names when its config does not say otherwise | required |
| `:produces` | what a successful call produces to the next sibling (ADR-0003) | the step is unconstrained beyond being one |
| `:fields` | extra field declarations, appended in the order given | the step carries only `label` and `invoke_type` |
| `:palette` | palette-entry keys, merged over the base's defaults | the editor's own fallbacks |

What it injects, over decision 1's layer: `invoke_type/0`; `config_schema/1` as
`label`, then `invoke_type` prefilled with the declaration, then `:fields`;
`validate_config/1` as the `invoke_type` and `assign_to` checks; `io/1`;
`outcomes/1` as `[{"done", "Done"}, {"error", "Error"}]`; `palette_entry/0`;
and `emit/2`. Every one is overridable, and the module exports the pieces -
`check_invoke_type/2`, `check_assign_to/2`, `check_identifier/4`, `verdict/1`,
`literal_param/3`, `emit/4` - so a type that needs more composes its own
callback out of them rather than re-deriving the parts it still wanted.

**The emission is `core.invoke`'s with the `on_error` slot taken out.** A leaf
step has no children, so a failing call is an `error` outcome a parent may
wire rather than a subtree the block runs, and both outcome `<final>`s are
emitted unconditionally rather than only when a slot is occupied. Everything
else is `StatifierBlocks.Core.Invoke`'s and is unchanged by this record: both
transitions match by SCXML's descriptor prefix rule on an inner state that is
active only while this block's own call is outstanding; `assign_to` is written
on the success transition rather than in a `<finalize>`, because the answer is
only an answer when the call succeeded.

**A literal declaration is checked where it is written.** An `:invoke_type`
given as a string literal outside the `namespace:name` grammar raises at
compile time. A typo'd handler name is then a compile error at the module that
declared it, rather than a validation finding met later by every author of
every document that carries the step. A declaration computed from a module
attribute is not a literal at expansion time; it passes through and is checked
by `validate_config/1` like any stored value.

**The grammar has one spelling.** `namespace:name` moves to
`StatifierBlocks.Core.Config`, and `core.invoke` and this base both read it
from there. Two spellings would be two chances for a core block and a host step
to disagree about the same field.

### 3. The two-registry seam is untouched

A block type **names** an invoke type; a handler the host registers separately,
per session under st-ADR-0051, is what **runs** it. That is ADR-0002 decision
2's seam and this record does not move it. `use StatifierBlocks.InvokeStep`
registers nothing, resolves nothing, and knows no handler:
`StatifierBlocks.Compiler.InvokeTypes` remains what a caller compares the two
registries against, at the one moment it holds both.

### 4. What this record does not change

Stated explicitly, because a defaults layer is exactly the kind of change that
can be read as a contract change and is not:

* **The behaviour contract is untouched.** ADR-0002 decision 5's nine
  callbacks, which five are required, and what each returns are all exactly as
  that record has them. `use` adds no callback, removes none, and makes no
  optional callback required or the reverse.
* **The palette is untouched.** ADR-0002 decisions 1 to 3 (a type is named by
  string, the palette is a caller-supplied value, resolution is total) and
  ADR-0005 decision 10's presentation keys hold unchanged.
  `StatifierBlocks.InvokeStep` is not a block type: it implements no callback
  of its own, has no
  `type_name`, and appears in no palette.
* **The purity rules are untouched.** ADR-0002 decision 4 applies to a
  `use`-ing type in full, and to this package's own injected functions, which
  are pure.
* **Stored bytes are untouched.** ADR-0001's document schema, ADR-0004's
  provenance map and its decision 6 byte determinism all read the same
  callbacks and get the same answers. A type converted to `use` compiles to the
  bytes it compiled to before, or the conversion is wrong.
* **The `core.*` vocabulary is not converted.** The thirteen accepted types
  keep their hand-written callbacks. Rewriting them would touch code that
  ADR-0004 decision 6's compiled-bytes tests pin, for no gain this record
  needs; `core.invoke`'s one change here is that its `namespace:name` predicate
  now calls the shared one, with the same grammar and the same answers.

## Consequences

**A host type shrinks to what it decides.** The target shape is a `use` line,
an invoke type, a produced type, and a palette entry, with overrides only where
the type has real behavior. Taking the reference embedder's twelve types down
to that, and deleting most of its 332-line helper, is the uptake this record
was written for and is `statifier_examples`' own bead, not this one.

**There are now two ways to write a block type.** That is a real cost and the
mitigation is that they are not two kinds of type: `use` is sugar that defines
ordinary functions, the resulting module is indistinguishable from a
hand-written one, and the README says so where a host reads it first. The
package's own `core.*` vocabulary staying hand-written is a second copy of the
same message.

**A default can be wrong for a type that forgot to override it**, and this
record does not pretend otherwise. A step that meant to declare a slot and did
not gets `[]`. What it does not do is fail more quietly than the hand-written
mistake: the wrong answer reaches validation, the editor and the compiler by
the same path a wrong hand-written answer does, and is caught, or not, in the
same place.

**The compile-time invoke-type check reaches only literals.** A host that
computes its declaration keeps the runtime check and loses the early one. That
is the right trade: refusing a non-literal at compile time would refuse the
legitimate case of a host deriving names from one place.

**A later base is now cheap.** The pattern generalizes - a leaf step is the
shape the first embedder proved, and a second shape, if a second embedder
proves one, is another module beside this one under the same decision 1 layer.
This record deliberately ships exactly the one shape there is evidence for.

## Note (2026-08-31): `StatifierBlocks.Runtime.*` is where a canonical runtime helper lives

Recorded for `sb-4ptg` under campaign-024 ruling R-d. Decision 3 above keeps
the two-registry seam: a block type **names** an invoke type and a separately
registered handler **runs** it, so everything this record decides sits on the
authoring side of that line. `StatifierBlocks.Runtime.Subchart` (PR 197,
merged 2026-08-31 at `487cebf`) is the first thing this package has shipped on
the other side of it - the canonical `statifier_blocks:subchart` handler,
written once here because every host embedding `core.subchart` would otherwise
write the same one - and the namespace it chose is the precedent for every
runtime helper after it: **canonical host-side runtime helpers live under
`StatifierBlocks.Runtime.*`**, set against the authoring half that is
everything else under `lib/`. The alternative considered and rejected was
`StatifierBlocks.Invoke.*`, and the reason it was rejected belongs in the
record rather than only in a moduledoc, because it is about names this record
owns: `StatifierBlocks.InvokeStep` (decision 2) and `StatifierBlocks.Core.Invoke`
both *name* invoke types and run nothing, so a third `Invoke`-prefixed
namespace that did the opposite would read the same as those two and mean
their inverse. Nothing about decision 3 moves: a module under `Runtime.*` is a
handler a host registers with `statifier` per session (st-ADR-0051), it
resolves no block type, it appears in no palette, and no block type reaches
for one. The convention is where a later handler goes, not permission for one
to exist; whether this package ships a second is that handler's own bead.
