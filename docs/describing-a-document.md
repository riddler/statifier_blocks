# How to describe a document in words

This guide shows you how to turn a block document into an outline of its
blocks and the ways control passes between them, write that outline as lines
of English, and reword the lines in your own voice.

`StatifierBlocks.Describe.outline/3` answers the structure and
`StatifierBlocks.Describe.render/2` the lines.
[`docs/adr/0016-document-describes-itself.md`](https://github.com/riddler/statifier_blocks/blob/main/docs/adr/0016-document-describes-itself.md)
is the record; everything below is the moves.

## Before you start

You need the document and the palette you compile it with. The describe
never compiles: it reads the document's tree and the block types'
declarations, so no compiler check runs, and a block whose type the palette
cannot resolve is described as its placeholder rather than refused.

Nothing here reads a clock, starts a process, reaches a network or asks a
language model, and equal input answers byte-identical output. Nothing here
needs LiveView either.

The examples below are one program: later blocks use names earlier ones
bound.

## Outline a document

Build or load the document, then ask for its outline under your palette. This
one is a library loan: a patron who owes fines is sent a notice and the loan
waits for payment, the book is checked out, and the loan waits up to 21 days
for its return. A renewal resumes the wait; a report that the book is lost
abandons it. Either way the loan is closed.

```elixir
alias StatifierBlocks.{Block, Describe, Document, Palette}
alias StatifierBlocks.Describe.{Edge, Node}

send_event = fn id, event -> Block.new("core.send", id: id, config: %{"event" => event}) end

fines =
  Block.new("core.branch",
    id: "fines",
    config: %{"arms" => [%{"slot" => "arm_owes", "cond" => "patron.fines_owed > 0"}]},
    slots: %{
      "arm_owes" => [
        send_event.("notice", "loan.fines_notice"),
        Block.new("core.await", id: "paid", config: %{"event" => "fines.paid"})
      ],
      "otherwise" => [],
      "undecided" => []
    }
  )

lending =
  Block.new("core.resumable_group",
    id: "lending",
    config: %{"history" => "shallow"},
    slots: %{
      "body" => [
        Block.new("core.await",
          id: "returned",
          config: %{"event" => "loan.returned", "timeout" => "21d"}
        )
      ],
      "interrupts" => [
        Block.new("core.on_event",
          id: "renewed",
          config: %{"event" => "loan.renewed", "outcome" => "resume"}
        ),
        Block.new("core.on_event",
          id: "lost",
          config: %{"event" => "loan.reported_lost", "outcome" => "abandon"}
        )
      ]
    }
  )

loan =
  Block.new("core.sequence",
    id: "loan",
    slots: %{
      "body" => [fines, send_event.("checkout", "loan.checked_out"), lending, send_event.("close", "loan.closed")]
    }
  )

document = Document.new(loan, id: "bdoc_library_loan", revision: 1)
outline = Describe.outline(document, Palette.core(), [])

identity = {outline.id, outline.revision}
#=> {"bdoc_library_loan", 1}
```

Every block is one `StatifierBlocks.Describe.Node`, exactly once, in
`StatifierBlocks.ViewModel.outline/1`'s reading order. A node carries the block's id, type, parent,
depth, the kind of slot its parent holds it in (`:step`, `:arm`, `:rail` or
`:tray`), its sentence, the outcome names its type declares, its summary
chips and its fan label:

```elixir
nodes = Enum.map(outline.nodes, &{&1.id, &1.parent, &1.kind})
#=> [{"loan", nil, :step}, {"fines", "loan", :step}, {"notice", "fines", :arm}, {"paid", "fines", :arm}, {"checkout", "loan", :step}, {"lending", "loan", :step}, {"returned", "lending", :step}, {"renewed", "lending", :rail}, {"lost", "lending", :rail}, {"close", "loan", :step}]

returned = Enum.find(outline.nodes, &(&1.id == "returned"))
await_outcomes = returned.outcomes
#=> ["received", "timed_out"]
```

## Read the edges the containers draw

An edge is found inside a block of four types, from the document's structure:

| Type | Edges |
|---|---|
| `core.sequence` | `:entry` to the first child, `:sequence` from each child to the next, `:exit` from the last child |
| `core.group`, `core.resumable_group` | the same three over `body`, then one `:interrupt` per handler whose `outcome` is `abandon` or `resume` |
| `core.branch` | per arm, a `:branch` edge to the arm's first child (or to the branch's exit for an empty arm), then that arm's `:sequence` and `:exit` edges |

Every other type is described by containment and its node's fan label alone.
A `:sequence` or `:exit` edge carries every outcome its source's type
declares, on the one edge.

To answer "what ends the loan early", read the interrupt edges:

```elixir
interrupts = for %Edge{kind: :interrupt} = edge <- outline.edges, do: {edge.event, edge.to, edge.history}
#=> [{"loan.renewed", {:body, "lending"}, :shallow}, {"loan.reported_lost", {:exit, "lending"}, nil}]
```

A resume goes back into the group's body (at its history, for a
`core.resumable_group`; a `core.group` restarts its body from the first step);
an abandon goes to the group's exit. A branch's arms read the same way, each carrying its
condition, `:otherwise` or `:undecided`. The empty `otherwise` arm goes
straight to the branch's exit, where the arms converge, and the empty
`undecided` arm draws no edge at all:

```elixir
arms = for %Edge{kind: :branch} = edge <- outline.edges, do: {edge.condition, edge.to}
#=> [{"patron.fines_owed > 0", {:block, "notice"}}, {:otherwise, {:exit, "fines"}}]
```

## Write the outline as lines

`render/2` answers one line per node, in node order, then one line per edge,
in edge order. A line is non-blank English with no newline, carriage return
or tab, and a block's id never appears in a default line:

```elixir
lines = Describe.render(outline, [])

node_lines = Enum.take(lines, length(outline.nodes))
#=> ["Run its steps in order", "Decide: When \"owes\", otherwise (one of)", "Send loan.fines_notice", "Wait for fines.paid", "Send loan.checked_out", "Resumable group", "Wait for loan.returned, giving up after 21d", "When loan.renewed, resume", "When loan.reported_lost, abandon", "Send loan.closed"]

interrupt_lines = Enum.filter(lines, &String.starts_with?(&1, "On "))
#=> ["On loan.renewed, When loan.renewed, resume resumes Resumable group at shallow history", "On loan.reported_lost, When loan.reported_lost, abandon abandons Resumable group"]
```

## Reword lines with a phrasing module

Implement `StatifierBlocks.Describe.Phrasing` and pass the module as
`phrasing:`. Each line is offered to the callback named for its node's `kind`
(`step/2`, `arm/2`, `rail/2`, `tray/2`) or its edge's `kind` (`entry/2`,
`sequence/2`, `branch/2`, `interrupt/2`, `exit/2`), with the structured node or
edge and the default line. Every callback is optional.

```elixir
defmodule MyApp.Describing.LoanPhrasing do
  @behaviour StatifierBlocks.Describe.Phrasing

  alias StatifierBlocks.Describe.{Edge, Node}

  @impl true
  def rail(%Node{id: "renewed"}, _default), do: "A renewal"
  def rail(%Node{id: "lost"}, _default), do: "A report that the book is lost"
  def rail(%Node{}, _default), do: :default

  @impl true
  def interrupt(%Edge{event: "loan.renewed"}, _default), do: "A renewal restarts the wait for the return"
  def interrupt(%Edge{event: "loan.reported_lost"}, _default), do: "A lost book ends the lending\nearly"
  def interrupt(%Edge{}, _default), do: :default
end

reworded = Describe.render(outline, phrasing: MyApp.Describing.LoanPhrasing)

reworded_lines = Enum.filter(reworded, &String.starts_with?(&1, "A "))
#=> ["A renewal", "A report that the book is lost", "A renewal restarts the wait for the return"]

lost_line = List.last(reworded)
#=> "On loan.reported_lost, When loan.reported_lost, abandon abandons Resumable group"
```

The callback answers its own line or `:default`. An answer that is blank,
carries a newline, carriage return or tab, is not a string, or comes from a
callback that raises, throws or exits keeps the default line for that one node
or edge, never an error. That is why the lost-book interrupt above, whose
answer carries a newline, still reads as the default.

## Know what a phrasing module cannot change

The seam rewords lines one at a time. It does not add, drop or reorder them,
and it never sees or changes the outline: `render/2` with and without a
phrasing module answers the same number of lines in the same order. A
node's rewording is its own line only; an edge line that names that block
still quotes the block's default sentence, so reword the edge too when it
should match.

```elixir
same_count? = length(reworded) == length(lines)
#=> true
```

For the lines to stay byte-identical for equal input, each callback has to be
a pure function of its arguments; that half of the contract is yours.
