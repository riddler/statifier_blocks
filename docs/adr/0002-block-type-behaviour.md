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
