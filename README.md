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
    {:statifier_blocks, "~> 0.14"}
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

That relation rides on the palette (`Palette.new(types, assignability:
MyApp.Blocks.Types)`) and it reaches every consumer through that one value.
`Assignability.validate/3` - what the compiler runs over the whole document -
and `Edit.Targets.slot_verdicts/3` - what the editor runs once at drag start
to mark every droppable slot before the pointer moves - are the same
implementation reading the same relation, so widening the host module opens a
drop target and clears the matching finding in the same edit. The relation can
only widen: identity is checked first, so a host callback can never refuse
something the default rule accepts.

Where a seam refuses, `Assignability.finding_reason/2` says why in a small
vocabulary (`:not_assignable`, `{:fixable_by, block_id}`), and
`Assignability.seam_reasons/3` names the seams that passed only because a
block declared nothing (`:source_untyped`, `:target_untyped`,
`:both_untyped`) - the way to find the parts of a palette you have not typed
yet. The editor stamps a refused slot's reason beside its validity as
`data-drop-reason`.

**2. Compose the document.** Your two types, arranged by the `core.*`
vocabulary this package ships. Twelve types: the containers that arrange
other blocks (`core.sequence`, `core.group`, `core.branch`, `core.parallel`,
`core.resumable_group`), and the leaves that do a structural thing on their
own (`core.wait`, `core.on_event`, `core.invoke`, `core.subchart`,
`core.send`, `core.raise`,
`core.assign`). None of them knows a domain - `core.invoke` *names* an invoke
type for the host to run and never runs one, and `core.subchart` names
another chart the same way. `StatifierBlocks.Core` carries
the table of all twelve with their slots. In a running system an editor
writes this tree; it is ordinary data either way.

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
    id: "bdoc_card_capture",
    datamodel: [
      %Document.DatamodelEntry{
        id: "budget_remaining",
        description: "What the card's budget has left before this authorization."
      },
      %Document.DatamodelEntry{id: "amount", description: "The amount being authorized."}
    ]
  )
```

The branch's condition reads `budget_remaining` and `amount`, so the document
declares both. A declaration names a **root** - storage exists at that name,
and everything beneath it is declared too (ADR-0001 decision 11). The
document's `datamodel` key is one of three surfaces that declare: a host's own
datamodel, the compile call's `:declare` roots, and this one. A document that
declares nothing and whose siblings declare nothing gets no undeclared-path
advisories at all - not because everything checked out, but because nobody
made a claim to check against, which is the case this example used to be in.

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
  <datamodel>
    <data id="budget_remaining"/>
    <data id="amount"/>
  </datamodel>
  <state id="s_blk_root" initial="s_blk_authorize">
    <transition event="done.state.s_blk_authorize" target="s_blk_approved" type="internal"/>
    <transition event="done.state.s_blk_approved" target="s_blk_root__o_done" type="internal"/>
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

## Registering your own block types

The `core.*` vocabulary is structural on purpose: it knows sequencing,
branching, waiting and parallelism, and nothing about anyone's domain. A
card-processing host adds the steps its own product has by writing a module
per step and handing the editor an **explicit list** of them where the editor
is mounted. There is no global registry, no application-configuration lookup,
and no discovery pass that finds every module implementing the behaviour -
each of those would make two tenants in one runtime share a vocabulary that
is supposed to be per palette.

```elixir
defmodule MyApp.Blocks.RiskHold do
  @moduledoc "myapp.risk_hold: parks an authorization until a reviewer clears it."

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
        default: "fraud"
      }
    ]

  @impl true
  def validate_config(config) do
    case Map.get(config, "queue") do
      queue when is_binary(queue) and queue != "" -> :ok
      _missing -> {:error, [{"queue", "name the queue a reviewer picks this up from"}]}
    end
  end

  @impl true
  def palette_entry,
    do: %{
      label: "Risk hold",
      group: "Payments",
      description: "Parks the authorization until a reviewer clears it.",
      badge: "manual review",
      accent_token: "--sb-accent-risk"
    }

  @impl true
  def emit(_block, context) do
    done = Context.done_id(context)

    with {:ok, holding} <- Context.role_id(context, "holding") do
      waiting =
        Emit.state(holding, nil, [
          Emit.transition(event: "myapp.risk.cleared", target: done)
        ])

      {:ok, Emit.state(context.state_id, holding, [waiting, Emit.final(done)])}
    end
  end
end

palette =
  StatifierBlocks.Palette.from_modules(
    [{"myapp.risk_hold", MyApp.Blocks.RiskHold}],
    core: true
  )

{:ok, risk_hold} = StatifierBlocks.Palette.fetch(palette, "myapp.risk_hold")

Map.has_key?(palette.types, "core.sequence")
#=> true

StatifierBlocks.BlockType.badge(risk_hold.palette_entry())
#=> "manual review"

StatifierBlocks.ViewModel.accent_token(risk_hold.palette_entry())
#=> "--sb-accent-risk"
```

`from_modules/2` is a value constructor and nothing more - the palette it
returns is passed into the editor, the compiler and validation explicitly,
the same way `Palette.new/2` and `Palette.core/0` are. The list is ordered
and later entries win, so `core: true` puts the core vocabulary underneath
and a host that deliberately swaps in its own `core.wait` writes it after.
The registration carries the type **name** as well as the module because the
document names a type by string and the palette resolves the string: the
mapping is the host's fact, which is what lets one module serve two names in
two tenants' palettes.

### Declaring a type instead of spelling it

Most host types have nothing to say about most callbacks. `use
StatifierBlocks.BlockType` declares the behaviour and injects the answer a
type gives when it has none of its own - no slots, no fields, nothing to
refuse, version 1, unconstrained assignability, no migration - each one
overridable, so a type writes only the rows where it differs. `emit/2` is
deliberately not among them: there is no emission to default to, and one
injected here would let a type that compiles nothing look complete.

A leaf step that **names** one host invoke type and waits for the answer is
the shape a host writes over and over, so it has a base of its own.
`use StatifierBlocks.InvokeStep` fills in all nine callbacks from a
declaration:

```elixir
defmodule MyApp.Blocks.Capture do
  @moduledoc "myapp.capture: captures the authorized amount."

  use StatifierBlocks.InvokeStep,
    invoke_type: "myapp:capture",
    produces: "myapp.capture",
    palette: %{
      label: "Capture",
      group: "Payments",
      description: "Captures the authorized amount.",
      icon: "banknotes"
    }
end

MyApp.Blocks.Capture.invoke_type()
#=> "myapp:capture"

Enum.map(MyApp.Blocks.Capture.config_schema(%{}), & &1.key)
#=> ["label", "invoke_type"]

MyApp.Blocks.Capture.outcomes(%{})
#=> [{"done", "Done"}, {"error", "Error"}]

MyApp.Blocks.Capture.io(%{})
#=> %{kinds: [:step], produces: "myapp.capture"}
```

That is the whole type. It compiles to an `<invoke>` in an inner state with
one transition and one `<final>` per outcome - `core.invoke`'s emission with
the `on_error` slot taken out, since a leaf step has no children and its
failure path is an outcome a parent may wire. `:fields` adds config fields
after `label` and `invoke_type`, and every injected callback is
overridable: a step with extra `<param>` children calls
`StatifierBlocks.InvokeStep.emit/4` itself, and one with a tighter rule
composes its own `validate_config/1` out of the checks the module exports.

It still only **names** an invoke type. What runs one is a handler the host
registers separately, per session - the two-registry seam this package
draws, which `use` does not cross. One type is the exception: see
"The one handler this package does ship" below.

### The three presentation declarations

A palette entry may also say how the editor should draw the type, and three
of those keys are worth calling out because a host reaches for them
immediately:

| Key | What it declares | Absent means |
|---|---|---|
| `accent_token` | the NAME of a `--sb-*` custom property, never a colour | the editor's own accent |
| `badge` | a short chip for the card header | no chip |
| `join_label` | a one-argument function of config, phrasing the join marker under a side-by-side arrangement | the editor's own word |

All three are read through a total normalizer that **refuses rather than
repairs**: a badge longer than 24 characters is dropped, not clipped, and one
carrying a newline is dropped rather than collapsed to a space, because a
truncated chip reads as a bug in the editor where a missing one reads as the
declaration it is. An accent that is not an anchored `--sb-*` name never
reaches a style attribute. A `join_label` is host code on the layout path, so
it is a pure function of its argument and it is called inside a rescue - a
type with a bug in it gets an ordinary join marker rather than taking the
canvas down.

## The handlers this package does ship

The seam above is unchanged: a block type still only **names** an invoke
type, and the host still registers the handler that runs it, per session.
`core.subchart` is the one type where that handler is generic enough to
write once and ship: "start the child chart this document names" is the
same code in every host, because a subchart's contract already fixes both
ends of it (`StatifierBlocks.Core.Subchart`'s moduledoc) - a child compiled
with `child_use: true`, its outcome carried on `<donedata>`, one final per
outcome. Nothing host-specific is left for a handler to decide except
*which* chart a document id names, so that is the one thing this handler
asks the host for.

`use StatifierBlocks.Runtime.Subchart` builds that handler from two
callbacks a host supplies: `resolve_chart/2`, which turns a document id
into a chart (or refuses to), and `palette/0`, the palette the child
compiles against. `handlers/1` turns the resulting module into the map
`Statifier.Session.start_link/2` expects for `:invoke_handlers`:

```elixir
defmodule MyApp.Charts do
  @moduledoc "Resolves a document id to the chart it names."

  use StatifierBlocks.Runtime.Subchart

  alias StatifierBlocks.{Document, Palette}

  @impl true
  def resolve_chart(document_id, _ctx) do
    case Map.fetch(document_store(), document_id) do
      {:ok, %Document{} = document} -> {:ok, document}
      :error -> :error
    end
  end

  @impl true
  def palette, do: Palette.core()

  defp document_store, do: Application.get_env(:my_app, :charts, %{})
end

StatifierBlocks.Runtime.Subchart.handlers(MyApp.Charts)
#=> %{"statifier_blocks:subchart" => MyApp.Charts}
```

A refusal to run the child surfaces on `error.communication.invoke` with
one of exactly three reasons: `unknown_document` (the resolver could not
place the id), `child_compile_findings` (the resolved document failed to
compile as a child), or `cycle_refused` (the resolver detected a
cross-document cycle a single-document compile cannot see for itself).

Placing the runtime is the host's job, not this package's: statifier ships
no `mod:` application callback, so a host that wants `Statifier.Session`
to run at all - subcharts or not - adds `Statifier.Supervisor` to its own
supervision tree, then passes `handlers/1`'s map as the `:invoke_handlers`
option on every `Statifier.Session.start_link/2` call that should run
subcharts.

### The durable variant

`start/2` staying a pure planning callback is what scopes the handler
above to the in-memory `Statifier.Session` case: a child that is its own
durably persisted run has to record its parent linkage as part of
starting, and a planning callback performs nothing.

So the durable variant is a **second module**,
`StatifierBlocks.Runtime.DurableSubchart` (ADR-0008). It takes the same
two callbacks, refuses for the same reasons, and answers at dispatch time
instead - `dispatch_fun/1` builds the fun
`StatifierPersistence.Driver`'s `:dispatch` option takes:

```elixir
dispatch = StatifierBlocks.Runtime.DurableSubchart.dispatch_fun(MyApp.Charts)
```

The child then runs as its own persisted run, linked to the parent's run
and invocation with a chart-identity pin, and its completion re-enters the
parent through the driver's own `done.invoke` door long after the process
that started it is gone. A durable start has one refusal reason the
in-memory handler cannot have - `child_run_creation_failed` - and the
driver raises it, since creating the run happens after this package has
answered. Nesting works with no extra wiring; fan-out (one invocation, N
children) is named by the record and not built.

Which variant runs is the host's session wiring, never the document: the
same block document compiles to the same bytes either way. A host that
wires the in-memory module into a durable run gets a child that does not
survive the restart the parent was made durable to survive.

Nothing in this package depends on `statifier_persistence`; the durable
module names no module from it and answers in plain tuples.

## Embedding the editor

The editor ships in this package, and a host that never renders anything must
not pay for it. `phoenix_live_view` is therefore an **optional** dependency,
and every module under `StatifierBlocks.Editor.*` is compiled behind a
presence guard: an authoring API that compiles documents in a background job,
a test suite that exercises validation, a migration script - none of them drag
in Phoenix, and none of them compile a line of editor code.

A host that wants the editor already has LiveView, since there is nowhere else
to put the editor, so it adds nothing to `mix.exs`. It does three things:

**1. Import the hooks.** The package's entire client-side surface is two hooks,
and the default export carries both, so registering them is one line. There
are two ways to make the specifier resolve, and which one you want depends on
whether your app runs `npm install` at all.

*If it does*, declare the dependency in `assets/package.json`. Point it at the
package's `assets/` directory, which is where the `package.json` lives - the
package ships no manifest at its root, so `file:../deps/statifier_blocks`
names a directory npm cannot read:

```json
{ "dependencies": { "statifier_blocks": "file:../deps/statifier_blocks/assets" } }
```

*If it does not* - the default for an app from the Phoenix generator, which
has no `assets/package.json` and no npm step - let esbuild resolve it the same
way it already resolves `phoenix` and `phoenix_live_view`, through `NODE_PATH`
pointed at `deps`:

```elixir
config :esbuild,
  my_app: [
    args: ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]
```

On this route the specifier is the path into the package rather than the bare
name, because `NODE_PATH` resolution walks `deps/` as a module directory and
does not read `assets/package.json`:

```javascript
import StatifierBlocks from "statifier_blocks/assets/js/statifier_blocks.js";
```

Registration is the same on either route - only the specifier differs, and
the bare name below is the npm one:

```javascript
import StatifierBlocks from "statifier_blocks";

let liveSocket = new LiveSocket("/live", Socket, {
  hooks: { ...StatifierBlocks },
});
```

Register **both**: `StatifierBlocksDrag` turns pointer gestures into commands,
and `StatifierBlocksMeasure` reports the laid-out geometry the server draws the
connectors from - without it nothing measures the browser's boxes, so no
connectors are drawn and the editor renders as stacked rows with no flow lines.
Both are still available as named exports, and a host that wants measurement
alone can import it from `statifier_blocks/measure` on the npm route, or from
`statifier_blocks/assets/js/statifier_blocks_measure.js` on the `NODE_PATH`
one (ADR-0005 decision 7 and its 2026-08-29 amendment, "a second hook that
only measures").

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
derives), `icon` (a function component that turns an icon *name* into markup),
`expression_component` (an override for `:expression` fields), `theme`, and
`class`.

**Icons.** You do not have to pass `icon`. The package ships
`StatifierBlocks.Editor.Icons`, a small set of inline SVGs for the names the
core block types declare - no font, no CDN, nothing to register in your asset
pipeline - and the editor uses it when you pass nothing. Every glyph paints
with `currentColor` and fills its tile, so the two tokens the tile reads
(`--sb-block-accent` and `--sb-block-accent-tint`) are all a theme has to
touch. See [`docs/theming.md`](https://github.com/riddler/statifier_blocks/blob/main/docs/theming.md).

Pass `icon` when you have an icon set of your own, and it wins on every tile -
the canvas cards and the palette rows alike. It is a component taking `name`
and `class`, and the *name* is what the block type declared:

```heex
<.live_component
  module={StatifierBlocks.Editor}
  id="editor"
  document={@document}
  palette={@palette}
  icon={&icon/1}
/>
```

```elixir
# A heroicons-style component: the name in, your markup out. The core types
# name heroicons ("clock", "bars-3", "arrow-path", ...), so a host already
# using them resolves every one by prefixing.
attr :name, :string, required: true
attr :class, :string, default: nil

def icon(assigns) do
  ~H"""
  <span class={[@class, "hero-" <> @name]} aria-hidden="true" />
  """
end
```

Yours is rendered as a **function component**, exactly as if the editor had
written `<.icon name={...} class={...} />` against it, so it gets a tracked
assigns map and every `Phoenix.Component` helper works inside it - `assign/3`,
`assign_new/3`, whatever you reach for to derive a value before the markup. It
has to return a `~H` template, which is the one thing the seam requires.

Two rules the seam keeps. A block type declares a **name**, never markup, so
nothing a palette entry carries is injected into the editor's render tree. And
a block type that declares no icon at all gets **no tile** rather than an empty
one, in the shipped set and in yours: your component is never called with a
`nil` name.

Underneath the component is a pure command algebra - `StatifierBlocks.Edit`
(insert, remove, move, update config, each with its inverse) over
`StatifierBlocks.ViewModel` - with no UI framework dependency at all. A host
that wants to drive document edits from something other than this editor uses
those directly.

### What the mounted component holds

The `document` you pass in, an undo history over it, the current selection,
and a `drafts` map of config edits the validation gate has not accepted yet.
A draft is never in the document and never on the undo stack: a form whose
config has not been accepted names the fields that are outstanding and offers
"Discard edits", because a draft was never a command and so cannot be undone.

There is a **`datamodel` assign**, and it carries paths rather than logic. A
host hands in the datamodel paths it declares, and the one thing that buys is
the undeclared-path advisory ADR-0005 amendments `11e`-`11g` specify: a config
field a block type annotated `datamodel_path?: true` whose value is not in
that set gets an `:info` finding anchored on the field. `nil` is the default,
and per `11f` it produces nothing anywhere - the check does not run at all -
which is not the same as an empty set, a host declaring that its documents
address nothing. Beyond that set the package still checks *shape* and nothing
more, because it does not own the datamodel path grammar: a host that wants
more than the advisory checks paths itself and hands the result in through
`findings`.

### The host seams that exist today

Everything a host can say about how its own types behave and look is a
declaration on a value it already passes in - the palette, the palette entry,
the theme - rather than a callback the editor calls back into:

| Seam | Declared on | What it does |
|---|---|---|
| `:assignability` | `Palette.new/2` (also `from_modules/2`) | the host's widening relation for "may this block land in this slot" - both gates, kind admission and data flow, run against the palette the caller passed (ADR-0003 decision 6) |
| `accent_token` | palette entry | the NAME of a `--sb-*` property, stamped on that type's cards and palette rows |
| `badge` | palette entry | a short chip for the card header |
| `join_label` | palette entry | a one-argument function of config, phrasing the join marker under a side-by-side arrangement |
| `slot_outcome_key` | palette entry | names the config key the blocks in one slot carry their outcome under, so a renderer routes an interrupt rule's escape without branching on a type name; it reaches the view model as `Slot.outcome_key` and the resolved value as `Node.outcome` |
| `--sb-*` tokens | the `theme` assign, or your own CSS | every colour, space, radius and drag treatment - see [`docs/theming.md`](https://github.com/riddler/statifier_blocks/blob/main/docs/theming.md) |
| compile findings | `findings` assign | `StatifierBlocks.Finding.from_compiler/2` adapts a compiler finding into the shape the editor renders, so a compile result routes back to the field somebody typed it into |
| `datamodel` | the `datamodel` assign | the datamodel paths the host declares; drives the undeclared-path advisory of ADR-0005 `11e`-`11g`, and `nil` (the default) turns it off entirely |

The metadata readers are total and refuse rather than repair: a badge that is
blank, carries a newline, or runs past 24 characters is dropped rather than
clipped, an accent that is not an anchored `--sb-*` name never reaches a style
attribute, and a `join_label` that raises degrades to the editor's own word.
Assignability answers with reason-carrying refusals (sb-ue7, in flight).

Routing a compile pass into the drawer's Findings tab is two calls:

```elixir
{lint_findings, _refused} =
  StatifierBlocks.Finding.from_compiler_all(compiled.warnings)
```

`from_compiler_all/2` returns the findings it could anchor and, separately,
the ones it refused with the reason - a finding that names no block has
nowhere in the editor to land, and dropping it silently would be the wrong
answer. Pass the anchored ones as the `findings` assign, or straight into
`StatifierBlocks.ViewModel.build/3` if you are driving the view model
yourself.

### Not yet

Honest about the edges, so you do not go looking for these:

- **Connectors.** Blocks are arranged by containment, and there is no
  free-floating edge between two cards. Whether the editor grows one is an
  open ADR-0005 decision-7 question (`sb-y14`).
- **A fixtures pane.** No panel drives a document against fixture rows, and
  nothing marks a block as currently invoking. ADR-0005 decision 15 defers
  the live half to the family's trace conventions (`sui-13q`).
- **A datamodel path grammar.** The undeclared-path advisory `11e`-`11g`
  settled is shipped, but only against the set of paths a host declares.
  Nothing here parses or validates a path beyond its shape, and a host that
  supplies no datamodel gets no advisory at all.

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

One of them is worth knowing before you embed rather than after. By default the
editor is as tall as the document in it and your page scrolls, which puts the
drawer below the fold on a long document. Set `--sb-editor-height` to a length -
`calc(100vh - 4rem)`, or `100%` inside a box your own layout has already sized -
to bound the editor instead: the panes scroll in their own boxes and the drawer
stays pinned at the bottom of it. The default is `auto`, so a host that does not
set it is unchanged.

[`docs/theming.md`](https://github.com/riddler/statifier_blocks/blob/main/docs/theming.md)
is the full guide: the three tiers the surface is organised into, why
`--sb-color-scheme` is not optional, how a block type gets an identity of its
own by naming a token, and a complete host theme you can copy. The rule it
holds itself to is that a theme sets `--sb-*` properties and writes no other
declaration - and that example is read out of the document and audited in the
gate, so it is checked rather than promised.

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
