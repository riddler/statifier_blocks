# How to register your own block types

This guide shows you how to add the steps your own domain needs to the
palette an editor and the compiler work from, beside the `core.*`
vocabulary this package ships.

The example is patron registration: a visitor becomes a library patron
through a few screens. The host adds two steps of its own - a librarian
approves the registration, and the visitor's library card is printed - and
one arrangement it writes over and over.

Every snippet on this page runs, in order, as one script:
[`test/statifier_blocks/readme_registration_test.exs`](https://github.com/riddler/statifier_blocks/blob/main/test/statifier_blocks/readme_registration_test.exs)
evaluates them on every build and asserts every `#=>` output against what
the code answers.

## Write a block type and register it

The `core.*` vocabulary is structural on purpose: it knows sequencing,
branching, waiting and parallelism, and nothing about anyone's domain.

1. Write one module per step, implementing `StatifierBlocks.BlockType`.

```elixir
defmodule MyApp.Blocks.LibrarianReview do
  @moduledoc "myapp.librarian_review: parks a registration until a librarian approves it."

  @behaviour StatifierBlocks.BlockType

  alias StatifierBlocks.Compiler.Context
  alias StatifierBlocks.Core.Emit

  @impl true
  def current_version, do: 1

  @impl true
  def slots(_config), do: []

  @impl true
  def config_schema(_config),
    do: [
      %{
        key: "queue",
        type: :string,
        label: "Review queue",
        required?: true,
        default: "front_desk"
      }
    ]

  @impl true
  def validate_config(config) do
    case Map.get(config, "queue") do
      queue when is_binary(queue) and queue != "" -> :ok
      _missing -> {:error, [{"queue", "name the queue a librarian picks this up from"}]}
    end
  end

  @impl true
  def palette_entry,
    do: %{
      label: "Librarian review",
      group: "Registration",
      description: "Parks the registration until a librarian approves it.",
      badge: "manual review",
      accent_token: "--sb-accent-myapp-review"
    }

  @impl true
  def emit(_block, context) do
    done = Context.done_id(context)

    with {:ok, holding} <- Context.role_id(context, "holding") do
      waiting =
        Emit.state(holding, nil, [
          Emit.transition(event: "myapp.registration.approved", target: done)
        ])

      {:ok, Emit.state(context.state_id, holding, [waiting, Emit.final(done)])}
    end
  end
end
```

2. Build a palette from an **explicit list** of your types with
   `StatifierBlocks.Palette.from_modules/2`, and hand it to the editor where
   the editor is mounted. There is no global registry, no
   application-configuration lookup, and no discovery pass that finds every
   module implementing the behaviour: each would make two tenants in one
   runtime share a vocabulary that is supposed to be per palette.

```elixir
palette =
  StatifierBlocks.Palette.from_modules(
    [{"myapp.librarian_review", MyApp.Blocks.LibrarianReview}],
    core: true
  )

{:ok, review} = StatifierBlocks.Palette.fetch(palette, "myapp.librarian_review")

Map.has_key?(palette.types, "core.sequence")
#=> true

StatifierBlocks.BlockType.badge(review.palette_entry())
#=> "manual review"

StatifierBlocks.ViewModel.accent_token(review.palette_entry())
#=> "--sb-accent-myapp-review"
```

3. Pass the palette into the editor, the compiler and validation
   explicitly. `from_modules/2` is a value constructor and nothing more, the
   same way `Palette.new/2` and `Palette.core/0` are.

4. Order the list deliberately. Later entries win, so `core: true` puts the
   core vocabulary underneath; if you swap in your own `core.wait`, write it
   after.

5. Name each type as well as its module. The document names a type by
   string and the palette resolves the string, so the mapping is your fact:
   one module can serve two names in two tenants' palettes.

## Declare a type instead of spelling it

Most host types have nothing to say about most callbacks.

1. Write `use StatifierBlocks.BlockType` to declare the behaviour and take
   the answer a type gives when it has none of its own - no slots, no
   fields, nothing to refuse, version 1, unconstrained assignability, no
   migration. Override only the rows where your type differs.

2. Write `emit/2` yourself. It is deliberately not injected: there is no
   emission to default to, and one injected here would let a type that
   compiles nothing look complete.

## Declare a step that calls one invoke type

A leaf step that **names** one host invoke type and waits for the answer is
the shape a host writes over and over, so it has a base of its own.

1. Write `use StatifierBlocks.InvokeStep` with a declaration. It fills in
   every callback:

```elixir
defmodule MyApp.Blocks.PrintCard do
  @moduledoc "myapp.print_card: prints the new patron's library card."

  use StatifierBlocks.InvokeStep,
    invoke_type: "myapp:print_card",
    produces: "myapp.library_card",
    palette: %{
      label: "Print card",
      group: "Registration",
      description: "Prints the new patron's library card.",
      icon: "identification"
    }
end

MyApp.Blocks.PrintCard.invoke_type()
#=> "myapp:print_card"

Enum.map(MyApp.Blocks.PrintCard.config_schema(%{}), & &1.key)
#=> ["label", "invoke_type"]

MyApp.Blocks.PrintCard.outcomes(%{})
#=> [{"done", "Done"}, {"error", "Error"}]

MyApp.Blocks.PrintCard.io(%{})
#=> %{kinds: [:step], produces: "myapp.library_card"}
```

   That is the whole type. It compiles to an `<invoke>` in an inner state
   with one transition and one `<final>` per outcome - `core.invoke`'s
   emission with the `on_error` slot taken out, since a leaf step has no
   children and its failure path is an outcome a parent may wire.

2. Adjust the declaration where your step differs:
   - The `error` outcome is **failure-classed** by default, so a step that
     comes back on it is a step that failed. If your `error` is routine,
     override `failure_outcomes/1` with `[]` in the same place you would
     override `outcomes/1`.
   - To add config fields after `label` and `invoke_type`, pass `:fields`.
   - For a step with extra `<param>` children, call
     `StatifierBlocks.InvokeStep.emit/4` yourself.
   - For a tighter rule, compose your own `validate_config/1` out of the
     checks the module exports.

3. Register what runs the invoke type separately. The type only **names**
   an invoke type; what runs one is a handler you register per session - the
   two-registry seam this package draws, which `use` does not cross. One
   type is the exception: see
   [The handlers this package does ship](../reference/config-fields-and-handlers.md#the-handlers-this-package-does-ship).

## Declare a type that stands for a subtree

An arrangement you write over and over - call a step, and record the
failure somewhere if it comes back on `error` - can be one block type
rather than a shape an author has to rebuild each time.

1. Write `use StatifierBlocks.Composite` with **params** plus a pure
   `subtree/1`:

```elixir
defmodule MyApp.GuardedStep do
  alias StatifierBlocks.Block

  use StatifierBlocks.Composite,
    name: "myapp.guarded_step",
    params: [
      %{key: "invoke_type", type: :string, label: "Call",
        required?: true, default: ""},
      %{key: "failure_path", type: :string, label: "Record the failure at",
        required?: true, default: "", datamodel_path?: true}
    ],
    sentence: "Call {invoke_type}, recording failure at {failure_path}",
    palette_entry: %{label: "Guarded step", group: "Structure"},
    version: 1

  @impl true
  def subtree(params) do
    [
      Block.new("core.invoke",
        id: "call",
        config: %{"invoke_type" => params["invoke_type"], "assign_to" => ""},
        slots: %{"on_error" => [
          Block.new("core.assign",
            id: "guard",
            config: %{"path" => params["failure_path"], "value" => "failed"})
        ]}
      )
    ]
  end
end
```

2. Write `params` as a list of ordinary field declarations - no new key and
   no new field type. It **is** the type's `config_schema/1`, so every
   declaration check the compiler already runs runs over it for free.

3. Keep `subtree/1` pure: the same params answer the same blocks, forever.
   The ids it writes are local, minted by
   `StatifierBlocks.Composite.expand!/2` as
   `composite_id <> "_" <> local_id`, so the members inherit the composite
   block's own uniqueness rather than being freshly generated on every
   call.

4. Override only what presents or refuses. The `use` derives
   `config_schema/1`, `slots/1`, `io/1`, `outcomes/1`, `current_version/0`,
   `sentence/1`, `palette_entry/0` and a raising `emit/2`; only
   `sentence/1`, `palette_entry/0` and `validate_config/1` are overridable,
   because the others are about the expansion rather than about
   presentation or refusal. If you already ship the arrangement as a
   recipe, use the `StatifierBlocks.Recipe` the `use` derives at
   `<Module>.Recipe`: its `insert/2` puts down **one composite block** - one
   command, not the expansion.

Know three things before you reach for one:

- **The compiler expands it, at the Resolve stage.** A document holding a
  composite that declares no `outcomes` compiles to bytes identical to the
  same document with that composite expanded in place, so nothing about the
  chart depends on which of the two the author stored. A composite that
  declares `outcomes` is the exception: since 0.30.0 it compiles to a state
  of its own enclosing its expansion, with one `<final>` per declared
  outcome and an `on_<name>` slot for each, and the compiler writes that
  state from the expansion itself. Either way `emit/2` raises if it is ever
  reached, because the compiler never calls a composite's own `emit/2`.
  [How to migrate a document from 0.27 to 0.34](migrating-documents-0.27-to-0.34.md)
  shows a document moving onto declared outcomes.
- **A finding inside an expansion is reported against the composite.** It
  carries the key of the param that produced the expanded block, or no key
  at all where no single param is responsible - never an anchor on a block
  the author cannot see. A declaration that cannot be expanded is a
  `:composite_expansion_failed` finding at `:resolve` rather than a raise.
- **A composite exposes only the slots it declares.** `slots/1` is `[]`
  unless the declaration names **pass-through slots** - `use
  StatifierBlocks.Composite, slots: [%{name: "body", to: {"call",
  "on_error"}}]` on a module, or a declaration-level `"slots"` key on a
  `Composite.Data` row - and each one it names is drawn as an interior on
  the card. `expand!/2` splices the children the author put there into the
  mapped slot of the mapped member, ids unchanged, so the chart is still
  the one the expansion by hand would have produced. A child's findings are
  the child's own, at the child. `Composite.pass_through/2` resolves each
  declared slot to the minted id it maps into, and
  `Composite.mapping_errors/2` answers the three refusals a mapping can
  earn against its own subtree.

### If your users save block types

You do not have to generate a module per type.

1. Declare the type as data with `StatifierBlocks.Composite.Data`: params,
   a subtree template with one `"$param"` placeholder arm and one
   `"$literal"` escape. It registers as a `{module, state}` palette entry
   beside the bare modules and expands through the same
   `Composite.expand!/2`, so a data composite and the module composite of
   the same shape expand to the same blocks and compile to the same bytes.

2. Check each declaration with `Composite.Data.declaration/1`, which
   refuses a malformed one before it reaches a palette.

3. Use any field type a module declares. All nine field types have a JSON
   spelling - `select`, `path`, `list` and `type_expr` being the type's
   name plus an optional `"options"` key.

4. Spell in the declaration the two keys a module composite spells in
   Elixir:
   - `"slots"` declares the pass-through slots above,
     `name => [local_id, inner_slot]`.
   - `"migrations"` declares an ordered chain of `rename` / `drop` /
     `default` steps, each keyed by the `type_version` it migrates from, so
     a block an author saved against an older `type_version` of a *saved*
     type resolves rather than being refused.
     `Composite.Data.migrate_config/3` walks every step at or above the
     stored version in one call, and the whole chain - shapes, gaps, order,
     and keys the declaration's own params do not account for - is
     validated at `declaration/1` rather than at the first stored block
     that needs it.

## Declare how the editor draws the type

A palette entry may also say how the editor should draw the type. Three of
those keys are the ones you reach for first:

| Key | What it declares | Absent means |
|---|---|---|
| `accent_token` | the NAME of a `--sb-*` custom property, never a colour | the editor's own accent |
| `badge` | a short chip for the card header | no chip |
| `join_label` | a one-argument function of config, phrasing the join marker under a side-by-side arrangement | the editor's own word |

1. Keep a badge to 32 characters or fewer, on one line. All three keys are
   read through a total normalizer that **refuses rather than repairs**: a
   longer badge is dropped, not clipped, and one carrying a newline is
   dropped rather than collapsed to a space.

2. Name an accent as an anchored `--sb-*` custom property, and define it in
   your theme; see
   [How to theme the editor](../theming.md#per-block-type-accents). An
   accent that is not an anchored `--sb-*` name never reaches a style
   attribute.

3. Write a `join_label` as a pure function of its argument. It is host code
   on the layout path and it is called inside a rescue, so a type with a
   bug in it gets an ordinary join marker rather than taking the canvas
   down.
