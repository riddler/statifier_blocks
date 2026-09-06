# ADR-0012: A condition that could not be decided is a third slot on `core.branch`, and an unwired one falls to `otherwise`

Status: accepted (2026-09-06, drafted for `sb-qrcn` under the operator's
campaign-033 grant, recording the ruling of 2026-09-06). It merges at proposed
under that campaign's invariant, like every other record filed with it;
flipping it to accepted is a separate request through the same `docs/adr/`
gate, after `sb-2hoh` has built it.

[Note 2026-09-06, `sb-5fa7`: the paragraph above is the record as it was
drafted, and it is left standing rather than rewritten. The status word is
now `accepted`; this is the separate request that sentence points at, and
the Note at the foot of this record carries what the flip verified.]

## Context

`core.branch` is the one shipped type whose control flow is an author's
expression. `slots/1` returns one `arm_*` slot per well-formed arm in config
order followed by `otherwise`
(`lib/statifier_blocks/core/branch.ex:72-79`), `config_schema/1` gives each
arm one `:expression` field keyed by the arm's slot name (`:89-101`), and
`emit/2` compiles the block to a compound state whose initial child is a
transient `pick` state carrying one conditional transition per arm, in config
order, then an unconditional one for `otherwise` (`:247-268`, the shape
ADR-0004 decision 2 names). The author's condition is passed into the
generated `cond` verbatim, with the arm's config key attached so an upstream
expression error routes back to the field the author typed into
(`lib/statifier_blocks/core/emit.ex:142-146`, ADR-0004 decision 9).

**A predicator condition has three readings, and the compiled chart has two
destinations.** The third reading is the one this record is about. In the
resolved dependency, predicator 9.4.0, a comparison with an operand it cannot
compare produces neither `true` nor `false` but the `:undefined` sentinel:
`Predicator.Undefined.value/0` is the sentinel and
`Predicator.Undefined.undefined?/1` the check
(`deps/predicator/lib/predicator/undefined.ex:25-26`, `:42-44`), and the
comparison path returns it in two distinct situations - an `:undefined`
operand under any non-strict operator
(`deps/predicator/lib/predicator/evaluator.ex:786-792`) and a pair of operands
whose types do not match at all (`:828`). An unbound datamodel path is the
first situation, because a `["load", name]` whose name is not in the context
pushes the sentinel unless the evaluator was built with `on_unbound: :error`
(`:325-330`), and the `core.*` vocabulary builds no such evaluator.

[Note 2026-09-06, `sb-5fa7`: true of this package, and not of a chart that
is running. The evaluator a compiled `cond` is evaluated by is the engine's,
and it is built with `on_unbound: :error`, so an unbound *root* is decision
1's erroring case rather than the sentinel. What reaches the new slot is a
missing path under a bound root, or a mixed-type comparison. The Note of
2026-09-06 at the foot of this record carries the four cases and their
cites.]

At the top of an expression that sentinel is reported two ways, on a
distinction that is predicator's and not this package's: a run that executed
an unbound load returns `{:error, %Predicator.Errors.UndefinedVariableError{}}`
naming the variable, and a run that did not - a mixed-type comparison, a
missing nested path under a bound root - returns `{:ok, :undefined}`
(`deps/predicator/lib/predicator.ex:619-625`, building the error at `:669-675`).

**Both shapes reach the same place in the engine, and it is not a third
destination.** `Statifier.Interpreter.Selection`'s `evaluate_cond/2` takes
`{:ok, true}` and `{:ok, false}` as the two answers, turns any other `{:ok,
value}` into `{:error, {:non_boolean_cond, value}}`, and passes an `{:error,
_}` through
(`deps/statifier/lib/statifier/interpreter/selection.ex:316-329`). Its
caller's contract, which the comment at that clause quotes from SCXML 5.9.1,
is one consequence for both: the transition is **not taken** and one
`error.execution` is placed (`:341-347`). So today an undecided condition
behaves exactly as a false one, plus an `error.execution` nobody in the block
vocabulary raised on purpose. A branch whose arms are "amount over the limit"
and "otherwise approve" approves a card whose limit the datamodel never
bound, and the only trace of the difference is an error event.

That is a defensible default and a bad only option. The author who wants
"I could not tell" to be its own path in the document has no way to write it:
there is no expression that asks predicator whether the previous expression
decided, the `otherwise` slot is already spoken for, and adding a `core.branch`
after the first one to re-test the same paths re-runs the same undecidable
comparison. The ruling of 2026-09-06 gives the reading a slot of its own.

## Decision

**1. The undecided reading is the `:undefined` sentinel reaching a `cond`, and
nothing else.** A condition is *undecided* when evaluating it produces
`Predicator.Undefined.value/0` as the expression's value - whichever of the
two shapes above predicator reports it in. A condition that produces a
predicator **error** on its own terms is not undecided, and is never routed to
the new slot: `not 5` is a `TypeMismatchError` before any sentinel exists
(`deps/predicator/lib/predicator/evaluator.ex:875-878`), `x in 5` is one
(`:898-899`), and both keep today's routing - the arm is not taken, an
`error.execution` is placed, and the block falls through. On a branch that
wires the slot such an arm places a second `error.execution` as well, because
the guard of decision 5 evaluates the same source and fails the same way;
decision 7 states that case. The line is drawn
where predicator draws it, so this package does not have to maintain a second
taxonomy of what an expression can fail to do.

**2. `core.branch` gains a third slot, `undecided`, and it is a slot rather
than an outcome.** `slots/1` returns the arm slots in config order, then
`{"otherwise", :any, "Otherwise"}`, then
`{"undecided", :any, "Cannot be decided"}`. A slot declaration is
`{name, arity, label}`, the name being the key under `slots` in the document
(ADR-0002 decision 6, `docs/adr/0002-block-type-behaviour.md:140-144`, whose
key is ADR-0001 decision 5's), and `undecided` is a bare lowercase word in the shape every shipped slot name
already has - `body`, `interrupts`, `otherwise`. It cannot collide with an
arm, because an arm's slot name must match `~r/\Aarm_[a-z][a-z0-9_]*\z/`
(`lib/statifier_blocks/core/config.ex:20`, `:60-61`), and `:any` is the arity
`otherwise` already carries, for the same reason - an empty slot is the
ordinary case.

`outcomes/1` is untouched. `core.branch` does not export it today and does not
gain it here, so the block keeps the single `{"done", "Done"}` outcome every
accepted `core.*` type has (`lib/statifier_blocks/block_type.ex:508-513`).
ADR-0002 amendment A2 is the reason the distinction is worth a sentence: a
slot is not an outcome, `slots/1` says where children live and `outcomes/1`
says how finishing can differ, and "`core.branch` has many slots and one
outcome" is that section's own example
(`docs/adr/0002-block-type-behaviour.md:789-790`). An undecided condition
changes which children run; it does not change how the branch finishes. The
ruling's phrase "a third outcome slot" is read here as the slot it names.

`slot_style` is untouched as well. `core.branch`'s `palette_entry/0` declares
none (`lib/statifier_blocks/core/branch.ex:148-157`), so `otherwise` and
`undecided` both render in the ordinary rail, and the ruling's "renders like
`otherwise` with its own label" is what declaring nothing already produces.
The label is the slot declaration's third element, "Cannot be decided", and it
is the only thing that distinguishes the two in the editor.

**3. An unwired `undecided` slot compiles to today's bytes.** When the slot
holds no children, `emit/2` emits exactly what it emits at 0.20.0: one
conditional transition per arm, then the unconditional `otherwise` transition.
No guard is synthesized, no transition is added, no arm's `cond` is rewritten.
An undecided condition then falls to `otherwise` exactly as it does today,
`error.execution` included. This is the clause that makes the change additive:
every stored document that predates it, and every document whose author does
not want the third path, compiles byte-identically, and ADR-0004 decision 6's
determinism guarantee is not disturbed for any of them.

**4. A wired `undecided` slot adds exactly one transition, and it goes last
among the guarded ones.** When the slot holds at least one child, `emit/2`
emits, in this order:

1. one conditional transition per arm, as today, each carrying the author's
   `cond` verbatim and the arm's `cond_key`;
2. one conditional transition targeting the `undecided` slot's first child;
3. the unconditional `otherwise` transition, as today.

Position 2 is the whole of the addition. Ordering is what makes its guard
simple: transitions in the `pick` state are tried in document order, so by the
time position 2 is reached no arm decided `true`, and "some arm was undecided"
is the only thing left to test.

**5. The guard is composed from the arms' own sources with `===`, and it
carries no `cond_key`.** For the `n` well-formed arms' conditions `c1 .. cn` -
the same arms `slots/1` declared, read through the same filter
(`lib/statifier_blocks/core/branch.ex:294-296`, `:304-314`) - the emitted guard is

```
not ((c1) === false and (c2) === false and ... and (cn) === false)
```

Strict equality is the one comparison predicator answers with a boolean when
handed the sentinel (`deps/predicator/lib/predicator/evaluator.ex:794-796`),
so each conjunct is `true` exactly when that arm decided `false`, and the
negated conjunction is `true` exactly when at least one arm did not. Each
`ci` is the author's source, parenthesized and otherwise untouched.

Two properties fall out of that spelling and are the reason it is preferred to
rewriting each arm's own transition into `(ci) === true`:

- **the arms' transitions keep the author's bytes and the author's spans.**
  ADR-0004's content findings compose a predicator span inside the author's
  config value back into the field the author typed into
  (`docs/adr/0004-compiler-provenance.md:414-435`). A prefix on the author's
  source would offset every one of those spans by the prefix's length, for
  every arm of every wired branch. Nothing here touches them.
- **the guard is the type's composition, not the author's field**, so it is
  emitted with no `cond_key` - `Emit.transition/2`'s own rule, "pass it
  whenever the condition is an author's `:expression` field rather than
  something the type composed" (`lib/statifier_blocks/core/emit.ex:142-146`).
  A parse error in `ci` is the author's typo and surfaces on that arm's own
  transition, which does carry the key; the guard cannot be the only place it
  is reported, because it holds no source the arms do not.

A branch with no well-formed arm emits no guard transition, because there is
no condition that could go undecided; a slot wired on such a branch is
unreachable, which is the advisory named in the deferred list rather than an
emission this record invents.

An arm whose condition *errors* rather than going undecided (decision 1) makes
the guard error too, since the guard evaluates the same source. The guard is
then not taken and the block falls to `otherwise`, which is where that arm
already sent it. An erroring arm therefore never reaches the `undecided` slot,
and this is intended: the slot is for a condition that could not be decided,
not for one that could not be run.

[Note 2026-09-06, `sb-5fa7`: that is the count and the routing when the
guard reaches the erroring arm's source. `and` short-circuits, so an
*undecided* arm earlier in config order makes its own conjunct `false` and
the conjunction stops there: the erroring arm's source is never evaluated
inside the guard, the guard answers `true`, and the block goes to
`undecided` rather than to `otherwise`. The Note at the foot of this record
carries the check.]

**6. An undecided arm does not shadow a later decided one.** Because the guard
sits after every arm's transition, an earlier undecided arm is passed over
when a later arm decides `true`, exactly as it is today, and `undecided` is
reached only when no arm decided `true` at all. Ordering among the arms is
unchanged in every case, wired or not.

**7. The `error.execution` an undecided arm places today is still placed, and
a wired branch with an erroring arm places one more.** For an *undecided* arm
the guard of position 2 evaluates to a boolean, so it places nothing of its
own; the arms' transitions are unchanged, so each undecided arm still places
one `error.execution` before the guard is reached, exactly as at 0.20.0.
Wiring the slot routes the run, it does not silence the event.

An *erroring* arm is the one case where wiring the slot adds an event. The
guard evaluates that arm's source too, so it fails the same way the arm's own
transition did, and `select_transitions/2` places "one `error.execution` per
failed `cond`"
(`deps/statifier/lib/statifier/interpreter/selection.ex:341-347`) - two events
for one arm rather than today's one. Where the run goes is unchanged: neither
the arm nor the guard is taken and the block falls to `otherwise`, exactly as
decision 5 says. A test for this record's behaviour should count events per
*failed cond* rather than per arm.

[Note 2026-09-06, `sb-5fa7`: "two events for one arm" is likewise the count
when the guard reaches that arm's source. An undecided arm earlier in config
order short-circuits the conjunction ahead of it, so the guard places nothing
of its own, the round leaves exactly one `error.execution` - the erroring
arm's own - and the run goes to `undecided`. The Note at the foot of this
record carries the check.]

That is deliberate rather than a debt. Suppressing the event would mean
rewriting the arms' own conditions, which decision 5 declines for the two
reasons given there; and the event carries diagnostic information the slot
does not - which arm, and where in its source. An `error.execution` that no
transition selects on is consumed by the microstep that dequeues it and
changes nothing about where the run goes, so a document that models the
undecided path is routed by the slot and not by the event.

**8. The environment at the `undecided` slot is the branch's inbound
environment.** ADR-0011 decision 4 already says it, for every slot of every
container: "a `core.branch`'s arms, a `core.parallel`'s lanes, and any host
container with more than one slot in the flow each start from the environment
that reached the container"
(`docs/adr/0011-typed-environment.md:258-261`). The `undecided` slot is one of
those arms. It is named here because a reader could reasonably expect
otherwise: the walk *has* just learned something about the document - that an
arm's condition could not be decided - and the temptation is to spell that as
a type. It is not spelled as a type. A condition that did not decide says
nothing about what any path holds; a path is unbound at compile time or it is
not, and the environment already answers that question the same way for every
arm. The slot's environment leaves the container through decision 4's per-path
merge like every other arm's, with nothing added and nothing removed. ADR-0011
carries a dated Note pointing here.

**9. Nothing about the config changes.** The `undecided` slot is not a field:
`config_schema/1` and `validate_config/1` are untouched, no key is added to
`config`, and a document wires the slot by putting children in it, the same
gesture that fills `otherwise`. Where a finding names the slot it names it by
its slot name, `undecided`, exactly as findings name `otherwise` today.

`summary/1` names the slot only when it is wired: `"1 arm + otherwise"` for
every branch that predates this record, and `"1 arm + otherwise + undecided"`
for one that wires it. ADR-0002 amendment H names `otherwise`
rather than counting it "because it is always there"
(`docs/adr/0002-block-type-behaviour.md:1893-1894`), and the type's own
moduledoc gives the reason in full - `slots/1` "appends it to every branch,
including one with no arms at all, and a card reading `1 arm` would be
under-reporting the paths out of the block by one"
(`lib/statifier_blocks/core/branch.ex:164-167`). An unwired `undecided` slot
is not a path out of the block, since decision 3 sends it to `otherwise`, so
naming it would over-report by one instead.

[Note 2026-09-06, `sb-5fa7`: the `summary/1` clause of this decision - the
`"1 arm + otherwise + undecided"` card for a branch that wires the slot - is
**withdrawn** by the operator's ruling of 2026-09-06 under the campaign-033
grant. The callback cannot answer it: `@callback summary(Block.config())` is
handed the config alone (`lib/statifier_blocks/block_type.ex:609`), and
whether a slot holds children is a fact about the block rather than about its
config, so the clause would need the callback widened - surface no record has
asked for. The card therefore reads `N arms + otherwise` for every branch,
wired or not, exactly as it did at 0.20.0, and `core.branch`'s own
`summary/1` doc says so. Nothing else in decision 9 moves.]

## Consequences

**The change is additive and the release is a minor one.** A stored document
compiles to the same bytes unless it wires the new slot (decision 3), no
config key is added or removed (decision 9), no callback changes shape, and no
other block type is touched. `statifier_blocks` 0.21.0 carries it.

**A wired branch evaluates each arm's condition twice per pass through the
`pick` state** - once on the arm's own transition, once inside the guard. That
is safe because a `cond` is a read: the compiled chart puts author expressions
in `cond` attributes only, and predicator's comparison path has no effect
beyond its value. It is not free, and it is proportional to the number of arms
rather than to anything the author can see, so a branch with many arms and a
wired slot does measurably more work per pass than one without. Nothing in the
vocabulary is nearer to free, short of an engine-level "why did this cond not
decide" the interpreter does not expose.

**A guard trace sees the arms twice too.** `select_transitions/2` returns a
round's guard trace, `[]` unless a written `cond` was evaluated under `trace:
true` (`deps/statifier/lib/statifier/interpreter/selection.ex:341-347`). A
wired branch contributes the arms' entries plus one composed entry with no
config key. A consumer that reads the trace as a list of author-written
conditions will see one entry that is not one; the missing `cond_key` is what
distinguishes it.

**The editor gains a slot on a type most documents use.** Every `core.branch`
card renders one more drop target once this is built. The label carries the
whole of the explanation, which is why decision 2 fixes it rather than leaving
it to the editor: "Cannot be decided" says what the slot is for without
requiring the author to have read this record.

**Two of predicator's distinctions stay invisible here, deliberately.** Which
of the two report shapes an undecided condition took (Context), and which
variable was unbound, are both available to a host through
`Predicator.Evaluator.unbound_loads/1`
(`deps/predicator/lib/predicator/evaluator.ex:162-165`) and through the
`error.execution` decision 7 leaves standing. The slot answers "was it
decided", one bit, because that is the question the document can branch on.

**This record does not adopt predicator's word.** Predicator's sentinel is
`:undefined` and its evaluator option is `on_unbound: :undefined | :error`;
the slot is `undecided`. The names differ because the subjects differ: the
sentinel is a value a variable can hold, and the slot is a reading of a
condition. A future predicator that spells the sentinel differently changes
decision 1's citation and nothing else in this record.

## The contract as typespecs

Nothing in `StatifierBlocks.BlockType`'s contract changes. The declaration
below is `slots/1`'s existing return type - `@callback slots(Block.config())
:: [slot_decl()]` with `@type slot_decl :: {Block.slot_name(), slot_arity(),
String.t()}` (`lib/statifier_blocks/block_type.ex:144`, `:249`) - shown with
the third entry `core.branch` returns:

```elixir
@impl true
def slots(config) do
  arm_slots =
    Enum.map(arms(config), fn %{"slot" => slot} -> {slot, :at_least_one, arm_label(slot)} end)

  arm_slots ++ [{"otherwise", :any, "Otherwise"}, {"undecided", :any, "Cannot be decided"}]
end
```

`emit/2` keeps its signature, `@spec emit(Block.t(), Context.t()) :: {:ok,
Emission.t()} | {:error, [finding]}`, and gains one branch in its body: the
guard transition of decision 5, emitted only when
`Context.children(context, "undecided")` is non-empty.

## Worked shape: an authorization whose limit the datamodel never bound

A card-processing document. The entry block writes `cards.credit_txn`, and a
branch decides whether the amount clears the account's limit:

```
core.branch
  arms: [%{"slot" => "arm_over_limit",
           "cond" => "cards.credit_txn.amount > accounts.current.limit"}]
  arm_over_limit: [myapp:decline]
  otherwise:      [myapp:authorize]
  undecided:      [myapp:manual_review]
```

`accounts.current.limit` is a path the document declares and a run may leave
unbound - the account lookup is an earlier `myapp:*` invoke that can answer
without it. Three runs, one document:

| The datamodel at the branch | The condition | Where the run goes |
|---|---|---|
| `amount` 120, `limit` 100 | `true` | `arm_over_limit` -> `myapp:decline` |
| `amount` 120, `limit` 500 | `false` | `otherwise` -> `myapp:authorize` |
| `amount` 120, `limit` unbound | undecided | `undecided` -> `myapp:manual_review` |

The third row is the whole of the change. At 0.20.0 it reads
`otherwise -> myapp:authorize`: the card is approved because the limit was
missing, which is the outcome nobody wrote down and nobody wanted. The same
document with the `undecided` slot left empty still reads that way, by
decision 3.

The emitted `pick` state for the wired document, with the guard of decision 5:

```xml
<state id="s_BR" initial="s_BR__pick">
  <state id="s_BR__pick">
    <transition cond="cards.credit_txn.amount &gt; accounts.current.limit"
                target="s_blk_DECLINE"/>
    <transition cond="not ((cards.credit_txn.amount &gt; accounts.current.limit) === false)"
                target="s_blk_REVIEW"/>
    <transition target="s_blk_AUTHORIZE"/>
  </state>
  ...
</state>
```

With one arm the guard's conjunction has one conjunct, which is the shape
above; with three arms it has three. The first transition still carries the
arm's `cond_key`, `"arm_over_limit"`; the second carries none.

## What this record owes ADR-0002 when it is accepted

Three lines in ADR-0002 describe `core.branch`'s slots and card as they are
without this record, and each becomes wrong when `sb-2hoh` has built it:

- decision 10's vocabulary row, "one `arm_*` per declared arm, then
  `{"otherwise", :any, ...}`"
  (`docs/adr/0002-block-type-behaviour.md:341`);
- amendment H's summary row, "`N arms + otherwise`"
  (`docs/adr/0002-block-type-behaviour.md:1883`);
- the Note of 2026-09-06's environment table row, "one arm slot per declared
  arm, then `otherwise`, merged per path"
  (`docs/adr/0002-block-type-behaviour.md:3528`).

They are not edited here. This record is proposed, and a proposed record does
not reach into an accepted one; the three rows are named so that the amendment
carrying them is a known piece of work and not a discovery. ADR-0011's Note is
the one exception, and it is not an amendment: it says that decision 4 already
covers the new slot, which is true whether or not this record is accepted.

[Note 2026-09-06, `sb-5fa7`: this section names its own status too, and the
flip falsifies the sentence. The record is now accepted and `sb-2hoh` has
built it, so the debt this section describes is due rather than anticipated -
and it is one row shorter than it reads. Decision 10's vocabulary row and the
environment table row are both stale, because `slots/1` now returns
`undecided` after `otherwise`. Amendment H's summary row is not: decision 9's
`summary/1` clause is withdrawn by the Note above, so `N arms + otherwise`
stays exactly right. Carrying the two stale rows into ADR-0002 is a separate
amendment through the same gate, and it is not done here - this flip edits no
record but its own.]

## Deferred questions, named rather than guessed

- **Is a wired `undecided` slot on a branch with no arms worth a finding?**
  Such a branch has no condition to be undecided, so the slot is unreachable
  and its children are dead. That is an ADR-0005 findings-layer advisory, at
  `:info`, and it has the same shape as several already deferred there. No
  finding is decided here.
- **Should `otherwise` and `undecided` be distinguishable by `slot_style`?**
  Decision 2 declares none, which is what "renders like `otherwise`" asks for.
  If the editor later wants the pair drawn apart, the key already exists
  (`lib/statifier_blocks/block_type.ex:491-493`) and adding it is ADR-0005's
  call, not this record's.
- **Does any other type want the reading?** `core.on_event`'s optional `cond`
  (ADR-0002's Note of 2026-08-31) can go undecided in exactly the same way,
  and there the consequence is that the handler does not fire. Whether an
  interrupt handler wants a third path is a different question with a
  different shape - a rail, not a slot - and it has no consumer today.

## Note (2026-09-06): the engine evaluates a chart's `cond` with `on_unbound: :error`, so an unbound root is decision 1's erroring case

A dated Note rather than an amendment, and it edits nothing above this line.
It decides nothing: decision 1 already draws the line at "the `:undefined`
sentinel reaching a `cond`, and nothing else", and this Note records which
situations reach that line once the chart is running inside
`Statifier`. It is written now because `sb-2hoh` built the slot and drove it,
and one sentence of the Context reads differently against what the runs
actually do.

The Context says an unbound datamodel path is the first of predicator's two
sentinel situations, "unless the evaluator was built with `on_unbound:
:error` ... and the `core.*` vocabulary builds no such evaluator". That is
true of this package: nothing under `lib/statifier_blocks/` builds a
predicator evaluator at all. The evaluator that runs a compiled chart is the
engine's, and it does build one that way:
`Statifier.Evaluator.context/1` carries "the resolved `functions` map and
`on_unbound: :error`" (`deps/statifier/lib/statifier/evaluator.ex:90`,
`:150`). Under that policy a `["load", name]` whose name is not in the
datamodel is an error rather than the sentinel, whatever the surrounding
expression would have made of it.

So the two situations the Context names are reached from a chart like this,
and only the second of them routes to the new slot:

| At the branch | What the arm's `cond` answers | Where the run goes |
|---|---|---|
| `accounts.current.limit` bound | `true` or `false` | the arm, or `otherwise` |
| `accounts.current` bound and holding no `limit` | `{:ok, :undefined}` - a missing path under a bound root | `undecided`, when the slot is wired |
| the operands' types do not match | `{:ok, :undefined}` - a mixed-type comparison | `undecided`, when the slot is wired |
| `accounts` itself unbound | the engine's `on_unbound: :error` makes it an error | `otherwise`, wired or not |

The fourth row is decision 5's own erroring-arm paragraph reached by a second
route: the guard evaluates the arm's source, the unbound load errors there
too, neither transition is taken, and the block falls to `otherwise` - which
is where that arm already sent it. Two `error.execution` events rather than
one, exactly as decision 7 describes for an arm that errors.

The worked shape above is unaffected in the form it is written. Its prose has
`accounts.current` bound - "the account lookup is an earlier `myapp:*` invoke
that can answer without it" - and its third row is the second row of the table
here. What the shape does not cover, and this Note now says plainly, is a
document whose branch reads a root the run never bound at all: that document
gets today's routing and the `undecided` slot never sees it.

Whether the engine should distinguish the two is not this record's call. It is
`Statifier`'s evaluator policy, in the repository that owns the interpreter
contract, and it is named here rather than worked around: this package
composes the guard from the author's own source and cannot ask predicator a
question the engine's context does not permit.

## Note (2026-09-06): what the flip verified, the short-circuit the erroring-arm paragraphs did not name, and the cites that drifted

A dated note rather than an amendment, and it edits nothing above this line.
No decision moves and no clause gains or loses a member, with one exception
the operator ruled on and decision 9's own inline Note records: the
`summary/1` clause is withdrawn. What this section carries is the check the
flip from proposed to accepted ran - every claim read against `main` as it
stands at `25be58d`, after `sb-2hoh` built the slot - and the three places
where a reader of the record and a reader of the code would otherwise come
away with different answers.

### What the flip read, and what holds

Decisions 1 through 8 hold as written and are now built rather than
promised. `slots/1` returns the arm slots, then `{"otherwise", :any,
"Otherwise"}`, then `{"undecided", :any, "Cannot be decided"}` (decision 2),
`outcomes/1` is still not exported by the type and `palette_entry/0` still
declares no `slot_style`, so the two slots render alike in the ordinary rail
and the label is what distinguishes them. `emit/2` appends the guard branch
between the arms and `otherwise` (decision 4) and emits nothing at all when
the slot holds no children (decision 3); the guard is spelled
`not ((c1) === false and ... and (cn) === false)`, carries no `cond_key`,
and rewrites no arm (decision 5). `config_schema/1` and `validate_config/1`
are untouched (decision 9's first half). The environment at the slot needed
no code of its own: the walk reads the declared slots generically, which is
decision 8's "ADR-0011 decision 4 already says it" holding literally.

Every citation into the two predicator modules, the engine's
`Statifier.Interpreter.Selection` and `Statifier.Evaluator`,
`lib/statifier_blocks/core/config.ex`, `lib/statifier_blocks/core/emit.ex`
and the four sibling records still resolves to the text it is quoted for.
The citations into `lib/statifier_blocks/core/branch.ex` and
`lib/statifier_blocks/block_type.ex` have moved, and the tables below carry
them.

### The erroring arm behind an undecided one

Decision 5's closing paragraph says an arm whose condition errors "makes the
guard error too, since the guard evaluates the same source", and decision 7
counts two `error.execution` events for such an arm on a wired branch. Both
are true when the guard reaches that arm's source, and the guard does not
always reach it. `and` short-circuits: it compiles to a jump that leaves a
falsy left operand in place and skips the right operand entirely
(`deps/predicator/lib/predicator/evaluator.ex:1711-1714`, the `false` /
`:undefined` / `nil` clause of `execute_jump_if_falsy_or_pop/2`). An
undecided arm's conjunct `(ci) === false` is `false`, by decision 5's own
strict-equality reading, so a conjunction whose *first* undecided arm sits
ahead of an erroring one stops before the erroring arm's source is reached.

Driven against the resolved predicator, with `a` bound to a map so that
`a > 5` is the mixed-type comparison of the Context and `not 5` is decision
1's `TypeMismatchError`:

| The guard | What predicator answers | Where the run goes |
|---|---|---|
| `not ((a > 5) === false and (not 5) === false)` | `{:ok, true}` | `undecided`, one `error.execution` - the erroring arm's own |
| `not ((not 5) === false and (a > 5) === false)` | `{:error, TypeMismatchError}` | `otherwise`, two `error.execution` - as decision 7 describes |

So the two paragraphs describe the second row, which is the case they were
written for; the first row is the case config order can also produce, and it
routes to the slot. Nothing about either paragraph's reasoning changes -
the guard still evaluates the arms' own sources, still places no event of
its own for an undecided arm, and still rewrites nothing.

### One narrowing the code makes that decision 5 does not name

Decision 5 composes the guard from "the `n` well-formed arms' conditions",
read through the filter `slots/1` reads arms through. The code reads through
that filter and then narrows once more, to the arms whose `cond` is a
non-empty string. The narrowing is forced rather than chosen: an arm with a
blank or missing `cond` is one `validate_config/1` reports and `slots/1` may
not raise on, it compiles to an *unconditional* transition ahead of the
guard - which makes the guard unreachable for that document anyway - and
splicing its empty source into the conjunction would emit `(() === false)`
and fail the whole document's upstream compile. The record's own sentence
"a branch with no well-formed arm emits no guard transition" is therefore
read as "no arm carrying a condition that could go undecided", which is the
same set for every document that compiles.

### The `branch.ex` and `block_type.ex` cites, and what they read today

The file grew by about 118 lines when `sb-2hoh` built the slot, so every
citation into it names a range that has moved. Nothing the citations support
changes; only the numbers went stale. The form is the one ADR-0002's Note of
2026-09-06 uses for the same problem: say what the record cites, say what is
true now, and add rather than rewrite. Read at `25be58d`, `def`/`defp` line
through `end` line:

| What the record cites | The claim it carries | On `main` today |
|---|---|---|
| `:72-79` | `slots/1` returns the arm slots then `otherwise` (Context) | `lib/statifier_blocks/core/branch.ex:100-105`, now returning `undecided` after them |
| `:89-101` | `config_schema/1`'s per-arm `:expression` field (Context) | `:117-128` |
| `:148-157` | `palette_entry/0` declares no `slot_style` (decision 2) | `:176-185` |
| `:164-167` | why the card names `otherwise` rather than counting it (decision 9) | `:192-195`, in `summary/1`'s own `@doc` |
| `:247-268` | `emit/2`'s `pick` state (Context) | `:319-342`, now with the guard branch |
| `:294-296` | `arms/1`, the filter the guard reads through (decision 5) | `:412-414` |
| `:304-314` | `indexed_arms/1`, that filter's own body (decision 5) | `:422-432` |

`lib/statifier_blocks/block_type.ex` moved for a different reason - the
failure-outcome callback `sb-napt` added to it, three lines ahead of the
first of these cites and thirty-six ahead of the last:

| What the record cites | The claim it carries | On `main` today |
|---|---|---|
| `:144` | `@type slot_decl` (the typespec section) | `lib/statifier_blocks/block_type.ex:147` |
| `:249` | `@callback slots(Block.config())` (the typespec section) | `:252` |
| `:491-493` | the `slot_style` key, if the pair is ever drawn apart (deferred questions) | `:494-496` |
| `:508-513` | a type that exports no `outcomes/1` has one `done` outcome (decision 2) | `:511-516`, with the callback at `:537` |

A reader following any of these should search for the function rather than
the line: the beads that build a record move it, and this record's argument
does not rest on a line number.
