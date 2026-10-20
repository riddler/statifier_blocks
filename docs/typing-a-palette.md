# How to type a palette

This guide shows you how to declare what your block types read and write, so
the editor and the compiler can refuse a document that contradicts itself.

Nothing flows between adjacent blocks. Every value a block produces is written
to a datamodel path by name, and every value one reads is read from a path by
name, so a validation walk carries an **environment** - a map from datamodel
path to type - through the document, and the question at a position is whether
what the environment holds at a path satisfies what the block reads there.
[`docs/adr/0011-typed-environment.md`](https://github.com/riddler/statifier_blocks/blob/main/docs/adr/0011-typed-environment.md) is the
record; everything below is the moves.

The example is patron registration: a visitor becomes a library patron
through a few screens. One step checks the details the visitor entered, and a
later step issues a library card to a visitor whose details say enough to
hold one.

Every snippet on this page runs, in order, as one script:
[`test/statifier_blocks/typing_a_palette_test.exs`](https://github.com/riddler/statifier_blocks/blob/main/test/statifier_blocks/typing_a_palette_test.exs)
evaluates them on every build and asserts every `#=>` output against what
the code answers.

## Before you start

The types themselves live in the datamodel document, which
[`statifier_datamodel`](https://github.com/riddler/statifier_datamodel) owns:
`sd-ADR-0001` is the record that defines the document, its `types` key and the
read check. The read check is that package's
`StatifierDatamodel.Types.satisfies/3` - unknown is permissive both ways,
identity is nominal, and a record satisfies a shape when it covers the
shape's required fields. This package takes it as a dependency and calls it;
it defines no second read check and no compatibility or coverage module of
its own.

The dependency resolves from Hex, at a floor of 0.4:

```elixir
# mix.exs
{:statifier_datamodel, "~> 0.4"}
```

0.3.0 is the release in which an entry's `type` may name a declaration, which
the section below uses; 0.4.0 is the one in which a type expression admits an
inline, unnamed shape beside a declared name, which the environment reads and
a `{:type_expr, opts}` field stores.

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
      "label" => "This registration",
      "entries" => [
        %{
          "name" => "visitor",
          "path" => "registration.visitor",
          "type" => "object",
          "label" => "Visitor"
        },
        %{
          "name" => "library_card",
          "path" => "registration.library_card",
          "type" => "object",
          "label" => "Library card"
        }
      ]
    },
    %{"scope" => "event", "label" => "Event", "entries" => []}
  ],
  "types" => [
    %{
      "name" => "myapp.patron_application",
      "kind" => "record",
      "label" => "Patron application",
      "fields" => [
        %{"name" => "full_name", "type" => "string", "required?" => true},
        %{"name" => "age", "type" => "integer", "required?" => true},
        %{"name" => "submitted_at", "type" => "datetime"},
        %{"name" => "birth_date", "type" => "date"}
      ]
    },
    %{
      "name" => "myapp.library_card",
      "kind" => "record",
      "label" => "Library card",
      "fields" => [
        %{"name" => "card_number", "type" => "string", "required?" => true},
        %{"name" => "full_name", "type" => "string", "required?" => true},
        %{"name" => "issued_on", "type" => "date", "required?" => true}
      ]
    },
    %{
      "name" => "CardApplicant",
      "kind" => "shape",
      "label" => "Card applicant",
      "fields" => [
        %{"name" => "full_name", "type" => "string", "required?" => true},
        %{"name" => "age", "type" => "integer", "required?" => true}
      ]
    }
  ]
}

declarations = StatifierDatamodel.Declarations.from_document(datamodel)

application_label =
  StatifierBlocks.Environment.type_label(declarations, "myapp.patron_application")
#=> "Patron application"
```

A declared name is not a path: the `types` key on its own contributes nothing
to the declared-path set the undeclared-path advisory reads. The `scopes` entry
is what says a path **exists**; `types` is what says what a path may hold.

## Type an entry by a declaration

An entry's `type` - and a `list` entry's `item_type` - may name one of the
declarations instead of one of the nine types (`sd-ADR-0001`'s amendment of
2026-09-06, in `statifier_datamodel` 0.3.0). The declaration's fields are then
declared paths beneath the entry's own path, exactly as an inlined `object`
entry's `fields` are:

```elixir
%{
  "name" => "visitor",
  "path" => "registration.visitor",
  "type" => "myapp.patron_application",
  "label" => "Visitor"
}
```

With that entry in `scopes`, `registration.visitor.age` is a declared
path: it is offered as an expression candidate, it draws the control its
declared type asks for, and a block that writes there gets no undeclared-path
advisory. Nothing about it is a special case here - this package reads the
projection off `StatifierDatamodel.Index` and never asks whether the fields
beneath a path were written inline or reached through a name. The Datamodel
tab's Type cell for the entry itself reads `myapp.patron_application`, the
name the author wrote.

Write the declaration out inline instead when the shape is one path's alone;
name it when the same record sits at more than one path, or when a step's
`expects` already names it and the two ought not to drift.

## Name the document's subject

A one-subject document - one visitor's registration moving through a few
screens - has one path everything is about. Name it once, on the palette
entry of the block type your documents start with:

1. Add `subject:` to that type's `palette_entry/0`. It is read from the
   **entry block**: the first block of the root's `body` slot.
2. Keep `io/1`'s `consumes` and `produces` where they are. They are sugar over
   that path now: `consumes: T` is a read there, `produces: T` is a write
   there.

```elixir
defmodule MyApp.Typing.CheckDetails do
  @moduledoc "myapp.check_details: checks the details a visitor entered."

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
  def io(_config), do: %{kinds: [:step], produces: "myapp.patron_application"}

  @impl true
  def palette_entry, do: %{label: "Check details", subject: "registration.visitor"}

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

Each signature is an ordinary field declaration, so you can build one and
read it on its own. `BlockType.value_path/1` says where the field's value
lives in the block's config, and the field's `type` is its signature:

```elixir
alias StatifierBlocks.BlockType

read = %{
  key: "applicant",
  type: {:path, %{expects: "CardApplicant"}},
  label: "Applicant",
  required?: true,
  default: "registration.visitor"
}

write = %{
  key: "assign_to",
  type: {:path, %{writes: "myapp.library_card"}},
  label: "Write the card to",
  required?: true,
  default: "registration.library_card"
}

read_path = BlockType.value_path(read)
#=> ["applicant"]

write_signature = %{write.key => write.type}
#=> %{"assign_to" => {:path, %{writes: "myapp.library_card"}}}
```

Put both on the block type that needs them:

```elixir
defmodule MyApp.Typing.IssueCard do
  @moduledoc "myapp.issue_card: issues a library card to a visitor whose details allow one."

  @behaviour StatifierBlocks.BlockType

  @impl true
  def current_version, do: 1

  @impl true
  def slots(_config), do: []

  @impl true
  def config_schema(_config),
    do: [
      %{
        key: "applicant",
        type: {:path, %{expects: "CardApplicant"}},
        label: "Applicant",
        required?: true,
        default: "registration.visitor"
      },
      %{
        key: "assign_to",
        type: {:path, %{writes: "myapp.library_card"}},
        label: "Write the card to",
        required?: true,
        default: "registration.library_card"
      }
    ]

  @impl true
  def validate_config(_config), do: :ok

  @impl true
  def io(_config), do: %{kinds: [:step]}

  @impl true
  def palette_entry, do: %{label: "Issue card"}

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
          Block.new("myapp.check_details",
            id: "blk_check_details",
            config: %{"invoke_type" => "myapp:check_details"}
          ),
          Block.new("myapp.issue_card",
            id: "blk_issue_card",
            config: %{
              "applicant" => "registration.visitor",
              "assign_to" => "registration.library_card"
            }
          )
        ]
      }
    ),
    id: "bdoc_patron_registration"
  )

palette =
  Palette.new(
    Map.merge(Palette.core_types(), %{
      "myapp.check_details" => MyApp.Typing.CheckDetails,
      "myapp.issue_card" => MyApp.Typing.IssueCard
    })
  )

ctx = %{datamodel: datamodel}

known_at_issue_card = Environment.at(palette, document, {"blk_root", "body", 1}, ctx)
#=> %{"registration.library_card" => "object", "registration.visitor" => "myapp.patron_application", "registration.visitor.age" => "integer", "registration.visitor.birth_date" => "date", "registration.visitor.full_name" => "string", "registration.visitor.submitted_at" => "datetime"}

verdict = Assignability.validate(palette, document, ctx)
#=> :ok
```

`registration.library_card` is in that map without any block having written
it: the environment seeds every path the datamodel declares, at the type it
declares there (ADR-0011 decision 2, amended 2026-09-06), and a type a block
writes replaces the seeded one from that position on - which is what
`registration.visitor` shows, seeded `object` and then written
`myapp.patron_application` by the entry block's `produces`.

The four paths beneath `registration.visitor` are there because that write names
a **record** (ADR-0011's Amendment of 2026-09-07): a write signature whose
type is a record, a shape, or an inline shape puts an entry at the path and
one at every member beneath it, at the member's own type, recursively and to
any depth. So a later step reading `registration.visitor.age` is
checked against `integer` rather than getting the nothing-is-known advisory,
and a declaration-only field naming that path is unnecessary. Nothing expands
through a `list`, and an explicit write signature at one of those member
paths wins over the member the record derived.

That is worth one sentence of care in a guide: a path your document declares
is now **checked**. A read at it that found nothing before, and was an
advisory, meets the declared type instead - so a document that validated may
refuse once its host supplies a datamodel, and the fix is either the block's
declaration or the document's.

The issue-card step expects `CardApplicant` and the environment holds
`myapp.patron_application`. That is not identity, so the check asks coverage:
`myapp.patron_application` has `full_name` and `age`, which is the whole of
`CardApplicant`'s required set. Satisfied.

To see a refusal, point the read at a shape the record does not cover:

```elixir
by_coverage =
  Environment.satisfies(declarations, "myapp.patron_application", "CardApplicant")
#=> :covers

refused =
  Environment.satisfies(declarations, "myapp.library_card", "myapp.patron_application")
#=> :not_assignable

permissive = Environment.satisfies(declarations, :unknown, "CardApplicant")
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
  Palette.new(Map.merge(Palette.core_types(), %{"myapp.issue_card" => MyApp.Typing.IssueCard}),
    assignability: MyApp.Typing.IssueCard
  )
```

## Read the result in the editor

Four surfaces show the environment, and none of them changes a verdict:

- **Findings carry the declared label.** A finding about a path renders the
  declaration's `label`, so an author reads "Patron application" rather
  than a nominal name they have to look up. A declaration with no `label`
  renders its name.
- **The Datamodel tab answers "what is known here".** Select a block and the
  drawer's Datamodel tab lists the paths the environment holds at that
  position, with their types.
- **Path controls offer candidates.** A `{:path, opts}` control offers the
  declared paths as candidates; with no datamodel, it is a plain text input.
- **The condition editor offers the operators the type allows.**
  `StatifierDatamodel.Index.path_types/1` projects the declared paths to the
  expression language's own value kinds, and the editor hands that map to
  statifier-ui (0.8 or later), so a condition on a path declared `integer`
  offers the numeric operators and one on a `date` path the date set. Like
  every other surface here it draws a control and decides nothing: the
  operator your author already wrote is still offered, their value is still
  kept, and a path the document does not declare is unchanged.
