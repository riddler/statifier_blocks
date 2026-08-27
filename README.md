# StatifierBlocks

[![CI](https://github.com/riddler/statifier_blocks/actions/workflows/ci.yml/badge.svg)](https://github.com/riddler/statifier_blocks/actions/workflows/ci.yml)
[![Hex.pm Version](https://img.shields.io/hexpm/v/statifier_blocks.svg)](https://hex.pm/packages/statifier_blocks)
[![Hex Downloads](https://img.shields.io/hexpm/dt/statifier_blocks.svg)](https://hex.pm/packages/statifier_blocks)
[![Hex Docs](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/statifier_blocks/)
[![License](https://img.shields.io/hexpm/l/statifier_blocks.svg)](https://github.com/riddler/statifier_blocks/blob/main/LICENSE)

Block document model, one-way SCXML compiler, and LiveView editor components
for composing [Statifier](https://github.com/riddler/statifier-ex) statecharts
from typed blocks.

Statecharts are the right execution model for long-running workflows, and
SCXML is the right interchange format for them - but neither is something a
non-engineer will author by hand. This package is the authoring layer:

- **A block document model.** The authoring artifact is a document: a tree of
  typed blocks that a person composes, each block a unit with a declared
  shape rather than free-form XML. The document, not the chart, is the source
  of truth that gets stored, versioned, and edited.

- **A one-way SCXML compiler.** The compiler turns a block document into an
  SCXML chart that Statifier can run, and carries a provenance map so a
  runtime position in the chart can be pointed back at the block that
  produced it. The direction is deliberate: documents compile to charts, and
  nothing decompiles a chart back into blocks.

- **LiveView editor components.** The components a host embeds to let people
  compose, rearrange, and validate a block document in a browser - the
  editing surface over the model above, sharing the family's rendering and
  fixtures conventions with
  [statifier_ui](https://github.com/riddler/statifier-ui).

Blocks are typed and host-pluggable: a host registers the block types its own
domain needs, and the compiler and editor work off that registry rather than
off a closed built-in vocabulary.

## Installation

```elixir
def deps do
  [
    {:statifier_blocks, "~> 0.1"}
  ]
end
```

## A worked example

A card-processing flow: place a hold, and settle it when the account has the
budget for it. Everything below runs - it is the example the suite executes on
every build.

**1. Write the block types your domain needs.** A block type is a behaviour
module: a handful of declarations plus one `emit/2`. These two are invoking
leaves, so they share their emission.

```elixir
defmodule MyApp.Blocks do
  @moduledoc "Emission helpers shared by this host's invoking leaves."

  alias StatifierBlocks.{Block, Emission}
  alias StatifierBlocks.Compiler.Context
  alias StatifierBlocks.Core.Emit

  @doc "One compound state that starts an `<invoke>` and finishes either way."
  def invoke_leaf(%Block{config: config}, %Context{} = context) do
    done = Context.done_id(context)
    {:ok, running} = Context.role_id(context, "running")
    {:ok, invocation} = Context.role_id(context, "invocation")

    waiting =
      Emit.state(running, nil, [
        Emission.element("invoke", [
          {"id", invocation},
          {"type", Map.get(config, "invoke_type", "")}
        ]),
        Emit.transition(event: "done.invoke." <> invocation, target: done),
        Emit.transition(event: "error.execution", target: done)
      ])

    {:ok, Emit.state(context.state_id, running, [waiting, Emit.final(done)])}
  end
end

defmodule MyApp.Blocks.Authorize do
  @moduledoc "`myapp.authorize`: places a hold on the card."
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
  def io(_config), do: %{kinds: [:step], produces: "myapp.credit_card_txn"}

  @impl true
  def emit(block, context), do: MyApp.Blocks.invoke_leaf(block, context)
end

defmodule MyApp.Blocks.Capture do
  @moduledoc "`myapp.capture`: settles a hold this flow already placed."
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
  def io(_config), do: %{kinds: [:step], consumes: "myapp.credit_card_txn"}

  @impl true
  def emit(block, context), do: MyApp.Blocks.invoke_leaf(block, context)
end
```

`io/1` is where a type declares how data flows through it. `produces` and
`consumes` are opaque strings compared for identity, widened only by a
relation the host supplies - there is no built-in type lattice.

**2. Compose the document.** Your two types, arranged by the `core.*`
structural vocabulary this package ships (`core.sequence`, `core.group`,
`core.branch`, `core.parallel`, `core.wait`, `core.resumable_group`,
`core.on_event`). In a running system an editor writes this tree; it is
ordinary data either way.

```elixir
alias StatifierBlocks.{Block, Compiler, Document, Palette, Provenance}

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
          Block.new("core.branch",
            id: "blk_approved",
            config: %{
              "arms" => [%{"slot" => "arm_approved", "cond" => "budget_remaining > amount"}]
            },
            slots: %{
              "arm_approved" => [
                Block.new("myapp.capture",
                  id: "blk_capture",
                  config: %{"invoke_type" => "myapp:capture"}
                )
              ]
            }
          )
        ]
      }
    ),
    id: "bdoc_card_capture"
  )
```

**3. Build a palette and compile.** A palette is a plain value - a
`type_name => module` map you build for one operation and pass explicitly.
It is deliberately not application config and not a named process, so two
tenants in one runtime never step on each other's block types.

```elixir
palette =
  Palette.new(
    Map.merge(Palette.core_types(), %{
      "myapp.authorize" => MyApp.Blocks.Authorize,
      "myapp.capture" => MyApp.Blocks.Capture
    })
  )

{:ok, compiled} = Compiler.compile(document, palette)
```

`Compiler.compile/3` is a total function of `{document, palette}`: no process
state, no clock, no IO. It returns `{:ok, %StatifierBlocks.Compiled{}}` or
`{:error, findings}` - never a raise, never a partial success. The artifact
carries the generated bytes, the provenance map, a compilation record joining
document identity to chart identity, and the invoke types the chart names:

```elixir
compiled.invoke_types
#=> ["myapp:authorize", "myapp:capture"]
```

The SCXML it produced is a chart Statifier runs as-is - one compound state per
block, completion signalled by `done.state`:

```xml
<scxml initial="s_blk_root" name="bdoc_card_capture" version="1.0" xmlns="...">
  <state id="s_blk_root" initial="s_blk_authorize">
    <transition event="done.state.s_blk_authorize" target="s_blk_approved" type="internal"/>
    <transition event="done.state.s_blk_approved" target="s_blk_root__done" type="internal"/>
    <state id="s_blk_authorize" initial="s_blk_authorize__running">
      <state id="s_blk_authorize__running">
        <invoke id="s_blk_authorize__invocation" type="myapp:authorize"/>
        ...
```

**4. Point a running position back at a block.** That is what the provenance
map is for. Hand it the active state ids of a live session and it answers with
the blocks the session is inside - which is how an editor highlights the step
a run is on, and how a chart-level finding routes back to the config field
somebody typed it into.

```elixir
active_state_ids = Map.keys(compiled.provenance.by_state_id)

blocks_in_play =
  compiled.provenance
  |> Provenance.owners_of_states(active_state_ids)
  |> Enum.map(& &1.block_id)
  |> Enum.uniq()
  |> Enum.sort()

#=> ["blk_approved", "blk_authorize", "blk_capture", "blk_root"]
```

For a fixed `{document canonical bytes, palette, compiler version}` the
generated SCXML is byte-identical on every machine and every run, and
`compiled.record` carries all three - so a host can skip a recompile on an
unchanged triple. The guarantee is not reversible: identical SCXML does not
mean an unchanged document, because `metadata` is not compiled.

The package's two full worked examples - this card-processing flow and a
signup wizard with A/B testing (`myapp:signup`, variants, conversion events) -
live in `test/support/document_fixtures.ex` and are stored as canonical bytes
under `test/fixtures/documents/`. Between them they reach the whole `core.*`
vocabulary.

## Config fields and where their values live

A block type's `config_schema/1` declares the fields the editor renders for
it. A field's `key` is its **identity**: the DOM id, the form param name, and
what a `{:config, block_id, key}` finding anchors to. Where the value is
*stored* is a second, separate question, and a field answers it with an
optional `value_path` - a list of keys and list indexes from the config root
down to the value it edits.

Most fields need no path: `key` alone addresses `config[key]`. Some cannot use
one. `core.branch` keys a condition field by the arm's slot name, because that
is what a finding has to name, while the condition itself is stored inside the
ordered `"arms"` list:

```elixir
alias StatifierBlocks.{BlockType, Core}

config = %{"arms" => [%{"slot" => "arm_approved", "cond" => "budget_remaining > amount"}]}

[field] = Core.Branch.config_schema(config)

field.key
#=> "arm_approved"

BlockType.value_path(field)
#=> ["arms", 0, "cond"]

BlockType.fetch_value(config, BlockType.value_path(field))
#=> {:ok, "budget_remaining > amount"}

BlockType.put_value(config, BlockType.value_path(field), "amount <= 5000")
#=> %{"arms" => [%{"cond" => "amount <= 5000", "slot" => "arm_approved"}]}
```

`value_path/1` answers `[key]` for a declaration that declares no path, so a
caller never branches on which case it has. `fetch_value/2` is total and
answers `:error` for a path that does not resolve; `put_value/3` writes the
last segment whether or not a value was already there - an arm with no
condition yet is exactly the one an author is about to type into - but never
invents an intermediate map or list a block type did not write. A host block
type that stores a value somewhere other than a top-level key declares the
path the same way.

## Using the editor

The editor ships in this package, and a host that never renders anything must
not pay for it. `phoenix_live_view` is therefore an **optional** dependency,
and every module under `StatifierBlocks.Editor.*` is compiled behind a
presence guard: an authoring API that compiles documents in a background job,
a test suite that exercises validation, a migration script - none of them drag
in Phoenix, and none of them compile a line of editor code.

A host that wants the editor already has LiveView, since there is nowhere else
to put the editor, so it adds nothing to `mix.exs`. It does three things:

**1. Import the hook.** The package's entire client-side surface is one hook.
Add the package to `assets/package.json`:

```json
{ "dependencies": { "statifier_blocks": "file:../deps/statifier_blocks" } }
```

and register it in `app.js`:

```javascript
import { StatifierBlocksDrag } from "statifier_blocks";

let liveSocket = new LiveSocket("/live", Socket, {
  hooks: { StatifierBlocksDrag },
});
```

**2. Import the stylesheet.** It is structural CSS only - the column layout,
the drag affordances, the finding treatments - with no visual opinion and no
framework:

```css
@import "../../deps/statifier_blocks/assets/css/statifier_blocks.css";
```

**3. Render the component.**

```heex
<.live_component
  module={StatifierBlocks.Editor}
  id="editor"
  document={@document}
  palette={@palette}
  on_change={&save_draft/1}
/>
```

Optional assigns: `findings` (yours, merged with the ones the view model
derives), `icon` (a function component that turns an icon *name* into markup -
this package never emits an icon set of its own), `expression_component` (an
override for `:expression` fields), `theme`, and `class`.

Underneath the component is a pure command algebra - `StatifierBlocks.Edit`
(insert, remove, move, update config, each with its inverse) over
`StatifierBlocks.ViewModel` - with no UI framework dependency at all. A host
that wants to drive document edits from something other than this editor uses
those directly.

### Theming

Every class the package emits is prefixed `sb-`, and every color, space,
radius and drag treatment is a `--sb-*` custom property with a default. Set
them through the `theme` assign, or in your own CSS against the prefix:

```heex
<.live_component
  module={StatifierBlocks.Editor}
  id="editor"
  theme={%{"--sb-accent" => "var(--brand-500)", "--sb-radius" => "10px"}}
  ...
/>
```

Enough that a host can make the editor look like its own product without
forking it, and not so much that the package acquires a theming DSL.

### What stays yours

Which palette entries a tenant may use, who may edit or publish a document,
where it is stored, and what publishing means. The editor is also a
single-session component: it surfaces the `revision` it loaded so you can do
optimistic concurrency on save, and it does not merge or resolve anything.

## Design records

The contracts this package is built out of are written down as ADRs in
[`docs/adr/`](https://github.com/riddler/statifier_blocks/tree/main/docs/adr):
the document schema (0001), the block-type behaviour (0002), host-pluggable
assignability (0003), the compiler and its provenance map (0004), and the
editor architecture (0005). A module's docs cite the decision it implements;
when the two disagree, the record is the contract and the code is the bug.

## License

MIT - see
[LICENSE](https://github.com/riddler/statifier_blocks/blob/main/LICENSE).
