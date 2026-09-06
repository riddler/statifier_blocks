defmodule StatifierBlocks.Core.Map do
  @moduledoc """
  `core.map`: a step that runs **another chart once per item** of a
  datamodel list, all of them at once, and waits for the whole batch
  (ADR-0009, accepted 2026-09-01).

  It is a sibling of `core.subchart`, not a mode of it, and it is not
  `core.foreach` with a flag. ADR-0009 decision 1 is why: `core.foreach`
  is SCXML's synchronous loop, compiled into the parent chart, and a
  fan-out is N concurrent runs that may outlive the process that started
  them. One type meaning both would make the execution model conditional
  on a config value.

  ## One `<invoke>`, whatever N turns out to be

  Decision 3: a compiled `core.map` carries exactly **one** `<invoke>` -
  one entry in `active_invocations`, one `done.invoke.<block id>`, one
  `error.communication.invoke.<block id>` route - and the **handler** is
  what reads the list and starts the children. The compiled bytes do not
  scale with N and cannot: N is a runtime value, and a compile of one
  document never sees it. That is what keeps ADR-0004 decision 6's byte
  determinism intact - the same document compiles to the same bytes over
  three items and over three thousand.

  It follows that this type validates **nothing** about N (campaign-031
  ruling `D31-9`, recorded as ADR-0009's 2026-09-05 Tier A note). A bound
  on the batch, if measurement forces one, is a configuration key of the
  fan-out runtime with a runtime refusal on the ordinary error route -
  never a compile finding here, because the value a bound would apply to
  does not exist at compile time. Nothing in this package imports or knows
  about the runtime that enforces it.

  ## `items` are descriptors, and the handler resolves them

  The `items` field names a datamodel path, and the path is carried into
  the invocation **as a path** - a quoted literal in the `<param>` - so
  the handler evaluates it at the point it fans out. ADR-0009's second
  2026-09-05 note is the discipline that goes with it: the list holds
  **descriptors** - ids, ranges, chunk handles - never row payloads. The
  parent's datamodel is serialized on every persisted step for the rest of
  the run, so a fan-out over ten thousand order ids costs what ids cost,
  and one over ten thousand order records charges the parent for those
  records forever.

  ## The invoke type is a constant, and a different one from a subchart's

  `invoke_type/0` returns `"statifier_blocks:map"`, in the shape
  `core.subchart`'s constant has: one definition site, never a config
  field, because *which handler starts children* is deployment state
  rather than authoring state (st-ADR-0051). It is deliberately a
  different string from `"statifier_blocks:subchart"` (decision 3): a host
  that wired a single-child subchart handler has not thereby wired a
  fan-out handler, and a document that reached such a host should fail to
  find a handler rather than quietly start one child.
  `StatifierBlocks.Compiler.InvokeTypes` reports that gap at the one
  moment a caller holds both registries; nothing has to be registered
  there for it to, because that pass reads emitted `<invoke type>` strings
  rather than a list of known types.

  ## Two outcomes, fixed

  `done` and `error`, declared here rather than derived from the child
  chart. `core.subchart` takes its outcomes from the chart it names,
  because one child reports one outcome and an author can branch on it. N
  children report N outcomes, and joining them into one branch target has
  no meaning - "seven approved and one declined" is data, not control flow
  (decision 4). So the per-child answers go where data goes, into
  `collect`, and the block's own outcome says only whether the fan-out as
  a whole succeeded. An author who wants to branch on the answers reads
  the collected list with a `core.branch` after the block.

  ## The six fields

  | Key | Type | What it names |
  |---|---|---|
  | `items` | `{:path, %{}}` | the datamodel path holding the descriptor list |
  | `chart` | `:string` | the document id of the chart run once per item |
  | `item_as` | `:string` | the name a child sees its item under, default `item` |
  | `index_as` | `:string` | the name a child sees its position under, when the author wants one |
  | `collect` | `{:path, %{writes: {:list, :unknown}}}` | where the assembled answer is written |
  | `on` | `{:select, ...}` | the aggregation policy, `all` or `first_error` |

  ## The names a child sees, and why they bind nothing here

  `item_as` and `index_as` are ADR-0009 decision 4's declared names for
  the item and its position, kept with the defaults `item` and `index` by
  ADR-0011 decision 11. They are the **child's** vocabulary: decision 3's
  `<param>` list carries them beside `items`, and the handler is what
  binds one item and one position per child run. Nothing in this document
  reads them, and this module declares no `<data>` root for either.

  That is the one place a reader coming from `core.foreach` has to slow
  down. A foreach's `item_as` and `index_as` are declared roots in *this*
  chart, written by the loop's own `<assign>`, so a block in its body
  reads them and the walk binds them there. A map has no body to bind
  into: ADR-0009 decision 3 is "a per-item chart, not a per-item body",
  and an inline body slot was considered there and deliberately not built.
  So `StatifierBlocks.Environment`'s fan-out binding - which fires for a
  block declaring a datamodel-path `items` field **and** carrying a slot
  called `body` - does not reach a `core.map`, and this block's only
  contribution to the environment stays the `collect` write of decision
  12. A name a child sees is bound in the child's own run, one document
  away from anything this walk can check.

  Two smaller consequences follow from the same fact. Neither name is a
  datamodel path, so neither draws ADR-0005 clause 11e's declared-path
  advisory and neither is offered path candidates. And neither can
  collide with an enclosing loop's binding the way `core.foreach`'s can
  (that check is `DeclaredRoots`', and there is no root here to collide),
  so the only cross-field rule this type carries is the foreach one that
  still means something: the item and its position cannot share one name,
  because the handler would bind the second over the first.

  `items` and `collect` are declared `{:path, opts}` - ADR-0002 decision
  7's eighth field type - so the editor offers the host's declared
  datamodel paths as candidates on both and gives a value the datamodel
  does not declare ADR-0005 clause 11e's `:info` advisory, which is a
  remark and not a refusal. `collect` is refused unless it is a datamodel
  path, the grammar ADR-0009 decision 4's Amendment of 2026-09-06 widened
  it to. The other three fields this package writes an
  `<assign location="...">` from - `core.invoke`'s and
  `StatifierBlocks.InvokeStep`'s `assign_to`, and `core.subchart`'s -
  read the same `StatifierBlocks.Core.Config.datamodel_path?/1` since
  ADR-0011 decision 13 and `sb-r313`, so all four now agree: the same
  `<assign>` element writes the same datamodel, so there is one location
  rule to have. The shape of all four refusals is shared in
  `StatifierBlocks.Core.AssignLocation`, and now the rule is shared too. A
  bare lowercase identifier is still a valid `collect` - every one of them
  is already a datamodel path - so the widening refuses nothing the field
  accepted before.

  `collect` carries the `writes` key ADR-0002's Note of 2026-09-06
  records, and what it writes is `{:list, :unknown}` (ADR-0011 decision
  12): the assembled answer is a list, dense and in item-index order per
  ADR-0009 decision 5, and this block says nothing about what one element of
  it holds, because the shipped child recipe emits the outcome name and
  nothing else. A block after a `core.map` therefore knows it is looking
  at a list - which is more than it knew before - and knows nothing about
  an element, which is exactly true. `items` carries neither key, so
  ADR-0011 decision 2 reads it as writing `:unknown` at the path it names:
  known without becoming typed.

  `on` is read **through its default**, in `core.parallel`'s G7a shape: an
  absent key reads as `"all"` everywhere, so a block an author never
  opened the field on compiles identically. A stored `null` is not an
  absent key and is refused (ADR-0001 decision 6). Decision 6 reserves the
  **word** `quorum` by refusing everything outside the two permitted
  values, so no host can establish a private meaning for it before its own
  walk happens.

  `all` waits for every child to settle and a child failing is data at its
  index rather than a route to `error`; `first_error` cancels the live
  siblings and routes `error`. The runtime is what implements either, and
  it reads the policy off the `on` param verbatim.

  ## What it compiles to

      <state id="s_blk_INV" initial="s_blk_INV__running">
        <state id="s_blk_INV__running">
          <invoke id="blk_INV" src="bdoc_CHILD" type="statifier_blocks:map">
            <param expr="'signup.invitees'" name="items"/>
            <param expr="'bdoc_CHILD'" name="chart"/>
            <param expr="'invitee'" name="item_as"/>
            <param expr="'position'" name="index_as"/>
            <param expr="'answers'" name="collect"/>
            <param expr="'all'" name="on"/>
          </invoke>
          <transition event="done.invoke" target="s_blk_INV__o_done">
            <assign expr="_event.data" location="answers"/>
          </transition>
          <transition event="error.communication.invoke" target="s_blk_PARK"/>
        </state>
        ...
      </state>

  Three things about those bytes are worth saying out loud.

  **`src` carries the document id verbatim**, as ADR-0004's subchart-`src`
  amendment has it, which is also what puts a `core.map` under
  `StatifierBlocks.Compiler.SelfReference`: that pass classifies by
  SCXML's own semantics rather than by block type, so a map naming the
  document it sits in is refused with no edit there.

  **Every `<param>` carries a literal, not an expression.** The handler
  evaluates `items`; the parent does not. So each value is emitted quoted,
  and every field whose value reaches a quoted expression is refused a
  single quote in `validate_config/1` - a value that closed the literal
  early would compile to something the author did not write. `item_as` and
  `index_as` are identifiers, so their own rule already excludes it.

  **`item_as` is emitted through its default and `index_as` only when the
  author named one.** `on`'s G7a shape, for `on`'s reason: a stored config
  from before either key existed reads as `item` and no position name, so
  it validates exactly as it did and nothing has an older shape to migrate
  from (`current_version` stays `1`). What it does *not* do is stay
  byte-identical: a document compiled before this type carried the names
  gains the `item_as` param, because ADR-0009 decision 3 says the param
  list carries them and until now it did not.

  **`chart` is emitted twice**, as `src` and as a param. `src` is decision
  3's requirement and is what the self-reference pass and a reading host
  see; the param is what the handler reads beside the other three, so a
  handler needs one place to look rather than two. They are the same
  verbatim string, stamped with the same provenance.

  ## Where the answer is written

  Decision 5: the whole result is one list at one author-named location,
  one element per item, in **item index order**, dense - errors sit at
  their own index, and under `first_error` cancelled siblings sit at
  theirs. Ordering by index rather than by completion is what makes the
  result a function of the input: completion order is not reproducible
  across a restart or a change of concurrency bound.

  The write happens once, at the invocation's completion: the `<assign>`
  sits on the success transition, in the shape ADR-0007 decision 2
  describes for a leaf step and `core.subchart` already emits. `collect`
  is optional and omitting it is supported (decision 7 clause 3) - a
  fan-out whose answers the parent does not need accumulates nothing, and
  nothing else about the block changes.

  ## What this type does not do

  It runs nothing. ADR-0002 decision 2's two-registry seam holds here as
  it does for `core.invoke` and `core.subchart`: this type **names** an
  invoke type, and a handler the host registers per session is what fans
  out. It imports nothing from the durable runtime packages, it mints no
  effect and no event name, and it takes no position on how child starts
  are batched or bounded - that is the fan-out runtime's record, cited by
  ADR-0009 decision 9 and not restated here.
  """

  @behaviour StatifierBlocks.BlockType

  alias StatifierBlocks.Block
  alias StatifierBlocks.Compiler.Context
  alias StatifierBlocks.Core.{AssignLocation, Config, Emit}
  alias StatifierBlocks.Emission

  @invoke_type "statifier_blocks:map"

  @error_event "error.communication.invoke"
  @done_event "done.invoke"

  @done_slot "on_done"
  @error_slot "on_error"
  @error_outcome "error"

  @default_on "all"
  @policies ["all", "first_error"]

  @default_item_as "item"

  @chart_message ~s(names the document to run for each item, like bdoc_01JWIZ)
  @items_message "names the datamodel list to run over, like signup.invitees"
  @collect_message "must be a datamodel path, like cards.answers"
  @on_message ~s(must be "all" or "first_error")
  @item_as_message "must be a bare lowercase identifier, like invitee"
  @index_as_message "must be a bare lowercase identifier, like position"
  @distinct_message "the item and its position cannot share one name"

  @impl true
  def current_version, do: 1

  @doc """
  The invoke type every `core.map` emits: the host-registered fan-out
  type.

  A constant rather than a config field, for `core.subchart`'s reason -
  which handler starts children is deployment state (st-ADR-0051) - and a
  *different* constant from that one, for ADR-0009 decision 3's: wiring a
  single-child handler is not wiring a fan-out handler.
  """
  @spec invoke_type() :: String.t()
  def invoke_type, do: @invoke_type

  @doc """
  Two `zero_or_one` slots, `on_done` then `on_error`, one per outcome
  (ADR-0009 decision 4).

  Arity is `zero_or_one` for `core.invoke`'s reason: an outcome path is
  one continuation, not a list of them, and an author who wants several
  steps there puts a `core.sequence` in it.
  """
  @impl true
  def slots(_config),
    do: [
      {@done_slot, :zero_or_one, "When the batch is done"},
      {@error_slot, :zero_or_one, "If the batch fails"}
    ]

  @doc """
  `done` and `error`, fixed rather than config-derived (ADR-0009 decision
  4). The moduledoc says why N children cannot hand a parent one outcome
  to branch on.
  """
  @impl true
  def outcomes(_config), do: [{"done", "Done"}, {@error_outcome, "Error"}]

  @doc """
  `error` is failure-classed: a batch that ended on the error route is a
  batch that finished badly (the campaign-033 failure seam, 2026-09-06).

  ADR-0009 decision 4's outcome set is untouched by this - there are still
  exactly two outcomes, `done` and `error`, and the class is a second axis
  on `error` rather than a third outcome. Nor does it change what decision
  5's `collect` holds: the per-child answers are still data, one element
  per item in index order, and an author still branches on them with a
  `core.branch` after the block. What the class changes is the
  top-level `<final>` for `error`: it carries the reserved `<donedata>`
  `<param>` that tells a durable stepper the run failed, so a fan-out that
  ended badly settles its parent's invocation instead of completing
  quietly. For a document whose **root** block is a `core.map` that is the
  root's own outcome final; from ADR-0002's amendment of 2026-09-06
  (sections 2 and 4) a `core.map` **below** the root whose `on_error` slot
  is empty reaches the document's shared failed final too, and one whose
  slot is occupied is handled and reaches nothing above the block.
  """
  @impl true
  def failure_outcomes(_config), do: [@error_outcome]

  @impl true
  def config_schema(_config),
    do: [
      %{
        key: "items",
        type: {:path, %{}},
        label: "Over these items",
        required?: true,
        default: ""
      },
      %{
        key: "chart",
        type: :string,
        label: "Run this chart for each",
        required?: true,
        default: ""
      },
      %{
        key: "item_as",
        type: :string,
        label: "Call the item",
        required?: true,
        default: @default_item_as
      },
      %{
        key: "index_as",
        type: :string,
        label: "Call the position (optional)",
        required?: false,
        default: ""
      },
      %{
        key: "collect",
        type: {:path, %{writes: {:list, :unknown}}},
        label: "Collect the answers into",
        required?: false,
        default: ""
      },
      %{
        key: "on",
        type:
          {:select,
           [
             {"all", "All - wait for every item, whatever each one answers"},
             {"first_error", "First error - stop the rest as soon as one fails"}
           ]},
        label: "Finish",
        required?: false,
        default: @default_on
      }
    ]

  @doc """
  The six fields' findings, and nothing about N.

  `on` and `item_as` are read through their defaults, so a config that
  never carried either key validates exactly as it did before the key
  existed; a stored `null` is not an absent key and is refused (ADR-0001
  decision 6).

  The one cross-field check is `core.foreach`'s, and it earns its place
  here for the same reason it does there: two bindings that share a name
  read fine and mean nothing, since the handler binding the position
  would overwrite the item.
  """
  @impl true
  def validate_config(config) do
    []
    |> check_items(config)
    |> check_chart(config)
    |> check_item_as(config)
    |> check_index_as(config)
    |> check_distinct(config)
    |> check_collect(config)
    |> check_on(config)
    |> Config.verdict()
  end

  defp check_items(findings, config) do
    if reference?(Map.get(config, "items")) do
      findings
    else
      [{"items", @items_message} | findings]
    end
  end

  defp check_chart(findings, config) do
    if reference?(Map.get(config, "chart")) do
      findings
    else
      [{"chart", @chart_message} | findings]
    end
  end

  # Read through the default, `on`'s G7a shape: a config stored before
  # this key existed reads as `"item"` and validates as it did, and a
  # stored `null` reaches `identifier?/1` as the `nil` it is and is
  # refused.
  defp check_item_as(findings, config) do
    if Config.identifier?(item_as(config)) do
      findings
    else
      [{"item_as", @item_as_message} | findings]
    end
  end

  # The optional-field idiom `core.foreach` states for the same key: `""`
  # is this field's own default, which the config form writes into every
  # block of this type, so absent and empty are both silent.
  defp check_index_as(findings, config) do
    case Map.get(config, "index_as") do
      blank when blank in [nil, ""] ->
        findings

      value ->
        if Config.identifier?(value) do
          findings
        else
          [{"index_as", @index_as_message} | findings]
        end
    end
  end

  defp check_distinct(findings, config) do
    item_as = item_as(config)

    if Config.identifier?(item_as) and item_as == Map.get(config, "index_as") do
      [{"index_as", @distinct_message} | findings]
    else
      findings
    end
  end

  defp check_collect(findings, config) do
    AssignLocation.check(
      findings,
      config,
      "collect",
      &Config.datamodel_path?/1,
      @collect_message
    )
  end

  defp check_on(findings, config) do
    if Config.one_of(policy(config), @policies) do
      findings
    else
      [{"on", @on_message} | findings]
    end
  end

  @doc """
  A step with two outcomes, so `produces` is `:unknown` for `core.invoke`'s
  reason: joining what the call produces with what the `on_error` subtree
  produces is the lattice ADR-0003 decision 4 refuses to build.

  `consumes` is absent - a fan-out reads its input out of the datamodel
  through `items`, not through the type flow.
  """
  @impl true
  def io(_config),
    do: %{
      kinds: [:step],
      produces: :unknown,
      slot_accepts: %{@done_slot => [:step], @error_slot => [:step]}
    }

  @impl true
  def palette_entry,
    do: %{
      label: "For every item, run a chart",
      group: "Structure",
      description: "Runs another chart for every item in a datamodel list, all at once.",
      # `core.parallel`'s glyph, and the reuse is argued the way
      # `core.foreach` argues borrowing `core.resumable_group`'s: the
      # picture a reader needs here is several things running beside each
      # other, which is the one `view-columns` already draws. The
      # difference from `core.parallel` - lanes named at authoring time
      # against a count read out of the datamodel - is what the label and
      # the description carry.
      icon: "view-columns",
      keywords: ["map", "fan out", "fanout", "each", "every", "batch", "parallel", "chart"],
      order: 16,
      layout: :stack,
      slot_style: %{@error_slot => :failure}
    }

  @doc """
  A compound state that runs the whole batch as one invocation in an
  inner state and finishes at the `<final>` of whichever outcome it
  reached.

  The two transitions match `done.invoke` and `error.communication.invoke`
  by SCXML's descriptor prefix rule and name no invocation, which is safe
  for `core.invoke`'s reason: both sit on the inner state, active only
  while this block's own call is outstanding. The `<invoke>` still carries
  an explicit `id` of the block's own id (ADR-0004 C3), so a parent
  running two fan-outs at once can tell their completions apart by a value
  it knows at compile time.

  An absent `on_error` slot still ends the block on `error`, exactly as
  `core.invoke` has it: ADR-0002's amendment of 2026-09-06 section 2 emits
  a failure-classed outcome's `<final>` whether or not its slot is
  occupied, because the class is read off the final, and with the slot
  empty the failure transition targets that final directly. An absent
  `on_done` slot is the ordinary case and routes straight to the `done`
  final.

  ## Who owns what

  Everything here is this block's except one transition per occupied
  slot: the one leaving a slot's child for that outcome's final is
  attributed to **that child**, because what happens after the parking
  step finishes is a fact about the child (ADR-0004 decision 5). The
  `src` attribute's value is stamped as coming from `chart` and the
  `location`'s from `collect`, and each `<param>` from the field it
  carries, so an upstream finding inside one is the author's typo rather
  than a bug in this type.
  """
  @impl true
  def emit(%Block{config: config}, context) do
    with {:ok, running} <- Context.role_id(context, "running"),
         {:ok, done_final} <- Context.outcome_id(context, "done"),
         {:ok, chart} <- chart(Map.get(config, "chart")),
         {:ok, items} <- items(Map.get(config, "items")),
         {:ok, item_as} <- item_as_value(config),
         {:ok, index_as} <- index_as_value(config),
         {:ok, collect} <- collect(Map.get(config, "collect")),
         {:ok, on} <- on(config),
         {:ok, error_parts} <- error_parts(context) do
      call =
        "invoke"
        |> Emission.element(
          [{"id", context.block_id}, {"src", chart}, {"type", @invoke_type}],
          params(items, chart, item_as, index_as, collect, on)
        )
        |> Emission.attribute_from_config("src", "chart")

      done_child = context |> Context.children(@done_slot) |> List.first()
      done_target = if done_child, do: done_child.state_id, else: done_final

      inner =
        Emit.state(running, nil, [
          call,
          Emit.transition([event: @done_event, target: done_target], assign(collect))
          | failure_transition(error_parts)
        ])

      children =
        [inner] ++
          chain(done_child, done_final) ++
          error_children(error_parts) ++
          [Emit.final(done_final)] ++ error_final(error_parts)

      {:ok, Emit.state(context.state_id, running, children)}
    end
  end

  # ADR-0009 decision 3: the params carry the *list's path* and the names
  # the child sees, not the list and not N copies of an item, so the
  # emitted bytes are the same over any N. `index_as` and `collect` are
  # omitted when the author declared neither, which is decision 7 clause
  # 3's supported shape rather than an empty string the handler would have
  # to read as absence.
  @spec params(
          String.t(),
          String.t(),
          String.t(),
          String.t() | nil,
          String.t() | nil,
          String.t()
        ) :: [Emission.t()]
  defp params(items, chart, item_as, index_as, collect, on) do
    [
      literal_param("items", items, "items"),
      literal_param("chart", chart, "chart"),
      literal_param("item_as", item_as, "item_as")
    ] ++
      optional_param("index_as", index_as) ++
      optional_param("collect", collect) ++
      [literal_param("on", on, "on")]
  end

  defp optional_param(_name, nil), do: []
  defp optional_param(name, value), do: [literal_param(name, value, name)]

  # A `<param>` carrying a literal, for a value the handler reads rather
  # than one the parent evaluates. `config_key` is stamped as the
  # provenance of the value, so a finding inside it points at the
  # author's field and not at this module.
  @spec literal_param(String.t(), String.t(), String.t()) :: Emission.t()
  defp literal_param(name, value, config_key) do
    "param"
    |> Emission.element([{"expr", "'" <> value <> "'"}, {"name", name}])
    |> Emission.from_config(config_key)
  end

  # ADR-0002's amendment of 2026-09-06 section 2: the `error` final is
  # always minted and always emitted; the slot decides only what the
  # failure transition points at and whether a child subtree sits between
  # the transition and the final.
  @spec error_parts(Context.t()) ::
          {:ok, {Context.child_summary() | nil, String.t()}}
          | {:error, {:invalid_outcome, Block.id(), String.t()}}
  defp error_parts(context) do
    with {:ok, final} <- Context.outcome_id(context, @error_outcome) do
      {:ok, {context |> Context.children(@error_slot) |> List.first(), final}}
    end
  end

  defp failure_transition({nil, final}),
    do: [Emit.transition(event: @error_event, target: final)]

  defp failure_transition({child, _final}),
    do: [Emit.transition(event: @error_event, target: child.state_id)]

  defp error_children({child, final}), do: chain(child, final)

  defp error_final({_child, final}), do: [Emit.final(final)]

  # The slot child's subtree, and the transition out of it into that
  # outcome's final - attributed to the child, per ADR-0004 decision 5.
  @spec chain(Context.child_summary() | nil, String.t()) :: [Emission.node_t()]
  defp chain(nil, _final), do: []

  defp chain(child, final) do
    [
      Emission.child_ref(child.block_id),
      [event: child.done_event, target: final, internal: true]
      |> Emit.transition()
      |> Emission.attributed_to(child.block_id)
    ]
  end

  # Decision 5: the write happens once, at the invocation's completion,
  # so the `<assign>` sits on the success transition rather than in a
  # `<finalize>` - the answers are only answers when the batch answered.
  @spec assign(String.t() | nil) :: [Emission.t()]
  defp assign(nil), do: []

  defp assign(location) do
    [
      "assign"
      |> Emission.element([{"expr", "_event.data"}, {"location", location}])
      |> Emission.attribute_from_config("location", "collect")
    ]
  end

  @spec chart(term()) :: {:ok, String.t()} | {:error, [{String.t(), String.t()}]}
  defp chart(value) do
    if reference?(value), do: {:ok, value}, else: {:error, [{"chart", @chart_message}]}
  end

  @spec items(term()) :: {:ok, String.t()} | {:error, [{String.t(), String.t()}]}
  defp items(value) do
    if reference?(value), do: {:ok, value}, else: {:error, [{"items", @items_message}]}
  end

  @spec collect(term()) :: {:ok, String.t() | nil} | {:error, [{String.t(), String.t()}]}
  defp collect(value) do
    AssignLocation.location(value, "collect", &Config.datamodel_path?/1, @collect_message)
  end

  @spec item_as_value(Block.config()) :: {:ok, String.t()} | {:error, [{String.t(), String.t()}]}
  defp item_as_value(config) do
    value = item_as(config)

    if Config.identifier?(value),
      do: {:ok, value},
      else: {:error, [{"item_as", @item_as_message}]}
  end

  @spec index_as_value(Block.config()) ::
          {:ok, String.t() | nil} | {:error, [{String.t(), String.t()}]}
  defp index_as_value(config) do
    case Map.get(config, "index_as") do
      blank when blank in [nil, ""] ->
        {:ok, nil}

      value ->
        if Config.identifier?(value),
          do: {:ok, value},
          else: {:error, [{"index_as", @index_as_message}]}
    end
  end

  # The name the child sees its item under, read through the default so an
  # absent key means `"item"` and a stored `null` stays the `nil` that
  # `identifier?/1` refuses.
  @spec item_as(Block.config()) :: term()
  defp item_as(config), do: Map.get(config, "item_as", @default_item_as)

  @spec on(Block.config()) :: {:ok, String.t()} | {:error, [{String.t(), String.t()}]}
  defp on(config) do
    value = policy(config)

    if Config.one_of(value, @policies), do: {:ok, value}, else: {:error, [{"on", @on_message}]}
  end

  # Read through the default, `core.parallel`'s G7a shape: an absent key
  # is `"all"`, and a stored `null` is handed on as the `nil` it is so
  # `one_of/2` refuses it.
  @spec policy(Block.config()) :: term()
  defp policy(config), do: Map.get(config, "on", @default_on)

  # Deliberately loose, for the reason `core.invoke`'s path check and
  # `core.subchart`'s chart check are: this package owns neither the
  # host's document-id grammar nor the datamodel path grammar, and a
  # tighter rule here would be a second, quieter proposal about either.
  # The one addition is the single quote, and it is not a grammar claim:
  # both values are emitted inside a quoted expression literal (the
  # handler evaluates `items`, not the parent), so a value carrying one
  # would close the literal early and compile to something the author did
  # not write.
  @spec reference?(term()) :: boolean()
  defp reference?(value) do
    Config.non_empty_string?(value) and
      not String.contains?(value, " ") and
      not String.contains?(value, "'")
  end
end
