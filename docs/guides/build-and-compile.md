# How to build a block document and compile it to a chart

This guide shows you how to go from your own block types to a compiled chart,
and how to point a running position in that chart back at the block that
produced it.

The example is patron registration: a visitor becomes a library patron
through a few screens. The document checks the visitor's details, and issues
a library card when the visitor is old enough for one.

Every snippet on this page runs, in order, as one script:
[`test/statifier_blocks/readme_test.exs`](https://github.com/riddler/statifier_blocks/blob/main/test/statifier_blocks/readme_test.exs)
evaluates them on every build and asserts every `#=>` output, and the SCXML
lines shown, against what the code answers.

## Write the block types your domain needs

1. Write each block type as a module that implements
   `StatifierBlocks.BlockType`: a handful of declarations plus one `emit/2`.
   The two types here are invoking leaves, so they share their emission.

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

defmodule MyApp.Blocks.CheckDetails do
  @moduledoc "`myapp.check_details`: checks the details a visitor entered."
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

  # The document's subject path. This type is the flow's first block, so it
  # is the one whose entry names where the subject lives - and `produces`
  # above is a write there.
  @impl true
  def palette_entry, do: %{label: "Check details", subject: "registration.visitor"}

  @impl true
  def emit(block, context), do: MyApp.Blocks.invoke_leaf(block, context)
end

defmodule MyApp.Blocks.IssueCard do
  @moduledoc "`myapp.issue_card`: issues a library card to a checked visitor."
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
  def io(_config), do: %{kinds: [:step], consumes: "myapp.patron_application"}

  @impl true
  def emit(block, context), do: MyApp.Blocks.invoke_leaf(block, context)
end
```

2. Declare in `io/1` what each type reads and writes. Nothing flows between
   adjacent blocks: every value a block writes goes to a datamodel path by
   name, so `produces` is a **write** and `consumes` a **read** at the
   document's subject path - the path the document's first block names with
   `subject:` on its `palette_entry/0`. If the first block names no subject,
   the two keys declare nothing.

To type those paths, check a read against what the document holds at it, and
widen what may land where, see [How to type a palette](../typing-a-palette.md).
For why a read refuses, and which reads passed only because a block declared
nothing, see `StatifierBlocks.Assignability`; for how the editor marks the
slots a dragged block may land in, see `StatifierBlocks.Edit.Targets`.

## Compose the document

1. Arrange your types with the `core.*` vocabulary this package ships: here a
   `core.sequence` and a `core.branch`. None of the core types knows a domain:
   `core.invoke` names an invoke type for the host to run and never runs one.
   For every core type and its slots, see `StatifierBlocks.Core`. In a running
   system an editor writes this tree; it is ordinary data either way.

```elixir
alias StatifierBlocks.{Block, Compiler, Document, Palette, Provenance}

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
          Block.new("core.branch",
            id: "blk_old_enough",
            config: %{
              "arms" => [%{"slot" => "arm_old_enough", "cond" => "visitor_age >= minimum_age"}]
            },
            slots: %{
              "arm_old_enough" => [
                Block.new("myapp.issue_card",
                  id: "blk_issue_card",
                  config: %{"invoke_type" => "myapp:issue_card"}
                )
              ]
            }
          )
        ]
      }
    ),
    id: "bdoc_patron_registration",
    datamodel: [
      %Document.DatamodelEntry{
        id: "visitor_age",
        description: "The visitor's age, from the details they entered."
      },
      %Document.DatamodelEntry{
        id: "minimum_age",
        description: "The youngest age the library issues a card at."
      }
    ]
  )
```

2. Declare every root a condition reads. The branch's condition reads
   `visitor_age` and `minimum_age`, so the document declares both in its
   `datamodel` key. A declaration names a **root**: storage exists at that
   name, and everything beneath it is declared too. A document that declares
   nothing, and whose siblings declare nothing, gets no undeclared-path
   advisories at all - not because everything checked out, but because nobody
   made a claim to check against. The document's own key is one of three
   surfaces that declare; for the other two, see `StatifierBlocks.Datamodel`.

## Build a palette and compile

1. Build a palette: a `type_name => module` map you build for one operation
   and pass explicitly. It is not application config and not a named
   process, so two tenants in one runtime never step on each other's block
   types.

```elixir
palette =
  Palette.new(
    Map.merge(Palette.core_types(), %{
      "myapp.check_details" => MyApp.Blocks.CheckDetails,
      "myapp.issue_card" => MyApp.Blocks.IssueCard
    })
  )

{:ok, compiled} = Compiler.compile(document, palette)
```

2. Read the result. `Compiler.compile/3` answers
   `{:ok, %StatifierBlocks.Compiled{}}` or `{:error, findings}` - never a
   raise, never a partial success. The compiled value carries the generated
   bytes, the provenance map, a `StatifierBlocks.CompilationRecord` joining
   the revision it compiled to the chart it emitted, and the invoke types the
   chart names:

```elixir
compiled.invoke_types
#=> ["myapp:check_details", "myapp:issue_card"]
```

The SCXML in `compiled.scxml` is a chart Statifier runs as-is - one compound
state per block, completion signalled by `done.state`:

```xml
<scxml initial="s_blk_root" name="bdoc_patron_registration" version="1.0" xmlns="...">
  <datamodel>
    <data id="visitor_age"/>
    <data id="minimum_age"/>
  </datamodel>
  <state id="s_blk_root" initial="s_blk_check_details">
    <transition event="done.state.s_blk_check_details" target="s_blk_old_enough" type="internal"/>
    <transition event="done.state.s_blk_old_enough" target="s_blk_root__o_done" type="internal"/>
    <state id="s_blk_check_details" initial="s_blk_check_details__running">
      <state id="s_blk_check_details__running">
        <invoke id="s_blk_check_details__invocation" type="myapp:check_details"/>
        ...
```

## Point a running position back at a block

Hand the provenance map the active state ids of a live session, and it
answers with the blocks the session is inside. That is how an editor
highlights the step an execution is on, and how a chart-level finding routes
back to the config field somebody typed it into.

```elixir
active_state_ids = Map.keys(compiled.provenance.by_state_id)

blocks_in_play =
  compiled.provenance
  |> Provenance.owners_of_states(active_state_ids)
  |> Enum.map(& &1.block_id)
  |> Enum.uniq()
  |> Enum.sort()

#=> ["blk_check_details", "blk_issue_card", "blk_old_enough", "blk_root"]
```

## Skip a recompile on an unchanged input

For a fixed `{document canonical bytes, palette, compiler version}` the
generated SCXML is byte-identical on every machine and every compile, and
`compiled.record` carries all three - so skip the compile when the triple is
unchanged. The guarantee does not run backwards: identical SCXML does not
mean an unchanged revision, because `metadata` is not compiled, and two
revisions that differ only there compile to one chart.
