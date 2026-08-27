# ADR-0002: A block type is a behaviour module resolved through a caller-supplied palette

Status: accepted (2026-08-26); decision 9 amended (2026-08-26); decisions 7, 8 and 10 and the typespec appendix amended (2026-08-27, operator rulings)

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
