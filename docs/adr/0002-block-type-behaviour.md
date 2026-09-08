# ADR-0002: A block type is a behaviour module resolved through a caller-supplied palette

Status: accepted (2026-08-26); decision 9 amended (2026-08-26); decisions 7, 8 and 10 and the typespec appendix amended (2026-08-27, operator rulings); outcomes/metadata/label amendment (accepted 2026-08-29, operator ruling); decision 7 amended - optional `datamodel_path?` key (2026-08-29, accepted under the operator campaign-015 direction-agent gate grant, PR 90); decision 10 amended - the core.assign row, section G (2026-08-29, accepted under the operator campaign-015 direction-agent gate grant, PR 98); decision 7 amended - optional `sensitive?` key and the secrets rule (2026-08-29, accepted under the operator campaign-015 direction-agent gate grant, PR 99); core.send send id and no core.cancel amendment (2026-08-29, accepted under the operator campaign-015 direction-agent gate grant, PR 95); decision 10 amended - the core.send row, section G2, and the decision 7 :duration cross-reference (2026-08-29, accepted under the operator campaign-015 direction-agent gate grant, PR 110); decision 10 amended - the core.subchart and core.foreach rows, core.parallel's `complete` key and the thirteen count, G5-G8 (2026-08-29, accepted under the operator campaign-015b direction-agent gate grant, PR 129); the optional `summary/1` callback and the card's second line, section H (2026-08-30, accepted under the operator campaign-017 direction-agent gate grant, PR 150)

## Context

ADR-0001 fixed the document: a tree of `{type, id, config, slots}` nodes,
where `type` is a namespaced string, `config` is opaque JSON, and the set of
slot names a block carries is declared by its block type *given that block's
config*. It deliberately stopped at the point where the block type's own
contract begins, and named this record as the owner of three questions it
left open: how a type name resolves to an implementation (decision 4), what
a slot's declared arity is (decision 5), and what a block type's config
schema is (decision 6).

**The block type is the extension seam of this package.** This package ships
a small `core.*` structural vocabulary and nothing else; every palette entry
a host actually cares about - an external data-provider step, a budget-check
step, a settlement step - is written by a multi-tenant host embedding the
engine. That is the same shape the engine already settled upstream for
`<invoke>`: st-ADR-0051 made the invoke-handler set deployment state,
supplied per session as a caller-declared value, with a behaviour of pure
planning callbacks. This record is the authoring-time analogue of that
runtime seam, and it is deliberately built the same way, for the same
reasons. Where the two meet is worth saying now: a block type never runs
anything. It emits SCXML that names an invoke type, and the host registers a
handler for that type with `statifier` at runtime. Authoring-time extension
and runtime extension are two registries with two different lifetimes, and
this record owns only the first.

Three forces shape what a block type has to declare.

**Everything about a block is a function of its config.** ADR-0001 decision
5 made slot sets config-parameterized: a branch has one slot per arm plus
`otherwise`, a parallel block one slot per lane, and neither is knowable
from the type name alone. That single fact rules out declaring a block
type's shape with module attributes or a static struct, and forces the
declaration surface to be *functions taking config*. It also means the
editor cannot cache a block type's shape by name: re-editing config can add
and remove slots, which is an editing operation on the document (sb-w50) and
a re-validation trigger.

**Resolution must be able to fail without anything catching fire.** ADR-0001
decision 9 made decoding registry-free precisely so a document containing a
palette entry the host has since removed still loads. That promise is only
real if resolution has a typed failure arm that every consumer - validation,
the editor, the compiler - can carry as a value rather than an exception.

**These callbacks run inside deterministic pipelines.** Validation runs on
every keystroke-adjacent edit in an editor; compilation must be reproducible
against a document hash (ADR-0001 decision 8, sb-iwz). Neither can afford a
callback that reads a database, calls a service, or depends on process
state. st-ADR-0051 decision 4 drew this line for its own planning callbacks
and it carries over unchanged.

## Decision

**1. A block type is an Elixir behaviour module. The document names it by
string; a palette resolves the string.** `StatifierBlocks.BlockType` is the
behaviour. The module never appears in stored bytes - ADR-0001 decision 4
already settled that, and this record does not reopen it. Resolution is a
lookup from `type_name` to module, and it is the only place the two
namespaces meet.

**2. The palette is a caller-supplied value, not global state.** A
`%StatifierBlocks.Palette{}` is a map of `type_name` to module, built by the
host and passed explicitly into every operation that needs to resolve a type:
validation, the editor's session state, the compiler. There is no
`Application` env lookup, no named ETS table, no process registry, and no
"register at boot" side effect.

st-ADR-0051 decision 2's grounds carry over almost verbatim. A value can be
recorded, snapshotted, and compared, where a global registry's answers would
have to be captured lookup by lookup; a value makes the dependency
structural rather than conventional, so a function that needs the palette
says so in its signature; and a value lets a multi-tenant host hold
different palettes for different tenants in one VM, which a global registry
makes actively hard.

The cadence differs from st-ADR-0051's, and for a reason worth naming: the
invoke-handler set is fixed for a session's lifetime, while a palette is
fixed for an *editing or compiling operation*. A host that adds a palette
entry does not restart anything; the next operation is passed a different
value. Nothing in this package holds a palette across operations.

**3. Resolution is total and returns typed errors.** `Palette.fetch/2`
returns `{:ok, module}` or `{:error, {:unknown_block_type, type_name}}`, and
never raises. Every consumer that walks a document walks it with the
unresolvable case as an ordinary arm: validation reports it as a finding
against a block id, the editor renders an unresolvable-block presentation
(sb-w50), and the compiler refuses with that block id named (sb-iwz). This
is the same discipline ADR-0001 decision 9 applied to decoding, and the same
shape upstream applies to loading untrusted persisted bytes (st-ADR-0052,
sp-ADR-0003 decision 4): an ordered check, one error arm per distinguishable
cause, nothing rescued to a default.

**4. Every callback is a pure function of its arguments.** No process
dictionary, no `Application.get_env/2`, no IO, no database, no clock, no
randomness. Given the same block and the same palette, a callback returns
the same answer forever. This is what lets validation run on every edit and
what lets sb-iwz promise a deterministic compile against a document hash.

A block type that genuinely needs external data at authoring time - a list
of the host's budget policies to populate a select, say - gets it by the host
resolving it *before* the operation and passing it in the palette entry's
own options, not by the callback reaching for it. That mechanism is not
specified here; what is specified is that the callback stays pure.

**5. The declaration surface: nine callbacks, five required.**

| Callback | Required | Owner of its return shape |
|---|---|---|
| `slots(config)` | yes | this record (decision 6) |
| `config_schema(config)` | yes | this record (decision 7) |
| `validate_config(config)` | yes | this record (decision 7) |
| `current_version()` | yes | this record (decision 8) |
| `emit(block, context)` | yes | sb-iwz |
| `io(config)` | no | sb-7rx |
| `migrate_config(from_version, config)` | no | this record (decision 8) |
| `fixtures()` | no | provisional (decision 9) |
| `palette_entry()` | no | sb-w50 |

Only the first four rows are this record's own contract. `emit/2` is listed
because the callback has to live somewhere and this is the module it lives
on; its signature is sb-iwz's. `palette_entry/0` is presentation metadata
rather than contract - a label, a description, a grouping, an icon name -
and this record fixes only that it hangs off the same module. What it
contains and how it renders is sb-w50's.

The required five are required because a block type that cannot say what
slots it has, cannot say what its config looks like, cannot reject bad
config, cannot say what version its config shape is at, or cannot compile is
not usable by any consumer in this package. The
optional ones each degrade cleanly: no `io/1` means assignability treats the
block as unconstrained (sb-7rx decides exactly how), no `migrate_config/2`
means the type has never changed its config shape, no `fixtures/0` means the
palette entry ships no executable examples, no `palette_entry/0` means the
editor falls back to the type name.

**6. `slots(config)` returns an ordered list of slot declarations, and
arity is one of four values.** A slot declaration is
`{name, arity, label}` - the name is the key under `slots` in the document
(ADR-0001 decision 5), the order is the order the editor presents them in,
and the label is human text.

Arity is a closed set:

| Arity | Meaning | Motivating case |
|---|---|---|
| `:any` | zero or more blocks | `core.sequence`'s `body`; a group's `interrupts` |
| `:at_least_one` | one or more | a branch arm that must do something |
| `:exactly_one` | exactly one | a wrapper that decorates a single child |
| `:zero_or_one` | at most one | an optional `otherwise` |

Four values, not a numeric range, because arity here exists to be *checked
and explained to an author*, and every additional expressible constraint is
another message the editor has to phrase and another rule a host can get
subtly wrong. Nothing in the core vocabulary needs "between two and five",
and a block type that thinks it does is describing a config-level constraint
(how many lanes) rather than a slot-level one.

Arity is a validation rule applied against the uniform document shape, never
a change to it - ADR-0001 decision 5 said exactly this, and this record
supplies the vocabulary. A document violating an arity still decodes; it
fails validation, with the offending block id and slot name named.

Two properties bind `slots/1` to the schema. **Declared slots are the
complete set**: a document block carrying a slot key its type does not
declare for that config is a validation finding (`:undeclared_slot`), not
silently ignored, because silently ignoring it loses children on the next
save. And **`slots/1` must be stable under config it accepts**: for any
config that `validate_config/1` accepts, `slots/1` returns without raising.
A type whose slot set depends on config the type itself rejects has no
defined shape for the editor to render mid-edit.

Changing a slot's name or arity is a breaking change to that block type's
contract, on the same footing ADR-0001 decision 5 put slot renames: the type
migrates its own documents.

**7. The config schema is a flat, declarative field list, and it is not a
validation language.** `config_schema(config)` returns an ordered list of
field declarations, each with a key, a field type, a label, a `required?`
flag, and a default. The closed field-type set is `:string`, `:integer`,
`:boolean`, `:select` (with choices), `:expression` (a predicator source
string, st-ADR-0004), `:duration` (an ISO-8601 string, since ADR-0001
decision 6 forbids floats), and `:list` of one of those.

*[Cross-reference added 2026-08-29. The wording above is unchanged and no
decision changes here.]* `:duration`'s stored form was widened by ADR-0005's
2026-08-29 amendment to its decision 9, accepted the same day (PR 91): a
predicator duration string (`1h30m`, `2d`, `3d8h`) is the primary spelling,
whichever spelling an author typed is stored verbatim, and ISO-8601 is the
pivot a compile canonicalises through before the attribute is emitted. That
record states in terms that this field-type set is untouched - `:duration` is
still one of the seven types and still holds a string - so read "an ISO-8601
string" above as naming the pivot rather than the only spelling `config` may
hold.

It takes `config` for the same reason `slots/1` does: a branch's schema
gains a condition field per arm as arms are added, and a select's choices
can depend on an earlier field's value. The editor re-derives the form after
every config change rather than caching it.

*(Amended 2026-08-27, operator ruling on sb-9cp.)* A field declaration's
`key` addresses `config[key]` by default - that relation was implied rather
than stated, and the editor reads and writes exactly there. A field whose
value lives elsewhere in the config declares it explicitly: the field
declaration gains an optional `value_path`, a list of keys and indexes from
the config root to the value (e.g. `["arms", 2, "cond"]`), and when present
the editor reads and writes through it instead of `config[key]`. The `key`
remains the field's identity - what findings anchor to (ADR-0005
decision 11) and what the form keys the control by - so `Core.Branch`'s
per-arm condition fields keep their slot-name keys and become editable
without the editor ever branching on a block type's internals. A
declaration without `value_path` behaves exactly as before.

The schema drives the editor's form and nothing else. It deliberately
expresses no cross-field rules, no conditional requirement, no numeric
bounds, and no regex - because a schema rich enough to express those becomes
a second validation implementation that must agree with the first, and the
disagreement always surfaces as a form that lets an author save something
the block type then rejects. So: **`validate_config/1` is the authority**,
returning `:ok` or `{:error, [finding]}` with each finding naming a config
key and a message. The schema is a rendering hint that happens to catch the
easy cases early.

Field types are a closed set for the same reason arities are: the editor
must be able to render every one of them, and an open set means a host can
declare a field the editor cannot draw.

**8. `type_version` migration is the block type's own business, and runs at
resolution time, not decode time.** ADR-0001 decision 4 gave each block a
`type_version` this layer never compares to anything. This record says who
compares it: the block type, through the optional
`migrate_config(from_version, config)` callback, called when a resolved
block's `type_version` is below the module's `current_version/0`.

Migration is applied to the in-memory block when it is resolved, and it is
*not* written back by this package. Persisting a migrated document is the
host's decision - it owns storage and the `revision` axis (ADR-0001 decision
7) - and a package that silently rewrote stored bytes on load would make
every read a write in a multi-tenant host. A block whose `type_version` is
*above* the module's current version is a typed resolution error
(`:block_type_too_new`), not a best-effort read: it means the code is older
than the data, and guessing there is how a rollback corrupts documents.

*(Amended 2026-08-27, operator ruling.)* Three semantics the original text
left open, fixed as shipped:

- A `migrate_config/2` call that returns `{:error, reason}`, and a module
  whose `type_version` is behind but does not export `migrate_config/2` at
  all, are a fourth typed resolution error,
  `{:error, {:migration_failed, block_id, reason}}` (the no-callback case
  carries `:no_migration_available`).
- Migration is a single hop, straight from the stored version to
  `current_version/0` - never a version-by-version ladder.
- The returned block's `type_version` is left as stored, never bumped, so
  an in-memory-migrated block can never be mistaken for one migrated on
  disk.

**9. Fixture bundles are optional, and this section is provisional.** The
brief asks that a palette entry be able to carry its own executable examples
- datasets plus expression fixtures, per sui-ADR-0003 and sui-ADR-0006 - so
that a host can show a "test this step" panel for one palette entry rather
than only for a whole chart.

This record fixes only the seam: `fixtures/0` is an optional callback
returning a fixture bundle for the block type, and a block type without it
ships no examples. **The bundle's own convention - how datasets and
expression fixtures are packaged and discovered per palette entry - is
sui-13q's to define, and sui-13q is open with no request up as of this
writing.** This package therefore does not invent a competing convention.
When sui-13q lands, this section is amended to cite it, and the return type
of `fixtures/0` is pinned to whatever it settles. Until then a host wiring
`fixtures/0` should expect the return shape to change.

*Amended (2026-08-26), and this decision is no longer provisional:* sui-13q
landed. The convention is statifier-ui's `docs/fixture-bundles.md`, and this
record adopts it whole rather than restating it - that page is the authority
on the bundle shape, and a disagreement between it and the summary below is
resolved in its favour. The three things this record now pins:

**9a. `fixtures/0` returns one of four spellings**, exactly the set that page
defines, and `StatifierUI.Fixtures.Bundle.load/3` is what reads it:

| Spelling | Recognized by |
|---|---|
| `%StatifierUI.Fixtures{}` | the struct |
| `%{scenarios: ..., events: ..., datasets: ..., expressions: ...}` | **atom** top-level keys |
| `%{"version" => 1, "datasets" => ...}` | **string** top-level keys |
| `"palette/budget_check.fixtures.json"` | a binary path |

The atom-versus-string top-level key is the whole discriminator: atom keys
are the Elixir spelling a host writes by hand in a module, string keys are
the JSON spelling that survives a file, and a map mixing the two is rejected
as `{:mixed_bundle_keys, name}` rather than guessed at. Unknown top-level
keys are ignored on the JSON spelling (the sidecar's forward-compatibility
discipline, sui-ADR-0006) and rejected on the Elixir spelling as
`{:unknown_bundle_key, name, key}`, because an unknown atom key is a typo in
code the author is looking at. A block type that implements no `fixtures/0`
at all is an absence, never an error.

**9b. The bundle is addressed by block type name.** A bundle carries the
fragment name it was loaded under, and for this package that name is the
`type_name` the palette resolves (decision 1) - the same string the document
stores. That is what lets a host discover the whole palette's examples at
once with `StatifierUI.Fixtures.Bundle.discover/2` over its palette map, and
what makes a failing expectation name the block type that drifted.

**9c. Discovery is per-entry, never all-or-nothing.** One palette entry's
malformed bundle is reported against that entry's name and every other entry
still loads; a `fixtures/0` that raises is caught the same way. This is the
same discipline decision 3 applies to resolution, arriving from the other
package for the same reason: one bad palette entry must not hide every good
one.

Read the callback table's `fixtures/0` row as owned by sui-13q rather than
"provisional", and the two PROVISIONAL comments in the worked example as
settled - the example's atom-keyed map was already one of the four
spellings, so nothing in it changes. The typespec block below keeps
`@callback fixtures() :: term()`, and that is not laziness: statifier-ui
names no single type for the union of the four spellings, and inventing one
here would be this package asserting a type it does not own. The authority is
what `StatifierUI.Fixtures.Bundle.load/3` accepts.

What this amendment does **not** do: it does not make `statifier_ui` a
required dependency of this package. Nothing here calls the loader. A host
that wants palette-entry test panels depends on `statifier_ui` itself, and a
host that does not can leave `fixtures/0` unimplemented and lose nothing.
Whether this package ever grows an optional dependency to validate bundles at
palette-construction time is sb-w50's question, not this record's.

**10. The core vocabulary, as answers to these callbacks.** ADR-0001
decision 10 listed the structural block types as the load its schema had to
carry. Here they are as block-type contracts. Their SCXML emission remains
sb-iwz's.

| Block type | `slots(config)` | Config schema | Notes |
|---|---|---|---|
| `core.sequence` | `[{"body", :any, "Steps"}]` | empty | the conventional document root |
| `core.branch` | one `arm_*` per declared arm, then `{"otherwise", :any, ...}` | `arms`: a list of `{slot name, condition expression}` (amended 2026-08-27: the full slot name, e.g. `arm_approved`, not a suffix - matching ADR-0001's worked-example bytes) | conditions are `:expression` fields |
| `core.parallel` | one `lane_*` per declared lane | `lanes`: a list of lane names | lane slots are `:any`; no ordering between them |
| `core.wait` | `[]` | `duration`: `:duration` | a leaf whose whole meaning is config |
| `core.resumable_group` | `[{"body", :any, ...}, {"interrupts", :any, ...}]` | `history`: `:select` of `shallow`/`deep` | the two-named-slots case |
| `core.on_event` | `[]` | `event`: `:string`; `outcome`: `:select` of `abandon`/`resume` (ratified 2026-08-27) | an interrupt handler, valid only inside an `interrupts` slot |
| `core.group` | `[{"body", :any, ...}, {"interrupts", :any, ...}]` | empty | ratified 2026-08-27: `core.resumable_group` minus the history mode - same slots, no config; a `resume` re-enters and the body restarts |

*(Ratified 2026-08-27, operator ruling.)* Three shipped facts this table
now records rather than leaves to moduledocs:

- The vocabulary is **seven** types - `core.group` above is the seventh,
  drawn so the `core.resumable_group` row is untouched.
- `core.on_event`'s `outcome` values are `"abandon"` (leave the group, do
  not come back) and `"resume"` (handle the event, re-enter the group).
  A third value is a `config_schema/1` change plus a `current_version/0`
  bump, not a document schema change.
- **The `statifier_blocks.` event-name prefix is reserved.** The interrupt
  protocol between a handler and its enclosing group is two package-owned
  events, `statifier_blocks.interrupt.abandon` and
  `statifier_blocks.interrupt.resume`, named in code by
  `StatifierBlocks.Core.Emit.interrupt_events/0`. A host block type joins
  the protocol by raising them; a host must not name its own events under
  the prefix. (ADR-0004's emitted-event vocabulary - `done.state.*` - is
  unchanged; these are raised events inside the emitted chart.)

`core.on_event`'s placement constraint is the one rule in this table that
`slots/1` cannot express, because it is a constraint on a block's *parent*,
not on its own children. It is a validation rule the core types carry, and
the general question - which block types may appear in which slots - is
assignability's, which is sb-7rx's record, not this one.

*Amended at acceptance (2026-08-26):* ADR-0003 answered that question by
subsuming this special case - the placement rule is carried by `io/1` kind
tags, in both directions, and the core types carry no separate validation
rule. Read this table's `core.on_event` row and the paragraph above as
"carried by `io/1`" per ADR-0003.

**11. What this record does not decide.** Named so that the next four
records do not have to re-derive the boundary:

- **Assignability (sb-7rx)** owns `io/1`'s return shape, what a type
  expression is, and the compatibility relation that decides whether a block
  may be dropped into a slot. This record only guarantees the declaration
  hangs off the block-type module and is a pure function of config.
- **The compiler and provenance map (sb-iwz)** own `emit/2`'s signature, the
  emit context, the SCXML subtree representation, state-id generation, and
  how emission is keyed back to block ids.
- **The editor (sb-w50)** owns `palette_entry/0`'s contents, how a config
  schema renders as a form, how validation findings are presented, and the
  unresolvable-block presentation decision 3 creates.
- **The document schema (ADR-0001)** owns everything about the stored bytes.
  Nothing in this record changes them, and `schema_version` stays at `1`.

## Consequences

- A host adds a palette entry by writing one module and adding one map
  entry. No configuration file, no boot-time registration, no recompile of
  this package.
- Because the palette is a value, tests construct one inline with a toy
  block type and exercise the whole validation and compile path with no
  global state to reset between tests. This is the same testability argument
  st-ADR-0051 made for its handler map, and it is why the acceptance example
  below is a self-contained module.
- Because every callback takes config rather than being a static
  declaration, a block type is more work to write than a struct would be:
  four functions minimum. That is the price of ADR-0001 decision 5, paid
  here rather than paid later as a schema migration when the first
  config-parameterized type arrives.
- The closed field-type set means the first host that wants a field this
  package cannot render files an issue against this package rather than
  shipping a renderer of its own. That is intentional: an open set makes the
  editor's completeness unprovable.
- Migration not being written back means a long-lived document can be
  migrated on every load until the host chooses to save it. Migrations must
  therefore stay cheap and idempotent.
- Two registries now exist in a host's mental model: the palette (authoring
  time, this record) and the invoke-handler map (runtime, st-ADR-0051). They
  are related only by string type names appearing in a block's config and in
  the emitted SCXML. Keeping them separate is deliberate - an authoring
  server that never runs a chart needs only the first - but a host wiring
  `myapp.authorize` must remember to do both, and a block type whose emitted
  invoke type has no registered handler fails at runtime with
  `error.execution` (st-ADR-0051 decision 1), not at authoring time. Naming
  that gap is sb-iwz's and sb-w50's to act on if either wants a lint.
- Pinning `fixtures/0` provisionally means one known future amendment to
  this record. It is scoped to decision 9 and touches no other decision.
  *Amended (2026-08-26): discharged. That amendment is decision 9's 9a-9c
  above, and it touched no other decision, as predicted.*

## The contract as typespecs

```elixir
defmodule StatifierBlocks.BlockType do
  @moduledoc """
  The authoring-time extension seam. A host implements this behaviour once
  per palette entry; this package ships only the `core.*` types.

  Every callback is a pure function of its arguments (ADR-0002 decision 4).
  """

  alias StatifierBlocks.Block

  @type slot_arity :: :any | :at_least_one | :exactly_one | :zero_or_one

  @typedoc "Name, arity, human label. Order is presentation order."
  @type slot_decl :: {Block.slot_name(), slot_arity(), String.t()}

  @type field_type ::
          :string
          | :integer
          | :boolean
          | {:select, [{value :: String.t(), label :: String.t()}]}
          | :expression
          | :duration
          | {:list, field_type()}

  @type field_decl :: %{
          key: String.t(),
          type: field_type(),
          label: String.t(),
          required?: boolean(),
          default: Block.json()
        }

  @typedoc "Names the offending config key; message is author-facing."
  @type finding :: {key :: String.t(), message :: String.t()}

  @doc "Slots this block carries given this config. ADR-0001 decision 5."
  @callback slots(Block.config()) :: [slot_decl()]

  @doc "Ordered form fields for this config. A rendering hint, not the authority."
  @callback config_schema(Block.config()) :: [field_decl()]

  @doc "The authority on config validity (ADR-0002 decision 7)."
  @callback validate_config(Block.config()) :: :ok | {:error, [finding()]}

  @doc """
  Emits this block's SCXML subtree. Signature and context shape are
  sb-iwz's; this record fixes only that the callback lives here and is pure.
  """
  @callback emit(Block.t(), context :: term()) :: {:ok, term()} | {:error, term()}

  @doc "Type expressions for assignability. Return shape is sb-7rx's."
  @callback io(Block.config()) :: term()

  @doc "The version this module's config shape is at. ADR-0001 decision 4."
  @callback current_version() :: pos_integer()

  @doc "In-memory upgrade; never written back by this package (decision 8)."
  @callback migrate_config(from :: pos_integer(), Block.config()) ::
              {:ok, Block.config()} | {:error, term()}

  @doc "Executable examples for this palette entry. PROVISIONAL - see decision 9."
  @callback fixtures() :: term()

  @doc "Palette presentation metadata. Contents are sb-w50's."
  @callback palette_entry() :: map()

  @optional_callbacks io: 1, migrate_config: 2, fixtures: 0, palette_entry: 0
end

defmodule StatifierBlocks.Palette do
  @moduledoc "A caller-supplied value, never global state (ADR-0002 decision 2)."

  alias StatifierBlocks.Block

  # assignability added 2026-08-27: ADR-0003 decision 6 puts the host's
  # widening relation on the palette; this appendix predated that record.
  @type t :: %__MODULE__{
          types: %{optional(Block.type_name()) => module()},
          assignability: module() | nil
        }

  defstruct types: %{}, assignability: nil

  @doc "Total; never raises (ADR-0002 decision 3)."
  @spec fetch(t(), Block.type_name()) ::
          {:ok, module()}
          | {:error, {:unknown_block_type, Block.type_name()}}

  @doc """
  Resolves and, if needed, migrates in memory. `:block_type_too_new` when the
  block's `type_version` exceeds the module's `current_version/0`;
  `:migration_failed` when `migrate_config/2` fails or is not exported
  (amended 2026-08-27, per decision 8's amendment).
  """
  @spec resolve(t(), Block.t()) ::
          {:ok, module(), Block.t()}
          | {:error, {:unknown_block_type, Block.type_name()}}
          | {:error, {:block_type_too_new, Block.id(), pos_integer()}}
          | {:error, {:migration_failed, Block.id(), term()}}
end
```

## Worked example: one block type exercising every callback

A budget-check step in a multi-tenant host embedding the engine. It checks
a card transaction against the account's budget policy, writes the decision
to the datamodel, and offers an optional review slot whose contents run when
the amount is above a configured ceiling. It is deliberately the smallest
type that needs config-parameterized slots, a migration, and a non-trivial
cross-field rule.

```elixir
defmodule MyApp.Blocks.BudgetCheck do
  @behaviour StatifierBlocks.BlockType

  @impl true
  def current_version, do: 2

  # Config-parameterized: the review slot exists only when the author asked
  # for one. Turning the flag off in the editor removes a slot, which is a
  # document edit (sb-w50), not a silent drop.
  @impl true
  def slots(%{"review_above" => ceiling}) when is_integer(ceiling),
    do: [{"review", :at_least_one, "If the amount is above the ceiling"}]

  def slots(_config), do: []

  @impl true
  def config_schema(config) do
    [
      %{key: "policy", type: {:select, [{"standard_v3", "Standard policy v3"},
                                        {"corporate_v1", "Corporate policy v1"}]},
        label: "Policy", required?: true, default: "standard_v3"},
      %{key: "assign_to", type: :string, label: "Write decision to",
        required?: true, default: "decision"},
      %{key: "timeout", type: :duration, label: "Timeout",
        required?: false, default: "PT30S"}
    ] ++ review_fields(config)
  end

  defp review_fields(%{"review_above" => _}),
    do: [%{key: "review_above", type: :integer, label: "Review above",
           required?: true, default: 50}]

  defp review_fields(_), do: []

  # The authority (decision 7). The schema above cannot express "the ceiling
  # must be in 0..100" or "assign_to must be a bare identifier", and
  # deliberately does not try.
  @impl true
  def validate_config(config) do
    findings =
      []
      |> check_policy(config)
      |> check_assign_to(config)
      |> check_ceiling(config)

    if findings == [], do: :ok, else: {:error, Enum.reverse(findings)}
  end

  defp check_policy(f, %{"policy" => p}) when p in ["standard_v3", "corporate_v1"], do: f
  defp check_policy(f, _), do: [{"policy", "pick a policy"} | f]

  defp check_assign_to(f, %{"assign_to" => a}) when is_binary(a) do
    if Regex.match?(~r/\A[a-z][a-z0-9_]*\z/, a),
      do: f,
      else: [{"assign_to", "must be a bare lowercase identifier"} | f]
  end

  defp check_assign_to(f, _), do: [{"assign_to", "required"} | f]

  defp check_ceiling(f, %{"review_above" => n}) when is_integer(n) and n in 0..100, do: f
  defp check_ceiling(f, %{"review_above" => _}),
    do: [{"review_above", "must be an integer from 0 to 100"} | f]

  defp check_ceiling(f, _), do: f

  # sb-7rx owns what these terms mean; this module only declares them.
  @impl true
  def io(_config), do: %{consumes: ["myapp.transaction"], produces: ["decision"]}

  # sb-iwz owns the context and the subtree representation. What the type
  # promises here is that the emitted subtree invokes `myapp:budget_check` - the
  # runtime handler for which the host registers separately, per
  # st-ADR-0051.
  @impl true
  def emit(%StatifierBlocks.Block{config: config} = block, context) do
    MyApp.Blocks.BudgetCheckEmitter.emit(block, config, context)
  end

  # v1 spelled the target key `field`; v2 spells it `assign_to`.
  @impl true
  def migrate_config(1, config) do
    {value, rest} = Map.pop(config, "field", "decision")
    {:ok, Map.put(rest, "assign_to", value)}
  end

  def migrate_config(from, _config), do: {:error, {:no_migration_from, from}}

  # PROVISIONAL (decision 9): the bundle convention is sui-13q's, unshipped.
  @impl true
  def fixtures do
    %{
      datasets: %{
        "within-budget" => %{"transaction" => %{"amount" => 120, "currency" => "USD"}},
        "over-budget" => %{"transaction" => %{"amount" => 940, "currency" => "USD"}}
      },
      expressions: %{
        "needs_review" => %{
          "source" => "amount > 500",
          "expect" => %{"within-budget" => false, "over-budget" => true}
        }
      }
    }
  end

  @impl true
  def palette_entry,
    do: %{label: "Budget check", group: "Authorization",
          description: "Checks a transaction against the account's budget."}
end
```

Registered, and used:

```elixir
palette = %StatifierBlocks.Palette{
  types:
    Map.merge(StatifierBlocks.Palette.core(), %{
      "myapp.budget_check" => MyApp.Blocks.BudgetCheck
    })
}

# A block stored at type_version 1 resolves and migrates in memory only.
{:ok, MyApp.Blocks.BudgetCheck, block} = StatifierBlocks.Palette.resolve(palette, stored_block)
block.config["assign_to"]
#=> "decision"

# The slot set follows the config, per ADR-0001 decision 5.
MyApp.Blocks.BudgetCheck.slots(%{"policy" => "standard_v3", "assign_to" => "decision"})
#=> []

MyApp.Blocks.BudgetCheck.slots(%{"policy" => "standard_v3", "assign_to" => "decision",
                                 "review_above" => 50})
#=> [{"review", :at_least_one, "If the amount is above the ceiling"}]

# A palette entry the host removed still resolves to a value, not an exception.
StatifierBlocks.Palette.fetch(palette, "myapp.retired")
#=> {:error, {:unknown_block_type, "myapp.retired"}}
```

What this example is chosen to demonstrate:

- **Every callback, including the optional four.** The acceptance property
  for this record is that a toy type can implement all of them without
  reaching outside its arguments.
- **Config-parameterized slots (ADR-0001 decision 5).** `slots/1` returns a
  different set for the same type depending on one config key, and the
  editor must re-derive rather than cache.
- **The schema/validation split (decision 7).** `config_schema/1` renders a
  form; the "0 to 100" rule and the identifier rule live only in
  `validate_config/1`, so there is exactly one authority to disagree with.
- **In-memory migration (decision 8).** `migrate_config/2` renames a config
  key on resolve, and nothing writes the document back.
- **The two-registry seam.** `emit/2` produces a subtree naming
  `myapp:budget_check`; a handler for that invoke type is registered with the
  engine at runtime under st-ADR-0051, by the same host, separately.

---

## Amendment (2026-08-28): outcomes, presentation metadata, the invoke row, and who owns a label

**Status: accepted (2026-08-29, operator ruling).** Drafted 2026-08-28 as a
proposed amendment; the operator accepted it in full on 2026-08-29, including
the two-declaration reading of D13, the `{name, label}` outcome-declaration
shape, and the editor-owned-fields generalization of decision 7. This section
is additive: nothing above it is edited, and every earlier accepted decision
stands as written. It amends decision 5's
callback table, decision 7's schema ownership, decision 10's vocabulary table
and decision 11's boundary list, and it does so in one section because the
four are one seam seen from four sides: what a block type declares about
itself.

It is drafted from two sources and invents as little as it can get away with.
The operator's 2026-08-28 ruling (umbrella `docs/decisions.md` D13) settles the
authoring model; the campaign-012 editor spike (`spike/`) supplies working
forms for everything D13 left to a record. Where the spike already does
something, this section records what it does rather than proposing a better
name for it.

### What forces the amendment

**D13: outcome paths are slots, never ports.** A block has one inlet and one
outlet; a block with more than one way to finish declares a *slot* per
alternative path, and each outcome compiles to a distinct completion event.
Ports - several typed outputs with author-drawn edges - were rejected because
they break the invariant the editor rests on: every edge in a document is a
parent/slot/child relationship, so connectors are rendered and never authored.

D13 lands on two records at once, and they have already been separated. The
**emission** is ADR-0004's, and its own amendment of the same date, also
accepted 2026-08-29 (`docs/adr/0004-compiler-provenance.md`, "decision 2,
outcome-tagged finals"), holds it: outcome-tagged finals, `Context.outcome_id/2`, the reserved `o_`
role namespace, and the completion event a parent wires on. That section
explicitly parks the declaration surface here - "where the declaration surface
lives is not this record's call" - and this section is the answer. Nothing
below restates what that amendment decides, and where the two touch, it is the
authority on emission and this one is the authority on declaration.

The rest is what four beads of spike work found by rendering real cards: a
block type that can name a token but not a chip, a join marker whose words no
type could supply, an invoke whose failure path had a slot and no compiled
target, and every card in the flagship demo titled by a key no `core.*` type
declares.

### A. `outcomes(config)`, an ordered list, defaulting to one

**A1. The callback.** A block type may declare its outcomes:

| Callback | Required | Owner of its return shape |
|---|---|---|
| `outcomes(config)` | no | this section |

It takes `config` for decision 5's reason and no other: a type whose
alternative paths are config-parameterized - one outcome per declared arm,
say - is the same shape `slots/1` and `config_schema/1` already have, and a
callback that took no config would be the one declaration in this record that
could not follow the config. A type that does not export it has exactly one
outcome, named `done`. All seven accepted `core.*` types are in that case and
none of them changes meaning.

An outcome declaration is `{name, label}`: the name is what the compiled event
carries, and the label is human text on the same footing as a slot
declaration's. Names match `~r/\A[a-z][a-z0-9_]*\z/` and the order is fixed,
both because ADR-0004's amendment needs them to be - the first for the role
shape it mints ids under, the second for its byte determinism.

`outcomes/1` is stable under config `validate_config/1` accepts, and returns
without raising there, for the reason decision 6 binds `slots/1` the same way:
the editor renders mid-edit and the compiler runs against config the type has
already accepted.

**A2. A slot is not an outcome, and this record does not marry them.** D13's
sentence - outcomes are slots - is about the *authoring surface*, and it is
honoured by section D below: `core.invoke`'s failure path is an `on_error`
slot with `zero_or_one` arity and a `:failure` slot style, which is machinery
`core.group`'s `interrupts` rail already provides and the renderer already
reads without learning a type name. [Correction 2026-08-29, sb-4kh: was "a
`secondary` slot style". ADR-0005 amendment 10g, accepted 2026-08-29, names the
`on_error` rail `slot_style: :failure` and has `core.invoke` declare
`slot_style: %{"on_error" => :failure}`. The claim this paragraph makes - that
the rail is existing renderer machinery and needs no type name - is unchanged;
10h derives rail placement from the rail partition, `:secondary` and `:failure`
alike.] It is not a claim that the two
declarations are one list. They answer different questions: `slots/1` says
where children live, `outcomes/1` says how finishing can differ, and a type
can have either without the other. `core.branch` has many slots and one
outcome; a type could declare a second outcome reached from no slot at all.

**Which outcome a given slot's completion reaches is deliberately not a third
declaration.** It is the block type's own emission - `emit/2`, under ADR-0004's
amendment - and pushing it into a declaration would mean this record inventing
a binding language for a relation exactly one shipped-adjacent type currently
has. The alternative was considered: an outcome declaration carrying the slot
name it is reached from, which would let a validator check that every declared
outcome is reachable and let the editor caption a slot with the outcome it
leads to. Both are real, and neither is worth a guessed shape today. Recorded
as a deferred question in section F rather than decided.

### B. The presentation metadata trio, and the boundary it sits on

The spike's palette entries carry three keys the accepted record does not
know about: `accentToken` (a `--sb-*` custom-property *name*), `badge` (a short
chip for the card header), and `joinLabel` (what the join marker under a
side-by-side arrangement says, as a **function of config**). In the Elixir
surface they are `accent_token`, `badge` and `join_label`, following the
spelling ADR-0005's own 14d amendment already uses for the first of them.

**B1. The contents of `palette_entry/0` are not this record's, and stay not
this record's.** Decision 5 says so and decision 11 repeats it: what the
metadata map contains is ADR-0005 decision 10's, and `accent_token` is already
proposed there (14d). This section does not adopt the trio into decision 10 on
that record's behalf, and a host reading only this section learns nothing about
what the editor draws.

**B2. What this record does own is that two of the three are inert data and the
third is code.** `accent_token` and `badge` are values; `join_label` is a
callback the editor invokes during layout with the block's config. That makes
it the first executable thing to hang off a palette entry, and decision 4
therefore applies to it in full: **`join_label` is a pure function of its
argument.** No process dictionary, no `Application.get_env/2`, no IO, no clock.
A host that needs external data to phrase a join marker resolves it before the
operation, exactly as decision 4 already requires of every other callback.

This is the whole reason the trio needs a sentence in *this* record rather than
only in ADR-0005. Every other key decision 10 owns is inert, so the purity rule
had nothing to bite on; one callback changes that.

**B3. Normalizer semantics: refuse, do not truncate; a throw degrades to the
default.** Every consumer reads these three through a total normalizer, and the
discipline is decision 3's, arriving at presentation for decision 3's reason: a
malformed declaration in one host's registry must produce the ordinary card,
never a broken one and never an exception.

| Declaration | Malformed reads as | Refusals |
|---|---|---|
| `accent_token` | `nil`, meaning the editor's own accent | anything not matching an anchored `--sb-` custom-property name |
| `badge` | `nil`, meaning no chip | a non-string, empty or all-whitespace, a newline or tab, or longer than the cap |
| `join_label` | the editor's own word | the same set, applied to the callback's **return**; plus a non-function, plus a callback that raises |

Two properties are the point of the table, and both are the spike's behaviour
rather than a proposal:

- **Refuse, never truncate.** An over-long badge is dropped, not clipped to the
  cap; a badge containing a newline is dropped, not collapsed to a space. A
  truncated chip reads as a rendering bug the host will file against the
  editor, where a missing chip reads as the declaration it is. This is the
  same posture decision 7 takes toward config the schema cannot express: refuse
  the input, do not silently repair it.
- **A callback that raises degrades to the default.** `join_label` is host code
  called inside the editor's layout pass, so it is called inside a rescue and a
  raise produces the editor's own word. A host type with a bug in its
  `join_label` gets an ordinary join marker; it does not take the canvas down.
  That is a deliberate exception to the "nothing rescued to a default" rule
  this package otherwise keeps, and it is bounded to exactly this callback:
  the value being defaulted is one word of chrome, and the alternative is a
  blank editor. `validate_config/1`, `slots/1`, `emit/2` and every other
  callback keep the rule unweakened.

The cap itself is a number ADR-0005 decision 10 should carry rather than this
record; the spike's is 24 characters for both the badge and the join marker,
chosen so that "calls the host" and "timer" fit and a sentence does not.

### C. Who owns a block's label

Two different things are spelled `label`, and the spike found the confusion the
hard way: both `core.invoke` cards in the flagship demo render as "Invoke"
while the fixtures pane says "Authorize the card" about the same card.

- **A palette entry's `label` names the TYPE.** It is what the palette browser
  and the "+" picker show, it defaults to the type name when a type declares
  none, and it is ADR-0005 decision 10's.
- **A block's label names THIS BLOCK.** It is the author's own words for one
  card, it is per-block data, and it therefore lives in `config`.

**C. The block label is editor-owned and editor-injected, not type-declared.**
The editor injects an optional `label` field into every block type's config
schema; a block type declares none, and one that declares one today migrates it
away. This amends decision 7's implication that `config_schema/1`'s return is
the complete field list a form renders: it is the complete list of the fields
the *type* owns, and the editor may prepend fields it owns for every type.

The universal form is the operator's 2026-08-28 ruling, and the reasoning is
that the per-type alternative guarantees the gap recurs. Every card titles
itself from its label; a type that forgets to declare the field is a card
titled by its type name, which is a defect no reviewer catches because the
card still renders. Making it a per-type declaration is asking every host,
forever, to remember a field that has the same meaning in every type that has
ever existed.

The implementation of this - the injection, the inspector control, and
migrating the demo types that declare their own - is sb-jvz's, and is not this
record's to describe. What is recorded here is only the contract half: `label`
in a block's config is the editor's field, and a block type neither declares it
nor validates it.

### D. Two additions to the core vocabulary, and two held back

Decision 10's table lists seven types. This section proposes two more, both
built and exercised in the spike as descriptors registered through the
caller-supplied palette decision 2 already provides:

| Block type | `slots(config)` | Config schema | `outcomes(config)` | Notes |
|---|---|---|---|---|
| `core.invoke` | `[{"on_error", :zero_or_one, "If it fails"}]` | `invoke_type`: `:string`; `assign_to`: `:string`; params (see below) | `done` and `error` | names an invoke type, never runs one - decision 2's two-registry seam |
| `core.raise` | `[]` | `event`: `:string` | default (`done`) | a leaf that raises one event for an enclosing group's interrupt rail |

**D1. `core.invoke`'s failure path is a slot, and its compiled target is
ADR-0068's.** The `on_error` subtree is the target of a transition on
statifier-ex ADR-0068's `error.communication.invoke.<invoke_id>` - the accepted
upstream name, a blessed suffix extension of the `error.communication` that
st-ADR-0051 decision 1 already assigns to this failure, with `<invoke_id>` the
emitted invocation's own id. Two properties come free from upstream's choice
and both matter here: a host chart already listening for `error.communication`
catches the failure with no edit, by SCXML's descriptor prefix rule, and a
chart naming the full event parks one invocation alone.

An **absent `on_error`** emits no such transition at all and the error
propagates as it does today. That is what makes the slot optional in fact and
not only in arity, and under ADR-0004's amendment it costs a parent nothing: a
parent may wire an outcome whose final was never emitted and the transition
simply never fires.

The emission itself - the `<invoke>`, the transition, and how the `on_error`
subtree's completion reaches the error outcome's final - is ADR-0004's, and its
amendment of this date works that example through in full. This row states only
what the type *declares*.

`core.invoke`'s params field is the one place the vocabulary is knowingly
provisional: decision 7's field types are a closed set and none of them is "a
list of name/path pairs", so the spike flattens the pairs into a `:string`, one
`name=path` per line. That is a compromise that proves the type's shape without
also proposing an editor feature, and whichever way it is resolved - a new
field type, a dedicated control, or the flattening as shipped - is a decision 7
change rather than a change to this row.

**D2. `core.raise`'s send is a name, not a port.** A raise names an event and
hands control on; the send-to-catch relationship is deliberately not an edge in
the document but two blocks naming the same string, with the enclosing group's
rail as where the catch lives. That is D13's answer arrived at from the other
side, and it protects the same invariant: a port pointing at the handler it
wakes would have been the first hand-drawn edge in a document, and a
cross-subtree one at that.

Whether the emission is `<raise>` or a zero-delay `<send>`, and whether a raise
may carry a payload, are both open and both ADR-0004's; the second additionally
needs decision 7's field-type set to grow, which is why neither is settled
here.

**D3. Two demo types are deliberately NOT promoted.** The spike also carries
`myapp.guarded_on_event` and `myapp.timeout_rule`, and an earlier reading of the
spike would have promoted all four. They are held back because the interrupt
rail covered their demo use cases: a guarded event handler and a timeout rule
are `core.on_event` and `core.wait` inside a group's `interrupts` slot, with
the guard as a condition, and promoting them would put two types into the core
vocabulary whose whole content is a spelling of an arrangement the vocabulary
already expresses. They stay host types in `demo-types.js`, which is exactly
what the extension seam is for, and they remain the best evidence that it
works.

### E. Consequences

- The callback table grows by one optional row, and every existing block type
  keeps working unchanged: no `outcomes/1` means one outcome named `done`,
  which is the accepted behaviour spelled out.
- The core vocabulary goes from seven types to nine. Both additions are
  structural in the sense decision 10 uses - neither knows a host's domain -
  and `core.invoke` is the first `core.*` type that names an invoke type,
  which makes decision 2's two-registry seam something the shipped vocabulary
  demonstrates rather than only describes.
- `join_label` puts host code on the layout path for the first time. The purity
  rule covers correctness and the rescue covers robustness; what neither covers
  is cost, and a `join_label` that is expensive is a slow canvas. Naming that
  is enough for now: the callback is called once per rendered join marker.
- Adopting this and ADR-0004's amendment together moves compiled bytes for
  every document, because the default outcome's final id changes. That is
  ADR-0004's decision 6 obligation and is stated there; it is noted here only
  so a reader of this record is not surprised by it.
- The label injection means `config_schema/1`'s return is no longer the whole
  form. A host reading the callback's return to build its own form - which
  nothing in this package does, but a host might - gets the type's fields and
  not the editor's.

### F. Deferred questions, named rather than guessed

- **Does an outcome declaration bind to a slot?** Section A2's rejected
  alternative. Deciding yes would buy a reachability check and a slot caption;
  deciding no keeps the binding in `emit/2` where the spike has it. Both
  produce the same emission, so ADR-0004's amendment stands either way.
- **Does the trio join ADR-0005 decision 10's metadata, and is a callback
  allowed there at all?** That record's call, and its 14d amendment already
  asks the operator half of it for `accent_token`. `join_label` sharpens the
  question, because every other key decision 10 owns is inert data.
- **Where does the badge/join-marker length cap live?** A number in this record
  would be visual opinion in the wrong place; a number in no record is a
  constant two implementations can disagree about.
- **`core.invoke`'s params field**, per D1.
- **`core.raise`'s emission and payload**, per D2.

---

## Amendment (2026-08-29): decision 7, an optional `datamodel_path?` key

**Status: accepted (2026-08-29, unqualified direction-agent verdict under the operator campaign-015 grant, PR 90).** Additive;
decision 7 and its 2026-08-27 `value_path` amendment both stand exactly as
written, and no text above this line is edited by this section.

### Context

The editor needs to know which config fields hold datamodel paths, because a
path is the one field value it can check against something outside the
document: a host-supplied datamodel. ADR-0005's amendment of the same date
fixes what that check produces (an `:info` finding anchored on the field's
`key`, only when the host supplies a datamodel). It cannot say which fields to
check, because that is a block type's claim about its own config, and decision
7 owns those.

### Decision

One sentence is added to decision 7: **a field declaration may carry an
optional `datamodel_path?: true` key beside `value_path`, declaring that the
field's value is a path into the host's datamodel.**

What that sentence deliberately is not:

- **Not a new field type.** Decision 7's type set - `:string`, `:integer`,
  `:boolean`, `:select`, `:expression`, `:duration`, and `:list` of one of
  those - stays closed. A datamodel-path field is a `:string` that carries one
  more claim about itself; adding a `:path` type would give the editor a second
  control to render for what is textually identical input.

  *[Note added 2026-09-05, with `sb-5v3i` under campaign-031 ruling D31-4.
  This bullet is reversed, and only this bullet: decision 7's set gains
  `{:path, opts}` by the amendment of this date at the end of this record.
  The sentence above is true of the input's bytes and not of what an author
  can do with them. A `:string` carrying `datamodel_path?: true` gets
  ADR-0005 clause 11e's undeclared-path advisory and no candidate list; a
  host block type that never learns the key gets neither, because `:string`
  is the whole answer the field-type set gives it, and its declaration says
  nothing is missing. The package's own vocabulary already shows the gap -
  `core.subchart`'s `assign_to` holds a path as a bare `:string`
  (`lib/statifier_blocks/core/subchart.ex:197-203`) while `core.assign`'s
  `path` carries the key (`lib/statifier_blocks/core/assign.ex:73-79`). And the
  candidates
  now exist to render: `StatifierBlocks.Datamodel.candidates/3`
  (`lib/statifier_blocks/datamodel.ex:380-387`) computes them, and what the
  editor's control table is keyed on is the field type. The `path_kind`
  bullet below is **not** reversed, and neither is this key withdrawn; the
  amendment says what the two spellings mean to one another.
  `core.subchart`'s `assign_to` migrates on `sb-2ym4`.]*
- **Not a `path_kind` enum.** A boolean is what the ruling admits. There is one
  kind of path today, and an enum would be a vocabulary invented ahead of its
  second member.
- **A boolean, on the `required?: boolean()` convention** decision 7 and the
  typespec appendix already establish. It reads the same way and needs no new
  spelling.

A declaration without the key behaves exactly as before, as with `value_path`.
The key is orthogonal to `value_path`: one says where the value lives, the
other says what the value means, and a field may carry both, either, or
neither.

**First consumer: `core.assign`'s `path` field.** Its decision-10 vocabulary row
is a sibling change and not this section's. Signup wizard, for the shape: an
assign block writing `signup.variant` declares its `path` field with
`datamodel_path?: true`, and the editor checks that value against the supplied
datamodel and anchors any advisory on the `path` key.

### Consequences

- One optional key on one map. Every existing declaration is unchanged and
  every existing consumer keeps working, because absence means what it meant
  before.
- The type set stays closed, which is what keeps the editor's control table
  finite - the property the closed set exists for.
- The schema is still not a validation language. The key declares what a value
  is, not what it must be; `validate_config/1` remains the authority per
  decision 7, and the datamodel check produces an advisory that changes no
  verdict, per ADR-0005.
- A boolean forecloses nothing. If a second kind of path ever appears, it
  arrives as its own key or as a widening amendment, with a real second member
  to name.

---

## Amendment (2026-08-29): the `core.assign` row on decision 10

**Status: accepted (2026-08-29, unqualified direction-agent verdict under the operator campaign-015 grant, PR 98).** The 2026-08-28
amendment's section D promoted `core.invoke` and `core.raise` and stopped
there, so `core.assign` - built in the campaign-013 spike, shipped in
campaign 014, and registered in `StatifierBlocks.Palette.core_types/0` - has
been running with no row in decision 10's vocabulary table and a
`PROVISIONAL` admonition in its moduledoc saying so. The operator's ruling of
this date is that the type is in the shipped vocabulary and is owed the row.

This section is additive. Nothing above it is edited: decision 10's original
seven-row table stands, section D's two-row table stands, and D2's parked
questions about `core.raise`'s emission and payload are untouched by this
record.

### G. `core.assign` joins the core vocabulary

| Block type | `slots(config)` | Config schema | `outcomes(config)` | Notes |
|---|---|---|---|---|
| `core.assign` | `[]` | `path`: `:string`; `value`: `:string` | default (`done`) | a leaf that assigns one value to one datamodel path, emitting `<assign>`; `validate_config/1` checks shape only |

The row is read off the shipped `StatifierBlocks.Core.Assign`, not off the
spike proposal that preceded it. In full, so a reader need not open the
module: `slots/1` returns `[]` for every config; `config_schema/1` returns
exactly two field declarations, `path` (label "Write to") and `value` (label
"This literal"), both `:string`, both `required?: true`, both defaulting to
`""`; there is no `outcomes/1`, so section A's default applies and the type
has the single outcome `done`; `io/1` is `%{kinds: [:step]}`, one outcome and
nothing consumed through the type flow; `current_version/0` is `1`.

With this row the table records **ten** types: the seven of decision 10, the
two of section D, and this one. `StatifierBlocks.Palette.core_types/0`
registers **eleven** - `core.send` is the difference, shipped in the same
campaign and under the same `PROVISIONAL` admonition, and still owed a row of
its own. That gap is named here rather than closed, because a row is written
off a ruling and this record carries one ruling.

**G1. `validate_config/1` checks shape only, and that is the whole rule.**
The callback refuses an empty or whitespace-bearing `path` and an empty
`value`, and stops there. Whether the path is *declared* is a document-level
pass over the whole tree, not this callback's business - `validate_config/1`
is handed a config and has no document to answer the question against - and
the type's own moduledoc is where that boundary is spelled out. The `path`
check is deliberately not a dotted-identifier grammar either: this package
does not own the datamodel path grammar, and a regex here that accepted
`signup.variant` while refusing something a host legitimately declares would
be a second, quieter proposal riding along with this row.

**G2. `value` is `:string` in the shipped type, and stores source text.**
The ruling anticipated an `:expression` field, and the shipped module is
narrower on purpose: `value` holds the literal exactly as an author typed it
- `true`, `42`, `"control"`, quotes included for a string - which is what
lets it land in the compiled `expr` attribute unchanged. Expressions computed
from datamodel state are explicitly not supported in V1, because which
expression language, how it would be stored, and whether a block document may
carry an expression that must be evaluated to compile are jointly
predicator-ex's and statifier-ex's calls. Widening `value` to `:expression`
is therefore a later change to this row, not a correction of it, and it
arrives with those answers rather than ahead of them.

**G3. `path` and decision 7's `datamodel_path?` key.** The amendment of this
date above this one - "decision 7, an optional `datamodel_path?` key", drafted
on sb-1ba - admits that optional field key, and it is the key a field like
this one exists to carry: a `:string` whose values are datamodel locations
rather than free text, so an editor can offer what the document's datamodel
declares instead of a bare text box. That sentence is that section's, cited
here and not restated. The shipped `path` declaration does **not** yet set
the key - it is `%{key: "path", type: :string, label: "Write to", required?:
true, default: ""}` and nothing more - so this row records the field as
shipped. Setting `datamodel_path?: true` on it is a one-key change to
`config_schema/1` with no `current_version/0` bump behind it, and it is named
here so that it is picked up deliberately rather than discovered.

**G4. What it compiles to.** A compound state whose entry writes `expr` to
`location` and immediately goes final. A signup wizard recording which
variant an arriving author was bucketed into:

```xml
<state id="s_blk_ASN" initial="s_blk_ASN__done">
  <onentry><assign expr="&quot;control&quot;" location="signup.variant"/></onentry>
  <final id="s_blk_ASN__done"/>
</state>
```

Both attribute values are annotated back to the config fields they came from
- `location` from `"path"`, `expr` from `"value"` - per ADR-0004 decision 9:
the `<assign>` element is the block's own, but each attribute *value* is the
author's. The emission itself is ADR-0004's, and this row states only what
the type declares.

**G5. What stays open.** What an assign to an undeclared datamodel location
means, and how the write is ordered against a state's other `onentry`
content, are both statifier-ex's and both still open. Neither blocks the row:
a vocabulary table records what a type declares, and a type whose declared
shape is settled belongs in it whether or not the engine has finished
answering what a host can do to itself with it.

---

## Amendment (2026-08-29): decision 7, an optional `sensitive?` key, and the secrets rule behind it

**Status: accepted (2026-08-29, unqualified direction-agent verdict under the operator campaign-015 grant, PR 99).** Additive; decision 7, its 2026-08-27
`value_path` amendment and the accepted 2026-08-29 `datamodel_path?`
amendment above all stand exactly as written, and no text above this line is
edited by this section. It sits beside the `datamodel_path?` section because
it annotates the same surface - a field declaration - and because the two keys
are read together: one says a field's value is a datamodel path, this one says
what may be true of the path it names.

### Context

**The rule, first, because the key exists only to serve it: credentials, API
keys and other secrets never enter a chart datamodel.** A secret is referenced
by an identifier and fetched by the invoke handler at effect time. The
datamodel carries the identifier; it never carries the value.

The reason is that encryption at rest answers one leak surface and there are
several. A value that lives in a datamodel also flows into:

- **traces** - the execution record a session leaves behind;
- **telemetry** - measurement events emitted as the chart runs;
- **job payloads** - the serialized state a durable step hands to a queue;
- **the editor's fixtures and truth tables** - authoring artifacts that are
  written down, shared, and checked in;
- **LiveView diffs** - the wire updates the editor pushes to a browser.

Encrypting storage covers the first surface a reader thinks of and none of
these five. They are not defects to be fixed one at a time either: each of
them exists because someone wanted the datamodel visible, which is exactly
what a datamodel is for. The only durable answer is that the value is not
there to be seen.

That is a rule about hosts, not about this package. This package emits SCXML
and never sees a value. What it can do is refuse to compile a document that
would carry a value it has been told is a secret into a position where one of
those five surfaces would read it - and to do that it needs the host to have
said which paths those are. Hence a key.

### Decision

**A declared datamodel path may carry `sensitive?: true`.** It is a boolean,
on the same convention `required?: boolean()` and `datamodel_path?: true`
already establish, and it is read the same way: absent means what absence
meant before, and a declaration without it behaves exactly as it does today.

What it deliberately is not:

- **Not a field type.** Decision 7's type set stays closed for the reason the
  `datamodel_path?` section gives: a sensitive path is textually a path, and
  a `:secret` type would give the editor a second control to render for
  identical input. The closed set is what keeps the control table finite.
- **Not encryption, masking, redaction, or any runtime behaviour.** Nothing in
  this package reads a value, so nothing here can protect one. The key buys
  exactly one thing: a claim the compiler can check a document against.
- **Not a licence to store a secret.** This is the part worth saying in the
  record rather than leaving to a reviewer's charity. The annotation exists
  for the values a host insists on describing anyway - so that the compiler
  can refuse them where they would leak - and describing a secret does not
  make storing it correct. The rule above is unconditional. A host that reads
  `sensitive?: true` as permission has read it backwards.

**Where the annotation lives.** It annotates a declared path, so it rides on
whatever surface declares paths: today, a config field declaration carrying
`datamodel_path?: true`, per the accepted amendment above. The typed, scoped
datamodel *document* is a separate accepted record, ADR-0006, and the same
boolean belongs on its per-entry shape, from which the declared-path set is
derivable by one total function. This section is written against the
declared-path set - the normalized input the shipped editor already takes and
`sb-6b1` implements - so it holds under either shape and asserts nothing about
which one wins. ADR-0006 owns that question. [Correction 2026-08-29, sb-l0g:
was "a separate Proposed record (`sb-g8m`, in flight at the time of writing),
and if that record lands, the same boolean belongs ..." and closed "`sb-g8m`
owns that question." The record landed as ADR-0006, "The datamodel document is
a typed, three-scope declaration, and the declared-path set is its
projection", accepted 2026-08-29 (PR 101). Stale status and a stale bead-id
citation only; the substantive claim - that this section is written against
the declared-path set and asserts nothing about which shape wins - is
unchanged, and this correction places the `sensitive?` boolean on ADR-0006's
per-entry shape no more firmly than the original sentence did.]

**Worked example, credit-card processing.** A payment step's datamodel
declares `card.last_four` and `card.token_id`, neither of them sensitive, and
a host that insists on describing the raw pan and the processor credential
declares `card.number` and `processor.api_key` with `sensitive?: true`. The
correct document reads `card.token_id` into the invoke's params and lets the
handler exchange it for the card data at effect time. A document that reads
`card.number` or `processor.api_key` into those params is the case this
annotation exists to catch.

### What the compiler half does once this section is accepted

Named here so the record says what it authorizes, and built by this bead's
second half rather than by this one.

**Refusal, and its shape.** When the host supplies a datamodel declaring a
path sensitive, the compiler refuses a document that reads that path into a
trace-visible position, with a finding whose fault is the document's - the
author's side of ADR-0004 decision 9's split, the side that carries a config
key - anchored `{:config, block_id, key}` on the offending field, source
`:lint` from decision 11's source list, and a message naming the path and
saying why it cannot go there.

**The trace-visible positions, refused:**

- a `core.invoke` param, whether the read is the whole declared path or a
  prefix of it - a prefix drags the sensitive leaf along with everything else
  under it, so a prefix read is the same leak spelled shorter;
- a `core.send` payload;
- a `core.assign` target or source - either direction: writing a sensitive
  value somewhere else spreads it, reading one out publishes it;
- a `core.branch` arm predicate.

**No datamodel supplied, nothing produced.** The check does not run, reports
nothing, and makes no claim - the same qualifier ADR-0005's 11f states for the
undeclared-path advisories, and in 11f's own words: absence is not
unknown-ness. A host that has described nothing has claimed nothing, and the
compiler does not claim on its behalf.

**Findings, not runtime checks.** This package emits SCXML and never sees a
value, so every word above is about what a document says, checked at compile
time. Nothing here inspects, masks, or intercepts anything at run time, and a
record that appeared to promise that would be promising something this package
is structurally unable to do.

### What is not refused, and what this section leaves open

A read of a sensitive path in a position that never leaves the session is not
refused. The criterion is that one: a position whose value reaches none of the
five surfaces above - no trace, no telemetry event, no job payload, no
authoring fixture, no LiveView diff.

What is clearly on that side today:

- **The declaration itself.** Annotating a path is not a read of it, and a
  datamodel that declares `processor.api_key` sensitive is not thereby a
  document that reads it.
- **The identifier pattern the rule prescribes.** A field reading
  `card.token_id` - a declared path that is not sensitive, holding the
  identifier the handler exchanges at effect time - is not a read of a
  sensitive path at all. There is nothing to refuse, and the refusal must not
  grow into a suspicion of any field near a secret.

**And the honest remainder: in the accepted `core.*` vocabulary as it stands,
that side of the line is otherwise empty.** Every position in decision 10's
table, and in the `core.invoke` row the 2026-08-28 amendment added, that can
read a datamodel path at all is in the refused list above. So the complement
is a criterion with no members yet rather than a list, and this section states
it as one deliberately.

Two consequences of that, both left open on purpose:

- **Where exactly the boundary falls is the compiler half's to refine**, against
  the accepted trace and telemetry contracts, not this section's to decide. A
  position argued to be session-local - a value consumed only by the next
  block and never serialized, say - is admitted by an amendment naming it and
  the surfaces it is shown to miss, not by a compiler bead reading the
  criterion generously.
- **Two of the four refused positions name types the vocabulary does not
  declare today.** `core.send` is not in decision 10's table and not in the
  2026-08-28 amendment's two additions; `core.assign`'s vocabulary row is a
  sibling change the `datamodel_path?` section already names as not its own.
  The clauses above bind those types when they exist. Today the refusal has
  two live positions, `core.invoke` params and `core.branch` arm predicates,
  and stating the other two now is what keeps the rule from having to be
  rediscovered when the rows land.

One further thing this section does not fix: **the severity a refusal
carries.** Decision 11's severity set is `:error | :warning | :info` as
amended, and the accepted amendments give `:lint` one producer at `:info`, for
advisories that change no verdict. A refusal is not an advisory - it stops a
compile - so it is not `:info`; which of the remaining two it is, and whether a
`:lint` source may carry it, is one decision, and the compiler half is where it
is asked. It is named here rather than assumed so that accepting this section
does not silently settle it.

### Consequences

- One optional boolean on one declaration. Every existing declaration is
  unchanged and every existing consumer keeps working, because absence means
  what it meant before - the same property the `datamodel_path?` key has, for
  the same reason.
- The type set stays closed, and the editor's control table stays finite.
- The compiler gains its first refusal that depends on an input outside the
  document. ADR-0005's 11f already accepted that shape for advisories and
  named it a real cost; this section spends it a second time, and at a higher
  stake, because a refusal blocks where an advisory only informs. The
  no-datamodel qualifier is what keeps that honest: a host that describes
  nothing loses nothing.
- The rule is stated as a rule, not as a feature. A host can obey it with no
  annotation at all - by not putting secrets in the datamodel, which is the
  whole instruction - and the annotation is the fallback for hosts that
  describe what they should not be carrying.
- Nothing changes in the anchor vocabulary, the source list, the severity set,
  the field-type set, or the emission. This section adds one key and describes
  one refusal.

---

## Amendment (2026-08-29): `core.send`'s descriptor carries a send id, and there is no `core.cancel`

**Status: accepted (2026-08-29, unqualified direction-agent verdict under the operator campaign-015 grant, PR 95).** This section is additive: nothing above it
is edited, and every earlier accepted decision stands as written. It records
the operator's 2026-08-29 delayed-send lifetime ruling - filed here as
`sb-b4f` and mirrored to statifier-ex as `st-q3ud` - on the side this record
owns, which is what a block type *declares*. The emission is ADR-0004's, and
its amendment of the same date holds it; where the two touch, that one is the
authority on emission and this one on declaration.

### What forces the amendment

`core.send` shipped with a gap it recorded rather than papered over: a delayed
send it arms is never cancelled by anything this package emits - no `<cancel>`,
and no `sendid` an author could name - because a cancel that *names* the send
it cancels is a cross-subtree reference to another block, the exact shape
the umbrella's D13 refuses - outcome paths are slots, never ports, and
connectors are rendered, never authored - as ADR-0001's tree invariant and
ADR-0005's amendment 10a state at record level. The module note named the
alternative that keeps the tree invariant, said it was scope-shaped rather
than reference-shaped, and parked the choice on `sb-b4f` instead of guessing
it.

The ruling picks the scope-shaped alternative. Two things follow for this
record, and nothing else does.

### A. The descriptor gains a send id

`core.send` emits `<send id="<its state id>__send" ...>`.

The id is derived, not authored. No config field names it, so decision 7's
schema for the type is unchanged and the editor gains no control; a reader of
the document cannot see it and does not need to. What the descriptor gains is
one attribute that was previously absent, which is what makes a cancel
possible at all - a send with no id is a send nothing can name later.

Where an id of that shape is minted, and by what, is ADR-0004's call. This
section records only that the descriptor carries one.

### B. Cancellation is scope-shaped, so there is no `core.cancel`

Cancellation is **not a block**. The compiler emits the cancel from the scope
that armed the send (ADR-0004's amendment of this date says exactly where), so
no `core.cancel` type exists and none will: decision 10's vocabulary table does
not grow, the palette gains no entry, and D13 holds - a cancel block would have
been the first author-drawn cross-subtree edge in a document, which is the
thing D13 exists to refuse.

### C. What this amendment does not change

- Decision 10's vocabulary table, in either direction. It gains no
  `core.cancel` row, and this section does not write the `core.send` row that
  type is still owed; that remains a separate bead's.
- Decision 7's field types, and `core.send`'s config schema, which keeps its
  two fields.
- Any other block type's declarations. Nothing but `core.send` arms a delayed
  send, so nothing but `core.send` is touched.

---

## Amendment (2026-08-29): the `core.send` row on decision 10

**Status: accepted (2026-08-29, unqualified direction-agent verdict under the operator campaign-015 grant, PR 110).** Section G of this date gave `core.assign` its row and
named the one type still owed one: `core.send`, shipped in the same campaign,
registered in `StatifierBlocks.Palette.core_types/0`, and running under a
`PROVISIONAL` admonition in its moduledoc saying decision 10's vocabulary
table does not carry it. The send-id amendment of this date settled what the
type's descriptor emits and said, in its section C, that it was not the record
that writes the row. This section writes it.

It is additive. Nothing above it is edited: decision 10's original seven-row
table stands, the 2026-08-28 amendment's section D stands, section G stands,
and the send-id amendment's two rulings stand exactly as accepted - this
section records them in the table rather than revisiting them.

### G2. `core.send` joins the core vocabulary

| Block type | `slots(config)` | Config schema | `outcomes(config)` | Notes |
|---|---|---|---|---|
| `core.send` | `[]` | `event`: `:string`; `delay`: `:duration`, optional | default (`done`) | a leaf that sends one event, now or after a delay, emitting a `<send>` inside its `<onentry>`; the block finishes when the send is armed, and cancellation is scope-shaped rather than a block, per the send-id amendment of this date |

The row is read off the shipped `StatifierBlocks.Core.Send`, not off the
campaign-013 spike proposal that preceded it. In full, so a reader need not
open the module: `slots/1` returns `[]` for every config; `config_schema/1`
returns exactly two field declarations, `event` (label "Send this event",
`:string`, `required?: true`, default `""`) and `delay` (label "After",
`:duration`, `required?: false`, default `""`); there is no `outcomes/1`, so
section A's default applies and the type has the single outcome `done`; `io/1`
is `%{kinds: [:step]}`, one outcome and nothing consumed through the type
flow; `current_version/0` is `1`.

**G2a. `delay` is optional, and both spellings are stored forms.** An absent
`delay` key and the field's own `""` default are both "no delay", and neither
is a finding; a present `delay` is accepted in either spelling through
`StatifierBlocks.Core.Duration` - a predicator duration string (`1h30m`, `2d`)
or ISO-8601 (`PT2H`) - which is ADR-0005's accepted decision-9 `:duration`
amendment of this date, cross-referenced beside decision 7 above. Decision 7's
field type is untouched by this row: `delay` is a `:duration` and holds a
string.

**G2b. `validate_config/1` checks shape only.** It refuses an `event` that is
not an event name and a stored `delay` that is neither spelling, and it
refuses nothing else - the same rule section G1 states for `core.assign`, and
for the same reason: a config callback is not a validation language.

**G2c. What the descriptor emits is the send-id amendment's, not this row's.**
A compiled `core.send` is a compound state whose `<onentry>` carries one
`<send>`, with `event` attributed as the author's verbatim, `delay` written
only when there is one and never attributed (its bytes are canonicalised), and
an `id` of the shape that amendment's section A fixes. This row records that
the type declares such a descriptor; the emitted bytes are ADR-0004's, and the
shipped emitter follows the accepted record on its own bead rather than in
this one.

### G3. The count, and what is still owed a row

With this row the table records **eleven** types: the seven of decision 10,
the two of section D, `core.assign` from section G, and this one.
`StatifierBlocks.Palette.core_types/0` registers **twelve**. Section G, written
when the palette registered eleven, named `core.send` as the difference and
declined to close it; this section closes it, and the difference is now
`core.subchart`, which shipped later the same day with its routing recorded in
ADR-0004's amendment of this date and no decision-10 row of its own. That gap
is named here rather than closed, for section G's reason: a row is written off
a ruling, and this record carries one ruling.

### G4. The moduledoc admonition goes

`core.send`'s `PROVISIONAL` admonition said one true thing - that no row
existed - and this section makes it false, so the same change replaces it with
a pointer at this row, exactly as section G did for `core.assign`. The
module's other recorded notes are untouched, including the cancel note, which
the send-id amendment rules on and a separate bead brings into line.

## Amendment (2026-08-29): the `core.subchart` and `core.foreach` rows, and `core.parallel`'s `complete` key

**Status: accepted (2026-08-29, unqualified direction-agent verdict under the operator campaign-015b grant, PR 129).** Section G3 of this date closed the `core.send` gap and
named the one type still owed a row: `core.subchart`, which shipped later the
same day with its routing recorded in ADR-0004's amendment of that date and no
decision-10 row of its own. `core.foreach` shipped after G3 was written and is
in exactly that position too. And `core.parallel`, whose original row lists one
config key, has since gained a second - `complete` - that the row does not
carry. This section writes the two rows and records the key.

It is additive. Nothing above it is edited: decision 10's original seven-row
table stands, the 2026-08-28 amendment's section D stands, sections G and G2
stand, and G3's count sentence stands exactly as accepted - G8 below records
the count the table now carries rather than rewriting that sentence.

Every row is read off the shipped module rather than off the bead that proposed
it, and each quoted callback names its file and line so a reader can diff the
record against the source.

### G5. `core.subchart` joins the core vocabulary

| Block type | `slots(config)` | Config schema | `outcomes(config)` | Notes |
|---|---|---|---|---|
| `core.subchart` | one `zero_or_one` slot per declared outcome, named `on_<outcome>`, in declaration order with `on_error` last | `chart`: `:string`, required; `outcomes`: `:string`, optional; `assign_to`: `:string`, optional; `params`: `:string`, optional | the outcomes the referenced chart declares, as the author listed them, with `error` appended unless they listed it | a step that runs another chart through one host-registered invoke type, and finishes at the outcome the child reported |

In full, so a reader need not open the module. `current_version/0` is `1`
(`lib/statifier_blocks/core/subchart.ex:117`). `slots/1` (`:144`) maps the
outcome names through the `on_` slot prefix, each with arity `zero_or_one` -
an outcome path is one continuation, not a list of them, which is
`core.invoke`'s reason. `outcomes/1` (`:156`) returns those same names with
their labels, so section A's default does not apply and the type's outcome list
is the author's. `io/1` (`:248`) is
`%{kinds: [:step], produces: :unknown, slot_accepts: accepts}`, where `accepts`
maps every slot to `[:step]`; `produces` is `:unknown` rather than a join over
the subtrees reaching each outcome, which is the lattice ADR-0003 decision 4
refuses to build, and there is no `consumes` because a subchart reads its
inputs through `params`. The invoke type is a constant rather than a config
field: `invoke_type/0` (`:132`) returns `"statifier_blocks:subchart"` (`:106`),
because *which handler* starts a child session is deployment state rather than
authoring state (st-ADR-0051).

`config_schema/1` (`:163`), verbatim:

```elixir
def config_schema(_config),
  do: [
    %{
      key: "chart",
      type: :string,
      label: "Run this chart",
      required?: true,
      default: ""
    },
    %{
      key: "outcomes",
      type: :string,
      label: "It can finish with",
      required?: false,
      default: ""
    },
    %{
      key: "assign_to",
      type: :string,
      label: "Write the outcome to",
      required?: false,
      default: ""
    },
    %{
      key: "params",
      type: :string,
      label: "Send along",
      required?: false,
      default: ""
    }
  ]
```

**G5a. What it emits is ADR-0004's, not this row's.** A compiled
`core.subchart` is a compound state whose inner state carries one `<invoke>`
with an `id`, an `src` stamped as coming from `chart`, and the `type` above,
plus one `<param>` per parsed `params` row; every declared outcome gets one
conditioned `done.invoke` transition in declaration order, and the
unconditioned one comes last and lands on the first declared outcome, so a
subchart that declares nothing behaves exactly like a `core.invoke`. The
`error.communication.invoke` route is emitted only when the `on_error` slot is
occupied. This row records that the type declares that shape; the emitted bytes
are ADR-0004's, as G2c says for `core.send`.

### G6. `core.foreach` joins the core vocabulary

| Block type | `slots(config)` | Config schema | `outcomes(config)` | Notes |
|---|---|---|---|---|
| `core.foreach` | `[{"body", :any, "For each item"}]` | `items`: `:string`, required, `datamodel_path?: true`; `item_as`: `:string`, required, default `"item"`; `index_as`: `:string`, optional | default (`done`) | a container whose body runs once per item of a datamodel list; the body's states exist once however long the list is |

In full. `current_version/0` is `1` (`lib/statifier_blocks/core/foreach.ex:162`).
`slots/1` (`:169`) is total and constant:
`def slots(_config), do: [{@body_slot, :any, "For each item"}]`, with
`@body_slot` being `"body"` (`:152`). There is no `outcomes/1`, so section A's
default applies and the type has the single outcome `done`. `io/1` (`:271`) is
`def io(_config), do: %{kinds: [:step], slot_accepts: %{@body_slot => [:step]}}`,
which is `core.group`'s shape, with `produces` absent rather than `:unknown`
because a foreach has one outcome and so no join to refuse, and `consumes`
absent because `items` is a config path rather than a value arriving through
the type flow.
`items` carries decision 7's `datamodel_path?: true`, as `core.assign`'s `path`
does.

`config_schema/1` (`:172`), verbatim, its source comment included because it is
where the read-only case is argued:

```elixir
def config_schema(_config),
  do: [
    %{
      key: "items",
      type: :string,
      label: "For each item in",
      required?: true,
      default: "",
      # A foreach only ever reads this path. ADR-0002 decision 7's key is
      # a boolean, so "reads" is not expressible in the declaration; the
      # editor's lint is the same either way (the path must be one the
      # host's datamodel declares).
      datamodel_path?: true
    },
    %{
      key: "item_as",
      type: :string,
      label: "Call the item",
      required?: true,
      default: @default_item
    },
    %{
      key: "index_as",
      type: :string,
      label: "Call the position (optional)",
      required?: false,
      default: ""
    }
  ]
```

`@default_item` is `"item"` (`:154`).

**G6a. Two compiler-owned roots, which no other core row has.** A compiled
`core.foreach` is a plain Appendix D loop: a compound state whose `<onentry>`
snapshots the list into `s_blk_<id>__items` and zeroes a cursor in
`s_blk_<id>__i`, an inner head state that assigns the item (and the position,
when `index_as` is set) and either leaves for the block's `<final>` or enters
the body, and a loop-back transition that increments the cursor. Both roots are
minted through `Context.role_id/2` and declared through
`Compiler.DeclaredRoots`, so decision 3's uniqueness keeps them out of any name
an author can write. The loop-back transition is `type="internal"` and must be:
an external transition exits and re-enters its own source, which would re-run
the `<onentry>` and reset the cursor on every pass. The bytes are ADR-0004's
2026-08-29 amendment (F1 through F6); what this row records is that the type
declares the callbacks above.

### G7. `core.parallel`'s `complete` key, recorded

Decision 10's row for `core.parallel` gives its config schema as "`lanes`: a
list of lane names". That was the whole schema when the row was written and is
no longer: the type gained a second key. The row is not edited; the schema it
names is superseded by this one, which is the shipped `config_schema/1`
(`lib/statifier_blocks/core/parallel.ex:76`) in full:

```elixir
def config_schema(_config),
  do: [
    %{
      key: "lanes",
      type: {:list, :string},
      label: "Lanes",
      required?: true,
      default: []
    },
    %{
      key: "complete",
      type:
        {:select,
         [
           {"all", "All - when every lane is done"},
           {"first", "First - when any one lane is done"}
         ]},
      label: "Continue",
      required?: false,
      default: "all"
    }
  ]
```

The permitted values are `["all", "first"]` (`:57`) and the default is `"all"`.
Nothing else in the row changes: `slots/1` is still one `:any` slot per
well-formed lane in config order, and the type still has the default single
outcome.

**G7a. The key is read through its default, so no stored block moved.** Every
`core.parallel` stored before the key existed decodes, validates, and compiles
to the byte it did before, because `complete` is absent and absent reads as
`"all"` everywhere. A stored `null` is *not* an absent key and is still refused
(ADR-0001 decision 6): `Map.get/3` hands the `nil` straight to the one-of
check, which rejects it with `pick "all" or "first"`.

**G7b. What the two values emit.** Under `"all"` the wrapper carries a single
`done.state.<run>` transition to the block's `<final>`, which is the shape the
original row's emission has always had - a `<parallel>` is done when every
region is, so no join logic of its own is needed. Under `"first"` that single
transition is replaced by one transition per lane, placed on the `<parallel>`
element itself and taken on that lane's own `done.state.<region id>`; they are
external, they come before the regions, and the `done.state.<run>` transition
is dropped rather than kept because it could never be taken. A parallel with no
lanes emits no `<parallel>` at all under either value, so `complete` moves no
byte of that case. Those bytes are ADR-0004's 2026-08-29 amendment (P1, P2);
this section records only that the config key declaring the choice is in the
shipped schema.

### G8. The count, corrected

With G5 and G6 the table records **thirteen** types: the seven of decision 10,
the two of section D, `core.assign` from section G, `core.send` from section
G2, and these two. `StatifierBlocks.Palette.core_types/0` registers
**thirteen** (`lib/statifier_blocks/palette.ex:87-103`). The table and the
palette now agree, and no type is owed a row.

G3 said the table records eleven and the palette twelve. Both halves were true
when G3 was accepted and neither is now - `core.foreach` registered after that
section was written, and G5 and G6 add the two rows. That sentence is not
edited, per this record's amendment convention; it is **superseded by this
section**, and a reader who reaches G3 should carry the counts above rather
than the ones there.

## Amendment (2026-08-30): an optional `summary/1`, and what a core card's second line says

**Status: accepted (2026-08-30, unqualified direction-agent verdict under the operator campaign-017 grant, PR 150).** Additive; decision 5's
callback table gains a row, decision 7 is untouched, and no text above this
line is edited by this section. Section C of the 2026-08-28 amendment stands
exactly as written: this section does not move who owns a label, it says what
the line *under* the title carries when nobody has written one.

### Context

The 2026-08-28 amendment settled the card's first line - the block's own label
when the author wrote one, the type's label when they did not - and left the
second line to the editor record. ADR-0005's card face shipped it as the type
label, drawn only when the first line is the author's, which for the whole
`core.*` vocabulary means it is never drawn: a `core.wait` card reads "Wait"
and nothing else.

The authoring spike this package's editor is a parity target for does not read
that way. Its cards carry a per-type second line: a `core.parallel` shows its
lane names, a `core.wait` shows a `timer 30s` chip, a `core.on_event` shows the
outcome and the event it waits for. The spike produces those lines from a
`switch` on the type name inside its layout pass.

That switch is the thing this record has to refuse. ADR-0005 decision 2's whole
premise is that the editor works off the caller-supplied palette and never
names a type: a host that registers `myapp:authorize` gets the same card the
core vocabulary gets, and an editor carrying a table of `core.*` names would
give the built-in types a face no host can ask for. So the second line is a
*declaration*, made where every other claim a block type makes about itself is
made - here - and the core types are the first thirteen callers of it rather
than thirteen special cases in the renderer.

The operator's ruling of 2026-08-30 (D3) names the shape: "core summary =
optional BlockType summary/1, recorded as an ADR-0002 amendment through the
direction-agent gate."

### Decision

**H1. A block type may export `summary(config)`, and it is optional.**

    @callback summary(Block.config()) :: nil | String.t() | [String.t()]

It answers one question: *what does this block's card say about itself under
its title, given this config?* Three return shapes, because the spike's lines
come in two shapes and most types want neither:

  * `nil` - no second line. This is the default, it is what a type that does
    not export the callback means, and it is the card every block type has
    today.
  * a string - one summary line. `core.send`'s event name, `core.wait`'s
    `timer 1h`.
  * a list of strings - a **chip list**, each entry read as one chip.
    `core.parallel`'s lane names, `core.on_event`'s outcome and event.

It joins `io/1`, `migrate_config/2`, `fixtures/0`, `palette_entry/0` and
`outcomes/1` in `@optional_callbacks`, and it is read through a resolver on
this module for the reason amendment A gave for `outcomes/2`: a default that
two consumers can spell differently is a default that will eventually be
spelled two ways.

The three rules decision 6 already puts on `slots/1` and `config_schema/1`
apply unchanged and are not restated as new law: it is a **pure function of
config**, it is **total** - it answers for any config, including config
`validate_config/1` rejects, because the editor calls it mid-edit - and it
**never raises**.

**H2. `BlockType.summary/2` is the resolver, and it returns a chip list.**

    @spec summary(module(), Block.config()) :: [String.t()]

Every caller gets the same shape - a possibly-empty list of chips - so no
consumer branches on which of the three return shapes a type chose. `nil` and
a module that does not export the callback both come back `[]`; a string comes
back as a one-element list; a list comes back filtered. Absence is checked with
`Code.ensure_loaded?/1` plus `function_exported?/3`, the pattern `outcomes/2`
and `StatifierBlocks.Palette.resolve/2` already use.

**H3. A summary chip is a presentation string, so amendment B3's refusal
discipline governs it, unchanged.** Each chip goes through the one refusal set
B3 wrote for the badge and the join marker: a non-string, an empty or
all-whitespace string, one carrying a newline, carriage return or tab, and one
longer than the presentation cap are **refused, never truncated**. A refused
chip is dropped from the list and the rest of the list survives; a summary
whose every chip is refused is a card with no second line, which is the card
that type had before it declared one.

This is the point where the spike and this record part company on purpose. The
spike's parallel card reads `fraud_review, balance_chec...` - it truncates.
The cap exists (`@presentation_cap` in `lib/statifier_blocks/block_type.ex`,
at B3's request)
because a clipped string reads as a rendering bug a host files against the
editor, where a missing chip reads as the declaration it is. That reasoning
does not weaken because the string moved from the header to the second line, so
a lane name longer than the cap costs its own chip and nothing else: the
sibling lanes still draw.

**H4. A callback that raises degrades to no summary.** B3 widened "a callback
that raises degrades to the default" to a throw and an exit for `join_label`,
because host code on the editor's layout pass leaves that pass in the same
place however it fails. `summary/1` sits on exactly that pass, so it is
rescued the same way and the rescued value is never inspected: what comes back
is `[]`, the card the type had before it declared anything.

**H5. The view model carries it, and the second line reads it when the title
is the type's.** `StatifierBlocks.ViewModel.Node` gains a `summary` field,
additively, defaulting to `[]`. `ViewModel.subtitle/1` gains one arm and loses
none:

  * a node whose title is the **author's** keeps the line it has - the type's
    label - because that is the fact the author cannot see anywhere else on the
    card. The summary is derivable from the fields in the inspector; the type
    name of a card the author has renamed is not.
  * a node whose title is the **type's** now draws the summary, which is the
    line the whole `core.*` vocabulary was missing, and `nil` when there is
    none.

A chip list reaching a renderer that has no chip markup is joined with `", "`
rather than dropped. The list shape is in the contract because chips are what
the second line eventually draws; nothing in this section requires the markup
to exist first, and a package that ships the markup later changes no block
type.

**H6. The five core summaries.** Read off the shipped modules. Each is a pure
function of the config the type already validates, and every one of them is
data the author typed, never a type name:

| Block type | `summary(config)` | Shape |
|---|---|---|
| `core.parallel` | the well-formed lane names, in stored order | chip list |
| `core.wait` | `timer <duration>`, from the stored `duration` | string |
| `core.on_event` | the outcome's word (`Abandon`, `Resume`) then the event name | chip list |
| `core.send` | the event name | string |
| `core.branch` | `N arms + otherwise`, `N` counting the well-formed arms | string |

Notes on the three that need one. `core.parallel` reads lanes through the same
private filter `slots/1` reads them through, so a malformed lane is absent from
the summary exactly as it is absent from the slots - the card and the slot list
cannot disagree about which lanes exist. `core.on_event` puts the outcome
first, which is the order the spike's card reads in and the reverse of the
order `config_schema/1` declares the two fields: the outcome is what the block
*does*, and the event is only when. `core.branch` counts arms rather than listing
their conditions, because an arm's condition is an expression and an expression
is not a chip; the `otherwise` slot is named rather than counted because it is
always there.

The other eight core types declare no summary and are unchanged. Nothing in
this section makes a summary mandatory for a host type either: a host that
wants the one-line card keeps it by exporting nothing.

### Consequences

- **The editor still names no type.** The second line is a declaration read
  through one resolver, so a host type gets the same card face the core
  vocabulary gets by exporting the same callback. That is what this section
  buys, and it is the reason it is a callback rather than a table in the
  renderer.
- **Decision 5's callback table is one row longer** and every existing type
  still compiles: the callback is optional and its absence is the behavior
  every type has today.
- **The presentation cap now governs three things** - the badge, the join
  marker, and a summary chip - and it is still one number in one place
  (`@presentation_cap` in `lib/statifier_blocks/block_type.ex`; cited by name
  rather than by line, because this section's own implementation moves the
  number). B3 left the
  number to ADR-0005 decision 10, which still carries none; this section adds
  a third reader rather than a second opinion.
- **A prose claim in the code is now false and is corrected by the same
  change.** `lib/statifier_blocks/view_model.ex` documents `subtitle/1` as
  `nil` "for every block that has no name of its own", and calls that "the
  state the whole `core.*` vocabulary is in". That was true when it was
  written and this section makes it false. The comment on `title_override/2`
  saying no core type declares a `label` field stays true and is untouched:
  the summary is not a label, no core type declares one, and section C's
  editor-owned label is still the only way a card's *first* line becomes the
  author's.
- **Nothing serializes.** A summary is presentation, read at render time from
  config that is already stored. No compiled byte moves, so ADR-0004 decision
  6's byte determinism is not in reach of this section.
- **What is deferred.** The chip *markup* on the card - a `.sb-node__summary`
  chip row rather than one joined string - is ADR-0005's to describe and a
  later bead's to ship. Until it does, a chip list renders joined, which is
  the spike's own reading of a two-chip `core.on_event` line minus the
  truncation.

## Note (2026-08-30): amendment H, what the chip row draws for none and for one

A dated precision note rather than an amendment: amendment H is unchanged in
every particular, and what is recorded here is what the deferral it left behind
resolved to once the markup existed. The chip row is ADR-0005's, per H's own
Consequences, and it landed there as that record's 2026-08-30 amendment
(decision 10, the summary chip row) with `sb-2mxa` as the implementing bead.
This note says only what a reader of H cannot otherwise tell about the two
degenerate cases, both of which H's table produces.

**A type that declares no summary draws no row.** `summary/1` is optional and
eight of the thirteen core types export none; a type whose every chip is
refused under H3 lands in the same place, since refusal drops a chip rather
than replacing it. In both cases `ViewModel.Node.summary` is `[]` and the card
draws **no row element at all** - not an empty one. That is the card those
types had before H, and H's "the other eight core types are unchanged" is true
of the markup and not only of the callback.

**A string summary draws exactly one chip.** Three of H6's five rows declare a
string rather than a chip list - `core.wait`'s `timer <duration>`,
`core.send`'s event name and `core.branch`'s `N arms + otherwise` - and
`StatifierBlocks.BlockType.summary/2` wraps a string
into a one-element list, so `Node.summary` is always a list and a string is the
one-chip case of it. The card draws one chip, with no join marker and no
separator of any kind. The `core.branch` row is the sharpest reading of that:
`3 arms + otherwise` is one fact whose own words contain a `+`, and it stays
one chip.

The `", "` join H described as the interim rendering is gone with the deferral
it belonged to; the arm of `ViewModel.subtitle/1` that H5 added for it now
answers `nil` and the chips are read from the node. The function that reads
them is `StatifierBlocks.ViewModel.summary_chips/1`, which is the public reader
a host calls rather than reaching for `Node.summary` itself (named by ADR-0005
decision 10's 2026-08-30 Note, "the cap signals", which also records that a
chip H3 refuses now raises a `:lint` warning against its block). H5's rule
about **which** fact the second line carries - the type's label when the author
named the block, the summary otherwise - is untouched and is what the row is
placed by.

## Note (2026-08-31): `core.on_event` takes an optional `cond`

A dated note rather than an amendment, recorded for `sb-d65` under
campaign-022 ruling R6. It records one optional field on a type this record
already ships, and the reason that field belongs on the interrupt handler
rather than on a `core.branch` after it. The record's Status is untouched, no
document authored without the key compiles differently, and the vocabulary
does not grow.

### What the type carries now

Decision 10's table gives `core.on_event` two config fields, `event` and
`outcome`. It now declares a third:

| Field | Type | Required? | Means |
|---|---|---|---|
| `cond` | `:expression` | no, default `""` | the handler fires only when this condition holds |

`:expression` is already in decision 7's closed field-type set, so nothing about
the set moves; `core.branch`'s arms were its only reader and now have a second
one. The field's `value_path` is decision 7's default, `[key]`, because the
condition is stored at `config["cond"]` - `core.branch` declares an explicit
path because its conditions live inside its `arms` list, and this type has no
such indirection to describe.

What is emitted is one attribute on one transition. The watcher's
`<transition event="..." target="...">` gains `cond="..."` when the key holds a
non-blank string:

    <transition cond="review.parked" event="review.resolved" target="s_INT__done">
      <raise event="statifier_blocks.interrupt.resume"/>
    </transition>

A handler whose `cond` is absent, empty, or whitespace writes no `cond`
attribute at all, which is what makes this key additive: every document authored
before it existed compiles to the same bytes it compiled to before.

### Why the guard is on the handler and not on a branch after it

The alternative this note rejects is that a guarded interrupt is spelled
`core.on_event` followed by a `core.branch` inside it, with no new key anywhere.
It does not work, and the reason is a fact about *when* the two conditions are
read.

A `core.on_event` decides whether to leave the group it interrupts. Its
transition raises the interrupt-protocol event, and the enclosing group
transitions on that event unconditionally - by the time control is inside the
handler's own body, the in-flight work has already been abandoned or re-entered.
A branch there can decide what to do *afterwards*; it cannot decide whether the
interrupt should have happened. The question "does this event actually interrupt
this work" has exactly one place it can be asked, and that is the transition
this note puts the guard on.

The evidence was already in the repository. This record's own 2026-08-28
amendment, section D, point D3 ("Two demo types are deliberately NOT promoted"),
held two demo types back from the core vocabulary on the grounds that "a guarded
event handler and a timeout rule are `core.on_event` and `core.wait` inside a
group's `interrupts` slot, with the guard as a condition". That sentence
described an affordance the shipped type did not have: `core.on_event` declared
no condition and read none. The `card_processing` example document has carried an
authored `cond` on an interrupt rule since 2026-08-28, stored and inert, on the
strength of the same reading. This note makes D3's sentence true rather than
aspirational, and the inert key live.

### What validates it, and what does not

`validate_config/1` asks only whether the stored value is a string. Whether the
string is a well-formed predicator expression is not this package's question -
ADR-0004 decision 9 puts expression checking upstream. The transition therefore
carries the `cond_key` that decision 9's provenance needs, naming `"cond"`, and
a malformed guard is refused at the Chart stage as an `:expression_compile_error`
finding with `config_key: "cond"` and `fault: :author`: the same shape, from the
same machinery, that a malformed `core.branch` arm produces with the arm's slot
name as its key. The only difference between the two is that a branch requires
its conditions and a handler does not.

### What this note does not change

- **Decision 10's placement rule.** `core.on_event` is still an
  `:interrupt_handler` and nothing else, carried by `io/1` per ADR-0003, with no
  validation rule of its own. A guard is a condition on firing, not on placement.
- **The `outcome` values.** Still `"abandon"` and `"resume"`, still the pair
  ratified 2026-08-27, and a third still costs a `current_version/0` bump.
- **The size of the core vocabulary.** No type is added. The demo types D3 held
  back stay held back, and the argument for holding them back is stronger now
  than it was, not weaker.
- **Amendment H6's card row.** `core.on_event`'s summary is still the outcome
  word then the event name, and the guard is not a third chip. The reason
  `core.branch` counts its arms instead of listing their conditions is the same
  reason here: an expression is not a chip.
- **The document schema.** ADR-0001 owns the stored bytes and `schema_version`
  stays at `1`. An optional key inside a block's `config` object is a block-type
  contract, which is this record's, and the stored spelling of the guarded
  handler in `card_processing` is unchanged by being read at last.

## Amendment (2026-08-31): decision 10, the `core.drafts` and `core.placeholder` rows

**Status: accepted (2026-09-01), drafted for `sb-5h6q` under the operator campaign-024 grant; accepted on the gate's unqualified direction-agent verdict.** Additive; decision 10's original
seven-row table stands, the 2026-08-28 amendment's section D stands, sections
G through G8 stand, and no text above this line is edited by this section.

### Context

Every block in a document is in the flow. That is what makes a document
compile: ADR-0001 decision 1 fixes one root, ADR-0004 decision 5's totality
makes every emitted byte some block's, and there is nowhere in the tree for a
fragment an author has built but has not placed. An author who knows the sink
of a workflow before its sources therefore cannot build backwards toward it.
The half-built tail has to be either wired into the flow, where it compiles as
though the author meant it there, or deleted and rebuilt later.

Two different things are missing. The first is a **shelf**: somewhere in the
document to hold a fragment that is not in the flow and is not pretending to
be. The second is a **marker**: a way to say, inside the flow, that a step is
deliberately missing here.

Neither is a document-schema change. ADR-0001 decision 1's single root stands,
no second root is introduced, no envelope key is added, and `schema_version`
stays at `1`. These are two block types and nothing else, and
campaign-024 ruling R-a is what puts the second in the same record as the
first: they are one authoring story and one review. What the two mean to the
compiler is ADR-0004's amendment of this date; how they render is ADR-0005's;
where they may sit is section G12 below together with ADR-0003's amendment of
this date.

These two rows are written **ahead of the modules that will answer them**,
which reverses the discipline G5 through G8 kept. That is deliberate and it is
what `sb-5h6q` is: the shape was agreed before the code existed, and the
implementing bead `sb-uag7` builds to this record rather than this record being
read off the build. G11 says what the counts are while that is true.

### G9. `core.drafts` joins the core vocabulary

| Block type | `slots(config)` | Config schema | `outcomes(config)` | Notes |
|---|---|---|---|---|
| `core.drafts` | `[{"body", :any, "Drafts"}]` | empty | not declared; nothing reads one | the document's shelf: a container whose children are held out of the flow, admitted only as a direct child of the root and only once per document (G12) |

In full, so a reader need not hold the rest of this section in their head:
`slots/1` returns that one slot for every config, `config_schema/1` returns
`[]`, `validate_config/1` is `:ok`, `current_version/0` is `1`, and `io/1` is
`%{kinds: [:draft_shelf], slot_accepts: %{"body" => :any}}`. There is no
`outcomes/1`: section A's default would give the type the single outcome
`done`, and no consumer ever asks, because a drafts block is not a step and is
never sequenced into or out of. The type declares no `produces` and no
`consumes` for the same reason - see G10a.

**G9a. A drafts block is elided from the flow before anything reads
sequencing.** ADR-0001 decision 5 makes a slot's child list ordered, and two
passes read that order as a flow: the Structure stage's data-flow walk
(ADR-0003 decision 4) and the Emit stage's sequencing (ADR-0004 decision 2).
`core.drafts` is removed from the root's child list before either of them
runs. The sibling before it is therefore adjacent to the sibling after it, no
other block's inbound type moves, and no state is emitted for it or for
anything inside it.

That single rule is what the rest of this design falls out of. It is why the
type declares no data-flow direction at all: a block that is never at either
end of a seam has nothing to say about one. It is why ADR-0004's amendment of
this date can say the compile is byte-identical with the shelf occupied and
with it empty. And it is why ADR-0005's amendment of this date can say the
renderer must draw no connectors between the shelf's children: an order the
compiler is defined never to read must not be drawn as though it meant
something.

**G9b. `:draft_shelf` is a new kind, and it is the whole placement mechanism
except for two facts.** ADR-0003 decision 3 admits a block into a slot by
intersecting the parent's `slot_accepts` with the child's `kinds`. Every slot
in the shipped `core.*` vocabulary accepts `[:step]` or `[:interrupt_handler]`
and none accepts `:any`, so a block declaring `kinds: [:draft_shelf]` and
nothing else is refused by every one of them through the mechanism that
already exists, with no new rule and no per-type list. A host container that
declares no `io/1` is the exception, since ADR-0003 decision 5 gives it
`slot_accepts` `:any` for every slot and `:any` admits everything; G12's
Structure rule is what catches a shelf there. The two facts the mechanism
cannot express - that the root's `body` admits it anyway, and that it admits
at most one - are G12's.

Minting a kind rather than declaring `kinds: [:step, :draft_shelf]` is the
point of G9a restated at the placement layer. A shelf that were also a step
would be admitted by every `[:step]` slot in every host palette, and the only
thing standing between a document and a drafts block nested four levels deep
inside a branch arm would be G12's structure rule catching it afterwards.
Under the kind, the ordinary mechanism refuses it at drag time everywhere in
the shipped vocabulary, and G12's rule is left carrying only the two cases it
alone can decide - the root's own admission, and the untyped host container of
the paragraph above.

**G9c. `body` accepts everything, and what is inside it is still checked.**
`slot_accepts: %{"body" => :any}` is the maximally permissive declaration
ADR-0003 decision 5 already describes, and this record makes it deliberately:
a shelf that refused the fragment an author most needed to put down would be
worse than no shelf. What that permissiveness does **not** buy is a suspension
of the Config stage. `validate_config/1` runs on every block in the document
including every block inside the shelf, because the Config stage walks the
document rather than the flow, and an author who parks a half-configured
fragment still wants the form to say so. ADR-0004's amendment of this date
records the same fact from the compiler's side, including which stages a
shelved fragment is and is not seen by.

**G9d. `drafts` in this record means the block type, never the editor's edit
state.** ADR-0005 decision 9's uncommitted config-form value is also called a
draft and is held in an editor assign of that name. The two share a word and
nothing else: a config draft is per-field, lives for as long as a form is
open, and never reaches the document; a *draft fragment* is a block subtree
stored in the document, in the canonical bytes, in the hash and on the undo
stack. Where either record needs to be unambiguous it says *the drafts tray*
and *a draft fragment*, and ADR-0005's amendment of this date says the same
thing on its own surface.

### G10. `core.placeholder` joins the core vocabulary

| Block type | `slots(config)` | Config schema | `outcomes(config)` | Notes |
|---|---|---|---|---|
| `core.placeholder` | `[]` | `note`: `:string`, optional | default (`done`) | an in-flow leaf marking a gap the author has left on purpose; it compiles to a step that does nothing and warns |

In full: `slots/1` returns `[]`, `config_schema/1` returns one field
declaration - `note` (label "What goes here", `:string`, `required?: false`,
default `""`) - `validate_config/1` refuses a `note` that is not a string and
refuses nothing else, `current_version/0` is `1`, and `io/1` is not declared
at all. An absent `io/1` is ADR-0003 decision 5's permissive default, which is
exactly right here: `kinds: [:step]` puts the marker wherever a step goes,
`consumes: :unknown` and `produces: :unknown` let it sit anywhere in a seam
without narrowing either side, and a gap that constrained its neighbours would
be a worse gap than one that does not.

**G10a. The two types are opposites and that is why they are one record.**
A `core.drafts` block holds work that is **not** in the flow and says nothing
about it; a `core.placeholder` block **is** in the flow and says something is
missing from it. An author moving a fragment from the shelf into the flow is
filling a gap; an author who has not built the fragment yet marks the gap
instead. Both are the same authoring fact - a workflow under construction -
and shipping only the first would leave an author no way to say *where* the
parked fragment is eventually going.

**G10a-i. `placeholder` in this record means the block type, never the
compiler's child placeholder.** The compiler already uses the word: an
`Emission` carries `{:child, block_id}` markers that decision 10's Emit stage
splices each child's own emission into, and both the code and ADR-0004 call
those **child placeholders**. They are an internal step of one compile, exist
only between a child's `emit/2` and the splice, and are never stored, never
rendered and never seen by an author. A `core.placeholder` block is the
opposite in every one of those respects. This is the same collision G9d
records for `drafts`, and it is resolved the same way: where either could be
meant, this record says *a placeholder block* or *a child placeholder* and
never the bare word.

**G10b. The note is prose and this package never reads it.** `note` exists so
that a gap can carry the author's own words into the editor's card and into
the compile warning ADR-0004's amendment of this date mints. Nothing parses
it, nothing routes on it, and an empty one is not a finding: an unexplained
gap is still a gap, and refusing one would make the marker more expensive to
place than leaving the hole unmarked, which inverts the whole point.

### G11. The counts, while these two rows run ahead of the code

With G9 and G10 the table records **fifteen** types: the thirteen G8 counted
and these two. `StatifierBlocks.Palette.core_types/0` registers **thirteen**
(`lib/statifier_blocks/palette.ex:87-103`) and will register fifteen when
`sb-uag7` lands the modules.

G8's sentence - "The table and the palette now agree, and no type is owed a
row" - was true when it was accepted and is not now. It is not edited, per
this record's amendment convention; it is **superseded by this section**, and
the disagreement runs the opposite way from every previous one in this record:
here the record is ahead of the palette rather than behind it. A reader who
finds a fifteen-row table and a thirteen-entry palette is looking at that gap
and not at drift.

*[Note added 2026-09-05, with `sb-5v3i` under campaign-031 ruling D31-2. Both
counts moved after this section was written, and neither move is edited into
it. The palette caught up first: `StatifierBlocks.Palette.core_types/0`
registers **fifteen** today, not thirteen, because `sb-uag7` landed the two
modules this section was waiting on - and it registers them at
`lib/statifier_blocks/palette.ex:117-133`, not at the `:87-103` cited above,
which the file has since moved past. (ADR-0009's consequences carry a stale
citation of their own for the same map, `:87-104` at
`docs/adr/0009-fan-out-block-type.md:509`; the count there is right and only
the line range is old.) Then the table ran ahead again: the
`core.await` row that G14 of this date adds makes the table **sixteen** while
the palette stays at fifteen until `sb-m0t1` lands that module, which is the
same kind of gap this section describes and not drift. ADR-0009's
"`core.map`'s row would be the **sixteenth**"
(`docs/adr/0009-fan-out-block-type.md:512`) is an ordinal counted from the
fifteen rows it saw - it names the next row after those - rather than a
reservation of the sixteenth position against this one, and `core.map` still
has no row in this table.]*

*[Note added 2026-09-05, with `sb-7haw` under campaign-031, after `sb-kqno`
landed `core.map` (PR 281, `a852429`). The table and the palette both read
**seventeen** now, and they agree. The amendment of this date below adds
`core.map`'s row as G15, which takes the table from the sixteen the Note
above records to seventeen; `StatifierBlocks.Palette.core_types/0`
(`lib/statifier_blocks/palette.ex:116-136`) registers the same seventeen,
because `sb-m0t1` landed `core.await` and `sb-kqno` landed `core.map`. So
both gaps the Note above describes - the table ahead of the palette by
`core.await`'s row, and `core.map` owed a row it did not have - are closed,
and by the two moves closing in opposite directions rather than by one.

Three count sentences above are superseded rather than edited, per this
record's amendment convention. G11's "the table records **fifteen** types"
and its "`StatifierBlocks.Palette.core_types/0` registers **thirteen**" were
true when G11 was accepted. The Note above them reads fifteen and sixteen,
which were true when it was written. G14's parenthetical - "registers
**sixteen** once it lands" - was true of the module it was written beside.
A reader wanting today's number reads this Note: **seventeen rows, seventeen
palette entries**, and no type owed a row.

One line citation the Note above carries has moved, by this bead's own edit
and not by anyone else's. That Note cites ADR-0009 at `:509` and `:512`; the
`core.map` Note this bead adds beneath ADR-0009's decision 4 is inserted above
both, so the palette citation it flags as stale now reads at
`docs/adr/0009-fan-out-block-type.md:564` and the "sixteenth" ordinal at
`:567`. Neither claim changes - only where in that file it sits - and neither
Note is edited to say so.]*

### G12. Two placement facts `io/1` cannot carry, and the Structure-stage rule that does

ADR-0003 decision 3 withdrew ADR-0002's one special-cased placement rule and
said why: a constraint on a block's parent is expressible as an intersection
of kinds, so it should be one. Neither fact below is that shape, and this
section says so rather than bending them into it.

**G12a. `core.drafts` is admitted as a direct child of the root block's `body`
slot, and nowhere else.** This is a constraint on *depth*, not on the parent's
type: a `core.sequence` is the conventional root (decision 10) and is also the
most common block in any document, so a rule expressed as "inside a
`core.sequence`" would admit the shelf at every level of every document. What
distinguishes the one admissible position is that its parent is the document's
root, which is a property of the document rather than of either block, and
`slot_accepts` has no way to say it.

**G12b. A document carries at most one `core.drafts` block.** Cardinality
across a document is not a placement question at all. It is closest in shape
to ADR-0001 decision 3's document-unique ids, and like that rule it is checked
by walking the document rather than by asking a block type anything.

Both are enforced as **Structure-stage findings** (ADR-0004 decision 10),
which is campaign-024 ruling R-b. The stage is right on its own terms: the
Structure stage is where arity, undeclared slots and assignability already
live, it runs after Config so a document with a malformed form does not first
hear about its shelf, and it runs before Emit so nothing has been generated
for a block that should not be there. ADR-0004's amendment of this date names
the two codes and their fault.

**G12c. Relaxing either fact later is additive.** Both rules refuse documents
that would otherwise be admitted; neither changes the meaning of a document
that is already valid. A later record that lets a shelf sit inside a group, or
that admits a second one, widens the admitted set and leaves every existing
document compiling to the bytes it compiles to today. That is why this record
takes the narrow position now rather than guessing at the general one:
campaign-024 ruling R-b, and the reason behind it.

### G13. What these two rows do not change

- **The document schema.** ADR-0001 owns the stored bytes. Two new type names
  in the reserved `core.` namespace are what decision 4 of that record already
  provides for, and `schema_version` stays at `1`.
- **The behaviour contract.** Decision 5's nine callbacks are unchanged. Both
  types answer the callbacks that already exist; neither needs one that does
  not.
- **The edit algebra.** Putting a fragment on the shelf and taking it off are
  ordinary Move commands over ADR-0001's tree, with ADR-0005 decision 3's
  inverses, so undo and redo work on them because nothing about them is
  special. No command is added by this record and none is amended.
- **The `core.*` count as a claim about structure.** ADR-0007's context says
  decision 10's vocabulary is structural and a host's domain step is not. Both
  types here are structural in exactly that sense - a shelf and a gap are
  facts about a document under construction, not about anybody's domain - and
  neither is a reason to widen the vocabulary further.
- **Two registries.** Neither type names an invoke type, so neither touches
  the seam ADR-0007 decision 3 states.

## Note (2026-09-01): reading G9b, and the duplicated G-labels

A dated precision note rather than an amendment, recorded for `sb-9ln1` under
the campaign-024 wrap walk (ruling 4). It decides nothing. No section above is
edited, no label is renumbered, no row is added or removed, no Status changes,
and every rule this record states means after this note exactly what it meant
before it. What is written down is three places a reader trips over, corrected
by reference in the same form G8 used for G3's count sentence.

### Reading G9b's "none accepts `:any`"

G9b says:

> Every slot in the shipped `core.*` vocabulary accepts `[:step]` or
> `[:interrupt_handler]` and none accepts `:any`

Read literally that is false, and G9c three paragraphs below it is what makes
it false: `core.drafts` declares `slot_accepts: %{"body" => :any}`, and
`core.drafts` is in the shipped `core.*` vocabulary because G9 above put it
there. A reader who reaches G9b should carry the sentence with its qualifying
clause attached:

> ... and none accepts `:any` **except `core.drafts`'s own `body`**, which
> G9c declares `:any` deliberately.

**The refusal argument G9b is making survives the clause**, which is why this
is a note and not an amendment. What that argument needs is that a block
declaring `kinds: [:draft_shelf]` and nothing else is refused by ADR-0003
decision 3's ordinary intersection everywhere an author could drop it, and the
one slot the clause exempts is a shelf's own `body` - so the only document the
exception admits is a shelf nested inside another shelf. Such a document
carries two `core.drafts` blocks, and G12b refuses it: ADR-0004's D3 mints
`:duplicate_drafts_block` against the second in document order, and
`:drafts_block_misplaced` against the one that is not a direct child of the
root's `body`. The exception therefore lands inside the case G9b already hands
to G12 rather than escaping it. The untyped host container of G9b's own
paragraph is the other one, and it is unchanged.

### Reading G9b's "only the two cases it alone can decide" against ADR-0004's D3

G9b closes by saying the ordinary mechanism refuses a shelf at drag time
everywhere in the shipped vocabulary, and that G12's rule is "left carrying
only the two cases it alone can decide". ADR-0004's D3 states
`:drafts_block_misplaced` unconditionally - *a `core.drafts` block appears
somewhere other than as a direct child of the root block's `body` slot* - with
no carve-out for a placement assignability has already refused. The two
sentences read as though they disagree. They do not, and the campaign-024 wrap
ruling that filed this note settles which way to read them: **the D3
double-naming stands.**

The two sentences quantify over different things.

- G9b's is about **which cases G12's rule is the only thing deciding**. A
  shelf dragged at a `[:step]` slot is refused by assignability, so for that
  case G12's rule is not the only decider; the root's own admission and the
  untyped host container are the two where it is.
- D3's is about **which documents the Structure stage names**. That stage
  walks the document it is handed and does not ask whether an editor would
  have allowed the document to be built. A `core.drafts` block sitting in a
  `[:step]` slot is therefore named twice - `:kind_not_admitted` by ADR-0003
  decision 3 and `:drafts_block_misplaced` by D3 - and the redundancy is the
  contract rather than a defect in either record. A document can arrive from
  an importer, a fixture, a hand-edited file or a host that never ran the
  editor, and the compiler is the last place that can refuse it.

So G9b's "only" is scoped to G12's rule *being the sole decider*, never to
when D3's code fires. Neither sentence is edited and both stand as accepted.

### The G-labels collide four times, and how to cite one unambiguously

Section G (`core.assign` joins the core vocabulary, the 2026-08-29 amendment)
numbers its five paragraphs **G1** through **G5** in bold. Later amendments
number their own `###` sections **G2** through **G13**. Four labels therefore
name two different things in this record:

| Label | The bold paragraph inside section G | The later `###` section |
|---|---|---|
| G2 | `value` is `:string` in the shipped type | `core.send` joins the core vocabulary |
| G3 | `path` and decision 7's `datamodel_path?` key | The count, and what is still owed a row |
| G4 | What it compiles to | The moduledoc admonition goes |
| G5 | What stays open | `core.subchart` joins the core vocabulary |

G1 is section G's alone, and G6 through G13 are the `###` series' alone.

**Nothing is renumbered, and that is the point.** Both series sit in accepted
text that other records and this record's own Status line already cite by
label. Renumbering either would break every existing citation in order to fix
a citation problem.

**Every bare `G2`-`G5` citation written before this note means the `###`
section**, checked against each occurrence: the Status line's "section G2" and
"G5-G8", G3's own text, the 2026-08-29 subchart amendment's Status paragraph,
G8's count corrections, and the 2026-08-31 amendment's "the discipline G5
through G8 kept". Section G's bold paragraphs are never cited from outside
section G; the single citation of `G1` (in G2b) is unambiguous because G1 does
not collide.

**From this note forward**, cite a bold paragraph inside section G as **G.G1**
through **G.G5**, and a `###` section by its bare label, **G2** through
**G13**. A reader meeting a bare `G3` in text older than this note reads the
`###` section, per the paragraph above.

## Note (2026-09-02): `core.wait` arms a delayed send too, so the send-id amendment's section C is stale in one clause

A dated precision note rather than an amendment, recorded for `sb-4m2` under
the campaign-015b queue-walk ruling (item 10), which filed it after the PR 132
direction-agent review surfaced the sentence as pre-existing staleness. It
decides nothing. No section above is edited, no row is added or removed, no
Status changes, and every rule this record states means after this note exactly
what it meant before it.

### The clause, and why it was never accurate

The send-id amendment of 2026-08-29 closes with section C, "What this amendment
does not change" (:1414). Its third bullet reads:

> - Any other block type's declarations. Nothing but `core.send` arms a delayed
>   send, so nothing but `core.send` is touched.

The middle clause was inaccurate on the day it was accepted. `core.wait`
compiled to a `<send>` carrying a `delay` before that amendment, minting the
id under a `"timer"` role of its own, and it is inaccurate for a second reason
now: `sb-cqg` (PR 132) moved the wait's id onto the **same reserved send role**
`core.send` mints under, so the two types are no longer even distinguishable by
the role their armed send carries.

### What is accurate at `main`

Two types in the shipped `core.*` vocabulary arm a delayed send, and they mint
the id through the same reserved role.

| Type | `emit/2` at `main` | Where the id is minted | Is the send always delayed? |
|---|---|---|---|
| `core.send` | `lib/statifier_blocks/core/send.ex:264-279` | `:267` | no - `delay` is optional, and an absent one emits no `delay` attribute |
| `core.wait` | `lib/statifier_blocks/core/wait.ex:171-190` | `:175` | yes - `duration` is required |

The two emit sites, quoted:

```elixir
# lib/statifier_blocks/core/send.ex:267
with {:ok, id} <- Context.role_id(context, Cancels.armed_role()),

# lib/statifier_blocks/core/wait.ex:175
     {:ok, send_id} <- Context.role_id(context, Cancels.armed_role()),
```

and each hands that id straight to the `<send>` it builds - `send.ex:270-273`,
and `wait.ex:180`:

```elixir
# lib/statifier_blocks/core/wait.ex:180
Emission.element("send", [{"delay", delay}, {"event", event}, {"id", send_id}])
```

`Cancels.armed_role/0` is the one place that string lives
(`lib/statifier_blocks/compiler/cancels.ex:139-140`), and `Cancels` reads it
back to emit one `<cancel sendid="..."/>` per armed send in the arming scope's
`<onexit>` (`:218-220`). A `core.wait` left before its delay elapses is
therefore cancelled by exactly the mechanism a `core.send`'s delayed send is,
because it is the same mechanism reaching the same role. ADR-0004's Note of
2026-08-29, "`core.wait`'s timer rides the reserved send role", is the record
that decided this; this note only carries it across to the record whose
sentence a reader would otherwise trust.

### The deadline spelling arms one as well, through `core.send`

ADR-0010 decision 1 spells a clock interrupt as a `core.send` carrying the
deadline event and a `delay` at the head of a group's `body`, paired with a
`core.on_event` on its rail, and its decision 3 turns on this same scope
cancel: the body region exiting fires `Cancels`, and the armed deadline goes
with it. That adds no third arming type - a deadline **is** a `core.send` - but
it is where a reader most often meets an armed delayed send that is not written
as "a send block", so it is named here rather than left for them to infer.

### What section C still gets right, and what this note does not do

C's third bullet is about **declarations**, and on that it is correct and
stands: no other block type's declared shape is changed by the send-id
amendment, `core.wait`'s included - its `duration` field, its outcome and its
slot declarations are what they were before that amendment and what they are
after it. Read the bullet as the declaration claim it makes, and read its
middle clause as corrected by this note in the same by-reference form G8 used
for G3's count sentence and the 2026-09-01 note used for G9b.

Section C is not rewritten and nothing above this line is edited. Decision 10's
vocabulary table does not grow, no config schema changes, and the send-id
amendment's two rulings stand exactly as accepted. `core.wait` arming a delayed
send is not new behaviour blessed here - it is behaviour ADR-0004 and
`core.wait`'s own moduledoc already carry.

## Note (2026-09-05): decision 7 and G2a, a `:duration` reads one grammar

A dated Note rather than an amendment, because nothing this record decides
moves. Decision 7's closed field-type set is untouched: `:duration` is still
one of the seven types, still holds a string, and `core.send`'s `delay` is
still an optional `:duration` field with a `""` default. What moves is which
strings that string may be, and that is ADR-0005 decision 9's to decide.

**That amendment is in flight, not settled.** ADR-0005's decision-9 amendment
of this date is **proposed**, on its own gate and under its own bead; what it
settles is that record's to state, and this Note neither depends on its text
nor speaks for it. What follows records which passages here that amendment
reaches, and how they are to be read once it is accepted. Until then both
passages stand exactly as they were written on 2026-08-29.

### What the record that owns it proposes

ADR-0005's amendment of 2026-09-05 to its decision 9 - proposed, and merging
at proposed - reverses the clause that kept an older, calendar-style duration
spelling accepted beside the expression language's. It reverses it on a fact
rather than a preference: the operative argument for keeping that spelling was
that documents already written hold it, and a sweep found no such document -
the spelling survives only in this package's own records, moduledocs and
fixtures, all of which this package migrates itself.

### The two passages here that clause reaches

- **The dated cross-reference beside decision 7**, added 2026-08-29. It tells a
  reader to take decision 7's parenthetical for `:duration` as naming a pivot
  rather than the only spelling `config` may hold. Once that amendment is
  accepted there is no pivot and no second spelling: a `:duration` holds a
  string the expression language's duration grammar parses, and a compile
  renders the emitted attribute straight from it. Decision 7's own sentence is
  unchanged, and so is the reading that its parenthetical names a
  representative spelling rather than a grammar - the representative spelling is
  simply a different one now.
- **G2a**, in the `core.send` row of the 2026-08-29 amendment, whose middle
  clause accepts a present `delay` in either spelling through
  `StatifierBlocks.Core.Duration`. On that amendment's acceptance a present
  `delay` is accepted in one spelling, the expression language's, and a value in
  the other is refused like any other unparseable string. G2a's other claims
  stand exactly as written: an absent `delay` key and the field's own `""`
  default are both "no delay" and neither is a finding, and decision 7's field
  type is untouched by the row.

Read both by reference, in the same form G8 used for G3's count sentence and
the 2026-09-01 note used for G9b. Neither is rewritten.

### What this Note does not do

- It does not change **G2b**'s rule, though it does narrow what one of G2b's
  words denotes. `validate_config/1` still checks shape only: it refuses an
  `event` that is not an event name and a stored `delay` that is, in G2b's own
  phrase, "neither spelling", and it refuses nothing else. What the pivot
  changes is the count that phrase presupposes - after it there is one
  spelling rather than two, so the same sentence is read as "not a duration in
  the expression language's grammar". The rule, and what a config callback is
  for, are untouched.
- It does not change **G2c**, or anything about what a compiled `core.send`
  emits beyond which bytes can have been stored to produce the `delay`
  attribute. The attribute is still written only when there is one, and still
  never attributed verbatim.
- It does not change decision 10's vocabulary table, any config schema, any
  `io/1`, or any other block type's declared shape. The one other declared
  `:duration` field, `core.wait`'s `duration`, is reached by that same
  proposed amendment for the same reason and by the same record, not by any
  decision taken here. There is no third such field to reach: ADR-0010
  decision 1, accepted 2026-09-02, settles that a clock interrupt is the
  `core.send` + `core.on_event` pair and that no `core.timeout` exists.
- It does not itself carry the wording rule that comes with the pivot. No
  refusal message, example or documentation line in this package names the
  retired spelling; that rule is ADR-0005's amendment clause 9d, and it binds
  the messages the rows above describe.

The code follows the records rather than preceding them: the recogniser, the
refusal wording and the fixture migration land on `sb-4r1p`. Nothing above this
line is edited.

Filed with `sb-8acm`, campaign-029's Lane A.

## Note (2026-09-05): decision 8, `core.wait` and `core.send` become its first users

A dated Note rather than an amendment, because nothing this record decides
moves. Decision 8's rules on `type_version` migration are unchanged in every
particular, no row is added to decision 10's vocabulary table, no
`config_schema/1` changes, no callback is added to or removed from the
behaviour, and no Status changes. No section above this line is edited.
Recorded ahead of the code, bead `sb-8vkc`, campaign 030 Lane S0; it merges at
proposed under the campaign invariant like every other section filed with it,
and flipping it to accepted is a separate gated request. `sb-me4u` implements.

### What is about to be true, and why it is worth a line

Decision 8 gave this package a migration mechanism in its founding record and
nothing has used it since. `migrate_config/2` has been an optional callback on
the behaviour from the beginning (`lib/statifier_blocks/block_type.ex:304-310`),
every shipped `core.*` type is still at `current_version/0` of 1, and so no
block has ever been behind its module and the callback has never been called.

How a type would answer if one were is worth stating precisely, because the
obvious reading is wrong. Fourteen of the fifteen declare `@behaviour
StatifierBlocks.BlockType` rather than `use` it, so they do not carry the
`__using__` default at `lib/statifier_blocks/block_type.ex:124-130` at all -
`core.placeholder` is the only one that does
(`lib/statifier_blocks/core/placeholder.ex:56`). For the other fourteen the
callback is simply not exported, and a behind-version block of one of them
takes `Palette.resolve/2`'s no-callback arm,
`{:error, {:migration_failed, block_id, :no_migration_available}}`
(`lib/statifier_blocks/palette.ex:262-269`). Decision 8's 2026-08-27 amendment settled the
three semantics an implementation would need - the typed error for a failed or
absent migration, the single hop rather than a version ladder, and the stored
`type_version` left as stored - against no implementation at all.

That changes on `sb-me4u`. ADR-0005's decision-9 amendment of 2026-09-05
retired a duration spelling, and its Note of this date settles that a document
holding the retired spelling is **migrated at open** rather than refused. The
mechanism it reaches for is this record's, unmodified:

| Type | `current_version/0` today | after `sb-me4u` | Config key the migration rewrites |
|---|---|---|---|
| `core.wait` | 1 (`lib/statifier_blocks/core/wait.ex:39`) | 2 | `"duration"`, its one `:duration` field |
| `core.send` | 1 (`lib/statifier_blocks/core/send.ex:102`) | 2 | `"delay"`, its optional `:duration` field |

These are the first two `migrate_config/2` implementations in the package, and
they exercise decision 8 exactly as written: the migration runs at resolution
time, is a single hop from 1 straight to 2, is applied to the in-memory block,
and leaves the stored `type_version` alone, so a host that never saves the
document never has its bytes rewritten. Which strings the migration reads and
what it writes are ADR-0005's, not this record's; what this Note fixes is that
the two rows above are the whole of the change to this record's subject matter.

There is no third `:duration` field in the shipped vocabulary for the same
migration to reach. The 2026-09-05 Note above already establishes that, and
ADR-0010 decision 1's refusal of a `core.timeout` is why it stays true.

### What this Note does not do

- It does not change decision 7's closed field-type set, or the type of either
  field named above. Both are still `:duration` and both still hold a string.
- It does not change either type's `validate_config/1`, `slots/1`, outcomes, or
  what its `emit/2` writes. A `core.send` still emits a `delay` attribute only
  when there is one, and a `core.wait` still requires its `duration`.
- It does not make migration mandatory, general, or a pattern other types are
  expected to follow. Decision 8's "absent means the type has never changed its
  config shape" is unchanged, and the other thirteen shipped types stay absent.
- It does not decide persistence. Whether a migrated document is written back
  is the host's, on the host's own `revision` axis, exactly as decision 8 says.

Filed with `sb-8vkc`, campaign-030's Lane S0.

## Note (2026-09-05): the two Notes above, five corrections to how they read

A dated Note about the two dated Notes above it, not about this record. No
decision moves: decision 7's closed field-type set, decision 8's migration
rules, decision 10's vocabulary table and the 2026-08-29 send-id amendment
are all exactly as they were, no `config_schema/1` changes, no callback is
added to or removed from the behaviour, and no Status changes. No text above
this line is edited by this section. Every correction below was raised in
review against the request that added the Note it concerns and routed to a
follow-up rather than cured in place, so each merged artifact stayed the
artifact its review read. Recorded under campaign 030's fill lane D.

**1. Where a proposed rule is written in the flat indicative, read it as
proposed.** The last bullet of the 2026-09-05 Note on decision 7 and G2a
reads "No refusal message, example or documentation line in this package
names the retired spelling" (`:2540-2542`). That is the shape of a rule
already in force, and it is not one: the rule is ADR-0005's amendment clause
9d, which is proposed and merged at proposed, and the code bringing the
package into line with it is its own bead. Read the sentence as what clause
9d requires once accepted. The bullet's next clause says as much - "that rule
is ADR-0005's amendment clause 9d" - so this corrects the mood of one
sentence and nothing else.

**2. The same, for the sentence about decision 7's parenthetical.** The first
bullet under "The two passages here that clause reaches" ends "and so is the
reading that its parenthetical names a representative spelling rather than a
grammar - the representative spelling is simply a different one now"
(`:2503-2505`). "Now" asserts an effect the amendment that produces it has
not yet taken. That Note's own opening is the governing sentence - "Until
then both passages stand exactly as they were written on 2026-08-29"
(`:2482`) - so read the clause as "the representative spelling is a different
one once that amendment is accepted". ADR-0005's matching "superseded in one
clause each" is to be read the same way, and a Note of this date in that
record says so on its own side.

**3. "Pivot" carries two senses, forty lines apart.** In the first bullet
under "The two passages here that clause reaches" a pivot is the older
intermediate form a compile canonicalised through before emitting - the thing
ADR-0005 clause 9c abolishes (`:2498-2500`). Under "What this Note does not
do" the same word names the reversal itself: "What the pivot changes is the
count that phrase presupposes" (`:2523-2524`), and "the wording rule that
comes with the pivot" (`:2540`). Read the first as the intermediate form and
the other two as the 2026-09-05 change of grammar. No claim in either
sentence is affected; the word is doing two jobs and a reader should not have
to notice that unaided.

**4. G2c's "verbatim" belongs to `event`, not to `delay`.** The restatement
under "What this Note does not do" says a compiled `core.send`'s `delay`
attribute "is still written only when there is one, and still never
attributed verbatim" (`:2528-2531`). G2c itself is stricter: `event` is
"attributed as the author's verbatim", while `delay` is "written only when
there is one and never attributed (its bytes are canonicalised)"
(`:1471-1474`). `delay` is never the stored string at all, verbatim or
otherwise, so the trailing qualifier reads as though some non-verbatim
attribution of the stored string were the thing left standing. Read the
restatement as "still never the stored string". G2c's own sentence is
unchanged, and what ADR-0005 clause 9c moves is only the mechanism between
the stored string and the attribute - the middle canonical form goes and the
normalised duration renders straight - which leaves G2c's claim true on both
sides of it.

**5. "The other thirteen shipped types stay absent" is shorthand.** The Note
on decision 8 above says decision 8's "absent means the type has never
changed its config shape" is unchanged, "and the other thirteen shipped types
stay absent" (`:2615`). Read "absent" there as "has no migration of its own",
which is what the sentence is about. Read literally as "exports no
`migrate_config/2`" it is untrue of one of the thirteen: `core.placeholder`
is the single shipped type that `use`s the behaviour
(`lib/statifier_blocks/core/placeholder.ex:56`) and so carries the
`__using__` default (`lib/statifier_blocks/block_type.ex:124-130`), which
exports the callback and refuses. The paragraph above that bullet, in the
same Note, has this exactly right; only the shorthand is loose.

Filed with `sb-a9r8`, campaign-030's fill lane D.

## Amendment (2026-09-05): decision 7, the `{:path, opts}` field type

**Status: proposed (2026-09-05).** Drafted for `sb-5v3i` under the operator
campaign-031 grant, and merging at proposed under that campaign's invariant
like every other section filed with it; flipping it to accepted is a separate
gated request. Additive; decision 7, its 2026-08-27 `value_path` amendment,
its 2026-08-29 `datamodel_path?` amendment and its 2026-08-29 `sensitive?`
amendment all stand exactly as written, and no text above this line is edited
by this section. A dated Note beside the `datamodel_path?` amendment's first
bullet records that this section reverses it.

### Context

That 2026-08-29 bullet refused a `:path` type on one argument: the input is
textually identical to a `:string`'s, so a second control would render the
same box twice. The argument was about bytes, and what has since become
visible is that identical bytes are not identically authorable.

Two shipped facts make it visible. The first is that the claim rides a key a
host has to know exists. A host block type whose config holds a datamodel
path writes `type: :string` and stops, because `:string` is the whole answer
the field-type set gives it; it then gets no candidate list and no
undeclared-path advisory, and nothing in its declaration says anything is
missing. This package's own vocabulary already has that gap in it. Of the
core fields that hold a path, `core.assign`'s `path`
(`lib/statifier_blocks/core/assign.ex:73-79`) and `core.foreach`'s `items`
(`lib/statifier_blocks/core/foreach.ex:174-185`) carry `datamodel_path?:
true`, and `core.subchart`'s `assign_to`
(`lib/statifier_blocks/core/subchart.ex:197-203`) is a bare `:string` that
does not.

The second is that there is now something for a control to offer.
`StatifierBlocks.Datamodel.candidates/3`
(`lib/statifier_blocks/datamodel.ex:380-387`) computes the declared paths,
and ADR-0005 clause 11e fixes what an undeclared one produces. Both hang off
a field, and the thing the editor's control table is keyed on is the field
type.

### Decision

**Decision 7's closed field-type set gains an eighth member, `{:path,
opts}`.** The set is `:string`, `:integer`, `:boolean`, `{:select, choices}`,
`:expression`, `:duration`, `{:list, field_type}`, and now `{:path, opts}`.
It is still closed, and this is a widening by one named member rather than an
opening: the property the closed set exists for is that the editor can draw
every member, and `{:path, opts}` is the member it can draw best.

A `{:path, opts}` field holds a path into the host's datamodel - exactly the
claim `datamodel_path?: true` makes about a `:string`. What the type adds is
that the editor reaches the right control by the field type alone:

- **Candidates.** The control offers `StatifierBlocks.Datamodel.candidates/3`'s
  result for the document and the host-supplied datamodel. With no datamodel
  supplied there are no candidates and the control is a plain text input,
  which is what a `:string` was.
- **The advisory.** ADR-0005 clause 11e's `:info` finding for an undeclared
  path stays anchored on the field's `key`, as it already is. This section
  changes which fields the advisory reaches, not what it says or what it
  costs.

**`opts` carries no defined key today.** It is the second element of a tuple
for the reason `{:select, choices}` and `{:list, inner}` have one: so that
what a control needs can arrive without widening the set a second time. The
`path_kind` enum the 2026-08-29 amendment refused stays refused, on its own
argument and unamended - there is still one kind of path, and an enum still
wants a second member before it is written. Read/write direction, which
`core.foreach`'s source comment names as inexpressible with a boolean
(`lib/statifier_blocks/core/foreach.ex:180-183`, quoted in G6), is the first
candidate for a key on the day a consumer needs one. Until then a declaration
writes `type: {:path, %{}}`.

**The `datamodel_path?` key is not withdrawn, and the two spellings mean one
thing.** A field declaring `{:path, opts}` makes the claim the key makes; a
field declaring `:string` with `datamodel_path?: true` keeps making it, keeps
its control and keeps its advisory, so every declaration written before this
section behaves exactly as it did. There is one place a consumer asks the
question today - `StatifierBlocks.BlockType.datamodel_path?/1`
(`lib/statifier_blocks/block_type.ex:580-582`), whose own doc says to read
the claim through it and never by matching the key (`:245-246`) - and that
function is the code's, not the 2026-08-29 amendment's: that section adds one
optional key to decision 7 and names no reader. This section relies on it
only for what follows from its existing there, which is that reading the
claim off either spelling can be its business rather than every caller's.
A declaration carrying both says the same thing twice; it is not a finding
and not a contradiction.

### What this section does not decide

- **Which fields migrate, and when.** Nothing migrates by this section being
  accepted. `core.subchart`'s `assign_to` is the one core field that holds a
  path and declares nothing about it, and it migrates on `sb-2ym4` together
  with whatever the other path fields do there.
- **The control's markup.** Whether a candidate list is drawn as a
  `<datalist>`, through ADR-0005 decision 9's `expression_component` seam, or
  as something else is ADR-0005's question. `candidates/3`'s own moduledoc
  already says the shipped answer is a datalist in the meantime, and this
  section does not move it.
- **Validation.** `validate_config/1` is still the authority per decision 7,
  and the schema is still not a validation language. A `{:path, opts}` field
  whose value is not a declared path produces ADR-0005 clause 11e's advisory
  and no verdict, which is unchanged.
- **The record's own typespec appendix is not edited, and neither is the
  code, yet.** Decision 7's list is written out in three other places. Two are
  code - `field_type/0` (`lib/statifier_blocks/block_type.ex:146-153`) and the
  "seven closed `field_type/0` values" sentence in `config_schema/1`'s doc
  (`:210-212`) - and the code follows the record, so `sb-2ym4` moves both. The
  third is *The contract as typespecs* above, whose `field_type` union lists
  the same seven (`:448-455`). That block is this record's snapshot at
  acceptance and no amendment has edited it since: the `field_decl` map beside
  it (`:457-463`) still shows neither `value_path` (2026-08-27) nor
  `datamodel_path?` and `sensitive?` (both 2026-08-29). This section is read
  into it the same way, by reference, and adds `{:path, opts}` to the union in
  the reading rather than in the bytes. A reader who finds seven values in
  either place and eight here is looking at that convention, not at drift.

Filed with `sb-5v3i`, campaign-031's lane H. `sb-2ym4` implements.

## Amendment (2026-09-05): decision 10, the `core.await` row

**Status: proposed (2026-09-05).** Drafted for `sb-5v3i` under the operator
campaign-031 grant, and merging at proposed under that campaign's invariant;
flipping it to accepted is a separate gated request. Additive; decision 10's
original seven-row table stands, the 2026-08-28 amendment's section D stands,
sections G through G13 stand, and no text above this line is edited by this
section. Like G9 and G10, this row is written **ahead of the module that will
answer it**: `sb-m0t1` builds to this record rather than this record being
read off the build, and the dated Note beside G11 says what the counts are
while that is true.

### Context

A workflow that has to hold at a step until something outside it happens has
one spelling in the shipped vocabulary, and it is a `core.group` whose
`interrupts` slot carries a `core.on_event`. That arrangement is built for an
interrupt - an event arriving *while* the group's body does other work - and
a wait is the case where the arriving event is the only thing the step is
for. The two read differently to an author, and, as G14b works out, they are
not the same shape to the compiler either.

### G14. `core.await` joins the core vocabulary

| Block type | `slots(config)` | Config schema | `outcomes(config)` | Notes |
|---|---|---|---|---|
| `core.await` | `[]` | `event`: `:string`, required, default `""`; `timeout`: `:duration`, optional, default `""` | `received`, `timed_out` | an in-flow leaf that holds until a named event arrives, with an optional deadline; the two outcomes are the two ways it can end |

In full, so a reader need not hold the rest of this section in their head.
`slots/1` returns `[]` for every config. `config_schema/1` returns the two
declarations above, in that order, with labels the palette entry's wording
settles. `validate_config/1` refuses an `event` that is not an event name -
the same `StatifierBlocks.Core.Config.event_name?/1` check
(`lib/statifier_blocks/core/config.ex:46`) that `core.on_event` and
`core.send` already apply - and refuses a present, non-blank `timeout` that
the duration grammar does not parse; it refuses nothing else. An absent or
blank `timeout` is "no deadline" and is not a finding, exactly as an absent
`core.send` `delay` is not one (G2b). `current_version/0` is `1`. `io/1` is
`%{kinds: [:step]}`, which is `core.wait`'s declaration byte for byte
(`lib/statifier_blocks/core/wait.ex:100`), leaving `consumes` and `produces`
to ADR-0003 decision 5's permissive default because awaiting transforms no
data - and that identity is what "valid wherever `core.wait` is" means.

`timeout` is a `:duration`, so it reads the one grammar the 2026-09-05 Note
on decision 7 and G2a describes, through the same
`StatifierBlocks.Core.Duration` pair `core.wait` and `core.send` call. It is
the **third** declared `:duration` field in the vocabulary, and the two Notes
of this date above - the one on decision 7 and G2a, and the one on
decision 8 - each say there is no third. Both are right about the vocabulary
they were counting, the fifteen rows that existed when they were written, and
both give the same ground for it: ADR-0010 decision 1 refuses a
`core.timeout`. That ground is untouched (G14b), and this row is a third
field they could not have counted rather than a contradiction of either. The
consequence they draw from the count - that `core.wait`'s `duration` and
`core.send`'s `delay` are the whole of what the grammar change and the
`migrate_config/2` work have to reach - stands as written: `core.await` has
no shipped documents to migrate, and it is authored in the one grammar from
its first day.

**G14a. What it compiles to, and why its timer cannot outlive it.** A
compiled `core.await` is a compound state with one waiting child and one
`<final>` per outcome. The waiting child carries a transition on the
configured `event` to the `received` outcome's final. When `timeout` holds a
non-blank duration it also carries an `<onentry>` `<send>` with that delay
and a generated event name carrying the block id - the shape `core.wait`
emits (`lib/statifier_blocks/core/wait.ex:194-206`) - and a second transition
on that generated event to the `timed_out` outcome's final. The exact bytes,
the state ids and the outcome finals' names are ADR-0004's and `sb-m0t1`'s;
what this row records is that the type declares the callbacks above.

The send id is minted with `Context.role_id/2` under
`StatifierBlocks.Compiler.Cancels.armed_role/0`
(`lib/statifier_blocks/compiler/cancels.ex:140`), which is exactly how
`core.wait` mints its own (`lib/statifier_blocks/core/wait.ex:195`). That is
the whole of the timer's lifetime story, and it is inherited rather than
built: `Compiler.Cancels.arm/2` (`:153`) already reaches every armed send a
scope's direct children minted and cancels it in the scope's `<onexit>`, so
an await left before its deadline - because the awaited event arrived,
because an interrupt fired, because a losing `complete: first` lane exited,
because a group was abandoned - leaves no timer behind. An await with no
`timeout` arms nothing, and there is nothing to cancel. Nothing in
`Compiler.Cancels` changes for this row.

*[Note added 2026-09-06, with `sb-6uzm` under campaign-032: G14a's first
sentence pre-dates the answer the Note beneath G14d records, and now reads
looser than what ships. "One `<final>` per outcome" was written while G14d
still held the outcome list open, and the count it states is the count for an
await whose `timeout` is stored, not for one whose `timeout` is blank.

What ships is one `<final>` per outcome the block can reach. `outcomes/1`
returns both `received` and `timed_out` for every config
(`lib/statifier_blocks/core/await.ex:123`), while `emit/2` writes the
`received` final unconditionally and takes the `timed_out` final from the
deadline (`:271-290`): `deadline/4`'s no-deadline clause returns empty
`onentry`, `transitions` and `finals` together (`:298-299`) and its other
clause returns all three (`:301-312`), which is the "a deadline is all of
this, or none of it" decision its own comment names. An await with no
`timeout` therefore compiles to the awaited transition and one final. The
paragraph above already makes the `<onentry>` `<send>` and the timer
transition conditional on a stored `timeout`; the final that transition
targets is conditional on the same thing, and only the sentence's opening
count reads otherwise.

This is the shape the Note beneath G14d names rather than a new one, and
`core.subchart` is where the vocabulary already carries it: `outcome_names/1`
appends `error` whether or not the author listed it
(`lib/statifier_blocks/core/subchart.ex:516-521`), while `finals/1` emits a
`<final>` only for an outcome that is routed or slotted (`:500-505`). Read
G14a's opening sentence as the declaration count and the Note beneath G14d as
the emission count. Nothing else in G14a changes: the waiting child, the two
transitions, the send id and the cancel story stand as written.]*

**G14b. Why this is a row and not an arrangement.** ADR-0010 decision 1
states the vocabulary's admission test in its sharpest form: a type whose
whole content is a spelling of an arrangement the vocabulary already
expresses does not join the vocabulary. A clock interrupt failed that test,
because the `core.send` and `core.on_event` pair already expresses it. This
row passes it, on the mechanism-shaped reading ADR-0009 used for `core.map`.

The nearest arrangement is a `core.group` whose `interrupts` rail carries a
`core.on_event` for the awaited event with `outcome: "abandon"`, plus - for
the deadline - the deadline recipe's head-of-body `core.send` and a second
`core.on_event` for the timer event. It does not express the row above, and
the reason is one fact about what a handler compiles to: a handler's outcome
word becomes one of exactly two package-owned events,
`statifier_blocks.interrupt.abandon` and `statifier_blocks.interrupt.resume`
(`StatifierBlocks.Core.Emit.interrupt_events/0`,
`lib/statifier_blocks/core/emit.ex:77-78`), and the enclosing group
transitions on those. Neither `core.group` nor `core.resumable_group`
declares `outcomes/1` at all, so both take section A's default and finish
with the single outcome `done`. Two `abandon` handlers on one rail are
therefore indistinguishable to everything downstream of the group: the seam
an author would wire `received` and `timed_out` into does not exist there,
and no quantity of additional blocks produces it. `core.await` declares the
two outcomes directly, which is the mechanism the arrangement is missing -
the same test `core.map` passed when no arrangement of the fifteen could
start N children.

This does not reopen `core.timeout`, and ADR-0010's decision 1 is untouched.
A clock interrupt is a deadline on *other work* running inside a group, and
the pair is still its spelling; an await's `timeout` is a deadline on the
await itself, which has no other work to interrupt. ADR-0010's "no row is
added to ADR-0002 decision 10's vocabulary table" is that record's statement
about its own case, not a freeze on the table, and the counts it quotes are
reached by the Note beside G11.

**G14c. `core.await` and `core.wait` are one word apart, and this section
says which is which rather than renaming either.** A `core.wait` holds for a
duration and ends one way; a `core.await` holds for an event and ends one of
two ways, one of which may be a duration elapsing. The names are close
because the things are close, and the record's own convention where two names
could be confused is G10a-i's: say which is meant rather than avoid the word.
Where either could be read, this record says *a wait* for the duration leaf
and *an await* for this row, and never lets an unqualified verb carry the
difference. Renaming `core.wait` is not on the table: it is a
shipped type in shipped documents, and ADR-0001 decision 4 makes a type name
part of the stored bytes.

**G14d. One thing this row deliberately leaves to `sb-m0t1`: the outcome list
when no `timeout` is stored.** The row declares `received` and `timed_out`,
which is what the ruling says. `outcomes/1` takes `config` for exactly this
kind of question - `core.subchart`'s outcome list is config-derived already
(G5) - so two answers are available and this section picks neither, because
the ruling did not.

- Return both outcomes always. Simplest, and an author's wiring survives
  toggling the deadline off and on; the cost is a `timed_out` seam on an
  await that can never take it, which ADR-0004's totality then has to emit
  something for.
- Return `["received"]` when `timeout` is blank and both when it is not. No
  unreachable seam; the cost is that clearing the `timeout` field silently
  removes a seam an author had already wired, which is the failure decision
  6's `slots/1` stability rule exists to avoid on the slot side.

`sb-m0t1` decides it against the compiler and records the answer as a dated
Note here. Neither answer changes any other claim in this section.

Filed with `sb-5v3i`, campaign-031's lane H. `sb-m0t1` implements.

*[Note added 2026-09-05, with `sb-m0t1` under campaign-031 ruling D31-2, and
the answer G14d above leaves to it: **`outcomes/1` returns both outcomes for
every config**, including one with no `timeout`. The first of G14d's two
options, and the compiler is what picks it.

The cost G14d puts against that option - "a `timed_out` seam on an await that
can never take it, which ADR-0004's totality then has to emit something for" -
is not a cost this option actually carries, and the record already says why.
ADR-0004's outcome amendment, 2c, states it as the third of its three
consequences: "an outcome a block never reaches costs a parent nothing",
because the wiring is an event and not a target, so a parent may transition on
an outcome whose `<final>` was never emitted, the transition simply never
fires, and no `{:unresolved_target, _}` finding results. The compiler agrees:
`Compiler.validate_outcomes/2` (`lib/statifier_blocks/compiler.ex:981`) checks
the declared names' role shape and their uniqueness and nothing else, so no
stage cross-checks a declaration against an emitted final. Nor does totality
reach one: ADR-0004 decision 5 makes provenance total over the bytes that
**are** emitted, and a final that was never written is not bytes.

The vocabulary already contains a type in exactly this position, and it is
`core.subchart` rather than the `core.invoke` 2c names. `core.subchart`
declares `error` whether or not the author listed it - `outcome_names/1`
(`lib/statifier_blocks/core/subchart.ex:463-467`) appends it, so
`BlockType.outcome_names(Core.Subchart, %{})` is `["done", "error"]` - while
`finals/1` (`:448-453`) emits a `<final>` only for a route that is routed or
slotted, and its own comment beside that function draws the conclusion from
2c: "an outcome the block can never reach emits no `<final>`". A declared
outcome with no final is therefore a shipped shape, not a new one, and
`core.await` joins it.

The two neighbouring shapes are worth naming so this Note is not read as
claiming all three are one. `core.invoke` is the **inverse** case: it exports
no `outcomes/1` at all, so under amendment A1 it declares the single default
outcome `done`, while `emit/2` writes an `error` final only when its
`on_error` slot is filled (`error_parts/1`,
`lib/statifier_blocks/core/invoke.ex:261-271`) - emitted but never declared.
`StatifierBlocks.InvokeStep`, the ADR-0007 host base, is the third shape: it
declares both `done` and `error` (`lib/statifier_blocks/invoke_step.ex:212`)
and emits both finals unconditionally (`:405-421`), with no `on_error` slot to
make either conditional.

The second option's cost is not discharged by anything. Clearing the `timeout`
field would remove a declared seam an author may already have wired, which is
the failure decision 6's `slots/1` stability rule exists to avoid on the slot
side and which amendment A1 extends to `outcomes/1` in the same words. A2 also
says outright that "a type could declare a second outcome reached from no slot
at all", so a declared outcome with no reachable final is a shape this record
already admits rather than a novelty this row would introduce.

(The palette count the Note beside G11 tracks moves with this module rather
than against it: `StatifierBlocks.Palette.core_types/0` registers **sixteen**
once it lands, which is that Note's gap closing exactly as it describes.)

What `sb-m0t1` emits follows `core.invoke` rather than declaring dead bytes: an
await with a `timeout` emits the `<onentry>` send, the timer transition and the
`timed_out` final together; an await without one emits none of the three, so
its compiled bytes are the awaited transition and the `received` final and
nothing else. The declaration and the emission disagree on purpose, and 2c is
where that is allowed. Neither this Note nor that choice changes any other
claim in this section.]*

## Note (2026-09-05): `core.on_event` takes an optional `capture`

A dated Note rather than an amendment, recorded for `sb-5v3i` under
campaign-031 ruling D31-3 and in the same form the 2026-08-31 Note above used
for `cond`: one optional field on a type this record already ships, and the
reason it belongs on the interrupt transition rather than on a `core.assign`
after it. The record's Status is untouched, no document authored without the
key compiles differently, and the vocabulary does not grow. Recorded ahead of
the code; it merges at proposed under the campaign invariant, `sb-0q0z`
implements, and no section above this line is edited.

### What the type carries now

Decision 10's table gives `core.on_event` two config fields, `event` and
`outcome`; the 2026-08-31 Note above declared a third, `cond`. It now
declares a fourth:

| Field | Type | Required? | Means |
|---|---|---|---|
| `capture` | a map, and not one of decision 7's field types - see below | no, default `%{}` | each pair writes one value out of the firing event's payload into the datamodel: the key is the datamodel path written, the value is the `_event.data` path read |

The direction is worth stating twice because a path-to-path map reads either
way: **the key is the destination** (a datamodel path, the thing the
2026-09-05 `{:path, opts}` amendment above is about) and **the value is the
source** (a path inside `_event.data`). A `capture` of
`%{"order.cancel_reason" => "reason"}` on a handler for `order.cancelled`
writes that event's `reason` into `order.cancel_reason`.

What is emitted is one `<assign>` per pair, on the transition the handler
already emits, **before** the `<raise>` that carries the outcome:

    <transition event="order.cancelled" target="s_INT__done">
      <assign expr="_event.data.reason" location="order.cancel_reason"/>
      <raise event="statifier_blocks.interrupt.abandon"/>
    </transition>

The pairs are emitted in their datamodel paths' sorted order. A map has no
order of its own and a compile has to be deterministic, so the record fixes
one rather than leaving the bytes to a map's iteration.

A handler whose `capture` is absent or empty writes no `<assign>` at all,
which is what makes this key additive in the way `cond` was: every document
authored before it existed compiles to the bytes it compiled to before.

### Why the assigns are on the transition and before the raise

The 2026-08-31 Note put `cond` on this transition for a reason about *when* a
condition is read, and the same fact places these assigns. The `<raise>` is
what tells the enclosing group to abandon or resume; by the time control is
anywhere else, that has happened. On `abandon` the group's body is gone and
the handler's own body may never run; on `resume` the body is re-entered and,
on a `core.resumable_group`, history decides where - so neither outcome
leaves a place after the raise where the payload is reliably still in hand.

`_event.data` is only in scope for the transition the event selected, which
is the other half of it. A `core.assign` placed after the handler is a
separate microstep with a different `_event`, so the payload is not merely
awkward to reach there, it is gone. That is why this is a key on the handler
and not an arrangement of two blocks, and it is the same argument the `cond`
Note made against a `core.branch` after the fact.

### The two failure shapes, and the one that is dormant

Neither an unwritten path nor a missing payload key is allowed to become a
silent `nil` in the datamodel - a captured value that quietly is not there is
the failure this Note exists to prevent, because everything downstream reads
it as an authored absence.

- **At run, an undeclared source path raises `error.execution`.** An
  `<assign>` whose `expr` does not resolve is an execution error in the
  interpreter, on the platform's own error event, and nothing about this
  Note's compiled form suppresses it.
- **At compile, a declared payload that lacks a named source path is a
  `:config` finding**, anchored on the `capture` key, naming the pair.

The second is **dormant today, and this Note says so rather than implying a
surface that exists.** Nothing in this package declares an event payload's
shape. The `:declare` compile option and `StatifierBlocks.Declarations`
declare the document's datamodel `<data>` roots, not event payloads, and
`fixtures/0`'s example payload is not a declaration either: it is one sample
per event name for a palette panel, its own doc calls the event name "an
example, not this block's configured `event`", and decision 9 marks the whole
callback PROVISIONAL (`lib/statifier_blocks/core/on_event.ex:208-232`). So
the `:config` branch is written here for the day a payload declaration
exists, and until then the run-time branch is the one that fires. What
`fixtures/0` **is** good for is the panel: it is where a `capture` control
gets its candidate source keys, which is a rendering affordance and not a
verdict.

### Note (2026-09-05): what the run-time branch actually does

The bullet above states the run-time branch as one rule. `sb-0q0z`, which
this Note's closing section names as the bead that confirms the interpreter's
behaviour before relying on it, measured the engine and found two rules
rather than one. This Note
records what was measured, because the paragraph above was written ahead of
the measurement and a record that keeps the unmeasured version would have
this package relying on a guarantee it does not have.

The engine splits on whether the expression's **root** is bound, not on
whether the whole path resolves:

| The `expr` | What the engine does |
|---|---|
| `_event.data.reason`, payload has `reason` | writes the value |
| `_event.data.reason`, payload lacks `reason` | writes the explicit unbound marker; raises nothing |
| `_event.data.reason`, event carries no data | writes the explicit unbound marker; raises nothing |
| `_event.data.a.b.c`, nothing at `a` | writes the explicit unbound marker; raises nothing |
| `nosuchroot.reason`, no such root | writes nothing; raises `error.execution` |

Measured with a hand-written chart carrying a single `<assign>` and an
`error.execution` transition on the enclosing parent state, so a raised
error is observable whichever target the machine reaches. Identical results
on `2.2.0`, the version this package locks, and on `2.5.0`, the newest
published one, so the finding does not turn on a stale lock.

Every `expr` a `capture` compiles to is rooted at `_event`, which is always
bound. So the row that governs this key is the second, not the last: **a
missing payload key is written as the marker, and no `error.execution` is
raised today.** The cites, in the engine's own tree:
`lib/statifier/machine/content/assign.ex:80` (`execute/2`) and `:120`
(`evaluate_value/2`), `lib/statifier/evaluator.ex:276-289` (`evaluate/2`,
built with the `on_unbound: :error` policy that produces the last row), and
`lib/statifier/interpreter/content.ex:296` (the single site that names
`error.execution` for executable content).

Two consequences for the red line this section opens with, and they pull in
opposite directions, so both are stated:

- **The `nil` clause holds, and is read as written.** The value the engine
  writes is its explicit unbound marker, which is not `nil` and is not
  `nil`'s spelling: the engine distinguishes unbound from null deliberately.
  So the failure this section exists to prevent - a captured value that
  quietly is not there, read downstream as an authored absence - does not
  occur, provided the consumer checks for the marker. That proviso is the
  whole of the correction: "no silent `nil`" is satisfied by the marker
  being a value a reader can test for, not by an error being raised.
- **The `error.execution` clause does not hold yet.** It is written above as
  present tense and it describes a future. It is carried upstream as
  `st-fwsh`, and it follows here when that lands; until then the bullet above
  is read as the target rather than the guarantee, and nothing in this
  package may be built on the error arriving.

The compile-time branch is unaffected and stays dormant for the reason the
paragraph above gives: nothing in this package declares an event payload's
shape, so there is no declaration for a `:config` finding to be checked
against. Correcting the run-time branch does not wake it.

### What this Note does not change, and what it leaves open

- **Decision 7's field-type set is untouched by this Note.** It grows by one
  member on this date, but by the amendment above and for `{:path, opts}`;
  `capture` is a map, no member of the set describes a map, and this Note
  does not add one. `core.on_event`'s `config_schema/1` therefore declares no
  field for `capture` yet, and how an author writes the pairs - a repeated
  two-control row, something else - is ADR-0005's question and `sb-0q0z`'s.
  Named here rather than guessed, in decision 11 and section F's habit.
- **The interpreter's behaviour on an unresolvable `expr` is statifier-ex's
  contract, not this record's.** This Note states what the compiled form must
  produce - an error, never a silent write - and `sb-0q0z` confirms the
  interpreter already produces it before relying on it. If it does not, that
  is an upstream question and not a licence to write `nil`.
- **The outcome words.** Still `"abandon"` and `"resume"`, still the pair
  ratified 2026-08-27, and a third still costs a `current_version/0` bump.
  `capture` is orthogonal to both: it runs before the raise whichever word
  the raise carries.
- **`cond`.** A guarded handler that does not fire captures nothing, because
  the assigns are on the transition the guard is on. No ordering question
  arises between the two keys.
- **The size of the core vocabulary.** No type is added by this Note; the row
  added on this date is `core.await`'s, in the amendment above.
- **The document schema.** ADR-0001 owns the stored bytes and
  `schema_version` stays at `1`. An optional key inside a block's `config`
  object is a block-type contract, which is this record's.

Filed with `sb-5v3i`, campaign-031's lane H. `sb-0q0z` implements.

## Amendment (2026-09-05): decision 10, the `core.map` row

**Status: proposed (2026-09-05).** Drafted for `sb-7haw` under the operator
campaign-031 grant, and merging at proposed under that campaign's invariant;
flipping it to accepted is a separate gated request. Additive: decision 10's
original seven-row table stands, the 2026-08-28 amendment's section D stands,
sections G through G14 stand, and no text above this line is edited by this
section.

### Context

ADR-0009 decision 11 assigned this row and named who owed it: "`core.map`'s
row would be the **sixteenth**, and it is an ADR-0002 amendment that lands
with the implementation - the implementation bead's to write, not this
record's" (`docs/adr/0009-fan-out-block-type.md:567-569`, decision 11's
ADR-0002 bullet). The implementation
bead is `sb-kqno`, which landed `StatifierBlocks.Core.Map` in PR 281
(`a852429`) under a campaign instruction that it touch no `docs/adr/` file.
The row it owed is therefore written here, by the bead the conductor filed
for the residue, rather than beside the code.

Unlike G9, G10 and G14, this row is read **off the shipped module** rather
than written ahead of it, in the habit G, G2 and G5 set: every callback below
is quoted from `lib/statifier_blocks/core/map.ex` at `main`, with its line, so
a reader can diff the record against the source.

**The ordinal has moved, and the row is not the sixteenth.** `core.await`'s
row (G14, this date) took that position between decision 11 being written and
this section being written. The dated Note beside G11 already reads decision
11's "sixteenth" as an ordinal counted from the fifteen rows that record saw -
it names the next row after those - rather than a reservation of a position.
This row is the **seventeenth**, and the Note added beside G11 on this date
records what the counts are once it lands.

### G15. `core.map` joins the core vocabulary

| Block type | `slots(config)` | Config schema | `outcomes(config)` | Notes |
|---|---|---|---|---|
| `core.map` | two `zero_or_one` slots, `on_done` then `on_error`, with `slot_style: %{"on_error" => :failure}` | `items`: `{:path, %{}}`, required, label "Over these items"; `chart`: `:string`, required, label "Run this chart for each"; `collect`: `{:path, %{}}`, optional, label "Collect the answers into"; `on`: `{:select, ...}` over `all` and `first_error`, optional, default `"all"`, label "Finish" | `done`, `error` - fixed, not config-derived | a step that runs another chart once per item of a datamodel list, all at once, as **one** invocation of a constant fan-out invoke type, and waits for the whole batch |

In full, so a reader need not hold the rest of this section in their head.

`current_version/0` is `1` (`:192`). `slots/1` returns the two slots above for
every config (`:215`) - `zero_or_one` for `core.invoke`'s reason, that an
outcome path is one continuation rather than a list of them. `outcomes/1`
returns `[{"done", "Done"}, {"error", "Error"}]` for every config (`:227`),
fixed rather than derived from the named chart; ADR-0009 decision 4 is why,
and its argument is that N children report N outcomes and joining them into
one branch target has no meaning, so the per-child answers go where data goes
and the block's own outcome says only whether the batch succeeded.

`config_schema/1` (`:230`) declares the four fields above, in the order
`items`, `chart`, `collect`, `on`. `items` and `collect` are the eighth field
type, `{:path, opts}`, from the 2026-09-05 amendment on decision 7, so the
editor offers the host's declared datamodel paths on both and a value the
datamodel does not declare draws ADR-0005 clause 11e's `:info` advisory rather
than a refusal. `on` carries the default `"all"`.

`validate_config/1` (`:275`) refuses an `items` or a `chart` that is not a
bare reference - blank, containing a space, or containing a single quote - a
`collect` that is present and not a bare lowercase identifier, refused in the
same words `core.invoke` and `core.subchart` produce for `assign_to`, and an
`on` outside the two permitted words. **It refuses nothing else, and in
particular nothing about N**; G15c says why. `on` is read *through* its
default in `core.parallel`'s G7a shape, so a block whose config never carried
the key validates and compiles exactly as it did before the key existed; a
stored `null` is not an absent key and is refused (ADR-0001 decision 6).
Refusing every word outside the two is also what reserves `quorum` for its own
walk, which ADR-0009 decision 6 asks for.

`io/1` (`:329`) is `%{kinds: [:step], produces: :unknown, slot_accepts:
%{"on_done" => [:step], "on_error" => [:step]}}`. `produces` is `:unknown` for
`core.invoke`'s reason - joining what the call produces with what the
`on_error` subtree produces is the lattice ADR-0003 decision 4 refuses to
build - and `consumes` is absent because a fan-out reads its input out of the
datamodel through `items` rather than through the type flow.

`invoke_type/0` (`:204`) returns the constant `"statifier_blocks:map"`, one
definition site and never a config field, in the shape `core.subchart`'s
constant has: which handler starts children is deployment state rather than
authoring state (`st-ADR-0051`). It is deliberately a **different** string
from `"statifier_blocks:subchart"`, which is ADR-0009 decision 3's
requirement - a host that wired a single-child subchart handler has not
thereby wired a fan-out handler, and a document that reached such a host
should fail to find a handler rather than quietly start one child. Nothing had
to be added to `StatifierBlocks.Compiler.InvokeTypes` for the lint to reach
it: that pass reads emitted `<invoke type>` strings out of the emission rather
than a list of known types.

`palette_entry/0` (`:337`) takes order 16 in the `Structure` group, with the
label "For every item, run a chart" - ADR-0009 decision 2's split between the
engineer-facing type name and the author-facing label - and the description
"Runs another chart for every item in a datamodel list, all at once."

**G15a. What it compiles to.** A compound state with one inner running state
holding the invocation, plus the slot subtrees and one `<final>` per reachable
outcome. The inner state carries exactly **one** `<invoke>`, with the block's
own id (ADR-0004 C3), `type` the constant above, and `src` the `chart` value
verbatim. Its four `<param>` elements carry `items`, `chart`, `collect` and
`on`, each as a **quoted literal** rather than an expression, because the
handler is what evaluates them and the parent is not (`params/4`, `:430`;
`literal_param/3`, `:447`). `collect` is omitted from the params entirely when
the author declared none, which is ADR-0009 decision 7 clause 3's supported
shape rather than an empty string a handler would have to read as absence.

Two facts about those bytes are worth stating at row level rather than leaving
to ADR-0004.

`chart` is emitted **twice**: as the `<invoke src>` and as a `<param>`. The
`src` is ADR-0009 decision 3's requirement and is what a reading host sees;
the param is what the handler reads beside the other three, so a handler has
one place to look rather than two. They are the same verbatim string. Carrying
`src` also puts a `core.map` under `StatifierBlocks.Compiler.SelfReference`
with no edit there, because that pass classifies by SCXML's own semantics
rather than by block type - so a map naming the document it sits in is refused
for free.

The `collect` write is one `<assign expr="_event.data">` on the **success
transition** (`assign/1`, `:499`), not in a `<finalize>`. That is ADR-0009
decision 5's "the write happens once, at the invocation's completion" and it
is the shape ADR-0007 decision 2 describes for a leaf step and `core.subchart`
already emits: the answers are only answers when the batch answered.

**G15b. The field names in this row are the shipped ones, and ADR-0009
decision 4's table spells two of them differently.** That record's declaration
table names `assign_to` and `aggregate` for the two ideas that ship as
`collect` and `on`, and declares four further fields - `item_as`, `index_as`,
`max_concurrency`, `params` - that the shipped surface does not carry. The row
above is read off the module, per this record's rule that a row is read off
the shipped type; the reconciliation, and the record of what became of the
four, is a dated Note beneath ADR-0009 decision 4 added on this date by this
same bead. Nothing in this section decides anything about those four: they are
that Note's to hold open.

**G15c. This row validates nothing about N, and that is a decision.** Campaign
031's ruling `D31-9` puts the bound on a fan-out batch in the *runtime* that
starts the children: a configuration key with a runtime refusal on the
ordinary `error.communication.invoke` route, carrying N and the cap in its
detail. It is never a compile finding here, and the reason is not division of
labour but arithmetic: the compiled bytes do not scale with N and cannot, since
the `<param>` carries the list's *path* and a compile of one document never
sees the list. The same document compiles to the same bytes over three items
and over three thousand, which is what keeps ADR-0004 decision 6's byte
determinism intact. This package imports nothing from the durable runtime
packages and takes no position on how child starts are batched or bounded.

**G15d. What this row does not change.** `core.foreach` is untouched, in every
sense ADR-0009 decision 1 and decision 11 mean: `core.map` is a sibling of
`core.subchart` and not a mode of it, and it is not `core.foreach` with a
flag. `core.subchart`'s row (G5) stands unedited, its outcome set still
config-derived and its own invoke type constant still its own. ADR-0002
decision 2's two-registry seam holds exactly as it does for `core.invoke` and
`core.subchart`: this type **names** an invoke type and runs nothing. The
effect vocabulary, the event names and chart identity remain `statifier-ex`'s.
And the document schema is untouched - ADR-0001 owns the stored bytes and
`schema_version` stays at `1`, because a new block type is a new value of an
existing field.

Filed with `sb-7haw`, campaign-031. `sb-kqno` (PR 281, `a852429`) is the
implementation this row is read off.

## Note (2026-09-06): decision 7, `{:path, opts}` gets its first two keys, and a `field_candidates` feed

A dated Note rather than an amendment: decision 7 is unchanged, its closed
field-type set still has eight members, and no line above this one is edited.
The 2026-09-05 `{:path, opts}` amendment says `opts` "carries no defined key
today" and is a tuple precisely "so that what a control needs can arrive
without widening the set a second time". This Note records that a later record
has taken that door, and points at it rather than restating what it decides.

`ADR-0011` gives `opts` two keys, and both are optional:

- **`expects: T`** - a read signature. The block reads the path the field's
  value names and requires the environment at the block's position to satisfy
  `T`.
- **`writes: T`** - a write signature. The block puts `T` at that path for
  every block after it.

`T` is one of `sd-ADR-0001`'s nine scalars, the `name` of a `record` or
`shape` declaration there, `{:list, T}`, or `:unknown`. A `{:path, opts}`
field with neither key keeps behaving exactly as the 2026-09-05 amendment
describes, and so does a `:string` field carrying `datamodel_path?: true` -
`ADR-0011` decision 2 reads both as writing `:unknown` at the path, which is
known-but-untyped and refuses nothing. The `path_kind` enum the 2026-08-29
amendment refused stays refused; neither key is it.

`ADR-0011` also **names** a `field_candidates` feed beside the two keys, and
names it without fixing its shape: what a candidate list is keyed on and how it
is supplied are `sb-xk1h`'s, and this Note records only that the feed exists so
that a field may offer the values a host expects without a new field type.
`validate_config/1` stays the only authority per decision 7, and the schema is
still not a validation language: a candidate list is what a control draws, not
what a config is checked against.

Two of this record's own sections are read by `ADR-0011` and neither is
changed by it. The 2026-09-05 Note on `core.on_event`'s optional `capture`
says `config_schema/1` declares no field for the map, and leaves the authoring
surface open; `ADR-0011` decision 10 closes it as a repeated two-control row -
a `{:path, opts}` target beside an `_event.data` source path, with the source
control's candidates from `fixtures/0` - and adds no member to decision 7's
set. And `ADR-0011` decision 13 resolves `core.subchart`'s `assign_to` by
admitting a dotted path: G5's row records what the type declares and G5a hands
the emitted bytes to `ADR-0004`, so neither states a constraint on what an
`<assign>` location may be, and `core.assign` already emits a dotted one. That
decision widens two call sites in `core/subchart.ex` and changes nothing in
G5 or G5a.

`sb-xk1h` implements both keys and the feed.

## Note (2026-09-06): decision 10, the read and the write signature of each core row

A dated Note rather than an amendment, and a **new table beside** decision
10's rather than a column added to it: decision 10's table is four columns
wide and every row of it is a merged line, so a fifth column cannot arrive
without rewriting seventeen rows that this Note does not reopen. Nothing above
this line is edited, and no row here contradicts one there - the table below
is a projection of what `config_schema/1` already declares, read through the
two `{:path, opts}` keys the Note of 2026-09-06 records.

`ADR-0011` decision 2 fixes the reading, and it is the whole of it:

- a `{:path, %{writes: T}}` field writes `T` at the path its value names;
- a `{:path, opts}` field with no `writes` key, and a `:string` field carrying
  `datamodel_path?: true`, write `:unknown` there - the path becomes known
  without becoming typed;
- `core.on_event`'s `capture` writes `:unknown` at each pair's key;
- a `{:path, %{expects: T}}` field reads `T` there.

| Block type | Reads | Writes | How it reaches the environment |
|---|---|---|---|
| `core.sequence` | none | none | one slot, so what its `body` wrote leaves it unchanged by the merge |
| `core.group` | none | none | `body` and `interrupts` merge per path; a path only the handler wrote leaves at `:unknown` |
| `core.resumable_group` | none | none | as `core.group`; the history mode changes nothing here |
| `core.branch` | none | none | one arm slot per declared arm, then `otherwise`, merged per path |
| `core.parallel` | none | none | one slot per lane, merged per path; no ordering between lanes is modelled |
| `core.foreach` | none | `items`, `:unknown` | `items` is a `:string` carrying `datamodel_path?: true`; the body additionally sees `item_as` and `index_as` bound, and those two names do not leave it |
| `core.map` | none | `items`, `:unknown`; `collect`, `{:list, :unknown}` | `collect` is the vocabulary's only typed write - `ADR-0011` decision 12 says a list and says nothing about an element |
| `core.subchart` | none | `assign_to`, `:unknown` | a `{:path, opts}` field since `sb-2ym4`; what the outcome holds is the child chart's, not this record's |
| `core.assign` | none | `path`, `:unknown` | the worked shape's step 1: known without becoming typed |
| `core.on_event` | none | one per `capture` pair, at the pair's key, `:unknown` | no field declaration - the Note of 2026-09-05 records why - so the walk reads the config map directly |
| `core.invoke` | none | none | its `<assign>` location is emitted rather than declared, so nothing here sees it |
| `core.wait` | none | none | a leaf whose whole meaning is config |
| `core.send` | none | none | |
| `core.raise` | none | none | |
| `core.await` | none | none | |
| `core.drafts` | none | none | the shelf is not entered, and each parked fragment is walked from an empty environment |
| `core.placeholder` | none | none | the one type declaring no `io/1` at all |

Three readings the table makes and a reader would otherwise have to derive.

**No core type declares a read.** The `expects` key exists and nothing in this
vocabulary uses it, which is not an oversight: a `core.*` block is structural,
and the blocks that need a value of a particular shape at a particular path are
the host's. A document built of nothing but core types therefore refuses
nothing on data-flow grounds, exactly as it did before `ADR-0011`.

**The `consumes` and `produces` sugar is inert across the vocabulary.**
`ADR-0011` decision 6 desugars a binary `produces` into a write at the
document's subject path. `core.sequence` declares `{:passthrough, "body"}`,
five types declare `:unknown`, and the rest declare neither, so no core row
contributes a sugared signature. The passthrough is answered by the walk
carrying the slot's own writes out through the merge, which is the same answer
by a mechanism that does not need the subject path to exist.

**A container's row says "none" about the container, not about the block.**
Every write in a container's slots reaches the block after the container
through the merge, which is `ADR-0011` decision 4 and not a property of any
row above. The rows say what the type itself declares.

`sb-u7zt` declares these across `lib/statifier_blocks/core/` and pins each row
by test; `sb-xk1h` is where a `core.*` row would first gain an `expects`.

## Note (2026-09-06): the two `core.subchart` cites under G14 have drifted, and what they read today

A dated Note rather than an amendment, recorded for `sb-50lu` under
campaign-033. Nothing above this line is edited and no decision moves: this
is a cite errata for the two `lib/statifier_blocks/core/subchart.ex` line
ranges the Notes under G14 use as evidence. The claims those ranges support
are unchanged and still hold; only the numbers naming them went stale, and
the two functions the Notes point at are still `finals/1` and
`outcome_names/1` in that module. The form is the one `statifier-ui`'s
ADR-0016 amendment uses for a fact that moved after a record merged: say
what the record says, say what is true now, and add rather than rewrite.

### What the two Notes cite, and when each was true

The Note added 2026-09-05 beneath G14d cites `outcome_names/1` at
`lib/statifier_blocks/core/subchart.ex:463-467` and `finals/1` at
`:448-453`. Both were true at `3fef9a8`, the commit that added that Note.

The Note added 2026-09-06 beneath G14a cites `outcome_names/1` at `:516-521`
and `finals/1` at `:500-505`. The first was true at `b7acfcf`, the commit
that added it. The second was one line high at each end there: `finals/1`
ran `:501-506`, so the range as written opened on the last line of the
comment above the function and stopped one line short of its `end`. The two
lines the claim rests on - the `Enum.filter` and the `Emit.final` it pipes
into - sat at `:504` and `:505`, inside the range either way, so the claim
held while the range naming it did not.

### What they read on `main` today

Read at `1cdcc9d`, and given `@spec` line through `end` line for both:

| Function | Cited 2026-09-05 | Cited 2026-09-06 | On `main` today |
|---|---|---|---|
| `finals/1` | `:448-453` | `:500-505` | `lib/statifier_blocks/core/subchart.ex:518-523` |
| `outcome_names/1` | `:463-467` | `:516-521` | `lib/statifier_blocks/core/subchart.ex:533-538` |

Three commits moved them, none of which touched either function's body:
`23d1455` and `0ae8c3f` between the two Notes, and `bbe55ac` after the
second. `finals/1` still filters on `routed? or child` and maps
`Emit.final/1` over what survives, and `outcome_names/1` still appends
`error` unless the author listed it, which is what both Notes read off them.

One inconsistency inside the 2026-09-05 cites is worth naming so this table
is not read as correcting a fourth thing: `:448-453` spans `@spec` through
`end`, while `:463-467` stops at the body's last line and leaves `end` out.
The column above uses the first convention for both rather than preserving
the difference.

A line range is the citation form this record has used since G, and it ages
against a file that moves. The durable half of each cite is the function
name, which is why the ranges above are given beside `finals/1` and
`outcome_names/1` rather than instead of them, and why a reader who finds a
range that no longer lands should read the name and not the number.

## Note (2026-09-06): the seventeen rows of the decision 10 Note's rationale sit in ten tables, seven of them in decision 10's

A dated Note rather than an amendment, recorded for `sb-ae12` under
campaign-033. Nothing above this line is edited and no decision moves: this is
a cite errata for one clause in the Note added earlier this date under
"decision 10, the read and the write signature of each core row". The form is
the one the Note added beside G14 on this date uses for a fact that moved after
a record merged: say what the record says, say what is true now, and add rather
than rewrite.

That Note gives its reason for building a new table beside decision 10's rather
than adding a fifth column to it:

> decision 10's table is four columns wide and every row of it is a merged
> line, so a fifth column cannot arrive without rewriting seventeen rows that
> this Note does not reopen.

Seventeen is the right count of the vocabulary and the wrong count of that
table. Decision 10's table carries **seven** rows. The other ten core types
joined one and two at a time in later sections, each in a table of its own, and
those nine tables are **five** columns wide - they carry `outcomes(config)`,
which section A added after decision 10's four columns were written.

### The ten tables, counted against this file today

Read at `854a745`. The durable half of each cite is the section label and the
type names beside it; the line number is the half that ages.

| Table | Section | Columns | Rows | The types it declares |
|---|---|---|---|---|
| `:338` | decision 10 | 4 | 7 | `core.sequence`, `core.branch`, `core.parallel`, `core.wait`, `core.resumable_group`, `core.on_event`, `core.group` |
| `:905` | D | 5 | 2 | `core.invoke`, `core.raise` |
| `:1105` | G | 5 | 1 | `core.assign` |
| `:1463` | G2 | 5 | 1 | `core.send` |
| `:1541` | G5 | 5 | 1 | `core.subchart` |
| `:1610` | G6 | 5 | 1 | `core.foreach` |
| `:2107` | G9 | 5 | 1 | `core.drafts` |
| `:2185` | G10 | 5 | 1 | `core.placeholder` |
| `:2902` | G14 | 5 | 1 | `core.await` |
| `:3331` | G15 | 5 | 1 | `core.map` |

Seven plus ten is seventeen, which is the count the Note added 2026-09-05
beneath G11 gives (**seventeen rows, seventeen palette entries**) and the
number of entries `StatifierBlocks.Palette.core_types/0` returns
(`lib/statifier_blocks/palette.ex:116-136`, seventeen `"core.*" => module`
pairs). Nothing about that count moves here; only where its rows physically
sit is corrected.

### Why the conclusion the clause supports is stronger under the accurate count

A fifth column added to decision 10's table would rewrite seven rows, not
seventeen - a smaller edit than the clause claims. But a read/write column
carried **uniformly across the vocabulary** would have to reach ten tables in
two different shapes, and in nine of them it would be a sixth column rather
than a fifth, because `outcomes(config)` already holds their fifth. The choice
that Note actually made - one new table beside decision 10's, projecting what
`config_schema/1` declares - is therefore the cheaper and the more legible of
the two by a wider margin than its own rationale claimed, and the Note's
conclusion stands unchanged.

One usage is worth naming so this errata is not read as correcting more than
one clause. The Note added 2026-09-05 beside G11 says "the table" for the
vocabulary's rows taken together, across all ten, and G15's "the ordinal has
moved" paragraph counts that same single sequence by ordinal rather than by
table. Neither reading is disturbed here: this Note corrects only the
decision 10 Note's clause, which says "decision 10's table" and then counts
all seventeen.

## Note (2026-09-06): `core.invoke`'s `assign_to` is a declared path, so the writes table gains a row

A dated Note rather than an amendment, and it edits nothing above this line.
Two statements this record makes about `core.invoke` were true when they
were written and are not any more, and both are consequences of one change
`sb-r313` made under `ADR-0011` decision 13's argument rather than of any
decision made here.

**Section D of the 2026-08-28 amendment declares `assign_to` as `:string`
in its table.** It is `{:path, %{}}` on `main` - decision 7's eighth field
type, from the 2026-09-05 amendment - exactly as `core.subchart`'s became
on `sb-2ym4` and for the same reason: the field names a datamodel location,
the editor reaches a candidate list by the field type alone, and a value
the host's datamodel does not declare draws `ADR-0005` clause 11e's `:info`
advisory rather than a refusal. Decision 7's set gains no member and the D
table's `core.invoke` row is otherwise unchanged; a reader of that row
should read the type as `{:path, %{}}`.

**The Note of 2026-09-06's writes table says `core.invoke` writes
nothing.** Its row reads "none | none | its `<assign>` location is emitted
rather than declared, so nothing here sees it", which was the defect
`sb-r313` was filed for rather than a property worth keeping. The row is now:

| Block type | Reads | Writes | How it reaches the environment |
|---|---|---|---|
| `core.invoke` | none | `assign_to`, `:unknown` | a `{:path, opts}` field carrying no `writes` key, so the path becomes known without becoming typed - `core.subchart`'s row exactly, and for the same reason: what the call answers is the host's, not this record's |

That row is the only change to that Note's table, and the reading beneath it
that opens "**No core type declares a read**" still holds: this is a write.
The census of path-field writers across the `core.*` vocabulary is five
after it rather than four.

**The same Note's sentence about `collect`'s wording.** Section G15's prose
says a `collect` that is present and not a bare lowercase identifier is
"refused in the same words `core.invoke` and `core.subchart` produce for
`assign_to`". Those three wordings have diverged in two steps: `sb-xk1h`
moved `core.subchart`'s to the datamodel-path sentence when it implemented
`ADR-0011` decision 13, and `sb-r313` moved `core.invoke`'s to the same
sentence. `core.map`'s `collect` keeps the bare-identifier wording, because
`ADR-0009` decision 4 decides that field's grammar outright and widening it
is that record's amendment to make. The refusal's *shape* is now shared -
`StatifierBlocks.Core.AssignLocation`, one blank-permissive check anchored
on the field's own key per `ADR-0005` decision 11 - and only the rule and
the wording differ. G15's sentence should be read as naming the shape.

## Note (2026-09-06): G15's `collect` sentence, read against the four `<assign>` location fields as they now stand

A dated Note rather than an amendment, and it edits nothing above this line.
The Note immediately above already records that G15's sentence - a `collect`
that is present and not a bare lowercase identifier is "refused in the same
words `core.invoke` and `core.subchart` produce for `assign_to`" - should be
read as naming the refusal's *shape*, and it records that as one consequence
of `sb-r313` among several. This Note is the per-field table behind that
reading, because the sentence's claim is scoped to four fields and three of
them have moved since it was written, and it names the bead that owns the one
question left open. It decides nothing.

Four fields name the location of an `<assign>` this package emits. After
`sb-xk1h` carried `ADR-0011` decision 13 to `core.subchart` and `sb-r313`
carried its argument to `core.invoke` and to `StatifierBlocks.InvokeStep`,
they stand like this on `main`:

| Field | Declared as | Location rule | Refusal reads | Record that decides the grammar |
|---|---|---|---|---|
| `core.invoke`'s `assign_to` | `{:path, %{}}` (`core/invoke.ex:105`) | `StatifierBlocks.Core.Config.datamodel_path?/1` (`:138`, `:314`) | "must be a datamodel path, like cards.authorization" (`:75`) | `ADR-0011` decision 13's argument, carried here by `sb-r313` |
| `StatifierBlocks.InvokeStep`'s `assign_to` | the host declares the field; the moduledoc example declares `{:path, %{}}` (`invoke_step.ex:20`) | `datamodel_path?/1` (`:301`, `:435`) | the same sentence (`:115`) | as above |
| `core.subchart`'s `assign_to` | `{:path, %{}}` (`core/subchart.ex:260`) | `datamodel_path?/1` (`:307`, `:619`) | "must be a datamodel path, like eligibility.outcome" (`:316`) | `ADR-0011` decision 13 |
| `core.map`'s `collect` | `{:path, %{writes: {:list, :unknown}}}` (`core/map.ex:264`) | `StatifierBlocks.Core.Config.identifier?/1` (`:318`, `:528`) | "must be a bare lowercase identifier, like answers" (`:205`) | `ADR-0009` decision 4 |

So the sentence names three wordings where it once named one, and `collect`
alone keeps the bare-identifier grammar. What all four share now is the
refusal's shape, and it is written once: `StatifierBlocks.Core.AssignLocation`
(`@moduledoc false`), `check/5` at `:39` for the `validate_config/1` pass and
`location/4` at `:51` for the `emit/2` re-check. A blank value passes and
emits nothing, a value the field's rule accepts passes, and anything else is
one finding anchored on the field's own key, which is `ADR-0005` decision 11.
The rule and the wording are arguments to that helper rather than properties
of it, which is exactly what let three of the four move while the fourth
stayed.

Two readings of the G15 row above follow from that, and neither edits it. The
row declares `collect` as `{:path, %{}}`; the `writes` key that row predates
arrived with `ADR-0011`, the Note of 2026-09-06 on decision 7 records its
arrival, and the Note of 2026-09-06 on decision 10 already carries `collect`,
`{:list, :unknown}` in its writes table, which is the current reading of the
declaration. And nothing else in G15 moved: the four-field census, the `on`
default read through `core.parallel`'s G7a shape, and the "refuses nothing
else, and in particular nothing about N" clause are all unaffected, because
only the `assign_to` half of one sentence changed under them.

**`collect` is now declared a path and refused as an identifier**, which is
the candidates-versus-validation mismatch `ADR-0011` decision 13 called a
defect either way round when it found it on `core.subchart`: the editor
offers the host's declared dotted paths on a `{:path, opts}` field, and this
field's rule refuses every one of them. Resolving it is an amendment to
`ADR-0009` decision 4 - "There is no per-item path grammar and no dotted
form" - on that record's own argument, and nobody has ruled it. `sb-h6qt`
owns that question, with both directions named on it: widen `collect` to a
dotted path, or narrow its declaration to match the grammar. This record
takes neither, and G15 stands as written until that one is ruled.

## Note (2026-09-06): `core.branch` declares a third slot on `main`, and the three rows that describe its slots and its card

A dated Note rather than an amendment, and it edits nothing above this line.
It decides nothing and it is **not** the amendment `ADR-0012` names: that
record is proposed, and it says in its own words that the rows below "are not
edited here". This Note records what the code does today, so that a reader who
finds a row and the code disagreeing is reading a dated entry rather than
making a discovery.

`sb-2hoh` built `ADR-0012`'s decision 2. `StatifierBlocks.Core.Branch.slots/1`
now returns the arm slots in config order, then `{"otherwise", :any,
"Otherwise"}`, then `{"undecided", :any, "Cannot be decided"}`
(`lib/statifier_blocks/core/branch.ex`). `outcomes/1`, `slot_style`,
`config_schema/1` and `validate_config/1` are untouched, so every other row in
this record that describes `core.branch` still reads correctly.

Three rows describe the slots and the card, and each is now a row about a
branch with one slot fewer than the type declares:

- decision 10's vocabulary row, "one `arm_*` per declared arm, then
  `{"otherwise", :any, ...}`" (`:341`) - true of the arms and of `otherwise`,
  silent about the third slot;
- amendment H's summary row, "`N arms + otherwise`" (`:1883`) - still exactly
  what `summary/1` returns, and `ADR-0012` decision 9 asked for
  `"+ undecided"` on a branch that wires the slot. The callback is handed the
  config alone (`@callback summary(Block.config())`, `:573` of
  `lib/statifier_blocks/block_type.ex`), and whether a slot holds children is
  a fact about the block rather than its config, so the wired case is not
  reachable without widening the callback. `sb-2hoh` left the card as it was
  and said so in `summary/1`'s own doc; widening the contract is nobody's
  decision yet;
- the Note of 2026-09-06's environment table row, "one arm slot per declared
  arm, then `otherwise`, merged per path" (`:3528`) - the merge rule it states
  is unchanged and now covers one more slot. `ADR-0011` decision 4 already
  says why: every slot of a container starts from the environment that
  reached the container, and `ADR-0012` decision 8 names the new slot as one
  of those arms rather than adding a rule.

Nothing here is a decision about how those rows should eventually read. That
is the amendment `ADR-0012`'s own closing section reserves for its
acceptance, and it stays reserved.

## Note (2026-09-06): an optional `failure_outcomes/1`, a second axis on the outcomes amendment A already declares

A dated Note rather than an amendment. It edits nothing above this line, and
in particular it does not touch amendment A: `outcomes/1` still returns
`{name, label}` pairs in declaration order, the default is still the single
outcome `done`, and A2's refusal to marry an outcome to a slot stands word for
word. What this Note records is a **new optional callback beside** that one,
built by `sb-napt` under the operator's campaign-033 ruling `RQ-033-3` of
2026-09-06, and what it does and does not reach.

**The callback.** `StatifierBlocks.BlockType` declares
`failure_outcomes(config) :: [String.t()]`, optional, resolved through
`BlockType.failure_outcomes/2` the way `outcomes/1` is resolved through
`outcomes/2` - `Code.ensure_loaded?/1` plus `function_exported?/3`, defaulting
to `[]`. It returns the subset of the names `outcomes/1` already declares that
mean *this block finished badly*. A type that does not export it classes
nothing, which is where every accepted `core.*` type except `core.map` and
`core.subchart` stays, so a host type written before the callback existed
compiles to the bytes it compiled to.

**Why a second callback rather than a third element of the outcome
declaration.** A2 refused to make the declaration a triple when the third
thing was a slot, and the reasoning carries: a `{name, label}` pair is what
the compiler mints ids and events from and what the editor draws, and
widening it would move every host type's declaration for a fact only the
compiler's final emission reads. A separate list is additive in the sense
`ADR-0004` decision 6's byte determinism needs - a type that says nothing
is unchanged - and it keeps the class out of the serialized outcome order
entirely. The
resolver is total over any return value for `outcome_names/2`'s reason: a
declaration that is not a list of binaries reads as `[]` rather than raising
inside the compiler.

**What the class buys, in full.** One compiled byte span, described in
`ADR-0004`'s Note of this date: the top-level `<final>` for a failure-classed
outcome carries a reserved `<donedata>` `<param>`, key
`statifier_persistence:run_status` and value `failed`, under both the
`:child_use` and the `:terminate` compile options. The key and its closed
value set are `statifier_persistence`'s, fixed by that package's ADR-0008
amendment of 2026-09-06 (`sp-n8g`, the mirrored half of `sb-napt`), and this
package spells them rather than deciding them.

**What the class does not buy, and this is the longer half.** Nothing else in
this package branches on it. Routing is unchanged - a failure-classed outcome
is reached from `done.outcome.<root state id>.<outcome>` like any other, and a
`core.branch` arm, an `on_<outcome>` slot and an editor connector treat it
exactly as they treat `done`. The typed environment of `ADR-0011` writes
nothing and reads nothing new. No slot arity, no `slot_style`, no palette
entry and no card changes: `core.subchart` already gives its `on_error` slot
`slot_style: %{"on_error" => :failure}`, and that is the editor's separate,
older word for the same fact rather than a thing this callback now feeds.

**The two core types that class an outcome, and why only those two.**
`core.map`'s `error` and `core.subchart`'s `error` - in both cases the one
outcome the type itself appends or fixes for "the work did not succeed".
Nothing an author lists is classed: `core.subchart` takes the rest of its
outcomes from a chart this package cannot read, so what a `declined` or an
`expired` means there is the author's word and not a class this package may
assign. The operator's `RQ-033-3` is the boundary the code draws - a failure
is a final an author routed to on purpose, and an unhandled `error.*` is not
a failure by itself.

**Decision 10's rows are not edited here**, in the posture the Notes above
this line take: the `core.map` and `core.subchart` rows still read as their
amendments wrote them, because `outcomes(config)` is the column they carry and
neither type's outcome list changed.

Filed with `sb-napt`, mirrored with `sp-n8g` in `statifier_persistence`;
campaign-033 ruling `RQ-033-3`.

## Amendment (2026-09-06): decision 10's `core.branch` row and the environment table row, now that `slots/1` returns `undecided`

**Status: proposed (2026-09-06).** Drafted for `sb-uewa` under the operator
campaign-034 grant, and merging at proposed under that campaign's invariant
like every other section filed with it; flipping it to accepted is a separate
gated request. Additive; decision 10's original seven-row table stands, every
amendment and Note above this line stands, and no text above this line is
edited by this section.

This is the amendment `ADR-0012`'s closing section reserved for its
acceptance. That record is accepted, `sb-2hoh` has built its decision 2, and
the Note of 2026-09-06 above ("`core.branch` declares a third slot on `main`")
named the three rows the debt covers and deliberately edited none of them.
Two of the three are amended here. The third is withdrawn from the debt, and
section C says why.

Amendment by addition, per this record's convention: **no line above is
edited**. Each row below is restated in full as it now reads, and the restated
row is the one a reader follows.

### A. Decision 10's `core.branch` vocabulary row (`:341`)

| Block type | `slots(config)` | Config schema | Notes |
|---|---|---|---|
| `core.branch` | one `arm_*` per declared arm, then `{"otherwise", :any, "Otherwise"}`, then `{"undecided", :any, "Cannot be decided"}` | `arms`: a list of `{slot name, condition expression}` (amended 2026-08-27: the full slot name, e.g. `arm_approved`, not a suffix - matching ADR-0001's worked-example bytes) | conditions are `:expression` fields; the third slot is `ADR-0012` decision 2's, and it takes the children of a condition the engine could not decide |

Only the `slots(config)` column moves. `config_schema/1` is untouched -
`undecided` is not an arm and declares no condition field - and so is
`validate_config/1`. The row's reading of the arms and of `otherwise` was never
wrong; it was silent about a third slot, and it is not silent now.

### B. The environment table row of the Note of 2026-09-06 (`:3528`)

| Block type | Reads | Writes | How it reaches the environment |
|---|---|---|---|
| `core.branch` | none | none | one arm slot per declared arm, then `otherwise`, then `undecided`, merged per path |

The merge rule the row states is unchanged and now covers one more slot, which
is what the Note of 2026-09-06 above already said it would. `ADR-0011` decision
4 is why it needs no new rule: every slot of a container starts from the
environment that reached the container, and `ADR-0012` decision 8 names the new
slot as one of those rather than adding a case. Reads and writes stay `none` in
both columns.

### C. Amendment H's summary row (`:1883`) is **not** amended, and leaves the debt

`ADR-0012`'s closing section listed it as the third row owed. It is not owed.
`ADR-0012` decision 9's `summary/1` clause is withdrawn by that record's own
Note of 2026-09-06, so `N arms + otherwise` is still exactly what `summary/1`
returns and exactly what amendment H's row should say. The card under-reports a
*wired* `undecided` slot by one path, and that under-report is decision 9's own
answer rather than a drift: `@callback summary(Block.config())` is handed the
config alone, and whether a slot holds children is a fact about the block's
`slots` map rather than its config. Widening the callback to see the block is a
contract change no record has asked for. Recorded here because `ADR-0012`'s
closing section still lists three rows, and a reader who counts two amendments
against it should find the third accounted for rather than missing.

### D. Cite errata: `summary/1` is at `:609`, not `:573`

`@callback summary(Block.config())` is at
`lib/statifier_blocks/block_type.ex:609` on `main`; `:573` was the line before
`failure_outcomes/1` was declared above it. Two places carry the old number:

- the Note of 2026-09-06 above, in its reading of amendment H's summary row
  (`:3814-3815` of this file), which cites `` `:573` of
  `lib/statifier_blocks/block_type.ex` `` - `:609` is the line it means;
- the doc of `StatifierBlocks.Core.Branch.summary/1`
  (`lib/statifier_blocks/core/branch.ex`), corrected to `:609` in the request
  that carries this amendment.

Neither cite's argument changes; only the number does. A line cite in this
record family is a reading aid rather than a claim, which is why an errata
paragraph is the right shape for it: the Note above keeps its words, and the
number is corrected here.

Filed with `sb-uewa`; campaign-034 ruling `RQ-034-6`. Sections A, B and C
discharge the debt `ADR-0012` reserved.

## Note (2026-09-06): G15 and G15b, read against `core.map`'s six shipped fields

A dated Note rather than an amendment, and it edits nothing above this line. It
decides nothing: G15's field census and G15b's reconciliation were both correct
on the date they were written, and `sb-otpv` has since shipped two of the
fields they say the module does not carry. This records the count so that a
reader who finds those rows and the module disagreeing is reading a dated entry
rather than making a discovery.

`StatifierBlocks.Core.Map.config_schema/1` now declares **six** fields:
`items`, `chart`, `item_as`, `index_as`, `collect`, `on`. The two new ones are
`ADR-0009` decision 4's declared names for what a child sees its item and its
position under - `item_as` a `:string` with the default `item`, `index_as` a
`:string` the author declares only when they want one - and `ADR-0011`'s Note
of 2026-09-06 is where they are recorded on the typed environment's side.

**G15's row (`:3329`) lists four config fields, and there are six.** Everything
else in that row holds: `slots/1`, the `slot_style`, the `outcomes/1` pair and
the `on` default read exactly as they did. The two additions are declaration,
not structure - no slot, no outcome and no card changes because of them.

**G15b (`:3418`) says the four further fields `ADR-0009` declares are ones "the
shipped surface does not carry", and two of the four now ship.**
`max_concurrency` and `params` are still deferred, for the reasons `ADR-0009`'s
Note of 2026-09-06 gives each; the `assign_to`/`collect` and `aggregate`/`on`
spelling reconciliation that is the rest of G15b is untouched by this.

Filed with `sb-uewa`, folding `sb-z4vz`; campaign-034 ruling `RQ-034-6`.

## Amendment (2026-09-06): `core.on_event` declares its event payload, and a `capture` that reads past it is refused at compile

**Status: accepted (2026-09-06).** Drafted for `sb-i0cc` under the operator
campaign-034 grant, and merging at proposed under that campaign's invariant
like every other section filed with it; flipping it to accepted is a separate
gated request. Additive, by this record's convention: **no line above this one
is edited**. Decision 7's field-type set is not widened, decision 10's table is
untouched, the Note of 2026-09-05 that introduced `capture` (`:3118`) stands
word for word, and where this amendment corrects a bullet of that Note it
restates the bullet in full below rather than editing it in place.

[Note 2026-09-06, `sb-kkd7`: the paragraph above is this section as it was
drafted, and it is left standing rather than rewritten. The status word is now
`accepted`. This is the separate gated request that sentence points at, opened
after `sb-0na2` built P5's check (PR 325, `7f3cda3`) on top of the section
itself (PR 324, `6975e91`); the Note at the foot of this section carries what
the flip verified against `main`. The record's head `Status:` line at `:3` is
not extended by this flip: that line lists the amendments accepted up to
2026-08-30 and no accepted section since has been added to it - the Amendment
of 2026-08-31 at `:2069` is accepted and is absent from it too - so extending
it here would start a convention rather than follow one.]

Records campaign-034 ruling `RQ-034-7`, taken with the operator on 2026-09-06.

### Context

The Note of 2026-09-05 gave `core.on_event` an optional `capture` map and named
**two** failure shapes for it (`:3179`). The run-time one fires today. The
compile-time one - a `:config` finding when a declared payload and a capture's
source path disagree - was written for a day that had not arrived, and the Note
says so plainly at `:3193-3195`: *dormant, because nothing in this package declares
an event payload's shape*.

Two things have happened since. `sb-0q0z` measured the interpreter and found
that a missing member of a **bound** root writes the engine's unbound marker
and raises nothing, so the run-time branch is a marker rather than an error
(the Note of 2026-09-05 at `:3207` carries the measurement and its cites).
And the upstream question that would have made it an error was settled the
other way: the engine keeps writing the marker.

So the guarantee `capture` was reaching for - that a captured value which is
not there cannot be mistaken downstream for an authored absence - has to be
bought at **this package's compile**, or not at all. Buying it needs one thing
this package does not have: a statement of what the event's payload carries.
This amendment adds that statement, and wakes the dormant branch against it.

### P1. `core.on_event` takes an optional `payload` key, and it declares what `_event.data` carries

A `core.on_event` block's `config` gains an optional `"payload"` key. It
declares the shape of `_event.data` **for the event this handler names** - not
the datamodel, which the `:declare` and `:datamodel` compile options already
own (`lib/statifier_blocks/compiler.ex:87`, `:127`), and not a fact about the
event name anywhere else in the document. Two handlers for the same event may
declare different payloads and neither is thereby wrong; each governs its own
`capture`.

The key is **optional and additive in exactly the way `cond` and `capture`
are**. Absent, the block compiles to the bytes it compiled to before this
date, and P4 says what that means for findings. ADR-0001 owns the stored bytes
and `schema_version` stays at `1`: an optional key inside a block's `config`
object is a block-type contract, which is this record's, and that is the same
argument the Note of 2026-09-05 made for `capture` itself.

`payload` is a **declaration, not an emission**. Nothing about it reaches the
compiled SCXML. It is read at compile, by P5, and by nothing else.

### P2. The value vocabulary is `statifier_datamodel`'s, and this package mints none of it

The value of `payload` is a type expression in the datamodel document's own
spelling. `StatifierDatamodel.Types` admits four and no fifth: a name the
document's `types` key declares (`{:declared, name}`), one of the nine types
its set is closed at, an opaque string a consumer carries, and `:unknown`.
This package reads that vocabulary and adds nothing to it - the same stance
`StatifierBlocks.Environment` already takes, whose `type_expr/0` is *"one of
`t:StatifierDatamodel.Types.t/0`'s inhabitants as a document spells it"*
(`lib/statifier_blocks/environment.ex:93`).

Two arms are useful for a payload, and the record names both:

- **a declared name** - the name of a `record` or a `shape` the datamodel
  document declares, resolved with `StatifierDatamodel.Declarations.fetch/2`
  (public);
- **an inline shape** - the fields written where the payload is declared,
  because an event payload is frequently a one-off that no host wants in its
  datamodel's `types` key.

A `payload` spelling that resolves to a scalar, to an opaque string, or to
`:unknown` is read exactly as `Types` reads it and is **not** an error here.
Unknown is permissive both ways in that package by design, and this amendment
does not narrow it: a payload the document says nothing useful about is a
payload P5 refuses nothing against, which is P4's case reached by a second
route.

The declaration is resolved against the **same** `:datamodel` compile option
the typed environment already reads - one document, supplied once, read once
(`lib/statifier_blocks/compiler.ex:556-568`). A compile with no `:datamodel`
resolves no declared name, and P4 governs.

### P3. The `config_schema/1` spelling: the declared-name arm on an existing field type, and the inline shape deferred

Decision 7's field-type set is **closed**, and this amendment does not widen
it. Eight members are declared today
(`lib/statifier_blocks/block_type.ex:149-157`). The set has grown exactly
once since decision 7 was accepted - the Amendment of 2026-09-05 at `:2761`
added `{:path, opts}` as the eighth member, which the capture Note records at
`:3268-3269` - and it grew there on an argument about the editor: the control
table is keyed on the field type, so a path left as a bare `:string` gets no
candidate list and no undeclared-path advisory (`:2774-2798`). The two
amendments either side of it took an optional **key** instead
(`datamodel_path?` at `:1004`, `sensitive?` at `:1187`), and each says in its
own words that the type set stays closed (`:1028-1032`, `:1235-1238`). So the set is not sealed, and it is not widened casually either; this
section is the second kind of change and not the first. **No ninth field type
is added by it.**

What this section decides:

- **The declared-name arm gets a field, and its type is `:string`.** A
  `config_schema/1` may declare `payload` as a `:string` whose stored text is a
  declared type name. That is the arm the surrounding machinery can already
  carry: `Environment.type_expr/0` is `String.t() | :unknown | {:list,
  type_expr()}` (`environment.ex:93`), so a **name** is the only spelling of a
  declaration in hand anywhere in this package today. A `:string` carrying a
  name is a spelling, not a new kind of thing.
- **The inline-shape arm gets no field type here, and none is invented for
  it.** An inline shape is authored **through the document** and not through
  the editor, which is exactly the route `capture` itself takes today and for
  the same reason the Note of 2026-09-05 gives at `:3268-3274`: no member of
  decision 7's set describes the shape, that Note declined to add one, and how
  an author writes it is `ADR-0005`'s question rather than this section's.
  Left there rather than answered in passing. What this costs is the editor
  affordance for one arm; what it does not cost is the refusal, because P5
  reads `config` and a document-authored `payload` is as readable to the
  compiler as a field-authored one.

Deciding the first arm and declining the second is deliberate. A field type is
a member of a set every block type in this package renders against, and adding
one to spell a shape that no block stores yet would be a second proposal
riding along with this one - the objection the Note of 2026-09-05 raises
against a member for `capture`'s map, reaching the same answer here.

### P4. An undeclared payload keeps today's behaviour, exactly

A `core.on_event` whose `config` carries no `payload` - which is every block in
every document authored before this date - is unchanged in every respect:

- no new finding of any kind, at any severity;
- the compiled bytes are identical, because P1 emits nothing;
- the run-time branch of the Note of 2026-09-05 stands as measured: a `capture`
  whose source path is not in the payload writes the interpreter's explicit
  **unbound marker** and raises nothing, and a consumer of a captured path
  makes the test for it. That obligation is unchanged and is still the whole of
  what the key promises on an untyped document.

`statifier-ex` is **unchanged by this amendment**, and nothing in it is asked
for. The engine's marker write is the behaviour this package now builds around
rather than the behaviour it waits to have replaced.

The same rule reaches one more case, named so it is not read as a gap: a
`payload` whose declared name the datamodel document does not declare resolves
to nothing, and is the undeclared case. It is not a refusal of its own. This
amendment decides no finding for it; whether a name that resolves to nothing
deserves an advisory is `ADR-0005` clause 11e's kind of question and is left
to it.

### P5. The refusal: a `capture` pair reading a member the declared payload does not carry is a `:config` finding on the `capture` key

This is the dormant branch of `:3190-3191` waking. Its bullet reads *"a
declared payload that lacks a named source path"*, which admits two readings;
`RQ-034-7` fixes which, and it is this one: **the pair's source path names a
member the declared payload does not carry.** The other reading - a declared
member no `capture` reads - is not a finding, then or now: a payload may
legitimately carry more than one handler wants.

- **The anchor is `{:config, block_id, "capture"}`** - `Finding.anchor/0`'s
  config form (`lib/statifier_blocks/finding.ex:39-40`). One finding for the
  whole key, not one per pair, for the reason `check_capture/2` already gives
  in the module: `capture` has no field in `config_schema/1` for a per-pair
  finding to render against, so the key itself is the only anchor an editor
  can use (`lib/statifier_blocks/core/on_event.ex:283-296`). **The message
  names the offending pair** - both sides of it, and the declared payload -
  because the anchor cannot.
- **The source is `:config` and the severity is `:error`**
  (`lib/statifier_blocks/finding.ex:63`, `:80`). A refusal, not an
  `ADR-0005` clause 11e advisory. The reason is that both halves are the
  author's own bytes inside **one block's config**: the payload is what they
  said the event carries and the pair is what they said to read out of it, so
  a disagreement between them is a contradiction rather than a guess about a
  document the compiler cannot see. An advisory is right where the compiler is
  reasoning across documents; this is not that case.
- **How deep the check goes.** The **first** segment of the source path is
  checked against the declared payload's field names. A deeper segment is
  checked only where the field's own type resolves, through the same
  `Declarations.fetch/2`, to a declaration whose fields are in hand; a field
  whose type is a scalar, an opaque string or `:unknown` **stops the walk and
  refuses nothing beyond it**. This adds no structural rule
  `statifier_datamodel` does not already have - its read check is nominal,
  permissive on `:unknown`, and descends into no `list` element type - and a
  compile that invented one here would be a second proposal riding along with
  this one.
- **What it buys.** On a document that declares its payload, the marker write
  never happens, because the document does not compile. That is the guarantee
  the Note of 2026-09-05 opens with - no captured value that quietly is not
  there - now bought at compile rather than waited for from the engine.

### Note (2026-09-06): the correction the `error.execution` bullet of the Note of 2026-09-05 takes (`:3255`)

This is the dated correction `RQ-034-7` calls for, and it is placed here rather
than under the bullet it corrects. Amendment by addition is this record family's
convention, and here it is also the only safe shape: an insert at `:3259` would
shift every line below it, and sections already on `main` cite five distinct
lines below it by number - `:3329`, `:3331`, `:3418`, `:3528` and `:3814`.
Correcting one bullet by falsifying five cites is not a trade this record makes. So the bullet at `:3255` is **not edited**; it is restated below
in full as it now reads, and the restated bullet is the one a reader follows.

> - **The `error.execution` clause does not hold yet, and this package no
>   longer waits on it.** It is written in that Note as present tense and it
>   described a future. That future is not arriving: the engine keeps writing
>   the unbound marker for a missing member of a bound root, and the upstream
>   bead the bullet named as carrying it closed with the measurement rather
>   than a change. The guarantee this package offers is therefore
>   **compile-time on a typed document, not an engine raise**: with a `payload`
>   declared under P1, P5 refuses the document and the marker write never
>   happens; with no `payload`, the marker write stands and nothing in this
>   package is built on the error arriving. Nothing above this line depended on
>   the error either - the corrected bullet says so itself at `:3258-3259` - so
>   the correction removes a debt rather than an argument.

The paragraph immediately after that bullet (`:3261-3264`), which says the
compile-time branch *"stays dormant"* and that *"correcting the run-time branch
does not wake it"*, was accurate on its date and for its cause: correcting the
run-time branch did not wake it. **P1 does.** That paragraph keeps its words
and is read as the dated entry it is.

### What this amendment does not change

- **Decision 7's field-type set.** Eight members, closed, unwidened. P3 takes
  an existing type for the arm it decides and defers the arm it does not.
- **`config_schema/1` still declares no field for `capture`.** The map's own
  authoring question is `ADR-0005`'s and is untouched here; only `payload`
  gains a field, and only in P3's `:string` arm.
- **`Environment.capture_writes/1`.** A capture pair still writes
  `:unknown` at its destination path
  (`lib/statifier_blocks/environment.ex:662-`). This amendment types the
  **source** side of a pair at compile; typing the destination from the
  payload is a widening of `ADR-0011` decision 2's third write form that no
  ruling has asked for, and it is not taken here.
- **The compiled bytes.** One `<assign>` per pair, on the transition, before
  the `<raise>`, in the pairs' destination-sorted order. `payload` emits
  nothing and reorders nothing.
- **`cond`, and the outcome words.** Unchanged, and orthogonal: a guarded
  handler that does not fire captures nothing, and a refusal at compile is
  reached before either matters.
- **The size of the core vocabulary, and decision 10's table.** No row is
  added, no row is edited. `core.on_event` gains a config key, not a type.
- **`statifier-ex`.** Nothing is asked of the engine by this amendment, and
  nothing in it changes.
- **The document schema.** `ADR-0001` owns the stored bytes and
  `schema_version` stays at `1`.

Filed with `sb-i0cc`; campaign-034 ruling `RQ-034-7`. `sb-0na2` builds P5's
check; `sb-kkd7` is the request that flips this section.

### Note (2026-09-06): what the flip checked, and the three cites `sb-0na2` moved

The flip request `sb-kkd7` read P1 through P5 against `main` at `7f3cda3` -
the tree `sb-0na2` left - rather than against the tree this section was
drafted over. Every decision holds. Three line cites into `lib/` do not,
because the implementing commit moved the lines they point at, and two facts
about the shipped seam are recorded here because the section could not name
them before the seam existed. Nothing above this Note is edited by it.

**P1 and P3 hold, and the deferred arm stayed deferred.**
`StatifierBlocks.Core.OnEvent.config_schema/1` declares `payload` second,
after `event`: `type: :string`, `required?: false`, `default: ""`
(`lib/statifier_blocks/core/on_event.ex:287-293`). That is P3's
declared-name arm and only it; no inline-shape arm was built, no ninth field
type was added, and decision 7's set is still the eight members P3 counted
(`lib/statifier_blocks/block_type.ex:149-157`).

**P5 holds, and the seam it decided has a name this section did not give
it.** The refusal is
`StatifierBlocks.Core.OnEvent.payload_capture_findings/2`
(`on_event.ex:435`), a **public** function called from the compiler's config
stage (`lib/statifier_blocks/compiler.ex:513-514`) after that stage was
widened to take the compile options (`compiler.ex:472-479`). This section
decides the refusal, its anchor, its source, its severity and its depth rule
and leaves the spelling to the implementation, so the new function is inside
what P5 decided; this Note records it rather than amending anything. The
anchor is the `"capture"` key carried into `Finding.new/4` as `config_key`
(`compiler.ex:495-499`), which is `Finding.anchor/0`'s config form at
`lib/statifier_blocks/finding.ex:39-41` - one finding for the whole key, with
the message naming each offending pair and the declared payload
(`on_event.ex:489-499`).

**P4 holds.** A handler with no `payload` compiles to the bytes it compiled
to without one, and the test that says so is `"emits nothing of its own"`
(`test/statifier_blocks/core/on_event_test.exs:406-415`). One shape check
the section did not name sits beside it: a `payload` that is present and is
not a string is a finding on the `"payload"` key (`on_event.ex:393-399`).
Its `nil` clause is `findings` unchanged, so P4's case - the key absent - is
reached by neither half of it, and it is recorded here for the reader rather
than decided again.

**The three moved cites.** Each was correct at `6975e91`, where this section
merged. Read them at the right-hand column; the text above is not edited.

| Cited above as | What it points at | Where it is at `7f3cda3` |
|---|---|---|
| `compiler.ex:127` (in P1) | the `:declare` compile option's bullet | `compiler.ex:135` |
| `compiler.ex:556-568` (in P2) | `assignability_context/1`, the one datamodel read once | `compiler.ex:587-601` |
| `on_event.ex:283-296` (in P5) | `check_capture/2`, and why `capture` has no anchor of its own | `on_event.ex:352-373` |

P1's other cite, `compiler.ex:87` for the `:datamodel` option, is unmoved and
reads as written.

## Amendment (2026-09-06): `core.invoke` declares and classes `error`, a failure-classed final is unconditional, and an unhandled failure below the root reaches the root

**Status: accepted (2026-09-06), on the operator's campaign-034 rulings
`RQ-034-1` and `RQ-034-13`.** Drafted for `sb-ii2k`; it merges at proposed and
flips to accepted in a separate change once `sb-hxs5` has the code on main.

[Note 2026-09-06, `sb-ju4d`: the paragraph above is this section as it was
drafted, and it is left standing rather than rewritten. The status word is now
`accepted`. This is the separate change that sentence points at, opened after
`sb-hxs5` put the code on `main` (PR 328, `0f9f2cd`) on top of the section
itself (PR 320, `757ff3f`); the Note at the foot of this section carries what
the flip verified against `main`. The record's head `Status:` line at `:3` is
not extended by this flip, on the reason `sb-kkd7` gave beneath the amendment
of this date at `:4021`: that line lists the amendments accepted up to
2026-08-30, no accepted section since has been added to it, and extending it
here would start a convention rather than follow one.]

An amendment rather than a Note, because it changes what a shipped type
declares and what the compiler emits, rather than only recording a callback
that already existed. It is written by addition and edits nothing above this
line: amendment A's `{name, label}` pairs, A2's refusal to marry an outcome to
a slot, and the Note of this date that added the optional `failure_outcomes/1`
all keep every word. Taken by the operator as campaign-034 ruling `RQ-034-1`,
filed with `sb-ii2k`; the code is `sb-hxs5`.

**The defect it answers.** `sb-napt` gave a block type the ability to say that
one of its outcomes means *this block finished badly*, and gave the compiler
one byte span to emit when a document's **root** block reaches such an
outcome. Both halves work, and between them they reach almost no real
document. A chunk chart in the reference embedder is a `core.sequence` around
one `core.invoke`: the invoke is not the root, so the root emission never
looks at it, and `core.invoke` classes nothing anyway - it declares no
`outcomes/1` at all, so `BlockType.outcome_names/2` reads the default single
`done` while `emit/2` mints an `error` outcome final beside it. The chart
therefore cannot reach a failure-classed final by any authoring, and the host
translation that `statifier_persistence`'s ADR-0008 amendment of 2026-09-06
(`sp-n8g`, decision 6) exists to delete has nothing to be replaced by. Two
things are missing: a declaration on the one type that calls something out to
the world, and a rule for what a failure below the root does.

### 1. `core.invoke` declares `done` and `error`

`outcomes/1` returns `[{"done", "Done"}, {"error", "Error"}]`, fixed rather
than config-derived - the same pair `StatifierBlocks.InvokeStep.outcomes/0`
already returns for every host type built on it. Until now `core.invoke`
exported no `outcomes/1`, so the resolver's default single `done` was the
whole of its declaration while `emit/2` minted an `error` outcome final whose
entry raises `done.outcome.<state id>.error`. A type that raises an outcome
event it does not declare is the summary lie that `ADR-0004`'s outcome
amendment of 2026-08-28 forbids in its clause 2e -
a parent's child summary advertises the events the declaration names, and here
one of the two raised events was in no summary.

Two consequences, both wanted. The editor's outcome-event candidate list -
which offers a `core.on_event` author the events a sibling block can raise, and
which deliberately offers nothing for a type that implements no `outcomes/1` -
gains two rows for every `core.invoke` in the document, `done` and `error`,
where it previously offered none. And a parent may wire on
`done.outcome.<invoke state id>.error` the way it may wire on any declared
outcome, which is what section 4 below relies on.

The `on_error` slot is unchanged: still one `zero_or_one` slot, still named for
the failure path. A2's refusal stands - the slot and the outcome share a word
here and are not thereby married, exactly as `core.subchart` and `core.map`
have had both for longer.

### 2. A failure-classed outcome's final is emitted whether or not its slot is occupied - in `core.invoke`, `core.map` and `core.subchart` alike

Taken by the operator as campaign-034 ruling `RQ-034-13`, which extends this
section from `core.invoke` alone to all three shipped types that class an
outcome. The rule is one rule because the reason is one reason, and a rule
that held for one of the three would leave sections 4 and 5 true of that one
only.

Today the failure half of the emission is all of one piece and all of it
conditional, in each of the three:

- `core.invoke` with `on_error` empty emits no failure transition, no child
  and no `error` final, and the moduledoc's own sentence for that case is
  "the error propagates as it does today", meaning
  `error.communication.invoke` is selected by nothing this block emitted;
- `core.map` with `on_error` empty does the same - `error_final/1` and
  `failure_transition/1` each answer `[]` for an absent slot, and the
  moduledoc says so in as many words, "exactly as `core.invoke` has it";
- `core.subchart` with `on_error` empty emits no failure transition
  (`failure_transition/1` finds no route carrying a child) and emits the
  `error` final only when the **referenced chart's** own declared outcome
  list happens to name `error`, which is the `routed? or child` filter in
  `finals/1`. With the slot empty and `error` not among the child chart's
  declared outcomes - the ordinary case, since this type appends `error`
  itself rather than reading it from the author's list - the failure final is
  absent.

Those three sentences are superseded for the empty-slot case, and only for
it. A failure-classed outcome's final is emitted always, because a declared
outcome whose final is sometimes absent cannot be classed: the class is read
off the final, and the only thing that raises
`done.outcome.<state id>.<outcome>` - the event section 4's root catch
selects - is that final's own `onentry`. With the slot empty the failure
transition targets that final directly - the final whose id
`Context.outcome_id(context, "error")` mints, which is the id each of the three
types already uses for the occupied case. Today only `core.subchart` mints that
id for an unoccupied route, because its `routes/2` asks for every declared
outcome's id whatever the slot holds; `core.invoke`'s `error_parts/1` and
`core.map`'s equivalent mint it only in the branch that has a child, and under
this rule they mint it in both. With the slot occupied every byte is what it is
today: the transition targets the child, and the child's own `done_event`
carries it into the final.

This is what makes section 5's per-container table true as written and
section 4's rule reachable for all three types rather than for `core.invoke`
alone; it is also what section 6 counts as a cost, on all three.

An author who wants the old silence for a particular call, batch or child
chart has the slot: an occupied `on_error` is section 4's definition of
handling.

### 3. `core.invoke` classes `error`, and so does every `InvokeStep` type by default

`core.invoke` exports `failure_outcomes/1` returning `["error"]`. Reaching that
outcome means the call did not succeed, which is what the outcome has always
meant and what the `slot_style` `:failure` on `on_error` has always drawn.

`StatifierBlocks.InvokeStep`'s `use` macro defines the same default for every
host type built on it, beside the `outcomes/1` it already defines, and adds
`failure_outcomes: 1` to the `defoverridable` list. A host type whose `error`
is routine - a probe that reports "not found" through it, say - overrides it
with `[]` or with its own list, in the same place it would override
`outcomes/1`.

**This narrows one sentence of the Note of this date above**, and it is worth
saying which. That Note says a type that does not export the callback classes
nothing, "so a host type written before the callback existed compiles to the
bytes it compiled to". For a type built on `use StatifierBlocks.InvokeStep`
that is no longer true: it now exports the callback by inheritance, so its
`error` outcome is classed without its author writing anything. That is the
intended reading of the ruling - a step that calls out to the world and comes
back on `error` failed, and a host that disagrees says so in one line - but it
is a change to a host's compiled bytes that the earlier Note's sentence did not
anticipate, and section 6 counts it.

### 4. The nested-to-root propagation rule

**What handling means.** A failure-classed outcome of a block is **handled**
when the block's own type declares an `on_<outcome>` slot for it and the
document put a child in that slot. It is **unhandled** when the type declares
no such slot, or declares it and the document left it empty. Nothing else in
this package counts as handling it, because nothing else in this package looks
at a child's outcome: `Emit.chain/2` wires a container's children on
`done.state.<child>`, which fires for every final a child can reach, and no
core container emits a transition selected by `done.outcome.<child>.<outcome>`.

The reading is deliberately about the failing block rather than about the
container above it. A container that runs a step and then runs the next one has
not decided anything about how the step ended; the author who filled in "if it
fails" has.

**What the compiler emits.** Under `child_use: true` or `terminate: true` -
the same gate the root completion finals already sit behind, and nothing at
all outside it:

1. Walk the resolved tree **below** the root block, in document pre-order.
   Collect the pair `{state_id(block), outcome}` for every outcome in
   `BlockType.failure_outcomes(module, config)` that is also in
   `BlockType.outcome_names(module, config)` and is unhandled by the reading
   above. A class naming an outcome the type does not declare contributes
   nothing, which is the resolver's own posture toward a malformed return.
2. If the collected set is empty, emit nothing. A document with no unhandled
   failure-classed outcome below its root compiles to the bytes it compiles to
   today.
3. Otherwise emit **one** additional top-level `<final>`, sibling of the root
   completion finals, its id minted from the root block's id under the role
   `child_failed` or `root_failed` - the same two prefixes the completion
   finals use, so a reader can tell which compile option produced it. Its
   `<donedata>` carries the reserved `statifier_persistence:run_status` param
   with the value `failed`, spelled exactly as the Note of this date spells it;
   under `child_use: true` it carries the `outcome` param beside it, with the
   value `error`.

   [Note 2026-09-06, `sb-ju4d`: `sb-hxs5` mints that id as the root block's id
   under the role `<prefix>failed`, and a **root** block declaring an outcome
   literally named `failed` would mint the same id for its own completion
   final. Open, filed as `sb-k0dy`; whether the answer is a fallback role or a
   compile refusal is a decision this flip does not take.]
4. And emit, **on the root block's own state**, one `<transition>` per
   collected pair in walk order: `event="done.outcome.<state id>.<outcome>"`,
   `target` the single final from step 3, external. External because the point
   is to leave the root state for a sibling final; the completion transitions
   beside it are external for the same reason.

Attribution follows `ADR-0004` decision 5 and `Emit.chain/2`'s rule rather
than the completion finals': each transition is stamped to **the failing block**,
because "what happens after the authorize step fails" is a fact about the
authorize step, and the shared final is stamped to the root block, which is the
only block the document's own ending is a fact about. The provenance map stays
total over the added bytes.

**Why it reaches the root before the container advances.** The two events are
both on the internal queue and their order is fixed by the SCXML processor's
own procedure: entering a `<final>` runs its `onentry` content - which is where
`Emit.final/1` puts the `<raise>` of `done.outcome.<state id>.<outcome>` - and
only then is `done.state.<parent>` generated. The internal queue is FIFO, so
the outcome event is selected first. The root's transition exits the root
state, `done.state.<parent>` is then selected by nothing, and the sequence
never takes its step. This is the whole mechanism; there is no flag, no
datamodel write, and nothing a container has to cooperate with.

**Why an inner handler wins without the root knowing.** Transition selection
walks outward from the atomic states, and a transition in a descendant
pre-empts one in an ancestor for the same event. So a container that one day
does route a child's outcome event - a `core.branch` on an outcome, say, if a
later record decides to have one - pre-empts this catch by construction, and
nothing here needs a rule for it. Today no container does, which is why the
slot reading above is the whole of the definition rather than the first case of
it.

**Why one shared final rather than one per pair.** What a durable stepper reads
is that the run failed; *which* block failed is in the trace and in the
provenance map, at higher fidelity than a final id could carry. One final also
keeps the added bytes proportional to "does this document have any unhandled
failure at all" rather than to the number of blocks in it, and keeps the
top-level shape a reader has to hold in their head at the size ADR-0004's root
shape fixed it at.

**Why `outcome` is `error` under `child_use`.** That compile option exists so a
parent chart can branch on how the child chart ended, and the parent reads the
child through `core.subchart`, which appends `error` to its outcomes whether or
not the author listed it. `error` is therefore the one word a parent is
guaranteed to have a route for, and reporting the nested block's own outcome
name instead would put a name from inside the child chart into the parent's
branch vocabulary - which is exactly what `core.subchart`'s declared outcome
list exists to prevent.

**Where the emission is recorded.** The compiled shape a document's root
carries, its provenance and its byte determinism are `ADR-0004`'s, not this
record's. This section fixes what the added bytes *are* and why, because that
is a fact about outcomes and their classes; the reading of them as a root shape
is Noted on `ADR-0004` by `sb-hxs5` when the code lands, exactly as the
reserved failure param's was on 2026-09-06.

**The root block itself is untouched.** The walk starts below it, and the
completion finals it already emits for its own outcomes are unchanged,
including when its own `on_<outcome>` slot is occupied. That asymmetry is on
purpose: at the root the outcome *is* the document's answer, and a chart that
ends on its failure-classed outcome reports failure whatever ran on the way
out; below the root the outcome is not the document's answer, the document goes
on, and an occupied slot is the author saying what going on means.

### 5. Where each container leaves a failure, today

Read down the second column for whether the container itself does anything
about a child's failure-classed outcome, and the third for what a document sees.

| Container and slot | Routes a child's failure-classed outcome? | What happens |
|---|---|---|
| `core.sequence` `body` | no - `Emit.ordered/2` chains on `done.state.<child>` | the root catch selects first; the sequence is exited mid-chain and its pending `done.state` is selected by nothing |
| `core.group`, `core.resumable_group`, `core.drafts` bodies | no - the same `Emit.ordered/2` and `Emit.interruptible/2` chain | as `core.sequence` |
| `core.branch` arms | no - an arm is chosen by its condition before the child runs, and the branch finishes on `done.state.<child>` | as `core.sequence`; the branch is exited from whichever arm was taken |
| `core.parallel` regions | no | as `core.sequence`; the sibling regions are torn down with the root state, which is what leaving a `<parallel>` means |
| `core.foreach` `body` | no | as `core.sequence`; the iteration stops where it is, mid-list |
| `core.on_event` | it declares no outcome to class - `abandon` and `resume` are the interrupt protocol's events, not outcomes - and it routes none | nothing of its own; a failure inside the body it guards reaches the root exactly as it would anywhere else |
| `core.invoke` `on_error` | **yes**, when occupied | occupied: the child runs and the block ends on `error`, the container advances, and nothing reaches the root. Empty: the root catch fires |
| `core.subchart` `on_<outcome>` | **yes**, when `on_error` is occupied | occupied: the child runs and the block ends on `error`, and nothing reaches the root. Empty: the root catch fires, on section 2's unconditional final. The child chart's own run has already failed on its own root, which is how the `error` outcome was reached at all |
| `core.map` `on_error` | **yes**, when occupied | occupied: the batch ends on `error` into the slot's child, and nothing reaches the root. Empty: the root catch fires, on section 2's unconditional final. The body is a separate chart document, so a failed *child of the batch* is data in `collect` (ADR-0009 decision 5) and is not a failure of this document; what the class is about is the batch ending on `error` |

Every "the root catch fires" in the third column depends on section 2: before
this amendment all three of the routing types emitted their failure final only
when the slot was occupied, so with the slot empty there was no final, no
`done.outcome.<state id>.<outcome>` and nothing for the root to select. Under
the extended rule the final is there in every case, and the three rows read the
same way as the six above them.

The two chart-referencing types are where the rule composes: a nested failure
in a child chart fails **that** document's run through this same rule at its own
root, the durable stepper reads the reserved param, the invocation comes back
as failed, and `core.map` or `core.subchart` takes its own `error` outcome -
which is then either handled by its slot or caught by this rule one level up.
There is no separate cross-document mechanism, and no document needs to know
how deep it is.

### 6. What this costs a host, and what it does not

Five kinds of document compile to different bytes than they did at 0.21.0. The
first three are section 2's and apply whatever the compile options are, because
an outcome final is emitted by the block type rather than by the root pass; the
last two are section 4's and section 3's and arrive only under `child_use:
true` or `terminate: true`:

- one containing a `core.invoke` whose `on_error` slot is **empty** - it gains
  that block's `error` outcome final and the transition into it (section 2);
- one containing a `core.map` whose `on_error` slot is **empty** - the same two
  byte spans, on the same reason (section 2). A failed batch now ends the
  block on `error` and, below the root, propagates, where before it was
  selected by nothing;
- one containing a `core.subchart` whose `on_error` slot is **empty** and whose
  referenced chart does not itself declare `error` - the same again (section
  2). A failed child chart now ends the block on `error` and, below the root,
  propagates. Where the referenced chart *does* declare `error`, the final was
  already emitted and only the transition into it is new;
- one containing any unhandled failure-classed outcome below its root, under
  the two compile options - it gains the shared failed final and one transition
  per pair (section 4);
- one containing a host type built on `use StatifierBlocks.InvokeStep`, on the
  same counts, because that type is now classed by default (section 3).

A document's content hash changes with its bytes, so such a document is a
different chart revision under statifier-ex ADR-0052 - the same one-time cost
the Note of this date already described for a root `core.map` or
`core.subchart`. It is why 0.22.0 is a minor release carrying this record's
Notes, and not a patch.

Nothing else moves. Routing is unchanged: a failure-classed outcome is still
reached from `done.outcome.<state id>.<outcome>` like any other, and a
`core.branch` arm, an `on_<outcome>` slot and an editor connector still treat it
exactly as they treat `done`. ADR-0011's typed environment reads nothing new and
writes nothing new. No slot arity, no `slot_style`, no palette entry and no card
changes. And no `<invoke>`, `<send>` or datamodel element is added anywhere: the
whole of the addition is transitions and one final.

**Decision 10's rows are not edited here**, in the posture every Note above this
line takes - and they need no edit: the `core.invoke` row's `outcomes(config)`
column has read `done` and `error` since the amendment of 2026-08-28 that wrote
it. What changes from this date is not the row but the code beneath it, which
now exports the `outcomes/1` the row has always described.

Filed with `sb-ii2k`, campaign-034 rulings `RQ-034-1` and `RQ-034-13`. The code
is `sb-hxs5`; this section merges at proposed and the record's own acceptance
is the operator's, through `sb-ju4d`. The reference embedder's host-side
translation comes out with `se-cqr`, against `statifier_persistence`'s ADR-0008
amendment of 2026-09-06, decision 6.

### Note (2026-09-06): what the flip checked, section by section

The flip request `sb-ju4d` read sections 1 through 6 and the per-container
table against `main` at `0f9f2cd` - the tree `sb-hxs5` left (PR 328) - rather
than against the tree this section was drafted over. Every decision holds, and
the closing paragraph above, which says this section merges at proposed and
leaves its acceptance to `sb-ju4d`, is left standing rather than rewritten:
this Note is that acceptance. Nothing above this Note is edited by it.

**Section 1 holds.** `StatifierBlocks.Core.Invoke.outcomes/1` returns
`[{"done", "Done"}, {"error", "Error"}]`, fixed rather than config-derived
(`lib/statifier_blocks/core/invoke.ex:114`), which is the pair
`StatifierBlocks.InvokeStep.outcomes/0` already returned
(`lib/statifier_blocks/invoke_step.ex:217`). The `on_error` slot is one
`zero_or_one` slot still.

**Section 3 holds, in both halves.**
`StatifierBlocks.Core.Invoke.failure_outcomes/1` returns `["error"]`
(`:127`). The `use` macro defines `failure_outcomes/1` from
`StatifierBlocks.InvokeStep.failure_outcomes/0`
(`lib/statifier_blocks/invoke_step.ex:172`, `:237`) and `failure_outcomes: 1`
is in the `defoverridable` list beside `outcomes: 1` (`:186`), so a host type
built on the macro is classed by inheritance and overrides in one line.

**Section 2 holds in all three types, and the unconditional final is the
same id in each.** `core.invoke`'s `failure_transition/1` targets the final
directly when the slot is empty and the child when it is occupied, and
`error_final/1` emits the final in both branches
(`lib/statifier_blocks/core/invoke.ex:327-344`); `core.map` has the same
three clauses on the same shape (`lib/statifier_blocks/core/map.ex:623-631`);
`core.subchart` keeps `error` past the `routed? or child` filter whatever the
author declared and whatever the slot holds
(`lib/statifier_blocks/core/subchart.ex:495-526`). All three mint the final
through `Compiler.Context.outcome_id/2`, which is the id the occupied case
already used.

**Section 4 holds, step for step.** `Compiler.propagation/3` runs only from
the `completion_finals/4` clause the `:child_use` / `:terminate` `cond`
selects (`lib/statifier_blocks/compiler.ex:1363-1394`); `unhandled_failures/1`
starts at the root's slots rather than the root
(`:1523`); `node_failures/1` walks the block then its slots in declaration
order and keeps only an outcome that is both classed and declared
(`:1536-1546`); `unhandled?/2` reads a declared `on_<outcome>` slot with a
child as handled and an undeclared or empty one as unhandled (`:1549-1555`);
the empty set emits nothing (`:1501-1503`); the one shared final is minted
under `prefix <> "failed"` from the root block's id and stamped to the root
block (`:1506-1510`, `:271`), its `<donedata>` carries
`statifier_persistence:run_status` with `'failed'` (`:263-264`, `:1443-1449`)
and, under `:child_use`, the `outcome` param with `'error'` (`:279`,
`:1424`); and one transition per pair is emitted on the root block's state
with no `type` attribute, which is external (`:1561-1570`).

**Section 5's table holds.** `Emit.final/1` is the only place that raises
`done.outcome.<state id>.<outcome>` (`lib/statifier_blocks/core/emit.ex:120`),
and no core container emits a transition selected by one: the only other
`outcome_event` in `lib/statifier_blocks/core/` is `core.on_event`'s own
config reader for `abandon` and `resume`
(`lib/statifier_blocks/core/on_event.ex:646`, `:712-714`), which is the
interrupt protocol the table's `core.on_event` row names and not an outcome
route.

**Section 6's five classes hold, and the corpus pins the sixth case.**
`StatifierBlocks.ByteCorpus` carries five documents - the two worked examples
and one each of `core.invoke`, `core.map` and `core.subchart` with the
failure slot **occupied** - each pinned under `plain`, `terminate: true` and
`child_use: true`, which is the fifteen golden files under
`test/fixtures/corpus/` (`test/support/byte_corpus.ex:28-43`). That is where
"an occupied slot compiles to the bytes it compiled to" and "a document with
no unhandled failure below its root is byte-identical under the gate as well
as outside it" are cashed.

**Two cites that were forward-looking when the section was written now
resolve.** The reading of the added bytes as a root shape is Noted on
`ADR-0004` by `sb-hxs5`, as this section's "Where the emission is recorded"
paragraph said it would be, and that Note also supersedes `ADR-0004`'s
earlier sentence that the three routing types emit their failure route only
when the slot is occupied. And `ADR-0009`'s Note of this date, which this
amendment's section 2 and section 4 are cited by, reads the `collect`
envelope off `statifier_persistence`'s `Driver`: a failed child's entry is
`"status" => "failed"` with a `"failure"` map, a completed child's is
`"status" => "completed"` with its donedata, and a cancelled one's is
`"status" => "cancelled"` alone
(`statifier_persistence/lib/statifier_persistence/driver.ex:1157`, `:1160`,
`:1172`). That Note carries no `Status:` line of its own - Notes in this
family do not - so there is nothing on it for this flip to turn, and it is
left untouched.

Filed with `sb-ju4d`; the section it accepts was filed with `sb-ii2k` (PR
320, `757ff3f`) and built by `sb-hxs5` (PR 328, `0f9f2cd`).

## Note (2026-09-06): three corrections the payload amendment takes, and the two lines it does not re-wrap

Residue from the pass-2 reviewer of the amendment of this date that begins at
`:4010` (`sb-i0cc`, PR 324, merged at `6975e91`). The reviewer raised these as
non-qualifying NOTES rather than as findings, so that amendment merged on an
UNQUALIFIED verdict without them and curing them then would have invalidated
the reviewed head. They are recorded here rather than edited in, which is the
posture every Note above this line takes. **Nothing above this Note is edited
by it**, and no decision moves: `P1` through `P5` decide exactly what they
decided at `6975e91`.

### 1. `P3`'s "either side of it" is a chronology slip: both key amendments are earlier

`P3` says, of the `{:path, opts}` amendment of 2026-09-05 at `:2761`, that
"the two amendments either side of it took an optional **key** instead
(`datamodel_path?` at `:1004`, `sensitive?` at `:1187`)" (`:4117-4120`). Both
of those amendments are dated **2026-08-29** and both sit above `:2761`, so
neither of them is on the later side of it. Decision 7 has taken exactly three
amendments, in this order:

| Line | Date | What it added |
|---|---|---|
| `:1004` | 2026-08-29 | the optional `datamodel_path?` key |
| `:1187` | 2026-08-29 | the optional `sensitive?` key |
| `:2761` | 2026-09-05 | the `{:path, opts}` field type, the set's eighth member |

Nothing has amended decision 7 since. The Note of this date at `:3456` gives
`{:path, opts}` its first two `opts` keys, but it is a Note and not an
amendment and it adds no member either, so the sentence has no later neighbour
to have meant. Read it as **"the two earlier amendments"**.

What the slip does not touch: the attribution is right - `:1004` and `:1187`
are the key-only pair, and each does say in its own words that the type set
stays closed (`:1028-1032`, `:1235-1238`) - and the argument `P3` rests on
them, that an optional key is the cheap change and a ninth field type is not,
holds whichever side of `:2761` they sit on. Two words of chronology, not a
false cite.

### 2. `P5`'s `check_capture/2` cite began one comment block short, and where it stands today

`P5`'s first bullet cites `lib/statifier_blocks/core/on_event.ex:283-296` for
the reason `check_capture/2` "already gives in the module" (`:4188`). At
`6975e91`, `:283` was the `defp check_capture(findings, config) do` line; the
reason itself - that "`capture` has no field in `config_schema/1` to render a
per-pair finding against ... so the anchor an editor could use is the key
itself" - is in the comment block directly above the function, at `:277-282`,
and the cited range starts one line past its end. The cite named the function
and stopped short of the sentence it was offered for.

The range a reader follows **today** does carry the reason, by where the code
moved rather than by design. The Note at `:4272` re-points that cite to
`on_event.ex:352-373` (`:4320`), and on `main` at `f3e737f` `:352` is the first
line of that same six-line comment block and `:358` is the `defp`. So the
original cite was one block short and the moved cite is not; the two are
recorded here together so a reader who compares them does not read the
difference as a drift in the code. Neither range is edited.

### 3. Two lines left over-long in the payload amendment, and why they stay

`:4120` (140 characters) and `:4221` (145 characters) are unwrapped where the
body prose around them stays near 79: inside the amendment that begins at
`:4010` the widest of their neighbours are `:4040` at 83 and `:4217` at 80,
and everything else over 79 in that span is a heading or a table row.

They did not arrive together, and the reviewer NOTE that named them said they
did. Only `:4120` came from `sb-i0cc`'s pass-1 cure: it is absent at `b093ca0`,
the pre-cure head, and first appears at the cure commit `bcd2bce`. `:4221` is
older than the cure - it stands verbatim at `b093ca0`, where it is the one
body line past `:4000` over 100 characters - so it came in with the amendment's
first draft. The correction is recorded here rather than carried forward.

They are **not** re-wrapped, for the reason the second of them states about
itself at `:4218-4221`: wrapping a line adds a line, and every line below it
shifts, and the lines below are cited by number. The precedent at `:4218-4221`
names five such lines (`:3329`, `:3331`, `:3418`, `:3528`, `:3814`), each cited
by another section of this record, so an insert there would have falsified the
record for every reader.

This case is the same case, and it acquired its clearest instance while this
Note was being written. `ADR-0013` cites **this record by line number**, and at
the place it does so three of the four lines it names sit below `:4120`:
`docs/adr/0002-block-type-behaviour.md:4108`, `:4121-4122`, `:4126` and
`:4133`, quoted there for `P3`'s two decided arms and its closing "**No ninth
field type is added by it**"
(`docs/adr/0013-typed-fan-out-child-summary.md:143-144`). Wrapping `:4120`
would move every one of them by a line and leave another record on `main`
pointing at the wrong text. This Note's own cites go the same way - `:4188`,
`:4214`, `:4218-4221`, `:4272`, `:4318-4320`, `:4325`, `:4656` and
`:4739-4740` all sit below `:4120` - but they are no longer the only ones at
stake, and they were never the reason.

Closing two long lines buys a reader nothing to weigh against that.
`sb-nhw0`'s own terms settle it independently: amend-by-addition, zero removed
lines. Both lines read correctly as they stand; they are recorded here as
known, and left.

### The reviewer's fourth item, and why nothing here answers it

The fourth NOTES item was a serial hazard for the conductor rather than a
correction to this record: PR 320 (`sb-ii2k`), open at the time and appending
to this same file, would need a rebase over PR 324 once 324 landed. It landed -
the amendment that begins at `:4325` is its work, and the Note at `:4656` is
its acceptance - so the hazard is spent and there is nothing in the record to
correct for it.

This Note carries no `Status:` line. That is this file's convention for a Note,
as the Note at `:3456` shows (its heading is followed by prose at `:3458`, not
by a status line) and as the Note at `:4656` states in as many words at
`:4739-4740`: Notes in this family do not carry one.

Filed with `sb-nhw0`, from `sb-i0cc`'s pass-2 reviewer NOTES.

## Note (2026-09-06): an optional `donedata_type/1`, the thirteenth callback, and what decision 5's table of nine counts

A dated Note rather than an amendment. It edits nothing above this line, and in
particular it does not touch decision 5: the five required callbacks are still
the five it names, `emit/2` is still listed for the reason it gives, and no row
of its table gains or loses a word. What this Note records is a **new optional
callback beside** those, declared by `ADR-0013`
(`docs/adr/0013-typed-fan-out-child-summary.md`, decision 2, proposed
2026-09-06 under the operator's campaign-SF035 grant, recording campaign-034's
ruling `RQ-034-2`), and what it does and does not reach.

The form is the Note of this date at `:3832`, which recorded `failure_outcomes/1`
the same way and for the same reason: a new optional callback is additive to
decision 5 rather than a change to it, and the record catches up to the
behaviour rather than re-deciding the surface.

This record has taken the other form once, and the difference is worth stating
rather than leaving to look like an inconsistency. Amendment H of 2026-08-30
(`:1751`) recorded the optional `summary/1` as an **amendment**, because it
also decided what a core card's second line says - a presentation decision this
record owns and had not taken. `donedata_type/1` decides nothing this record
owns: what it declares is `statifier_datamodel`'s vocabulary, where the params
it produces go is `ADR-0004`'s C1, and what a parent does with them is
`ADR-0009`'s and `ADR-0011`'s. So it takes the `failure_outcomes/1` shape and
not amendment H's.

**The callback.** `StatifierBlocks.BlockType` declares
`donedata_type(config) :: [donedata_field()]`, optional, where a
`donedata_field` is a map of `name`, `path` and `type` - the `<param>` name a
field is emitted under, the datamodel path its `expr` reads at the child's own
runtime, and the field's type in `statifier_datamodel`'s vocabulary
(`t:StatifierDatamodel.Types.t/0`). It is resolved through
`BlockType.donedata_type/2` the way `outcomes/1` and `failure_outcomes/1` are -
`Code.ensure_loaded?/1` plus `function_exported?/3`, defaulting to `[]`. A type
that does not export it declares nothing, which is where every shipped `core.*`
type stays, so a host type written before the callback existed compiles to the
bytes it compiled to.

The three rules `slots/1` and `config_schema/1` carry apply to it unchanged -
it is a **pure function of `config`**, it is **total** for any config
`validate_config/1` accepts, and it **never raises**. Those are the three
`summary/1` restates in those words
(`lib/statifier_blocks/block_type.ex:609-612`) and the three `outcomes/1`
states as its stability rule (`:538-542`). Order is declaration order and is
never sorted, for `ADR-0004` decision 6's reason: the params serialize in the
order the callback returns them, so reordering the list moves compiled bytes.

**Two reserved names it may not mint.** A declared `name` may be neither
`outcome` nor `statifier_persistence:run_status`. Those two are the compiler's -
the first is `ADR-0004`'s amendment C1, the second the failure seam's reserved
param recorded in the Note of this date at `:3832` - and a declaration that
collides with either is an `:invalid_donedata_field` Emit finding against the
root block rather than a silently shadowed param.

**What decision 5's table of nine counts, and what is declared today.** The
table at `:109-121` reads "nine callbacks, five required" and lists nine.
Twelve are declared on the module today - `slots/1`, `config_schema/1`,
`validate_config/1`, `current_version/0`, `emit/2`, `io/1`, `migrate_config/2`,
`fixtures/0`, `palette_entry/0`, `outcomes/1`, `failure_outcomes/1`,
`summary/1` (`lib/statifier_blocks/block_type.ex:252`, `:330`, `:338`, `:345`,
`:374`, `:382`, `:389`, `:424`, `:520`, `:548`, `:581`, `:620`), seven of them
optional (`:622-628`) - and `donedata_type/1` is the **thirteenth**. The count
is stated here rather than left to be derived from the table because the table
lists nine where the module declares twelve, and has done since before this
Note - which is also why nothing above this line is edited to correct it.
Three callbacks arrived after decision 5 was accepted, and each was recorded
the way this one is: `outcomes/1` by amendment A (`:703`), `summary/1` by
amendment H (`:1751`), and `failure_outcomes/1` by the Note at `:3832`. A reader wanting the live surface reads `@optional_callbacks` and the
`@callback` list; a reader wanting what decision 5 contracted reads the table.

**What it does not reach.** Nothing in this package's editor, routing or
palette branches on it. It declares no outcome and classes none, so
`outcomes/1` and `failure_outcomes/1` are untouched and amendment A2's refusal
to marry an outcome to a slot is not in play. No slot arity, no `slot_style`,
no `palette_entry/0` key and no card changes; `summary/1` is still the card's
second line and the two are deliberately differently named, which `ADR-0013`
decision 2 gives its reason for. Decision 7's closed field-type set is not
widened by this Note: `core.map`'s companion field `collect_type` is typed
`:string`, which is the split the `payload` amendment of this date took in its
section `P3` at `:4108` - the declared-name arm gets a field typed `:string`
(`:4126`), the inline-shape arm gets no field type and none is invented for it
(`:4133`) - under the sentence that section closes its opening on at
`:4121-4122`: "**No ninth field type is added by it.**".

**Where the bytes go.** The declared fields are emitted as `<donedata>`
`<param>`s on every top-level `child_use` final, after both compiler-minted
params. That is `ADR-0013` decision 3 and it widens `ADR-0004`'s amendment C1;
the amendment filed with this Note carries it on that record, and the ordering
is what keeps the reserved failure-seam param's bytes stable.

This Note carries no `Status:` line, which is this file's convention for a Note
- the Note at `:3456` shows it (its heading is followed by prose at `:3458`,
not by a status line) and the Note at `:4656` states it in as many words at
`:4739-4740`. `sb-upv0` flips the sections that carry one; there is nothing to
flip here.

Filed with `sb-jvz3`, against `ADR-0013` as merged; campaign-SF035, from
campaign-034's ruling `RQ-034-2`. `sb-nqfd` builds the callback.

## Amendment (2026-09-06): decision 7, the `{:type_expr, opts}` field type

**Status: accepted (2026-09-06).** Drafted for `sb-zvar` under the operator's
campaign-SF035 grant, recording that campaign's ruling `RQ-SF035-1`, and
merging at proposed under that campaign's invariant like every other section
filed with it; flipping it to accepted is a separate gated request, and
`sb-wzoa` carries it. Additive: decision 7 and every amendment and Note it has
taken - `value_path` (2026-08-27), `datamodel_path?` (2026-08-29), `sensitive?`
(2026-08-29), the `{:path, opts}` amendment at `:2761` and the Note that gave
`opts` its first two keys at `:3456` - all stand exactly as written, and no
text above this line is edited by this section.

It is appended at the **end of this file** rather than beside decision 7 for
the reason the Note at `:4803` gives about itself: `ADR-0013` cites this record
by line number, and three of the four lines it names sit inside `P3`
(`docs/adr/0013-typed-fan-out-child-summary.md:143-144`, citing `:4108`,
`:4121-4122`, `:4126` and `:4133`). An insert above any of them would leave
another record on `main` pointing at the wrong text.

### Context

`P3` of the payload amendment of 2026-09-06 (`:4108`) split a type expression
into two arms and took one of them. The declared-name arm got a field typed
`:string`; the inline-shape arm got no field type, "and none is invented for
it" (`:4133`), under the sentence the section closes its opening on at
`:4121-4122`: "**No ninth field type is added by it.**" The reason given there
was not that the arm is unwanted but that no member of decision 7's set
describes a shape, and adding one to spell a shape nothing stored yet would
have been a second proposal riding along with the first.

`ADR-0013` reached the same fork the same day and took the same half.
`collect_type` on `core.map` is declared `:string`, "ADR-0002 decision 7's set
stays closed at the eight members declared today ... and no ninth is added
here" (`docs/adr/0013-typed-fan-out-child-summary.md:133-135`). That record then
deferred the inline arm **by name**, to this campaign's typed-shapes theme, as
four things only worth deciding together: a `{:type_expr, opts}` member of this
record's field-type set, an inline-shape inhabitant of
`StatifierBlocks.Environment`'s `type_expr()`, the editor control that renders
one, and the migration of `payload` onto the same spelling
(`:148-157`). "Each on its own is a partial answer, and `payload` is already
waiting for the whole one."

This section is the **first** of those four, and the other three are placed
rather than pending: the control's row is decided beside it, the environment's
inhabitant is `sb-myt1`'s, and the migration is `sb-268w`'s. What all four were
waiting on - a way to *say* a shape without naming it - has landed.

**A shape can be said without being named.** `sd-ADR-0001`'s inline-shape
amendment is accepted in `statifier_datamodel` on this campaign's ruling
`RQ-SF035-1`, and its code is on that repository's `main`. A type expression
there may now be `{:shape, members}`, `members` an ordered list of maps each
carrying exactly `name`, `type` and `required?`; member order is authoring
order and identity is member-set-wise; an inline shape is **built by a
consumer** and has no document syntax. That is the vocabulary this package
reads and does not mint, exactly as `P2` says of the rest of it (`:4076`).

**The control has a row.** `ADR-0005`'s Note of 2026-09-06
(`docs/adr/0005-liveview-editor.md:7006`) decides how a `{:type_expr, opts}`
field is drawn - a `<datalist>` of the document's declared type names for the
name arm, a member-list form in the inspector's Config tab for the inline arm,
a toggle when a field admits both - and says in terms that the field type
itself is this record's: what it stores, what `opts` carries, what config-time
validation reads, and which fields migrate. This section is that half.

**Two fields want it.** `payload` on `core.on_event` is declared `:string`
today (`lib/statifier_blocks/core/on_event.ex:287-292`), by `P3`.
`collect_type` on `core.map` is declared `:string` by `ADR-0013` decision 1 and
is not in `config_schema/1` yet (`docs/adr/0013-typed-fan-out-child-summary.md:568-578`).
`P3`'s objection - a member for a shape nothing stores - is spent: two fields
store one, one of them shipped.

### Decision

**Decision 7's closed field-type set gains a ninth member, `{:type_expr,
opts}`.** The set is `:string`, `:integer`, `:boolean`, `{:select, choices}`,
`:expression`, `:duration`, `{:list, field_type}`, `{:path, opts}`, and now
`{:type_expr, opts}`. It is still closed, and this is a widening by one named
member rather than an opening, on the argument the eighth member was admitted
on (`:2801-2806`): the property the closed set exists for is that the editor
can draw every member, and a type expression left as a bare `:string` gets no
list of declared names and no form for an inline shape, exactly as a path left
as a bare `:string` got no candidates and no advisory.

**1. What the field holds: three arms, and the third is absence.** A
`{:type_expr, opts}` field's value is one of:

- **a declared type name** - the `name` of a `record` or a `shape` the
  datamodel document's `types` key declares, stored as text and resolved with
  `StatifierDatamodel.Declarations.fetch/2`. This is the arm `P3` already
  decided and the arm every stored value is today;
- **an inline shape** - `sd-ADR-0001`'s `{:shape, [member()]}`, a member being
  `%{name: String.t(), type: t(), required?: boolean()}`. This record **cites**
  that spelling and does not respell it: the grammar, member order, the
  member-set-wise identity and the rule that a member's type is never absent
  are written down in that amendment and only there;
- **absent** - no key, or an empty value. That is what every document written
  before this date carries, and clause 5 says what it means.

**1a. The stored spelling is JSON, and neither arm is an Elixir term on disk.**
`ADR-0001` owns the stored bytes and a block's `config` is opaque JSON, so
`ADR-0005`'s Note is right to send the question here and this clause answers
it:

- the **name arm** is a JSON **string** - exactly the bytes both migrating
  fields store today;
- the **inline arm** is a JSON **list of objects**, each carrying `"name"`,
  `"type"` and the optional boolean `"required?"`. Those are the same three
  keys, spelled the same way, that a field object carries inside a datamodel
  document's declaration (`sd-ADR-0001` decision 5, whose worked shape writes
  `{"name": "brand", "type": "string", "required?": true}`). A member's
  `"type"` is itself a type expression under this clause, so a member may hold
  a member list of its own and the spelling recurses;
- the **absent arm** is a missing key, `null`, or `""`.

The two arms are told apart by the JSON type alone and no tag key is minted
for it: a string is never a member list. `{:shape, members}` is the Elixir term
this package **builds** from that list when it hands the value to
`statifier_datamodel` (clause 3); it is never what a document holds.

This adds no document syntax to `statifier_datamodel` and does not reopen its
clause (c). A block document is `ADR-0001`'s and has carried consumer-built
values since it existed, which is the distinction `ADR-0005`'s Note draws in
the same words.

There is no fourth arm. A scalar spelling and an opaque string are not arms of
their own: they are what `StatifierDatamodel.Types.parse/2` returns for text
the document declares nothing for, they are read exactly as that package reads
them, and `P2`'s sentence about them is unchanged (`:4095-4099`).

**2. `opts` carries two keys, and both are optional.** `opts` is the second
element of a tuple for the reason `{:select, choices}`, `{:list, inner}` and
`{:path, opts}` have one (`:2822-2830`): what a control needs can arrive
without widening the set a second time.

```elixir
@type type_expr_opts :: %{
        optional(:arms) => [:name | :inline, ...],
        optional(:allow_empty?) => boolean()
      }
```

and decision 7's field-type union gains `| {:type_expr, type_expr_opts()}`
beside `{:path, path_opts()}`, in the reading the last bullet of *What this
section does not decide* describes rather than in the bytes of any of the
three places that union is written out.

- **`arms: [:name | :inline]`** - which arms this field admits. The default is
  both. A field declaring `arms: [:name]` admits a declared name and nothing
  else; a field declaring `arms: [:inline]` admits a member list and nothing
  else. It is the key `ADR-0005`'s Note of 2026-09-06 reads to decide whether
  its control draws a toggle, and it is why that decision needed no key of its
  own.
- **`allow_empty?: boolean()`** - whether the absent arm is admitted. The
  default is `true`, which is what both migrating fields want and what every
  stored document already is. A field declaring `allow_empty?: false` has an
  empty value refused by clause 4's shared check rather than by each block type
  re-implementing the same test in `validate_config/1`.

`allow_empty?` and decision 7's own `required?` flag are **not** the same
claim, and a declaration carrying `required?: true` with `allow_empty?: true`
is neither a contradiction nor a finding. `required?` is a field declaration's
flag on every field type, and decision 7 fixes what it is: part of a rendering
hint, above the sentence that makes `validate_config/1` the authority
(`:180-186`, `:216-226`). `allow_empty?` is scoped to this member and says what
this member's own shared check does with an empty value. Neither reads the
other, and `validate_config/1` remains the authority over both, per decision 7
unamended.

No third key is defined here. Read/write direction is not one: a type
expression names a type and never a location, so the key the `{:path, opts}`
amendment holds open for its own `opts` (`:2826-2829`) has nothing to say about
this member.

**3. Config-time validation reads the document's declarations for the name arm,
and builds the inline arm rather than parsing it.** Both halves run in the
compile's `:config` stage, against the **same** `:datamodel` compile option the
typed environment and `P2` already read - one document, supplied once, read
once.

- **The name arm** resolves through `StatifierDatamodel.Declarations.fetch/2`,
  which is the resolution `P2` names for `payload` and is unchanged by this
  section.
- **The inline arm is constructed here, not parsed there.**
  `sd-ADR-0001`'s clause (c) is explicit that `Types.parse/2` reads a *binary*
  spelling, that there is no document syntax for an inline shape, and that one
  enters that package only as an argument a consumer hands `Types.satisfies/3`.
  So this package builds the `{:shape, members}` term from the members stored
  in the block's `config` and hands it over; it does not ask `Types` to parse a
  shape out of bytes, because that function does not do it and this section
  does not ask that package to change. Member well-formedness is
  `sd-ADR-0001`'s and is read from there, not restated here: a member whose
  `name` is not a non-empty string contributes nothing, a repeated member name
  keeps its first occurrence, and a member `type` that resolves to nothing is
  the datamodel's unknown.

**4. The refusal, and the two things that are not refusals.** A stored value
that is **neither arm the field admits** - text where `arms: [:inline]`, a
member list where `arms: [:name]`, an empty value where `allow_empty?: false`,
or bytes that are no arm at all - is a `:config` finding at compile, anchored
on the block and carrying the field's `key` as its `config_key`. That is the
existing anchor and the existing key: `{:config, block_id, key}` routes beneath
the field by decision 11's rule in `ADR-0005`, and `config_key` is the key on
the `Finding` struct already, which `sb-8mki`'s declaration refusal sets and
which campaign-SF035's ruling `RQ-SF035-5` settled as the place a field-scoped
finding names its field rather than growing the anchor tuple. No new finding
code, no new
severity, no new option. `ADR-0005`'s Note of 2026-09-06 draws such a value raw
in the name arm's text input with this finding beneath it, and adds none of its
own.

Two cases are **not** refusals, and are named so neither is read as a gap:

- **A name the document does not declare.** It resolves to nothing and is the
  undeclared case, exactly as `P4` fixed it for `payload` (`:4166-4172`): this
  section decides no finding for it, and whether it earns an advisory is
  `ADR-0005` clause `11e`'s kind of question. `ADR-0005`'s Note reaches the
  same answer from the control's side - the `<datalist>` "suggests and never
  constrains".
- **A compile with no `:datamodel`.** No declared name resolves, and clause 5
  governs, which is `P2`'s sentence unchanged.

**5. An absent value is today's behaviour, exactly.** A block whose config
carries no value for a `{:type_expr, opts}` field - which is every block in
every document authored before this date - is unchanged in every respect: no
new finding at any severity, and identical compiled bytes, because neither
migrating field emits anything. `ADR-0011` decision 12 already says what an
absent `collect_type` means and `P4` already says what an absent `payload`
means; this section changes neither.

**6. `datamodel_path?/1` is false for a `{:type_expr, opts}` field.** The
field is a **type**, never a path and never an expression - the sentence
`ADR-0013` decision 1 already writes about `collect_type`
(`docs/adr/0013-typed-fan-out-child-summary.md:171-174`).
`StatifierBlocks.BlockType.datamodel_path?/1` is total and true for two
spellings only, `{:path, _opts}` and the literal `datamodel_path?: true`
(`lib/statifier_blocks/block_type.ex:760-762`), so it answers `false` here
without a clause being added to it, and this section adds none. What follows is
what should follow: no path candidate list, no `ADR-0005` clause `11e`
undeclared-path advisory, and no `AssignLocation` read. `ADR-0005`'s Note keeps
the two feeds disjoint on `sd-ADR-0001` decision 7's own ground - the `types`
key contributes no path, so the declared paths a `{:path, opts}` field suggests
and the declared type names this one suggests share no member and are never
merged.

**7. Two fields migrate to it, and `sb-268w` migrates them.**

| Field | Declared today | After the migration |
|---|---|---|
| `payload` on `core.on_event` | `:string`, by `P3` (`lib/statifier_blocks/core/on_event.ex:287-292`) | `{:type_expr, opts}` admitting both arms |
| `collect_type` on `core.map` | `:string`, by `ADR-0013` decision 1; not in `config_schema/1` yet (`docs/adr/0013-typed-fan-out-child-summary.md:133-135`, `:568-578`) | `{:type_expr, opts}` admitting both arms |

**Nothing migrates by this section being accepted.** `sb-268w` carries both, as
`ADR-0013` named it, and it is the same shape the `{:path, opts}` amendment
took: that section named `core.subchart`'s `assign_to` and left the migration
to `sb-2ym4` (`:2849-2854`). Which arms each field ends up admitting is that
bead's, within what clause 2 defines; both want both today.

**8. A stored string stays valid as the name arm, and no document changes.**
Both migrating fields store text today, and after the migration that text is
read as the name arm: the same bytes, the same resolution through
`Declarations.fetch/2`, the same findings. No stored document is rewritten, no
`migrate_config/2` is called for it, and `ADR-0001`'s `schema_version` stays at
`1` - a field type is a block-type contract, which is this record's, and that
is the argument `P1` made for `payload`'s key itself (`:4066-4070`).

This is the whole of what makes the deferral `P3` and `ADR-0013` both took a
deferral rather than a debt: the arm each of them declined was additive to a
value neither of them changed.

**9. The `default:` rule for a `{:path, opts}` field, stated in the record.**
Campaign-SF035's ruling `RQ-SF035-6` rides here because it is decision 7's
rule and had no home in the record. A field declaration has always had to carry
`default:` - it is a required key of `field_decl/0` - and a `{:path, opts}`
field declared without it is **refused at declaration**, in the compile's
`:config` stage, as a finding anchored on the block and carrying the field as
its `config_key`. It is never a render-time raise, which is what the omission
produced before: a `FunctionClauseError` from inside the view-model build,
naming neither the block type nor the field, in whichever screen happened to
draw the block. `sb-8mki`'s code is on `main`
(`lib/statifier_blocks/compiler.ex:619-637`).

Three things this clause is careful **not** to say:

- **No example in this record gains a `default:`.** Every full
  `config_schema/1` example above already carries the key on every field; the
  only spelling that omits it is the inline `type: {:path, %{}}` at `:2830`,
  which is a sentence about a type and not a declaration. Nothing above this
  line is edited, here least of all.
- **The refusal is not widened past `{:path, opts}` by this clause.** For every
  other field type the view model reads `default:` permissively and renders a
  declaration written without it, so a `{:type_expr, opts}` field declared
  without the key renders rather than raising. The code says in as many words
  that widening the refusal to every field type "is a change to what a block
  type may declare, which is the record's call and not this stage's"
  (`lib/statifier_blocks/compiler.ex:604-611`). This section does not take that
  call. It is open, and it is not opened or closed here.
- **It attributes no fault.** Whether the pre-refusal raise was the view
  model's, the declaration's or the typespec's is not a question this record
  answers, and none of the three is named here as the one that was wrong.

### What this section does not decide

- **The control.** How either arm is drawn, what feeds the name arm's list,
  where the inline form renders and what a toggle does are `ADR-0005`
  decision 9's, decided by its Note of 2026-09-06
  (`docs/adr/0005-liveview-editor.md:7006`). Not restated here, and not
  reopened.
- **The environment's inhabitant.** `StatifierBlocks.Environment`'s
  `type_expr/0` (`lib/statifier_blocks/environment.ex:93`) has no inline-shape
  inhabitant today, and admitting a field type does not admit one: an
  environment entry and a config field are different values in different
  places. `ADR-0011` decision 1 is amended for it by `sb-myt1`, which is in
  flight as this section is written and unmerged - cited as the record that
  takes the question, not as a record whose text this one has read on `main`.
  A reader after both have landed reads that amendment for the environment's
  grammar and this section for the field's.
- **The migration itself.** `sb-268w`, per clause 7.
- **Widening the `default:` refusal.** Per clause 9.
- **The record's own typespec appendix is not edited, and neither is the code,
  yet.** Decision 7's list is written out in three other places, and the
  convention the `{:path, opts}` amendment states at `:2871-2877` is read into
  this section unchanged: this member is added to each of them **in the
  reading** rather than in the bytes, and a reader who finds eight values in
  one of them and nine here is looking at that convention rather than at drift.
  Two are code - `field_type/0` (`lib/statifier_blocks/block_type.ex:149-157`)
  and the "eight closed `field_type/0` values" sentence in `config_schema/1`'s
  doc (`:260-262`) - and the code follows the record, so `sb-1jcr` moves both.
  The third is *The contract as typespecs* above, whose `field_type` union
  still lists the original seven (`:448-455`).
- **Anything about the wire format.** Nothing here adds a trace type or moves
  a version; a config field is not a trace event.

### Where the counts stand after this section

`ADR-0005`'s Note of 2026-09-06 closes by saying its decision 9 table "holds
eight rows of a set of nine". The set of nine is this one, and that Note is
the row for the ninth member; the row it says is still owed is `{:path,
opts}`'s, which is that record's debt and not this one's. Sections on `main`
that count the set at eight - `P3` at `:4108-4133`, the Note at `:4934-4941`,
`ADR-0013` decision 1, and the `config_schema/1` doc at `:260-262` - are each
accurate as of the day they were written and are read forward under the
convention above.

Filed with `sb-zvar`, campaign-SF035's Lane A, on ruling `RQ-SF035-1` and
carrying ruling `RQ-SF035-6`. `sb-268w` migrates the two fields; `sb-1jcr`
builds the type; `sb-wzoa` flips this section.

## Note (2026-09-06): G15's `collect` row and the two sentences beside it, read against `ADR-0009`'s dotted-path amendment

A dated Note rather than an amendment, and it edits nothing above this line.
It decides nothing, and it cannot: `ADR-0009` decides `core.map`'s `collect`
grammar, and that record has now decided it differently in its *Amendment
(2026-09-06): decision 4, `collect` admits a dotted datamodel path through the
shared location helper*. This Note records which lines here that amendment made
historical, so that a reader who finds a row above and the code disagreeing is
reading a dated entry rather than making a discovery. The code is `sb-cjou`.

**What the amendment decided.** `collect` accepts a dotted datamodel path, in
exactly the grammar the other three `<assign location="...">` fields this
package writes already accept: `StatifierBlocks.Core.Config.datamodel_path?/1`,
reached through `StatifierBlocks.Core.AssignLocation`. Both of the field's sites
moved - the `validate_config/1` check and the `emit/2` re-check - and the
finding text moved with the rule. A bare lowercase identifier is still a valid
`collect`, because every one of them is already a datamodel path, so the field
refuses nothing it accepted before.

**The row it falsifies.** The Note of 2026-09-06 on G15's `collect` sentence
(`:3734`) carries a per-field table, and its `core.map` row (`:3756`) reads:

| `core.map`'s `collect` | `{:path, %{writes: {:list, :unknown}}}` (`core/map.ex:264`) | `StatifierBlocks.Core.Config.identifier?/1` (`:318`, `:528`) | "must be a bare lowercase identifier, like answers" (`:205`) | `ADR-0009` decision 4 |

Its *Location rule*, *Refusal reads* and *Record that decides the grammar* cells
are historical. Read forward, the row is:

| Field | Declared as | Location rule | Refusal reads | Record that decides the grammar |
|---|---|---|---|---|
| `core.map`'s `collect` | `{:path, %{writes: {:list, :unknown}}}` (`core/map.ex:355`) | `StatifierBlocks.Core.Config.datamodel_path?/1` (`:456-461`, `:682`) | "must be a datamodel path, like cards.answers" (`:256`) | `ADR-0009` decision 4 **as amended 2026-09-06** |

The *Declared as* cell is unchanged in substance; its line number moved only
because `sb-cjou` edited the same file above it. With that row read forward, the
table's four rows carry one location rule and one refusal wording rather than
two of each.

**The two sentences beside it.** Both are that Note's own, and both were true
when written.

- "So the sentence names three wordings where it once named one, and `collect`
  alone keeps the bare-identifier grammar" (`:3758-3759`). The wordings are back
  to one, and `collect` keeps the bare-identifier grammar no longer - it keeps
  the bare-identifier *values*, which is a different claim and the one that
  still holds.
- "**`collect` is now declared a path and refused as an identifier** ...
  Resolving it is an amendment to `ADR-0009` decision 4 ... and nobody has ruled
  it. `sb-h6qt` owns that question, with both directions named on it: widen
  `collect` to a dotted path, or narrow its declaration to match the grammar.
  This record takes neither, and G15 stands as written until that one is ruled"
  (`:3779-3788`). The mismatch it names is gone; the amendment is the one it
  says is owed, taken by the record that owed it, in the widening direction, and
  it folds `sb-h6qt`'s half of the question. What that paragraph asked for has
  happened rather than being still open.

One sentence in the Note before it (`:3727-3729`) - "`core.map`'s `collect`
keeps the bare-identifier wording, because `ADR-0009` decision 4 decides that
field's grammar outright and widening it is that record's amendment to make" -
is half historical for the same reason: its first clause no longer holds, and
its second clause is exactly what happened.

**And one sentence of G15 itself reads better than it did.** G15's prose
(`:3353-3356`) says `validate_config/1` refuses "a `collect` that is present and
not a bare lowercase identifier, refused in the same words `core.invoke` and
`core.subchart` produce for `assign_to`". Its rule clause is historical - the
refusal is now of a value that is not a datamodel path - while its *same words*
clause, which the Note at `:3721-3732` had to weaken to "naming the shape",
is once again true on its own words: the wording under all four fields is the
one sentence again, because the amendment moved `collect`'s message to it. G15
is not edited here, and the weakened reading stays safe to hold: the shape is
shared whether or not the wordings are.

**What does not change.** The writes table of the Note of 2026-09-06 on decision
10 (`:3531`) still reads `collect`, `{:list, :unknown}`: the amendment widened
where the one write may land and said nothing about what it holds. Decision 7's
field-type set gains no member, and `collect`'s declaration is untouched. G15's
four-field census, its `on` default read through `core.parallel`'s G7a shape,
and its "refuses nothing else, and in particular nothing about N" clause are all
unaffected, because only the rule behind one field's refusal moved.

Filed with `sb-ctfg`, campaign SF035's Lane A, from `sb-cjou`'s discovery.

## Note (2026-09-06): the open sentence in section 4 step 3 - a root outcome named `failed` is refused at compile

A dated Note rather than an amendment. It edits nothing above this line, and in
particular it does not touch the failure amendment of this date: section 4's
four steps stand word for word, the shared final is minted where and how step 3
says under both prefixes, and the `<donedata>` it carries is unchanged. What
this Note records is the answer to the one question that amendment left open,
in the bracketed Note inside its own step 3, and what the answer does and does
not reach.

**The open sentence.** The failure amendment of this date left one question
open, in a bracketed Note inside section 4 step 3: `sb-hxs5` mints the one
shared final an unhandled failure below the root reaches from the root block's
id under the role
`<prefix>failed`, and a **root** block declaring an outcome literally named
`failed` would mint the same id for its own completion final. That Note said
the choice between a fallback role and a compile refusal was a decision the
flip it rode on did not take. This Note takes it, and takes it as a refusal.

**The answer.** `failed` is reserved as an outcome name on a **root** block. A
document whose root block declares it is refused at compile, in the `:config`
stage, with a finding against the root block that names the reserved name and
says to rename the outcome. The finding carries the config field the outcome
name came out of where one field answers for it - `core.subchart`'s `outcomes`,
for the type most likely to reach this - and the block anchor where none does,
which is a type whose outcome list is a constant. Ruled `RQ-SF035-16` in
campaign SF035's walk, with the operator present.

**Why a refusal rather than a fallback role.** A fallback would have to rename
one of the two finals, and both names are load-bearing in a way a generated
suffix would spoil. The shared final's role is read by a human looking at the
compiled chart to tell which compile option produced it (step 3's own
reasoning), and the completion final's role is the author's own outcome name,
which is what `done.outcome.<state id>.<outcome>` and the `outcome` `<param>`
carry across the invoke boundary. Renaming either one to `failed_2` buys a
document that compiles and produces a chart nobody can read, in exchange for
allowing one word. The word is worth less than the two readings.

**Why unconditional, rather than only where the collision fires.** Whether the
shared final is emitted at all depends on step 2: a document with no unhandled
failure-classed outcome below its root emits nothing extra, so a conditional
refusal would let a document compile, and then stop compiling after an edit
three blocks down that says nothing about the root's outcome names - reporting
it in a sentence about a block the author was not editing. The name is reserved
on the root instead, where the author wrote it and can act on it.

**Why the root only.** `<prefix>failed` is minted from the root block's id
alone. A block below the root mints its own outcome ids from its own id, so
`failed` there collides with nothing and stays the author's word to use; this
Note reserves nothing below the root.

**What it replaces.** The collision was already refused - by `Statifier`, at
the `:chart` stage, as a duplicate state id, with `fault: :package` - the
class `ADR-0004` decision 9 gives a structural finding, which it calls a bug
in this package or in a host's block type and never the author's doing, and
which `StatifierBlocks.Compiler.Finding`'s own moduledoc spells "a bug in this
package or in a host's block type, and no edit to the document will help".
That was the defect: an author
who had written one word into one field was told the problem was not theirs to
fix. Nothing was ever miscompiled, and nothing about the emitted bytes changes
here. What moves is which stage refuses, whose fault it reports, and which
field it points at.

**What does not change**, beyond the section this Note answers, which the
opening paragraph holds fixed. The outcomes amendment A's rules on what a type
may declare are
untouched - `failed` is still a well-formed outcome name, still a legal role,
and still legal on every block that is not the root of the document being
compiled. Decision 7's field-type set gains no member and no callback is added
or changed. Every document that does not declare this one name at its root
compiles to exactly the bytes it compiled to before, which
`StatifierBlocks.Compiler.ByteCorpusTest` pins against goldens captured before
the amendment rather than against today's output.

The bracketed Note inside step 3 stays where it is: it is the dated record of
the question, and this Note is the dated record of the answer.

Filed with `sb-k0dy`, campaign SF035's Lane A, from `sb-hxs5`'s open question.

## Note (2026-09-06): the payload amendment's second arm is spelled - `payload` is a `{:type_expr, opts}` field and admits an inline shape

A dated Note rather than an amendment, on this record's convention: by
addition, zero removed lines, no `Status:` line of its own, and appended at the
**end of this file** for the reason the Amendment at `:4957` gives about itself
- `ADR-0013` cites this record by line number, and three of the four lines it
names sit inside `P3`. Nothing above this line is edited. The payload amendment
of 2026-09-06 (`:4010`) stands word for word: `P1`'s optional key, `P2`'s
vocabulary, `P4`'s undeclared case and `P5`'s refusal and its depth rule are
each unchanged in every particular.

**What `P3` deferred.** `P2` named two arms for a payload - a declared name and
an inline shape - and `P3` took one: "**No ninth field type is added by it**"
(`:4121-4122`), the inline arm getting "no field type here, and none is
invented for it" (`:4133`). The reason given was not that the arm is unwanted
but that no member of decision 7's set described a shape, and adding one to
spell a shape nothing stored yet would have been a second proposal riding along
with the first. The Amendment of 2026-09-06 at `:4957` is that second proposal,
made on its own: it adds `{:type_expr, opts}` as decision 7's ninth member, its
clause 7 names `payload` in the table of two fields that migrate onto it
(`:5201-5206`), and its clause 8 fixes what a stored string means afterwards
(`:5214-5220`). This Note records the migration for the field, which is the
half of clause 7 that belongs beside `P3`.

**The spelling.** `payload` is declared `{:type_expr, %{arms: [:name,
:inline]}}` (`lib/statifier_blocks/core/on_event.ex:307-308`). The name arm is
a JSON string carrying the name of a `record` or a `shape` the datamodel
document declares, resolved through `StatifierDatamodel.Declarations.fetch/2`
exactly as `P2` and `P5` describe. The inline arm is a JSON list of `"name"` /
`"type"` / `"required?"` objects, read into `{:shape, members}` by
`StatifierBlocks.Environment.inline_shape/1`. The two are told apart by the
stored JSON type alone - a string is never a member list - and no tag key is
read.

**`P5`'s refusal is the same refusal, against the members the other arm
carries.** The check needs one thing: a set of member names the payload
carries, and a rule for descending below the first segment. The arms differ in
where those names come from and in nothing else
(`lib/statifier_blocks/core/on_event.ex:469-497`). The first segment of a
source path is checked against the member names; a deeper segment is checked
only where that member's own type resolves to something whose members are in
hand - another declaration, or another inline shape - and a member typed as a
scalar, an opaque spelling, a list or nothing at all stops the walk and refuses
nothing beyond it (`:526-552`). That is `P5`'s rule kept literally, with one
descent added for the arm `P3` did not have: a member whose type is itself an
inline shape walks its own members.

The anchor, the severity and the count are untouched: one `:config` finding of
severity `:error` on the `"capture"` key, naming the offending pairs in their
destinations' sorted order, whichever arm the payload is in. An inline payload
has no name to print, so the message describes it instead of naming it.

**What an inline payload carrying no well-formed member means.** Every read is
a read past it. That is not a new rule: a `payload` naming a declaration with
no fields already refuses every pair, and the two cases are the same case.

**`P4` is unchanged, and gains no route.** A handler with no `payload` is
unchanged in every respect; a `payload` naming a type the datamodel document
does not declare resolves to nothing and refuses nothing; a compile with no
`:datamodel` at all resolves no declared name. An inline payload needs no
datamodel document to be read, which is not an exception to `P4` but a case
`P4` never reached: it is a declaration that is present rather than one that
fails to resolve.

**One thing moves in the module, and it is a removal.** `validate_config/1` no
longer carries a check of its own for the field. Under `P3` the field was a
`:string` and the callback refused a stored value that was not one; under
`{:type_expr, opts}` what a value may be is
`StatifierBlocks.BlockType.type_expr_findings/2`'s single check for every field
of that type, consulted by the compiler's `:config` stage and by the editor's
view model both, so keeping a clause here would report the same bytes twice on
the same key. Whether the name *resolves* is still no finding on either side,
which is `P4`.

**No stored document changes, and no byte moves.** A `payload` holding text is
the name arm - the same bytes, the same resolution, the same findings - and the
key still reaches no compiled SCXML at all, which `P1` states and
`StatifierBlocks.Core.TypeExprMigrationTest` asserts byte for byte beside the
corpus `StatifierBlocks.Compiler.ByteCorpusTest` pins.

Filed with `sb-268w`, campaign SF035's Lane A.

## Note (2026-09-07): what the flip of decision 7's `{:type_expr, opts}` amendment checked, and its forward sentences met

`sb-wzoa` is the separate gated request the Amendment of 2026-09-06 on
decision 7 (`:4957`) names in its own status paragraph, and it has flipped
that section's `Status:` word from `proposed` to `accepted`. That word is the
only text the flip changes in this record. This Note is by addition, sits at
the **end of this file** for the reason that amendment gives about itself -
`ADR-0013` cites this record by line number and three of the four lines it
names sit inside `P3` - and carries no `Status:` line of its own.

The flip reaches **that section only**. The Note of 2026-09-06 filed with
`sb-jvz3` and the Note of 2026-09-06 filed with `sb-268w` each say in as many
words that they carry no `Status:` line, which is this file's convention for a
Note, and nothing on either is flipped. Every cite below was read off `main` at
`f750b3b`, with `deps/statifier_datamodel` resolved at `0.4.0`.

### What was checked, clause by clause

- **The ninth member is declared.** `field_type/0` lists nine and closes on
  `| {:type_expr, type_expr_opts()}`
  (`lib/statifier_blocks/block_type.ex:152-161`).
- **`opts` carries the two keys clause 2 defines and no third.**
  `type_expr_opts/0` is `optional(:arms) => [:name | :inline, ...]` and
  `optional(:allow_empty?) => boolean()` (`:240-243`).
- **Clause 4's refusal is one shared check with the anchor the clause names.**
  `StatifierBlocks.BlockType.type_expr_findings/2` (`:979-984`) hands every
  field of that type to `type_expr_finding/2` (`:986-997`), which defaults `arms`
  to both and `allow_empty?` to `true`, tells the arms apart by stored JSON
  type alone with no tag key (`stored_arm/2`, `:1028-1037`), and returns a
  `{key, message}` the compile's `:config` stage carries with `config_key: key`
  (`lib/statifier_blocks/compiler.ex:672-681`). No new finding code, no new
  severity, no new option.
- **The two cases clause 4 excludes are excluded.** An undeclared name and a
  compile with no `:datamodel` produce nothing here; the check never resolves a
  name.
- **Clause 6 holds without a clause being added.**
  `StatifierBlocks.BlockType.datamodel_path?/1` is still true for `{:path,
  _opts}` and the literal `datamodel_path?: true` and false otherwise
  (`lib/statifier_blocks/block_type.ex:1084-1086`).
- **Clause 7's two fields migrated, and clause 8's stored string still reads as
  the name arm.** `payload` on `core.on_event` is declared `{:type_expr,
  %{arms: [:name, :inline]}}` (`lib/statifier_blocks/core/on_event.ex:306-312`)
  and `collect_type` is `core.map`'s seventh field
  (`lib/statifier_blocks/core/map.ex:463-469`).
  `StatifierBlocks.Core.TypeExprMigrationTest` asserts the bytes, and
  `ADR-0001`'s `schema_version` did not move.
- **Clause 9's refusal is where the clause says and is not widened.**
  `declaration_findings/2` refuses a `{:path, opts}` field declared without
  `default:` in the `:config` stage
  (`lib/statifier_blocks/compiler.ex:715-726`), and the comment holding the
  widening open for the record still reads "which is the record's call and not
  this stage's" (`:705-707`).

### The sentence that named another record as unmerged, discharged

*What this section does not decide* says of `ADR-0011` decision 1's amendment
that it is "in flight as this section is written and unmerged - cited as the
record that takes the question, not as a record whose text this one has read on
`main`". It merged, as `sb-myt1`, at `0fa760a` and `70f54b2`, before this
record's own section did. The sentence was true when it was written and the
reading it asks for is now available: a reader after both have landed reads
that amendment for the environment's grammar and this section for the field's,
which is what the sentence itself says to do. **That amendment is not accepted
as of this Note** - `sb-wzoa` does not flip it, and the Note of this date at
the foot of `docs/adr/0011-typed-environment.md` says why.

The same paragraph says `StatifierBlocks.Environment`'s `type_expr/0` "has no
inline-shape inhabitant today". It has one from `sb-1jcr` (PR 355, `d804062`):
`String.t() | :unknown | {:list, type_expr()} | {:shape, [member()]}`
(`lib/statifier_blocks/environment.ex:104`). The sentence is dated to its
section and is met rather than falsified - admitting the field type did not
admit the inhabitant, and a separate record did.

### Cites that drifted under the code, repointed

Every line below is a census taken on `f750b3b`, dated to this Note and to be
re-counted by a later reader rather than trusted.

| Written in the amendment | Reads today |
|---|---|
| `lib/statifier_blocks/core/on_event.ex:287-292` | `:306-312`, and no longer `:string` |
| `lib/statifier_blocks/environment.ex:93` | `:104` |
| `lib/statifier_blocks/block_type.ex:149-157` (`field_type/0`) | `:152-161` |
| `lib/statifier_blocks/block_type.ex:260-262` ("eight closed `field_type/0` values") | `:300`, and it reads **nine** |
| `lib/statifier_blocks/block_type.ex:760-762` (`datamodel_path?/1`) | `:1084-1086` |
| `lib/statifier_blocks/compiler.ex:604-611` | `:705-707` |
| `lib/statifier_blocks/compiler.ex:619-637` | `:715-726` |

*Where the counts stand after this section* said the `config_schema/1` doc
sentence counting the set at eight was "accurate as of the day it was written"
and read forward under the amendment's own convention. `sb-1jcr` moved it, so
it now counts nine and the convention has nothing left to carry there. The
third place the union is written out - *The contract as typespecs* above - still
lists the original seven, which that section also says, and it is not edited
here.

Filed with `sb-wzoa`, campaign SF035's Lane A.

## Amendment (2026-09-07): decision 7, optional `hidden?` and `readonly?` keys, and the missing-`default:` refusal widened to every field type

**Status: accepted (2026-09-07).** Drafted for `sb-s0jt` under the operator's campaign-SF036
grant, recording that campaign's ruling `RQ-SF036-3` and the two record
questions carried on `sb-btx0`, and merging at proposed under that campaign's
invariant like every other section filed with it; flipping it to accepted is a
separate gated request, and `sb-xnxw` carries it. Additive: decision 7 and
every amendment and Note it has taken - `value_path` (2026-08-27),
`datamodel_path?` (`:1004`), `sensitive?` (`:1187`), the `{:path, opts}`
amendment at `:2761`, the Note that gave `opts` its first two keys at `:3456`
and the `{:type_expr, opts}` amendment at `:4957` - all stand exactly as
written, no text above this line is edited by this section, and the closed
field-type set gains no member.

It is an amendment rather than a dated Note because it adds two keys to
`field_decl/0` and widens a compile refusal, which is what decision 7 says
rather than a reading of it; the `datamodel_path?` section at `:1004` is the
precedent, and it took the same shape for the same reason - one optional
boolean on the field declaration, defaulting to today's behaviour when absent,
with the editor and the compiler reading it and nothing else changing.

It is appended at the **end of this file** rather than beside decision 7, for
the reason the `{:type_expr, opts}` amendment at `:4957` gives about itself:
other records on `main` cite this one by line number, and an insert above any
of them would leave those citations pointing at the wrong text.

### Context: the key that is informative but not editable has no spelling

Decision 7 (`:180-186`) makes every field of `config_schema/1` an input: "each
with a key, a field type, a label, a `required?` flag, and a default". A block
type whose config carries keys the runtime supplies - an identifier of the run,
of the tenant, of the chart, the invoke-step shape a production embedder puts on
every host call - renders them as author-editable expression fields, because
that is the only thing a declared field can be. There is no way for a type to
say "this key is part of my config, the compiler and the Source tab must see it,
and no form may offer it to an author", and no way to say "show this, do not let
it be typed into".

The two shapes are different, and the difference is not cosmetic. One is about
whether a value reaches a form at all; the other is about whether the form draws
an input or a value. So they are two keys, not one enum.

### F1. `field_decl/0` gains `hidden?` and `readonly?`, both optional booleans

`field_decl/0` reads today (`lib/statifier_blocks/block_type.ex:251-259`,
read on `b71740c`):

```elixir
@type field_decl :: %{
        required(:key) => String.t(),
        required(:type) => field_type(),
        required(:label) => String.t(),
        required(:required?) => boolean(),
        required(:default) => Block.json(),
        optional(:value_path) => value_path(),
        optional(:datamodel_path?) => boolean()
      }
```

It gains two entries, and only two:

```elixir
        optional(:hidden?) => boolean(),
        optional(:readonly?) => boolean()
```

- **`hidden?: true`** - **never rendered by any form.** No label, no input, no
  row. The value is the field's `default:`, or whatever a host wrote into the
  config, and the compiler and the Source tab see it entirely unchanged: this is
  a rendering claim and nothing else. A hidden field is still a declared field -
  it appears in `config_schema/1`'s list, `validate_config/1` remains the
  authority over its value (decision 7), and a `:config` finding on its key
  routes exactly as it does today.
- **`readonly?: true`** - **rendered as its value beside the label, never as an
  input.** The row is drawn, the label is drawn, and where a control would sit
  the form draws the value. It is not a disabled input and not a
  `readonly` attribute on one: an author can neither type into it nor post it.

Both default to `false` when the key is absent, on the `required?: boolean()`
convention decision 7 and the `datamodel_path?` amendment both take. A
declaration carrying neither key behaves exactly as it does today.

The two are independent booleans rather than one three-valued key because they
answer different questions and a later record may want a third answer to either.
Declaring both `true` on one field is not refused; `hidden?` wins, because a
field that is not rendered has nothing to render as a value.

### F2. The existing rule: `field_decl/0` already requires `default:`

This is not new and this section does not change it. `field_decl/0` reads
`required(:default) => Block.json()` (`block_type.ex:256`): a declaration
without `default:` has never been a well-formed declaration under this record.

What is new is only how far that requirement is *enforced*. Today exactly one
arm is checked at compile - `declaration_findings/2` filters
`path_field_without_default?/1` (`lib/statifier_blocks/compiler.ex:719` and
`:727-731`), which matches `%{type: {:path, _opts}}` and nothing else - and the
comment above it (`:700-707`) says why, and says whose call the rest is:

> Widening the refusal to all field types is a change to what a block type may
> declare, which is the record's call and not this stage's.

This amendment is that record, and it takes the call.

### F3. The missing-`default:` refusal widens to every field type

**A field declaration without a `default:` key is refused at compile, whatever
its field type.** Not the `{:path, opts}` arm alone: `:string`, `:integer`,
`:boolean`, `{:select, choices}`, `:expression`, `:duration`, `{:list, inner}`,
`{:path, opts}` and `{:type_expr, opts}` alike - the nine members
`field_type/0` carries on `main` (`block_type.ex:152-161`).

The finding is a `:config` finding, per *block* rather than per type, with the
same shape and the same routing the `{:path, opts}` refusal already produces
(`sb-8mki`, campaign SF035): `config_schema/1` takes the block's config, so two
blocks of one type can differ, and anchoring on each block sends a reader to a
card they can see.

The reasoning the narrow refusal rested on generalises. A `default:` is what the
editor puts in an unset control and what a read of the value falls back to; a
declaration missing it makes the view model read the key permissively and render
`nil`, which is a value the block type never said was legal. Under decision 7
`validate_config/1` is the authority over a *value*, and a missing `default:` is
not a value - it is a defect in the declaration, which no `validate_config/1`
can see. Refusing it at compile is the only place it can be caught.

### F4. A hidden field whose `default:` is its type's empty value is refused

`hidden?: true` puts the field beyond every form. Its `default:` is therefore
the only value it will ever have unless a host writes the key itself, and a
`default:` that is the type's *empty* value declares a key that carries nothing
and can never be given anything. **That is refused at declaration**, as a
compile-time `:config` finding - the same door F3 walks through, and the same
door the missing `{:path, opts}` default already takes.

The claim is scoped to nine field types, so the empty value is stated per type
rather than left to a reader:

| Field type | Empty value refused under `hidden?: true` |
|---|---|
| `:string` | `""` |
| `:integer` | `""` - an empty control posts `""`, and `Editor.Field.decode/2` hands `raw` back unchanged when `Integer.parse/1` does not consume the whole string (`editor/field.ex:991-996`, the `_other -> raw` clause at `:994`), so the stored value is the empty string rather than a number |
| `:boolean` | *none* - `false` is a value; a hidden boolean defaulting to `false` is legal |
| `{:select, choices}` | `""` (no choice) |
| `:expression` | `""` |
| `:duration` | `""` - and it is the one type whose empty value omits its key entirely (ADR-0005 decision 9, amended 2026-08-29; `omitted?/2` at `editor/config_form.ex:412`) |
| `{:list, inner}` | `[]` |
| `{:path, opts}` | `""` |
| `{:type_expr, opts}` | `""`, `null`, or a missing key (the "nothing at all" arm the 2026-09-06 `{:type_expr, opts}` amendment names) |

`:boolean` is the one row with no refusal, and it is deliberate: `false` is a
decided value rather than an absence, so a hidden `false` is a hidden fact, not
an empty key. Every other row's empty value is indistinguishable from "the
author has not filled this in", and a hidden field has no author.

A **`readonly?: true`** field takes no such refusal. It is rendered, so an empty
value is visible, and a host that wants to show "not set" beside a label is
doing something coherent.

### F5. The finding's `fault` is `:author`, and the misattribution is accepted

`Finding.fault/2` (`lib/statifier_blocks/compiler/finding.ex:190-196`) reads:

```elixir
defp fault(stage, _config_key) when stage in [:config, :structure], do: :author
```

so every `:config` finding is the author's by construction, and the fault
vocabulary is `:package | :author`. Both refusals above are `:config` findings
about a **declaration**, which is the block type's text and not the document
author's, so both are attributed to the party who did not write them.

**This section accepts the misattribution rather than widening the vocabulary or
the classifier**, for two reasons. The first is that `fault` answers "who can
act on this", and in the deployment these records are written for the author of
a document and the host that declares its block types reach the same operator
through the same editor; a `:package` value would route nowhere different. The
second is that making `:config` conditionally `:package` means `fault/2` must
learn which `:config` findings name a declaration and which name a value, which
is a second classification of findings that must agree with the first - the
failure mode decision 7 refuses schemas for. A finding's *message* already says
plainly that a field is declared wrongly, which is what a reader acts on.

If a later record needs the distinction machine-readable, the door is a new
`stage` rather than a new `fault` - and this section does not open it.

### F6. Keeping a hidden value needs no decoder change, and that is a property

`ConfigForm.decode/3` (`lib/statifier_blocks/editor/config_form.ex:319`) needs
no change to **keep** a hidden or readonly value, because the behaviour both
require is one of the three properties that function already documents as "a bug
if it is missing" (`:272`, `:284`):

> **A field whose control did not post keeps the value it had.** A partially
> rendered form does not blank out the fields it did not show.

It is implemented in the decode reduce as `:error -> field.value` (`:327`): a
schema field whose key is absent from the posted params keeps the value the base
config carried. A hidden field is exactly a field whose control did not post,
and a readonly field is exactly a field whose control posted nothing to decode.
So the value both keys need preserved is preserved already, and **no decoder
change is a design change**: a decode that dropped a hidden value would be a
regression against a documented property, not a decision this record takes.

The `base` property holds the same way: the decode starts from the config the
block already carries, so a key no form drew is never deleted.

One gap the existing properties do **not** close, stated here so the
implementing bead does not miss it. The decode is keyed off the *schema*, and a
hidden field is in the schema - so a payload that posts under a hidden field's
key would be decoded through it even though no form ever offered that control.
**A `hidden?: true` or `readonly?: true` field ignores any posted value for its
key**: the decode takes the `:error` branch for it unconditionally rather than
reading `params`. That is a decode change, and it is the only one: it defends a
key the form withheld, and it does not touch the three documented properties.

This paragraph states a rule beyond the ruling the rest of this section records,
and it is ruled in its own right: campaign-SF036 ruling `RQ-SF036-15`,
2026-09-07, adds to `RQ-SF036-3` that a `hidden?: true` or `readonly?: true`
field ignores any posted value for its key and that the decoder takes the
unposted branch for a flagged field unconditionally.

### F7. `ViewModel.Field` carries both flags

`ViewModel.Field` (`lib/statifier_blocks/view_model.ex:174`, `@type t` at
`:186-195`, `defstruct` at `:198`) gains `hidden?: boolean()` and `readonly?:
boolean()`, defaulting to `false` and not in `@enforce_keys` - the same posture
`value_path` takes there.

They are on the view model rather than only inside the package's own form
component because the view model is what a host reads to draw its own surface.
A host that filters its view by these flags filters the same way the package's
config form does, from the same two booleans, and never has to re-derive them
from a block type module.

### F8. `sensitive?` is not touched, and is not a `field_decl/0` key

`sensitive?` (the amendment of 2026-08-29 at `:1187`) is a key on a **datamodel
declaration**, not on a field declaration: it lives on
`StatifierBlocks.Datamodel`'s declaration struct (`lib/statifier_blocks/datamodel.ex:226`)
and says a declared datamodel path holds a secret. `hidden?` and `readonly?` say
what a form does with a config field. Nothing here reads, sets, or overrides
`sensitive?`, and neither key implies the other - a hidden field is not thereby
sensitive, and a sensitive path is not thereby hidden.

### F9. Worked example

A signup block type whose config carries a seed the host assigns and a step name
the host owns:

```elixir
@impl StatifierBlocks.BlockType
def config_schema(_config) do
  [
    %{
      key: "step_name",
      type: :string,
      label: "Step",
      required?: true,
      default: "Collect email",
      readonly?: true
    },
    %{
      key: "variant_seed",
      type: :string,
      label: "Variant seed",
      required?: false,
      default: "control",
      hidden?: true
    }
  ]
end
```

The config form draws one row: `Step` with the text `Collect email` beside the
label and no input. `variant_seed` is drawn nowhere, and the compiler, the
Source tab and `validate_config/1` all see `config["variant_seed"]` exactly as
the document holds it. Declaring `variant_seed` with `default: ""` would be
refused under F4; omitting `default:` altogether would be refused under F3.

### What this amendment does not decide

- **No new field type**, and no member added to the closed set of nine. Both
  keys are orthogonal to type.
- **Nothing about `required?` on a hidden field.** `required?: true` beside
  `hidden?: true` is not refused here; F4 already guarantees the field carries a
  non-empty default, which is what `required?` asks for at the form.
- **No host-view policy.** F7 puts the flags where a host can read them; what a
  host does with them is the host's.
- **No secrets claim.** `hidden?` is a rendering claim; it is not a security
  boundary, and F8 says where that lives.

### Implementing beads

`sb-21gm` implements F1, F3, F4, F6, F7 and the rendering half of F1's
`readonly?` clause, from this section as merged. `sb-btx0`'s two record questions -
whether a `:config` finding for a declaration defect may be `:package`, and
whether the missing-`default:` refusal widens beyond `{:path, opts}` - are
answered here by F5 and F3 respectively, and land in the same pair. `sb-xnxw`
flips this section to accepted after `sb-21gm` lands.

Cites above were read on `b71740c` and are to be re-counted by a later reader
rather than trusted.

## Amendment (2026-09-07): decision 5, an optional `sentence/1`, and the one refusal set a sentence sits outside

**Status: accepted (2026-09-07, campaign SF036, bead `sb-hlut`, on ruling
`RQ-SF036-4`).** A decision record merges at proposed under campaign SF036's
invariant; flipping this section's status line to accepted is a separate gated
request (`sb-xnxw`, after `sb-w37s` lands the callback). Additive: decision 5's
table at `:109-121`, its closing paragraph at `:130-138`, amendment B3 at
`:831` and every clause above this line stand exactly as written, and no text
above this line is edited by this section. Nothing here is built yet -
`sb-w37s` is the request that builds it.

Every code cite below is a reading of `main` at `b08c99a`, dated to this
section and to be re-read rather than trusted.

### Why this is an amendment and not a Note

Three optional callbacks have arrived since decision 5 was accepted, and two
of the three were recorded as dated Notes rather than as amendments:
`failure_outcomes/1` at `:3832` and `donedata_type/1` at `:4858`. The Note at
`:4858` states the test it applied in as many words - `donedata_type/1`
"decides nothing this record owns", so it is additive to decision 5 rather
than a change to it - and contrasts itself with amendment H at `:1751`, which
recorded the optional `summary/1` as an **amendment** because it also decided
what a core card's second line says.

`sentence/1` falls on amendment H's side of that test, for two reasons this
record owns and neither of the two Notes had:

1. **It is a carve-out from B3.** `:831`'s normalizer semantics - refuse, do
   not truncate - are this record's, and `ADR-0005`'s `10o` says so
   explicitly ("`ADR-0002` keeps ownership of the semantics"). This section
   places a new executable return **outside** the length arm of that refusal
   set while keeping the rest of it. Narrowing the reach of a rule this record
   states is a decision this record takes, not a catch-up entry.
2. **It changes what `use StatifierBlocks.BlockType` injects.** The injected
   default set at `lib/statifier_blocks/block_type.ex:107-145` is decision 5's
   degradation promise in code; adding a member to it is an edit to that
   promise's surface.

So: an amendment, with a status line, and `sb-xnxw` has a line to flip.

### The gap

`ADR-0005` decision 10's `10n` (`docs/adr/0005-liveview-editor.md:2480-2487`)
caps `badge` and the `join_label` return at 24 characters, and gives its reason
at `:2484-2485`, where the number is "the spike's" and the thing it is chosen
to exclude is named:

> The value is the spike's, chosen so that "calls the host" and "timer" fit and
> a sentence does not

`10o` at `:2489-2497` adopts B3's discipline over them - refuse, never
truncate.

That is the right rule for a chip. It leaves the package with no surface at
all for the other thing an author reads: **a block as one line of prose.**
"Wait 30 seconds" is not a chip and never will be; it is a sentence, and every
consumer that wants to render a document as a vertical list of lines - a host
list view, an outline pane, a diff, a test that asserts what a document says -
today has to assemble one out of a title, a type label and a list of capped
chips, each host differently.

### The callback

`StatifierBlocks.BlockType` declares

```elixir
@callback sentence(Block.config()) :: String.t()
```

optional. It joins `io/1`, `migrate_config/2`, `fixtures/0`,
`palette_entry/0`, `outcomes/1`, `failure_outcomes/1`, `summary/1` and
`donedata_type/1` in `@optional_callbacks` (`block_type.ex:710-717`, eight
members today, nine with this one). By the count the Note at `:4858`
establishes - twelve callbacks declared on the module, `donedata_type/1` the
thirteenth - `sentence/1` is the **fourteenth**. That count is stated here for
the reason `:4858` states its own: decision 5's table reads "nine callbacks"
and lists nine, and has done since before that Note, which is also why nothing
above this line is edited to correct it. A reader wanting the live surface
reads `@optional_callbacks` and the `@callback` list; a reader wanting what
decision 5 contracted reads the table.

It carries the same three rules `summary/1` (`block_type.ex:650-652`) and
`donedata_type/1` (`:701-702`) carry, in the same words: it is a **pure
function of `config`**, it is **total** for any config `validate_config/1`
accepts, and it **never raises**. Purity is decision 4's
and is not relaxed here - a sentence is assembled out of `config` and nothing
else, so a callback reaching for a datamodel, a clock or a process is outside
the contract exactly as `join_label` is.

### What the reader answers, per case

The reader is `StatifierBlocks.BlockType.sentence/2`, a palette entry plus a
config, resolved the way `join_label/2` resolves at `block_type.ex:1389-1397`.
The claim below is scoped to four declaration states, so it carries a table
rather than a sentence:

| The type's `sentence/1` | The reader answers | Does the 24-character cap apply |
|---|---|---|
| declared, returns a single-line binary | that binary, verbatim | **no** - see the carve-out below |
| not declared | the type's label | not reached |
| declared, raises / throws / exits | the type's label | not reached |
| declared, returns a non-binary, a blank binary, or a binary carrying a newline, carriage return or tab | the type's label | not reached |

"The type's label" is `palette_entry()`'s `label`, and for a type that
declares no `palette_entry/0` it is the type name - which is decision 5's own
last sentence at `:138` ("no `palette_entry/0` means the editor falls back to
the type name"), unchanged and not extended. The **view model's** three-way
resolution, which puts an author's `title` config into this chain, is
`ADR-0005` decision 10's and is written in that record's amendment of this
date; nothing about it is decided here.

**The rescue is `join_label`'s, exactly.** `call_join_label/2` at
`block_type.ex:1653-1661` rescues a raise and catches a throw and an exit, and
the comment above it at `:1651-1652` states what comes back: "The rescued value is never inspected:
what comes back is the editor's own word either way." A `sentence/1` that
breaks its own never-raises rule is bounded the same way and answers the same
kind of thing - the package's own word for the type, which is the label. B3's
authorization at `:831` is for exactly this: a callback that raises degrades
to the default.

Row 3 has a consequence worth stating rather than leaving to be discovered: a
type that **declares** `sentence/1` and raises inside it lands on the label,
while a type that declares **nothing** may land on an author's `title` first
(`ADR-0005`'s chain). That is deliberate. A bounded rescue's answer is the
package's own word by B3's discipline; it is not an entry into a fallback
chain that a host callback can trigger by raising, because a chain a callback
can steer is a chain a callback can be written against.

### The carve-out: no cap

`chip/1` (`block_type.ex:1666-1673`) and the `chip_refusal/1` it is defined in
terms of (`:1678-1688`) refuse four things:
a non-string, a blank string, a string carrying a newline, carriage return or
tab, and a string longer than `@presentation_cap` (`:1229`, 24). A sentence is
refused for the first three and **not** the fourth.

The reason is `10n`'s own: the cap exists so that a chip is a chip, and `10n`
names "a sentence" as the thing 24 characters deliberately excludes. Applying
the number to the return whose whole purpose is to be the thing the number was
chosen to exclude would refuse every sentence the callback exists to carry.
The other three arms stay, because a sentence is **a line**: a return carrying
a newline is drawn on one line by a list view either way, and refusing it is
how the package avoids picking a collapse rule; a blank one says nothing that
the label does not say better.

**Chips are unchanged by this section.** `summary/1`, `badge`, the
`join_label` return, `@presentation_cap`, `chip/1`, `chip_refusal/1`,
`summary_refusals/2` and `ADR-0005`'s `10n`, `10o`, `10p`, `10q`, `10r` and
`10w` all keep every word they have. A block type may declare `summary/1` and
`sentence/1` and they answer two different questions; a block type may declare
either alone.

### What `use` injects

`use StatifierBlocks.BlockType` (`block_type.ex:107-145`) gains

```elixir
@impl StatifierBlocks.BlockType
def sentence(config), do: ...the type's own label...
```

alongside the six defaults it injects today, added to `defoverridable`
(`:138-143`) with them. The injected body answers `palette_entry()[:label]`
where the module exports `palette_entry/0`, which is the only label a module
holds: a block type module does not know the type **name** the document stores
it under, so the type-name arm of `:138` is the reader's and stays the
reader's. A module that `use`s the behaviour, declares a `palette_entry/0` and
declares nothing else therefore answers its own label and is indistinguishable
from a module that declares no `sentence/1` at all - which is the point. The
injection is for the type that wants to override one default among many, not a
new degradation path.

Sixteen of the seventeen shipped `core.*` types declare
`@behaviour StatifierBlocks.BlockType` directly rather than `use`-ing it
(`lib/statifier_blocks/core/wait.ex:25` is the shape), so the injection does
not reach them and each declares its own sentence or does not. The exception
is `core.placeholder` (`lib/statifier_blocks/core/placeholder.ex:56`), the one
core type that `use`s the behaviour - its moduledoc at `:16` says why ("Every
callback but three is the default `use StatifierBlocks.BlockType`") - so it
answers its own palette label from the injected default unless `sb-w37s`
overrides it, which for a placeholder is the right answer either way.

### Worked example

Two sentences, in the canonical registers, to show the shape and nothing more:

| Type | `config` | `sentence/1` answers |
|---|---|---|
| `core.wait` | `%{"duration" => "30s"}` | `"Wait 30 seconds"` |
| `core.branch` | one arm on slot `"approved"`, labelled `Approved` | `"Decide: Approved, otherwise"` |

Both are longer than 24 characters, which is the carve-out doing its work.
Neither is settled here: **the sentence every shipped `core.*` type answers is
`sb-w37s`'s to fix**, together with the exact wording, and this section names
two only to show that a sentence is a line and a chip is not.

### What this section does not decide

- **No new required callback**, and no row of decision 5's table changes.
  `sentence/1` is optional and degrades to the label, which is what every
  optional callback in that table's closing paragraph does.
- **Nothing about the card.** What a block's card draws is `ADR-0005`'s;
  `RQ-SF036-4` rules that an author's `title` still wins there, and this
  section neither states nor weakens that.
- **No cap of its own.** A sentence has no maximum length here. If one is ever
  wanted it is `ADR-0005` decision 10's to carry, by `10n`'s own argument
  about where a presentation number lives.
- **Nothing about a locale.** The return is a string the type produced; this
  record has no translation seam and does not open one.
- **No compiler reach.** `sentence/1` is presentation. Nothing in `emit/2`,
  the emission, the routing table or any compiled byte reads it.
- **It edits nothing.** Decision 5, decision 4, amendment B3, amendment H and
  the Notes at `:3832` and `:4858` stand as written; this section is additive
  and sits at the foot of the record so no line a sibling record cites moves.

### Implementing and flipping beads

`sb-w37s` builds the callback, the `use` default, the reader and the core
types' sentences, from this section as merged. `sb-xnxw` flips **this
section's status line** to accepted after `sb-w37s` lands.

Filed with `sb-hlut`, campaign SF036, on ruling `RQ-SF036-4`.

## Note (2026-09-07): the field-flags and `sentence/1` amendments are flipped to accepted, with five claims corrected and their code cites re-counted

The Amendment of 2026-09-07 on decision 7 (`:5644`, the optional `hidden?` and
`readonly?` keys and the widened missing-`default:` refusal) and the Amendment
of 2026-09-07 on decision 5 (`:5948`, the optional `sentence/1`) both read
`Status: accepted` from this date. `sb-xnxw` is the separate gated request
both sections' own status paragraphs name, and this Note is what the flip
checked and what it corrects.

It is by addition, sits at the **foot** of this record so that no line a
sibling record cites moves, edits no clause, and carries no `Status:` line of
its own. The only lines the request removes in this file are the two the
status words sit on - the shape `sb-wzoa`'s flip at `ADR-0011:1186` and
`sb-9paa`'s at `ADR-0011:1846` both took. No marker is inserted beside either
status paragraph: inserting one mid-file is what this campaign's
append-at-the-end rule exists to prevent, and every forward sentence those
paragraphs carry is met here instead, where it stands.

### What was implemented, and where the flip read it

| Section | Implementing request | On `main` at | Read for this flip at |
|---|---|---|---|
| decision 7, `hidden?` / `readonly?` (`:5644`) | `sb-21gm`, PR 375 | `09d048b` | `8abc655` |
| decision 5, `sentence/1` (`:5948`) | `sb-w37s`, PR 377 | `ea2fdee` | `8abc655` |

The forward sentences both status paragraphs carry are met by those two
requests: "`sb-21gm` implements F1, F3, F4, F6, F7 and the rendering half of
F1's `readonly?` clause" and "`sb-btx0`'s two record questions [...] land in
the same pair" are met at `09d048b`; "Nothing here is built yet - `sb-w37s` is
the request that builds it" and "`sb-w37s` builds the callback, the `use`
default, the reader and the core types' sentences" are met at `ea2fdee`. Both
sections' closing sentence - that `sb-xnxw` flips them after the implementing
bead lands - is met by this request.

### What the flip verified, claim by claim

**Decision 7's amendment.** F1: `t:StatifierBlocks.BlockType.field_decl/0`
(`lib/statifier_blocks/block_type.ex:277-287`) carries `optional(:hidden?) =>
boolean()` (`:285`) and `optional(:readonly?) => boolean()` (`:286`) and
gained nothing else. F3: the missing-`default:` refusal is checked for every
field type - `declaration_finding/1` (`compiler.ex:771-791`) refuses on `not
Map.has_key?(decl, :default)` (`:774`) with no arm on the field type at all.
F4: `hidden_with_empty_default?/1` (`:797-801`) over `empty_default?/2`
(`:803-813`) refuses one empty value per field type, `:boolean` alone having
none (`:806`), matching the section's table row for row; the `{:type_expr,
opts}` row's third case, a missing key, is refused by F3's arm rather than
this one, which is the same refusal by the other door. F5 stands untouched:
`fault/2` (`compiler/finding.ex:193-195`) still answers `:author` for every
`:config` finding and no `stage` was added. F6: `posted_value/2`
(`editor/config_form.ex:463-465`) answers `:error` unconditionally for a
`hidden?: true` or a `readonly?: true` field, ahead of the `Map.fetch/2`
clause, and `decode/3`'s reduce turns that into `field.value` (`:374`) - the
fourth documented property, written at `:324-332` and citing `RQ-SF036-15` by
name; the three properties at `:309-322` are unedited. F7: `ViewModel.Field`
carries `hidden?` and `readonly?` in its `@type t` (`view_model.ex:209-210`),
defaulting to `false` in the `defstruct` (`:223-224`) and absent from
`@enforce_keys` (`:214`), which is the posture `value_path` takes there. F8
stands: nothing in the implementation reads, sets or overrides `sensitive?`.

**Decision 5's amendment.** The callback is declared `@callback
sentence(Block.config()) :: String.t()` (`block_type.ex:813`) and optional
(`@optional_callbacks` at `:815-823`, nine members with it, as the section
predicted). The reader is `StatifierBlocks.BlockType.sentence/2`
(`:1551-1559`), answering the declared return through `line/1` and falling to
`label(module)` in the section's other three states; the rescue is
`join_label`'s, `call_sentence/2` (`:1829-1832`) reaching the callback through
the same shape. The carve-out holds: `line/1` (`:1843-1852`) refuses a
non-string, a blank string and one carrying a newline, carriage return or tab
and applies no length arm, while `chip_refusal/1` (`:1885-1894`) keeps all
four including `@presentation_cap` (`:1335`, 24) - so chips are unchanged and
a sentence is uncapped. `use StatifierBlocks.BlockType` (`:109-171`) injects a
`sentence/1` default reading `palette_entry/0`'s `label` (`:148-161`, the
comment above it at `:140-147`) and adds it to `defoverridable` (`:163-169`).
Sixteen shipped `core.*` types still declare `@behaviour
StatifierBlocks.BlockType` directly (`core/wait.ex:25` is the shape) and
`core.placeholder` (`core/placeholder.ex:56`, moduledoc at `:16`) is still the
one that `use`s it.

### Five corrections this Note takes

They are corrections of wording and of cites, not of decisions. Nothing either
section decides moves.

**1. F2's description of the narrow refusal describes the code the amendment
replaced, and its three cites do not resolve at all.** F2 says "Today exactly
one arm is checked at compile - `declaration_findings/2` filters
`path_field_without_default?/1` (`lib/statifier_blocks/compiler.ex` `:719` and
`:727-731`), which matches `%{type: {:path, _opts}}` and nothing else - and
the comment above it (`:700-707`) says why". At `8abc655` there is no
`path_field_without_default?/1` in this repository: `sb-21gm` implemented F3
by replacing it with `declaration_finding/1` (`compiler.ex:771-791`), which
asks about `:default` for every field type, and the comment that said the
widening was the record's call now records that the call was taken
(`:724-763`, `declaration_findings/2` itself at `:764-769`). F2 is a statement
about the state **before** this amendment, and the amendment's own F3 is what
changed it, so it is met rather than falsified - but a reader following its
line numbers today lands nowhere, and the correction is not the uniform `+37`
a rebase alone would have produced. The rest of F2 stands unaltered:
`field_decl/0` has required `:default` from the start, and it still does
(`block_type.ex:282`).

**2. F8 calls `StatifierBlocks.Datamodel`'s `declared_row` a "declaration
struct"; it is a `@type` map.** `declared_row/0` is defined at
`lib/statifier_blocks/datamodel.ex:219-227` as a plain map type with seven
keys, not a `defstruct`, and `sensitive?` is one of them (`:226`, which is the
line F8 cites and it still resolves). F8's decision is unaffected -
`sensitive?` remains a key on a **datamodel** declaration rather than on a
field declaration, and neither key implies the other - and only the word
"struct" is wrong.

**3. F4's `{:type_expr, opts}` row names the wrong arm.** The row reads `the
"nothing at all" arm the 2026-09-06 {:type_expr, opts} amendment names`
(`:5792`). That amendment names it the **absent arm**: "the **absent arm** is
a missing key, `null`, or `""`" (`:5069`). The three values F4's row lists are
exactly that arm's three values, so the row is right about what it refuses and
wrong only about what the earlier section calls it.

**4. The `sentence/1` amendment describes the reader as "a palette entry plus
a config"; it is `(module, config)`.** The section's "What the reader answers,
per case" says "The reader is `StatifierBlocks.BlockType.sentence/2`, a
palette entry plus a config, resolved the way `join_label/2` resolves". A
palette entry carries no module, and the reader must ask a module whether it
exports the callback, so the arity-2 reader is `sentence(module(),
Block.config())` (`block_type.ex:1551`) - the shape `summary/3`
(`block_type.ex:1592-1593`) already takes for the same reason. `join_label/2`
(`:1495-1503`) does take a palette entry, because a join label is declared
**in** the entry rather than as a callback; what `sentence/2` borrows from it
is the bounded rescue and the refusal set, not the argument list. Nothing
about the four-state table changes: each row answers the same thing under the
corrected signature.

**5. "Indistinguishable from a module that declares no `sentence/1`" is true
at the reader and false one level up, and the difference has a cost worth
stating.** The "What `use` injects" section says a module that `use`s the
behaviour, declares a `palette_entry/0` and declares nothing else "answers its
own label and is indistinguishable from a module that declares no `sentence/1`
at all". At the reader that holds: `BlockType.sentence/2` answers the label
either way. But the injected default is a real `def sentence/1` in the module
(`block_type.ex:148-161`), so `function_exported?(module, :sentence, 1)`
answers `true` for it, and `ADR-0005`'s amendment of this date puts a
**separate** `function_exported?/3` question in the chain: `ViewModel`'s
`declares_sentence?/1` (`view_model.ex:1760-1763`) decides between "the
reader's answer" and "the author's `title`, then the label". A `use`-ing type
that overrides nothing therefore counts as **declared** in the view-model
chain, and its `Node.sentence` is its palette label even where the author gave
a `title` - which is the same landing a declared callback that raises takes,
and by `ADR-0005`'s deliberate rule that a bounded rescue answers the
package's own word. The cost is exactly that: a `use`-ing block type that
overrides no `sentence/1` and whose config declares a `label` field lands its
outline line on the type's palette label rather than on the author's title. No
shipped `core.*` type is in that set - `core.placeholder` is the only one that
`use`s the behaviour, and it declares no `label` config field - so the cost is
a host's to meet, and a host meets it by overriding `sentence/1`. Neither
record's decision moves: the injection stays, the chain stays, and this Note
only says where the word "indistinguishable" stops being true.

### Cites re-counted

`sb-21gm` and `sb-w37s` moved code that both sections cite, and both sections
end by saying their cites are to be re-read rather than trusted. The
load-bearing ones read, at `8abc655`:

| Cited as, in the section | Reads today, at `8abc655` |
|---|---|
| `block_type.ex` `:251-259` (`field_decl/0`) | `:277-287`, `required(:default)` at `:282` |
| `block_type.ex` `:152-161` (`field_type/0`, nine members) | `:178-187`, still nine |
| `compiler.ex` `:700-707`, `:719`, `:727-731` | superseded; see correction 1 |
| `finding.ex` `:190-196` (`fault/2`) | `:193-195` |
| `editor/field.ex` `:991-996`, the `_other -> raw` clause at `:994` | `:1026-1032`, the clause at `:1030` |
| `editor/config_form.ex` `:412` (`omitted?/2`) | `:485-486` |
| `editor/config_form.ex` `:319` (`decode/3`), `:272`/`:284`, `:327` | `:366-386`; the three properties `:309-322`; `:error -> field.value` at `:374` |
| `view_model.ex` `:174`, `:186-195`, `:198` (`ViewModel.Field`) | `defmodule Field` `:183`, `@type t` `:201-212`, `@enforce_keys` `:214`, `defstruct` `:215-226` |
| `block_type.ex` `:710-717` (`@optional_callbacks`, eight) | `:815-823`, nine, `sentence: 1` at `:823` |
| `block_type.ex` `:650-652` / `:701-702` (the three rules) | `summary/1` `:718-723`, `donedata_type/1` `:769-771`, `sentence/1` own `:796-803` |
| `block_type.ex` `:1389-1397` (`join_label/2`) | `:1495-1503`, the rescue at `:1814-1822` |
| `block_type.ex` `:1653-1661`, comment `:1651-1652` (`call_join_label/2`) | `:1814-1822`, comment `:1811-1813` |
| `block_type.ex` `:1666-1673` (`chip/1`), `:1678-1688` (`chip_refusal/1`), `:1229` (`@presentation_cap`) | `:1872-1878`, `:1884-1894`, `:1335` |
| `block_type.ex` `:107-145` (`use`), `:138-143` (`defoverridable`) | `:109-171`, `:163-169` |
| `datamodel.ex` `:226` (`sensitive?`) | `:226`, unmoved |
| `core/wait.ex` `:25`, `core/placeholder.ex` `:56` and `:16` | unmoved |

`docs/adr/.cite-baseline.json` is refreshed in this same request, so the
cross-record line citations this campaign moved are recorded as a reviewed
diff rather than found by the next record to be edited.

Filed with `sb-xnxw`, campaign SF036, folding the residue of `sb-p144`
(corrections 1-3) and `sb-xtcp` (corrections 4-5).

## Amendment (2026-09-07): decision 5, `use StatifierBlocks.Composite` - a block type derived from params and a pure subtree

**Status: accepted (2026-09-07, campaign SF037, bead `sb-2gdx`, on epic `R3`'s
settled direction and rulings `RQ-SF037-3`, `RQ-SF037-6` and `RQ-SF037-8`).** A
decision record merges at proposed under campaign SF037's invariant; flipping
this section's status line to accepted is a separate gated request (`sb-v3ny`,
after `sb-xio9` lands the macro). Additive: decision 5's table (`:109-121`) and
its closing paragraph (`:130-138`), decision 7 (`:180-186`), the field-flags
amendment at `:5644` and its F4 table, the `sentence/1` amendment at `:5948`,
and every other clause above this line stand exactly as written, and no text
above this line is edited by this section. Nothing here is built yet -
`sb-xio9` is the request that builds it.

It is appended at the **end of this file** rather than beside decision 5, for
the reason the `{:type_expr, opts}` amendment at `:4957` gives about itself:
other records on `main` cite this one by line number, and an insert above any
of them would leave those citations pointing at the wrong text.

Every code cite below is a reading of `main` at `c77356b`, dated to this
section and to be re-read rather than trusted.

### Why this is an amendment and not a Note

The test the Note at `:4858` applied to `donedata_type/1` - does it decide
anything this record owns - is the test this section fails in two places, the
way amendment H at `:1751` did:

1. **It adds a second `use` macro to the declaration surface decision 5 owns.**
   `use StatifierBlocks.BlockType` (`lib/statifier_blocks/block_type.ex:109`)
   injects a *fixed* answer per callback, and `ADR-0007` is the record of what
   those answers are and why. `use StatifierBlocks.Composite` injects answers
   **derived from a declaration**, which is a different kind of default and a
   change to what "a block type is a behaviour module" means in this package.
2. **It fixes which of the derived answers a declaration may override.** That
   is a narrowing of `ADR-0007`'s "every one is `defoverridable`", and a rule
   this record states is a rule this record narrows.

### The count this section works from

Decision 5's table is titled "nine callbacks, five required" (`:109`).
`ADR-0007`'s Note of 2026-09-06 (`docs/adr/0007-block-type-defaults.md:250`)
recorded that the count had already moved to **twelve**, and it has moved
again: `StatifierBlocks.BlockType` declares **fourteen** `@callback`s on `main`
today - decision 5's nine, plus `outcomes/1` (`:657`), `failure_outcomes/1`
(`:690`), `summary/1` (`:729`), `donedata_type/1` (`:777`) and `sentence/1`
(`:813`) - and five are still required. This section therefore says "the
declaration surface" rather than "the nine", and it answers for every callback
the macro touches and names the ones it does not. The count in decision 5's
heading is left alone; it is the historical count, and correcting it in place
would edit text above this line.

### The declaration

`use StatifierBlocks.Composite` takes two things and nothing else.

**`params`** is a `[field_decl()]` in decision 7's shape -
`t:StatifierBlocks.BlockType.field_decl/0` at `block_type.ex:277-287` - with no
new key and no new field type. Every flag decision 7 and its amendments give a
field is available to a param on the same terms: `required?`, `default:`,
`value_path`, `datamodel_path?`, `sensitive?`, `hidden?` and `readonly?` all
mean here exactly what they mean on any other declared field, and the F3 and F4
refusals at `:5644` apply to a param declaration unchanged. That is the whole
of this package's answer to "a freshly inserted block is not finding-free": a
composite whose declaration says what its params default to lands finding-free,
because its params are ordinary fields and ordinary fields already have that
property.

**The "first option for a required select" convention is declined here.** A
required `{:select, choices}` param does not silently default to `choices`'
first entry. A declaration that wants a default writes one, which is what
every other field in this package does, and F3 already refuses the field that
writes none.

**`subtree/1`** is a **pure** function from the param map to the blocks the
composite stands for: a non-empty list of `t:StatifierBlocks.Block.t/0`
(`lib/statifier_blocks/block.ex:32-38`) of `core.*` and host types, nested
through their own `slots`. Its **head is the expansion root**, and several
derivations below read that block and no other. Pure in decision 4's sense
(`:100-107`): same params in, same subtree out, forever, no I/O, no clock, no
process dictionary. A composite that would need external data at authoring
time gets it the way decision 4 already says a callback does - the host
resolves it before the operation and passes it in - not by `subtree/1`
reaching for it.

### The ids the subtree mints

**The declaration mints the expanded blocks' ids deterministically from the
composite block's own id.** They are not fresh UXIDs and they are not a
counter over the document.

Two properties follow, and they are the acceptance tests for this clause:

- **No `__`.** `ADR-0004` decision 3
  (`docs/adr/0004-compiler-provenance.md:122-150`) derives every generated
  state id as `"s_" <> block_id` or `"s_" <> block_id <> "__" <> role`, and its
  uniqueness argument at `:147-149` rests on a block id containing no `__` -
  "a `blk_`-prefixed UXID contains no `__`, and roles cannot contain `__`". A
  minted id that contained one would break the invertibility that decision's
  `unstate_id/1` promises. So a minted id contains no `__`.
- **Document-unique, for free.** The composite block's own id is
  document-unique, opaque and never reused (`ADR-0001` decision 3). An id
  derived from it by a function that is injective per composite inherits all
  three, per block rather than per document - which is the same property
  `ADR-0004` decision 3 buys for state ids, bought the same way and for the
  same reason: editing one block's config, or inserting a block above it,
  changes the ids of nothing else.

### What the `use` derives

| Callback | The composite's answer | Derived from | Overridable |
|---|---|---|---|
| `config_schema/1` | `params`, in declaration order | the declaration | no |
| `validate_config/1` | the refusals `params` declare, over the composite's config | the declaration | **yes** |
| `slots/1` | `[]` | `RQ-SF037-3` | no |
| `io/1` | see below | the expansion | no |
| `current_version/0` | the version the declaration states | the declaration | no |
| `outcomes/1` | the **expansion root's** `outcomes/1`, over its expanded config | the expansion | no |
| `sentence/1` | the declaration's sentence template rendered over the config; the palette label when the declaration states no template | the declaration | **yes** |
| `palette_entry/0` | the map the declaration states | the declaration | **yes** |
| `emit/2` | generated, and never reached | `RQ-SF037-6` | no |

**Overridable by a declaration: `sentence/1`, `palette_entry/0` and
`validate_config/1`. Those three and no others.** They are the three whose
answers are about *presentation and refusal* rather than about the expansion:
a composite that wants a better sentence, a richer palette entry, or a
cross-param refusal `params` cannot state as a single field's flag is saying
something the subtree does not know. Every other row is a fact about the
subtree, and a declaration that overrode one would be asserting something its
own `subtree/1` contradicts - a second source of truth for the same question,
which is the failure mode decision 7 refuses schemas for.

`migrate_config/2`, `fixtures/0`, `failure_outcomes/1`, `summary/1` and
`donedata_type/1` are **not derived**. `migrate_config/2` keeps `ADR-0007`'s
injected refusal (`block_type.ex:135-139`) unchanged; the other four stay
optional and absent unless the declaration writes them by hand, and each
degrades exactly as decision 5's closing paragraph says an absent optional
callback does.

Two rows need their own paragraph.

**`slots/1` is `[]`, and that is `RQ-SF037-3`.** A composite in this campaign
exposes no slot of its own: an author fills its params, not its children. A
pass-through slot - a composite that lets an author drop blocks into a named
hole in its own subtree - is a later record's, and this one does not open the
door. The cost is real and stated rather than hidden: the "Guarded step" below
cannot let an author put their own block on the error path, and a host that
needs that writes the arrangement out by hand until that record lands.

**`validate_config/1` runs over the params; the members' run at compile.** The
composite's own callback answers only about the config an author filled in.
Every expanded member's `validate_config/1` is run by the compiler against that
member's *expanded* config when the composite is expanded, so a param that
produces an illegal member config is still refused - one level later, and
attributed the way `ADR-0004`'s amendment `sb-nzc1` (*the compiler expands a
composite at the Resolve stage, and a finding inside an expansion is attributed
one level up to the param that produced it*) says it is. That amendment is
cited here by bead and title rather than by line, because it is in flight
beside this one.

**`emit/2` exists and raises.** The behaviour requires `emit/2` and `ADR-0007`
deliberately injects no default for it (`docs/adr/0007-block-type-defaults.md`,
"`emit/2` is deliberately not among them"). The macro therefore generates one,
and it raises if it is ever called, because the compiler expands the composite
at **Resolve** and no composite block survives to **Emit** (`RQ-SF037-6`;
`sb-nzc1`). A generated `emit/2` that quietly emitted an empty state would be
exactly the failure `ADR-0007` refuses to inject a default to avoid: a type
that compiled to nothing looking complete instead of failing.

### What a composite reads and writes, and the one open question

This section states the *decision* and names the *mechanism* as open, because
the mechanism does not exist on `main` and this record does not get to invent
it.

**The decision.** A composite's reads and writes, **as the environment walk
consumes them**, are the **union of its expanded members'**, each taken over
that member's expanded config. A composite is not a hole in the data flow: if
its subtree writes `cards.settlement`, the document after it may read
`cards.settlement`, and a walk that never descends into an expansion must
still say so.

**Why that union is not `io/1`.** It is worth spelling out, because the
obvious reading is wrong. `t:StatifierBlocks.Assignability.io/0`
(`lib/statifier_blocks/assignability.ex:88-93`) has four keys - `kinds`,
`consumes`, `produces`, `slot_accepts` - and **none of them carries a
per-path read or write.** Those come from somewhere else entirely:
`StatifierBlocks.Environment.read_signatures/3` (`environment.ex:361`) is
`field_reads/2` followed by the `consumes` sugar, and `write_signatures/3`
(`:377`) is `field_writes/2`, then the capture pairs, then the `produces`
sugar. `field_reads`/`field_writes` read `config_schema/1`'s `{:path, opts}`
`expects:` and `writes:` declarations (`block_type.ex:215-232`), and a
`:string` field carrying `datamodel_path?: true` counts as a write of
`:unknown` at its path (`block_type.ex:220-221`). `io/1` contributes only
`ADR-0011` decision 6's sugar, through `environment.ex:1070-1080`, and both
sugar keys are **single-valued**: `consumes: T`, not `consumes: [T]`.

So the union above cannot be carried by `io/1` even in principle, and this
section does not pretend it is.

**What the derived `io/1` therefore answers**, per key:

| `io/0` key | The composite's derived answer | Why |
|---|---|---|
| `kinds` | the members' `kinds` concatenated in expansion order, de-duplicated | it is a list, so it holds a union without changing shape |
| `slot_accepts` | `%{}` | the composite declares no slots (`RQ-SF037-3`), so there is no slot name to accept into, and the root's own entry is dropped with the slot it names |
| `consumes` | the **expansion root's**, or absent when the root declares none | single-valued; a union of two members' `consumes` has no shape to go in |
| `produces` | the **expansion root's**, or absent when the root declares none | as above |

Dropping a non-root member's sugar **under-declares** rather than
over-declares, which is the safe direction and the one `ADR-0011` decision 6
already takes: a missing subject path desugars "to nothing at all - not to a
read of `nil`, not to a write at `""`, and not to a finding"
(`docs/adr/0011-typed-environment.md:345-347`),
and decision 5 of that record (`:300`) makes a path the environment does not
hold an `:info` rather than an `:error`. A composite that says less than it
could is quiet; it is never wrong.

**No new arm of the type-expression vocabulary is opened here.**
`RQ-SF037-8` stands: if a union the mechanism computes cannot be expressed in
the arms `sd-ADR-0001` already has, that is a `statifier_datamodel` record
question and the implementing request stops rather than widening the
vocabulary from this package.

**Open question: `RQ-SF037-15`, queued 2026-09-07 for the operator.** *By what
mechanism does a composite expose its expansion's path reads and writes to a
walk that never descends into the expansion?* Three shapes are on the table and
this section picks none of them: (A) an `Environment` arm that computes read
and write signatures over `Composite.expand/2`'s subtree, attributed to the
composite's one position in the document; (B) a derived `config_schema/1` that
re-exports the members' path declarations as `hidden?: true` fields, so the
existing `field_reads`/`field_writes` path answers without a new arm; (C) a new
optional callback on the behaviour. Each buys the decision above and each pays
differently - (A) adds a walker arm and keeps the declaration surface fixed,
(B) adds no code path but puts declarations in a schema that describes no form,
(C) adds a fifteenth callback. **This amendment is proposed with that question
open, and it flips to accepted only once the question is ruled and its ruling
is implemented.** Everything else in this section stands independently of which
shape is chosen: the union is the decision, the mechanism is the open part.

### The derived recipe

The declaration also derives a `StatifierBlocks.Recipe` whose `insert/2`
(`lib/statifier_blocks/recipe.ex:53`) returns exactly **one `:insert` of the
composite block** at the armed target, and whose `palette_entry/0` is the same
map the block type's is. One command, not the expansion: what an author puts
down is the composite, and the expansion happens at compile.

It exists for the host that already ships the arrangement as a recipe and is
replacing it with a composite: the recipe name keeps working, the palette
browser draws the same entry, and the document it produces is one block instead
of several. `StatifierBlocks.Palette` keeps types and recipes in **two maps**
(`lib/statifier_blocks/palette.ex:70-75`), for the reason `:90-92` gives -
"the two names are two namespaces" - so a composite registered in both is legal
and draws two entries. **A composite's own palette entry is its `types` entry**;
the derived recipe is a compatibility surface for a host mid-migration, and a
host that registers both is choosing to show two.

### `Composite.expand/2` is the one expansion function

    StatifierBlocks.Composite.expand(block, module) ::
      {[StatifierBlocks.Block.t()], param_map}

`block` is the composite block as the document stores it; `module` is the
composite's own module, which every caller has already resolved through
`StatifierBlocks.Palette.fetch/2` (`palette.ex:408`). The return is the
expanded blocks in document order - **head first, and the head is the expansion
root** - together with `param_map`, which maps each expanded block's id to the
**param key** that produced it, or to `nil` for a block no single param is
responsible for.

**`param_map` is what makes `RQ-SF037-5` implementable.** A finding raised
inside an expansion is reported against the composite block, with the
`config_key` the map names - and with `config_key: nil` when the map says no
param is to blame. An author never sees a finding against a block id they
cannot find in their document.

**One function, three callers, and that is the point of naming it here.** The
compiler reads it at Resolve (`sb-nzc1`), the editor's Expand operation reads
it to replace a composite block with its expansion in the document, and the
derived recipe reads nothing else about the expansion because it inserts the
composite rather than the expansion. Three implementations of "what does this
composite stand for" would be three chances for the compiled chart and the
expanded document to disagree; there is one, so they cannot.

### `nil` is an empty hidden default for every row of F4

Folding `sb-3ejc`. **F4's per-type empty values (`:5782-5792`) are a floor and
not a ceiling: `nil` is refused as the `default:` of a `hidden?: true` field
for every row of that table, not only for the `{:type_expr, opts}` row that
happens to name it (`:5792`).** F4's own reason applies unchanged to every row
- a hidden field's `default:` is the only value it will ever have, and `nil`
carries nothing in exactly the sense an empty string does - and the literal
reading, under which a hidden `:string` declaring `default: nil` is accepted
while a hidden `{:type_expr, opts}` declaring the same is refused, is an
accident of which row's prose enumerated its arms rather than a distinction
anyone decided.

`:boolean` stays the one row whose *type-specific* empty value is `none`, and
that is untouched: `false` is a decided value, so a hidden `false` is a hidden
fact. `nil` is not `false`. A hidden `:boolean` declaring `default: nil` is
refused with every other row.

The code half is `sb-xio9`'s - one clause in the compiler's private
`empty_default?/2`, with a test per row.

### Worked example: "Guarded step"

A host in the card-processing domain calls out and records the failure if the
call comes back on the error path. Written by hand that is two blocks and a
slot; as a composite it is one block with two params.

**The declaration.**

    params:
      %{key: "invoke_type",  type: :string, label: "Call",
        required?: true, default: ""}
      %{key: "failure_path", type: :string, label: "Record the failure at",
        required?: true, default: "", datamodel_path?: true}

    subtree(params):
      core.invoke   id "blk_GS_call"
        config  %{"invoke_type" => params["invoke_type"], "assign_to" => ""}
        slots   %{"on_error" => [
          core.assign  id "blk_GS_guard"
            config  %{"path"  => params["failure_path"],
                      "value" => "failed"}
        ]}

for a composite block whose id is `blk_GS`. `core.invoke` declares exactly one
slot, `on_error`, at `:zero_or_one` (`lib/statifier_blocks/core/invoke.ex:96`),
and `invoke_type` and `assign_to` are two of its three declared config keys
(`:130-153`); `core.assign` declares `path` and `value`
(`lib/statifier_blocks/core/assign.ex:64-75`). The two minted ids are
deterministic in `blk_GS`, contain no `__`, and are document-unique because
`blk_GS` is.

**What the derived block type answers**, for a `blk_GS` whose config is
`%{"invoke_type" => "myapp:authorize", "failure_path" => "cards.authorization.failure"}`:

| Callback | Answer | Where it comes from |
|---|---|---|
| `config_schema/1` | the two params above | the declaration |
| `slots/1` | `[]` | `RQ-SF037-3` - the author cannot put a block on the error path |
| `outcomes/1` | `[{"done", "Done"}, {"error", "Error"}]` | the expansion root's (`core/invoke.ex:114`) |
| `io/1` | `%{kinds: [:step], produces: :unknown}` | `kinds` is `[:step]` merged with `[:step]` (`core/invoke.ex:199-200`, `core/assign.ex:121`); `produces` is the root's `:unknown`; `slot_accepts` is `%{}`, so the root's `%{"on_error" => [:step]}` is dropped with the slot it names |
| `current_version/0` | the declaration's | the declaration |
| `sentence/1` | "Call myapp:authorize, recording failure at cards.authorization.failure" | the declaration's template |
| `emit/2` | raises | no `blk_GS` survives Resolve |

**And what the walk must see, which `io/1` above does not carry.**
`core.assign`'s `path` is a `:string` with `datamodel_path?: true`, which is a
write of `:unknown` at that path (`block_type.ex:220-221`). So the expansion
writes `:unknown` at `cards.authorization.failure`, and a block after `blk_GS`
reading that path must be answered `:info` rather than `:error`. That write is
exactly the union this section decides the composite exposes, and exactly the
thing `RQ-SF037-15` has to pick a mechanism for. It is named here rather than
left in the abstract because it is the smallest composite that has the problem.

### What this section does not decide

- **The mechanism for the reads-and-writes union**: `RQ-SF037-15`, above.
- **A pass-through slot**: `slots/1` is `[]` here by `RQ-SF037-3`, and a
  composite that exposes a slot of its own is a later record's.
- **Whether an expanded block carries a marker in the document**: it does not
  (`RQ-SF037-2`), and `ADR-0001` decision 2 is why. That belongs to `ADR-0004`'s
  amendment `sb-nzc1` and to `ADR-0005`'s, not here.
- **A stateful composite, or a palette entry that is `{module, state}`**: that
  is `RQ-SF037-1` and a separate amendment to this record (`sb-5b7j`).
- **The `Collapse` operation**: a later record's, and no code in this campaign.

Filed with `sb-2gdx`, campaign SF037, folding `sb-3ejc`.

## Amendment (2026-09-07): decisions 1-4, a palette entry may be `{module, state}`, resolved through one call seam, and `Composite.Data` is the stateful composite

**Status: accepted (2026-09-07, campaign SF037, bead `sb-5b7j`, on ruling
`RQ-SF037-1`).** A decision record merges at proposed under campaign SF037's
invariant. This section's status line flips to accepted by `sb-v3ny` **only if
`sb-5xqr` lands in SF037**; if that request does not land, this section stays
at proposed and `sb-v3ny` records that fact as a dated note instead of flipping
it. Additive: decisions 1 (`:58-63`), 2 (`:65-70`), 3 (`:86-88`), 4 (`:97-107`)
and 5 (`:109`), the composite amendment immediately above this line, and every
other clause in this file stand exactly as written, and no text above this line
is edited by this section.

It is appended at the **end of this file**, after the `use
StatifierBlocks.Composite` amendment it builds on, for the reason that
amendment gives about itself: other records on `main` cite this one by line
number, and an insert above any of them would leave those citations pointing at
the wrong text.

Every code cite below is a reading of `main` at `d0af5f0`, dated to this
section and to be re-read rather than trusted. The counts in the census are a
re-count at that commit; where an earlier count differs, this section's number
is the one to work from and the anchor beside it - a function head, not a line
number alone - is how to find the site after the line has moved.

### The question this section answers, and where decision 4 left it open

Decision 4 (`:103-107`) already says what a block type does when it needs
external data at authoring time: the host "resolv[es] it *before* the operation
and pass[es] it in the palette entry's own options, not by the callback
reaching for it", and then says in as many words that "that mechanism is not
specified here". This section specifies it, for the one case that forces it.

The forcing case is a host whose **users** save composites. The amendment above
derives a composite block type from a `params` list and a `subtree/1` function
written at compile time in a `use` block. A host that lets a tenant build a
composite in a browser has no compile step in that loop: what the tenant saved
is a row, and what the palette must carry is that row. The subtree is data, the
params are data, and the block type has to be assembled from them at the moment
the host builds the palette for an operation - which is exactly decision 2's
cadence (`:80-84`), one palette value per editing or compiling operation.

### The entry shape

**`Palette.types` admits `module()` or `{module(), state}`.** One type name
still resolves to one entry; the entry may now carry a term beside the module.

    @type type_ref :: module() | {module(), state :: term()}

    types: %{optional(Block.type_name()) => type_ref()}

`state` is an opaque term to `Palette`: this record fixes that it is *carried*
and *prepended*, and fixes nothing about its shape. `Composite.Data` below is
the one module in this package that declares a shape for its own, and a host's
stateful type declares its own.

**`fetch/2` answers the entry as stored.** Its return widens from `{:ok,
module()}` to `{:ok, type_ref()}`, and it neither normalizes a bare module into
`{module, nil}` nor unwraps a pair into its module. Decision 3's totality
(`:86-88`) and its `{:error, {:unknown_block_type, type_name}}` arm - the one
error arm decision 3 names, and the only one `fetch/2` has
(`palette.ex:405-407`) - are untouched. `resolve/2` widens the same way, to
`{:ok, type_ref(), Block.t()}`, and its three error arms (`palette.ex:517-521`)
are untouched too.

Answering the entry as stored rather than normalizing is what keeps this change
**source-compatible for every host that has one today**: a host matching `{:ok,
module}` on `fetch/2` still matches, because a host that registered no stateful
entry can be handed no pair. The widening is visible only to a host that opted
into it by registering one. A normalizing `fetch/2` would have broken every
such match at once, for the benefit of a case most palettes do not have.

**`registration/0` widens with it**, to `{Block.type_name(), type_ref()}`, so
`from_modules/2` (`palette.ex:311`) takes a stateful entry in the ordered list
a host already writes.

**There is still no `:kind` key on a palette entry**, and none is added here.
The amendment above records why (`Palette` keeps types and recipes in two maps,
`palette.ex:70-75`, for the reason `:90-92` gives); a pair is not a kind tag,
it is one entry that carries a term.

### `Palette.call/4` is the one call seam

    @spec call(type_ref(), atom(), [term()], term()) :: term()
    Palette.call(type_ref, callback, args, default)

`call/4` resolves the entry, decides whether the callback is there, and calls
it: for a bare `module` entry it calls `module.callback(args...)`; for a
`{module, state}` entry it calls `module.callback(state, args...)`, with
`state` **prepended** to the declared argument list. When the callback is not
exported at the arity the entry implies, `call/4` answers `default`.

Three things belong to the seam and to nothing else, and they are why it is one
function rather than a convention:

1. **The arity arithmetic.** A callback declared at arity *n* is exported at
   arity *n + 1* by a stateful module. Every `function_exported?/3` in the
   package asks about a fixed arity today; asking about the wrong one would
   silently answer "not declared" and degrade a stateful type into the absent-
   callback path, which looks exactly like a type that declared nothing.
2. **The absent-callback default**, which is why the seam takes four arguments
   and not three. Nine of the fourteen callbacks are optional, and every call
   site in the package today is written as a probe followed by a fallback -
   `%{}` for an absent `io/1` (`assignability.ex:166-172`), the default
   outcomes for an absent `outcomes/1` (`block_type.ex:855-861`), the type's
   label for an absent `sentence/1` (`block_type.ex:1559-1566`). Folding the
   probe and its fallback into the seam is what makes the arity arithmetic
   unrepeatable, because there is no longer a probe outside the seam to get
   wrong.
3. **The `state`-prepending itself**, which is the whole of what a caller must
   not know.

For one of the five **required** callbacks the default is unreachable - a
module that does not export `emit/2` is not a block type at all - and a caller
passes a value whose appearance would be a bug rather than a degradation. The
seam does not distinguish the two cases; the behaviour's required list already
does.

`Palette.declares?/3` answers the same question without calling, for the two
sites that need declaredness alone rather than a value:
`ViewModel.declares_sentence?/1` (`view_model.ex:1984`) and the editor's
`declares_outcomes?/1` (`editor.ex:2755`). Both feed a *presentation* branch
rather than a fallback value - ADR-0005's three-way chain reads the first, and
the second decides whether a card draws an outcome row at all - so neither can
be expressed as `call/4` with a default. It is one predicate, not a second
seam: `call/4` is written in terms of it.

**The seam is a generalization, not an invention.** `StatifierBlocks.BlockType`
already wraps six of the fourteen callbacks in exactly this shape - **probe,
call, fall back** - in `outcomes/2` (`block_type.ex:855-861`),
`failure_outcomes/2` (`:901-907`), `donedata_type/2` (`:936-942`),
`sentence/2` (`:1560-1566`), the private `declared_chips/2` (`:1795-1802`)
and the private `label/1` (`:1866-1875`). Those six become the seam's **first
callers**: they keep their signatures with `module()` widened to `type_ref()`,
and their bodies lose the probe to `call/4`. They do not become a second seam.

**The rescue is not part of that shape, and it stays where it is.** Four of the
six - `outcomes/2`, `failure_outcomes/2`, `donedata_type/2` and `label/1` -
carry no rescue at all; the two that reach one reach it a level down, in
`call_sentence/2` (`:1838-1846`) and `call_summary/2` (`:1809-1816`). That
asymmetry is deliberate and this section does not disturb it: a rescue is B3's
degradation, about a *callback* that raises, while the seam is about how an
entry is reached. Folding a rescue into `call/4` would quietly give one to
every site that today has none.

**What the seam does not do.** It does not rescue on behalf of a site that does
not rescue today, it does not memoize, and it does not change any callback's
declared arity in the behaviour. `StatifierBlocks.BlockType`'s `@callback`
list is untouched by this section: fourteen callbacks, five required, declared
at the arities the amendment above tabulates. A stateful module implements them
at one higher arity because `use StatifierBlocks.Composite.Data`'s generated
functions take the state; the *behaviour* is unchanged, which is why a stateful
module does not `@behaviour StatifierBlocks.BlockType` and why nothing in the
package may reach one except through the seam.

### The census: every site that goes through the seam

A site is in the census when it calls a callback on a module a palette resolved
- `module.callback(...)` where `module` came from `Palette.fetch/2`,
`Palette.resolve/2`, or a `types` map read. Counted at `d0af5f0`: **38 call
sites in 12 files**, and **17 declaredness probes in 6 files**, of which 15
guard one of those 38 in the same expression and 2 stand alone.

| File | Call sites | Anchors (function head, line at `d0af5f0`) |
|---|---|---|
| `lib/statifier_blocks/block_type.ex` | 7 | `outcomes/2` `:857`, `failure_outcomes/2` `:903`, `donedata_type/2` `:938`, `type_expr_findings/2` `:1096`, `call_summary/2` `:1810`, `call_sentence/2` `:1839`, `label/1` `:1868` |
| `lib/statifier_blocks/compiler.ex` | 6 | `resolve_children/3` `:505`, `config_findings/2` `:704`, `declaration_findings/2` `:767`, `emit/2` `:1432`, `candidate_findings/2` `:2172`, `entries/1` `:2278` |
| `lib/statifier_blocks/palette.ex` | 6 | `manifest/1` `:225`, `ordered_entry/1` `:368`, `new_block/2` `:452` and `:455`, `resolve/2` `:524`, `migrate/3` `:542` |
| `lib/statifier_blocks/view_model.ex` | 6 | `head_of_root/2` `:1416`, `chip_label/2` `:1505`, `config_findings/3` `:1642`, `build_resolved_node/4` `:1691` and `:1701`, `palette_entry_with_defaults/2` `:2146` |
| `lib/statifier_blocks/editor.ex` | 3 | `entry_default_config/1` `:1867`, `fixture_events/1` `:2570`, `draft_findings/3` `:3193` |
| `lib/statifier_blocks/environment.ex` | 3 | `subject_of/1` `:1031`, `io/2` `:1130`, `schema/2` `:1139` |
| `lib/statifier_blocks/assignability.ex` | 2 | `io/2` `:169`, `target_verdicts/4` `:783` |
| `lib/statifier_blocks/slot_validation.ex` | 1 | `block_findings/2` `:80` |
| `lib/statifier_blocks/edit.ex` | 1 | `check_config/3` `:271` |
| `lib/statifier_blocks/edit/targets.ex` | 1 | `full?/4` `:297` |
| `lib/statifier_blocks/datamodel.ex` | 1 | `block_findings/5` `:818` |
| `lib/statifier_blocks/core/deadline_recipe.ex` | 1 | `config/2` `:228` |
| **Total** | **38** | **12 files** |

The 17 probes sit in `block_type.ex` (6: `:856`, `:902`, `:937`, `:1561`,
`:1796`, `:1867`), `environment.ex` (3: `:1030`, `:1129`, `:1138`), `editor.ex`
(3: `:1866`, `:2569`, `:2755`), `view_model.ex` (2: `:1984`, `:2145`),
`palette.ex` (2: `:367`, `:541`) and `assignability.ex` (1: `:168`).

Two counts that are **not** the census, named because both are easy to reach
for and both are wrong:

- **The literal `palette.types` and `Palette.fetch(` reads outside
  `palette.ex`** are six, not thirty-eight: `Editor.probe/2`
  (`editor.ex:1854`), `Editor.draft_findings/3` (`:3192`),
  `Editor.accepted_types/3` (`:3214`), `ViewModel.singleton_specs/2`
  (`view_model.ex:1339`), `ViewModel.palette_groups/1` (`:2175`) and
  `Composite.member_module/1` (`composite.ex:598-603`), plus one `recipes`
  read in `Editor.accepted_recipes/2` (`editor.ex:3247`). The last of those
  fetches from `Palette.core()` rather than the caller's palette, so it can
  meet no stateful entry today; it is listed because it is the same read and
  will meet one the moment it is passed a host palette. Those are
  the sites that must stop assuming a `types` value is a module; they are a
  subset of the problem, and a request that fixed only them would leave 38
  call sites still calling a bare module.
- **`RunPane.component/1` (`editor/run_pane.ex:191-196`) is not in the census.**
  Its `apply(module, name, [&1])` looks like a callback dispatch and is not one:
  the module it applies comes from `Application.get_env(:statifier_blocks,
  :run_pane_module, StatifierUI.Live)`, not from a palette, and the functions
  it probes are LiveView components rather than block-type callbacks. It stays
  as it is.

**A site outside this package is out of scope and stays source-compatible**
for the reason `fetch/2`'s clause gives: a host that registered no stateful
entry is handed none.

### The expansion's own dispatches, now that `Composite` is code

`sb-xio9` landed `use StatifierBlocks.Composite` on `main`
(`lib/statifier_blocks/composite.ex`, `d0af5f0`) while this section was
being written, so `Composite.expand/2` is code rather than a proposal and
this section can say what a stateful entry costs it instead of guessing.

`expand/2` is declared `@spec expand(Block.t(), module())` with an
`is_atom(module)` guard (`composite.ex:368-369`); `composite?/1` is
`is_atom(module)` plus `function_exported?(module, :__composite__, 0)`
(`:341-346`); the declaration is read back through a `__composite__/0` the
macro generates (`:224-225`) at three sites - `recipe_insert/3` (`:455`),
`params_of/2` (`:494`) and `probe_block/2` (`:501`) - and `subtree/1` is
called directly at `:378`.

Three consequences follow from the entry shape and from nothing else:

1. **`expand/2`'s second argument widens to `type_ref()`**, and its
   `is_atom/1` guard becomes the seam's question rather than the caller's.
   It is still the ONE expansion function - `Composite.expand/2`, unrenamed
   and unforked - reached with an entry instead of a bare module.
2. **`__composite__/0` and `subtree/1` are seam calls like any other**, at
   one higher arity for a stateful entry:
   `Palette.call(ref, :__composite__, [], nil)` and
   `Palette.call(ref, :subtree, [params], nil)`. They are **not**
   `StatifierBlocks.BlockType` callbacks, so they are not in the census
   above and the count of 38 does not move; they are in the seam for the
   census's reason, and the implementing request carries them with it.
3. **For `Composite.Data` both answers are the state.**
   `__composite__/0` reads a module attribute the macro wrote at compile
   time, and `Composite.Data` has no such attribute to read: its
   declaration arrives at run time. So its `__composite__(state)` answers
   the decoded `state`, and its `subtree(state, params)` answers the
   template with its placeholders substituted. That is the whole reason the
   declaration **is** the state rather than a pointer to one.

### Where a stateful entry is still visible, and why that is right

The seam makes a stateful entry invisible to a *caller of a callback*. It does
not make it invisible to the places that ask about **identity** rather than
behaviour, and this section decides those explicitly rather than leaving them
to be discovered.

**`Palette.manifest/1` (`:224-229`) and the compiler's `palette_hash/1`
(`compiler.ex:2261-2273`) need no new arm.** The manifest's type entries are
`{name, current_version()}` and carry no module at all; the hash's triples are
`{type_name, module, current_version}`, and for every data composite the module
element is the same one. So both distinguish two data composites **by type name
and version**, and neither distinguishes two *revisions of one declaration
registered under one name at one version*.

That is not a gap this section closes, because the record that owns it already
answers it. `StatifierBlocks.CompilationRecord` states that `palette_hash` "is
a hygiene aid, not a commitment", that it is "**not** a cryptographic
commitment to those modules' behaviour", and that "a host that changes an
`emit/2` without bumping `current_version/0` has moved a compile input without
moving the record; that is a palette-hygiene obligation on the host"
(`lib/statifier_blocks/compilation_record.ex:40-51`). An edited declaration is
that same obligation with a different author. What this section adds is to name
who now carries it: **the declaration's `"version"` is required, and a host that
changes a data composite's `params` or `subtree` bumps it.** A host whose users
edit composites has more occasions to forget than a host whose developers do,
which is exactly why the obligation is written down beside the shape rather
than left in the other record.

**`from_modules/2`'s duplicate-`order` check (`palette.ex:343-373`) needs no
new arm either**, and for a better reason: it compares the `group` and `order`
a `palette_entry/0` returns, so once it reads them through the seam, two data
composites sharing one module are two entries with two answers, and a
collision between them is caught exactly like a collision between two ordinary
types.

It does need the seam, though, and this is the one site where forgetting it
would fail **silently** rather than loudly. `ordered_entry/1` opens with
`is_atom(module) and Code.ensure_loaded?(module)` (`palette.ex:365`), and its
`else` arm is `_no_declared_order -> []`. A `{module, state}` entry fails
`is_atom/1`, so a stateful entry left to that guard does not raise and does not
warn: it drops out of the duplicate-order check and out of every ordering
question downstream of it. That guard is the seam's work, not the caller's, and
the implementing request has a test for it.

### `StatifierBlocks.Composite.Data` and its `state`

**`Composite.Data` is the only stateful module this package ships.** It is the
data-driven half of the amendment above: `use StatifierBlocks.Composite`
derives a block type from a declaration written in Elixir at compile time;
`Composite.Data` derives the same block type from the same declaration written
as **data** at run time. Everything the amendment above decides about a
composite holds here unchanged - `slots/1` is `[]` (`RQ-SF037-3`),
`config_schema/1` is `params`, `emit/2` raises, the expansion root is the
subtree's head, ids are minted deterministically from the composite block's id,
and `Composite.expand/2` is the one expansion function. A data composite is
expanded by the *same* `Composite.expand/2` over the *same* subtree, which is
why it answers the environment walk the same way: `RQ-SF037-15` was ruled on
2026-09-07 - the walk computes a composite's read and write
signatures at its one position through `Environment.read_signatures/3` and
`write_signatures/3` fed with `expand/2`'s subtree and the expanded config, no
descent, no new `type_expr` arm and no fifteenth callback - and that ruling
covers a data composite without a clause of its own.

Its `state` is a **declaration map**, JSON-shaped throughout, because the point
of it is that a host can store it in a column and hand it back:

| Key | Required | Shape |
|---|---|---|
| `"type_name"` | yes | the name the document uses, and the key this entry is registered under |
| `"version"` | yes | a positive integer; `current_version/0` returns it |
| `"params"` | yes | a list of field declarations, JSON-shaped (below) |
| `"subtree"` | yes | a non-empty list of template nodes (below); the head is the expansion root |
| `"palette_entry"` | no | the map `palette_entry/0` returns, with string keys |
| `"sentence"` | no | a template string; `{{key}}` is replaced by the param's value rendered as a string |

**Two of the three overridables have a key here; the third cannot.** The
amendment above lets a `use`-composite declaration override `sentence/1`,
`palette_entry/0` and `validate_config/1`, and no others. The first two are
values, so they are the `"sentence"` and `"palette_entry"` keys above. The
third is a **function**, and a declaration held as data cannot hold one - the
same ground this section gives for the subtree being a template rather than a
`subtree/1`. So a data composite gets `validate_config/1` as `params` alone
refuse it, and a cross-param refusal is one of the two things a host must
still write a `use`-composite module for (the other being a `sentence` that
is not a substitution). That is a cost of the data shape, not an oversight,
and a later record that wants it will need a declared refusal vocabulary
rather than a key.

**`"params"` is decision 7's `field_decl()` in JSON.** Each entry is a map with
string keys: `"key"`, `"type"` (the field type's name as a string), `"label"`,
and whichever of `"required?"`, `"default"`, `"value_path"`,
`"datamodel_path?"`, `"sensitive?"`, `"hidden?"` and `"readonly?"` the
declaration writes. No new key and no new field type is introduced here, and
every refusal decision 7 and its amendments state applies to a param
unchanged - including F3's missing-`default:` refusal and F4's `nil`-is-not-an-
empty-hidden-default clause. `Composite.Data` **decodes** this list into
decision 7 `field_decl()` maps once, when the entry is built, and
`config_schema/1` returns the decoded list; it is not decoded per call, because
decision 4 makes `config_schema/1` pure and a decode that could fail on the
hot path is a callback that can fail.

**Every refusal is at entry-build time, not at call time.** A host builds the
state through `Composite.Data.declaration/1`, which answers `{:ok, state}` or
`{:error, [reason]}`, and registers `{module, state}` only on the `:ok`. That
placement is forced by decision 4 and by decision 3 together: a callback must
be pure and total, and `fetch/2` must not raise, so the last moment a malformed
declaration can be refused is before it is in the palette. `declaration/1` is
not new surface in `RQ-SF035-17`'s sense - it is the function this section's own
decision forces, and without it there is no moment at which a declaration can
be refused at all.

### The subtree template's data shape

A template node is a map with string keys:

    %{
      "type"      => "core.invoke",
      "id_suffix" => "call",
      "config"    => %{"invoke_type" => %{"$param" => "invoke_type"},
                       "assign_to"   => ""},
      "slots"     => %{"on_error" => [ ...nodes... ]}
    }

- **`"type"`** is a `type_name` resolvable in the same palette. It is not
  checked at declaration time - the palette is not built yet - and an
  unresolvable one is the compiler's ordinary unknown-block-type arm on the
  expanded block, which decision 3 already makes total.
- **`"id_suffix"`** matches `~r/\A[a-z0-9]+(_[a-z0-9]+)*\z/` and is unique
  within one declaration. The minted id is the composite block's own id, an
  underscore, and the suffix - so the "Guarded step" example's `blk_GS` mints
  `blk_GS_call`. That pattern is what discharges the amendment above's two
  acceptance properties: it can produce no `__`, so `ADR-0004` decision 3's
  uniqueness argument - "a `blk_`-prefixed UXID contains no `__`, and roles
  cannot contain `__`" (`docs/adr/0004-compiler-provenance.md:147-149`) - and
  the `unstate_id/1` invertibility it buys both hold; and it is injective
  per composite, so document-uniqueness is inherited from the composite
  block's id.
- **`"config"`** is a map of the type's config keys to JSON values.
- **`"slots"`** is optional, defaulting to `%{}`: a slot name to a list of
  nodes.

**The placeholder vocabulary is one arm, and one escape.** A map with exactly
the single key `"$param"`, whose value is a declared param key, is a
placeholder: it is replaced **whole** by that param's value, at that param's
declared type, so a `:boolean` param substitutes a boolean and not the string
`"true"`. A map with exactly the single key `"$literal"` is its value,
unsubstituted - the escape that keeps a config value which genuinely is a
one-key `"$param"` map expressible. Every other JSON value is a literal,
including every other map. A `"$param"` naming an undeclared key is refused by
`declaration/1`.

**Whole-value substitution is the whole vocabulary, and that is a decision, not
an omission.** There is no interpolation of a param into a larger string, no
expression, no conditional, and no default-if-blank. The reason is
`Collapse`. `ADR-0005`'s amendment of this date states the gesture at
proposed (`docs/adr/0005-liveview-editor.md:8692-8710`) and hands this
record the shape it produces: the author "marks which of the arrangement's
config values become params, and the subtree becomes the declaration's
template with those values replaced by the params that stand for them", and
the output is "a declaration in the shape `ADR-0002`'s data-composite
amendment fixes". A lifted config value is a **whole** value, so whole-value
substitution is exactly what that gesture can emit and the arm it needs. A
template arm `Collapse` cannot emit is a shape with no producer in this
package - it would exist only for a declaration written by hand, in a feature
whose whole point is declarations that were not. A host that needs
`"prefix-" <> param` writes two params, or waits for the record that adds an
arm and says which producer emits it.

**`param_map` for a data composite is derived, not declared.** The amendment
above defines `expand/2`'s `param_map` as expanded-block-id to param key or
`nil`. For `Composite.Data`: a node is attributed to param key *K* when the
placeholders in **its own `"config"`**, not its slots' children, name exactly
one distinct param, and to `nil` when they name none or more than one. That is
what makes `RQ-SF037-5`'s attribution mechanical for a declaration nobody
wrote by hand.

### Per-instance module generation is rejected

The obvious alternative is to keep `types` as `name => module` and generate a
module per saved composite - `Module.create/3` over the declaration, registered
under a minted name. It is rejected, on four grounds, each of which is an
existing decision of this record rather than a taste:

1. **It mints atoms a tenant controls.** A module name is an atom and the atom
   table is never collected. A feature whose whole premise is that users save
   composites turns every save into a permanent allocation in a VM that has no
   way to reclaim it. That is a denial of service with the tenant holding the
   trigger.
2. **A generated module is not a value, and decision 2 requires one**
   (`:65-70`). A palette is "a caller-supplied value, not global state" with
   "no `Application` env lookup, no named ETS table, no process registry, and
   no 'register at boot' side effect". The code server is exactly such a
   registry: two palettes that differ would agree about a generated module,
   because there is only one code server and the last writer wins.
3. **It breaks decision 2's multi-tenant ground** (`:76-78`): "a value lets a
   multi-tenant host hold different palettes for different tenants in one VM".
   Two tenants who name a composite the same thing collide on one module name,
   and the repair - a tenant id inside the module name - is the state, moved
   into a global namespace and made irreversible.
4. **It weakens decision 3's totality** (`:86-88`). `fetch/2` returning `{:ok,
   module}` means the caller has a module it can call. A generated module can
   be purged out from under an operation that is already running, so the same
   `{:ok, module}` would no longer carry that meaning, and the failure would
   arrive as a raise inside a callback rather than as decision 3's
   `{:unknown_block_type, ...}` arm or one of `resolve/2`'s other two.

The cost of the chosen shape is real and is stated rather than hidden: every
callback call in the package pays one extra function call, a stack trace from
inside a host callback now shows `Palette.call/4` between the caller and the
callback, and a static reader can no longer see which module a given site
dispatches to. Those are the price of one seam, and they are paid once at the
seam rather than 38 times at the sites.

### Worked example: "Guarded step", saved by a tenant

A tenant in the card-processing domain builds a composite in the host's
editor: call out, and record the failure if the call comes back on the error
path. It is the amendment above's "Guarded step", arriving as a row instead of
as a `use` block - the same subtree, the same two params, and a different
place for the declaration to have come from. That is the point of the example:
nothing downstream of the palette can tell which one it got.

**What the host stores and hands back**, as the `state` of one palette entry:

    %{
      "type_name" => "myapp.guarded_step",
      "version"   => 1,
      "sentence"  => "Call {{invoke_type}}, recording failure at {{failure_path}}",
      "params" => [
        %{"key" => "invoke_type", "type" => "string", "label" => "Call",
          "required?" => true, "default" => ""},
        %{"key" => "failure_path", "type" => "string", "label" => "Record the failure at",
          "required?" => true, "default" => "", "datamodel_path?" => true}
      ],
      "subtree" => [
        %{"type" => "core.invoke", "id_suffix" => "call",
          "config" => %{"invoke_type" => %{"$param" => "invoke_type"},
                        "assign_to" => ""},
          "slots" => %{"on_error" => [
            %{"type" => "core.assign", "id_suffix" => "guard",
              "config" => %{"path"  => %{"$param" => "failure_path"},
                            "value" => "failed"}}
          ]}}
      ]
    }

**What the host registers.**

    Palette.from_modules(
      [{"myapp.guarded_step", {StatifierBlocks.Composite.Data, state}}],
      []
    )

after `{:ok, state} = Composite.Data.declaration(row)`.

**What a caller sees.** For a composite block `blk_AD` whose config is
`%{"invoke_type" => "myapp:authorize", "failure_path" => "cards.authorization.failure"}`:

| The call site | What it writes today | What it writes through the seam | Answer |
|---|---|---|---|
| `ViewModel.build_resolved_node/4` (`:1701`) | `module.config_schema(config)` | `Palette.call(ref, :config_schema, [config], [])` | the two params |
| `ViewModel.build_resolved_node/4` (`:1691`) | `module.slots(config)` | `Palette.call(ref, :slots, [config], [])` | `[]` (`RQ-SF037-3`) |
| `BlockType.call_sentence/2` (`:1839`) | `module.sentence(config)` | `Palette.call(ref, :sentence, [config], nil)` | "Call myapp:authorize, recording failure at cards.authorization.failure" |
| `Compiler.entries/1` (`:2278`) | `module.current_version()` | `Palette.call(ref, :current_version, [], 1)` | `1`, the declaration's |
| `Compiler.emit/2` (`:1432`) | `module.emit(block, context)` | `Palette.call(ref, :emit, [block, context], :never)` | never reached - `blk_AD` does not survive Resolve |

Not one of those five sites knows the entry is a pair, and none of them is a
composite-aware site: they are the same lines that answer for `core.assign`.
That is the property this section exists to buy.

**What the expansion is.** `Composite.expand/2` over `blk_AD` returns the two
blocks the amendment above's "Guarded step" returns, with `blk_AD_call` and
`blk_AD_guard` as their minted ids, and a `param_map` of `%{"blk_AD_call" =>
"invoke_type", "blk_AD_guard" => "failure_path"}` - each node's own `"config"`
names exactly one param, so neither is `nil` here. `core.invoke` declares
`invoke_type` and `assign_to` among its config keys
(`lib/statifier_blocks/core/invoke.ex:130-153`) and one `on_error` slot at
`:zero_or_one` (`:96`); `core.assign` declares `path` and `value`
(`lib/statifier_blocks/core/assign.ex:64-75`).

**And what the tenant's second save costs, stated with its sharp edge.**
Editing the declaration and re-registering it at `"version" => 1` moves a
compile input without moving `palette_hash` - the obligation named above.
Bumping to `2` moves the manifest entry and the hash, and it also puts every
stored `blk_AD` at a `type_version` below `current_version/0`, which sends
`Palette.resolve/2` down `migrate/3`'s third clause (`palette.ex:540-549`).
`ADR-0007` injects `migrate_config(from, _config), do: {:error,
{:no_migration_from, from}}` (`block_type.ex:137-138`) and the amendment above
leaves that injection alone for a composite, so a bump with no migration
declared refuses every existing block of that type.

That is a real cost and this section does not pretend it away. What it decides
is only the minimum: `"version"` is **required**, so a declaration always has
one to bump, and a host that changes `params` or `subtree` has a place to
record that it did. **How a data composite declares a migration is not decided
here** - it is the first thing the implementing request will find, and it is
listed below.

### What this section does not decide

- **A shape for a host's own `state`.** `Composite.Data`'s is fixed here;
  `Palette` treats every other one as opaque, and a host's stateful type says
  what its own is.
- **Whether `Composite.Data` ships in SF037.** `sb-5xqr` is the request that
  builds it, and it is that campaign's cut line. If it does not land, this
  section stays at proposed.
- **How a host persists a declaration.** The shape above is JSON-shaped so that
  it can be stored; which column, which schema and which migration are the
  host's, and `ADR-0001`'s document schema is untouched - a document holding a
  data composite is an ordinary `schema_version` 1 document naming a type by
  string.
- **A pass-through slot, a marker on an expanded block, or the `Collapse`
  operation**: unchanged from the amendment above - `RQ-SF037-3`,
  `RQ-SF037-2`, and `ADR-0005`'s amendment respectively.
- **How a data composite declares a migration.** The paragraph above shows why
  it matters: a declaration is the only thing that can supply one, and this
  section fixes no key for it. Until that is decided, a host bumping
  `"version"` on a declaration with stored blocks is choosing a refusal, and
  the implementing request must not paper over it with a derived
  `{:ok, config}` - which is exactly the answer `ADR-0007`'s injected refusal
  exists to refuse.
- **Any change to the fourteen `@callback`s**: none is added, removed or
  re-arity'd by this section.

Filed with `sb-5b7j`, campaign SF037. The implementing request is `sb-5xqr`.

## Note (2026-09-07): the `use StatifierBlocks.Composite` amendment is flipped to accepted, with five corrections by addition, three questions named, and the data-composite amendment left at proposed

`sb-xio9` landed on `main` at `d0af5f0`, and this Note is a reading of `main` at
`0c39a3c`. Every claim the Amendment of this date at `:6360` makes was checked
against that code before its `Status:` line at `:6362` was flipped. No text
above this line is edited by this Note; everything below corrects by addition,
which is this file's practice at `:6229-6280` and `:6340-6360`.

### 0. The sentences the flip falsifies, met rather than edited

Three sentences in the section are true only of the day it was written, and the
flip is what makes them false. They stay exactly as written:

- `:6370-6371`, "Nothing here is built yet - `sb-xio9` is the request that
  builds it." `sb-xio9` built it.
- `:6364-6366`, "flipping this section's status line to accepted is a separate
  gated request (`sb-v3ny`, after `sb-xio9` lands the macro)". `sb-v3ny` is
  that request and this is it.
- `:6594-6596`, "**This amendment is proposed with that question open, and it
  flips to accepted only once the question is ruled and its ruling is
  implemented.**" That is the precondition this flip had to meet, and section 1
  below is the record that it is met.

`:6378-6379` dates every code cite in the section to `main` at `c77356b` and
asks to be re-read rather than trusted. It was, and the re-reading is sections
1 to 6.

### 1. `RQ-SF037-15` is ruled in shape (A), and built as a branch rather than a walker arm

The open-question paragraph at `:6583-6597` is superseded here. The operator
ruled `RQ-SF037-15` on 2026-09-07 in shape **(A)**, the shape the paragraph
lists at `:6586-6588` and `ADR-0011`'s Note lists at `:2465-2468`: a composite's
read and write signatures are computed at its one position by running the same
`read_signatures/3` and `write_signatures/3` over `Composite.expand/2`'s subtree
with the expanded config, with no descent, no new `type_expr()` arm, and
`config_schema/1` left as the params. Shapes (B) and (C) are declined.

One wording in the paragraph's cost line needs narrowing. `:6592` says of shape
(A) that it "adds a walker arm and keeps the declaration surface fixed". The
declaration surface is indeed fixed. Nothing that was built is a walker arm:
`Environment.read_signatures/3` and `Environment.write_signatures/3` each gained
an `if Composite.composite?(module)` branch inside the function that was already
there, and both branches call one private helper,
`Environment.expansion_signatures/5`, whose body is
`{members, _param_map} = Composite.expand(block, module)` flattened and mapped
through the same signature function it was handed. No public function was added,
no arm of the type-expression vocabulary was opened, and the module declares no
`@callback` at all. `:6577-6581`'s "**No new arm of the type-expression
vocabulary is opened here.** `RQ-SF037-8` stands" is exact as written.

`:6714-6715`, "exactly the thing `RQ-SF037-15` has to pick a mechanism for", is
stale in the same way and is met by this section.

### 2. Correction 1: `sensitive?` is not a param flag

`:6417-6420` lists the flags a param may carry "on the same terms" as any other
declared field, and `sensitive?` is among them, on `:6418`. It is not a
`field_decl/0` key. The cite the same sentence gives -
`t:StatifierBlocks.BlockType.field_decl/0` at `block_type.ex:277-287` - is exact,
and it is what falsifies the list: the type's nine keys are `key`, `type`,
`label`, `required?`, `default`, `value_path`, `datamodel_path?`, `hidden?` and
`readonly?`, and `sensitive?` is not one of them.

`sensitive?` is a key on a **datamodel** declaration, `Datamodel.declared_row/0`
at `datamodel.ex:226`. `block_type.ex:400-402` says so - "neither implies
`sensitive?`, which is a key on a **datamodel** declaration rather than on a
field declaration" - and this file already said so at `:6276-6280`, in the SF036
correction that left F8 standing. The sentence at `:6417-6420` is read with
`sensitive?` struck from its list; every other flag in it is a `field_decl/0`
key and means for a param exactly what the sentence says. Nothing else in the
section depends on the word: no derivation reads it, and `:6229` already
records that nothing in the implementation reads, sets or overrides it as a
field flag.

### 3. Correction 2: `validate_config/1` is not derived; it is left at `ADR-0007`'s injected `:ok`

The derived-callbacks table at `:6469-6479` gives `validate_config/1` the row
"the refusals `params` declare, over the composite's config", derived from the
declaration and overridable (`:6472`), and the subsection heading at `:6508`
says "`validate_config/1` runs over the params". `StatifierBlocks.Composite`
derives no `validate_config/1` at all. `use StatifierBlocks.BlockType` runs
first (`composite.ex:217`), `ADR-0007`'s injected `:ok` stands, and
`composite.ex` never redefines it.

The implementation's reading, stated in its own moduledoc at
`composite.ex:96-106`, is that the row's **outcome** is already delivered
without a derivation: the refusals a param declares are declaration-level - F3's
missing `default:`, F4's empty hidden default, and `{:type_expr, opts}`'
`allow_empty?` - and the compile already runs every one of them over
`config_schema/1`, which for a composite is the params. F3 and F4 run from
`Compiler.declaration_findings/2` (`compiler.ex:1008-1012`, refusals at
`:1017-1029`) and `allow_empty?` from `BlockType.type_expr_findings/2`
(`block_type.ex:1093-1098`, called at `compiler.ex:953`) - all three over
`module.config_schema(config)`. `required?` is a rendering hint and not an
authority, which is what lets the section's own worked example - two
`required?: true` params defaulting to `""` - land finding-free.

So the decision the row states holds and the mechanism it names does not. The
row is read as a statement of what the compile guarantees rather than of a
generated function. Overridability is unaffected: `validate_config/1` stays
overridable through `block_type.ex:163-169`, so `:6481-6482`'s "`sentence/1`,
`palette_entry/0` and `validate_config/1`. Those three and no others" is exactly
right about what a declaration may override, even though `composite.ex:258`'s
`defoverridable` names only the two the macro itself defines. `composite.ex:80`
repeats the table's wording in the module's own doc table and carries the same
imprecision; correcting it is a code change and is not this request's.

### 4. Correction 3: the `use` takes more than two things

`:6413` says "`use StatifierBlocks.Composite` takes two things and nothing
else." The two things it then describes - `params` and the `subtree/1` callback
- are the two the decision turns on, and `subtree/1` is a `@callback`
(`composite.ex:194`) enforced by `__before_compile__` (`:265-273`) rather than
an option. The macro's option list is five: `:name` and `:params`, both
required, plus `:version`, `:sentence` and `:palette_entry`
(`composite.ex:303-332`).

The section is not wrong about any of the other three; it names all of them
itself, three rows later, in the same table this Note corrects - `:6475`
derives `current_version/0` from "the declaration's version", `:6477` derives
`sentence/1` from a declared template, and `:6478` derives `palette_entry/0`
from "the declared map". `:6413` is a topic sentence that undercounts what the
section goes on to describe, and it is read as "two things the decision turns
on" rather than as a statement of the option list.

### 5. Correction 4: the sugar cite, and the cites the code moved

`:6552-6553` cites `environment.ex:1070-1080` for `ADR-0011` decision 6's sugar.
That range is `writes?/1` and `written_type/1` today. The sugar is
`sugar_read/4` at `environment.ex:1102` and `sugar_write/4` at `:1107`. The
claim the sentence makes - that `io/1` contributes only the sugar, and that
both sugar keys are single-valued - holds:
`t:StatifierBlocks.Assignability.io/0` at `assignability.ex:88-93` declares
`consumes` and `produces` as single values, not lists.

The rest of the section's `lib/` cites resolve to the text they were written
against, at these lines today. The claims are unchanged; only the numbers move.

| Cited in the section | Cited as | Reads today |
|---|---|---|
| `outcomes/1`, `failure_outcomes/1`, `summary/1`, `donedata_type/1`, `sentence/1` (`:6403-6404`) | `:657`, `:690`, `:729`, `:777`, `:813` | `block_type.ex:665`, `:698`, `:737`, `:785`, `:821` |
| `migrate_config/2`'s injected refusal (`:6492-6493`) | `block_type.ex:135-139` | `:132-138` (comment `:132-136`, clause `:137-138`) |
| `read_signatures/3` (`:6546`) | `environment.ex:361` | `:363-364` |
| `write_signatures/3` (`:6547-6548`) | `environment.ex:377` | `:386-387` |
| `Recipe`'s `insert/2` (`:6601-6602`) | `recipe.ex:53` | `:73` |
| the sugar (`:6552-6553`) | `environment.ex:1070-1080` | `sugar_read/4` `:1102`, `sugar_write/4` `:1107` |

The count at `:6402-6405` - "fourteen `@callback`s on `main` today ... and five
are still required" - is exact: `block_type.ex` declares fourteen and
`@optional_callbacks` at `:823-831` names nine.

Two prose cites are narrow rather than moved. `:6446-6447` says "**The
declaration** mints the expanded blocks' ids"; `expand/2` mints them
(`composite.ex:544-557`), from the local ids the declaration writes, and the
determinism the sentence claims is `expand/2`'s. `:6636-6642` enumerates "one
function, three callers" for `expand/2`; the environment walk is a fourth
(`environment.ex:427`), which is section 1's own doing, and the module's two
derivations are a fifth class the code acknowledges at `composite.ex:337-339`.

### 6. What the code does that the section does not describe

Two behaviours are recorded here because the accepted text should carry them.

**The derived `io/1` and `outcomes/1` resolve members through the core palette
only.** Both derivations read a member's *module*, and a `Block` carries a type
*name*; neither `io/1` nor `outcomes/1` is handed a palette, so
`member_module/1` (`composite.ex:597-603`) resolves through
`Palette.fetch(Palette.core(), type)`. A composite whose expansion root is a
**host** type therefore falls back: `outcomes/1` to the behaviour's default
`[{"done", "Done"}]` (`block_type.ex:836`, `:855-861`), and `io/1` to
`%{kinds: [:step], slot_accepts: %{}}` with no sugar copied. `composite.ex:135-146`
documents it. Both reference composites root at `core.*` and are exact, and the
environment walk is unaffected because it has a palette. Rows `:6474` and
`:6476` and the worked-example table at `:6703-6704` state the derivations
unconditionally, and are read with this limitation. **Whether a composite's
derived `io/1` and `outcomes/1` should see the host palette is a question this
Note names and does not decide**; it is for the SF038 walk.

**The param map handed to `subtree/1` is the declaration's defaults with the
stored config merged over them** (`params_of/2`, `composite.ex:492-497`). The
section does not describe the layering. Nothing in it contradicts the layering.

### 7. `Composite.expand/2` as built

`:6619-6628`'s signature is exact:
`@spec expand(Block.t(), module()) :: {[Block.t()], param_map()}`
(`composite.ex:368-369`). The second argument is the composite's own **module**,
an atom the caller has already resolved through `Palette.fetch/2`
(`palette.ex:408`), as `:6622-6624` says. `composite?/1` (`composite.ex:341-346`)
and `flatten/1` (`:401-411`) are public, which the decision forces rather than
adds: `composite?/1` is how the compiler, the environment walk and the editor
each ask the question the section makes them ask, and `flatten/1` is how the
param map and the derivations reach nested members. The `param_map` answers one
param key or `nil` per expanded block (`composite.ex:173`, built at `:562-583`),
and it is built over `flatten/1`, so nested members are in it too - which the
section does not say and which nothing in it contradicts.

`RQ-SF037-17` - where `expand/2` should get a member's `current_version` - is
named open here and decided nowhere. `mint/3` rewrites a member's `id` and
`slots` and does not stamp `type_version`, so a member carries `Block.new/2`'s
default of 1 (`block.ex:54`) and a member type at version 2 would take the
migration path on every compile. `sb-qxyh` declined to stamp at Resolve to keep
the byte identity `ADR-0004`'s amendment of this date requires. The question is
queued for the SF038 walk.

A third question this Note names and does not decide: **nothing derives
`summary/1` for a composite**, and `:6491-6496` is right that it stays optional
and absent. The consequence the section does not state is that a composite
declaring no `summary/1` draws **no chip row at all** - `BlockType.summary/3`
answers `[]` and `block_node.ex:367` renders the row only when the chip list is
non-empty. Whether a composite's params should draw as chips by derivation is
`ADR-0005`'s to say, and its amendment of this date says the chips come from the
composite's config through the existing reader. The two records are consistent;
what neither settles is whether a composite with no declared summary should draw
something. Named for the walk.

### 8. The data-composite amendment stays at proposed

The Amendment at `:6732`, `sb-5b7j`'s, says at `:6735-6739` that its status line
flips "**only if `sb-5xqr` lands in SF037**", and that if it does not, "this
section stays at proposed and `sb-v3ny` records that fact as a dated note
instead of flipping it". `sb-5xqr` did not land in campaign SF037: it was below
the cut line `RQ-SF037-14` draws, `Palette.call/4` is not defined in
`palette.ex`, and no `StatifierBlocks.Composite.Data` module exists on `main` at
`0c39a3c`. **The Status line at `:6734` therefore stays at `proposed`**, exactly
as that section instructs, and this is the dated note it asks for. It flips when
`sb-5xqr` lands, by its own terms and through the same gate.

### 9. Folding `sb-cr7e`: the `ADR-0011` amendment is accepted

`:5608-5610`, inside the Note of 2026-09-07 at `:5560`, reads "**That amendment
is not accepted as of this Note** - `sb-wzoa` does not flip it, and the Note of
this date at the foot of `docs/adr/0011-typed-environment.md` says why." It was
true of that Note and is time-bounded by its own words. For the reader who
arrives later: `sb-wzoa` accepted `ADR-0011`'s amendment on 2026-09-07 at
`dcf5668`, and `docs/adr/0011-typed-environment.md:1848` reads `accepted` today.
The sentence at `:5608-5610` is left standing and dated here.

### 10. Folding `sb-ot1x`: four cite ranges and one attribution

Items 1, 2 and 4 of `sb-ot1x` are folded here. Item 3 - the comment at
`block_type.ex:140-147`, which still carries the unqualified "indistinguishable
from a type that declares no `sentence/1`" wording that correction 5 at
`:6303-6326` qualifies - is a change to a **code** file and is out of scope for
this docs-only request. It is confirmed present at exactly those lines and is
left for a code request.

**The three ranges, re-located by anchor.** The bead's numbers were themselves
off by eight to thirteen lines; these are today's.

| Cited in this file | Cited as | Reads today, at `0c39a3c` |
|---|---|---|
| `chip_refusal/1` (`:6240`, and the table row at `:6348`) | `:1885-1894` / `:1884-1894` | `@spec` `block_type.ex:1892`, body `:1893-1900`, catch-all clause `:1902`. The `@spec` and the catch-all are both outside the cited range as written |
| `call_sentence/2` (`:6237`) | `:1829-1832` | `@spec` `:1837`, body `:1838-1845`, which runs to the end of the `rescue`/`catch` the sentence is about; the cited range stops four lines short of the clauses it cites |
| `call_join_label/2`'s comment (the table row at `:6347`) | comment `:1811-1813`, body `:1814-1822` | comment `:1818-1821`, body `:1822-1830` |

Related and moved with them: `chip/1` (`:6348`) cited `:1872-1878`, today
`@spec` `:1880` and body `:1881-1886`; `@presentation_cap` cited `:1335`, today
`:1343`. All resolve to the text they name; only the numbers move.

**The attribution at `:6309-6314`.** The sentence says `ADR-0005`'s amendment of
this date "puts a **separate** `function_exported?/3` question in the chain",
and attributes to it a reading in terms of a function `ADR-0005` never names.
`ADR-0005`'s own words for what it did are at `:8442-8444` of
`docs/adr/0005-liveview-editor.md`: "the table is written in terms of what the
type **declares**, and an injected default is declared." That is the exact form,
and `:6309-6314` is read against it. `ADR-0005`'s three-step table at
`:7902-7906` speaks only of a type that "declares `sentence/1`"; the function
`function_exported?/3` is the **implementation's** way of asking that question,
in `ViewModel.declares_sentence?/1`, and naming it is this file's reading of
`ADR-0005` rather than a claim about `ADR-0005`'s text. The cite
`block_type.ex:148-161` on `:6309` still resolves exactly.

**Item 4, the `InvokeStep` caveat.** `StatifierBlocks.InvokeStep.__using__/1`
emits `use StatifierBlocks.BlockType` (`invoke_step.ex:137-144`, the `use` at
`:144`), so every type built on `InvokeStep` also carries the injected
`sentence/1`, answers `true` to `function_exported?(module, :sentence, 1)`, and
counts as **declared** by `ViewModel.declares_sentence?/1`. Such a type
therefore sits inside correction 5's cost set at `:6303-6326`: its outline line
is the palette label and never the author's `title`. `:6322`'s "No shipped
`core.*` type is in that set" stays true as written - it is scoped to `core.*` -
and the caveat is that a **host** type built on `InvokeStep` is in it, which is
the common shape rather than an exotic one. The `use`-injection subsection at
`:6101` is where this attaches, and specifically the sentence at `:6115-6117`
about a module that "declares nothing else". Two cites in that subsection have
moved with the file: `:6103` cites `block_type.ex:107-145` for the `use` macro,
today `:109-171`, and `:6111` cites `:138-143` for `defoverridable`, today
`:163-169`; both were already re-counted at `:6349`.

Filed with `sb-v3ny`, campaign SF037, folding the `ADR-0002` half of `sb-cr7e`
and items 1, 2 and 4 of `sb-ot1x`. This Note changes no code and adds no README
row; it flips the `Status:` line at `:6362` and nothing else in this file, and
it leaves the Status line at `:6734` at `proposed`.

## Note (2026-09-07): the data-composite amendment is flipped to accepted, with six corrections by addition, its cites re-counted, and three questions named open

`sb-5xqr` landed on `main` at `592c23b`, **after** `sb-v3ny` had merged at
`ea2df96` and recorded at `:7521-7531` that it had not. This Note is a reading
of `main` at `7186b24`. Every claim the Amendment of this date at `:6732` makes
was checked against that code before its `Status:` line at `:6734` was flipped.
No text above this line is edited by this Note; everything below corrects by
addition, which is this file's practice at `:6229-6280`, `:6340-6360` and
`:7305-7597`.

### 0. The sentences the flip falsifies, met rather than edited

Three sentences were true only of the day they were written, and the landing is
what makes them false. They stay exactly as written:

- `:6736-6739`, "This section's status line flips to accepted by `sb-v3ny`
  **only if `sb-5xqr` lands in SF037**; if that request does not land, this
  section stays at proposed and `sb-v3ny` records that fact as a dated note
  instead of flipping it." `sb-5xqr` did land in SF037, and later than
  `sb-v3ny` merged, so the flip is a separate gated request rather than
  `sb-v3ny`'s work. It is `sb-acf5`, and this is it.
- `:7282-7284`, "**Whether `Composite.Data` ships in SF037.** `sb-5xqr` is the
  request that builds it, and it is that campaign's cut line. If it does not
  land, this section stays at proposed." It landed.
- `sb-v3ny`'s section 8 at `:7521-7531`, "`sb-5xqr` did not land in campaign
  SF037 ... **The Status line at `:6734` therefore stays at `proposed`**." That
  was exact when written, against `main` at `0c39a3c`. It is superseded by
  addition on the terms it set for itself in its own last sentence: "It flips
  when `sb-5xqr` lands, by its own terms and through the same gate."

`:6750-6754` dates every code cite in the section to `main` at `d0af5f0`, asks
to be re-read rather than trusted, and names the **anchor** rather than the line
as the way to find a site after it has moved. It was re-read on those terms;
sections 1 to 8 are the re-reading.

### 1. The claim table: what the section decides, and what the code reads today

Every row was checked against `main` at `7186b24`. No row is refuted; the six
that need narrowing are corrected in sections 2 to 7, and every cite that moved
is re-counted in section 8.

| The section's claim | Where it says it | What `7186b24` reads | Verdict |
|---|---|---|---|
| `Palette.types` admits `module()` or `{module(), state}`, and `state` is opaque to `Palette` | `:6775-6785` | `@type type_ref :: module() \| {module(), state :: term()}` (`palette.ex:92`), `types:` in `@type t` (`:94`) | holds |
| `registration/0` widens with it, so `from_modules/2` takes a stateful entry | `:6803-6805` | `@type registration :: {Block.type_name(), type_ref()}` (`palette.ex:266`); the second `register/2` clause at `:417-420` | holds |
| `fetch/2` answers the entry **as stored**, normalizing neither way, and decision 3's one error arm is untouched | `:6787-6794` | `fetch/2` (`palette.ex:453-461`) answers `{:ok, ref}`; the sole error arm at `:459` | holds |
| `resolve/2` widens the same way and keeps its three error arms | `:6792-6794` | `@spec resolve/2` (`palette.ex:669-673`) answers `{:ok, type_ref(), Block.t()}`; head `:674-678` | holds |
| `Palette.call/4` is the one seam: two clauses, `state` **prepended**, `default` when the entry does not declare the callback | `:6812-6821` | `call/4` (`palette.ex:510-527`): the pair clause applies `[state \| args]`, the bare clause applies `args`, both fall to `default` | holds |
| the seam does **not** rescue, does not memoize, and changes no declared arity; fourteen callbacks, five required | `:6876-6884` | no `rescue` and no cache in `call/4`; `block_type.ex` declares 14 `@callback`s and `@optional_callbacks` (`:824-832`) names 9 | holds |
| `Palette.declares?/3` does the arity arithmetic itself, so no caller writes `arity + 1` | `:6849-6856` | `declares?/3` (`palette.ex:552-561`): the pair clause asks `arity + 1`, the bare clause asks `arity` | holds, widened in section 7 |
| the census is **38 call sites in 12 files** | `:6888-6892`, table `:6894-6908` | 38 in 12, re-counted per file in section 7 | holds |
| `manifest/1` and `palette_hash/1` need no new arm; the hash's triples keep the module | `:6985-6991` | `manifest/1` (`palette.ex:247-255`) maps `{name, current_version}`; `palette_hash/1` (`compiler.ex:2504-2516`) keeps the module through a private `module_of/1` (`:2529`, `:2534-2536`) | holds, narrowed in section 6 |
| the duplicate-`order` check needs the seam, and `ordered_entry/1`'s `is_atom/1` guard is where a stateful entry would drop out **silently** | `:7007-7021` | the guard is gone: `ordered_entry/1` (`palette.ex:400-408`) reads `palette_entry/0` through `call/4`, and the comment at `:370-378` records exactly this reason. Two tests hold it - a stateful entry colliding at a duplicated order is refused, and the refusal names both entries (`test/statifier_blocks/palette/call_test.exs:157-184`) | holds |
| `Composite.expand/2`'s second argument widens to `type_ref()`; it is still the ONE expansion function, unrenamed and unforked | `:6959-6962` | `@spec expand(Block.t(), Palette.type_ref())` (`composite.ex:375`), head `:376`; the `is_atom/1` guard is now `composite?/1`'s question (`:341-350`, asked at `:377-381`) | holds |
| `__composite__` and `subtree` are seam calls at one higher arity, and are **not** in the census of 38 | `:6963-6969` | four `Palette.call/4` sites in `composite.ex` (`:385`, `:462`, `:502`, `:510`), none of them a `BlockType` callback; the census total is unmoved | holds |
| for `Composite.Data` both answers are the state | `:6970-6976` | `__composite__(state)` (`composite/data.ex:331-334`) and `subtree(state, params)` (`:344-347`) | holds, narrowed in section 5 |
| the declaration is JSON-shaped so a host can store it; `declaration/1` answers `{:ok, state}` or `{:error, [reason]}` and every refusal is at **entry-build** time | `:7042-7043`, `:7080-7088` | `declaration/1` (`composite/data.ex:285-317`) accumulates every error and answers `{:ok, decoded}` or `{:error, errors}` | holds, narrowed in section 5 |
| `slots/1` is `[]`, `config_schema/1` is the params, `current_version/0` is the declaration's, `emit/2` raises | `:7029-7033` | `slots/2` (`composite/data.ex:355`), `config_schema/2` (`:351`), `current_version/1` (`:359`), `emit/3` (`:401-409`) raising | holds |
| `validate_config/1` is left as the params alone refuse it, so a cross-param refusal still needs a `use`-composite | `:7054-7065` | `validate_config(_state, _config), do: :ok` (`composite/data.ex:380`), which is `ADR-0007`'s injected answer | holds |
| `migrate_config/2` is left at `ADR-0007`'s injected refusal, so a version bump with no migration refuses every stored block | `:7259-7268` | `migrate_config(_state, from, _config), do: {:error, {:no_migration_from, from}}` (`composite/data.ex:371`), the same shape `block_type.ex:139` injects, reached down `migrate/3`'s third clause (`palette.ex:692-698`) | holds |
| the placeholder vocabulary is one arm and one escape: `"$param"` substituted **whole**, `"$literal"` unsubstituted, every other value a literal | `:7120-7128` | `substitute/2` (`composite/data.ex:427-439`), both special clauses guarded `map_size(node) == 1`; `placeholders/1` (`:633-642`) reads the same vocabulary | holds |
| `"id_suffix"` matches `~r/\A[a-z0-9]+(_[a-z0-9]+)*\z/`, is unique per declaration, and can mint no `__` | `:7106-7112` | `@id_suffix` (`composite/data.ex:213`); the `__` refusal is `mint_id/3`'s (`composite.ex:555-568`), citing `ADR-0004` decision 3 in its own message | holds |
| per-instance module generation is rejected, on decisions 2 (`:65-70`, `:76-78`), 3 (`:86-88`) and the atom table | `:7155-7190` | those four decision passages read today exactly as cited, and nothing in `palette.ex` or `composite/data.ex` calls `Module.create/3` | holds |
| the worked example's `param_map` is `%{"blk_AD_call" => "invoke_type", "blk_AD_guard" => "failure_path"}` | `:7249-7253` | reproduced from `param_map/2` (`composite.ex:573-578`) over the example's own config values | holds, by a different derivation - section 4 |

### 2. Correction 1: the sentence placeholder is spelled `{{key}}` here and `{key}` in the code, and is collapsed once at decode

`:7052` gives the `"sentence"` key as "a template string; `{{key}}` is replaced
by the param's value rendered as a string", and the worked example at `:7206`
writes `"Call {{invoke_type}}, recording failure at {{failure_path}}"`. A
`use`-composite's `:sentence` spells the same placeholder `{key}`, and
`StatifierBlocks.Composite.render_sentence/2` is the renderer for both.

They are one rendering, not two. `decode_sentence/2`
(`composite/data.ex:683-696`) collapses `{{key}}` to `{key}` **once, at decode,
for the keys this declaration actually declares**, and the collapsed template is
what the state carries; `sentence/2` (`:394-395`) hands that to
`render_sentence/2`. So the record's spelling is what a host writes, the code's
is what the one renderer reads, and a data composite and a `use`-composite of
the same shape answer the same line. Nothing else in the section depends on the
spelling, and a `{{...}}` naming an undeclared key is left alone rather than
refused - it is a placeholder in neither vocabulary.

### 3. Correction 2: `sensitive?` is not a param key, and an unknown key is refused by name

`:7067-7071` gives `"params"` as decision 7's `field_decl()` in JSON and lists
`"sensitive?"` among the keys a declaration may write, on `:7070`. It is not a
`field_decl/0` key: the type's nine keys at `block_type.ex:278-288` are `key`,
`type`, `label`, `required?`, `default`, `value_path`, `datamodel_path?`,
`hidden?` and `readonly?`. `sensitive?` is a key on a **datamodel** declaration,
`Datamodel.declared_row/0` at `datamodel.ex:226`. This file said so at
`:6276-6280` and `sb-v3ny` said so again at `:7358-7377`; the sentence at
`:7067-7071` is read with `sensitive?` struck from its list, for the same reason
and on the third occasion.

The code is not permissive about it. `decode_param/1`
(`composite/data.ex:477-503`) admits `"key"`, `"type"`, `"label"`, `"default"`
and the five flags `@param_flags` names (`:223-229` - `required?`, `value_path`,
`datamodel_path?`, `hidden?`, `readonly?`), and refuses any other key **by
name**: *param `<key>` declares unknown keys: [...]*. A declaration writing
`"sensitive?"` is refused at entry-build time rather than silently carried,
which is the honest reading of the same decision.

### 4. Correction 3: `"default"` is required, and `param_map` is derived by value

Two mechanisms the section presents one way and the code implements another. In
both cases the decision the section states holds and the mechanism it names is
not the one built.

**`"default"` is not optional.** `:7069` lists `"default"` among the keys
"whichever of ... the declaration writes", which reads as optional, while the
same paragraph says at `:7071-7074` that "every refusal decision 7 and its
amendments state applies to a param unchanged - including F3's missing-`default:`
refusal". F3 governs: `decode_param/1` (`composite/data.ex:487-490`) refuses a
param carrying no `"default"` key at entry-build time, before the entry is in
the palette, in the words *is declared with no "default", so it has no value to
read when a config leaves it unset*. The list at `:7067-7071` is read with
`"key"`, `"type"`, `"label"` and `"default"` as the four required keys and the
flags as the optional ones - which is what `decode_param/1`'s own head and
`:7080-7088`'s entry-build placement already say.

**`param_map` is derived by value comparison, not by reading placeholders.**
`:7147-7153` attributes a node to param key *K* "when the placeholders in **its
own `"config"`**, not its slots' children, name exactly one distinct param".
`Composite.expand/2` does not read the template's placeholders when it builds
the map: `param_map/2` (`composite.ex:573-578`) walks `flatten/1` over the
**expanded** blocks and blames each on the one param whose **value** its config
carries (`blamed_param/2` `:580-594`), with `distinguishing?/1` (`:598-600`)
excluding `nil`, `""`, `[]`, `%{}` and `false` because an empty value would
match every empty config field in the expansion. Two params matching, or none,
is `nil`.

The two agree on every case the section states, its own worked example included,
which is why this is a correction and not a refutation: a whole-value
substitution puts exactly the param's value into the expanded config, so "the
placeholders in its own config name exactly one param" and "its own config
carries exactly one param's value" pick out the same node. The value derivation
is the more general of the two - it reads no template, which is what lets one
`param_map/2` serve a `use`-composite and a data composite alike - and it
differs in one stated way: a param whose value is empty blames nothing, where a
placeholder count would blame it. `:7147-7153` is read as a description of the
mechanical result rather than as a second derivation.

### 5. Correction 4: the `state` is the **decoded** declaration, and `__composite__/1` answers five of its keys

`:7042-7043` heads its table "Its `state` is a **declaration map**, JSON-shaped
throughout", with six string keys at `:7045-7053`, and `:7201` presents the JSON
row as "the `state` of one palette entry". What a palette entry carries is
`declaration/1`'s **output**, not its input. The state is a map with atom keys
(`t:StatifierBlocks.Composite.Data.state/0`, `composite/data.ex:204-211`):
`:name` (from the row's `"type_name"`), `:params` (decoded into decision 7
`field_decl()` maps), `:version`, `:sentence` (collapsed, section 2), and
`:palette_entry` and `:subtree` (decoded into `t:node_template/0`s). The table's
six rows are the rows of the **row** `declaration/1` takes; the section's own
worked example writes the conversion out at `:7232` - `{:ok, state} =
Composite.Data.declaration(row)` - so both readings are already present, and
this Note names which is which.

The distinction is not cosmetic: it is `:7074-7079`'s decision built.
`Composite.Data` "**decodes** this list ... once, when the entry is built ...
because decision 4 makes `config_schema/1` pure and a decode that could fail on
the hot path is a callback that can fail". The atom-keyed state is that
sentence's consequence, and `config_schema/2` (`composite/data.ex:351`) returns
the already-decoded list without work.

`:6973-6974` says `__composite__(state)` "answers the decoded `state`". It
answers **five of its six keys**: `Map.take(state, [:name, :params, :version,
:sentence, :palette_entry])` (`composite/data.ex:331-334`), which is
`t:StatifierBlocks.Composite.declaration/0` - the shape a `use`-composite's
generated `__composite__/0` answers from a module attribute
(`composite.ex:224-225`). `:subtree` sits outside it deliberately, because the
template is read by `subtree/2` and a `use`-composite has no template to hand
back. The claim the sentence makes - that the declaration **is** the state
rather than a pointer to one - is what that `Map.take/2` shows.

### 6. Correction 5: only five of the nine field types have a data spelling, and `manifest/1` no longer raises

**Four field types are refused, not spelled.** `:7068` says `"type"` is "the
field type's name as a string". Only five of
`t:StatifierBlocks.BlockType.field_type/0`'s nine members
(`block_type.ex:179-188`) have one: `@field_types` (`composite/data.ex:215-221`)
maps `"string"`, `"integer"`, `"boolean"`, `"expression"` and `"duration"`. The
other four - `{:select, opts}`, `{:list, field_type}`, `{:path, opts}` and
`{:type_expr, opts}` - carry options, have no name, and are **refused** by
`decode_param/1` (`composite/data.ex:481-485`), whose message lists the five
spellable names. `:7071`'s "No new key and no new field type is introduced here"
stays exact - none is - and what this Note adds is that four existing ones
cannot be reached from a declaration held as data. How an option-carrying field
type would be spelled in data is a question this Note names and does not decide;
it is section 9's third.

**`Palette.manifest/1` no longer raises on an uncompiled module.** `:6985-6991`
is about the manifest needing no new arm, and that holds. What moved beside it:
`manifest/1` now reads `current_version/0` through `call(ref, :current_version,
[], nil)` (`palette.ex:250`), and `call/4` answers the default when
`Code.ensure_loaded?/1` fails, so a palette naming an uncompiled module answers
`nil` for that entry where it used to raise. Nothing this section decides
depends on the raise, and the 0.25.0 CHANGELOG records the change. The
manifest's own moduledoc at `palette.ex:241-243` still describes the old
behaviour; correcting it is a **code** change, out of scope for this docs-only
request, and it is named here so it is not lost.

### 7. Correction 6: the census total holds, two files' split moved, and `declares?/3` has more callers than the two named

**The census is still 38 call sites in 12 files**, and every anchor in the table
at `:6894-6908` resolves to the same function head in the same file, with one
exception: `entry_default_config/1` moved from `editor.ex` to
`edit/targets.ex` (`sb-mcs8`), along with `probe/2` and `accepted_types/4`. So
`editor.ex` reads 2 and `edit/targets.ex` reads 2, where the table has 3 and 1.
The total is unmoved, which is why the count the section asks to be worked from
is still its own.

| File | Section's count | Today | Anchors at `7186b24`, with the call-site line |
|---|---|---|---|
| `lib/statifier_blocks/block_type.ex` | 7 | 7 | `outcomes/2` `:858`, `failure_outcomes/2` `:900`, `donedata_type/2` `:931`, `type_expr_findings/2` `:1086`, `call_summary/2` `:1798`, `call_sentence/2` `:1827`, `label/1` `:1855` |
| `lib/statifier_blocks/compiler.ex` | 6 | 6 | `resolve_children/3` `:643`, `config_findings/2` `:947`, `declaration_findings/2` `:1010`, `emit/2` `:1675`, `candidate_findings/2` `:2415`, `entries/1` `:2529` |
| `lib/statifier_blocks/palette.ex` | 6 | 6 | `manifest/1` `:250`, `ordered_entry/1` `:404`, `new_block/2` `:600` and `:606`, `resolve/2` `:676`, `migrate/3` `:693` |
| `lib/statifier_blocks/view_model.ex` | 6 | 6 | `head_of_root/2` `:1417`, `chip_label/2` `:1508`, `config_findings/3` `:1645`, `build_resolved_node/4` `:1694` and `:1704`, `palette_entry_with_defaults/2` `:2148` |
| `lib/statifier_blocks/editor.ex` | 3 | **2** | `fixture_events/1` `:2679`, `draft_findings/3` `:3346` |
| `lib/statifier_blocks/environment.ex` | 3 | 3 | `subject_of/1` `:1030`, `io/2` `:1125`, `schema/2` `:1130` |
| `lib/statifier_blocks/assignability.ex` | 2 | 2 | `io/2` `:192`, `target_verdicts/4` `:803` |
| `lib/statifier_blocks/edit/targets.ex` | 1 | **2** | `entry_default_config/1` `:227`, `full?/4` `:387` |
| `lib/statifier_blocks/slot_validation.ex` | 1 | 1 | `block_findings/2` `:80` |
| `lib/statifier_blocks/edit.ex` | 1 | 1 | `check_config/3` `:271` |
| `lib/statifier_blocks/datamodel.ex` | 1 | 1 | `block_findings/5` `:818` |
| `lib/statifier_blocks/core/deadline_recipe.ex` | 1 | 1 | `config/2` `:228` |
| **Total** | **38** | **38** | **12 files** |

**`declares?/3` has four callers on `BlockType` callbacks, not the two the
section names.** `:6849-6852` gives it "the two sites that need declaredness
alone" - `ViewModel.declares_sentence?/1` (`view_model.ex:1985-1988`) and the
editor's `declares_outcomes?/1` (`editor.ex:2862-2865`). Two more are the
section's own doing rather than a departure from it: `BlockType.sentence/2`
(`block_type.ex:1548-1555`) and the private `declared_chips/2` (`:1782-1791`)
each keep a probe, because the call each guards is one level down in
`call_sentence/2` (`:1825-1833`) and `call_summary/2` (`:1796-1804`) - the two
sites `:6867-6874` says reach a **rescue**, and which therefore cannot be folded
into a `call/4` the section forbids to rescue. A fifth caller is
`Composite.composite?/1` (`composite.ex:341-350`), asking about
`__composite__/0`, which `:6963-6969` already places in the seam and outside the
census. `:6849-6852` is read as naming the two sites that need declaredness for
a **presentation** branch; the arity argument it makes is unaffected, and no
site anywhere writes `arity + 1` itself.

The probe count at `:6910-6913` - 17 in 6 files - was a count of the
`function_exported?/3` calls the seam was about to absorb, at `d0af5f0`. It is a
statement about the code before the request rather than a claim about the code
after it, and it stands as written.

### 8. The cites that moved

Every cite below resolves to the text it names. Only the numbers move; no claim
changes. This is `:6750-6754`'s own instruction being followed.

| Cited in the section | Cited as | Reads today at `7186b24` |
|---|---|---|
| `fetch/2`'s one error arm (`:6791-6792`) | `palette.ex:405-407` | `:459`, inside `fetch/2` `:453-461` |
| `resolve/2`'s three error arms (`:6793`) | `palette.ex:517-521` | `@spec` `:669-673`, head `:674-678` |
| `from_modules/2` (`:6804`) | `palette.ex:311` | `:341` |
| `manifest/1` (`:6985`) | `palette.ex:224-229` | `:247-255` |
| the duplicate-`order` check (`:7007`) | `palette.ex:343-373` | `refute_duplicate_orders!/2` `:379-401` |
| `ordered_entry/1`'s opening guard (`:7015-7016`) | `palette.ex:365` | **gone.** The guard the sentence describes was removed, which is what the sentence asks for; `ordered_entry/1` is `:400-408` and the comment at `:370-378` records the removal in the sentence's own terms |
| `migrate/3`'s third clause (`:7264`) | `palette.ex:540-549` | `:692-698` |
| the two maps, quoted from `:6610-6611` (`:6807-6809`) | `palette.ex:70-75` | `@type t`'s `types:` and `recipes:` at `:94-95`; `:70-75` is the validators paragraph. The cite is the accepted amendment's rather than this section's and is recorded, not restated |
| `palette_hash/1` (`:6986`) | `compiler.ex:2261-2273` | `:2504-2516`, with `module_of/1` `:2534-2536` |
| the palette-hygiene obligation (`:6996-6998`) | `compilation_record.ex:40-51` | `:40-50` |
| `expand/2`'s spec and guard (`:6949-6950`) | `composite.ex:368-369` | `@spec` `:375`, head `:376`; the `is_atom/1` guard is now `composite?/1`'s, asked at `:377-381` |
| `composite?/1` (`:6950-6952`) | `composite.ex:341-346` | `:341-350`, now three clauses and reading `Palette.declares?/3` |
| the generated `__composite__/0` (`:6952-6953`) | `composite.ex:224-225` | `:224-225` - unmoved |
| `recipe_insert/3`, `params_of/2`, `probe_block/2` (`:6953-6954`) | `:455`, `:494`, `:501` | `:461`, `:500`, `:509`, each now reading the declaration through `call/4` |
| the `subtree/1` call (`:6954-6955`) | `composite.ex:378` | `:385`, through `call/4` |
| `member_module/1` (`:6923`) | `composite.ex:598-603` | `:608-614` |
| the six `BlockType` wrappers (`:6860-6863`) | `:855-861`, `:901-907`, `:936-942`, `:1560-1566`, `:1795-1802`, `:1866-1875` | `:856-859`, `:898-901`, `:929-932`, `:1548-1555`, `:1782-1791`, `:1853-1859` |
| `call_sentence/2` and `call_summary/2` (`:6869-6870`) | `:1838-1846`, `:1809-1816` | `:1825-1833`, `:1796-1804` |
| the absent-`io/1` fallback (`:6834`) | `assignability.ex:166-172` | `io/2` `:190-193`, now the seam's `%{}` default |
| `ViewModel.declares_sentence?/1` (`:6851`) | `view_model.ex:1984` | `:1985-1988` |
| the editor's `declares_outcomes?/1` (`:6852`) | `editor.ex:2755` | `:2862-2865` |
| `ADR-0007`'s injected `migrate_config/2` (`:7266`) | `block_type.ex:137-138` | `:138-139` |
| `core.invoke`'s config keys and its `on_error` slot (`:7255-7256`) | `invoke.ex:130-153`, `:96` | unmoved |
| `core.assign`'s config keys (`:7257`) | `assign.ex:64-75` | unmoved |
| `RunPane.component/1`, named as **not** in the census (`:6931`) | `editor/run_pane.ex:191-196` | unmoved, and still not a callback dispatch: the module it applies comes from `Application.get_env/3` |

**The list at `:6918-6930` of literal `types` reads that are not the census has
moved with `sb-mcs8`.** `Editor.probe/2` and `Editor.accepted_types/3` are now
`Targets.probe/2` (`edit/targets.ex:215-223`) and `Targets.accepted_types/4`
(`:175-190`, reading `palette.types` at `:181`); `Editor.draft_findings/3` is
`editor.ex:3345`, `Editor.accepted_recipes/2`'s `recipes` read is `:3393`,
`ViewModel.singleton_specs/2` is `view_model.ex:1339`,
`ViewModel.palette_groups/1` is `:2174`, and `Composite.member_module/1` is
`composite.ex:610`. The count is still six plus the one `recipes` read, not one
of them assumes a `types` value is a module, and the paragraph's claim is
unchanged.

### 9. Three questions this Note names and does not decide

- **`RQ-SF037-16`, a data composite's migration key.** `:7293-7299` names it
  open, and `sb-5xqr` built the refusal that paragraph describes rather than
  papering over it: `migrate_config/3` (`composite/data.ex:371`) answers
  `{:error, {:no_migration_from, from}}` unconditionally, so a host that bumps
  `"version"` on a declaration with stored blocks is choosing a refusal,
  exactly as `:7270-7275` says. The declaration carries no migration key, and
  `Composite.Data`'s moduledoc says so. Queued.
- **`RQ-SF037-17`, a member's `current_version` in an expansion.** `sb-v3ny`
  named it at `:7502-7509` and this request does not touch it: a data composite
  expands through the same `Composite.expand/2`, and its members carry
  `Block.new/2`'s default of 1 for the same reason. Queued.
- **How an option-carrying field type is spelled in a declaration held as
  data.** Section 6: four of the nine field types are refused by
  `decode_param/1` rather than spelled. Whether a data declaration should be
  able to reach them, and in what shape, is not decided here.

Filed with `sb-acf5`, campaign SF037. This Note changes no code and adds no
README row; it flips the `Status:` line at `:6734` and nothing else in this
file.

## Note (2026-09-07): seven readings the SF038 walk takes on this record - the migration question ruled and pointed at its own amendment, a member's version in an expansion, io/outcomes through a palette, a derived `summary/1`, what `param_map` blames, a declared `failure_outcomes`, and one question named open

The SF038 walk read the questions this file's Notes leave standing and took the
six rulings the items below record. This Note is a reading of `main` at
`503ed48`. It edits no text above this line, carries no `Status:` line and
flips nothing: five of its seven items record what the code already does or
what a named request will do to it, one points at a decision that lands as its
own amendment, and one names a question and leaves it open. The walk's rulings
are labelled `RQ-SF038-<n>` below, which is the form this file already uses for
the SF037 walk's at `:7894` and `:7901`.

### 1. `RQ-SF037-16` is ruled, and the ruling lands as an amendment rather than here

`:7894-7900` names a data composite's migration key open, and `:7901-7904`
records that `sb-v3ny` left `RQ-SF037-17` beside it. The walk ruled it: a
declaration may carry a declarative `"migrations"` list. That is a decision
about the declaration's shape, so it does not land in a Note - it lands as its
own dated `## Amendment` on this file (`sb-ekkt`), after the pass-through
amendment (`sb-nlo5`), with its implementing request `sb-mulk`. **This item
fixes nothing about that shape**: not the step keys, not the order steps are
applied in, not what a gap in the chain does, not what an unexpressible change
answers. It records only that the question is no longer queued.

Until that amendment lands, the standing answer is unchanged.
`StatifierBlocks.Composite.Data`'s heading reads
`## What this module does not decide: a migration` (`composite/data.ex:159-169`)
- this file's earlier Notes and the requests filed against it paraphrase that
heading with "project" in place of "module"; the module's word is the one
above. `migrate_config/3` (`composite/data.ex:371`) still answers
`{:error, {:no_migration_from, from}}` unconditionally, and
`## The hygiene obligation a bump is for` (`composite/data.ex:171-181`) is
untouched by this Note.

### 2. `RQ-SF037-17`: an expansion is at each member's current version

The walk ruled it: an expansion is at each member's **current** version, as the
palette resolves it at expansion time; a template carries no version key; and
the `Collapse` gesture strips versions from what it lifts.

The clause about templates is already true of the code, and worth stating
because it is what makes the rest of the ruling reachable. A data declaration's
node template carries a type, an id suffix, `"config"` and `"slots"` and no
version, and `instantiate/2` builds each member with
`StatifierBlocks.Block.new/2` (`composite/data.ex:413-420`), whose
`:type_version` defaults to `1` (`block.ex:40`, `:49-57`).
`StatifierBlocks.Composite.expand/2` mints ids and copies each template block
through untouched (`composite.ex:395`).

The clause about resolution is read against what the compiler does with those
members: `expand_node/3` hands every member back to `resolve/2`
(`compiler.ex:576`; `resolve_member/3` at `:595-596`), so a member meets
`StatifierBlocks.Palette.resolve/2`'s version comparison
(`palette.ex:646-656`) exactly as a stored block does. Two core types are past
version 1 today - `core.send` (`core/send.ex:102`) and `core.wait`
(`core/wait.ex:39`) - so a subtree that names one and takes `Block.new/2`'s
default reaches that type's `migrate_config/2` rather than being read at the
type's current version. `StatifierBlocks.Palette.block/2`
(`palette.ex:596-608`) already builds a block at its type's
`current_version/0`, and is the shape the ruling points a declaration's
instantiation at. Making the instantiation say so is the implementing work the
ruling leaves to the requests that carry it; the ruling is what those requests
are measured against.

`Collapse` is not built (`sb-uzly` is the request), so the version-stripping
clause is a requirement on it rather than a description of code.

### 3. `RQ-SF038-13`: the derived callbacks stay core-only, and readers with a palette go through a palette

Section 6 of the Note at `:7464-7481` names this question and leaves it for
the SF038 walk (`:7479-7481`): whether a composite's derived `io/1` and
`outcomes/1` should see the host palette. Ruled: **the callbacks stay
core-only, and say so.**
`member_module/1` resolves a member's type name through
`Palette.fetch(Palette.core(), type)` (`composite.ex:608-613`), and
`### The one limitation in the derived io/1 and outcomes/1`
(`composite.ex:135-146`) is the moduledoc that states the consequence. No
`@callback` is added, removed or re-arity'd by this Note, and neither
derivation gains a palette argument.

What changes is the reader side. Every in-package reader that **has** a palette
resolves a composite's io and outcomes through it, via two arity-2 functions
`StatifierBlocks.Composite.io/2` and `StatifierBlocks.Composite.outcomes/2`
(`sb-9w7w`), which the decision forces rather than adds - they are the only way
a reader holding a palette can reach the exact answer without widening a
callback. A composite whose expansion root is a **host** type is therefore
exact wherever a palette is in hand, and the behaviour's defaults that
`:7473-7475` describes stay the answer only where none is. The environment walk
was already unaffected, for the reason `composite.ex:145-146` gives.

### 4. A derived `summary/1`

`sb-9w7w` also derives `summary/1` on a composite: the chips are the
declaration's `params`, minus those declared `hidden?: true`. `hidden?` is the
field-declaration flag at `block_type.ex:286` and `:379-398`, so a param the
author has already said no form renders is not a chip either - the same reading
`ViewModel` takes at `view_model.ex:160`. Nothing about the behaviour changes:
`summary/1` is already one of the optional callbacks, where
`0007-block-type-defaults.md:257-262` reads "seven are optional" and names it.
The `use StatifierBlocks.Composite` block injects `sentence/1` today
(`composite.ex:243-244`) and no `summary/1`; the derivation is added there,
beside it.

### 5. What `param_map` blames a member on, in both kinds

Both kinds attribute, and they attribute differently. Both are stated here
because the section describes neither.

- **A data composite's is by placeholder, and exact.** A node is attributed to
  param key *K* when the placeholders in its **own** `"config"`, not its slots'
  children, name exactly one distinct param, and to `nil` when they name none
  or more than one (`composite/data.ex:150-157`). It is exact because a
  template is the only thing that could have put the value there.
- **A module composite's is by value comparison.** `blamed_param/2`
  (`composite.ex:580-593`) blames the one param whose *distinguishing* value
  the member's config carries anywhere, where a value is distinguishing when it
  is not one of `nil`, `""`, `[]`, `%{}` or `false` (`composite.ex:596-599`).

And the collision, which both readings above reach for. **Ruled
(`RQ-SF038-14`): the module side takes the first param in *declaration
order*.** The declaration has an order to take: `:params` is a
`[t:StatifierBlocks.BlockType.field_decl/0]` (`composite.ex:204`), which is why
`config_schema/1` answers "`params`, in declaration order" (`composite.ex:79`,
`:228`).

The code does not take it yet, and this Note records that rather than reading
the ruling back as description. `blamed_param/2` answers `nil` when none **or
more than one** param matches (`composite.ex:590-593`), which the comment at
`composite.ex:570-572` calls "no single param is responsible", "the honest
answer in both directions". Nor could it take the ruling where it stands:
`params_of/2` (`composite.ex:500-506`) hands `blamed_param/2` a `Map.new/2`
over the declaration's list, so the order is already gone by the time the
comparison runs. The ruling therefore names two changes - carry the
declaration's order past `params_of/2`, and blame the first match rather than
refusing - and it is what a request making them is measured against, the way
item 2's ruling is. No request carries it today.

### 6. `use StatifierBlocks.InvokeStep, failure_outcomes: [...]`

The Note at `:3832` added the optional `failure_outcomes/1`, and
`StatifierBlocks.InvokeStep`'s `__using__` injects
`def failure_outcomes(_config), do: StatifierBlocks.InvokeStep.failure_outcomes()`
(`invoke_step.ex:172`), whose module-level default is `["error"]`
(`invoke_step.ex:236-237`). A family of steps that fails in more ways than that
has, today, one place to say so: an `@impl` on every member.

The macro's four options - `:invoke_type`, `:produces`, `:fields` and
`:palette` (`invoke_step.ex:126-136`) - therefore gain a fifth,
`:failure_outcomes` (`sb-a0xw`), which declares the family default once at the
`use` site; a host wrapper module over `InvokeStep` may set it for its whole
family. Absent, the injection is exactly what it is now. This adds a `use`
option, not a callback, and changes no default.

### 7. Named, not decided: a register-aware `sentence`

`StatifierBlocks.Core.Branch.sentence/1` answers
`"Decide: <the first arm's label>, otherwise"`, or `"Decide: otherwise"` when
`otherwise` is first (`core/branch.ex:245-252`). That reads at the block's own
altitude, which is the altitude the callback has: `sentence/1` is handed a
config and nothing else, and `StatifierBlocks.BlockType.sentence/2`
(`block_type.ex:1548-1556`) only chooses between calling it and falling back to
the type's label.

A reading at a host authoring view's altitude would want the register the
profile carries, so that `"Decide:"` is the word that host's authors use -
which is a `sentence/2` on the callback taking the profile beside the config,
or something in its place.
The walk declined to treat this as a seam and ruled it wording. Whether the
callback should gain that arity, whether the profile is the right second
argument, and whether the register belongs to the profile at all are one
profile-shaped question for a later record. **Nothing here decides it**, and no
request is filed for it.

Filed with `sb-uigm`, campaign SF038. This Note changes no code, adds no README
row and carries no `Status:` line, because it takes no decision this file has
not already taken or pointed at. Items 3 and 4 are implemented by `sb-9w7w`,
item 6 by `sb-a0xw`, and item 1's decision lands as `sb-ekkt`'s amendment with
`sb-mulk` behind it. Items 2 and 5 record rulings no request carries yet; each
names the change it is measured against.

## Amendment (2026-09-07): a composite may declare a pass-through slot - `slots:` on the `use`, a `"slots"` key on a data declaration - and the card draws an interior for it

**Status: accepted (2026-09-07, campaign SF038, bead `sb-nlo5`, recording
campaign-SF038's ruling `RQ-SF038-5` and the card half of `RQ-SF038-14`).** A
decision record merges at proposed under the campaign invariant; flipping it to
accepted is a separate gated request through the same `docs/adr/` gate, and
`sb-vjvq` carries it once `sb-q183` has landed. Additive: decisions 1-8 stand
as accepted, the Amendment of this date at `:6360` and the Amendment of this
date at `:6732` stand as accepted, and no text above this line is edited by
this section.

An amendment rather than a Note, because this file says four times that a
composite has no slot of its own and `RQ-SF038-5` gives it one. `:6500`
("`slots/1` is `[]`, and that is `RQ-SF037-3`"), the worked example's table row
at `:6702`, `:6721` ("a composite that exposes a slot of its own is a later
record's") and `:7030` are the four; `:7656`'s claim-table row records the same
thing for the data kind. This is the later record `:6721` was written for.

A **pass-through slot** is a slot the author fills on the composite's own card,
whose children the expansion carries into a named slot of a named member. This
record owns the declaration and nothing else: the spelling, what `slots/1` and
`io/1` answer, the splice rule, what a broken declaration does, and what the
card draws. Where the children land in the compile, what ids they carry there
and who owns a finding on one of them is `ADR-0004`'s amendment of this date
(`docs/adr/0004-compiler-provenance.md:3241`, `:3286`, `:3318`); where the
environment walk descends is `ADR-0011`'s amendment of this date
(`docs/adr/0011-typed-environment.md:2683`). Neither is restated here.
`sb-q183` builds all three.

### P1. The declaration: `slots:` on `use StatifierBlocks.Composite`

`use StatifierBlocks.Composite`'s five options (`lib/statifier_blocks/composite.ex:226-244`,
the macro at `:245`) gain a sixth, `:slots`, optional and defaulting to `[]`.
It is a **list of maps**, each with:

  * `:name` (**required**) - `t:StatifierBlocks.Block.slot_name/0`, the slot
    name the composite exposes and a stored document keys the author's children
    under. Unique within one declaration.
  * `:to` (**required**) - `{local_id, inner_slot}`, the local id of a member
    of `subtree/1` and the name of a slot on that member.
  * `:label` - the human label the card's interior draws. Defaults to `:name`.
  * `:arity` - a `t:StatifierBlocks.BlockType.slot_arity/0`. Defaults to
    `:any`.

`:label` and `:arity` are **forced, not added**: `c:StatifierBlocks.BlockType.slots/1`
answers a `[t:StatifierBlocks.BlockType.slot_decl/0]`
(`lib/statifier_blocks/block_type.ex:321`) and a `slot_decl/0` is the 3-tuple
`{name, arity, label}` (`:177`). Two of the three have to come from somewhere,
and the declaration is the only place that knows them.

`:any` is the right default rather than an inherited one, and the reason is
worth stating. The obvious alternative is to derive the arity from the mapped
inner slot's own `slots/1`, and it is wrong twice: resolving the member's
module needs a palette, which `slots/1` is not handed and which the derivation
behind the callback can only approximate through `StatifierBlocks.Palette.core/0`
(`composite.ex:497`, the limitation stated at `:154-176`); and the check the
derivation would be imitating **already runs anyway**. `ADR-0004`'s T1 first bullet says an
unfilled pass-through slot splices nothing, the mapped inner slot is empty, and
the member's own arity finding is raised on the expanded tree and re-anchored
onto the composite. Declaring `:any` therefore loses no check; declaring
anything narrower is the author's own constraint, stated once, on top of it.

### P2. The same declaration held as data: a declaration-level `"slots"` key

`StatifierBlocks.Composite.Data.declaration/1`
(`lib/statifier_blocks/composite/data.ex:319`) reads six row keys today -
`"type_name"`, `"version"`, `"params"`, `"subtree"`, `"palette_entry"`,
`"sentence"`. It gains a seventh, `"slots"`, optional and defaulting to `%{}`:
a **map of slot name to `[local_id, inner_slot]`**, a two-element JSON array
because JSON has no tuple. `:label` and `:arity` from P1 are spelled as the
optional keys of a map value where an author wants them, so the value is
either the two-element array or
`%{"to" => [local_id, inner_slot], "label" => ..., "arity" => ...}`, and the
array is sugar for the map with the two defaults. The decoded state carries the
same `slots` list P1's `use` writes, so `slots/2`
(`composite/data.ex:388`, which answers `[]` today) and `slots/1`
(`composite.ex:261`, likewise) answer the same thing from the same shape.

**This is a declaration-level key, and the template already has a node-level
key of the same name.** A template node is a map with string keys
`"type"`, `"id_suffix"`, `"config"` and `"slots"` (`composite/data.ex:127`),
where the node's `"slots"` is "optional, defaulting to `%{}`: a slot name to a
list of nodes" (`:148`), decoded at `:734` and carried into `node_template/0`'s
`:slots` field. That key is untouched by this section and keeps its meaning
exactly. The key this section adds is a **sibling of `"subtree"`**, not a key
inside it: it appears once per declaration, at the top level of the row
`declaration/1` is handed, and its values are pairs of strings rather than
lists of nodes. A reader who cannot tell which is meant should read the nesting
depth: the node-level one is reached only through `"subtree"`.

### P3. What `slots/1` answers, and what `io/1`'s `slot_accepts` answers

`slots/1` answers **the declared slots, in declaration order**, one
`slot_decl/0` per entry, and `[]` when nothing is declared - which is the whole
of today's behaviour and why this is an amendment by addition rather than a
replacement. `RQ-SF037-3`'s answer at `:6500` is the `slots: []` case, and it
stays the answer for every composite written before this section and every one
that declares nothing after it.

`io/1`'s `slot_accepts` is `%{}` today, for the reason `:146-147` gives - "the
composite declares no slots, so there is no slot name to accept into" - and the
code writes the literal (`composite.ex:521`). It now answers, for each declared
slot, that slot's name mapped to **the mapped inner slot's accepted kinds**,
read from the member the local id names. That resolution is the one the
derivation already runs over the members (`composite.ex:515`, `:519`), and it
inherits its one limitation unchanged (`composite.ex:154-176`): the **callback**
resolves members through `StatifierBlocks.Palette.core/0` (`composite.ex:497`),
so a mapped member whose type is a **host** type falls back exactly as `io/1`
already falls back for a host expansion root. This section adds no new fallback
value and no palette argument to the callback. A reader that holds a palette
reaches the exact answer through `StatifierBlocks.Composite.io/2`
(`composite.ex:476`, the palette first), the arity-2 function the Note of this
date at `:7980` decides.

### P4. The splice: the composite block's slot children, ids unchanged

For a composite block whose declaration maps slot `name` to
`{local_id, inner_slot}`, `Composite.expand/2` (`composite.ex:409`) answers the
subtree it answers today **with the composite block's own children under
`name` placed in the `inner_slot` slot of the member minted from `local_id`**,
in their stored order.

Those children are **not minted**. Minting is what turns a subtree's local ids
into document ids (`### The ids the subtree mints`, `:6444`); a pass-through
child arrived carrying a document id already. `mint/3` walks the subtree's own
blocks and their slot children (`composite.ex:657`); the spliced children are
placed outside that walk and pass through untouched, ids, configs, slots and
all. `ADR-0004`'s T2 (`docs/adr/0004-compiler-provenance.md:3286`) is where
that id's consequences downstream are decided; here it is a property of
`expand/2`.

An unfilled declared slot splices nothing and the mapped inner slot is left as
the subtree wrote it - which, by P5's third error, is empty.

### P5. Three declaration errors, and where each is raised

A declaration whose mapping does not fit its own subtree is broken, and this
section refuses three cases. Each is checked against the subtree's **own**
blocks and needs no palette:

1. **An unknown local id.** `:to`'s `local_id` names no block in `subtree/1`'s
   flattened list.
2. **An unknown inner slot.** The member exists, but its `slots` map has no key
   `inner_slot`. A subtree that means to receive children therefore writes the
   empty slot explicitly - `core.group id "blk_GX_then" slots %{"body" => []}`
   in P8 - and that is deliberate: the declaration author states where the
   children go, in the subtree, in the one place the mapping can be checked
   without resolving a type.
3. **A mapped inner slot the subtree also fills.** The member's `slots` map
   carries `inner_slot` with a **non-empty** list. This is the question
   `ADR-0004`'s T1 defers here ("whether such a declaration is admissible at
   all is `ADR-0002`'s question rather than this one's",
   `docs/adr/0004-compiler-provenance.md:3241`), and the answer is **no**. T1
   already fixes that the mapped inner slot "holds them and only them"; a
   declaration that also wrote children there would be two authors writing one
   list, with no rule for the order and no way for either to see the other. It
   is refused rather than merged, and a declaration that wants both writes a
   second member.

Two declared slots mapping to **one** inner slot is refused for the same
reason, as is a duplicate `:name`.

**Where each is raised differs by kind, and follows the kind's existing
practice.** A module composite's `subtree/1` is a function of the params, so
there is no subtree to check until `expand/2` has one: these refusals raise
from `expand/2`, beside `check_local_ids!/2` (`composite.ex:628`) and
`mint_id/3` (`:668`), in the same `ArgumentError` shape and for the same
reason - "the declaration is broken" is not a finding a document can carry. A
data composite's subtree is a static template, so `declaration/1` sees all
three statically and answers `{:error, [...]}` with the other declaration
errors, which is the moment `composite/data.ex:116-123` calls "the last moment a
malformed declaration can be refused". The data kind therefore refuses earlier
and the module kind refuses at the first expansion; neither admits a broken
mapping.

The one check that is **not** here is the inner slot's own type: whether the
member's declared type really has a slot by that name is a question about a
resolved module, and a template's `"type"` "is not checked here - the palette
is not built yet" (`composite/data.ex:137-140`). That check is the compiler's
on the expanded tree, exactly as an unresolvable member type already is.

### P6. The card draws an interior for the declared slot only

`ADR-0005`'s 7E (`docs/adr/0005-liveview-editor.md:8601`) reads "**A composite
draws as an ordinary leaf card.**" That sentence is amended **by addition**, and
the addition is: *a composite draws as a leaf card unless its declaration names
a slot, and then it draws one interior per declared slot, in declaration order,
under the declared label.* 8E (`:8612`) scopes itself to campaign SF037 in its
own words - "**A composite's `slots/1` is empty, in campaign SF037**" - and
names pass-through slots "a later campaign's question"; this is that campaign
and that answer.

Nothing else about 7E changes, and its claim survives intact: the drawing code
still does not learn the word "composite". A composite that declares a slot
draws its interior the way **any** type with a slot draws one, from the
`slot_decl/0` its `slots/1` answers, through the same `ViewModel.Node` path;
that is precisely what P1's `:label` and `:arity` are for. The card's chips and
sentence are unchanged. An author drops into that interior the way they drop
into any slot, and what they may drop is `slot_accepts` (P3), which is the
mapped inner slot's own answer.

The addition is recorded here rather than in `ADR-0005` because the
declaration is this record's and campaign SF038's sections on `ADR-0005` belong
to other requests; 7E and 8E are named, quoted and amended by cross-cite, and
no text in that file is edited by this section.

`RQ-SF038-14`'s card half is this clause. **No layout mode is added to the
package editor by it**, and none is implied: a declared slot is a component's
own declaration, drawn by the drawing code that already exists.

### P7. Expand carries the children

The `Expand` gesture replaces a composite block in the document with its
expansion. It writes **the same tree `expand/2` answers**, pass-through
children included, in the mapped inner slot, with their ids unchanged - so the
gesture moves the author's blocks and rewrites none of them.

The property that buys is the one campaign SF038 is measured on: the compiled
chart of a document holding a composite with a filled pass-through slot is
byte-identical to the chart of the same document after `Expand`, because
`Expand` writes what Resolve would have built and `ADR-0004`'s T4
(`docs/adr/0004-compiler-provenance.md:3370`) says the compiled bytes are the
same before and after. A child that was addressable only through the
composite's card before the gesture is addressable in its own right after it,
at the same id, which is the same continuity `ADR-0004`'s T2 rests on.

### P8. Worked example: "Guarded section", as a module

The signup domain, and the same composite `ADR-0011`'s worked example
(`docs/adr/0011-typed-environment.md:2802`) reads the walk against, so the two
records describe one artefact.

    use StatifierBlocks.Composite,
      name: "myapp.guarded_section",
      params: [
        %{key: "applicant_path", type: :string, label: "Record the applicant at",
          required?: true, default: "", datamodel_path?: true},
        %{key: "failure_path",   type: :string, label: "Record the failure at",
          required?: true, default: "", datamodel_path?: true}
      ],
      slots: [
        %{name: "body", to: {"then", "body"}, label: "Then"}
      ]

    subtree(params):
      myapp.signup_step  local id "call"
        config  %{"assign_to" => params["applicant_path"]}
        slots   %{"on_error" => [
          core.assign  local id "guard"
            config  %{"path" => params["failure_path"], "value" => "failed"}
        ]}
      core.group  local id "then"
        slots   %{"body" => []}

for a composite block whose id is `blk_GX`, which mints `blk_GX_call`,
`blk_GX_guard` and `blk_GX_then`. `core.group` declares a `body` slot at `:any`
(`lib/statifier_blocks/core/group.ex:37-41`) and `core.assign` declares `path`
and `value` (`lib/statifier_blocks/core/assign.ex:64-75`). `"then"` is a local
id in the subtree and `"body"` is a key of that member's `slots` map written
empty, so none of P5's three errors fires.

**`:to`'s first element is the LOCAL id, not the minted one**, and this example
spells it that way deliberately. Two existing worked examples print the
*minted* id in the position where `subtree/1` writes a local one - `### Worked
example: "Guarded step"` at `:6665` (`core.invoke id "blk_GS_call"` for a
`blk_GS` composite) and `ADR-0011`'s at
`docs/adr/0011-typed-environment.md:2827-2838` (`core.group  id "blk_GX_then"`,
and
`to: {"blk_GX_then", "body"}` with it). Neither is edited by this section and
neither is a decision about the mapping; but a local id spelled that way is not
merely redundant, it is **refused**: `check_local_ids!/2` raises on a local id
that starts with `"blk_"` (`composite.ex:628`), and a data declaration's
`"id_suffix"` must match `~r/\A[a-z0-9]+(_[a-z0-9]+)*\z/`
(`composite/data.ex:141-146`), which no `blk_GX_then` matches. The mapping
names what `subtree/1` writes and what `"id_suffix"` spells, which is the same
string in both kinds, and `sb-q183` builds it that way.

The author's document holds `blk_GX` with one child, `blk_notify`, in its
`body` slot. What the derived block type answers:

| Callback | Answer | Where it comes from |
|---|---|---|
| `config_schema/1` | the two params above | the declaration |
| `slots/1` | `[{"body", :any, "Then"}]` | P1 and P3 - one entry, the declared label, the default arity |
| `io/1`'s `slot_accepts` | `%{"body" => the kinds core.group accepts into body}` | P3, resolved the way the derivation already resolves members, and exact here because `core.group` is a core type |
| `expand/2` | the two members above, with `blk_notify` in `blk_GX_then`'s `body` slot | P4 - `blk_GX_call`, `blk_GX_guard` and `blk_GX_then` are minted, `blk_notify` is not |
| `emit/2` | raises | no `blk_GX` survives Resolve |

Compared with `### Worked example: "Guarded step"` at `:6665`, exactly one row
of that example's table moves: `slots/1`, which reads `[]` there at `:6702`.
"Guarded step" declares no `slots:`, so its row stays right for it.

### P9. The same declaration, held as data

The identical composite, as a row a tenant saved, in the shape
`### The subtree template's data shape` (`:7090`) fixes, with P2's key added:

```json
{
  "type_name": "myapp.guarded_section",
  "version": 1,
  "params": [
    {"key": "applicant_path", "type": "string", "label": "Record the applicant at",
     "required?": true, "default": "", "datamodel_path?": true},
    {"key": "failure_path", "type": "string", "label": "Record the failure at",
     "required?": true, "default": "", "datamodel_path?": true}
  ],
  "slots": {"body": {"to": ["then", "body"], "label": "Then"}},
  "subtree": [
    {"type": "myapp.signup_step", "id_suffix": "call",
     "config": {"assign_to": {"$param": "applicant_path"}},
     "slots": {"on_error": [
       {"type": "core.assign", "id_suffix": "guard",
        "config": {"path": {"$param": "failure_path"}, "value": "failed"}}
     ]}},
    {"type": "core.group", "id_suffix": "then", "slots": {"body": []}}
  ]
}
```

Both `"slots"` keys are in that row, and the nesting says which is which: the
declaration-level one is a sibling of `"subtree"` and its value is a mapping;
the node-level ones are inside `"subtree"` and their values are lists of nodes.
The plain-array sugar of P2 spells the same mapping as
`"slots": {"body": ["then", "body"]}`, with the label defaulting to `"body"`.

`declaration/1` refuses this row if `"then"` is not a declared `"id_suffix"`,
if the node it names carries no `"body"` key in its own `"slots"`, or if that
key carries a non-empty list - P5's three errors, all three statically visible
here because the template is static. The mapping and the module kind's are the
same string in the same position, which is P8's last paragraph.

A tenant who saves this row gets a block type whose card has an interior, from
data, with no module generated for it - `### Per-instance module generation is
rejected` (`:7155`) is untouched.

### What this section does not decide

- **Where the children land in the compile, what ids they carry, who owns a
  finding on one**: `ADR-0004`'s amendment of this date, T1-T4.
- **Where the environment walk descends and what it reads there**:
  `ADR-0011`'s amendment of this date, sections 1-3.
- **A `"migrations"` list on a data declaration**: `sb-ekkt`'s amendment on
  this file, which the Note at `:7925` points at.
- **How `Collapse` proposes a pass-through slot.** `RQ-SF038-5` relaxes
  `ADR-0005`'s 13E so that a selection whose subtree holds an unfilled slot is
  admissible and proposed as a pass-through slot rather than refused, and the
  children are not lifted. The gesture is `ADR-0005`'s and `sb-uzly`'s; this
  section fixes only the declaration such a proposal must produce.
- **Nesting a composite in a pass-through slot**: it is admitted, and
  `ADR-0004`'s T1 third bullet says what happens to it. Nothing here limits the
  depth.
- **A slot on a composite that is not a pass-through**: there is no such thing.
  Every slot a composite declares maps to a member, and a composite still
  carries no interior of its own.

Filed with `sb-nlo5`, campaign SF038. Implemented by `sb-q183`; flipped to
accepted by `sb-vjvq` once it has landed.

## Amendment (2026-09-07): a data composite's declaration may carry a `"migrations"` list - `rename`, `drop` and `default` steps, walked once from the stored version to the current one

**Status: accepted (2026-09-07, campaign SF038, bead `sb-ekkt`, recording
campaign-SF038's ruling `RQ-SF038-3`, which was `RQ-SF037-16`).** A decision
record merges at proposed under the campaign invariant; flipping it to accepted
is a separate gated request through the same `docs/adr/` gate, and `sb-vjvq`
carries it once `sb-mulk` has landed. Additive: decisions 1-8 stand as
accepted, the Amendment of this date at `:6360`, the Amendment of this date at
`:6732` and the Amendment of this date at `:8093` stand as they stand, and no
text above this line is edited by this section.

An amendment rather than a Note, because this file says three times that a
declaration held as data fixes **no** migration key and this section fixes one.
`:7293-7299` names it open, `:7894-7900` records it queued, and
`StatifierBlocks.Composite.Data`'s own heading
`## What this module does not decide: a migration`
(`lib/statifier_blocks/composite/data.ex:180-190`) is the third. The Note at
`:7925` ruled the question and pointed at this section by name - its item 1
says in as many words that it "fixes nothing about that shape": not the step
keys, not the order steps are applied in, not what a gap in the chain does, not
what an unexpressible change answers. This section fixes all four. The
pass-through amendment of this date lists the same pointer among the things it
does not decide (`:8435-8436`).

### The arity this section means

The behaviour's callback is `migrate_config/2`
(`lib/statifier_blocks/block_type.ex:507-508`), and every module block type
writes it at that arity. `StatifierBlocks.Composite.Data` is the one stateful
module this package ships, so it implements the behaviour's callbacks **at one
higher arity, with the state first** (`composite/data.ex:36-41`) and
`StatifierBlocks.Palette.call/4` does the arithmetic. The function this section
changes is therefore `Composite.Data.migrate_config/3`
(`composite/data.ex:403-404`); "`migrate_config/2`" below means the callback
that seam answers for. The request text and this file's earlier prose use the
`/2` spelling for both; the module's arity is `/3`, exactly as the Note at
`:7940-7943` already records.

### M1. The key: `"migrations"`, optional, a sibling of `"subtree"`

The declaration table at `composite/data.ex:56-65` lists six keys today -
`"type_name"`, `"version"`, `"params"`, `"subtree"`, `"palette_entry"` and
`"sentence"` - and the pass-through amendment of this date adds a seventh,
`"slots"` (`:8155`). This section adds an eighth, `"migrations"`, **optional and
defaulting to `[]`**: a list of migration steps, ordered, read by
`StatifierBlocks.Composite.Data.declaration/1` (`composite/data.ex:319`) and
carried on the decoded `state` beside `version`.

`[]` is exactly today's behaviour, which is why this is an amendment by
addition: a declaration that writes no `"migrations"` key, or writes the empty
list, keeps the unconditional refusal `composite/data.ex:404` answers now.

**`"migrations"` is a declaration-level key and `"default"` inside it is not
the `"default"` a param writes.** A param's `"default"` is decision 7's
`field_decl/0` key, one level inside `"params"`, and it is the value a *new*
block starts with. A step's `"default"` is one level inside `"migrations"` and
it is the value an *old stored* block's config gains. A reader who cannot tell
which is meant should read the nesting depth, which is the same disambiguation
the pass-through amendment states for its two `"slots"` (`:8171-8183`).

### M2. The step shape

Each entry of `"migrations"` is a map with string keys:

    %{
      "from"    => 1,
      "rename"  => %{"limit" => "amount_limit"},
      "drop"    => ["legacy_mode"],
      "default" => %{"currency" => "USD"}
    }

  * **`"from"`** (**required**) - a positive integer, the `type_version` this
    step migrates *from*. The step carries a config at version `from` to
    version `from + 1`.
  * **`"rename"`** - a map of old config key to new config key, both non-empty
    strings. The value moves; nothing else about it changes.
  * **`"drop"`** - a list of non-empty strings, the config keys removed.
  * **`"default"`** - a map of config key to a JSON value, the keys added with
    that value.

The three parts are each optional and **at least one must be present**. A step
with none of them is refused rather than treated as a no-op: its `"from"` would
claim a version bump that changed nothing, and a version bump that changed
nothing is the hygiene obligation's business (`composite/data.ex:192-203`), not
a migration's. A step map carrying any key other than these four is refused
**by name**, which is the practice `decode_param/1` already follows for a param
(the Note at `:7682-7701`).

**Within one step the three parts are applied in a fixed order: `rename`, then
`drop`, then `default`.** Rename runs first so that `drop` and `default` are
written in the names the step is producing rather than the names it is
consuming, which is the reading a declaration author expects when the two are
read top to bottom. The one genuinely ambiguous overlap - a key named by both
`"drop"` and `"default"` in one step - is a contradiction rather than an
ordering question, and is refused at `declaration/1` (M5).

### M3. The chain: ascending `from`, contiguous, applied once

`migrate_config/3` is handed the stored version and the stored config, and it
applies **every step whose `"from"` is at or above the stored version and below
the declaration's `"version"`, in ascending `"from"` order**, answering
`{:ok, config}` with the result.

The steps' `"from"` values are **strictly ascending and contiguous**, and the
last step's `"from"` is `version - 1`. So a declaration at `"version"` 3 whose
earliest step is `"from" => 1` carries exactly two steps, `1` and `2`, and a
stored block at version 1 walks both while a stored block at version 2 walks
one. A duplicate `"from"`, an out-of-order `"from"`, a `"from"` at or above
`"version"`, and a **gap** - a version between the earliest step and `"version"`
with no step - are each refused at `declaration/1` (M5). There is no partial
chain: a list that cannot carry its own earliest version to its current one is
broken, not usable-in-part.

**This is not a change to `resolve/2`'s one-call rule.**
`StatifierBlocks.Palette.resolve/2` calls `migrate_config` **once**, straight
from the stored version to current, "never a version-by-version ladder"
(`lib/statifier_blocks/palette.ex:652-657`, the call at `:693`). That sentence
is about the seam, and it is untouched: the ladder this section describes runs
**inside** the one call, over a list the declaration holds, and the seam still
sees a single `{:ok, config}` or a single `{:error, reason}`. Nothing in
`palette.ex` changes.

### M4. What makes a key known: the chain is checked backwards from the params

"A step naming an unknown key is refused" needs a definition of known, and a
data composite has one without a palette: `config_schema/1` is the params
(`composite/data.ex:43-48`), so the config keys of the **current** shape are the
declared param keys.

The check runs the chain **backwards**. Start with the set of declared param
keys - the shape at `"version"` - and undo each step in **descending** `"from"`
order:

  * undo `"default"`: each key must be **in** the running set; remove it.
  * undo `"drop"`: each key must be **absent** from the running set; add it.
  * undo `"rename"`: each new name must be **in** the set and each old name
    **absent**; replace the new name with the old.

Within one step the undo order is the reverse of M2's: `default`, then `drop`,
then `rename`. What remains when the earliest step has been undone is the key
set of the shape at that step's `"from"`, and every violation along the way is
a step naming a key the shape does not have at that point - which is what
"unknown key" means here.

Running it backwards rather than forwards is what makes it checkable at all: a
declaration states its current params and does not state the shape it started
from, so the current shape is the only end of the chain that is known. A
declaration that wants to see the derived starting shape reads it off the same
walk.

**A step's values are not type-checked here.** A `"default"`'s value is a JSON
value and this section does not require it to match the param's declared type,
for the reason a template node's `"config"` values are not checked either
(`composite/data.ex:137-140`): the migrated config meets decision 7's refusals
at the compile, exactly as a stored config does, and a check here would
duplicate one that already runs and can already fail.

### M5. Every refusal is at `declaration/1`, entry-build time

`**Every refusal is here, at entry-build time, and not at call time.**`
(`composite/data.ex:283-288`) is the module's rule, forced by decision 4 and
decision 3 together, and this section adds nothing that escapes it. The
`"migrations"` refusals join the error assembly at `composite/data.ex:328-331`
beside `version_errors/1` (the call at `:330`, the definition at `:482-486`),
and `declaration/1` answers `{:error, [...]}` with them. A host registers
`{module, state}` only on the `:ok`, so a palette can never hold a broken
migration chain and `migrate_config/3` can never meet one.

The refusals, in one list:

1. `"migrations"` is present and is not a list.
2. A step is not a map, or carries a key other than `"from"`, `"rename"`,
   `"drop"` and `"default"`.
3. A step has no `"from"`, or its `"from"` is not a positive integer.
4. A step carries none of `"rename"`, `"drop"` and `"default"` (M2).
5. A `"rename"` that is not a map of non-empty string to non-empty string, a
   `"drop"` that is not a list of non-empty strings, or a `"default"` that is
   not a map with string keys.
6. A key named by both `"drop"` and `"default"` in one step (M2).
7. The `"from"` values are not strictly ascending, or the last is not
   `version - 1`, or there is a gap between the earliest and `version` (M3).
8. A step names an unknown key by M4's backwards walk.

Each is checked against the declaration's **own** params and its own list and
needs no palette, which is the same property the pass-through amendment's three
declaration errors have (`:8227-8232`).

### M6. Below the earliest step, the refusal stands

A stored block whose `type_version` is **below the earliest step's `"from"`**
gets `{:error, {:no_migration_from, from}}` - the answer
`composite/data.ex:404` gives today, unchanged, carrying the stored version.
That is deliberate and it is the point of the whole shape: a declaration says
which versions it can carry forward, and a version it never wrote a step for is
one it does not claim to understand. Answering such a block with a derived
`{:ok, config}` is "exactly the answer `ADR-0007`'s refusal exists to refuse"
(`:7297-7299`), and this section does not start doing it.

There is no arm for a stored version **above** `"version"`: `resolve/2` answers
`{:error, {:block_type_too_new, ...}}` before the callback is reached
(`palette.ex:648-651`).

### M7. What a step cannot express is still a refusal

`rename`, `drop` and `default` are the whole vocabulary. There is no value
transform, no merge of two keys into one, no split of one into two, no
conditional and no per-value computation - the same shape of decision, and for
the same reason, as the whole-value substitution the placeholder vocabulary
fixes (`composite/data.ex:151-169`): a declaration held as data cannot hold a
function, and the gesture that produces these declarations emits whole values.

So a change no step can express has an answer already, and this section keeps
it: the declaration writes no step for that version, the stored block gets
`{:no_migration_from, from}` by M6, and a host that needs more writes a
`use`-composite module and its own `migrate_config/2`. That is the same cost
the declaration table already books for a cross-param `validate_config/1` and a
non-substituting sentence (`composite/data.ex:67-77`), and it is a cost of the
data shape rather than an oversight.

### M8. A module composite is untouched

`use StatifierBlocks.Composite` gains **no** `migrations:` option. A module
composite already has the whole of Elixir available for the job: it writes
`migrate_config/2` itself, at the behaviour's arity, and `ADR-0007`'s injected
refusal (`lib/statifier_blocks/block_type.ex:139`) stays the default for one
that does not - which is exactly what `StatifierBlocks.Core.Send` and
`StatifierBlocks.Core.Wait` do with theirs today
(`lib/statifier_blocks/core/send.ex:112-113`,
`lib/statifier_blocks/core/wait.ex:60-61`). This section is the data kind's
answer to a question the module kind never had.

Nor does it touch the hygiene obligation (`composite/data.ex:192-203`).
`"version"` stays **required**, and a host that changes a data composite's
`params` or `subtree` still bumps it. A `"migrations"` list covers the
config-shape half of a bump - what a stored block's config becomes - and says
nothing about the subtree half, which is why the two coexist rather than one
replacing the other. A bump with a subtree change and no config-shape change
writes no step for that version and refuses stored blocks at it, deliberately.

### M9. Worked example: "Authorize with a deadline", renamed and then defaulted

A card-processing tenant saved a composite at version 1 with a `limit` param.
At version 2 the tenant renamed it `amount_limit`; at version 3 the tenant
added a `currency` param. The declaration registered today reads:

    %{
      "type_name" => "myapp.authorize_with_deadline",
      "version" => 3,
      "params" => [
        %{"key" => "amount_limit", "type" => "integer",
          "label" => "Amount ceiling", "required?" => true, "default" => 0},
        %{"key" => "currency", "type" => "string",
          "label" => "Currency", "required?" => true, "default" => "USD"},
        %{"key" => "deadline", "type" => "duration",
          "label" => "Deadline", "required?" => false, "default" => ""}
      ],
      "migrations" => [
        %{"from" => 1, "rename" => %{"limit" => "amount_limit"}},
        %{"from" => 2, "default" => %{"currency" => "USD"}}
      ],
      "subtree" => [
        %{"type" => "myapp.authorize", "id_suffix" => "call",
          "config" => %{"amount_limit" => %{"$param" => "amount_limit"},
                        "currency" => %{"$param" => "currency"}}},
        %{"type" => "core.wait", "id_suffix" => "deadline",
          "config" => %{"duration" => %{"$param" => "deadline"}}}
      ]
    }

M4's backwards walk over it: start from `{amount_limit, currency, deadline}`;
undo the `"from" => 2` step's `"default"`, leaving `{amount_limit, deadline}`;
undo the `"from" => 1` step's `"rename"`, leaving `{limit, deadline}`. That is
the version-1 shape, every step named a key its shape had, and `declaration/1`
answers `{:ok, state}`.

A block stored at `type_version` 1 with
`%{"limit" => 500, "deadline" => "PT30S"}` resolves through
`StatifierBlocks.Palette.resolve/2`, which calls `migrate_config` once with
`from` 1. Both steps run, ascending:

    %{"amount_limit" => 500, "currency" => "USD", "deadline" => "PT30S"}

The returned block's `type_version` is left **as stored**, in memory only, and
nothing is written back - `resolve/2`'s existing rule (`palette.ex:659-664`),
which this section does not touch.

A block stored at `type_version` 2 walks the second step alone and gains
`"currency"`. If the tenant had never written the `"from" => 1` step, a block
stored at version 1 would answer `{:error, {:no_migration_from, 1}}` by M6,
and `resolve/2` would report `{:error, {:migration_failed, block.id,
{:no_migration_from, 1}}}` - the shape it already reports.

### What this section does not decide

- **Whether a migration is ever persisted.** It is not: decision 8's
  in-memory-only rule is untouched, and `resolve/2` still "never calls
  `Document.to_json/1`, `from_json/1`, or anything else that could persist"
  (`palette.ex:659-664`). Persisting is the caller's decision, as it was.
- **A migration for the subtree half of a bump.** M8 says why the hygiene
  obligation stands beside this key rather than being replaced by it; a bump
  whose subtree changed and whose config shape did not still refuses stored
  blocks, and whether that should be relaxed is not asked here.
- **A `migrations:` option on `use StatifierBlocks.Composite`.** M8: the
  module kind writes the callback.
- **Any richer step.** M7: a value transform, a merge, a split or a
  conditional has no spelling, and adding one is a later record's.
- **How the editor or a host surfaces a migration.** Nothing here is drawn,
  and no `ADR-0005` clause is reached.
- **Any change to the fourteen `@callback`s.** None is added, removed or
  re-arityed; `migrate_config/2` keeps the signature at `:507-508` and its
  optional-callback row at `:46`.

Filed with `sb-ekkt`, campaign SF038. Implemented by `sb-mulk`; flipped to
accepted by `sb-vjvq` once it has landed.

## Note (2026-09-07): a composite's derived recipe carries its type's palette entry, so the duplicate-order refusal exempts exactly that pair

This Note records campaign SF038's ruling `RQ-SF038-26`, taken by the
operator on 2026-09-07 (bead `sb-4zyk`) - the form this file already uses
for the SF038 walk's rulings at `:7921-7923`. It is a reading of `main` at
`b65a1d5`. It carries no `Status:` line and flips nothing, it edits no text
above this line, and it adds no callback, option or declaration key: the
registration it exempts is already legal by this file's own rule, and the
ruling settles which of the two palette builders was reading that rule
correctly.

### 1. The pair, and why it is one card at one order

A composite's declaration derives a `StatifierBlocks.Recipe` at
`<Module>.Recipe` (`lib/statifier_blocks/composite.ex:333-334`) whose
`palette_entry/0` is the block type's own. Not a copy of it and not a second
entry beside it, but a delegation:

    def palette_entry, do: unquote(owner).palette_entry()

(`composite.ex:349`), which `test/statifier_blocks/composite_test.exs:823-825`
("`palette_entry/0` is the block type's") pins by equality. The
`use StatifierBlocks.Composite` Amendment of this date says the same in prose
under `### The derived recipe` (`:6599-6615`) and draws the conclusion this
Note starts from: a host may register the composite in `types` **and** its
derived recipe in `recipes`, "so a composite registered in both is legal and
draws two entries" (`:6612-6613`). `composite_test.exs:830-845` ("a composite
registers in a palette like any other type") exercises that registration.

Two entries, then, but **one card at one order**: both answer, through the
same `palette_entry/0`, with the same `%{label:, group:, order:}` map. One
label, in one group, at one number - registered twice.

### 2. What the refusal is for, and why this pair sits outside it

`StatifierBlocks.Palette.refute_duplicate_orders!/2`
(`lib/statifier_blocks/palette.ex:450-471`) reads types and recipes together,
groups the entries that declare an `order` by `{group, order}`, and raises on
the first key whose entries collide. The reason is in the moduledoc's
`## Ordering a group` (`:72-106`) and at length in the comment above the
function: `ADR-0005` decision 10 sorts a palette-browser group by `order`, so
two entries sharing one number "leave the pick between them to whatever the
sort happened to do", and "there is no degraded reading of 'both are
seventh'" (`:404-408`).

That is a reason about two entries an author can **tell apart**. Whichever
the sort puts first, the author reads a different card there, and the
palette's order changes between releases for no stated cause. A type and its
own derived recipe cannot be told apart: the sort's choice between them
changes nothing an author can observe, because the two entries answer with
the same map. The refusal has no work to do on that pair, and refusing it
would make a registration this file calls legal impossible to mount.

### 3. The exemption, stated

**Two palette entries sharing a `{group, order}` collide, unless they are
exactly two and one is a `types` entry whose module is a composite while the
other is that same composite's own derived recipe registered in `recipes`.**
That pair is admitted. Everything else stays refused, unchanged, and for the
reason section 2 gives:

- two `types` entries sharing the number, including two type names
  registered for one composite module;
- two `recipes` entries sharing it;
- a `types` entry and a hand-written recipe module that is not that type's
  derived one, even one whose `palette_entry/0` answers the same map;
- a `types` entry and a *different* composite's derived recipe;
- three or more entries at one number, whichever two of them happen to be a
  derived pair.

The pair is identified by **both halves of the derivation**: the recipe's
module is the `<Module>.Recipe` the `use` created (`composite.ex:333-334`)
**and** its `palette_entry/0` answers the type's entry. Neither half alone
is the ruling: entry equality alone admits two unrelated modules that happen
to declare one card, and the module link alone admits a hand-written
`Foo.Recipe` that is not derived from `Foo` at all
(`palette.ex:487-493`, and the comment at `:433-445`).

Today the exemption can only fire for a module composite:
`StatifierBlocks.Composite.Data` derives no recipe - `data.ex` names none -
and the pair test's own guard reads a plain module rather than a
`{module, state}` entry (`palette.ex:487-488`). Whether a data composite
should derive a recipe is not asked here.

### 4. Both builders run the same check

Before this ruling the check ran in `from_modules/2` alone, so the
registration this file calls legal was refused by that builder and admitted
by `new/2` - and `composite_test.exs:830-845` passed only because it builds
its palette with `new/2` (`:831-835`). Two constructors of one value may not
disagree about which palettes exist, so the ruling closes the split: **both
builders run the same check, with the exemption above.** They do, as of
`sb-ba15` (`8b6105a`): the check moved into `new/2` (`:178-189`), which
`from_modules/2` (`:393-402`) builds through, and `new/2`'s own doc records
both the refusal and the admitted pair (`:163-170`).

This Note fixes what the check must decide. How the pair is recognised in
code is `sb-ba15`'s, and the shape above is that request's as it landed.

### 5. What this Note does not decide

- **Whether a host should register both.** `:6613-6615` stands as written:
  the derived recipe is a compatibility surface for a host mid-migration,
  and a host that registers both is choosing to show two. The ruling says
  that choice mounts, not that it is the one to make.
- **What a palette browser draws for the pair.** Nothing here
  de-duplicates anything or adds a drawing rule; two registered entries are
  two entries, and what a browser does with two entries carrying one card is
  `ADR-0005`'s question, unasked here.
- **The message, or the skip rule.** An entry whose module is not loaded,
  exports no `palette_entry/0`, or declares no `order` is still skipped
  rather than refused (`palette.ex:495-503`), and a real collision still
  names both entries by name and module.
- **Where the check runs.** That a builder runs it is the decision; which
  function holds the code is not.
- **Any change to the fourteen `@callback`s, or to `Composite`'s
  declaration keys.** None is added, removed or re-arityed.

Filed with `sb-4zyk`, campaign SF038, recording the operator's ruling
`RQ-SF038-26` of 2026-09-07. Implemented by `sb-ba15`, landed at `8b6105a`.

## Note (2026-09-07): the pass-through and migrations amendments are flipped to accepted, their cites re-counted, and three of their own witnesses superseded by the code they asked for

Two amendments on this file are flipped to **accepted** by `sb-vjvq`, in the
order this file carries them:

- the Amendment of 2026-09-07 *a composite may declare a pass-through slot*
  (`:8093`), whose status line at `:8095` was the one word changed there.
  `sb-q183` (PR 422, `main` `e61890a`) built `P1` to `P9`.
- the Amendment of 2026-09-07 *a data composite's declaration may carry a
  `"migrations"` list* (`:8452`), whose status line at `:8454` was the one word
  changed there. `sb-mulk` (PR 425, `main` `aa0d755`) built `M1` to `M9`.

No other line of either section, and no line above either of them, is edited.
Read at `main` `d6fb241`.

### 1. The sentences the flips falsify, met here rather than edited

- The pass-through amendment's status paragraph, "flipping it to accepted is a
  separate gated request ... and `sb-vjvq` carries it once `sb-q183` has
  landed" (`:8098-8099`), and its closing line, "Implemented by `sb-q183`;
  flipped to accepted by `sb-vjvq` once it has landed" (`:8450-8451`). Both are
  now performed rather than pending, and both stand.
- The migrations amendment's matching pair at `:8457-8459` and `:8765-8766`.
  Same reading, with `sb-mulk` in `sb-q183`'s place.
- The migrations amendment's third witness that this file "fixes no migration
  key": `## What this module does not decide: a migration` at
  `composite/data.ex:180-190`. That heading is **gone from the code**, replaced
  by `## The declaration-level "migrations" key` (`composite/data.ex:202-274`),
  which is `M1` to `M8` written down where the heading was. The witness is
  superseded by the thing it was witnessing the absence of; the record's
  sentence naming it is unedited. The other two witnesses, `:7293-7299` and
  `:7894-7900`, are prose in this file and stand as written.
- The pass-through amendment's four witnesses that a composite has no slot of
  its own - `:6500`, `:6702`, `:6721` and `:7030`, with `:7656`'s claim-table
  row for the data kind - all stand, unedited, and are read with `P3`: `[]`
  remains `slots/1`'s answer for every composite that declares no slot, which
  is every composite written before `RQ-SF038-5`.

### 2. What the code answers, per clause, at `d6fb241`

Pass-through:

| Clause | Where it is, at `d6fb241` |
|---|---|
| `P1`, `:slots` on the `use` | `composite.ex:260-266` (the option), `:267` (the macro), `:215-229` (`pass_through_decl/0` and `declaration/0`), `:753-800` (`normalize_slots!/1`, the duplicate-`:name` refusal at `:796`) |
| `P2`, the `"slots"` row key | `composite/data.ex:986-1003` (`decode_slots/4`), `:1011-1030` (`decode_slot/2`, the array and the map-with-`"to"` sugar, `"label"` and `"arity"` defaulted), `:500` (`slots/2`) |
| `P3`, `slots/1` and `slot_accepts` | `composite.ex:283` (the injected `slots/1`), `:496-499` (`derived_slots/1`), `:654-656` (`slot_accepts/4`, `%{}` for a composite declaring none) |
| `P4`, the splice, ids unchanged | `composite.ex:441-470` (`expand/2`), `:880-906` (`splice/3` and `put_children/4`), `:910-918` (`mint/3`, which the spliced children are placed outside of) |
| `P5`, the three declaration errors | module kind: `composite.ex:862-875` (`check_mapping!/3`) beside `check_local_ids!/2` (`:826`) and `mint_id/3` (`:920`); data kind: `composite/data.ex:1072-1085` and `Composite.mapping_errors/2` (`composite.ex:512-530`), assembled into `declaration/1`'s error list at `composite/data.ex:429-436`. Two slots mapped to one inner slot is `duplicate_target_errors/1` (`composite/data.ex:1050-1066`) |
| `P6`, the card's interior | drawn from the `slot_decl/0` `slots/1` answers, through the path any slotted type takes; no drawing code learns the word "composite", and no layout mode is added |
| `P7`, Expand carries the children | `expand/2` is the one expansion function and Expand writes what it answers |

Migrations:

| Clause | Where it is, at `d6fb241` |
|---|---|
| `M1`, the key | `composite/data.ex:202-274` (the declaration prose), `:309-331` (`migration_step/0` and the state), `:429-449` (read by `declaration/1`) |
| `M2`, the step shape and `rename`/`drop`/`default` order | `composite/data.ex:1122-1230` (decode and refuse by name), `:540-553` (`apply_step/2`, in that order) |
| `M3`, the chain | `composite/data.ex:526-535` (`migrate_config/3`: every step at or above `from` and below `version`, ascending), `:1239-1262` (`chain_errors/2`) |
| `M4`, the backwards walk | `composite/data.ex:1264-1345` (`unknown_key_errors/3`, `undo_step/2` and the three undo arms) |
| `M5`, every refusal at `declaration/1` | `composite/data.ex:1094-1120` (`decode_migrations/4`), assembled at `:429-436` |
| `M6`, below the earliest step | the `_none_or_starting_above` arm at `composite/data.ex:531-532`, answering `{:error, {:no_migration_from, from}}` |
| `M8`, the module kind untouched | no `migrations:` option on the `use`; `block_type.ex:139` is still the injected refusal, and `core/send.ex:112-113` and `core/wait.ex:60-61` still write their own |

`migrate_config/3` is the arity the record itself names (`:8481-8486`), and the
seam's one-call rule is unchanged: `palette.ex` is not touched by either build.

### 3. Cites re-counted at `d6fb241`

Cites into this file and into `ADR-0004`, `ADR-0005` and `ADR-0011` resolve as
written; appends land at the end of each file, so no line above moved, and
`mix adr.cites` is green over this request.

The code cites have moved. Read at `d6fb241`:

| The sections' cite | At `d6fb241` |
|---|---|
| `composite.ex:226-244` (the `use` options), `:245` (the macro) | `:249-266`, `:267` |
| `composite.ex:154-176` (the callbacks are core-only) | `:156-177` |
| `composite.ex:261` (`slots/1` answering `[]`) | superseded: `:283` answers `derived_slots/1` |
| `composite.ex:409` (`expand/2`) | `:441` |
| `composite.ex:476` (`Composite.io/2`) | `:599` |
| `composite.ex:497` (`Palette.core/0` in the derivation) | `:619` and `:625` |
| `composite.ex:515`, `:519`, `:521` (the `slot_accepts` derivation) | `:654-669` |
| `composite.ex:628` (`check_local_ids!/2`), `:657` (`mint/3`), `:668` (`mint_id/3`) | `:826`, `:910`, `:920` |
| `composite/data.ex:319` (`declaration/1`) | `:419` |
| `composite/data.ex:388` (`slots/2`, answering `[]`) | superseded: `:500` answers the declared slots |
| `composite/data.ex:127`, `:148` (the template node's keys and its own `"slots"`) | `:128-135`, `:148-152` |
| `composite/data.ex:137-140` (a node's `"type"` is not checked here) | unmoved |
| `composite/data.ex:141-146` (`"id_suffix"`'s pattern in prose) | unmoved; the attribute itself at `:334` |
| `composite/data.ex:734` (the node's slots decoded) | `:880-930` (`decode_node/2`, `decode_node_body/5`) |
| `composite/data.ex:36-41`, `:43-48`, `:56-65`, `:67-77` | `:36-41`, `:43-48`, `:56-65`, `:67-77`, all unmoved |
| `composite/data.ex:116-123` ("the last moment a malformed declaration can be refused") | `:383-387`, and the same sentence as a code comment at `:980-984` |
| `composite/data.ex:151-169` (whole-value substitution) | `:175-192` |
| `composite/data.ex:180-190` (`## What this module does not decide: a migration`) | superseded, see 1 above |
| `composite/data.ex:192-203` (the hygiene obligation) | `:276-287` |
| `composite/data.ex:283-288` ("Every refusal is here, at entry-build time") | `:383-387` |
| `composite/data.ex:328-331`, `:330`, `:482-486` (the error assembly and `version_errors/1`) | `:429-436`; the `version_errors/1` call at `:434` and its definition at `:632-637` |
| `composite/data.ex:403-404`, `:404` (`migrate_config/3`'s unconditional refusal) | superseded: `:526-535` walks the chain and `:531-532` is the refusal that remains |
| `block_type.ex:321` (`c:slots/1`), `:177` (`slot_decl/0`) | both unmoved |
| `block_type.ex:507-508` (`c:migrate_config/2`), `:139` (the injected refusal), `:46` (the optional-callback row) | all unmoved |
| `core/group.ex:37-41`, `core/assign.ex:64-75` | `:37-41` unmoved; assign's `config_schema/1` at `:63-75`, `path` at `:65-73` |
| `core/send.ex:112-113`, `core/wait.ex:60-61` | both unmoved |
| `palette.ex:652-657` (never a ladder), `:693` (the call), `:648-651` (`:block_type_too_new`), `:659-664` (in-memory only) | `:747-752`, `:788`, `:741-746`, `:755-760` |
| `assignability.ex:661-667`, `:654` | see the `ADR-0011` foot Note of this date |

Filed with `sb-vjvq`, campaign SF038.

## Note (2026-09-08): admission resolves a composite's member kinds through the palette, `expand/2` answers a tuple beside a raising `expand!/2`, a strict `assignable?/4`, an unknown `use` option refused, and where the interrupt pair is scoped

A dated Note rather than an amendment, and it edits nothing above this line.
It records campaign SF039's rulings `RQ-SF039-9`, `RQ-SF039-10`, `RQ-SF039-14`
and `RQ-SF039-16`, taken by the operator on 2026-09-08, as six items, each
naming the bead that builds it. Every one of them names an arity, a return or
a refusal on a function this record already places, so none of them moves a
decision above: this Note carries no `Status:` line and flips nothing, no
`@callback` in decision 5's table is added, removed or re-arity'd, and
`schema_version` stays at `1`. The `RQ-SF039-<n>` label is the form this file
already uses for the SF037 and SF038 walks' rulings.

Every `lib/` cite below was read at `main` `f9b62c5` and is written beside the
anchor it was found by - a heading, a function head, a `@doc` line. A cite is
re-located by that anchor and not by its number.

### 1. Admission resolves a composite's member kinds through the palette (`RQ-SF039-14`)

`StatifierBlocks.Assignability.kinds/3` and `slot_accepts/4` take the palette
as their **first** argument and resolve a composite's members through it,
exactly as `produces/4` already does.

What they do today is the whole of the reason. `kinds/2` (`assignability.ex`,
`@doc "The block's `kinds`, defaulting to `[:step]`"`, `:195-197`) and
`slot_accepts/3` (`:203-204`) both read `io/2` (`:190-191`), which is
`Palette.call(ref, :io, [config], %{})` - the **core-only** callback, whose
composite derivation resolves members through `StatifierBlocks.Palette.core/0`
and falls back to `[:step]` kinds with no sugar for a composite rooted at a
host type (`composite.ex`, heading `### The callbacks are core-only, and a
reader with a palette is not`, `:158-180`). `produces/4` (`:464-465`) does not
have that problem, because it goes through `io_of/3` (`:482-483`), whose
composite arm is `Composite.io(palette, resolved)` (`:485`) - `Composite.io/2`
(`:601-602`) and `outcomes/2` (`:614-615`) being the palette-holding readers
this record's Note of 2026-09-07, item 3, named. Admission is a reader holding
a palette and has been reading with none.

Three consequences, and no more than three:

- `admits?/3` (`:216-218`) and `kind_admission_finding/5` (`:720-741`, which
  calls `admits?/3` at `:733`, `slot_accepts` at `:738` and `kinds` at `:739`)
  route through the palette-carrying arities. Every caller that already holds a
  palette therefore admits and refuses on the same kinds the compiler compiles
  on.
- **The `io/1` callback stays core-only.** No palette argument is added to
  `c:StatifierBlocks.BlockType.io/1` or to `c:StatifierBlocks.BlockType.outcomes/1`,
  and neither derivation gains one. The fallback described at
  `composite.ex:158-180` is still the callbacks' answer and still their answer
  alone; what changes is which of the two spellings admission calls.
- A composite whose expansion holds an interrupt handler carries
  `:interrupt_handler` among its kinds, because the derived `io/1` concatenates
  the members' `kinds` in expansion order and de-duplicates them (`composite.ex`,
  under `## What a composite reads and writes`, `:148`). Dropped at a `body`
  target it is **refused**, because `body` declares `slot_accepts` `[:step]`
  (`core/group.ex:59`, `core/resumable_group.ex:74`) and `ADR-0003` decision
  3's intersection is empty. That is the refusal the compiler already reaches -
  `{:kind_not_admitted, ...}` (`assignability.ex:124`), handled at
  `compiler.ex:1211` - so the editor refuses at drop what the compiler would
  have refused at compile, which is the whole point of routing them through one
  function.

This item **answers `sb-28gm`**, which asked whether a palette-carrying
`admits` form was a record question. It was, and this is the answer: the
editor's `admits_expansion?/5` (`editor.ex:2112-2114`, called at `:2064`) holds
a palette and calls the same functions, so a nested composite rooted at a host
type is admitted or refused on the host palette's kinds rather than on the
core-only derivation's. No separate palette-carrying `admits` spelling is
minted; the existing one takes the palette.

Built by `sb-x903`.

### 2. Per-target admission is `ADR-0005`'s, recorded there (`RQ-SF039-15`)

The editor's per-target admission form - one probe and one check at a gap,
rather than a sweep - is `StatifierBlocks.Edit.Targets`'s and therefore
`ADR-0005`'s. It is recorded there by `sb-0xdu` under clause `4C`. Nothing
about its arities, its defaults or its candidate list is stated here; this item
exists so a reader of item 1 knows where the target side lives and does not
look for it in this record.

### 3. `Composite.expand/2` answers a tuple; `expand!/2` keeps the raise (`RQ-SF039-10`)

`Composite.expand/2` (`composite.ex:443-444`) answers
`{:ok, {blocks, param_map}} | {:error, reason}`.

`expand!/2` keeps today's raising body - the broken-declaration raises listed at
`composite.ex:439-441` ("Raises when the declaration is broken: a `subtree/1`
that answers an empty list, a non-block, a duplicated local id, or a local id
that would mint an id carrying `__`") - and it is what the compiler's Resolve
and the editor's Expand call. A broken declaration is therefore still a
compile-time raise, and no caller learns to swallow one.

The sentence at `composite.ex:433`, "This is the **one** expansion function",
becomes **one expansion, two spellings**: one derivation of what a composite
stands for, two return shapes over it, and still no second implementation. The
argument that sentence makes - that three implementations would be three
chances for the compiled chart and the expanded document to disagree - is
unchanged by a second spelling that calls the first.

This is a **breaking** change to a public function's return, and it is named in
the changelog of the release it lands in.

Two rulings this file already carries are untouched by the new return, and are
named here only so that a reader of `expand/2` finds all three together: an
expansion's members are built at each member type's `current_version/0`
(`RQ-SF037-17`, this file's Note of 2026-09-07, item 2), and `param_map` blames
the **first** param in declaration order when more than one distinguishing
value matches (`RQ-SF038-14`, item 5 of that same Note). Both are ruled and
unbuilt; `sb-ij7y` and `sb-gua3` carry them, and the change here neither
implements nor disturbs either.

Built by `sb-671e`.

### 4. `assignable?/4` gains a strict form (`RQ-SF039-16`)

`Assignability.assignable?/4` (`assignability.ex:253-255`) gains a
`strict: true` form under which either side resolving to `:unknown` answers
`false`.

The default does not move. The clause at `:256-258` -
`satisfied when satisfied in [:unknown, :identical, :covers] -> true` - admits
an unknown in both directions, and that is the floor of the ordered relation
`assignability.ex` names in `assignable?/4`'s `@doc` at `:229` - "`ADR-0003`
decision 6's ordered relation as `ADR-0011` decision 3 narrows it" - whose
first step decides either side unknown before the host is asked. A value
nothing has typed is not a value that relation may refuse. `strict: true` is the opt-in for the caller that must not
admit one, and it is opt-in precisely so the floor stays where every existing
caller found it.

How the flag reaches the function - an option on the fourth argument or a
fifth - is `sb-v3c5`'s to choose and is not decided here. What is decided here
is the answer: under it, `:unknown` on either side is `false`, and nothing else
about the ordered relation changes.

Built by `sb-v3c5`.

### 5. `use StatifierBlocks.Composite` refuses an unknown option, by name

`use StatifierBlocks.Composite` refuses an unknown option at the **use site**,
naming the option it did not recognize.

Today it does not. `__declaration__/1` (`composite.ex:361-362`) reads `:name`
and `:params` through `required_option/2` and `:version`, `:sentence`,
`:palette_entry` and `:slots` through `Keyword.get/3`, and never looks at the
rest of the keyword list. A misspelled option is silently dropped and the
composite compiles carrying the default the author was trying to replace - a
`:verison` that leaves the type at version `1`, a `:slot` that leaves it with
no pass-through slot. It is the one class of declaration error
`__declaration__/1`'s existing refusals cannot catch, because nothing is wrong
with the declaration that results - it is simply not the one that was
written.

The recognized set is exactly the option list documented at
`composite.ex:250-266` - `:name`, `:params`, `:sentence`, `:palette_entry`,
`:version`, `:slots` - and the refusal is an `ArgumentError` raised where the
existing option refusals are raised, at declaration-build time, naming the
unknown key. A later amendment that adds an option adds it to that list and to the
recognized set together; the two are the same list.

Built by `sb-xudv`.

### 6. The interrupt pair's spelling does not change; its scoping is `ADR-0010`'s (`RQ-SF039-9`)

The reserved-prefix paragraph of decision 10 stands, unedited.
`statifier_blocks.interrupt.abandon` and `statifier_blocks.interrupt.resume`
(`core/emit.ex:68-69`, named by `interrupt_events/0` at `:77-78`) remain both
the **authored** and the **raised** spelling: a host block type joins the
protocol by raising exactly those two names, and a host must not name its own
events under the prefix.

Scoping the pair per enclosing group is the **compiler's**, at emit, and is
decided in `ADR-0010` decision 8 by `sb-e18p`. It is recorded there rather than
here because it is a property of what the compiler emits, not of what a block
type declares, and decision 11 above already hands the compiler and its
provenance map the SCXML subtree representation and state-id generation. No sentence of decision 10, and no row of its
table, is edited for it.

Filed with `sb-0lmk`, campaign SF039.

## Amendment (2026-09-08): a subtree may name a member's outcome - `outcome_of:` on a config value, resolved at expansion and lifted back by Collapse

**Status: proposed (2026-09-08, campaign SF039, bead `sb-gmqx`, recording
campaign-SF039's ruling `RQ-SF039-4`).** A decision record merges at proposed
under the campaign invariant, and this one **stays** proposed at that
campaign's wrap: `RQ-SF039-4` ruled the record first and the code a later
campaign's, so no bead in campaign SF039 builds any of it and **nothing below
describes code that exists**. Flipping it to accepted is a separate gated
request through the same `docs/adr/` gate, filed by the campaign that builds
it. **No bead carries the code yet**, and that is the one way this section
differs from the two rulings this file's Note of 2026-09-08 calls "ruled and
unbuilt" in its item 3: that item names the bead carrying each of them
(`sb-ij7y` and `sb-gua3`, `:9101-9103`), and this ruling has no carrier to
name. The bead that builds it is filed when the campaign that builds it is
walked, and this section is what that bead builds from. Additive:
every decision above stands exactly as it stands, every Amendment and Note
above this line stands as it stands, and no text above this line is edited by
this section.

An amendment rather than a Note, because the data-composite amendment of
2026-09-07 says in as many words that **"The placeholder vocabulary is one arm,
and one escape"** (`:7120-7128`) and this section gives it a second arm. That
same clause names the condition on which a second arm may be added - "A host
that needs `"prefix-" <> param` writes two params, or waits for the record that
adds an arm and says which producer emits it" (`:7143-7145`) - and this section
is that record: the producer is `Collapse`, in `O3` below, exactly as the
producer of the first arm is. `StatifierBlocks.Composite.Data`'s own heading
`### The placeholder vocabulary is one arm, and one escape`
(`lib/statifier_blocks/composite/data.ex:173`) repeats the sentence in the
code, and the module's private `substitute/2` (`composite/data.ex:610-621`) is
where the arm it names lives. Nothing else about that vocabulary moves:
whole-value substitution stays the whole of it, for the reason `:7130-7145`
gives, and this section adds no interpolation, no expression and no
conditional.

Every `lib/` cite below was read at `main` `e7dc045` and is written beside the
anchor it was found by - a heading, a function head, a `@doc` line. A cite is
re-located by that anchor and not by its number.

### What a subtree cannot say today, and the measurement that asks for it

A subtree's ids are **local**. `expand/2` mints each expanded block's real id
from the composite block's own, as `composite_id <> "_" <> local_id`
(`composite.ex`, heading `## The ids the subtree mints`, `:55-69`; `mint_id/3`,
`:923`), and the composite block's id is the document's - `blk_GD` in one
document and something else in the next. A member's **compiled** identity is
therefore unknowable to the template that writes it, and every generated name
built on that identity is unwritable there: the completion event one declared
outcome raises, `done.outcome.<state id>.<outcome>`, is built from the member's
state id (`ADR-0004`'s outcome amendment, `2b` and `2c`;
`StatifierBlocks.Compiler.StateId.outcome_event/2`, `compiler/state_id.ex:202-203`).

That name is exactly what a rail is written against. A hand-written
`core.on_event` holds it as a plain string in its `event` config key
(`core/on_event.ex:300`), and the editor offers the generated names of the
enclosing body's siblings as a `<datalist>` on that field
(`editor/field.ex`, under the heading its `event_candidates` section carries, `:186-195`). An
author writing by hand can pick one. An author writing a **composite** cannot,
because there is no id yet to pick.

The first production embedder's measurement is the reason this matters enough
to fix. A guard composite there cannot write a rail against a member's outcome
state, so it carries its failure reading through the datamodel instead: reset a
key before the step, branch on a sentinel after it. The two are not equivalent.
A transport error parks the run; a refusal that the call itself answers arrives
in `donedata` and does not. To the author both are one fact - the step did not
succeed - and the member already declares them as two outcomes
(`core.invoke`'s `done` and `error`, `core/invoke.ex:114`), which a rail can
tell apart and a sentinel in the datamodel cannot.

### `O1`. The declaration: `outcome_of:`, a config value naming a member and one of its outcomes

A member of `subtree/1` may carry, **as a whole config value**,

    {:outcome_of, local_id, outcome}

where `local_id` is the local id of another member of the same `subtree/1` and
`outcome` is one of that member's declared outcome names. Both are strings.

It stands in a config value and nowhere else: not in a slot, not in a block's
`id`, not inside a larger string. That is the vocabulary's existing rule and
this section keeps it.

**The reference is a pair, not a bare local id.** `ADR-0004`'s outcome
amendment compiles **one `<final>` per declared outcome** (`2b`), so "the
member's outcome state" is not one state: a member declaring `done` and `error`
has two, and a reference that named only the member would have to guess which.
The pair is the smallest thing that resolves, and it is the shape this file
already uses for the same kind of reference - the pass-through amendment's
`:to`, `{local_id, inner_slot}` (`:8131-8132`), which names a member and one of
its slots for the same reason.

### `O2`. What it resolves to, when, and at which level

At expansion, `expand/2` replaces the value **whole** with the completion event
that outcome raises:

    {:outcome_of, "call", "error"}   ->   "done.outcome.s_blk_GD_call.error"

for a composite block whose id is `blk_GD`. Three things are fixed by that.

**The member's id is minted first, and minted the way its own id is.** The
value resolves against `mint_id(composite_id, local_id, ref)` - the same
function, the same call, at the same level - so the reference lands on the
member this expansion produced and not on a member of another instance of the
same type. That is what "one level up" means here, and it is the level
`ADR-0004`'s Resolve-stage amendment already attributes a finding inside an
expansion to (`E3`).

**The generated name is spelled once, by the compiler's function for it.**
`StateId.outcome_event/2` over `StateId.state_id/1` (`compiler/state_id.ex:72`,
`:202-203`), never by string concatenation, for the reason that function's own
`@doc` gives - "Spelled once, here, so the event a `<final>` raises and the
event a parent wires on cannot drift apart" (`:195-196`) - and for the reason
`ADR-0004` decision `2b` gives about minting an outcome id through
`Context.outcome_id/2` rather than by hand.

**It answers the event, not the bare state id.** The value a rail holds is an
event name; no config key this package declares holds a bare state id. Because
substitution is whole-value, a template that received the state id alone could
not build the event from it, so a reference that resolved to the state id would
resolve to something no config value can hold. The state id is inside the
answer, where the author's hand-written name also carries it.

**Where it happens.** At expansion, which is the compiler's Resolve stage
(`ADR-0004`'s Resolve-stage amendment, `E1`) and the editor's Expand operation
- the two callers `expand/2`'s own `@doc` names (`composite.ex:433-437`). It
therefore happens **before** any block type reads the config, which is what
keeps `core.on_event`'s "must be an event name" check
(`core/on_event.ex:355-358`) true of every config that ever reaches it: the
tagged value lives in the declaration, never in a document and never in a
compile.

**`param_map` is unchanged.** An `outcome_of:` value names no param, so it
attributes nothing. A member whose config holds one and no `"$param"` is
attributed `nil`, exactly as a member with no placeholder at all is, by the
rule the data-composite amendment states at `:7147-7153`.

### `O3`. Collapse lifts a hand-written rail into `outcome_of:` and strips the compiled id

`ADR-0005`'s part (iii) amendment, clause `18E`, makes the template "the
subtree with each proposed value replaced by a placeholder", each marked value
becoming `%{"$param" => key}` and every other value carried across as the
literal it is. A generated completion-event name is the one class of value for
which "carried across as the literal it is" is wrong, because the literal
carries an id minted for the document being collapsed.

So: **a config value that is a generated completion-event name whose block is
inside the collapsed selection becomes an `outcome_of:` reference**, keyed by
that block's `"id_suffix"` - the one `18E` mints from the type name - and by the
outcome the name carries. The compiled id is **stripped**: no `s_blk_...`
reaches the declaration, and the collapsed composite expands correctly in a
second document, which is the whole point of collapsing it.

Recognising the name is `StateId.undone_event/1`'s (`compiler/state_id.ex:255-262`),
which inverts a generated name back to the block it names and the outcome it
names, or answers `:error` for a string that is not unambiguously one. It is
the same inversion `ADR-0005` decision `10w` already relies on for a summary
chip, cited by that function's own `@doc` (`:213-215`), so this clause adds a
caller and not a mechanism.

A marked value of this kind is **not** a proposed param: a param's default is a
value the author chose (`18E`), and a compiled id is a value the compiler
chose. The reference replaces it whether the author marked it or not.

### `O4`. The data spelling: `"$outcome_of"`, the vocabulary's second arm

A `Composite.Data` declaration says the same thing with a map carrying exactly
the single key `"$outcome_of"`, whose value is the two-element JSON array
`[local_id, outcome]`:

    {"event": {"$outcome_of": ["call", "error"]}}

A two-element array for the reason the declaration-level `"slots"` key already
uses one - "a two-element JSON array, because JSON has no tuple"
(`composite/data.ex:155-157`). It decodes to the same reference the `use`
kind's tuple writes, so the two kinds expand identically, which is the property
`expand/2` exists to hold.

What a data composite **may** say is that, and that alone. What it may not:

  * **No interpolation.** `"prefix-{$outcome_of}"` is not a value; the arm is
    whole-value like the first one, and the clause at `:7130-7145` is
    unchanged.
  * **No third element**, and no local id that is not a member of this
    declaration's own `"subtree"`. A reference reaches inside one declaration
    and no further.
  * **No escape from the escape.** A config value that genuinely is a one-key
    `"$outcome_of"` map is written `{"$literal": {"$outcome_of": ...}}`,
    exactly as a value that genuinely is a `"$param"` map is - the escape
    covers the new arm without itself changing.

Two consequences in the code this clause would be built into, named because
they are the places a builder would otherwise have to rediscover.
`substitute/2` (`composite/data.ex:610-621`) gains a clause beside its
`"$param"` one, guarded `map_size(node) == 1` like both existing arms.
`placeholders/1` (`:960-966`) answers `[]` for the new arm - it names no param
key - which is what keeps `param_map` attribution exactly what `O2` says it
stays.

### `O5`. A reference to a local id the subtree does not declare is refused, naming the id

An `outcome_of:` whose `local_id` names no member of `subtree/1` is refused,
and the refusal names the local id.

For the `use` kind it is raised where the declaration's other structural
refusals are raised - from `expand/2`, in the `ArgumentError` shape and beside
`check_local_ids!/2` (`composite.ex:829`) and `check_mapping!/3` (`:868`). For
the data kind it is a declaration error from `declaration/1`
(`composite/data.ex:419`), because the template is static and that is the last
moment a malformed declaration can be refused - the same split, for the same
reason, as the pass-through amendment's mapping refusals (`:8255-8267`).

The reason a silent miss is not an option is the one the pass-through
amendment's unknown-`local_id` refusal gives (`:8233-8234`): a reference that
resolves to nothing would expand to an event name naming a state that is not in
the chart, and a rail wired to it would simply never fire. That is a failure
with no symptom, in a feature whose whole purpose is a rail that fires.

### Worked example: "Guarded section" (signup)

A host in the signup domain wraps a step in a section that abandons when the
step comes back on its error outcome. Written by hand that is a group, a step
and a rule; as a composite it is one block with one param.

**The declaration.**

    params:
      %{key: "invoke_type", type: :string, label: "Call",
        required?: true, default: ""}

    subtree(params):
      core.group   id "section"
        slots  %{"body" => [
                   core.invoke   id "call"
                     config  %{"invoke_type" => params["invoke_type"],
                               "assign_to" => ""}
                 ],
                 "interrupts" => [
                   core.on_event   id "on_failure"
                     config  %{"event" => {:outcome_of, "call", "error"},
                               "outcome" => "abandon"}
                 ]}

`core.group` declares exactly those two slots (`core/group.ex:37-40`) and its
`interrupts` slot admits `:interrupt_handler` alone (`:59`), which
`core.on_event` is; `core.invoke` declares `done` and `error`
(`core/invoke.ex:114`), so `"error"` is a name the member answers for.

**The expansion**, for a composite block whose id is `blk_GD` and whose config
is `%{"invoke_type" => "myapp:signup"}`: three members, `blk_GD_section`,
`blk_GD_call` and `blk_GD_on_failure`, and the rule's `event` is
`done.outcome.s_blk_GD_call.error`. Nothing else in the expansion differs from
what a subtree without the reference produces.

**What could not be written before this section**, stated plainly because it is
the whole argument: the template would have to spell `s_blk_GD_call` itself,
and `blk_GD` is this document's block id. The same declaration used in a second
document would name a state that does not exist there, and the rail would never
fire. There is no arrangement of params that fixes it either - a param whose
default is a compiled id is the same document-bound value with a form control
in front of it.

**And what the example does not change.** This file's worked example "Guarded
step" (`:6665`) is a card-processing arrangement whose failure path is
`core.invoke`'s own `on_error` slot, not a rail wired to an outcome event. It
is untouched by this section, and it is the smaller of the two cases: a slot
the member declares needs no reference, because the author's block is already
inside the member.

### What this section does not decide

- **The code.** `RQ-SF039-4` ruled the record first and the code a later
  campaign's. No bead in campaign SF039 builds any clause above, and the
  implementing bead is filed when the campaign that builds it is walked. This
  section is what that campaign builds from.
- **Whether an outcome the member's type does not declare is refused, and
  where.** `O5` refuses an unknown **local id** and no more. Checking the
  outcome name is a read of the member's declared outcomes, which is a
  palette-holding read - `Composite.outcomes/2` takes a palette
  (`composite.ex:615`) and `expand/2` takes a `t:StatifierBlocks.Palette.type_ref/0`
  (`:444`) - so it is a question about where the check lives rather than about
  whether the answer is obvious. It is left to the record or the campaign that
  builds `O5`.
- **Interpolation, and therefore a guard.** A guard that needs the compiled id
  inside a larger expression - a `core.on_event`'s `cond`
  (`core/on_event.ex:314`) is the case at hand - is **not** expressible by this
  section, because substitution is whole-value and this section adds an arm
  without touching that. A host that needs one waits for the record that adds
  it and names its producer, which is what the vocabulary clause at
  `:7143-7145` already says of every arm after the first.
- **A generated name that names a block outside the collapsed selection.**
  `18E` carries it across as a literal, which leaves that declaration
  document-bound. Whether `Collapse` should refuse it instead - the way `19E`
  refuses a value it cannot spell, naming the block and the field - is a
  question for `ADR-0005`, not answered here.
- **How the editor draws an `outcome_of:` value.** A declaration's template is
  not drawn on any form this file describes; the composite's own card draws its
  params.

Filed with `sb-gmqx`, campaign SF039.
