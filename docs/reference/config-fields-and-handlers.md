# Config fields and the handlers this package ships

This page is the reference for two parts of the block model: how a config
field declares where its value is stored, and which invoke handlers the
package ships for a host to register. The examples use patron registration,
the same world as
[How to build a block document and compile it to a chart](../guides/build-and-compile.md).

Every snippet under each heading below runs, in order, as one script:
[`test/statifier_blocks/readme_test.exs`](https://github.com/riddler/statifier_blocks/blob/main/test/statifier_blocks/readme_test.exs)
evaluates the config-field snippet and
[`test/statifier_blocks/readme_runtime_test.exs`](https://github.com/riddler/statifier_blocks/blob/main/test/statifier_blocks/readme_runtime_test.exs)
evaluates the handler snippets, and each asserts every `#=>` output against
what the code answers.

## Config fields and where their values live

A block type's `config_schema/1` declares the fields the editor renders for
it. A field's `key` is its **identity**: the DOM id, the form param name, and
what a `{:config, block_id, key}` finding anchors to. Where the value is
*stored* is a second, separate question, and a field answers it with an
optional `value_path` - a list of keys and list indexes from the config root
down to the value it edits.

A field that declares no `value_path` is stored at `config[key]`. A field may
declare one when its key and its storage differ. `core.branch` keys a
condition field by the arm's slot name, because that is what a finding names,
while the condition itself is stored inside the ordered `"arms"` list:

```elixir
alias StatifierBlocks.{BlockType, Core}

config = %{"arms" => [%{"slot" => "arm_old_enough", "cond" => "visitor_age >= minimum_age"}]}

[field] = Core.Branch.config_schema(config)

field.key
#=> "arm_old_enough"

BlockType.value_path(field)
#=> ["arms", 0, "cond"]

BlockType.fetch_value(config, BlockType.value_path(field))
#=> {:ok, "visitor_age >= minimum_age"}

BlockType.put_value(config, BlockType.value_path(field), "visitor_age >= 18")
#=> %{"arms" => [%{"cond" => "visitor_age >= 18", "slot" => "arm_old_enough"}]}
```

### What each function answers

- `value_path/1` answers `[key]` for a declaration that declares no path, so
  a caller never branches on which case it has.
- `fetch_value/2` is total. It answers `{:ok, value}` for a path that
  resolves and `:error` for a path that does not.
- `put_value/3` writes the last segment whether or not a value was already
  there, so an arm with no condition yet accepts a write. It never invents an
  intermediate map or list that a block type did not write.

A host block type that stores a value somewhere other than a top-level key
declares the path the same way.

## The handlers this package does ship

A block type only **names** an invoke type, and the host registers the
handler that runs it, per session. `core.subchart` is the one type whose
handler the package ships: "start the child chart this block names by
document id" is the same code in every host, because a subchart's contract
fixes both ends of it (`StatifierBlocks.Core.Subchart`'s moduledoc) - a child
compiled with `child_use: true`, its outcome carried on `<donedata>`, one
final per outcome. The one thing the handler asks the host for is *which*
chart a document id names, meaning which of the document's revisions the
child is compiled from.

`use StatifierBlocks.Runtime.Subchart` builds that handler from two
callbacks a host supplies: `resolve_chart/2`, which turns a document id
into the revision to start (a `%StatifierBlocks.Document{}`, or a
refusal), and `palette/0`, the palette the child compiles that revision
against into the child chart. `handlers/1` turns the resulting module
into the map `Statifier.Session.start_link/2` expects for `:invoke_handlers`:

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
one of exactly three reasons:

- `unknown_document`: the resolver could not place the id.
- `child_compile_findings`: the resolved document failed to compile as a
  child.
- `cycle_refused`: the resolver detected a cross-document cycle that a
  single-document compile cannot see for itself.

The package ships no `mod:` application callback. A host that wants
`Statifier.Session` to run at all, subcharts or not, adds
`Statifier.Supervisor` to its own supervision tree, then passes `handlers/1`'s
map as the `:invoke_handlers` option on every `Statifier.Session.start_link/2`
call that should run subcharts.

### The durable variant

`start/2` is a pure planning callback, which scopes the handler above to the
in-memory `Statifier.Session` case. A child that is its own durably persisted
execution records its parent linkage as part of starting, and a planning
callback performs nothing.

The durable variant is a **second module**,
`StatifierBlocks.Runtime.DurableSubchart` (ADR-0008). It takes the same
two callbacks, refuses for the same reasons, and answers at dispatch time
instead - `dispatch_fun/1` builds the fun
`StatifierPersistence.Driver`'s `:dispatch` option takes:

```elixir
dispatch = StatifierBlocks.Runtime.DurableSubchart.dispatch_fun(MyApp.Charts)
```

The child runs as its own persisted execution, linked to the parent's
execution and invocation and pinned to the child chart's identity, and its
completion re-enters the parent through the driver's own `done.invoke` door
after the process that started it is gone. A durable start has one refusal
reason the in-memory handler cannot have - `child_run_creation_failed` - and
the driver raises it, since creating the child execution happens after this
package has answered. Nesting needs no extra wiring. Fan-out (one invocation,
N children) is named by the record and not built.

Which variant runs is the host's session wiring, never the document: the
same block document compiles to the same bytes either way. A host that wires
the in-memory module into a durable execution gets a child that does not
survive a restart of the parent.

Nothing in this package depends on `statifier_persistence`; the durable
module names no module from it and answers in plain tuples.
