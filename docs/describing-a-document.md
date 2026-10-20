# How to describe a document in words

This guide shows you how to turn a block document into an outline of its
blocks and the ways control passes between them, write that outline as lines
of English, and reword the lines in your own voice.

`StatifierBlocks.Describe.outline/3` answers the structure and
`StatifierBlocks.Describe.render/2` the lines. To check a stored document
against the JSON Schema instead, see
[How to validate a document against the schema from any language](guides/validate-a-document-against-the-schema.md).
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

Build or load the document, then ask for its outline under your palette. This one is patron registration: a visitor whose email address is not
verified is sent a reminder and the registration waits for the
verification, the application is submitted, and the registration waits up to
14 days for a librarian's approval. A correction resumes the wait; a
withdrawal abandons it. Either way the registration is closed.

```elixir
alias StatifierBlocks.{Block, Describe, Document, Palette}
alias StatifierBlocks.Describe.{Edge, Node}

send_event = fn id, event -> Block.new("core.send", id: id, config: %{"event" => event}) end

verify =
  Block.new("core.branch",
    id: "verify",
    config: %{"arms" => [%{"slot" => "arm_unverified", "cond" => "email_verified == false"}]},
    slots: %{
      "arm_unverified" => [
        send_event.("reminder", "registration.verify_reminder"),
        Block.new("core.await", id: "verified", config: %{"event" => "registration.email_verified"})
      ],
      "otherwise" => [],
      "undecided" => []
    }
  )

review =
  Block.new("core.resumable_group",
    id: "review",
    config: %{"history" => "shallow"},
    slots: %{
      "body" => [
        Block.new("core.await",
          id: "approved",
          config: %{"event" => "registration.approved", "timeout" => "14d"}
        )
      ],
      "interrupts" => [
        Block.new("core.on_event",
          id: "corrected",
          config: %{"event" => "registration.corrected", "outcome" => "resume"}
        ),
        Block.new("core.on_event",
          id: "withdrawn",
          config: %{"event" => "registration.withdrawn", "outcome" => "abandon"}
        )
      ]
    }
  )

registration =
  Block.new("core.sequence",
    id: "registration",
    slots: %{
      "body" => [verify, send_event.("submit", "registration.submitted"), review, send_event.("close", "registration.closed")]
    }
  )

document = Document.new(registration, id: "bdoc_patron_registration", revision: 1)
outline = Describe.outline(document, Palette.core(), [])

identity = {outline.id, outline.revision}
#=> {"bdoc_patron_registration", 1}
```

Every block is one `StatifierBlocks.Describe.Node`, exactly once, in
`StatifierBlocks.ViewModel.outline/1`'s reading order. A node carries the block's id, type, parent,
depth, the kind of slot its parent holds it in (`:step`, `:arm`, `:rail` or
`:tray`), its sentence, the outcome names its type declares, its summary
chips and its fan label:

```elixir
nodes = Enum.map(outline.nodes, &{&1.id, &1.parent, &1.kind})
#=> [{"registration", nil, :step}, {"verify", "registration", :step}, {"reminder", "verify", :arm}, {"verified", "verify", :arm}, {"submit", "registration", :step}, {"review", "registration", :step}, {"approved", "review", :step}, {"corrected", "review", :rail}, {"withdrawn", "review", :rail}, {"close", "registration", :step}]

approved = Enum.find(outline.nodes, &(&1.id == "approved"))
await_outcomes = approved.outcomes
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

One more kind is read across the whole document rather than inside a
container. A `core.send` with a delay draws a `:timer` edge to every
`core.on_event` and `core.await` whose `event` is the one it sends: the edge
runs from the send to the rule or await, its container is the send's parent,
its `event` is the sent event and its `delay` the send's delay as stored. It
is not a transition; it says the send arms an event the other block waits
for. A send whose delay is absent, empty or not a duration `core.send`
accepts (`soon`, say) draws none. Only blocks the palette resolves take part,
at either end, and a block inside a drafts shelf takes part in none. Timer
edges come after every other edge, and the default line reads
`In 24 hours, registration.deadline reaches ...`, the delay in the send's own
words. The registration above has no delayed send, so its outline has none.

To answer "what ends the review early", read the interrupt edges:

```elixir
interrupts = for %Edge{kind: :interrupt} = edge <- outline.edges, do: {edge.event, edge.to, edge.history}
#=> [{"registration.corrected", {:body, "review"}, :shallow}, {"registration.withdrawn", {:exit, "review"}, nil}]
```

A resume goes back into the group's body (at its history, for a
`core.resumable_group`; a `core.group` restarts its body from the first step);
an abandon goes to the group's exit. A branch's arms read the same way, each carrying its
condition, `:otherwise` or `:undecided`. The empty `otherwise` arm goes
straight to the branch's exit, where the arms converge, and the empty
`undecided` arm draws no edge at all:

```elixir
arms = for %Edge{kind: :branch} = edge <- outline.edges, do: {edge.condition, edge.to}
#=> [{"email_verified == false", {:block, "reminder"}}, {:otherwise, {:exit, "verify"}}]
```

## Write the outline as lines

`render/2` answers one line per node, in node order, then one line per edge,
in edge order. A line is non-blank English with no newline, carriage return
or tab, and a block's id never appears in a default line.

An edge line names a step by its sentence and a container by its node's
`noun`: the container's title where it has one, else a short noun for its
type - `the steps` for a sequence, `the group` for a group or a resumable
group, `the branch` - else `the` and its palette label in lower case. So the registration's resumable group is `Resumable group` as a step of the
registration and `the group` in the lines its own edges draw:

```elixir
lines = Describe.render(outline, [])

node_lines = Enum.take(lines, length(outline.nodes))
#=> ["Run its steps in order", "Decide: When \"unverified\", otherwise (one of)", "Send registration.verify_reminder", "Wait for registration.email_verified", "Send registration.submitted", "Resumable group", "Wait for registration.approved, giving up after 14d", "When registration.corrected, resume", "When registration.withdrawn, abandon", "Send registration.closed"]

interrupt_lines = Enum.filter(lines, &String.starts_with?(&1, "On "))
#=> ["On registration.corrected, When registration.corrected, resume resumes the group at shallow history", "On registration.withdrawn, When registration.withdrawn, abandon abandons the group"]
```

## Reword lines with a phrasing module

Implement `StatifierBlocks.Describe.Phrasing` and pass the module as
`phrasing:`. Each line is offered to the callback named for its node's `kind`
(`step/2`, `arm/2`, `rail/2`, `tray/2`) or its edge's `kind` (`entry/2`,
`sequence/2`, `branch/2`, `interrupt/2`, `exit/2`, `timer/2`), with the structured node or
edge and the default line. Every callback is optional.

```elixir
defmodule MyApp.Describing.RegistrationPhrasing do
  @behaviour StatifierBlocks.Describe.Phrasing

  alias StatifierBlocks.Describe.{Edge, Node}

  @impl true
  def rail(%Node{id: "corrected"}, _default), do: "A correction"
  def rail(%Node{id: "withdrawn"}, _default), do: "A withdrawal"
  def rail(%Node{}, _default), do: :default

  @impl true
  def interrupt(%Edge{event: "registration.corrected"}, _default), do: "A correction restarts the wait for the approval"
  def interrupt(%Edge{event: "registration.withdrawn"}, _default), do: "A withdrawal ends the review\nearly"
  def interrupt(%Edge{}, _default), do: :default
end

reworded = Describe.render(outline, phrasing: MyApp.Describing.RegistrationPhrasing)

reworded_lines = Enum.filter(reworded, &String.starts_with?(&1, "A "))
#=> ["A correction", "A withdrawal", "A correction restarts the wait for the approval"]

withdrawn_line = List.last(reworded)
#=> "On registration.withdrawn, When registration.withdrawn, abandon abandons the group"
```

The callback answers its own line or `:default`. An answer that is blank,
carries a newline, carriage return or tab, is not a string, or comes from a
callback that raises, throws or exits keeps the default line for that one node
or edge, never an error. That is why the withdrawal interrupt above, whose
answer carries a newline, still reads as the default.

A callback can pick one line by its endpoints as well as by id. This one
rewords the edge that leaves the `submit` step, whichever block follows it:

```elixir
defmodule MyApp.Describing.EdgePhrasing do
  @behaviour StatifierBlocks.Describe.Phrasing

  alias StatifierBlocks.Describe.Edge

  @impl true
  def sequence(%Edge{from: {:block, "submit"}}, _default), do: "Once the application is in, wait for the librarian"
  def sequence(%Edge{}, _default), do: :default
end

edge_reworded = Describe.render(outline, phrasing: MyApp.Describing.EdgePhrasing)

submit_line = Enum.find(edge_reworded, &String.starts_with?(&1, "Once "))
#=> "Once the application is in, wait for the librarian"
```

## Know what a phrasing module cannot change

The seam rewords lines one at a time. It does not add, drop or reorder them,
and it never sees or changes the outline: `render/2` with and without a
phrasing module answers the same number of lines in the same order. A
node's rewording is its own line only; an edge line that names that block
still quotes the block's default sentence, or its noun where the block is the
edge's container, so reword the edge too when it should match.

```elixir
same_count? = length(reworded) == length(lines)
#=> true
```

For the lines to stay byte-identical for equal input, each callback has to be
a pure function of its arguments; that half of the contract is yours.
