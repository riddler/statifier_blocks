# StatifierBlocks

[![CI](https://github.com/riddler/statifier_blocks/actions/workflows/ci.yml/badge.svg)](https://github.com/riddler/statifier_blocks/actions/workflows/ci.yml)
[![Hex.pm Version](https://img.shields.io/hexpm/v/statifier_blocks.svg)](https://hex.pm/packages/statifier_blocks)
[![Hex Downloads](https://img.shields.io/hexpm/dt/statifier_blocks.svg)](https://hex.pm/packages/statifier_blocks)
[![Hex Docs](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/statifier_blocks/)
[![License](https://img.shields.io/hexpm/l/statifier_blocks.svg)](https://github.com/riddler/statifier_blocks/blob/main/LICENSE)

> **Pre-1.0.** Until `statifier_blocks` reaches v1.0, its public surface may change
> between minor releases, sometimes drastically: a release may rename modules,
> callbacks, table columns, telemetry events or error vocabulary with no
> compatibility shim. Every such change is recorded in
> [CHANGELOG.md](CHANGELOG.md) under a bold **Breaking** heading that says what
> to do about it. Pinning to an exact minor - `~> X.Y.0` - is the recommended way
> to consume the package until 1.0.

Block document model, one-way SCXML compiler, and LiveView editor components
for composing [Statifier](https://github.com/riddler/statifier-ex) statecharts
from typed blocks.

Statecharts are the right execution model for long-running workflows, and
SCXML is the right interchange format for them - but neither is something a
non-engineer will author by hand. This package is the authoring layer:

- **A block document model.** The authoring artifact is a document: a tree of
  typed blocks that a person composes, each block a unit with a declared
  shape rather than free-form XML. The document, not the chart, is the source
  of truth that gets edited and stored, one revision per saved edit. The
  four nouns this README uses - document, revision, chart, execution - have
  one job each; [Document, revision, chart and
  execution](#document-revision-chart-and-execution) says which.

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
    {:statifier_blocks, "~> 0.44.0"}
  ]
end
```

Two dependencies are **optional** and neither is added for you:
`phoenix_live_view`, without which no editor module compiles at all, and
`statifier_ui`, which an `:expression` field uses for its expression editor
when it resolves. See [Embedding the editor](#embedding-the-editor).

Moving a host up from 0.31, one minor at a time:
[`docs/upgrading.md`](https://github.com/riddler/statifier_blocks/blob/main/docs/upgrading.md)
says what the host changes at each release, and names the calls a publish
step makes.

A document written against 0.27 still compiles. To have a composite in it say
how it finished - declared `outcomes`, a handler's `finish_as` and the
`on_<name>` slots an author fills - see
[`docs/guides/migrating-documents-0.27-to-0.34.md`](https://github.com/riddler/statifier_blocks/blob/main/docs/guides/migrating-documents-0.27-to-0.34.md).

Shapes a workflow commonly needs, built from the core block types - starting
with a step that must finish within a bound or the flow continues - are in
[`docs/guides/flow-patterns.md`](https://github.com/riddler/statifier_blocks/blob/main/docs/guides/flow-patterns.md).

## Documentation

- Do
  - [How to build a block document and compile it to a chart](docs/guides/build-and-compile.md) -
    write two block types, compose a document, compile it and point a running
    position back at its blocks
  - [How to register your own block types](docs/guides/register-block-types.md) -
    write a block type, declare one from a base or a subtree, and build a
    palette from your own types beside the core vocabulary
- Look up
  - [Config fields and the handlers this package ships](docs/reference/config-fields-and-handlers.md) -
    where a config field's value is stored, and the invoke handler the package
    ships for `core.subchart`

## Typing a palette

A block type can declare what it reads and writes at a datamodel path, and
the walk that carries those declarations through a document is what lets the
editor refuse a step that reads a path nothing put the right thing at.

Both signatures are declared on a **field**, not on the block, so a finding
anchors on the control an author has to change:

```elixir
alias StatifierBlocks.{BlockType, Environment}

read = %{
  key: "subject",
  type: {:path, %{expects: "Settleable"}},
  label: "Transaction",
  required?: true,
  default: "cards.current_txn"
}

write = %{
  key: "assign_to",
  type: {:path, %{writes: "cards.settlement"}},
  label: "Write the settlement to",
  required?: true,
  default: "cards.settlement"
}

read_path = BlockType.value_path(read)
#=> ["subject"]

declarations =
  StatifierDatamodel.Declarations.from_document(%{
    "types" => [
      %{
        "name" => "cards.credit_txn",
        "kind" => "record",
        "label" => "Credit card transaction",
        "fields" => [
          %{"name" => "amount_minor", "type" => "integer", "required?" => true},
          %{"name" => "currency", "type" => "string", "required?" => true}
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
  })

satisfied = Environment.satisfies(declarations, "cards.credit_txn", "Settleable")
#=> :covers

label = Environment.type_label(declarations, "cards.credit_txn")
#=> "Credit card transaction"

write_signature = %{write.key => write.type}
#=> %{"assign_to" => {:path, %{writes: "cards.settlement"}}}
```

A field declaring `expects` and no `writes` is a read and not also a write. A
`{:path, opts}` field carrying neither - and a `:string` field carrying
`datamodel_path?: true` - writes `:unknown`: the path becomes known without
becoming typed. `io/1`'s `consumes` and `produces` are sugar for a read and a
write at the document's subject path, which the entry block's palette entry
names with `subject:`.

The records and shapes themselves live in the datamodel document's `types`
key, which `statifier_datamodel` owns, and the read check is that package's
`StatifierDatamodel.Types.satisfies/3` - unknown is permissive both ways,
identity is nominal, and a record satisfies a shape when it covers the
shape's required fields. This package defines no second read check.

[`docs/typing-a-palette.md`](https://github.com/riddler/statifier_blocks/blob/main/docs/typing-a-palette.md)
is the how-to: declaring records and shapes, naming the subject, projecting a
host schema into the document with the scalar mapping table, and what a host
re-resolves at publish.

## Document, revision, chart and execution

This README uses four nouns, each with one job, the same four the engine's
[persistence guide](https://github.com/riddler/statifier-ex/blob/main/docs/persistence.md#the-four-nouns)
uses:

| Noun | What it is here | Identity | Owner | Changes when |
|---|---|---|---|---|
| **Document** | The block tree an author edits, under one stable id | The `id` of a `%StatifierBlocks.Document{}` | The host's authoring store | Never |
| **Revision** | One saved edit of a document | The document id plus the ordinal in the document's `revision` field | The host's revision store; this package stores nothing | Every saved edit |
| **Chart** | The SCXML `StatifierBlocks.Compiler.compile/3` emits for a revision | `chart_identity`: the SHA-256 hash of the SCXML bytes, plus the document id as `:chart_name` and a `nil` `:chart_version` (`Statifier.Machine.Identity`, the engine's ADR-0052) | The engine | A byte of the SCXML changes |
| **Execution** | One instance of a chart a host starts | A minted id, pinned to one chart identity | The persistence package or the host | Re-pinned only by an explicit migration |

`StatifierBlocks.CompilationRecord` is the bridge between a revision and a
chart. Every successful compile returns one as `compiled.record`: the
revision's side (`document_id`, `revision`, and `document_hash`, the
SHA-256 of the revision's canonical bytes), the compile inputs (`palette_hash`,
`compiler_version`) and the chart's side (`chart_identity`). Neither hash
is derived from the other - two revisions that differ only in `metadata`
compile to one chart - so the compile emits the join as a fact. An
execution names its chart identity; looking the record up by
`chart_identity` gives back the document, and the revision or revisions
that compiled to that chart.

Three more parts of the compiled artifact, in the same nouns:

- **`accepts`** is a document field, so each revision carries its own
  list: the names of the external events it declares its chart accepts.
  The compile passes it through onto `compiled.accepts` and
  `compiled.record.accepts` without judging it. It never reaches the
  SCXML, so a revision that edits only `accepts` compiles to the same
  chart. Whether the chart can take each name is a publish-time question
  (step 4 below).
- **`interface`** on `%StatifierBlocks.Compiled{}` is what the chart offers
  a parent that invokes it - the outcomes and done-data keys its root
  declares - and what it relies on from each document it names. A child is
  named by document id, never by chart: which revision, and so which
  chart, an id resolves to is the host's resolver's answer. `interface`
  adds nothing to the SCXML and is not on the record.
- **`StatifierBlocks.Publish.findings/3`** judges one revision - the
  document the host is about to publish - and emits no SCXML, so it runs before
  any chart for that revision exists. The host refuses to publish the
  revision on an `:error`.

Publishing makes a chart and its record, and touches no execution. An
execution already running stays pinned to the chart it started on; moving
it to another chart is an explicit migration a host performs, never a side
effect of a publish, and nothing in this package migrates one.

## At publish

The package ships the checks, not the publish. The host's publish step, its
registries, its revision store and its editor UI are the host's; this package
ships pure functions that step calls, and the host refuses the publish on what
they find. There is no publish step, publish store or process in here.

The step calls them in this order:

1. **`StatifierBlocks.Publish.findings/3`**, with the revision being
   published (the document as saved), the palette
   and the context map the editor takes (`:datamodel`, `:declare`,
   `:chart_outcomes`, every key optional). It runs the compile's stages
   before Emit through `StatifierBlocks.Compiler.structure_findings/3`, then
   the editor's own composition over their answer, and returns
   `StatifierBlocks.Finding`s in the editor's order. It emits nothing. A
   document the compile's Document stage refuses comes back as one finding
   anchored `:document`, and nothing else.
2. **`StatifierBlocks.Compiler.compile/3`**, with the same `:datamodel` and
   `:declare`. It adds what only the stages after Structure can find. Its
   refusal and its warnings are `StatifierBlocks.Compiler.Finding`s;
   `StatifierBlocks.Finding.from_compiler_all/2` adapts them to the same
   shape.
3. **The document graph**, over the `%StatifierBlocks.Compiled{}` the compile
   returned. Publishing a parent, the host calls
   `StatifierBlocks.Graph.check/2` with its resolver from a document id to
   the compiled artifact of that document's published revision; publishing
   a new revision of a child, it calls
   `StatifierBlocks.Graph.consumers_broken/2` with the published parents it
   says name that child, and it pairs each finding with that parent's
   document id. Each call judges pairs; walking the graph is the host's
   (ADR-0008's Amendment of 2026-09-22).
4. **The `accepts` declaration**, for a revision that carries one. The
   engine's `Statifier.Chart.check_accepts(machine, declared)` judges
   `compiled.accepts` against the chart that revision compiled to, the one
   the host will start executions on (ADR-0014 decision 4). It is the
   engine's function, arriving in the engine's next minor release, and this
   package runs no check of its own for that rule. It answers a map, not
   findings: the declared names no reachable transition can take
   (`unreachable`) and the reachable descriptors no declared name matches
   (`undeclared`). A declared name in `unreachable` refuses the publish;
   `undeclared` is internal, never an error (ADR-0014 decision 4).

Every answer from steps 1 to 3 is a finding with one of three severities,
and the rule is the same whichever of those calls reported it:

- **`:error` refuses the publish.**
- **`:warning` is the host's call.** A reasonable host publishes over one and
  shows it to the author who published, the way the drawer already showed it
  while they edited; a host that wants a warning to stop a publish asks the
  author to confirm first. What it should not do is drop it.
- **`:info` never refuses.** A config value naming a datamodel path the host
  does not declare is `:info`: an advisory, not a refusal.

The editor shows the same findings live because it runs the same functions:
the findings it derives, the undeclared-path advisories, the subchart outcome
disagreements and the palette's validators are what step 1 composes. Handed
the adapted `StatifierBlocks.Compiler.structure_findings/3` list as its
`findings` assign, the editor's list for a document equals
`Publish.findings/3`'s for the same palette and context, order included, and
`StatifierBlocks.Editor.findings_count/3` is its length (ADR-0004's Amendment
of 2026-09-22, G4). Steps 3 and 4 read a compiled artifact and are not in the
editor's list.

A host's check, written against those calls:

```elixir
defmodule MyApp.Publishing do
  @moduledoc "The host's publish check: the package's findings, the host's verdict."

  alias StatifierBlocks.{Compiler, Finding, Publish}

  def check(document, palette, context) do
    findings = Publish.findings(document, palette, context)

    # The compile would refuse with the same stage-1-to-4 findings, so a
    # document already refused here is not compiled.
    if refuses?(findings) do
      {:refused, findings}
    else
      opts = context |> Map.take([:datamodel, :declare]) |> Map.to_list()

      case Compiler.compile(document, palette, opts) do
        {:ok, compiled} ->
          {warnings, _no_anchor} = Finding.from_compiler_all(compiled.warnings)
          {:ok, compiled, findings ++ warnings}

        {:error, refusal} ->
          {adapted, _no_anchor} = Finding.from_compiler_all(refusal)
          {:refused, findings ++ adapted}
      end
    end
  end

  defp refuses?(findings), do: Enum.any?(findings, &(&1.severity == :error))
end
```

Take the patron registration document from ADR-0014, the one that waits for a
new patron's email to be verified, and add a `core.assign` that writes
`patron.card_number`. The host declares `patron.email` and nothing else.

- While the author edits, the drawer shows one row on that block's `path`
  field: `patron.card_number is not declared in the datamodel`, severity
  `:info`.
- At publish, `Publish.findings/3` returns that same finding and nothing
  else. Nothing is an `:error`, the compile succeeds, and the host publishes.
  The author saw the advisory before pressing publish, and the publish does
  not refuse on it.
- Leave the `core.await`'s `event` blank instead and the answer is an
  `:error` on `{:config, block_id, "event"}`: in the drawer as the author
  clears the field, and in `Publish.findings/3`'s list, so the host refuses.

## Validating and describing a document

Two read-only views of a saved document, neither of which compiles it: a
JSON Schema that a host in any language can check a stored document against,
and a description of the document in words.

### Validating a document against the schema from any language

The package ships the block document's JSON Schema (draft-07) at
`priv/schemas/block-document.schema.json`. `StatifierBlocks.Schema.path/0`
names the installed file, so a build step can copy it into a service written
in another language, and `StatifierBlocks.Schema.json/0` hands over its
content. This package ships no validator and runs none; a host checks a
document with a draft-07 validator in its own language.

```elixir
alias StatifierBlocks.Schema

same_file = File.read!(Schema.path()) == Schema.json()
#=> true

draft = Schema.json() |> JSON.decode!() |> Map.fetch!("$schema")
#=> "http://json-schema.org/draft-07/schema#"
```

Any draft-07 validator reads the file. Here it is ex_json_schema, the one this
package's own tests use (a test-only dependency, never a dependency of this
package at runtime), checking a library-loan document that a service stored as
JSON:

```elixir
schema = Schema.path() |> File.read!() |> JSON.decode!() |> ExJsonSchema.Schema.resolve()

stored = ~s({
  "schema_version": 1,
  "id": "bdoc_library_loan",
  "revision": 3,
  "root": {
    "id": "checkout",
    "type": "core.send",
    "type_version": 1,
    "config": {"event": "loan.checked_out"}
  }
})

checked = ExJsonSchema.Validator.validate(schema, JSON.decode!(stored))
#=> :ok

missing_root = stored |> JSON.decode!() |> Map.delete("root")
refused = match?({:error, [_ | _]}, ExJsonSchema.Validator.validate(schema, missing_root))
#=> true
```

The schema never refuses a document `StatifierBlocks.Document.from_json/1`
accepts, but it admits some that `from_json/1` refuses: a document that
repeats a block id or a datamodel entry id, and a whole number spelled with a
fraction or an exponent (`1.0`, `1e2`) where an integer is read. A document
that passes the schema is worth handing to `from_json/1`; only `from_json/1`
says it is one. The typed `config` and `slots` descriptions of the `core.*`
types sit under `definitions/core` and the root does not apply them, so a
block of a host type validates. `StatifierBlocks.Schema`'s docs list every
difference, and [ADR-0015](https://github.com/riddler/statifier_blocks/blob/main/docs/adr/0015-block-document-json-schema.md)
is the record.

A host that knows its palette can ask for a stricter schema.
`StatifierBlocks.Schema.for_palette/1` answers the same root with every block
also judged by its own type's definition: a `core.*` type's from
`definitions/core`, and a host type's generated from its declared
`config_schema/1` and `slots/1`, each declared field typed from its declared
field type (or `null`) with its label as `title` and its default as
`default`. A `core.*` type is judged by its `definitions/core` entry as
shipped, required keys and identifier patterns included. For a host type,
nothing past a field's declared type is checked: bounds, cross-field rules and
whether a field must be present stay with the type's `validate_config/1`. A
block of a type the palette does not carry is judged by the generic shape
alone.

```elixir
palette_schema =
  StatifierBlocks.Palette.core() |> Schema.for_palette() |> ExJsonSchema.Schema.resolve()

typed = ExJsonSchema.Validator.validate(palette_schema, JSON.decode!(stored))
#=> :ok

numbered = put_in(JSON.decode!(stored), ["root", "config", "event"], 5)
root_admits = ExJsonSchema.Validator.validate(schema, numbered)
#=> :ok

palette_refuses =
  match?({:error, [_ | _]}, ExJsonSchema.Validator.validate(palette_schema, numbered))
#=> true
```

The package holds a config to the same declared field types: a value its
field's declared type does not admit is refused at compile, at the edit gate
and in the view model, ahead of the type's own `validate_config/1` findings.
Before taking the version that made that so, run
`StatifierBlocks.Palette.preflight/1` over your palette. It lists every host
type whose own defaults, or the block `Palette.new_block/2` builds from them,
disagree with their declared field types, each finding naming the type, the
field's key, its declared type and the value; a type whose callbacks raise is
listed, not raised. `StatifierBlocks.Palette.preflight/2` takes the documents
you store as well and also lists every block of a type the palette carries
whose config would be refused, by block id. An empty list means you are ready.

### Describing a document

`StatifierBlocks.Describe.outline/3` reads a document under a palette into
one node per block and the edges by which control passes between them, found
from the document's structure; `StatifierBlocks.Describe.render/2` writes one
line of English per node and then one per edge. Neither compiles the
document, reads a clock, starts a process, reaches a network or asks a
language model, and equal input answers byte-identical lines.

```elixir
alias StatifierBlocks.{Block, Describe, Document, Palette}

loan =
  Block.new("core.sequence",
    id: "loan",
    slots: %{
      "body" => [
        Block.new("core.send", id: "checkout", config: %{"event" => "loan.checked_out"}),
        Block.new("core.await",
          id: "returned",
          config: %{"event" => "loan.returned", "timeout" => "21d"}
        )
      ]
    }
  )

outline = loan |> Document.new(id: "bdoc_library_loan") |> Describe.outline(Palette.core(), [])

lines = Describe.render(outline, [])
#=> ["Run its steps in order", "Send loan.checked_out", "Wait for loan.returned, giving up after 21d", "The steps start with Send loan.checked_out", "After Send loan.checked_out (done), Wait for loan.returned, giving up after 21d", "Wait for loan.returned, giving up after 21d (received, timed_out) ends the steps"]

edge_kinds = Enum.map(outline.edges, & &1.kind)
#=> [:entry, :sequence, :exit]
```

The outline is data as well as lines: each `StatifierBlocks.Describe.Node`
carries the block's id, parent, depth, sentence and declared outcomes, and
each `StatifierBlocks.Describe.Edge` its kind and endpoints. Edges are found
inside `core.sequence`, `core.group`, `core.resumable_group` and `core.branch`;
every other type is described by containment and its node's fan label alone.
One more kind, `:timer`, is read across the whole document: a delayed
`core.send` reaches each `core.on_event` and `core.await` that names its
event, labelled with the delay.

### Overriding the phrasing

A host rewords the lines through a module implementing
`StatifierBlocks.Describe.Phrasing`, passed as `phrasing:`. Each line is
offered to the callback for its node's or edge's `kind`, with the structured
node or edge and the default line; the callback answers its own line or
`:default`. Every callback is optional, and a blank answer, one carrying a
newline, carriage return or tab, or a callback that raises keeps the default
line.

```elixir
defmodule MyApp.LoanPhrasing do
  @behaviour StatifierBlocks.Describe.Phrasing

  alias StatifierBlocks.Describe.Edge

  @impl true
  def sequence(%Edge{from: {:block, "checkout"}}, _default), do: "Once the book is out, wait for its return"
  def sequence(%Edge{}, _default), do: :default
end

reworded = Describe.render(outline, phrasing: MyApp.LoanPhrasing)
#=> ["Run its steps in order", "Send loan.checked_out", "Wait for loan.returned, giving up after 21d", "The steps start with Send loan.checked_out", "Once the book is out, wait for its return", "Wait for loan.returned, giving up after 21d (received, timed_out) ends the steps"]
```

The seam rewords lines; it does not add, drop or reorder them. For the lines
to stay byte-identical for equal input, a callback has to be a pure function
of its arguments.

[`docs/describing-a-document.md`](https://github.com/riddler/statifier_blocks/blob/main/docs/describing-a-document.md)
is the how-to: reading the outline's structure, the edges each container
type draws, and rewording nodes and edges. [ADR-0016](https://github.com/riddler/statifier_blocks/blob/main/docs/adr/0016-document-describes-itself.md)
is the record.

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
`expression_component` (an override for `:expression` fields),
`value_candidates` (the values you offer per datamodel path), `on_select` (a
panel of yours that follows the canvas selection), `on_collapse` (the
declaration the "Save as a step" gesture proposes), `debounce` (what
`phx-debounce` the inspector's config controls carry), `theme`, and `class`.
`StatifierBlocks.Editor`'s own moduledoc carries the full assign table; the
seam table below says what a host declares on each of them.

**Following the selection.** `on_select` is `on_change`'s sibling for the
other subject a host may want: a one-argument function called with each new
selection, so a drawer tab, a preview or a detail pane of your own can follow
the canvas instead of making the operator pick the same block twice. What
arrives is a descriptor - `%{id:, type:, label:}`, where `label` is the line
the card draws - and `nil` when nothing is selected, which is how a panel
knows to empty itself. It fires when the selection changes and not otherwise,
it is optional, and a host that passes nothing sees no difference of any kind.
The block's config is deliberately not in it: you already hold the document
you passed in.

**Expression fields.** With `statifier_ui` on your load path an `:expression`
renders that package's own expression editor: picklists of field, operator and
value while the source is inside the subset predicator can round-trip, and a
text input over everything else. It never refuses what an author typed and
never rewrites it, and every control it draws writes a complete expression
source string into the same input - the document still stores your author's
text. Without `statifier_ui` the same field is the plain source input this
package has always rendered, so the dependency is genuinely optional. Pass
`expression_component` to override both.

When you pass a datamodel **document**, the kinds it declares reach that
editor too: a clause on a path declared `integer` offers the numeric
operators, and one on a `date` path the date set, rather than whichever set
the clause's current source happens to imply. It is a control and not a
check - the operator the source carries is still offered, the value in it is
still kept, and a disagreement renders as an advisory beside the clause - and
a path the document says nothing about renders exactly as it always did.

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

### With statifier_ui

[statifier_ui](https://github.com/riddler/statifier-ui) is an **optional**
dependency of this package, declared `{:statifier_ui, "~> 0.8", optional: true}`
beside `phoenix_live_view` and optional in the same sense: its only consumer is
a LiveView component, so a tree with no editor in it would be resolving a
package nothing there can call. Nothing adds it for you, nothing warns at
compile time when it is absent, and the resolution is a runtime
`Code.ensure_loaded?/1` plus `function_exported?/3` against the module named by
`:statifier_blocks, :expression_component_module`, which defaults to
`StatifierUI.Live.ExpressionInput`.

What it buys is one surface: the control an `:expression` config field renders.
If you want that control, there are two steps, and each is a *second* one
beside a step you have already taken above.

**1. A second `file:` entry.** statifier-ui ships its JavaScript as source too
(statifier-ui `docs/adr/0009-javascript-ships-as-source.md`), so on the npm
route its dependency sits beside this package's, and both point at the
package's `assets/` directory:

```json
{
  "dependencies": {
    "statifier_blocks": "file:../deps/statifier_blocks/assets",
    "statifier_ui": "file:../deps/statifier_ui/assets"
  }
}
```

That record documents this route and no other; statifier-ui's
`assets/package.json` names `js/index.js` as the entry point, which is the file
any other specifier would have to reach.

**2. A second hook registration.** The two packages' hooks are separate
objects, and registering one does not register the other. Spread both:

```javascript
import StatifierBlocks from "statifier_blocks";
import { StatifierUIHooks } from "statifier_ui";

let liveSocket = new LiveSocket("/live", Socket, {
  hooks: { ...StatifierBlocks, ...StatifierUIHooks },
});
```

`StatifierUIHooks` is `StatifierUIExpressionInput` and
`StatifierUIExpressionPicklist`, keyed by the names statifier-ui's component
renders; a host that wants one of them imports it by name instead. Hook names
and export names are public API under ADR-0009, the same as an exported
function.

**What degrades without them.** Only the `:expression` field moves. The three
states, in order:

| State | An `:expression` field renders |
|---|---|
| no `statifier_ui` on the load path | the plain source input this package has always rendered, with a `<datalist>` of the declared datamodel paths - clause 3 of the ordering `StatifierBlocks.Editor.Field` documents |
| `statifier_ui` resolves, hooks not registered | statifier-ui's own component, since this package passes it no `hook` assign and its attributes take their shipped defaults - but the JavaScript those `phx-hook` names refer to is not in your bundle, so nothing upgrades the field: no caret-aware completion list, and the picklist controls have nothing to write the expression source with |
| `statifier_ui` resolves and its hooks are registered | picklists of field, operator and value while the source is inside the subset predicator can round-trip, a text input over everything else, and caret-aware completion over the declared paths |

Nothing else in the editor changes across those three rows. The canvas, the
palette, the drawer and its tabs, findings, the undo history, the compiler and
this package's own two hooks call no function from statifier-ui: across `lib/`
a `StatifierUI` module is reached in exactly one place, as the default value of
the config key above. Without `phoenix_live_view` the question does not arise at all, because
no editor module compiles.

An `expression_component` you pass still wins over every row: the host's own
control is clause 1, and it is the answer whether or not `statifier_ui` is
present.

### Replacing a composite with its steps

A composite block's card carries one control of its own, reading **"Replace
with its steps"**: it takes the composite out and puts the blocks it stands
for in where it stood, as a single compound edit, so one undo puts the
composite back whole. The document it writes is the one
`StatifierBlocks.Composite.expand/2` answers, which is why the chart compiles
to the same bytes on both sides of the gesture. It is refused, and nothing is
written, when the slot the composite sits in will not admit the blocks that
come out of it.

### Saving an arrangement as a step

The inverse gesture reads a selected arrangement back as the composite that
stands for it. The selected card carries a **"Save as a step"** control with a
tray for marking which of the arrangement's values the saved step should ask
for, and what it hands out is the `Composite.Data` declaration
`StatifierBlocks.Composite.Collapse.propose/3` answers - the params, the
subtree template, and a pass-through slot for an unfilled slot inside the
selection. It does not name the type: naming it is the host's act, and so is
storing it.

**The gesture edits no document and this package persists nothing.** What
arrives on the `on_collapse` callback - `on_select`'s shape, a one-argument
function - is a map, and which table it goes in, which tenant owns it, and
whether it is saved at all are all the host's. A host that passes no
`on_collapse` sees no control.

Swapping the arrangement for the new type is a second, separate act, after the
host has registered what it saved: `Collapse.replacement/4` answers the
compound edit that performs it, and the host commits that compound itself
through `StatifierBlocks.Edit`. Nothing in the package commits it, which is
what keeps a type a host has not actually registered from reaching a document.

### What the mounted component holds

The `document` you pass in, an undo history over it, the current selection,
and a `drafts` map of config edits the validation gate has not accepted yet.
A draft is never in the document and never on the undo stack: a form whose
config has not been accepted names the fields that are outstanding and offers
"Discard edits", because a draft was never a command and so cannot be undone.

The selection is the editor's, but a host with a selection surface of its own
can move it: the **`selected_id` assign** is honoured on any update that
carries it, and the result comes back on `on_select` like any other
selection. An update that does not carry it leaves the author's selection
alone, and an id the open document does not hold clears the selection rather
than naming a block that is not there. It is not a document edit: no command,
nothing serialized, nothing on the undo stack.

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
| `:assignability` | `Palette.new/2` (also `from_modules/2`) | the host's widening relation for "may this block land in this slot" - both gates, kind admission and data flow, run against the palette the caller passed. It runs last, after the datamodel document's own read check (ADR-0003 decision 6 as ADR-0011 decision 3 narrows it) |
| `:validators` | `Palette.new/2` | the host's own whole-document rules: a list of `StatifierBlocks.DocumentValidator` modules, each handed the document as authored and answering `{anchor, message}` (optionally with `severity:`) for anything it objects to. Every module in the list runs, in list order; the package stamps the source `:lint` and defaults the severity to `:warning`, because a host's rule cannot make a document not compile. It is for the rules that are about the document rather than about one block - "a decision step must precede an act step" - which `validate_config/1` has no way to see (ADR-0005 `11p`-`11t`) - [`docs/host-validators.md`](https://github.com/riddler/statifier_blocks/blob/main/docs/host-validators.md) is the how-to |
| `accent_token` | palette entry | the NAME of a `--sb-*` property, stamped on that type's cards and palette rows |
| `badge` | palette entry | a short chip for the card header |
| `join_label` | palette entry | a one-argument function of config, phrasing the join marker under a side-by-side arrangement |
| `subject` | palette entry | a datamodel path. Read from the document's **entry** block - the first block of the root's `body` slot - it names where the document's subject lives, and `io/1`'s `consumes` and `produces` are a read and a write there. Absent means the document has no subject and those two keys declare nothing (ADR-0011 decision 6) |
| `singleton` | palette entry | `:anywhere` or `:head` - how many blocks of this type the document may hold, and (for `:head`) that the one it holds is first in the root's first declared slot. A document that does not comply draws one `:config` finding on the root, one per violating type; nothing is ever inserted, removed or moved for you (ADR-0005 `10z`/`11o`) |
| `slot_outcome_key` | palette entry | names the config key the blocks in one slot carry their outcome under, so a renderer routes an interrupt rule's escape without branching on a type name; it reaches the view model as `Slot.outcome_key` and the resolved value as `Node.outcome` |
| `--sb-*` tokens | the `theme` assign, or your own CSS | every colour, space, radius and drag treatment - see [`docs/theming.md`](https://github.com/riddler/statifier_blocks/blob/main/docs/theming.md) |
| compile findings | `findings` assign | `StatifierBlocks.Finding.from_compiler/2` adapts a compiler finding into the shape the editor renders, so a compile result routes back to the field somebody typed it into |
| `datamodel` | the `datamodel` assign | the datamodel paths the host declares; drives the undeclared-path advisory of ADR-0005 `11e`-`11g`, and `nil` (the default) turns it off entirely |
| `{:path, opts}` field type | `config_schema/1` on your own block type | says a config field holds a datamodel path - the eighth member of ADR-0002 decision 7's closed field-type set, and the spelling `datamodel_path?: true` already had. `StatifierBlocks.BlockType.datamodel_path?/1` answers `true` for it by construction, so the field carries the same undeclared-path advisory, and the editor renders it as a text input backed by a `<datalist>` of the paths `StatifierBlocks.Datamodel.candidates/3` derives from what the host declared. It suggests and never constrains: free text stays valid, `validate_config/1` stays the only authority, and with no `datamodel` handed in the list is empty and the plain input renders |
| `compile_options` | the `compile_options` assign | the rest of the option list the host compiles this document with - `terminate:`, `known_invoke_types:`, `datamodel:`. The editor recompiles the open document to resolve an execution's state ids back to blocks, and those options change the emission: `terminate: true` alone adds a top-level `<final>` per root-block outcome, so a finished execution sits on a state a recompile without the option has never heard of and the Run pane marks nothing. Hand over what you compiled with and the two agree. `:declare` is taken from the `declare` assign whatever this list says, and `[]` (the default) recompiles exactly as it did before |
| `expression_component` | the `expression_component` assign | the control an `:expression` field renders. Unset, it resolves to statifier-ui's expression editor when `statifier_ui` is present and to the package's plain source input when it is not; set, the host's own function component wins over both |
| `value_candidates` | the `value_candidates` assign | the values the host offers per datamodel path, `%{path => [%{label:, value:} \| binary]}`. Read by whatever fills the `expression_component` seam - a path with no entry gets a free-text value control, because only a host knows which of its own paths have a value set |
| `chart_outcomes` | the `chart_outcomes` assign | what the host says each of its stored documents finishes with, `%{document id => [outcome]}`. A `core.subchart` names a chart by document id and declares its outcomes by hand, because a block type cannot read the document it references; only the host knows which of its documents it compiles with `:child_use` - those are the ones a subchart may name - and what finals each of those emits. The editor offers that list on the `outcomes` field and reports a disagreement between it and what the block declares. A document the map does not name is *unknown*, which is not disagreement: `%{}`, the default, reports nothing about anything |
| `selected_id` | the `selected_id` assign | the block the editor is about, written by a host that draws its own selection surface. Honoured only on an update that carries it; an id the open document does not hold clears the selection. It moves the selection, it does not edit the document - nothing is serialized and nothing goes on the undo stack |
| `profile` | the `profile` assign | which of the editor's surfaces this mount draws, and whether it edits at all: `%{drawer_tabs:, inspector_tabs:, palette_groups:, toolbar:, read_only?:}`, every key optional and every list `:all` by default. No arrangement of the map, `%{}` included, removes a surface a host did not name, and an id a list names that the package cannot resolve is dropped rather than raised. `read_only?: true` renders the document offering no way to change it - [`docs/profiles.md`](https://github.com/riddler/statifier_blocks/blob/main/docs/profiles.md) is the page that works it through |
| `field_candidates` | the `field_candidates` assign | the values a host offers for one field, keyed `{type_name, field_key}`: `[{value, label}]` for a closed list, which a `:string` field draws as a `<select>`, or `{:open, [{value, label}]}` for an open one, drawn as a `<datalist>`. A `{:path, opts}` and an `:expression` field read it too and draw either spelling as a `<datalist>`, ahead of the declared datamodel paths, because the value stays typed by the control. `%{}` (the default) offers none. It draws a control and decides nothing: `validate_config/1` is still the only authority on a value |
| `on_collapse` | the `on_collapse` assign | a one-argument function called with each declaration the "Save as a step" gesture proposes, in `on_select`'s shape. The gesture edits no document and this package persists nothing: which table the saved step lives in, which tenant owns it, and whether it is saved at all are the host's. Swapping the arrangement for the registered type is the host's second act, through the compound `StatifierBlocks.Composite.Collapse.replacement/4` answers. Passing nothing draws no control |
| `debounce` | the `debounce` assign, and `StatifierBlocks.Editor.ConfigForm.config_form/1` / `StatifierBlocks.Editor.Field.field/1` directly | what `phx-debounce` the inspector's config controls carry, for a host persisting what the form posts on its own `on_change`. It takes what LiveView takes - milliseconds, or `:blur` - and defaults to no attribute, which is what every existing caller already renders. It is the same attr from the mount as from the two components, so a host composing the form itself and a host mounting the editor say it the same way. Controls drawn by an `expression_component` override are that component's own and are not covered |
| `capture` | `core.on_event` config, in the document | a map that writes values out of the firing event's payload into the datamodel: the key is the destination (a datamodel path) and the value is the source (a path inside `_event.data`). One `<assign>` per pair is emitted on the handler's own transition, in the destinations' sorted order, before the `<raise>` that carries the outcome. `config_schema/1` declares no field for it - the field-type set has no member that describes a map - so it is authored through the document rather than through the editor today. At run time a source whose root is bound but whose named member is missing writes the interpreter's explicit unbound marker and raises nothing (ADR-0002's capture Note, as corrected 2026-09-05), so a reader of a captured path tests for that marker rather than assuming an authored absence - unless the handler declares a `payload`, in which case the read is checked at compile and the marker write never happens |
| `payload` | `core.on_event` config, an optional `:string` field | the name of a type the datamodel document declares (`StatifierDatamodel.Declarations`), saying what `_event.data` carries **for the event this handler names**. Two handlers for one event may declare different payloads; each governs its own `capture`. With one declared, a `capture` pair whose source path reads a member the payload does not carry is a `:config` refusal on the `capture` key - the first segment against the payload's fields, deeper segments only where the field's own type resolves to another declaration, and a scalar, list or opaque field stops the walk. Absent, blank, naming a type the document does not declare, or compiled with no `:datamodel`: nothing is refused and nothing changes. `payload` emits no SCXML of its own (ADR-0002's amendment of 2026-09-06) |

The metadata readers are total and refuse rather than repair: a badge that is
blank, carries a newline, or runs past 32 characters is dropped rather than
clipped, an accent that is not an anchored `--sb-*` name never reaches a style
attribute, and a `join_label` that raises degrades to the editor's own word.
Assignability answers with reason-carrying refusals (sb-ue7, in flight).

Two things on the canvas are the design rather than a defect. A summary chip
is capped at 32 characters: one longer than that is drawn clipped, with an
ellipsis in its last position, and the chip's `title` carries its full text,
because a card has a fixed width and does not grow a line for one value. And
the canvas pane scrolls rather than squeezing the document: at 100 percent
zoom a document wider than the canvas scrolls horizontally inside the editor.
The toolbar's zoom steps and `Fit width` bring it into view, and the `fit`
assign (`:width` or `:active`) opens a document that way.

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

A document that did not come out of the editor - a stored master, one built
in code - can be checked against the palette you are about to mount before
an author opens it: `StatifierBlocks.Plan.expressible(document, palette)`
answers `:ok` when every block's type resolves through the palette and every
block sits in a slot the editor would let an author drop it into - declared,
with room, and admitting its kinds - and every empty required slot is one the
palette can fill; otherwise `{:no, reasons}`, each reason naming the rule and
the block. A read the environment contradicts is not a reason: the editor
flags it as a finding rather than refusing the drop.
`StatifierBlocks.Plan.expressible?(document, palette)` asks the same question
and answers `true` or `false`, for a host that only needs the yes or no. Both
take the assignability context as an optional third argument.

### Not yet

Honest about the edges, so you do not go looking for these:

- **Connectors.** Blocks are arranged by containment, and there is no
  free-floating edge between two cards. Whether the editor grows one is an
  open ADR-0005 decision-7 question (`sb-y14`).
- **A datamodel path grammar.** The undeclared-path advisory `11e`-`11g`
  settled is shipped, but only against the set of paths a host declares.
  Nothing here parses or validates a path beyond its shape, and a host that
  supplies no datamodel gets no advisory at all.
- **A chart view.** Nothing here draws a compiled chart's transitions as a
  flow between blocks. What such a view's edges would mean - the block-level
  flow graph lifted from the compiled transitions, which is not
  `StatifierBlocks.Graph` - is defined in
  [`docs/block-level-flow-graph.md`](https://github.com/riddler/statifier_blocks/blob/main/docs/block-level-flow-graph.md).

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
where its revisions are stored, and what publishing means. The editor is also a
single-session component: it surfaces the `revision` it loaded so you can do
optimistic concurrency on save, and it does not merge or resolve anything.

## Mounting the Map

The Map draws a block document as boxes in boxes: every step, what holds
it, the arrows between them, where the document starts and where it
finishes. It is a reader of the same view model the editor renders, and a
page mounts it beside a list of the document's steps. It is not a mode of
the editor, and the editor draws no map (ADR-0018). The editor does draw
the description region described below, under its canvas, from its own
document and selection: the selected block's description, its note first,
or the document's when nothing is selected, with no paragraph on how to
read a map, since there is none beside it.

Three pieces make it. `StatifierBlocks.Map.graph/2` builds the graph from
the view model, `StatifierBlocks.Map.Info` describes every element the map
draws in words, and two function components in
`StatifierBlocks.Editor.MapRegions` render them into the page:
`map_region/1`, where the `StatifierBlocksMap` hook lays the graph out and
draws it, and `description_region/1`, which says what the selected block is,
or what the document is when nothing is selected. Pointing at anything the
map draws shows its description in that region, in the browser, and pointing
away puts back what it said.

### What the host brings

The components keep no state. A host brings four things, and each stays its
own:

1. **The view model.** `StatifierBlocks.ViewModel.build/3` of the document.
   Both regions read it; the description region also takes the document and
   the palette it was built from.
2. **The selection.** The block id the host's list has selected, or `nil`.
   The map marks that block's box and the description region describes it.
   Selecting a block is the host's to do, in its own event handler.
3. **The list's event names.** The names the host's list already sends to
   select a block and to open an insert. A click on a box, on the gap after
   a block or on an empty slot's marker is sent under those names with the
   payload the list sends for the same gesture (`"block-id"`, and `"slot"`
   for an empty slot), so the server cannot tell a gesture on the map from
   the same gesture on the list. The map has no event of its own.
4. **The list.** The map region is hidden from assistive technology
   (`aria-hidden="true"`) and nothing in it takes focus, so the list is the
   keyboard and screen-reader path to every step. Its rows point at the
   description region with `aria-describedby`, and the region is
   `aria-live="polite"`, so a selection made in the list is read out.

```heex
<StatifierBlocks.Editor.MapRegions.map_region
  id="plan-map"
  view_model={@view_model}
  selected={@selected_id}
  select_event="select-row"
  insert_event="insert-open"
  editable={true}
  description="plan-description"
/>

<StatifierBlocks.Editor.MapRegions.description_region
  id="plan-description"
  document={@document}
  view_model={@view_model}
  palette={@palette}
  selected={@selected_id}
/>

<ol>
  <li :for={{node, _depth, _kind} <- ViewModel.outline(@view_model)}>
    <button
      type="button"
      phx-click="select-row"
      phx-value-block-id={node.block_id}
      aria-describedby="plan-description"
    >
      {ViewModel.sentence(node)}
    </button>
  </li>
</ol>
```

`description` on the map region names the description region's id, which
is what gives the map its hover; a map without it draws and selects, and
shows no description under the pointer. Both components take `phrase`, the
host's words for its event names, as `StatifierBlocks.Map.graph/2` takes
it; pass the same function to both so the region says what the box says.
`insert_reveal` takes a selector for the element to scroll into view after
an insert armed from the map, since what the list opens may sit below it.
`map` on the description region says whether a map is mounted beside it,
and a host with a map leaves it at its default, `true`; `false` is how the
editor draws the region under its canvas: no hover layer, no store, and no
paragraph on how to read the map, nor the map's key, in the document's
description. `label`
on the description region is its accessible name, the `aria-label` of the
live region, `"Description"` by default; a host passes its own words.

### The hook, and what it costs

The Map hook is not in the package's default export. It has its own entry
point, `statifier_blocks/map`, because it imports the vendored elkjs build
that lays the graph out, and a host that never mounts the Map should never
bundle it. Register it beside the editor's hooks:

```javascript
import StatifierBlocks from "statifier_blocks";
import { StatifierBlocksMap } from "statifier_blocks/map";

let liveSocket = new LiveSocket("/live", Socket, {
  hooks: { ...StatifierBlocks, StatifierBlocksMap },
});
```

On the `NODE_PATH` route the specifier is
`statifier_blocks/assets/js/statifier_blocks_map.js`.

The hook draws into a child of its element marked `data-map-canvas`, which
`map_region/1` renders with `phx-update="ignore"` so that LiveView leaves
the drawing alone. A host that attaches the hook to its own element gives
it that child. An element without one is not supported: the hook draws into
the element itself, which LiveView patches, so a patch can take the drawing
away, and it warns once per mount in the browser console, naming the
missing child.

That import pulls in `assets/vendor/elk.bundled.js`, elkjs 0.9.3 under the
Eclipse Public License 2.0 (its licence ships beside it), and pulls it in
whole: 1,606,238 bytes as shipped and 466,990 bytes gzipped, none of which a
bundler can shake out.

### Theming the Map

On a page of the host's, both regions read the `--sb-*` palette from the
page, since neither sits inside the editor (the description region the
editor draws under its canvas reads the editor's own tokens instead): set
the palette on an ancestor of the regions, or on
`.sb-map__region` and `.sb-map__description-frame` themselves (the frame
holds the description region and its hover layer). The map's drawing
reads the `--sb-map-*` tokens, declared on `.sb-map__region` and mapped onto
the palette, so a page that themes the palette dresses the map too; set one
of them to disagree with that mapping. Set it on `.sb-map__region` itself,
or on a selector that reaches that element: the region declares every
`--sb-map-*` token on itself, so a value set on an ancestor loses to that
declaration. The drawing carries a fallback for each, which is what the map
looks like on a page that sets none.

### Working on the Map in this repository

The package bundles nothing, and a host needs no Node for the Map. This
repository's own tests do: the Map hook's layout tests run the hook through
the vendored elkjs outside the browser, so a contributor needs `node` on the
path to run the full `mix quality` gate (`mise.toml` pins the version CI
uses).

## Design records

The contracts this package is built out of are written down as ADRs in
[`docs/adr/`](https://github.com/riddler/statifier_blocks/tree/main/docs/adr):
the document schema (0001), the block-type behaviour (0002), host-pluggable
assignability (0003), the compiler and its provenance map (0004), and the
editor architecture (0005), and the typed environment a pre-order walk carries
from datamodel path to type (0011). A module's docs cite the decision it
implements;
when the two disagree, the record is the contract and the code is the bug.

## License

MIT - see
[LICENSE](https://github.com/riddler/statifier_blocks/blob/main/LICENSE).

One file is not: `assets/vendor/elk.bundled.js`, elkjs 0.9.3 vendored
unmodified for the Map hook, is under the Eclipse Public License 2.0, and its
licence text ships beside it as `assets/vendor/elkjs-LICENSE.md`.
