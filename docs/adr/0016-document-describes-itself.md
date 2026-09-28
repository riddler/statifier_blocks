# ADR-0016: A document describes itself deterministically - block sentences joined by flow-graph edges read from structure, a host phrasing seam, and no model anywhere

Status: accepted (2026-09-26, recording the operator's ruling of
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

## Note (2026-09-27): decision 1, what the describe reads besides the view model

A dated note, not an amendment: it changes no decision in this record.

Decision 1 says the describe "is built over the view model and nothing
else". The view model's nodes carry no block config, and three things
decision 1 asks of the describe are config: a node's declared outcomes, a
handler's `event` and `outcome` select, and a resumable group's `history`.
So `outline/3` also reads each block of the document it was given, resolved
through the same palette it was given, for that block's config:

- `StatifierBlocks.Describe.outline/3` resolves every block of the
  document's tree once, beside the view model it builds
  (`describe.ex:121`, `def outline`, read at `a53155f`).
- The resolution is `Palette.resolve/2` (`describe.ex:191`, `defp resolve`,
  read at `a53155f`), the same lookup the view model makes for each node
  (`view_model.ex:1996`, `defp build_node`, read at `a53155f`).
- A node's `outcomes` are `BlockType.outcomes/2` of that resolved config
  (`describe.ex:199`, `defp outcomes`, read at `a53155f`).
- A resumable group's edge `history` is read from its resolved config
  (`describe.ex:226`, `defp container_edges(ResumableGroup, ...)`, read at
  `a53155f`).

The describe still compiles nothing and reads nothing outside its
arguments: the document and the palette are the only inputs, as decisions 1
and 4 require.

The interrupt edge is keyed on the handler's `outcome` config, as decision
1 says. Before the request that adds this Note, the describe read the
outcome from the view model node, which answers the name an abandoning
handler finishes with (`finish_as`) ahead of the select, so a handler with
`outcome: "abandon"` and a `finish_as` drew no edge. It now reads the
select at the slot's declared outcome key from the handler's resolved config
(`defp select/3` in `lib/statifier_blocks/describe.ex`, added in the same
request as this Note; a handler the palette cannot resolve is read from the
document's own config, as before), and decision 1's interrupt sentence holds
as written.
A `finish_as` beside `outcome: "resume"` is refused by `core.on_event`'s
config validation, so no resume handler names one.

## Note (2026-09-27): this record is flipped to accepted

A dated Note rather than an amendment: it carries no `Status:` line, decides
nothing, and edits no clause. The only line this request changes above it is
the record's own `Status:` line (`:3`), by one word, `proposed` to
`accepted`; the index row in `README.md` changes its status cell with it.
Everything else is this Note, at the foot of the file, so no line another
record cites moves.

The code this record decides first shipped in `statifier_blocks` 0.36.0
(tag `v0.36.0`, `d98dffb`). The interrupt-edge correction that the Note of
2026-09-27 above describes shipped in 0.36.1 (tag `v0.36.1`, `647e44f`),
and 0.36.1 is the published version that carries the code as this record
describes it. Every claim below was read at `647e44f`, which is both the
`v0.36.1` tag and `main` when this request was written. The record's own
cites are labelled `2033622`; each anchor still names the line the record
says, and none has moved. The tests named below are in
`test/statifier_blocks/describe_test.exs`.

### Each decision, and where it reads today

| Decision | Read at `647e44f` |
|---|---|
| 1, `outline/3` | `StatifierBlocks.Describe.outline/3` (`describe.ex:121`, `def outline`) answers a `%StatifierBlocks.Describe{}` with the document's `id` and `revision`, its nodes and its edges, and reads no key of `opts`. It calls `ViewModel.build/3` with an empty findings list and walks `ViewModel.outline/1` once. The sentence "It is built over the view model and nothing else" is superseded by the Note of 2026-09-27 above, which says what else it reads: each block of the document, resolved through the same palette, for its config. Nothing in the module calls `StatifierBlocks.Compiler`; the test `the compiled modules import nothing that reaches one` pins that |
| 1, a node | `StatifierBlocks.Describe.Node` (`describe/node.ex`, `defstruct`) carries the nine fields of the table, filled in `defp node/4` (`describe.ex:164`) |
| 1, the four types | `defp container_edges/4` (`describe.ex:220`) draws edges for `core.sequence`, `core.group`, `core.resumable_group` and `core.branch` only, and `defp edges/3` (`describe.ex:208`) draws none inside a block the palette did not resolve. An abandon handler ends at the group's exit and a resume handler at its body, keyed on the handler's `outcome` select (`defp select/3`, `describe.ex:371`), which holds for a handler that names `finish_as` (the test `an abandon handler that names finish_as draws its interrupt edge to the exit`). A resume into a `core.resumable_group` carries its `history`, and a resume into a `core.group` carries `nil` (the test `a plain group's resume re-enters its body from the first step; an empty body`). An abandon edge carries no history, which is what the library loan's lifted listing says of `blk_LLOS` |
| 1, a branch | one `:branch` edge per arm and for `otherwise`, and for `undecided` only when it holds a block (`defp branch_edges/2`, `describe.ex:251`; `defp unwired_undecided?/1`, `describe.ex:275`), each arm followed by its own sequence and exit edges (the test `a branch: an empty guarded arm, a wired otherwise, a wired and an unwired undecided`) |
| 1, outcomes and the other types | a `:sequence` or `:exit` edge carries the source's declared outcome names (`defp chain/3`, `describe.ex:288`); every other type draws no edge inside itself (`container_edges/4`'s last clause, `describe.ex:234`). `core.await` declares `received` and `timed_out` for every config (`core/await.ex:123`, `def outcomes`), and the tests `patron registration produces the note's edges` and `the library loan produces the note's edges` assert both worked examples edge for edge, with the one declared-outcome difference the record names |
| 2, `render/2` | `StatifierBlocks.Describe.render/2` (`describe.ex:151`, `def render`) answers the node lines then the edge lines, in the default words of the table (`defp edge_line/2`, `describe.ex:407`), with a newline, carriage return or tab in an author's text written as one space (`defp flat/1`, `describe.ex:455`). The test `the library loan renders the default lines` pins every line of one worked example |
| 3, the phrasing seam | `StatifierBlocks.Describe.Phrasing` (`describe/phrasing.ex`, `@optional_callbacks`) declares the nine optional callbacks. `defp phrase/4` (`describe.ex:462`) chooses the callback by kind and falls back to the default line on a refused answer or a raise, throw or exit (`defp ask/4`, `describe.ex:469`; `defp usable/1`, `describe.ex:481`). The tests under `the phrasing seam` pin each arm |
| 4, no model anywhere | the tests under `determinism` and under `no network, clock, process, random source or model` pin byte-identical output and the absence of each of those calls from the four compiled modules and their sources |
| 5, what it is not | no layout, no renderer and no chart read ship with the module; `StatifierBlocks.Connectors.edges/2` (`connectors.ex:409`, `def edges`) and `StatifierBlocks.Graph` are unchanged and separate |

One reading is named here rather than left to be found. Decision 2's
`:entry` row writes its target as `<S(to)>`, and an entry edge into an
empty body ends at the container's exit rather than at a block. The line
reads that endpoint the way decision 2's `<target>` sentence reads an exit,
"the end of" the container's sentence, as the test `a plain group's resume
re-enters its body from the first step; an empty body` pins.

### Sentences that name their own status

They are met here, not edited.

- The status paragraph says the record "merges at proposed; flipping it to
  accepted is a separate request through the same `docs/adr/` gate, after
  the code that builds it has shipped in a published version" (`:4-7`).
  This request is that one, and 0.36.1 is that version.
- Consequences says the flow-graph note's sentence "nothing in this package
  computes the graph" stops being true of main once the module ships, and
  that a dated Note at the foot of the note says where the computation is.
  `docs/block-level-flow-graph.md` carries that Note (`## Note (2026-09-26):
  where the graph is computed`), and the module has shipped.

## Amendment (2026-09-27): decision 1's event-name rule gains one named exception - the `:timer` edge

**Status: accepted (2026-09-27, drafted under the operator's campaign
consent on the operator's ruling of that date).** It merges at proposed;
flipping this section's status line to accepted is a separate request
through the same `docs/adr/` gate, after the code that builds it has shipped
in a published version. The record's own `Status:` line (`:3`) is not
changed by it.

Code cites below were read at `91fd2a1` and carry their anchors; re-locate
by anchor, not by number.

### Why this is an amendment

Decision 1 says: "No edge joins two blocks by an event name alone. A
`core.send` and a handler listening for the same name share a string, not a
transition, and the describe draws nothing between them". `ADR-0017`
decision 3 draws exactly such an edge for one pair, a delayed `core.send`
and the rule or await that names its event. That changes what decision 1
decides, so it is recorded here as an amendment with a status line rather
than as a Note, and `ADR-0017` does not decide it alone.

### The amendment

1. **One named exception.** Decision 1's event-name rule holds for every
   pair except one: a `core.send` whose `delay` is a duration
   `StatifierBlocks.Core.Duration.duration?/1` accepts
   (`lib/statifier_blocks/core/duration.ex:81`, `def duration?`), and a
   `core.on_event` or `core.await` in the same document whose `event` config
   is the send's `event`. For that pair `outline/3` answers one `:timer`
   edge from `{:block, send}` to `{:block, rule_or_await}`, whose
   `container` is the send's parent block. The shapes and the order are
   `ADR-0017` decision 3's. An undelayed send, and any other pair sharing a
   name, still draws nothing.
2. **A sixth edge kind, found outside the four container types.** Decision
   1 finds edges "for exactly the four `core.*` types the note works
   through"; the timer edge is found across the whole document instead,
   over blocks the palette resolved, and a block inside a `core.drafts`
   shelf takes part in none. The four container types' edges are
   unchanged, and every other type is still described by containment only.
3. **A field for the label.** `StatifierBlocks.Describe.Edge`
   (`lib/statifier_blocks/describe/edge.ex:49`, `defstruct`) gains `delay`,
   the send's delay as its config holds it, set on a `:timer` edge and `nil`
   on every other kind; the edge's existing `event` field carries the sent
   event. The `kind` type (`edge.ex:30`, `@type kind`) admits `:timer`.
4. **Decision 2's order and words.** Timer edges follow every edge decision
   2 orders, in the outline's order of their sends and then of their
   targets. Their default line is `In <delay>, <event> reaches <S(to)>`,
   with the delay written as `ADR-0017` decision 2 writes it, under the line
   contract decision 2 states.
5. **Decision 3 gains `timer/2`.** `StatifierBlocks.Describe.Phrasing`
   (`lib/statifier_blocks/describe/phrasing.ex:72`, `@optional_callbacks`)
   gains one optional callback, `timer/2`, asked for a `:timer` edge, with
   the same arguments, answers and refusal set as the other nine.

### What this amendment does not change

- **No existing edge or line changes.** A document with no delayed send
  describes and renders byte for byte as before; a document with one gains
  its timer edges after all the others and loses nothing.
- **Still no compile.** The edge is read from the document's config;
  decision 4's "no model anywhere" and the inputs the Note of 2026-09-27
  names are unchanged.
- **Not a chart edge.** The timer edge is not a transition, and
  `docs/block-level-flow-graph.md`'s sentence that a send and a handler
  sharing a name are not an edge stays true of the chart and of the graph
  the note lifts. The note is not edited by this amendment.
- **The acceptance shape grows by one edge.** The patron registration
  document's describe gains the timer edge from `blk_PDLN` to `blk_PEXP`
  beyond the note's lifted listing; the library loan has no delayed send
  and gains none. The building request asserts both.

Filed with `sb-q9d7`; `sb-1vro` builds it.

## Note (2026-09-28): the Amendment of 2026-09-27 is flipped to accepted

A dated Note rather than an amendment: it carries no `Status:` line, decides
nothing, and edits no clause. The only line this request changes above it is
the Amendment's own status line (`:367`), by one word, `proposed` to
`accepted`. The record's own `Status:` line (`:3`) already reads accepted
and is not touched. Everything else is this Note, at the foot of the file,
so no line another record cites moves.

The code the Amendment decides shipped in `statifier_blocks` 0.37.0 (tag
`v0.37.0`, `12d3d22`), the published version that carries it. Every claim
below was read at `12d3d22`, which is both the `v0.37.0` tag and `main` when
this request was written. `ADR-0017`, whose decision 3 the Amendment
shares, is flipped to accepted by the same request.

| Item | Read at `12d3d22` |
|---|---|
| 1, one named exception | `defp timer_edges/2` (`describe.ex:437`) draws one `:timer` edge from `{:block, send}` to `{:block, rule_or_await}` for each `core.send` whose `delay` `Duration.duration?/1` (`core/duration.ex:81`, `def duration?`) accepts and each `core.on_event` or `core.await` whose `event` is the send's; `defp timer_edge/3` (`describe.ex:466`) sets `container` to the send's parent. An undelayed send draws none (the test `a document with no delayed send answers no timer edge`) |
| 2, found across the document | the timer edges are read over every block of the outline rather than inside a container, admitted by `defp timer_party/2` (`describe.ex:456`) only when resolved and outside a drafts shelf (the test `a block inside a drafts shelf takes part in no timer edge`); `defp container_edges/4` still draws for the four container types only |
| 3, a field for the label | `StatifierBlocks.Describe.Edge` carries `delay: nil` (`describe/edge.ex:58`, `defstruct`), set only by `timer_edge/3`, and `@type kind` (`describe/edge.ex:38`) admits `:timer` |
| 4, order and words | `StatifierBlocks.Describe.outline/3` (`describe.ex:153`, `def outline`) appends the timer edges after every other edge; `defp edge_line/2`'s timer clause (`describe.ex:534`) writes `In <delay>, <event> reaches <S(to)>` with the delay in `core.send`'s sentence words. The tests `timer edges follow every other edge, and render byte-identically` and `patron registration renders the timer edge's line last` pin both |
| 5, `timer/2` | `StatifierBlocks.Describe.Phrasing` declares `@callback timer` (`describe/phrasing.ex:73`) among its `@optional_callbacks` (`describe/phrasing.ex:75`); the test `timer/2 rewords the timer edge's line, and only that line` pins it |
| what it does not change | the test `the library loan produces the note's edges` still asserts that document's edges with no timer edge, and `patron registration produces the note's edges` asserts the one added edge from `blk_PDLN` to `blk_PEXP` after the others. `docs/block-level-flow-graph.md` is not edited by the Amendment; its dated Note of 2026-09-27, added by the request that built the edge, says the event-name sentence stays true of the chart |

The Amendment's cites were read at `91fd2a1`. Re-located by anchor at
`12d3d22`: `defstruct` in `describe/edge.ex` is at `:58` (`:49` above),
`@type kind` at `:38` (`:30` above), and `@optional_callbacks` in
`describe/phrasing.ex` at `:75` (`:72` above); the cite into
`core/duration.ex` has not moved.

The Amendment's status paragraph says flipping it is "a separate request
through the same `docs/adr/` gate, after the code that builds it has shipped
in a published version". This request is that one, and 0.37.0 is that
version.
