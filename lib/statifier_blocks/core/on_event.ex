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

  ## Candidates for `event` (sb-82mu)

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

  `capture` writes values out of the firing event's payload into the
  datamodel. It is a map, and the direction is worth stating twice
  because a path-to-path map reads either way: **the key is the
  destination** - a datamodel path - and **the value is the source**, a
  path inside `_event.data`. A `capture` of
  `%{"order.cancel_reason" => "reason"}` on a handler for
  `order.cancelled` writes that event's `reason` into
  `order.cancel_reason`.

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

  The value is the **name of a type the datamodel document declares** - a
  `record` or a `shape` in its `types` key, read through
  `StatifierDatamodel.Declarations`. P2 of that amendment names a second
  arm, an inline shape written where the payload is declared, and P3
  defers it: no member of ADR-0002 decision 7's field-type set describes a
  shape, and inventing one to spell it would be a second proposal riding
  along with this one. So the field is a `:string` carrying a name, which
  is the only spelling of a declaration this package has anywhere today
  (`StatifierBlocks.Environment`'s `type_expr/0`), and no ninth field type
  is added.

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
  alias StatifierBlocks.Compiler.Context
  alias StatifierBlocks.Core.{Config, Emit}
  alias StatifierBlocks.Emission
  alias StatifierDatamodel.Declarations

  @outcomes ["abandon", "resume"]

  # The one spelling of the key, shared by the map's own validation and by
  # the payload refusal that reads the same pairs.
  @capture_key "capture"

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
        type: :string,
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
      }
    ]

  @impl true
  def validate_config(config) do
    []
    |> check_event(config)
    |> check_cond(config)
    |> check_outcome(config)
    |> check_payload(config)
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
          findings
        else
          [{"capture", capture_message()} | findings]
        end

      _other ->
        [{"capture", capture_message()} | findings]
    end
  end

  defp pair?({destination, source}), do: path?(destination) and path?(source)
  defp pair?(_other), do: false

  defp path?(value) do
    Config.non_empty_string?(value) and not Regex.match?(@whitespace, value)
  end

  defp capture_message do
    "must map each datamodel path written, like order.cancel_reason, " <>
      "to the path inside _event.data it is read from, like reason"
  end

  # The declaration is optional, so only a stored value that is not a
  # string at all is a finding here. Whether the name *resolves* is not
  # this function's question: a name the datamodel does not declare is
  # ADR-0002's P4 case - the undeclared payload, unchanged behaviour - and
  # a blank string is the field's own default, which is the editor's
  # spelling of "not declared".
  defp check_payload(findings, config) do
    case Map.get(config, "payload") do
      nil -> findings
      payload when is_binary(payload) -> findings
      _other -> [{"payload", "must name a declared type, or be left blank"} | findings]
    end
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
  """
  @spec payload_capture_findings(Block.config(), StatifierDatamodel.Declarations.t()) :: [
          {String.t(), String.t()}
        ]
  def payload_capture_findings(config, declarations) when is_map(declarations) do
    with payload when is_binary(payload) and payload != "" <- Map.get(config, "payload"),
         {:ok, declaration} <- Declarations.fetch(declarations, payload),
         pairs when is_map(pairs) <- Map.get(config, @capture_key),
         [_first | _rest] = offenders <- unread_pairs(pairs, declarations, declaration) do
      [{@capture_key, payload_message(payload, offenders)}]
    else
      _no_declaration_or_nothing_refused -> []
    end
  end

  # The pairs whose source path reads a member the payload does not carry,
  # in the destinations' sorted order - the same order the assigns are
  # emitted in, so a message that names several reads in the order the
  # bytes do. A pair `check_capture/2` has already refused is skipped:
  # one malformed pair is one finding, not two.
  @spec unread_pairs(map(), Declarations.t(), Declarations.declaration()) ::
          [{String.t(), String.t()}]
  defp unread_pairs(pairs, declarations, declaration) do
    for {destination, source} = pair <- Enum.sort(pairs),
        path?(destination) and path?(source),
        not carries?(declarations, declaration, String.split(source, ".")),
        do: pair
  end

  # P5's depth rule. The first segment is checked against the declaration's
  # field names; a deeper one is checked only where the field's own type
  # resolves to another declaration. A field typed as a scalar, an opaque
  # string, a list or nothing at all stops the walk and refuses nothing
  # beyond it, which is the stance `StatifierDatamodel.Types`' own read
  # check takes.
  @spec carries?(Declarations.t(), Declarations.declaration(), [String.t()]) :: boolean()
  defp carries?(declarations, declaration, [segment | rest]) do
    case field(declaration, segment) do
      nil -> false
      _field when rest == [] -> true
      field -> descend(declarations, field, rest)
    end
  end

  @spec descend(Declarations.t(), Declarations.field(), [String.t()]) :: boolean()
  defp descend(declarations, %{type: {:declared, name}}, rest) do
    case Declarations.fetch(declarations, name) do
      {:ok, declaration} -> carries?(declarations, declaration, rest)
      :error -> true
    end
  end

  defp descend(_declarations, _opaque_to_this_walk, _rest), do: true

  @spec field(Declarations.declaration(), String.t()) :: Declarations.field() | nil
  defp field(%{fields: fields}, name),
    do: Enum.find(fields, &(Map.get(&1, :name) == name))

  @spec payload_message(String.t(), [{String.t(), String.t()}]) :: String.t()
  defp payload_message(payload, offenders) do
    read =
      Enum.map_join(offenders, ", ", fn {destination, source} ->
        ~s("#{destination}" reads #{source})
      end)

    "reads past the declared payload: #{read}, and #{payload} carries no such member. " <>
      "Declare the member on #{payload}, correct the source path, or drop the payload " <>
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
  the queue is holding, and a nested group's handler is selected over an
  outer group's because SCXML prefers the transition whose source is the
  deepest active state.

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
  ahead of the `<raise>`:

      <state id="s_INT__armed">
        <transition event="order.cancelled" target="s_INT__done">
          <assign expr="_event.data.reason" location="order.cancel_reason"/>
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
    done = Context.done_id(context)

    with {:ok, armed} <- Context.role_id(context, "armed"),
         {:ok, outcome} <- outcome_event(Map.get(config, "outcome")),
         {:ok, event} <- event_name(Map.get(config, "event")),
         {:ok, assigns} <- captures(Map.get(config, "capture")) do
      watcher =
        Emit.state(armed, nil, [
          Emit.transition(
            [event: event, cond: guard(config), cond_key: "cond", target: done],
            assigns ++ [Emission.element("raise", [{"event", outcome}])]
          )
        ])

      {:ok, Emit.state(context.state_id, armed, [watcher, Emit.final(done)])}
    end
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
          Emission.element(
            "assign",
            [{"expr", "_event.data." <> source}, {"location", destination}]
          )
        end)

      {:ok, assigns}
    else
      {:error, [{"capture", capture_message()}]}
    end
  end

  defp captures(_other), do: {:error, [{"capture", capture_message()}]}

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
