defmodule StatifierBlocks.Core.OnEvent do
  @moduledoc """
  `core.on_event`: an interrupt handler, valid inside an `interrupts` slot
  and nowhere else (ADR-0002 decision 10).

  A leaf with five config fields: the `event` that fires it, an optional
  `cond` that decides whether it fires at all, the `outcome` that decides
  what happens to the group it interrupts, an optional `capture` that
  writes values out of the firing event's payload into the datamodel
  before the outcome is raised, and an optional `payload` that declares
  what that event carries - which is what makes a `capture` reading past
  it a refusal at compile rather than an unbound marker at run time.

  ## Placement, in both directions, from one tag

  This type declares `kinds: [:interrupt_handler]` and nothing else. That
  single tag is the whole placement rule:

    * an `on_event` dropped into a `body` slot fails, because `body`
      declares `[:step]` and the two sets do not intersect;
    * an ordinary step dropped into `interrupts` fails, because
      `interrupts` declares `[:interrupt_handler]` and a step is not one.

  ADR-0002 decision 10 originally recorded the first direction as a
  special-cased validation rule the core types carry, and **withdrew it at
  acceptance** in favour of ADR-0003 decision 3's kind tags, which close
  both directions with one declaration on each side. There is no placement
  check in this module, and there is not supposed to be one: adding it back
  would give the editor two code paths to highlight from.

  This type also never names the group types it may live inside. A host
  group with an `interrupts` slot admits it by declaring
  `"interrupts" => [:interrupt_handler]`, and a host with a genuinely
  different notion of interrupt handler mints its own kind and its own
  group without touching this package.

  ## Candidates for `event`

  `event` is a plain `:string` and this type validates it the way it always
  has - the event-name shape rule, and nothing else. What the editor adds is
  a list of *suggestions*: the completion events the blocks in the handler's
  enclosing body raise, each written as the
  `done.outcome.<state id>.<outcome>` name
  `StatifierBlocks.Compiler.StateId.outcome_event/2` mints, and labelled by
  the block's own card label and that outcome. Wiring a handler onto a
  sibling's outcome is then a pick rather than a transcription of a generated
  name.

  Three properties of the list are this record's, not the control's.

    * **The body is read through the declaration.** "The enclosing body" is
      every slot of the enclosing block that admits ADR-0003's `:step` kind,
      which is `body` on `core.group` and `core.resumable_group` and whatever
      a host group calls the slot it declares the same way. The handler's own
      `interrupts` slot declares `[:interrupt_handler]`, so it is excluded by
      construction rather than by name.
    * **Only a type that declares outcomes contributes.** ADR-0002 amendment
      A1 gives a type that implements no `outcomes/1` a single default
      `done`, and offering an author a generated name for an outcome a type
      never declared would be offering them a wire that is not there.
    * **`config_schema/1` is untouched.** The field declaration gains no
      candidate key; the derivation is the editor's and is keyed on this
      type. `core.send`, `core.raise` and `core.await` each declare an
      `event` key too, and each names events this list is not about.

  ## The `outcome` values

  ADR-0002 decision 10 fixes `outcome` as a `:select` and names no values.
  Two are implemented:

  | `outcome` | Means |
  |---|---|
  | `"abandon"` | leave the group and do not come back |
  | `"resume"` | handle the event and re-enter the group |

  They are the minimal pair ADR-0001 decision 10's compile target needs -
  transitions on the group's state, with the group's own history mode
  deciding where a `"resume"` re-enters. A third value is a
  `config_schema/1` change plus a `current_version/0` bump, not a document
  schema change.

  ## Naming the outcome this handler finishes with

  `finish_as` is an optional free-text field beside the `outcome` select,
  and it says *what this handler's own completion is called* when it
  abandons its group. The two keys answer different questions: `outcome`
  says what the arrival does to the group, `finish_as` names the
  completion this handler reaches, and the select above keeps exactly its
  two values.

  | `finish_as` | This handler finishes as |
  |---|---|
  | blank, or absent | `done`, exactly as it always has |
  | a role-shaped name | that name |

  Named, `outcomes/1` answers `[{name, name}]` - the name is its own
  label, because the author's words for a button live on the button and
  not on the watcher - and `emit/2` mints the handler's final at its
  outcome id, so the final raises `done.outcome.<handler state>.<name>`.
  That is the event an enclosing declaring composite routes on, which is
  what lets a composite declare an outcome one of its interrupt handlers
  reaches. The abandon raise on the watcher's transition is unchanged and
  still comes first, so the group is abandoned and only then is the named
  completion routed.

  A name is honoured with `outcome: "abandon"` only, must be role-shaped,
  and may not be `done`; each is a `validate_config/1` finding on the key.

  Blank or absent, every emitted byte is the byte that was emitted before
  this key existed - which is what keeps it an additive key rather than a
  document schema change, exactly as `cond` below and `capture` are. See
  ADR-0002's Amendment of 2026-09-14, `C8`.

  ## The optional `cond` guard

  `cond` is an optional `:expression` field, and when it is set it becomes
  the `cond` on the watcher's transition: the handler fires only when the
  event arrives **and** the condition holds. A handler with no `cond` -
  the key absent, or blank - emits exactly the bytes it emitted before the
  key existed, which is what keeps it an additive key rather than a
  document schema change.

  The guard belongs here rather than on a `core.branch` after the handler,
  which is the shape it would otherwise be spelled as. A `core.on_event`
  decides whether to leave the in-flight body at all, and by the time a
  branch inside the handler could read a condition the body has already
  been abandoned - so the two spellings do not express the same thing, and
  only this one expresses a guarded interrupt. See ADR-0002's 2026-08-31
  note.

  The condition is the author's bytes passed through into predicator's
  datamodel verbatim. This package ships no expression checking of its own
  (ADR-0004 decision 9), so `validate_config/1` only asks whether the
  stored value is a string; a typo inside it surfaces as an upstream
  compile error routed back to the `"cond"` field by the `cond_key` this
  type passes to `StatifierBlocks.Core.Emit.transition/2`.

  Unlike `core.branch`, this type declares no `value_path`: its condition
  is stored at `config["cond"]`, so ADR-0002 decision 7's default path -
  `[key]` - already addresses it. And `summary/1` is untouched. ADR-0002
  amendment H6 fixes this type's card as the outcome word then the event
  name, and the reason `core.branch` counts its arms rather than listing
  their conditions holds here too: an expression is not a chip.

  ## The optional `capture` map

  `capture` writes values into the datamodel on the transition this
  handler emits. It is a map, and the direction is worth stating twice
  because a path-to-path map reads either way: **the key is the
  destination** - a datamodel path - and **the value is the source**. A
  `capture` of `%{"order.cancel_reason" => "reason"}` on a handler for
  `order.cancelled` writes that event's `reason` into
  `order.cancel_reason`.

  A source takes either of two forms, and they are told apart by
  **shape**, never by content (ADR-0002's Note of 2026-09-12, `N1`):

    * a **string** is a path inside `_event.data`, which is what a source
      has always been and means exactly what it has always meant. No
      string is reinterpreted as a literal because of what it happens to
      spell;
    * a **two-element array tagged `"const"`** - `["const", value]` in the
      stored document, `{"const", value}` as this module reads it - is the
      literal `value`, read from the document rather than from the
      payload. `value` is taken as it stands: it is not parsed, not
      evaluated, and not resolved against the datamodel.

  The literal form is what lets two handlers on one screen record which of
  them fired - each writes its own value - rather than depending on the
  host to put different values in the payload, a contract neither document
  states.

  From `0.28.0` on, a pair whose source is a **path the firing payload
  does not carry writes nothing at all** (ADR-0002's Note of 2026-09-12,
  `N2`): the destination is left as it was - absent if nothing wrote it
  before, and carrying its previous value if something did. So a reader
  tests a captured destination the way it tests any other datamodel path,
  by asking whether it is there, and a guard on a path a screen never
  wrote reads an absence rather than a value. A payload that carries the
  source with a JSON `null` still writes: "not answered" and "answered
  with nothing" are different values, which is the whole of what the
  clause decides. There is no per-pair opt-in to the old behaviour. A
  literal source has no path to be absent and always writes.

  A literal is emitted as a predicator literal expression: a string
  double-quoted with `\\` and `"` escaped, an integer as its digits, a
  negative integer behind the `-` predicator reads as a unary minus,
  `true` / `false` / `null` as themselves, an array as `[a,b]` and an
  object as `{"k":v}` with its keys in sorted order. A value this module
  cannot spell so that the engine reads back what the document carried is
  a **malformed pair** - `validate_config/1` refuses it on the `capture`
  key like any other. What is refused is very nearly a matter of TYPE
  alone: a float never arises, because a block document may not carry one
  at all, and a string is admitted whatever it carries with one exception.
  A **raw C0 control character** other than tab, line feed and carriage
  return is refused on the `capture` key (ADR-0002's line of 2026-09-13):
  a literal's characters reach an XML attribute value raw, and XML 1.0
  admits no control character below `U+0020` there. The three that are
  admitted are the three `escape/1` already writes as predicator string
  escapes rather than raw.

  The one restriction beyond type this key used to carry - a string had
  to stay inside printable ASCII, tab, newline and carriage return - was
  **interim** and ended on 2026-09-13 (ADR-0002's Note of that date). It
  was earned only while predicator 9.4.0's string lexer wrote a literal's
  codepoints back a byte at a time; 9.4.1 fixed that lexer, `mix.exs`
  requires `~> 9.4.1`, and a positive round trip over a non-ASCII literal
  in the suite is what says the resolved version is one that reads a
  string back whole.

  One `<assign>` is emitted per pair, on the transition the handler
  already emits and **before** the `<raise>` that carries the outcome.
  The pairs are emitted in their datamodel paths' sorted order: a map has
  no order of its own and a compile has to be deterministic, so the
  record fixes one rather than leaving the bytes to a map's iteration.
  A handler whose `capture` is absent or empty writes no `<assign>` at
  all, which keeps the key additive in exactly the way `cond` is.

  The assigns belong on the transition, and before the raise, for the
  reason the guard belongs here: the `<raise>` is what tells the
  enclosing group to abandon or resume, and by the time control is
  anywhere else that has happened - on `abandon` the body is gone, on
  `resume` the body is re-entered and history decides where. `_event.data`
  is in scope only for the transition the event selected, so a
  `core.assign` placed after the handler is a separate microstep with a
  different `_event` and the payload is not merely awkward to reach
  there, it is gone. See ADR-0002's 2026-09-05 note.

  A captured value that quietly is not there is the failure this key has
  to avoid, because everything downstream would read it as an authored
  absence. What the interpreter does about that splits on whether the
  expression's **root** is bound, not on whether the whole path resolves:

    * `_event` is always bound, so a `capture` whose source path is not in
      the payload writes the interpreter's explicit **unbound marker** and
      raises nothing. The marker is not `nil` and is not `nil`'s spelling -
      unbound and null are deliberately different values there - so the
      absence is one a reader can test for rather than a silent hole. A
      consumer of a captured path has to make that test; that obligation is
      the whole of what this key promises today.
    * A wholly unbound root raises `error.execution` and writes nothing.
      That is predicator's `on_unbound: :error` policy reaching
      `Statifier.Interpreter.Content`'s one raise site, and no `capture`
      compiles to such an expression.

  [Note 2026-09-05, sb-0q0z: this paragraph read "an `<assign>` whose
  `expr` does not resolve is an execution error", following ADR-0002's
  capture Note, which was written ahead of the measurement. Measured on
  two engine versions, the error is raised for an unbound root only, never
  for a missing member of a bound one. ADR-0002 carries the correction and
  the cites; the error arriving for this shape too is upstream work, and
  nothing here may be built on it until that lands.]

  The compile-time half is the optional `payload` declaration below, and
  it is what the paragraph above stops being the whole story for: on a
  document that declares its payload the marker write never happens,
  because the document does not compile.

  ## The optional `payload` declaration

  `payload` declares what `_event.data` carries **for the event this
  handler names** (ADR-0002's amendment of 2026-09-06, P1). It is not a
  fact about the event name anywhere else in the document and it is not
  the datamodel, which the `:declare` and `:datamodel` compile options
  already own: two handlers for the same event may declare different
  payloads and neither is thereby wrong, because each governs its own
  `capture`.

  P2 of that amendment names **two** arms, and both are spelled today.
  The value is either the **name of a type the datamodel document
  declares** - a `record` or a `shape` in its `types` key, read through
  `StatifierDatamodel.Declarations` - or an **inline shape** written where
  the payload is declared, a list of members read through
  `StatifierBlocks.Environment.inline_shape/1`. The field type is
  `{:type_expr, opts}`, the ninth member of ADR-0002 decision 7's set that
  its amendment of 2026-09-06 added and whose clause 7 migrated this field
  onto: P3 deferred the second arm rather than refusing it, and the two
  arms are told apart by the stored JSON type alone, a string never being
  a member list. A `payload` stored as text before that date is the name
  arm, unchanged in every particular - the same bytes, the same
  resolution, the same findings.

  `payload` is a **declaration, not an emission**. Nothing about it
  reaches the compiled SCXML: a handler that gains one compiles to the
  bytes it compiled to without it, and a handler that has none is
  unchanged in every respect - no new finding of any kind, at any
  severity. A `payload` naming a type the datamodel does not declare, and
  a compile with no `:datamodel` at all, are that same unchanged case
  reached by a second route (P4): the name resolves to nothing, and
  nothing is refused against nothing.

  ## The refusal `payload` buys: `payload_capture_findings/2`

  With a payload declared, a `capture` pair whose **source** path reads a
  member the payload does not carry is a `:config` refusal at compile
  (P5). The other reading - a declared member no pair reads - is not a
  finding: a payload may legitimately carry more than one handler wants.

  P5 is a rule about a source **path**, so a literal pair is not reached
  by it at all: a `["const", value]` source has no path to read past the
  payload, and `unread_pairs/3` walks only the pairs whose source is a
  path. Nothing about that refusal changes, and a handler may declare a
  payload and capture a literal beside a path from it.

  The check needs the datamodel document, which `validate_config/1` does
  not get, so it is a function of its own that the compiler's config stage
  calls with the declarations it has already indexed. One finding is
  reported for the whole `capture` key rather than one per pair, for the
  same reason `check_capture/2` gives: the key is the only anchor an
  editor can use. The message names the offending pairs and the declared
  payload, because the anchor cannot.

  How deep it goes is P5's rule, kept literally. The **first** segment of
  a source path is checked against the payload's field names. A deeper
  segment is checked only where the field's own type resolves, through the
  same declarations, to a declaration whose fields are in hand; a field
  whose type is a scalar, an opaque string, a list or `:unknown` **stops
  the walk and refuses nothing beyond it**. That adds no structural rule
  `statifier_datamodel` does not already have - its read check is nominal,
  permissive on the unknown, and descends into no list's element type.

  An **inline** payload is checked by that same rule against the members
  it writes, and P5 gains nothing else from the second arm: the first
  segment is checked against the member names, a member typed by a
  declared name descends into that declaration, a member whose own type is
  another inline shape descends into its members, and every other member
  type stops the walk. What the two arms share is that the check needs a
  set of member names in hand and refuses only a read that is not in it -
  the arms differ in where those names come from and in nothing else. An
  inline payload writing no well-formed member carries no member, so every
  read is a read past it, which is what a payload naming a declaration
  with no fields already does.

  The destination side of a pair is untouched by all of this:
  `StatifierBlocks.Environment.capture_writes/1` still writes `:unknown`
  there. This types the source side at compile, and typing the
  destination from the payload is a widening of ADR-0011 that no ruling
  has asked for.

  `config_schema/1` declares **no field** for `capture`. ADR-0002
  decision 7's field-type set has no member that describes a map, the
  2026-09-05 note declines to add one, and how an author writes the pairs
  is ADR-0005's question rather than this module's. So the key is
  authored through the document today and not through the editor, and the
  two `<assign>` attributes carry no config attribution for the same
  reason `core.subchart`'s composed conditions carry none: `expr` is
  composed here rather than the author's bytes verbatim, and `location`
  has no declared field for a finding to land on.
  """

  @behaviour StatifierBlocks.BlockType

  alias StatifierBlocks.Block
  alias StatifierBlocks.Compiler.{Context, StateId}
  alias StatifierBlocks.Core.{Config, Emit}
  alias StatifierBlocks.{Emission, Environment}
  alias StatifierDatamodel.Declarations

  @outcomes ["abandon", "resume"]

  # The one spelling of the optional name a handler finishes with
  # (ADR-0002's Amendment of 2026-09-14, `C8`). It is spelled `finish_as`
  # and not `outcome_name` because `StatifierBlocks.BlockType` already has
  # a public `outcome_name/2` with a neighbouring meaning - it reads an
  # outcome name out of a config at whatever key a container nominates,
  # while this is one type's own field.
  #
  # The key is OPTIONAL with a blank default, and a handler that carries
  # none emits exactly the bytes it emitted before the key existed, which
  # is what keeps it an additive key rather than a document schema change
  # and why `current_version/0` stays 1. `cond` below records the same
  # precedent for the same reason, and `capture` is the same shape.
  @finish_as_key "finish_as"

  # The name the default outcome carries, which `outcomes/1` answers for a
  # handler with no `finish_as` - ADR-0002 A1's default, byte for byte -
  # and which a named handler may therefore not ask for.
  @default_outcome "done"

  # The one spelling of the key, shared by the map's own validation and by
  # the payload refusal that reads the same pairs.
  @capture_key "capture"

  # The tag of a literal capture source (ADR-0002's Note of 2026-09-12,
  # N1). In the stored document the form is the two-element JSON array
  # `["const", value]`; `{"const", value}` is that array as this package
  # reads it, and ADR-0001 owns the bytes.
  @const_tag "const"

  # How an inline payload is named in a message. It has no name of its
  # own - that is what makes it inline - so the message describes it.
  @inline_subject "the inline payload"

  # A path's shape, in both directions of a `capture` pair: non-empty and
  # carrying no whitespace, and deliberately NOT a dotted-identifier
  # grammar. `core.assign` reads the destination side with exactly this
  # rule and for exactly its reason - this package does not own the
  # datamodel path grammar, and a regex here that accepted `review.parked`
  # and refused something a host's datamodel legitimately declares would
  # be a second, quieter proposal riding along with this one. The source
  # side is a path inside `_event.data`, which this package owns no more
  # of than it owns the other.
  #
  # Any whitespace, not just the space/tab/newline trio: a carriage
  # return or a vertical tab is whitespace too.
  @whitespace ~r/\s/

  @impl true
  def current_version, do: 1

  @impl true
  def slots(_config), do: []

  @impl true
  def config_schema(_config),
    do: [
      %{
        key: "event",
        type: :string,
        label: "When this event arrives",
        required?: true,
        default: ""
      },
      %{
        key: "payload",
        type: {:type_expr, %{arms: [:name, :inline]}},
        label: "Its payload is",
        required?: false,
        default: ""
      },
      %{
        key: "cond",
        type: :expression,
        label: "Only when",
        required?: false,
        default: ""
      },
      %{
        key: "outcome",
        type:
          {:select,
           [{"abandon", "Abandon - leave the group"}, {"resume", "Resume - re-enter the group"}]},
        label: "Then",
        required?: true,
        default: "abandon"
      },
      %{
        key: @finish_as_key,
        type: :string,
        label: "Finishing as",
        required?: false,
        default: ""
      }
    ]

  @doc """
  The outcome this handler finishes with.

  Named, the single outcome `finish_as` carries, labelled with the name
  itself. Unnamed, ADR-0002 A1's default - which is what this type
  answered before it implemented this callback at all, and answering it
  here byte for byte is what keeps the key additive.
  """
  @impl true
  def outcomes(config) do
    case finish_as(config) do
      nil -> [{@default_outcome, "Done"}]
      name -> [{name, name}]
    end
  end

  @doc """
  The three fields with checks of their own, and `capture`.

  `payload` is not among them. It is a `{:type_expr, opts}` field, and
  what a value of one may be is
  `StatifierBlocks.BlockType.type_expr_findings/2`'s single check for
  every field of that type - the compiler's `:config` stage and the
  editor's view model both consult it, so an author is shown the set a
  compile refuses. Re-implementing the same test here would report the
  same bytes twice on the same key, and whether the name *resolves* is not
  a finding on either side: that is ADR-0002's P4 case, the undeclared
  payload, unchanged behaviour.
  """
  @impl true
  def validate_config(config) do
    []
    |> check_event(config)
    |> check_cond(config)
    |> check_outcome(config)
    |> check_finish_as(config)
    |> check_capture(config)
    |> Config.verdict()
  end

  defp check_event(findings, config) do
    if Config.event_name?(Map.get(config, "event")) do
      findings
    else
      [{"event", "must be an event name, like order.cancelled"} | findings]
    end
  end

  # The guard is optional, so only a stored value that is not a string at
  # all is a finding. Whether the expression *means* anything is
  # predicator's answer at compile, not this function's (ADR-0004
  # decision 9), and an empty string is the editor's spelling of "no
  # guard" - it is the field's own default.
  defp check_cond(findings, config) do
    case Map.get(config, "cond") do
      nil -> findings
      condition when is_binary(condition) -> findings
      _other -> [{"cond", "must be a condition expression, or left blank"} | findings]
    end
  end

  defp check_outcome(findings, config) do
    if Config.one_of(Map.get(config, "outcome"), @outcomes) do
      findings
    else
      [{"outcome", ~s(pick "abandon" or "resume")} | findings]
    end
  end

  # The three refusals `C8` item 4 names, each a finding on the new key.
  # They are three independent conditions and not a first-match ladder:
  # item 4 calls them "three refusals, all of them `validate_config/1`
  # findings on the new key", so a name that trips two of them draws two
  # findings on the key rather than the first one alone.
  #
  # The name becomes a state id segment and an event segment, so it takes
  # the shape every outcome name takes - `StatifierBlocks.Compiler.StateId.role?/1`
  # is that predicate, and it is the same judgement the compiler already
  # makes for a declared name.
  #
  # `done` is refused because it is the name the blank arm already
  # answers, so writing it is either a no-op spelled as a decision or a
  # request for two outcomes with one name.
  #
  # A name beside `outcome: "resume"` is refused because a resuming
  # handler re-enters the group and finishes nothing: honouring the name
  # would compile a final the handler never reaches.
  defp check_finish_as(findings, config) do
    case Map.get(config, @finish_as_key) do
      blank when blank in [nil, ""] ->
        findings

      name ->
        findings
        |> check_finish_as_done(name)
        |> check_finish_as_shape(name)
        |> check_finish_as_resumes(config)
    end
  end

  defp check_finish_as_done(findings, @default_outcome) do
    [
      {@finish_as_key, ~s(cannot be "done" - that is what a handler with no name finishes as)}
      | findings
    ]
  end

  defp check_finish_as_done(findings, _name), do: findings

  defp check_finish_as_shape(findings, name) do
    if StateId.role?(name) do
      findings
    else
      [{@finish_as_key, "must be an outcome name, like went_back"} | findings]
    end
  end

  defp check_finish_as_resumes(findings, config) do
    if Map.get(config, "outcome") == "resume" do
      [
        {@finish_as_key, ~s(only a handler that abandons its group finishes with a name)}
        | findings
      ]
    else
      findings
    end
  end

  # The map is optional, and an empty one is the same as none - it is what
  # a document that once carried pairs and no longer does looks like.
  # A single finding is reported for the whole key rather than one per bad
  # pair, because `capture` has no field in `config_schema/1` to render a
  # per-pair finding against (see the moduledoc), so the anchor an editor
  # could use is the key itself.
  defp check_capture(findings, config) do
    case Map.get(config, "capture") do
      nil ->
        findings

      capture when is_map(capture) ->
        if Enum.all?(capture, &pair?/1) do
          control_finding(findings, capture)
        else
          [{"capture", capture_message()} | findings]
        end

      _other ->
        [{"capture", capture_message()} | findings]
    end
  end

  defp pair?({destination, source}), do: path?(destination) and source?(source)
  defp pair?(_other), do: false

  # The one restriction on a literal that is not a question of type
  # (ADR-0002's line of 2026-09-13, taken on this request). `literal/1`
  # writes a string's characters into an `<assign expr=...>` attribute
  # value, and `escape/1` rewrites exactly three control characters - tab,
  # line feed and carriage return - as the escapes predicator's lexer
  # decodes. Every other C0 control reaches the attribute RAW, and XML 1.0
  # admits no character below `U+0020` in an attribute value other than
  # those three (XML 1.0 5th ed., the `Char` production). Saxy reads one
  # back today, but a parser's tolerance is not the wire format's contract,
  # so the document is refused at compile instead.
  #
  # The finding lands on the `capture` key for the reason `check_capture/2`
  # gives: the key is the only anchor an editor has. The message names the
  # offending codepoint so an author can find it in a string whose damage
  # is invisible on screen.
  #
  # The walk is `literal/1`'s own: into a list, and into a map's KEYS as
  # well as its members, because `literal/1` spells a key with the same
  # function it spells a string value with. Pairs and object keys are
  # sorted first so a document with more than one offender reports the same
  # codepoint on every compile.
  #
  # A control character in the PATH form is not this clause's business: a
  # path is refused for containing whitespace already, and what an
  # otherwise-shaped path spells is `path?/1`'s question.
  defp control_finding(findings, capture) do
    case control_codepoint(capture) do
      nil -> findings
      codepoint -> [{"capture", control_message(codepoint)} | findings]
    end
  end

  @spec control_codepoint(map()) :: non_neg_integer() | nil
  defp control_codepoint(capture) do
    capture
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.find_value(fn
      {_destination, [@const_tag, value]} -> control_in(value)
      {_destination, _source} -> nil
    end)
  end

  # `String.to_charlist/1` raises `UnicodeConversionError` on a binary that
  # is not valid UTF-8, so the clause asks `String.valid?/1` first and
  # answers `nil` - no control character found - for one that is not. A
  # parsed document never reaches that case: `Decode.decode/1` runs
  # `Validation.validate/1` over every document this package parses, and
  # its `canonical_json_check/2` refuses a non-UTF-8 binary in `config`
  # before any compile walks it. `validate_config/1` is public, though,
  # and a host calling it directly with `["const", <<0xFF>>]` asks a
  # question about SHAPE; it gets the shape answer rather than a raise,
  # and the encoding refusal stays the one `canonical_json_check/2`
  # gives.
  #
  # A literal that is BOTH invalid UTF-8 and carries a C0 control byte,
  # `<<1, 0xFF>>`, therefore draws no control-character finding either.
  # That is the same deliberate shape answer and not an oversight: this
  # walk reads CHARACTERS, a binary that is not valid UTF-8 has none to
  # read, and the byte that would offend is visible only to something
  # reading raw bytes instead. The layering is what makes it harmless -
  # such a binary is outside `ADR-0001`'s decision 6 value grammar
  # altogether, so the only way it arrives is a direct call (this
  # callback, or a hand-built `t:StatifierBlocks.Document.t/0` handed to
  # `StatifierBlocks.Compiler.compile/3`), and a direct call gets the
  # encoding refusal from `canonical_json_check/2`, at the door, rather
  # than a second copy of it phrased as a control-character finding
  # here.
  defp control_in(value) when is_binary(value) do
    if String.valid?(value), do: value |> String.to_charlist() |> Enum.find(&control?/1)
  end

  defp control_in(value) when is_list(value), do: Enum.find_value(value, &control_in/1)

  defp control_in(value) when is_map(value) and not is_struct(value) do
    value
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.find_value(fn {key, member} -> control_in(key) || control_in(member) end)
  end

  defp control_in(_other), do: nil

  defp control?(codepoint), do: codepoint < 0x20 and codepoint not in [?\t, ?\n, ?\r]

  defp control_message(codepoint) do
    ~s(must not carry the control character ) <>
      hex(codepoint) <>
      ~s( inside a ["const", value] literal: a literal is written into an ) <>
      "XML attribute value raw, and XML 1.0 admits no character below " <>
      "U+0020 there other than tab (U+0009), line feed (U+000A) and " <>
      "carriage return (U+000D)"
  end

  defp hex(codepoint) do
    "U+" <> (codepoint |> Integer.to_string(16) |> String.pad_leading(4, "0"))
  end

  # ADR-0002's Note of 2026-09-12, N1: the value position of a pair takes
  # either form, and the two are told apart by SHAPE and never by content.
  # A string is a path - no string is reinterpreted as a literal because of
  # what it happens to spell - and a two-element list tagged `"const"` is a
  # literal. Everything else is malformed, including a list of any other
  # length and a tagged pair whose value this package cannot spell as a
  # literal expression (`spellable?/1`).
  defp source?(source) when is_binary(source), do: path?(source)
  defp source?([@const_tag, value]), do: spellable?(value)
  defp source?(_other), do: false

  defp path?(value) do
    Config.non_empty_string?(value) and not Regex.match?(@whitespace, value)
  end

  defp capture_message do
    "must map each datamodel path written, like order.cancel_reason, " <>
      "to its source: either the path inside _event.data it is read from, " <>
      ~s(like reason, or the literal ["const", value], whose value is any ) <>
      "JSON a block document may carry: a string, an integer, true, " <>
      "false, null, an array or an object"
  end

  @doc """
  The `capture` pairs this handler's declared `payload` refuses
  (ADR-0002's amendment of 2026-09-06, P5).

  Returns `validate_config/1`'s own `{key, message}` shape, so the
  compiler's config stage renders it exactly as it renders that
  function's findings: at most one finding, on the `"capture"` key.

  It is a separate function rather than another clause of
  `validate_config/1` because it needs something that callback is not
  given - the datamodel document's declarations, indexed by
  `StatifierDatamodel.Declarations.from_document/1` - and the compiler
  reads that document once and hands it here.

  Both arms of the field are read here. A `payload` holding a name is
  resolved through `StatifierDatamodel.Declarations.fetch/2` and checked
  against that declaration's fields; a `payload` holding an inline shape
  is read through `StatifierBlocks.Environment.inline_shape/1` and checked
  against its members. The walk below the first segment is the same rule
  in both cases.

  Total, and empty in every case the amendment says is not a finding: no
  `payload`, a blank one, a name the declarations do not carry, no
  `capture`, a malformed one (`check_capture/2` owns that verdict), and a
  source path whose walk stops at a field this package cannot see into.

      iex> alias StatifierBlocks.Core.OnEvent
      iex> declarations = StatifierDatamodel.Declarations.from_document(%{"types" => [
      ...>   %{"name" => "cards.declined", "kind" => "record", "label" => "Declined",
      ...>     "fields" => [%{"name" => "reason", "type" => "string"}]}]})
      iex> config = %{"event" => "cards.declined", "outcome" => "abandon",
      ...>   "payload" => "cards.declined", "capture" => %{"card.why" => "reason"}}
      iex> OnEvent.payload_capture_findings(config, declarations)
      []
      iex> OnEvent.payload_capture_findings(%{config | "capture" => %{"card.why" => "code"}},
      ...>   declarations) |> Enum.map(&elem(&1, 0))
      ["capture"]

      iex> alias StatifierBlocks.Core.OnEvent
      iex> inline = [%{"name" => "reason", "type" => "string"}]
      iex> config = %{"event" => "cards.declined", "outcome" => "abandon",
      ...>   "payload" => inline, "capture" => %{"card.why" => "reason"}}
      iex> OnEvent.payload_capture_findings(config, %{})
      []
      iex> OnEvent.payload_capture_findings(%{config | "capture" => %{"card.why" => "code"}},
      ...>   %{}) |> Enum.map(&elem(&1, 0))
      ["capture"]
  """
  @spec payload_capture_findings(Block.config(), StatifierDatamodel.Declarations.t()) :: [
          {String.t(), String.t()}
        ]
  def payload_capture_findings(config, declarations) when is_map(declarations) do
    with {:ok, subject, members} <- declared_payload(Map.get(config, "payload"), declarations),
         pairs when is_map(pairs) <- Map.get(config, @capture_key),
         [_first | _rest] = offenders <- unread_pairs(pairs, declarations, members) do
      [{@capture_key, payload_message(subject, offenders)}]
    else
      _no_declaration_or_nothing_refused -> []
    end
  end

  # The two arms, read down to the one thing the walk needs: what the
  # payload's members are called, and how the payload is named in a
  # message. An inline shape has no name to print, so it is described.
  @spec declared_payload(term(), Declarations.t()) ::
          {:ok, String.t(), [map()]} | :error
  defp declared_payload(name, declarations) when is_binary(name) and name != "" do
    case Declarations.fetch(declarations, name) do
      {:ok, %{fields: fields}} -> {:ok, name, fields}
      _no_declaration -> :error
    end
  end

  defp declared_payload(members, _declarations) when is_list(members) do
    {:shape, read} = Environment.inline_shape(members)
    {:ok, @inline_subject, read}
  end

  defp declared_payload(_absent_or_no_arm, _declarations), do: :error

  # The pairs whose source path reads a member the payload does not carry,
  # in the destinations' sorted order - the same order the assigns are
  # emitted in, so a message that names several reads in the order the
  # bytes do. A pair `check_capture/2` has already refused is skipped:
  # one malformed pair is one finding, not two.
  @spec unread_pairs(map(), Declarations.t(), [map()]) ::
          [{String.t(), String.t()}]
  defp unread_pairs(pairs, declarations, members) do
    for {destination, source} = pair <- Enum.sort(pairs),
        path?(destination) and path?(source),
        not carries?(declarations, members, String.split(source, ".")),
        do: pair
  end

  # P5's depth rule. The first segment is checked against the member names
  # the payload carries; a deeper one is checked only where that member's
  # own type resolves to something whose members are in hand - another
  # declaration, or another inline shape. A member typed as a scalar, an
  # opaque string, a list or nothing at all stops the walk and refuses
  # nothing beyond it, which is the stance `StatifierDatamodel.Types`' own
  # read check takes.
  #
  # The two arms meet here: a declaration's `fields` and an inline shape's
  # members are both lists of maps carrying `:name` and `:type`, and the
  # only thing that differs is how a member's type spells a descent - a
  # declaration's field carries `{:declared, name}`, an inline member
  # carries the name itself or a nested `{:shape, members}`.
  @spec carries?(Declarations.t(), [map()], [String.t()]) :: boolean()
  defp carries?(declarations, members, [segment | rest]) do
    case field(members, segment) do
      nil -> false
      _member when rest == [] -> true
      member -> descend(declarations, member, rest)
    end
  end

  @spec descend(Declarations.t(), map(), [String.t()]) :: boolean()
  defp descend(declarations, %{type: {:declared, name}}, rest),
    do: descend_named(declarations, name, rest)

  defp descend(declarations, %{type: {:shape, members}}, rest),
    do: carries?(declarations, members, rest)

  defp descend(declarations, %{type: name}, rest) when is_binary(name) and name != "",
    do: descend_named(declarations, name, rest)

  defp descend(_declarations, _opaque_to_this_walk, _rest), do: true

  @spec descend_named(Declarations.t(), String.t(), [String.t()]) :: boolean()
  defp descend_named(declarations, name, rest) do
    case Declarations.fetch(declarations, name) do
      {:ok, %{fields: fields}} -> carries?(declarations, fields, rest)
      :error -> true
    end
  end

  @spec field([map()], String.t()) :: map() | nil
  defp field(members, name),
    do: Enum.find(members, &(Map.get(&1, :name) == name))

  # `subject` is how the payload is named: the declared name for the name
  # arm, and the inline description for the other, because an inline shape
  # has none.
  @spec payload_message(String.t(), [{String.t(), String.t()}]) :: String.t()
  defp payload_message(subject, offenders) do
    read =
      Enum.map_join(offenders, ", ", fn {destination, source} ->
        ~s("#{destination}" reads #{source})
      end)

    "reads past the declared payload: #{read}, and #{subject} carries no such member. " <>
      "Declare the member on #{subject}, correct the source path, or drop the payload " <>
      "declaration to leave the read unchecked"
  end

  @impl true
  def io(_config), do: %{kinds: [:interrupt_handler]}

  @impl true
  def palette_entry,
    do: %{
      label: "On event",
      group: "Structure",
      description: "Interrupts the group it sits in when an event arrives.",
      icon: "bolt",
      keywords: ["interrupt", "cancel", "event", "handler"],
      order: 6
    }

  @doc """
  The outcome's word, then the event name, as a chip list (ADR-0002
  amendment H6).

  The outcome comes first because it is what the block *does*; the event
  is only when. Each half is dropped on its own when it is not there or
  not well formed, so a handler mid-edit shows the half the author has
  filled in rather than nothing.

      iex> StatifierBlocks.Core.OnEvent.summary(%{"outcome" => "abandon", "event" => "order.cancelled"})
      ["Abandon", "order.cancelled"]

      iex> StatifierBlocks.Core.OnEvent.summary(%{"outcome" => "resume"})
      ["Resume"]

      iex> StatifierBlocks.Core.OnEvent.summary(%{})
      []
  """
  @impl true
  def summary(config) do
    [outcome_word(Map.get(config, "outcome")), event_chip(Map.get(config, "event"))]
    |> Enum.reject(&is_nil/1)
  end

  defp outcome_word("abandon"), do: "Abandon"
  defp outcome_word("resume"), do: "Resume"
  defp outcome_word(_undeclared), do: nil

  defp event_chip(event) do
    if Config.event_name?(event), do: event, else: nil
  end

  @doc """
  This block as one line of prose (ADR-0002's 2026-09-07 amendment).

  The event that fires the handler, then the outcome it raises. It is the
  reverse of `summary/1`'s chip order, and deliberately so: a chip list has
  no grammar to carry "when", so the outcome leads there because it is what
  the block does; a sentence has that grammar, and a reader scanning an
  `interrupts` slot asks which handler answers which event before asking
  what it does to the group.

  Each half is held to the same test the card holds it to. An event name
  that is not well formed, and an outcome that is not one of the two
  declared values, are findings on the card, and repeating either in a line
  that reads as settled would bury the finding rather than report it.

  A handler with no outcome yet falls back to the one thing both declared
  outcomes have in common - it interrupts the group it sits in - rather
  than naming a default the emission does not use.

      iex> StatifierBlocks.Core.OnEvent.sentence(%{"event" => "card.authz_timed_out", "outcome" => "abandon"})
      "When card.authz_timed_out, abandon"

      iex> StatifierBlocks.Core.OnEvent.sentence(%{"event" => "order.cancelled"})
      "When order.cancelled, interrupt the group"

      iex> StatifierBlocks.Core.OnEvent.sentence(%{})
      "When an event, interrupt the group"
  """
  @impl true
  def sentence(config) do
    event = event_chip(Map.get(config, "event")) || "an event"
    outcome = declared_outcome(Map.get(config, "outcome")) || "interrupt the group"

    "When #{event}, #{outcome}"
  end

  defp declared_outcome(outcome) do
    if Config.one_of(outcome, @outcomes), do: outcome, else: nil
  end

  @doc """
  One example event payload, so a palette panel can show what `_event.data`
  looks like when this handler fires.

  > #### Provisional: the accepted spellings are not settled {: .warning}
  >
  > PROVISIONAL - see ADR-0002 decision 9. The atom-keyed spelling below
  > comes from an amendment to that decision which has not been accepted.
  > Until it is, treat the shape as the intended target rather than a
  > settled contract. That this callback exists, and returns `term()`, is
  > settled either way.

  Under statifier-ui's `docs/fixture-bundles.md`, `events` is one sample
  `_event.data` payload per event name. The name here is an example, not
  this block's configured `event` - `fixtures/0` takes no config and could
  not read one.
  """
  @impl true
  def fixtures do
    %{
      events: %{
        "order.cancelled" => %{"reason" => "customer_request", "at" => "2026-08-26T17:00:00Z"}
      }
    }
  end

  @doc """
  A compound state that waits for `event` and, when it arrives, raises the
  interrupt-protocol event its `outcome` names before going final.

      <state id="s_INT" initial="s_INT__armed">
        <state id="s_INT__armed">
          <transition event="order.cancelled" target="s_INT__done">
            <raise event="statifier_blocks.interrupt.abandon"/>
          </transition>
        </state>
        <final id="s_INT__done"/>
      </state>

  The group this handler sits in runs it as a region of a `<parallel>`
  alongside the body, which is what keeps it live while the body works, and
  transitions on **both** protocol events unconditionally - see
  `StatifierBlocks.Core.Emit`. The raise is how the outcome crosses that
  seam: ADR-0004 decision 4 keeps a child's config out of its parent's
  context on purpose, so the group cannot read `outcome` and must not try.

  A raised event is internal, so it is processed before any external event
  the queue is holding. Which group the raise reaches is not left to the
  engine's transition selection: the compiler salts the raise, and the
  matching transitions, with the state id of the group whose rail this
  handler sits on (ADR-0010 decision 8), so a handler reaches its own
  group's rail and no other at any nesting depth. That is why the event
  name written above is the one this type emits, and the one in the
  compiled chart carries `.<group state id>` after it.

  ## A guarded handler

  A `cond` in config becomes the `cond` on that one transition, and
  nothing else about the shape moves:

      <state id="s_INT__armed">
        <transition cond="review.parked" event="review.resolved" target="s_INT__done">
          <raise event="statifier_blocks.interrupt.resume"/>
        </transition>
      </state>

  So the event arriving while the condition is false leaves the handler
  armed and the body running - the interrupt simply does not happen, and
  the same event arriving later, once the condition holds, still fires it.
  A handler with no `cond` writes no `cond` attribute at all
  (`StatifierBlocks.Core.Emit.transition/2` drops an absent one), which is
  why an unguarded handler's bytes are unchanged by this key existing.

  The `cond_key` passed alongside is `"cond"`, the config key the author
  typed into, so an upstream expression error lands on that field rather
  than reading as a bug in this type (ADR-0004 decision 9). It is passed
  unconditionally, guard or no guard:
  `StatifierBlocks.Emission.attribute_from_config/3` records an owner only
  for an attribute the element actually carries, so an unguarded handler
  records none without this call site testing for it twice.

  ## A capturing handler

  Each `capture` pair becomes one `<assign>` on that same transition,
  ahead of the `<raise>`. A pair whose source is a **path** carries that
  assign inside an `<if>` that tests the path for presence, so a payload
  that does not carry it leaves the destination alone (ADR-0002's Note of
  2026-09-12, `N2`); a pair whose source is a **literal** has no path to
  be absent and is written bare:

      <state id="s_INT__armed">
        <transition event="order.cancelled" target="s_INT__done">
          <if cond="_event.data.reason !== undefined">
            <assign expr="_event.data.reason" location="order.cancel_reason"/>
          </if>
          <assign expr="&quot;cancelled&quot;" location="order.mark"/>
          <raise event="statifier_blocks.interrupt.abandon"/>
        </transition>
      </state>

  The pairs are ordered by their datamodel paths, sorted, so two
  compiles of one document write one byte sequence. A handler with no
  `capture` - the key absent, or an empty map - emits the bytes above
  this section unchanged.
  """
  @impl true
  def emit(%Block{config: config}, context) do
    with {:ok, armed} <- Context.role_id(context, "armed"),
         {:ok, finish} <- finish_id(context, config),
         {:ok, outcome} <- outcome_event(Map.get(config, "outcome")),
         {:ok, event} <- event_name(Map.get(config, "event")),
         {:ok, assigns} <- captures(Map.get(config, "capture")) do
      watcher =
        Emit.state(armed, nil, [
          Emit.transition(
            [event: event, cond: guard(config), cond_key: "cond", target: finish],
            assigns ++ [Emission.element("raise", [{"event", outcome}])]
          )
        ])

      {:ok, Emit.state(context.state_id, armed, [watcher, Emit.final(finish)])}
    end
  end

  # The id of the final this handler reaches, and so - through
  # `StatifierBlocks.Core.Emit.final/1` - the completion event it raises.
  #
  # Named, that is the handler's own outcome id, which puts the id in the
  # `o_` namespace and makes `Emit.final/1` wrap it in an `<onentry>`
  # raise of `done.outcome.<handler state>.<name>`. Unnamed, it is
  # `Context.done_id/1` exactly as before.
  #
  # This is a threading and not a substitution: the two functions answer
  # different shapes - `done_id/1` a bare id, `outcome_id/2` the tagged
  # `{:ok, id} | {:error, {:invalid_outcome, ...}}` that is ratified
  # precisely because ADR-0004 decision 1 forbids `emit/2` to raise - so
  # the named call belongs inside the `with` above, where every other
  # caller of `outcome_id/2` puts it.
  @spec finish_id(Context.t(), Block.config()) ::
          {:ok, StateId.t()} | {:error, {:invalid_outcome, Block.id(), String.t()}}
  defp finish_id(context, config) do
    case finish_as(config) do
      nil -> {:ok, Context.done_id(context)}
      name -> Context.outcome_id(context, name)
    end
  end

  # The stored name, or `nil` for a handler that carries none. Blank
  # counts as none: `""` is the schema's default and what the editor
  # leaves behind when an author clears the field. A stored value that is
  # not a string at all is a `validate_config/1` finding, and reading it
  # as "no name" here keeps `outcomes/1` total.
  @spec finish_as(Block.config()) :: String.t() | nil
  defp finish_as(config) do
    name = Map.get(config, @finish_as_key)

    if Config.non_empty_string?(name), do: name, else: nil
  end

  # The stored condition, or `nil` for a handler that carries none.
  # Blank counts as none: `""` is the schema's default and what the editor
  # leaves behind when an author clears the field, and writing
  # `cond=""` would be an expression predicator has to reject rather than
  # the absence of a guard.
  #
  # Read with the same tolerance `validate_config/1` shows, because
  # `emit/2` runs on config the Config stage has already passed and a
  # non-string here cannot reach it - but a total function is what every
  # other reader of config in this module is.
  defp guard(config) do
    case Map.get(config, "cond") do
      condition when is_binary(condition) ->
        if String.trim(condition) == "", do: nil, else: condition

      _absent_or_malformed ->
        nil
    end
  end

  # The `<assign>` elements a `capture` map compiles to, in their
  # datamodel paths' sorted order, or `[]` for a handler that captures
  # nothing.
  #
  # A malformed map answers with a finding rather than dropping the pair.
  # The Config stage makes that arm unreachable in practice, never
  # impossible, and a capture silently not emitted is the failure this key
  # exists to prevent: everything downstream reads an unwritten path as an
  # authored absence.
  defp captures(nil), do: {:ok, []}

  defp captures(capture) when is_map(capture) do
    if Enum.all?(capture, &pair?/1) do
      assigns =
        capture
        |> Enum.sort_by(fn {destination, _source} -> destination end)
        |> Enum.map(fn {destination, source} ->
          guarded(
            source,
            Emission.element(
              "assign",
              [{"expr", source_expr(source)}, {"location", destination}]
            )
          )
        end)

      {:ok, assigns}
    else
      {:error, [{"capture", capture_message()}]}
    end
  end

  defp captures(_other), do: {:error, [{"capture", capture_message()}]}

  # ADR-0002's Note of 2026-09-12, `N2`: from `0.28.0` on, a pair whose
  # source is a PATH and whose path the firing event's payload does not
  # carry writes nothing at its destination, so that "not answered" and
  # "answered with nothing" stop being the same value. The Note decides the
  # behaviour and leaves the mechanism here; this is the mechanism, and the
  # four facts it rests on are cited below against the resolved dependency
  # versions (`statifier` 2.5.0, `predicator` 9.4.1), which are what an
  # emitted chart is read by.
  #
  # The assign is wrapped in an `<if>` whose `cond` tests the very path the
  # assign reads, spelled once by `source_expr/1` so the guard and the read
  # cannot drift apart:
  #
  #     <if cond="_event.data.reason !== undefined">
  #       <assign expr="_event.data.reason" location="order.cancel_reason"/>
  #     </if>
  #
  #   1. `<if>` is executable content the engine supports inside a
  #      `<transition>`, end to end: it is in the lowering table
  #      (`statifier/lowering.ex:75`, `"if" => &Builders.build_if/2`), it is
  #      placed into a transition like any other content node
  #      (`lowering/builders.ex`, `place({:content_node, node}, %Transition{}
  #      = parent, _)`), and it executes by selecting the first matching
  #      branch (`machine/content/if.ex:107`, `def execute(%If{branches:
  #      branches}, ...)`). With no branch selected it runs nothing and
  #      answers the context unchanged (`if.ex:112`, `nil -> {:ok, context,
  #      []}`), which is precisely "leaves its destination unwritten".
  #   2. A bare `<assign>` cannot express this: it always writes. `_event`
  #      is a bound root whatever the payload carries, and an access that
  #      does not resolve answers the unbound marker rather than failing
  #      (`predicator/evaluator.ex:1230`, `Map.get(object, key,
  #      Undefined.value())`), so the assign succeeds and stores
  #      `:undefined`. That is the behaviour `N2` retires, and it is the
  #      engine's, not this package's.
  #   3. `!==` is the operator, not `!=`. Every non-strict comparison
  #      propagates the marker rather than answering a boolean
  #      (`predicator/evaluator.ex:787`, `:791`, guarded `when operator not
  #      in ["STRICT_EQ", "STRICT_NE"]`); the strict pair compares the terms
  #      themselves (`:795`, `compare_values(left, right, "STRICT_EQ"), do:
  #      left === right`). A `cond` that answers a non-boolean is treated as
  #      false (`machine/content/if.ex:152`, `{:non_boolean_cond, other}`,
  #      accumulated into the context's `pending_errors` rather than
  #      selecting the branch) AND raises a spurious `error.execution` -
  #      three hops on: `interpreter/content.ex:241` (`drain_pending/2`
  #      over a non-empty `pending_errors`), `:295`
  #      (`raise_execution_error/4`), and `machine_state.ex:811`, where
  #      `raise_platform/4` `enqueue_internal`s the event. So `!=` would
  #      skip the assign and dirty the run at the same time. This
  #      is the same reading `core.subchart` took for its routing
  #      conditions, where `==` against an absent `_event.data.outcome` cost
  #      a spurious `error.execution` (pinned upstream in statifier-ex).
  #   4. A nested source needs no chain of guards: an access whose target is
  #      neither map nor list answers the marker too
  #      (`predicator/evaluator.ex:1244`, `defp access_value(object, _key,
  #      _operation) when not is_map(object) and not is_list(object)`), so
  #      one `!== undefined` over the whole path covers an absent
  #      intermediate as well as an absent leaf.
  #
  # A LITERAL pair is never guarded (`N2`: "a literal pair has no source to
  # be absent, and always writes"), which is also what keeps a document
  # whose every pair is a literal compiling to the bytes `N1` gave it.
  #
  # `null` is not absence. A payload that carries the source with a JSON
  # `null` writes `null`, because the marker and `null` are distinct terms
  # under `===` - which is the whole of what `N2` decides: "not answered"
  # and "answered with nothing" are different values.
  @spec guarded(String.t() | [term()], Emission.t()) :: Emission.t()
  defp guarded(source, assign) when is_binary(source) do
    Emission.element("if", [{"cond", source_expr(source) <> " !== undefined"}], [assign])
  end

  defp guarded([@const_tag, _value], assign), do: assign

  # The `expr` of one pair's `<assign>`, told apart by the source's SHAPE
  # (`source?/1`): a string is a path inside the firing event's payload and
  # compiles exactly as it always has, and a `["const", value]` pair
  # compiles to `value` spelled as a literal expression. Only pairs
  # `pair?/1` has already admitted reach here.
  @spec source_expr(String.t() | [term()]) :: String.t()
  defp source_expr(source) when is_binary(source), do: "_event.data." <> source
  defp source_expr([@const_tag, value]), do: literal(value)

  # A document value spelled as a predicator literal expression - the
  # decision ADR-0002's Note of 2026-09-12 delegates to this request, taken
  # against `predicator` 9.4.1 (the resolved version; `mix.exs` requires
  # `~> 9.4.1`) and against `Statifier.Compiler.Expressions.compile/3`, which
  # is what an `<assign expr=...>` is read by.
  #
  # The spelling is predicator's own literal grammar rather than the
  # value's JSON encoding, because the two differ in exactly one place
  # that matters: JSON escapes a character it cannot write literally as
  # `\uXXXX`, and predicator's lexer has no such escape - it decodes an
  # unrecognised `\X` to the bare `X` (`take_string/6`), so a JSON-encoded
  # string would arrive at the datamodel with the escape's own letters in
  # it. The grammar this emits, per type:
  #
  #   * a string  - double-quoted, with `\` escaped and then `"` escaped,
  #     which is the order predicator's own writer uses; the three control
  #     characters its lexer decodes (`\n`, `\t`, `\r`) are written as
  #     those escapes rather than raw, because a raw newline or tab in an
  #     XML attribute value is normalised to a space before any lexer sees
  #     it;
  #   * an integer - its digits, a negative one with the `-` that
  #     predicator reads as a unary minus over the positive literal and
  #     evaluates to the negative integer;
  #   * `true` / `false` - themselves;
  #   * `null` - JSON's null and predicator's, which both evaluate to
  #     Elixir's `nil`;
  #   * an array - `[` the elements by this same rule, comma-separated `]`;
  #   * an object - `{` its pairs as `"key": value`, comma-separated, in
  #     the keys' sorted order `}`. Sorted for the reason the pairs
  #     themselves are sorted: a map has no order of its own and a compile
  #     has to be deterministic.
  #
  # There is no float clause, and there needs to be none: a float is not a
  # value a block document may carry at all
  # (`StatifierBlocks.Validation`'s `{:float, path}` problem).
  #
  # The facts this rests on - the escape set the lexer decodes, and that a
  # string literal is written back whole rather than a byte at a time - are
  # that lexer's behaviour rather than a documented grammar, so `mix.exs`
  # requires the version they were measured at: `~> 9.4.1`.
  #
  # The round trips in `test/statifier_blocks/core/on_event_test.exs` hold
  # BOTH of them honest, and the same way: they assert the value read back
  # rather than the bytes emitted, against the real engine, so they answer
  # for whichever 9.x is actually resolved. An escape that stops decoding
  # takes the escape cases red; a lexer that goes back to writing a
  # string's codepoints one byte at a time takes the non-ASCII case red.
  # That second direction is the one nothing in this suite could cover
  # while the refusal stood, because a literal the refusal turned away
  # never reached this function to be round-tripped at all.
  @spec literal(term()) :: String.t()
  defp literal(value) when is_binary(value), do: ~s(") <> escape(value) <> ~s(")
  defp literal(value) when is_integer(value), do: Integer.to_string(value)
  defp literal(true), do: "true"
  defp literal(false), do: "false"
  defp literal(nil), do: "null"

  defp literal(value) when is_list(value),
    do: "[" <> Enum.map_join(value, ",", &literal/1) <> "]"

  defp literal(value) when is_map(value) and not is_struct(value) do
    inner =
      value
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map_join(",", fn {key, member} -> literal(key) <> ":" <> literal(member) end)

    "{" <> inner <> "}"
  end

  @spec escape(String.t()) :: String.t()
  defp escape(value) do
    value
    |> String.replace("\\", "\\\\")
    |> String.replace(~s("), ~s(\\"))
    |> String.replace("\n", "\\n")
    |> String.replace("\t", "\\t")
    |> String.replace("\r", "\\r")
  end

  # Whether `literal/1` can spell this value so that the engine reads back
  # what the document carried. Total, and the gate `source?/1` puts in
  # front of `literal/1`, so a value that cannot be spelled is a malformed
  # pair rather than bytes that only look like the author's value.
  #
  # This is a question of TYPE and nothing else. Until 2026-09-13 a string
  # carried one restriction beyond type - it had to stay inside printable
  # ASCII, tab, newline and carriage return - because predicator 9.4.0's
  # lexer read a string literal codepoint by codepoint and wrote each one
  # back as a single BYTE, so any character above ASCII arrived at the
  # datamodel mangled. That restriction was never a rule this package's
  # records state - `N1` of ADR-0002's Note of 2026-09-12 admits every JSON
  # type and left the spelling to the code - so it was declared interim
  # here and in `mix.exs`, and it ended with ADR-0002's Note of 2026-09-13:
  # predicator 9.4.1 reads a string literal back whole, `mix.exs` requires
  # `~> 9.4.1` for that reason and no other, and `escape/1` plus the round
  # trip in `test/statifier_blocks/core/on_event_test.exs` are now the whole
  # of what a string has to satisfy.
  #
  # So a string is admitted whatever it carries, and what is left here is
  # the types a block document may not carry into a predicator literal at
  # all: a float (`StatifierBlocks.Validation` refuses one before this key
  # is read), an atom other than `true` / `false` / `nil`, a tuple, a
  # struct, and a map with a key that is not a string.
  @spec spellable?(term()) :: boolean()
  defp spellable?(value) when is_binary(value), do: true
  defp spellable?(value) when is_integer(value), do: true
  defp spellable?(value) when is_boolean(value), do: true
  defp spellable?(nil), do: true
  defp spellable?(value) when is_list(value), do: Enum.all?(value, &spellable?/1)

  defp spellable?(value) when is_map(value) and not is_struct(value) do
    Enum.all?(value, fn {key, member} -> is_binary(key) and spellable?(member) end)
  end

  defp spellable?(_other), do: false

  defp outcome_event("abandon"), do: {:ok, Emit.interrupt_events().abandon}
  defp outcome_event("resume"), do: {:ok, Emit.interrupt_events().resume}
  defp outcome_event(_other), do: {:error, [{"outcome", ~s(pick "abandon" or "resume")}]}

  defp event_name(event) do
    if Config.event_name?(event) do
      {:ok, event}
    else
      {:error, [{"event", "must be an event name, like order.cancelled"}]}
    end
  end
end
