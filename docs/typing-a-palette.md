# How to type a palette

This guide shows you how to declare what your block types read and write, so
the editor and the compiler can refuse a document that contradicts itself.

Nothing flows between adjacent blocks. Every value a block produces is written
to a datamodel path by name, and every value one reads is read from a path by
name, so a validation walk carries an **environment** - a map from datamodel
path to type - through the document, and the question at a position is whether
what the environment holds at a path satisfies what the block reads there.
[`docs/adr/0011-typed-environment.md`](adr/0011-typed-environment.md) is the
record; everything below is the moves.

## Before you start

The types themselves live in the datamodel document, which
[`statifier_datamodel`](https://github.com/riddler/statifier_datamodel) owns:
`sd-ADR-0001` is the record that defines the document, its `types` key and the
read check. This package takes it as a dependency and calls it; it defines no
second read check and no compatibility or coverage module of its own.

The dependency resolves from Hex, at a floor of the package's first release:

```elixir
# mix.exs
{:statifier_datamodel, "~> 0.1"}
```

## Declare the records and shapes your paths hold

The datamodel document's fourth top-level key, `types`, carries named
declarations. A `record` is a thing your domain has; a `shape` is a set of
required fields a step will accept anything that covers.

1. Add a `types` list beside `scopes`. A declaration carries `name` (unique
   across the list), `kind` (`"record"` or `"shape"`), `label` (what a pane
   renders) and `fields`; `note` is optional prose.
2. Give each field a `name`, a `type`, and `required?: true` where a reader may
   depend on it. `label`, `note` and `one_of` are optional, and a `list` field
   carries its `item_type` under the same rule.
3. Reference declarations from each other by `name`. A reference to a name the
   list does not declare normalizes to unknown rather than failing admission -
   a half-written declaration declares nothing rather than raising.

```elixir
datamodel = %{
  "version" => 1,
  "scopes" => [
    %{"scope" => "global", "label" => "Global", "entries" => []},
    %{
      "scope" => "local",
      "label" => "This run",
      "entries" => [
        %{
          "name" => "current_txn",
          "path" => "cards.current_txn",
          "type" => "object",
          "label" => "Current transaction"
        },
        %{
          "name" => "settlement",
          "path" => "cards.settlement",
          "type" => "object",
          "label" => "Settlement"
        }
      ]
    },
    %{"scope" => "event", "label" => "Event", "entries" => []}
  ],
  "types" => [
    %{
      "name" => "cards.credit_txn",
      "kind" => "record",
      "label" => "Credit card transaction",
      "fields" => [
        %{"name" => "amount_minor", "type" => "integer", "required?" => true},
        %{"name" => "currency", "type" => "string", "required?" => true},
        %{"name" => "authorized_at", "type" => "datetime"},
        %{"name" => "expires_on", "type" => "date"}
      ]
    },
    %{
      "name" => "cards.settlement",
      "kind" => "record",
      "label" => "Settlement",
      "fields" => [
        %{"name" => "amount_minor", "type" => "integer", "required?" => true},
        %{"name" => "currency", "type" => "string", "required?" => true},
        %{"name" => "settled_on", "type" => "date", "required?" => true}
      ]
    },
    %{
      "name" => "Settleable",
      "kind" => "shape",
      "label" => "Settleable",
      "fields" => [
        %{"name" => "amount_minor", "type" => "integer", "required?" => true},
        %{"name" => "currency", "type" => "string", "required?" => true}
      ]
    }
  ]
}

declarations = StatifierDatamodel.Declarations.from_document(datamodel)

txn_label = StatifierBlocks.Environment.type_label(declarations, "cards.credit_txn")
#=> "Credit card transaction"
```

A declared name is not a path, and a declaration's field is not a path: the
`types` key contributes nothing to the declared-path set the undeclared-path
advisory reads. The `scopes` entry is what says a path **exists**; `types` is
what says what a path may hold.

## Name the document's subject

A one-subject document - a card moving through a flow, a signup running to
completion - has one path everything is about. Name it once, on the palette
entry of the block type your documents start with:

1. Add `subject:` to that type's `palette_entry/0`. It is read from the
   **entry block**: the first block of the root's `body` slot.
2. Keep `io/1`'s `consumes` and `produces` where they are. They are sugar over
   that path now: `consumes: T` is a read there, `produces: T` is a write
   there.

```elixir
defmodule MyApp.Typing.Authorize do
  @moduledoc "myapp.authorize: places a hold on the card."

  @behaviour StatifierBlocks.BlockType

  @impl true
  def current_version, do: 1

  @impl true
  def slots(_config), do: []

  @impl true
  def config_schema(_config),
    do: [%{key: "invoke_type", type: :string, label: "Invoke", required?: true, default: ""}]

  @impl true
  def validate_config(_config), do: :ok

  @impl true
  def io(_config), do: %{kinds: [:step], produces: "cards.credit_txn"}

  @impl true
  def palette_entry, do: %{label: "Authorize", subject: "cards.current_txn"}

  @impl true
  def emit(_block, context) do
    alias StatifierBlocks.Core.Emit
    done = StatifierBlocks.Compiler.Context.done_id(context)
    {:ok, Emit.state(context.state_id, done, [Emit.final(done)])}
  end
end
```

If your documents have no single subject, declare no `subject:`. The sugar
then desugars to nothing at all - not a read of `nil`, not a write at `""`,
and not a finding - so an existing palette keeps working untouched.

## Declare what each field reads and writes

Signatures go on the **field**, not on the block, so a finding anchors on the
control an author has to change. A block with three path fields has three
independent signatures.

| Declaration | What it means |
|---|---|
| `{:path, %{expects: T}}` | a **read**: the environment at this block's position must satisfy `T` at the path this field names |
| `{:path, %{writes: T}}` | a **write**: `T` is at that path for every block after this one |
| `{:path, %{}}` | a write of `:unknown`: the path becomes known without becoming typed |
| `:string` with `datamodel_path?: true` | the same write of `:unknown` |
| `core.on_event`'s `capture` | one write of `:unknown` per pair, at the pair's key |

A field declaring `expects` and no `writes` is a read and **not** also a
write: it says what the block needs at the path, not what it leaves there.

```elixir
defmodule MyApp.Typing.Settle do
  @moduledoc "myapp.settle: settles a hold this flow already placed."

  @behaviour StatifierBlocks.BlockType

  @impl true
  def current_version, do: 1

  @impl true
  def slots(_config), do: []

  @impl true
  def config_schema(_config),
    do: [
      %{
        key: "subject",
        type: {:path, %{expects: "Settleable"}},
        label: "Transaction",
        required?: true,
        default: "cards.current_txn"
      },
      %{
        key: "assign_to",
        type: {:path, %{writes: "cards.settlement"}},
        label: "Write the settlement to",
        required?: true,
        default: "cards.settlement"
      }
    ]

  @impl true
  def validate_config(_config), do: :ok

  @impl true
  def io(_config), do: %{kinds: [:step]}

  @impl true
  def palette_entry, do: %{label: "Settle"}

  @impl true
  def emit(_block, context) do
    alias StatifierBlocks.Core.Emit
    done = StatifierBlocks.Compiler.Context.done_id(context)
    {:ok, Emit.state(context.state_id, done, [Emit.final(done)])}
  end
end
```

A signature is a claim about the document's data flow, never a rule about the
bytes in this config: `validate_config/1` remains the only authority on a
field's own value.

## Check what the walk knows at a position

Hand the datamodel document in as context. `:entry_type` seeds the subject
path for a document whose entry block declares no `produces` of its own; the
entry block's own writes land through the walk, like every other block's.

```elixir
alias StatifierBlocks.{Assignability, Block, Document, Environment, Palette}

document =
  Document.new(
    Block.new("core.sequence",
      id: "blk_root",
      slots: %{
        "body" => [
          Block.new("myapp.authorize",
            id: "blk_authorize",
            config: %{"invoke_type" => "myapp:authorize"}
          ),
          Block.new("myapp.settle",
            id: "blk_settle",
            config: %{"subject" => "cards.current_txn", "assign_to" => "cards.settlement"}
          )
        ]
      }
    ),
    id: "bdoc_card_settle"
  )

palette =
  Palette.new(
    Map.merge(Palette.core_types(), %{
      "myapp.authorize" => MyApp.Typing.Authorize,
      "myapp.settle" => MyApp.Typing.Settle
    })
  )

ctx = %{datamodel: datamodel}

known_at_settle = Environment.at(palette, document, {"blk_root", "body", 1}, ctx)
#=> %{"cards.current_txn" => "cards.credit_txn"}

verdict = Assignability.validate(palette, document, ctx)
#=> :ok
```

The settle step expects `Settleable` and the environment holds
`cards.credit_txn`. That is not identity, so the check asks coverage:
`cards.credit_txn` has `amount_minor` and `currency`, which is the whole of
`Settleable`'s required set. Satisfied.

To see a refusal, point the read at a shape the record does not cover:

```elixir
by_coverage = Environment.satisfies(declarations, "cards.credit_txn", "Settleable")
#=> :covers

refused = Environment.satisfies(declarations, "cards.settlement", "cards.credit_txn")
#=> :not_assignable

permissive = Environment.satisfies(declarations, :unknown, "Settleable")
#=> :unknown
```

An unsatisfied read is a validation **error**, carrying the block, the field
and the path it was checked at. A read of a path the environment does not hold
is not an error at all: nobody contradicted anybody, so it stays the
undeclared-path `:info` advisory it already was, which is what lets a palette
be typed one entry at a time.

Two more readers, when you want to find the parts you have not typed yet:

- `Assignability.finding_reason/2` says why a read refused -
  `:not_assignable`, `{:shape_not_satisfied, missing}` naming the required
  fields that are absent, or `{:fixable_by, block_id}` naming the block whose
  write put the offending type there.
- `Assignability.seam_reasons/3` names the reads that passed only because
  something declared nothing - `:source_untyped`, `:target_untyped`,
  `:both_untyped`.

## Project a host schema into the document

Your records already exist somewhere - an Ecto schema, a JSON contract, a
database table. Project them rather than retyping them:

1. Map each column or field to one of the nine scalars, or to the `name` of
   another declaration when it is a nested thing.
2. Mark `required?: true` on the fields a reader may depend on, and only
   those. Coverage is decided against the required set alone.
3. Emit the declaration list into the datamodel document you already hand the
   editor.

| Host type | Declare |
|---|---|
| `:string`, `:text`, an enum backed by a string | `string` (add `one_of` for the enum) |
| `:integer`, `:id`, `:bigint` | `integer` |
| `:decimal`, `:float`, a money column | `decimal` |
| `:boolean` | `boolean` |
| `:utc_datetime`, `:naive_datetime` | `datetime` |
| `:date` | `date` |
| an interval, a TTL, a retention window | `duration` |
| `:map`, an embedded schema you do not want to name | `object` |
| an embedded schema you do want to name | the declaration's `name` |
| `{:array, T}`, a `has_many` | `list`, with `item_type` |

`date` is a distinct type rather than a `datetime` because the expression
language distinguishes them. Anything outside the nine is not a scalar: a
scope entry whose `type` is outside the set reads as untyped, and a
declaration field's type outside the set reads as a reference to a
declaration - which normalizes to unknown when nothing declares it.

There is no inference. Two records with identical fields are two records,
there is no union and no least-upper-bound, and none of it is enforced at run
time: the whole relation is authoring-time and no SCXML carries a type.

## Re-resolve a host relation at publish

If your palette carries an `assignability` module, it is still consulted - and
it now runs **last**, after unknown, after identity and after coverage. So:

1. Delete the half of your module that widened records into shapes by hand.
   Coverage does that now, and it does it before you are asked.
2. Keep the half only you can know - the host-specific pairs no declaration
   expresses.
3. Re-check at publish rather than at edit. The relation can only widen, so a
   buggy module degrades to extra permissiveness and removing it cannot
   invalidate a document you have already stored.

```elixir
_typed_palette =
  Palette.new(Map.merge(Palette.core_types(), %{"myapp.settle" => MyApp.Typing.Settle}),
    assignability: MyApp.Typing.Settle
  )
```

## Read the result in the editor

Three surfaces show the environment, and none of them changes a verdict:

- **Findings carry the declared label.** A finding about a path renders the
  declaration's `label`, so an author reads "Credit card transaction" rather
  than a nominal name they have to look up. A declaration with no `label`
  renders its name.
- **The Datamodel tab answers "what is known here".** Select a block and the
  drawer's Datamodel tab lists the paths the environment holds at that
  position, with their types.
- **Path controls offer candidates.** A `{:path, opts}` control offers the
  declared paths as candidates; with no datamodel, it is a plain text input.

For the expression editor's own view of the datamodel - the projection from
declared paths to value kinds - see `StatifierDatamodel.Index.path_types/1`;
it reaches statifier-ui in a later release.
