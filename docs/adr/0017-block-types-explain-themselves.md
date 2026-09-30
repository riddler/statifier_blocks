# ADR-0017: Block types explain themselves - an optional `explain/0` paragraph, a delayed send that says when, and a `:timer` edge in the describe

Status: accepted (2026-09-27, drafted under the operator's campaign consent;
the rulings it records were taken by the operator on 2026-09-27). It merges
at proposed; flipping it to accepted is a separate request through the same
`docs/adr/` gate, after the code that builds it has shipped in a published
version.

Code cites below were read at `91fd2a1` and carry their anchors, except
the cites into `lib/statifier_blocks/core/send.ex` in decision 2, which were
read at `99b5383`, the commit that built that decision; re-locate by anchor,
not by number.

## Context

**A reader of a document gets two kinds of text today, and neither
explains a type.** A block's card draws a label and capped chips, and the
cap is 24 characters (ADR-0005 decision 10's `10n`). A block's sentence,
from the optional `sentence/1` ADR-0002's amendment of 2026-09-07 gave a
type, is one uncapped line about *this* block and its config, read through
`StatifierBlocks.BlockType.sentence/2` (`lib/statifier_blocks/block_type.ex:1645`,
`def sentence`). Neither says what a type *does*: that a group's interrupt
rules leave the group whenever their event arrives, or that a branch tries
its arms in order and runs the first whose condition holds. A first-time
reader of a document needs that paragraph once per type, and today a host
has only the palette entry's one-line `description`
(`block_type.ex:631`, `optional(:description)`) to show.

**A delayed send did not say when.** `core.send` holds an `event` and an
optional `delay` duration, and at `91fd2a1` its sentence named only the
event (`lib/statifier_blocks/core/send.ex:201`, `def sentence`): its doc
said the delay was "deliberately left out". So a clock interrupt in
ADR-0010's spelling - a delayed `core.send` at the head of a group's body,
caught by a `core.on_event` on the group's rail - read as "Send
registration.deadline" beside "Wait for email.verified", and nothing on the
page said that the deadline was a day away.

**The describe cannot show the clock either.** ADR-0016 decision 1 draws no
edge between two blocks that share only an event name, as
`docs/block-level-flow-graph.md` says of the chart. That keeps the describe
honest about transitions, and it also leaves a reader of a patron
registration with no line between the send that arms the deadline and the
rule that fires on it. The pair is not an accident of naming: ADR-0010 made
it the one spelling of a clock interrupt, and ADR-0014 places its delayed
event among the events a document sends itself.

**The operator ruled on 2026-09-27**, in three rulings this record states
as decisions 1, 2 and 3: text in three tiers with a per-type explanation
from a new optional callback; the delay in a delayed send's sentence; and a
timer edge in the describe, drawn dashed.

## Decision

### 1. `explain/0` - one paragraph per type, and its resolver

**The callback.** `StatifierBlocks.BlockType` gains an optional callback
`explain() :: String.t()`. It answers a short paragraph that says what
every block of the type does - the same text for every block of the type,
so it takes no config. It is pure, and it has no cap. Its line rule is the
sentence's and no other: a non-blank string carrying no newline, carriage
return or tab.

**The resolver.** `StatifierBlocks.BlockType.explain/1` takes a type
reference (`Palette.type_ref()`) and answers a string or `nil`:

| The type | `explain/1` answers |
|---|---|
| declares `explain/0`, and it answers a usable paragraph | that paragraph, verbatim, uncapped |
| declares none, or its answer is refused | the palette entry's `description`, when that is itself a usable line |
| neither of the above | `nil` |

"Usable" is the refusal set `sentence/2` holds a type's `sentence/1` to: a
non-string, a blank string, and a string carrying a newline, carriage
return or tab are refused, and a callback that raises, throws or exits is
treated as refused. Declaredness and the call go through the palette's one
seam, `StatifierBlocks.Palette.declares?/3` (`lib/statifier_blocks/palette.ex:648`,
`def declares?`) and `Palette.call/4` (`palette.ex:606`, `def call`), so a
stateful `{module, state}` reference resolves the way a bare module does.

**Not injected.** `use StatifierBlocks.BlockType` does not inject a default
`explain/0` (`block_type.ex:110`, `defmacro __using__`): a type that does
not declare one falls to its palette description at the resolver. So no
existing type, core or host, answers anything new from the injected set.

**Every core type declares one.** Each shipped `core.*` type answers a
non-empty paragraph a first-time reader can use. The exact words are the
building request's.

### 2. `core.send`'s sentence names its delay

`core.send`'s `sentence/1` reads `In <delay>, send <event>` when its config
carries a delay, and is unchanged when it does not. A delay counts when
`StatifierBlocks.Core.Duration.duration?/1` accepts it
(`lib/statifier_blocks/core/duration.ex:81`, `def duration?`); an absent,
empty or unreadable delay is no delay, and the line reads as it did before,
`Send <event>` or `Send an event`. The event half is unchanged: a name that
is not well formed reads as "an event".

A delay in the short duration form - whole numbers, each unit at most once,
largest unit first - is written in words, one phrase per unit, singular for
one: `24h` is "24 hours", `7d` is "7 days", `1h30m` is "1 hour 30
minutes". Any other spelling the field accepts, a fraction or a repeated
unit, is written exactly as stored. That is `core.send`'s `sentence/1`
(`core/send.ex:216`, `def sentence`) through its private `delay_words/1`
(`core/send.ex:246`, `defp delay_words`), which tests the short form
against `@short_form` (`core/send.ex:229`), all read at `99b5383`. The
sentence stays pure over config and total for any config, as ADR-0002's
sentence contract requires, and it stays one line.

This is the one change to what an existing function answers in this record.
Every surface that draws a delayed send's sentence changes with it, and the
changelog names that change.

### 3. A `:timer` edge in the describe

`StatifierBlocks.Describe.outline/3` answers, beside ADR-0016's `:entry`,
`:sequence`, `:exit`, `:branch` and `:interrupt` edges, one `:timer` edge
for each pair of:

- a **delayed `core.send`** - a `core.send` whose delay counts under
  decision 2 - and
- a **`core.on_event`** (an interrupt rule) **or a `core.await`** anywhere
  in the same document whose `event` config is the send's `event`, the same
  string.

The edge runs from `{:block, send}` to `{:block, rule_or_await}`. Its
`container` is the send's parent block. It carries the send's `event` in
the edge's existing `event` field, and the delay, as the send's config
holds it, in a new field `delay` on `StatifierBlocks.Describe.Edge`
(`lib/statifier_blocks/describe/edge.ex:49`, `defstruct`): the delay is the
edge's label. `delay` is `nil` on every other kind of edge.

Only blocks the palette resolved take part, as in ADR-0016 decision 1, and
a block inside a `core.drafts` shelf takes part in none, as the shelf itself
takes part in no edge there. A send with no delay draws no timer edge, and
an undelayed send still shares only a string with any handler. The edge is read from the
document's structure and config: nothing is compiled. It is not a
transition; it says that one block arms an event another block is waiting
for.

**Order and words.** Timer edges follow every edge ADR-0016 decision 2
orders, in the outline's order of their sends, and for one send in the
outline's order of their targets. `render/2`'s default line is
`In <delay>, <event> reaches <S(to)>`, with the delay in decision 2's words
and a newline, carriage return or tab in an author's text written as one
space. `StatifierBlocks.Describe.Phrasing` gains one optional callback,
`timer/2`, asked for a `:timer` edge on the same terms as the other nine.

For the patron registration document the describe gains one edge: from the
deadline send `blk_PDLN` (`registration.deadline`, delay `24h`) to the
rule `blk_PEXP` that abandons the group on that event. The library loan
document has no delayed send and gains none.

### 4. What a renderer draws from each

The package ships no renderer of the outline (ADR-0016 decision 5), and
the editor's card is ADR-0005's: this record adds nothing to it, and the one
difference it shows is decision 2's sentence wherever it draws a sentence.
A renderer that draws a document from these answers - the reference host's
map view in `statifier_examples` is the first - draws three tiers of text:

1. **The card line**, on every box, under ADR-0005's cap.
2. **The sentence**, on a container's header and in a detail panel.
3. **The explanation**, `BlockType.explain/1` of the block's type, in a
   description region beside the drawing, and as a caption of one line
   under a **structural container** - a block whose type declares at least
   one slot. A leaf, a block whose type declares no slot, never carries it.

It draws a `:timer` edge dashed, labelled with its delay, and draws
`:interrupt` edges as well. It marks a `core.await` with a wait mark and a
delayed `core.send` with a clock mark; both marks are read from the block's
type and config, and need nothing new from this package.

### 5. What changes, and what does not

The code this record decides is three requests:

- the callback `explain/0`, the resolver `BlockType.explain/1`, and an
  explanation for every core type;
- the sentence change in `core.send`'s `sentence/1`;
- the edge kind `:timer`, the `delay` field on `Describe.Edge`, its default
  line in `render/2`, and `Describe.Phrasing.timer/2`.

The three are additive. **No existing answer changes except the delayed
send's sentence** (decision 2): every other function answers what it
answered before, and a host that calls none of the new surface sees one
difference, the sentence of a delayed send. A document with no delayed send
describes, edge for edge and line for line, as it did.

## Consequences

- A first-time reader learns what a type does from the type, once, and a
  host that ships its own types can say the same about them; a host type
  that declares nothing still shows its palette description.
- A delayed send says when, on every surface that shows a sentence: the
  outline, the describe's node lines and a renderer's headers.
- The clock interrupt of ADR-0010 is visible in the describe as one dashed
  edge from the send to the rule it arms, without a compile.
- The timer edge is a describe-level reading, not a lifted chart edge:
  `docs/block-level-flow-graph.md`'s sentence that an event name shared by
  a send and a handler is not an edge stays true of the chart and of the
  graph the note lifts. ADR-0016's rule for the describe gains this one
  named exception, in that record's Amendment of 2026-09-27.
- `explain/0` is a new optional callback beside decision 5 of ADR-0002 and
  changes no card line; ADR-0002 carries a dated Note pointing here, in the
  shape its Note on `donedata_type/1` took.
- A caption on every structural container costs vertical space in a
  renderer; the leaf rule keeps the cost to the containers, and the
  description region carries the rest.
- The changelog fragment for the sentence change names the visible
  card-line change for delayed sends.

## Note (2026-09-28): this record is flipped to accepted

A dated Note rather than an amendment: it carries no `Status:` line, decides
nothing, and edits no clause. The only line this request changes above it is
the record's own `Status:` line (`:3`), by one word, `proposed` to
`accepted`; the index row in `README.md` changes its status cell with it.
Everything else is this Note, at the foot of the file, so no line another
record cites moves.

The code this record decides shipped in `statifier_blocks` 0.37.0 (tag
`v0.37.0`, `12d3d22`), the published version that carries it. Every claim
below was read at `12d3d22`, which is both the `v0.37.0` tag and `main` when
this request was written.

### Each decision, and where it reads today

| Decision | Read at `12d3d22` |
|---|---|
| 1, the callback | `StatifierBlocks.BlockType` declares `@callback explain() :: String.t()` (`block_type.ex:857`) and lists `explain: 0` among its `@optional_callbacks` (`block_type.ex:859`). The test `explain/0 is declared, and declared optional` pins both |
| 1, the resolver | `StatifierBlocks.BlockType.explain/1` (`block_type.ex:1703`, `def explain`) answers the declared paragraph held to `defp line/1` (`block_type.ex:2124`), the refusal set `sentence/2` uses, else the palette entry's `description` held to the same set (`defp description/1`, `block_type.ex:2112`), else `nil`. A raise, throw or exit is a refused answer (`defp call_explain/1`, `block_type.ex:2100`). Declaredness and the call go through `Palette.declares?/3` (`palette.ex:648`, `def declares?`) and `Palette.call/4` (`palette.ex:606`, `def call`). The tests under `the resolver` in `test/statifier_blocks/block_type/explain_test.exs` pin each row of the table, the refusals and a `{module, state}` reference |
| 1, not injected | `defmacro __using__` (`block_type.ex:112`) injects no `explain/0`; the test `use StatifierBlocks.BlockType does not inject one` pins it |
| 1, every core type | each of the seventeen `core.*` types `Palette.core_types/0` lists (`palette.ex:221-237`) declares `def explain`; the test `the core palette's every type answers its own non-empty, one-line paragraph` pins it over the core palette |
| 2, the sentence | `core.send`'s `sentence/1` (`core/send.ex:216`, `def sentence`) answers `In <delay>, send <event>` when `delay_words/1` (`core/send.ex:249`) names a delay, and `Send <event>` or `Send an event` otherwise. `delay_words/1` answers `nil` unless `Duration.duration?/1` (`core/duration.ex:81`, `def duration?`) accepts the delay, writes a delay matching `@short_form` (`core/send.ex:229`) in words and any other accepted spelling as stored. The tests under `sentence/1` in `test/statifier_blocks/core/send_test.exs` pin the unchanged undelayed line, the delayed line, the words and the stored spelling |
| 3, the edge | `StatifierBlocks.Describe.outline/3` (`describe.ex:153`, `def outline`) appends the timer edges after every other edge; `defp timer_edges/2` (`describe.ex:437`) pairs each delayed `core.send` with every `core.on_event` and `core.await` naming its event, sends then targets in the outline's order, over blocks `defp timer_party/2` (`describe.ex:456`) admits, resolved and outside a drafts shelf; `defp timer_edge/3` (`describe.ex:466`) sets `container` to the send's parent, `event` and `delay`. `StatifierBlocks.Describe.Edge` carries `delay: nil` (`describe/edge.ex:58`, `defstruct`) and its `kind` admits `:timer` (`describe/edge.ex:38`, `@type kind`) |
| 3, the line and the callback | `defp edge_line/2`'s timer clause (`describe.ex:534`) writes `In <delay>, <event> reaches <S(to)>`, the delay through `core.send`'s `delay_words/1` and the event through `defp flat/1` (`describe.ex:569`). `StatifierBlocks.Describe.Phrasing` declares `@callback timer` (`describe/phrasing.ex:73`) among its `@optional_callbacks` (`describe/phrasing.ex:75`), asked by kind in `render/2` like the other nine |
| 3, the worked examples | the tests `patron registration produces the note's edges` and `patron registration renders the timer edge's line last` in `test/statifier_blocks/describe_test.exs` pin the one timer edge from `blk_PDLN` to `blk_PEXP`, with container `blk_PGRP`, and its line `In 24 hours, registration.deadline reaches When registration.deadline, abandon`; `a document with no delayed send answers no timer edge` pins that the library loan gains none. The tests under `the timer edge` pin the order, the drafts shelf and an unresolved block |
| 4, what a renderer draws | the package ships no renderer of the outline, and the marks decision 4 names are read from a block's type and config, needing nothing further from this package |
| 5, what changes | the three requests landed as the commits `133b1af` (the callback, the resolver and every core type's paragraph), `99b5383` (the sentence) and `40cb469` (the edge kind, the `delay` field, the line and `timer/2`); the `0.37.0` section of `CHANGELOG.md` lists them, with the delayed send's card line under Changed as the one changed answer |

### Cites that moved, and one that changed shape

The record's cites were read at `91fd2a1` and `99b5383`. Re-located by
anchor at `12d3d22`: `def sentence` in `block_type.ex` is at `:1666`
(`:1645` above), `optional(:description)` at `:633` (`:631` above) and
`defmacro __using__` at `:112` (`:110` above); `defstruct` in
`describe/edge.ex` is at `:58` (`:49` above) and `@type kind` at `:38`
(`:30` above); `@optional_callbacks` in `describe/phrasing.ex` is at `:75`
(`:72` above). The cites into `palette.ex`, `core/duration.ex`, and
`core/send.ex`'s `def sentence` and `@short_form` have not moved.

Decision 2 names `delay_words/1` as `core.send`'s private helper, anchored
`defp delay_words` at `core/send.ex:246`. At `12d3d22` it is
`def delay_words` at `core/send.ex:249`, carrying `@doc false`: the request
that built decision 3 made it public so the describe writes a timer edge's
delay in the words the sentence uses, which decision 3 requires. Its comment
says it is not part of the public API, and it has no documentation entry, so
it remains private to the package in the sense the record uses; what
decision 2 decides reads as written.

### Sentences that name their own status, and one that is superseded

- The status paragraph says the record "merges at proposed; flipping it to
  accepted is a separate request through the same `docs/adr/` gate, after
  the code that builds it has shipped in a published version" (`:4-7`).
  This request is that one, and 0.37.0 is that version.
- Context says a card's chips are capped at "24 characters (ADR-0005
  decision 10's `10n`)" (`:17-18`). `ADR-0005`'s Note of 2026-09-08, item 2,
  moved that number to 32, and the code's `@presentation_cap` is 32
  (`block_type.ex:1436`); the sentence's point, that a capped chip cannot
  carry a paragraph, holds at either number.
- Consequences names `ADR-0016`'s Amendment of 2026-09-27 and a dated Note
  on `ADR-0002` pointing here; both are on main. The Amendment is flipped
  to accepted by the same request as this Note.

## Note (2026-09-30): cites that have moved since the flip Note

A dated Note, not an amendment: it carries no `Status:` line and decides
nothing. The sentences it reads stay as written, and so do the cites it
re-locates.

The flip Note above read every decision at `12d3d22`. Several of its cites,
and the matching cites in the record's body, have moved since. Each cite
below was read at `d38dfb9` and is written anchor first, line second; the
lines in brackets are where the flip Note placed it, then, where the body
cites it at another line, the body's. Each anchor still names the thing the
record says.

- `lib/statifier_blocks/core/send.ex`: `def sentence` is at `:219` (`:216`;
  Context `:201`), `@short_form` at `:237` (`:229`) and `def delay_words`
  at `:257` (`:249`; decision 2 `:246`, as `defp delay_words`).
- `lib/statifier_blocks/block_type.ex`: `defmacro __using__` is at `:113`
  (`:112`; `:110`), `optional(:description)` at `:645` (`:633`; `:631`),
  `@callback explain` at `:869` (`:857`), `@optional_callbacks` at `:871`
  (`:859`), with `explain: 0` at `:880`, `@presentation_cap` at `:1540`
  (`:1436`), `def sentence` at `:1770` (`:1666`; `:1645`), `def explain` at
  `:1807` (`:1703`), `defp call_explain` at `:2204` (`:2100`),
  `defp description` at `:2216` (`:2112`) and `defp line` at `:2228`
  (`:2124`).
- `lib/statifier_blocks/palette.ex`: `def call` is at `:607` (`:606`) and
  `def declares?` at `:649` (`:648`); the seventeen `core.*` types
  `core_types/0` lists are at `:222-238` (`:221-237`).
- `lib/statifier_blocks/describe.ex`: `def outline` is at `:219` (`:153`),
  `defp timer_edges` at `:534` (`:437`), `defp timer_party` at `:555`
  (`:456`), `defp timer_edge` at `:565` (`:466`), `defp edge_line`'s timer
  clause, `%Edge{kind: :timer}`, at `:637` (`:534`) and `defp flat` at
  `:719` (`:569`).

These have not moved since `12d3d22`: `def duration?` in
`lib/statifier_blocks/core/duration.ex` (`:81`); `defstruct` and
`@type kind` in `lib/statifier_blocks/describe/edge.ex` (`:58`, `:38`); and
`@callback timer` and `@optional_callbacks` in
`lib/statifier_blocks/describe/phrasing.ex` (`:73`, `:75`).

`delay_words/1` is still `def delay_words` with `@doc false`, as the flip
Note read it.

Filed with `sb-062y`.
