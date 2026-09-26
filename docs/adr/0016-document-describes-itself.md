# ADR-0016: A document describes itself deterministically - block sentences joined by flow-graph edges read from structure, a host phrasing seam, and no model anywhere

Status: proposed (2026-09-26, recording the operator's ruling of
2026-09-26 on how the edges are found and how a host rewords them). It
merges at proposed; flipping it to accepted is a separate request through
the same `docs/adr/` gate, after the code that builds it has shipped in a
published version.

Code cites below were read at `2033622` and carry their anchors; re-locate
by anchor, not by number.

## Context

**A document already says what each block is, one block at a time.**
ADR-0002's amendment of 2026-09-07 gave a block type an optional
`sentence/1`, and `StatifierBlocks.BlockType.sentence/2` is the resolver
that holds its return to three of the presentation refusal arms and no cap
(`lib/statifier_blocks/block_type.ex:1645`, `def sentence(ref, config)`).
ADR-0005's amendment of 2026-09-07 put the answer on the view model as
`Node.sentence`, resolved by the three-way chain written once in
`StatifierBlocks.SentenceChain.sentence/5`
(`lib/statifier_blocks/sentence_chain.ex:46`, `def sentence`), and gave a
consumer one reading-order walk, `StatifierBlocks.ViewModel.outline/1`
(`lib/statifier_blocks/view_model.ex:1015`, `def outline`), whose entries
are `{node, depth, kind}` with `kind` one of `:step`, `:arm`, `:rail`,
`:tray` (`view_model.ex:944`, `@type kind`). `ViewModel.sentence/1`
(`view_model.ex:1338`, `def sentence`) is the line a row draws, never
blank. The summary chips stay a separate reading: `BlockType.summary/3`
(`block_type.ex:1693`, `def summary`) answers capped chips, and a chip is
not a sentence.

**Nothing says how control passes between those blocks.** The outline is a
list of lines with an indent. It does not say that the second step runs
after the first, that a branch's arms are alternatives that meet again, or
that a handler on a group's rail can end the group from any point in its
body. `docs/block-level-flow-graph.md` names that vocabulary - one node
per block, four kinds of edge (sequence, branch, interrupt, exit), one
edge carrying every outcome of its source, convergence at a branch's exit,
and no edge for an event name a send and a handler merely share - and
works it through two documents, patron registration and a library loan.
It says, in its own words, that nothing in this package computes the
graph and that a flow-graph emitter would be a proposal of its own.

**A consumer that wants a document as prose has to assemble it by hand.**
A list view, a review of a change, a test asserting what a document does
and a host explaining a document to a person all want the same thing: the
block sentences, joined by what happens between them, in a stable order.
Each has to re-derive the edges from the tree, and two re-derivations
disagree the first time a branch has an empty arm. And the words a host
wants are not always the package's: a host has its own voice, and its own
names for some events, and today its only option is to post-process
strings it did not produce.

**The operator ruled on 2026-09-26** that the edges are read from the
document's structure with no compile, and that a host rewords the output
through a phrasing behaviour.

## Decision

### 1. `StatifierBlocks.Describe.outline/3` - the structure, from the document

`StatifierBlocks.Describe.outline(document, palette, opts)` takes a
`%StatifierBlocks.Document{}`, a `%StatifierBlocks.Palette{}` and a keyword
list, and answers a `%StatifierBlocks.Describe{}` holding the document's
`id`, its `revision`, a list of nodes and a list of edges. `opts` is
accepted and no key is decided by this record; an unknown key is ignored.

It is built over the view model and nothing else: it calls
`StatifierBlocks.ViewModel.build/3` with the document, the palette and an
empty findings list (the third argument is findings, not options -
`view_model.ex:519`, `def build`), walks `ViewModel.outline/1` once, and
reads each node's structure off the tree that walk returns.
**It does not compile.** No call reaches `StatifierBlocks.Compiler`, and no
chart, state id or provenance map is built or read. The edges come from
the document's tree and the block types' declarations, not from compiled
transitions.

**A node** is a `%StatifierBlocks.Describe.Node{}`, one per block, in
`outline/1`'s order, carrying:

| Field | What it is |
|---|---|
| `id` | the block id |
| `type` | the block's type name |
| `parent` | the containing block's id, `nil` for the root |
| `depth` | `outline/1`'s depth |
| `kind` | `outline/1`'s kind: `:step`, `:arm`, `:rail` or `:tray` |
| `sentence` | `ViewModel.sentence/1` of the view-model node: the type's `sentence/1` through the three-way chain, else the title |
| `outcomes` | the names `BlockType.outcomes/2` declares for the block's config, in declaration order (`block_type.ex:872`, `def outcomes`) |
| `summary` | the node's summary chips, kept apart from `sentence` and never joined into it |
| `fan_label` | `ViewModel.fan_label/1` (`view_model.ex:1056`, `def fan_label`): `"one of"`, `"all of"` or `nil` |

**An edge** is a `%StatifierBlocks.Describe.Edge{}` with a `kind`, a
`container` (the block whose structure produced it), a `from`, a `to`, and
the fields its kind uses. An endpoint is `{:block, id}`, `{:entry, id}`,
`{:exit, id}` or `{:body, id}`, the note's "entry", "exit" and "body" of a
container. Edges are found for exactly the four `core.*` types the note
works through, and only on a node the palette resolved:

- **`core.sequence`**: an `:entry` edge from `{:entry, seq}` to its first
  child; a `:sequence` edge from each child to the next; an `:exit` edge
  from the last child to `{:exit, seq}`. An empty body is one `:entry` edge
  from `{:entry, seq}` to `{:exit, seq}`.
- **`core.group` and `core.resumable_group`**: the same three over the
  `body` slot, ending at the group's exit; and one `:interrupt` edge per
  block in the `interrupts` slot, from `{:block, handler}` to
  `{:exit, group}` when the handler's `outcome` config is `abandon`, or to
  `{:body, group}` when it is `resume`. The edge carries the handler's
  `event` and, on a `core.resumable_group`, the group's `history` config
  (`shallow` or `deep`); on a `core.group` the history is `nil`, because a
  resume restarts the body from its first step.
- **`core.branch`**: one `:branch` edge for each `arm_*` slot and for
  `otherwise`, in `slots/1`'s order, and one for `undecided` only when it
  holds a block, each from `{:entry, branch}` to the slot's first child,
  or to `{:exit, branch}` when the slot is empty. It carries the arm's
  condition from config, or `:otherwise`, or `:undecided`. An empty
  `undecided` slot is not wired - it falls to `otherwise` (ADR-0012) - and
  draws no edge.
  Inside each arm, `:sequence` edges between siblings and one `:exit` edge
  from the arm's last child to `{:exit, branch}`: convergence is at the
  branch's exit, with no join node.

"Child" in these rules means a child `ViewModel.flow_children/1` answers
for the slot (`view_model.ex:862`, `def flow_children`): a drafts shelf is
a node in the outline, as `outline/1` visits it, and takes part in no edge.

A `:sequence` or `:exit` edge carries `outcomes`: the source block's
declared outcome names, all of them on the one edge, because the
compiled edge fires on `done.state`, which any outcome raises. An
`:entry`, `:branch` or `:interrupt` edge carries no outcomes.

**Every other type is described by containment only.** `core.parallel`,
`core.foreach`, `core.map`, `core.subchart`, `core.invoke`, every composite
and every host type contribute their nodes, each child's `parent` and
`depth`, and the parent's `fan_label` - "one of" for alternatives, "all of"
for concurrent lanes - and no edge inside them. A block of such a type
still takes part in its parent's edges like any other child. The note does
not work those types through; a record that does may add their edges, and
until one does, the describe does not guess at them.

**No edge joins two blocks by an event name alone.** A `core.send` and a
handler listening for the same name share a string, not a transition, and
the describe draws nothing between them, as the note says of the chart.

**Declared, not compiled, outcomes.** An edge's outcomes are the ones the
source's type declares, not the finals a compile would emit, and the two
can differ. In the note's two worked examples they differ for one type:
`core.await` declares `received` and `timed_out` for every config
(`lib/statifier_blocks/core/await.ex:123`, `def outcomes`), while its
compiled chart holds a `timed_out` final only when a `timeout` is set.
So the exit edges from `blk_PVER` (patron registration) and `blk_LPAY`
(the library loan), both awaits with no timeout, say `received,
timed_out` where the note's listings, lifted from the compiled chart, say
`received`. Every other edge in both worked examples - its endpoints, its
kind, its condition, its event, its history, and every other outcome
list - is what the describe produces. The declared list is the one an
author wiring a parent reads, and it is the only one the describe can
have without compiling.

### 2. `StatifierBlocks.Describe.render/2` - one line per node and per edge

`StatifierBlocks.Describe.render(outline, opts)` answers a list of strings:
one line per node in the outline's node order, then one line per edge in
the outline's edge order. Edge order is the containers' order in the walk,
and within one container: its entry edge, then its body's edges in slot
and child order (for a branch, each arm's branch edge followed by that
arm's sequence and exit edges), then its interrupt edges in rail order.

The line contract is `BlockType.sentence/2`'s: each line is a non-blank
English string carrying no newline, carriage return or tab, and there is
**no length cap**. A newline, carriage return or tab inside a string the
author wrote (a condition, an event name) is replaced by one space in the
default line, so the default always meets the contract.

The default lines, where `S(x)` is the sentence of the block at `x`:

| Line | Default |
|---|---|
| a node | its `sentence`, followed by ` (one of)` or ` (all of)` when `fan_label` is set |
| `:entry` | `<S(container)> starts with <S(to)>` |
| `:sequence` | `After <S(from)> (<outcomes, comma-separated>), <S(to)>` |
| `:exit` | `<S(from)> (<outcomes, comma-separated>) ends <S(container)>` |
| `:branch` | `<S(container)>: when <condition>, <target>`; `otherwise, <target>` and `if undecided, <target>` for those two slots |
| `:interrupt` | `On <event>, <S(from)> abandons <S(container)>`, or `On <event>, <S(from)> resumes <S(container)>`, followed by ` at <history> history` when history is set |

A `<target>` that is `{:exit, id}` reads `the end of <S(id)>`. A block's
id never appears in a default line; a host that needs ids in the words
supplies them through the phrasing seam.

### 3. `StatifierBlocks.Describe.Phrasing` - the host's words

`render/2` takes `phrasing: module` in `opts`. The module implements the
behaviour `StatifierBlocks.Describe.Phrasing`, whose callbacks are all
optional, one per node kind and one per edge kind:

- node callbacks `step/2`, `arm/2`, `rail/2`, `tray/2`, chosen by the
  node's `kind`;
- edge callbacks `entry/2`, `sequence/2`, `branch/2`, `interrupt/2`,
  `exit/2`, chosen by the edge's `kind`.

Each receives the structured `%Describe.Node{}` or `%Describe.Edge{}` and
the default string, and answers a string or `:default`. `:default`, an
undeclared callback, and no `phrasing` option all mean the default line.
**A refused answer falls back to the default**, never to an error: a
blank string, a string carrying a newline, carriage return or tab, a
non-string other than `:default`, and a callback that raises, throws or
exits are each answered with the default line for that node or edge. It is
the refusal set `BlockType.sentence/2` holds a type's `sentence/1` to, on
the same grounds: a host's words for one line cost that line and nothing
else.

The seam rewords lines; it does not add, drop or reorder them, and it
never sees or changes the structure `outline/3` answered.

### 4. No model anywhere

The describe is arithmetic over the document. Nothing in
`StatifierBlocks.Describe` calls a language model, a network, a clock, a
random source or a process, at build time or at run time, and it reads
nothing outside its arguments and the palette's pure callbacks. Equal
input gives byte-identical output: the same document, palette and options
answer the same outline, and the same outline and options render the same
lines, on every machine and every run. A host that wants a model to
summarise a document can hand it these lines; that is the host's choice,
made outside this package.

### 5. What it is not

- **Not a layout.** No coordinate, size, colour or drawing rule is
  answered, and no renderer of the outline ships with it.
- **Not the editor's connector layer.** `StatifierBlocks.Connectors.edges/2`
  (`lib/statifier_blocks/connectors.ex:409`, `def edges`) draws edges from
  measured rectangles; the describe measures nothing.
- **Not a state-index renderer.** One block is one node; generated role
  states and outcome finals do not appear.
- **Not a compiled-chart emitter.** It reads no chart. Lifting edges from a
  compiled chart, as the note does by hand, stays a proposal of its own.
- **Not `StatifierBlocks.Graph`**, which checks references between
  documents; the describe never leaves one document.
- **Not localised.** The default lines are English; other words arrive
  through the phrasing seam.

## Consequences

- A host, a test or a review gets a document's prose from one call and one
  walk, and two consumers cannot disagree about the edges.
- The surface is new and additive: the module `StatifierBlocks.Describe`,
  its two structs `Describe.Node` and `Describe.Edge`, `outline/3`,
  `render/2`, and the behaviour `Describe.Phrasing`. No existing function
  answers anything different, and a host that calls none of them sees no
  change. The changelog fragment rides with the request that builds it.
- The describe's edges agree with the compiled chart for the four types it
  covers except where a type declares an outcome its compiled chart cannot
  reach (decision 1's last paragraph). A test may compile a document to
  cross-check the edges; the describe itself never does.
- The two worked examples in `docs/block-level-flow-graph.md` are the
  acceptance shape: the building request asserts the describe's edges for
  the patron registration fixture and for the library loan document, line
  for line against the note's lifted listings, with the one declared
  outcome difference named in decision 1.
- The note's sentence "nothing in this package computes the graph" stops
  being true of main once `StatifierBlocks.Describe` ships; a dated Note at
  the foot of the note says where the computation is.
- Adding edges for `core.parallel`, `core.foreach`, `core.map`,
  `core.subchart` or composites is an amendment to this record, worked
  through against their emitted shapes first.
- Because output is byte-identical for equal input, a rendered description
  can be stored beside a document revision and compared across revisions
  as text.
