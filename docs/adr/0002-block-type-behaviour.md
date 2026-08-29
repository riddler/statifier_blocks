# ADR-0002: A block type is a behaviour module resolved through a caller-supplied palette

Status: accepted (2026-08-26); decision 9 amended (2026-08-26); decisions 7, 8 and 10 and the typespec appendix amended (2026-08-27, operator rulings); outcomes/metadata/label amendment (accepted 2026-08-29, operator ruling); decision 7 amended - optional `datamodel_path?` key (2026-08-29, accepted under the operator campaign-015 direction-agent gate grant, PR 90)

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

**Status: proposed (2026-08-29, operator ruling on sb-jhj).** The 2026-08-28
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
