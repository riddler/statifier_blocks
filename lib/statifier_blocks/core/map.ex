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

  ## The four fields

  | Key | Type | What it names |
  |---|---|---|
  | `items` | `{:path, %{}}` | the datamodel path holding the descriptor list |
  | `chart` | `:string` | the document id of the chart run once per item |
  | `collect` | `{:path, %{}}` | where the assembled answer is written |
  | `on` | `{:select, ...}` | the aggregation policy, `all` or `first_error` |

  `items` and `collect` are declared `{:path, %{}}` - ADR-0002 decision
  7's eighth field type - so the editor offers the host's declared
  datamodel paths as candidates on both and gives a value the datamodel
  does not declare ADR-0005 clause 11e's `:info` advisory, which is a
  remark and not a refusal. `collect` accepts what `core.subchart`'s
  `assign_to` accepts, refused with the same wording: a bare lowercase
  identifier. Two spellings of the same complaint would suggest an author
  had met two fields.

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
  and the three fields whose values reach a quoted expression refuse a
  single quote in `validate_config/1` - a value that closed the literal
  early would compile to something the author did not write.

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
  alias StatifierBlocks.Core.{Config, Emit}
  alias StatifierBlocks.Emission

  @invoke_type "statifier_blocks:map"

  @error_event "error.communication.invoke"
  @done_event "done.invoke"

  @done_slot "on_done"
  @error_slot "on_error"

  @default_on "all"
  @policies ["all", "first_error"]

  @chart_message ~s(names the document to run for each item, like bdoc_01JWIZ)
  @items_message "names the datamodel list to run over, like signup.invitees"
  @collect_message "must be a bare lowercase identifier, like answers"
  @on_message ~s(must be "all" or "first_error")

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
  def outcomes(_config), do: [{"done", "Done"}, {"error", "Error"}]

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
        key: "collect",
        type: {:path, %{}},
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
  The four fields' findings, and nothing about N.

  `on` is read through its default, so a config that never carried the
  key validates exactly as it did before the key existed; a stored `null`
  is not an absent key and is refused (ADR-0001 decision 6).
  """
  @impl true
  def validate_config(config) do
    []
    |> check_items(config)
    |> check_chart(config)
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

  defp check_collect(findings, config) do
    case Map.get(config, "collect") do
      blank when blank in [nil, ""] ->
        findings

      value ->
        if Config.identifier?(value),
          do: findings,
          else: [{"collect", @collect_message} | findings]
    end
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

  An absent `on_error` slot emits no failure transition and no `error`
  `<final>`, exactly as `core.invoke` has it: outcome wiring is an event
  rather than a target, so a parent may transition on an outcome whose
  final was never emitted and the transition simply never fires (ADR-0004
  2c). An absent `on_done` slot is the ordinary case and routes straight
  to the `done` final.

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
         {:ok, collect} <- collect(Map.get(config, "collect")),
         {:ok, on} <- on(config),
         {:ok, error_parts} <- error_parts(context) do
      call =
        "invoke"
        |> Emission.element(
          [{"id", context.block_id}, {"src", chart}, {"type", @invoke_type}],
          params(items, chart, collect, on)
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

  # ADR-0009 decision 3: the params carry the *list's path*, not the list
  # and not N copies of an item, so the emitted bytes are the same over
  # any N. `collect` is omitted when the author declared none, which is
  # decision 7 clause 3's supported shape rather than an empty string the
  # handler would have to read as absence.
  @spec params(String.t(), String.t(), String.t() | nil, String.t()) :: [Emission.t()]
  defp params(items, chart, collect, on) do
    [
      literal_param("items", items, "items"),
      literal_param("chart", chart, "chart")
    ] ++
      collect_param(collect) ++
      [literal_param("on", on, "on")]
  end

  defp collect_param(nil), do: []
  defp collect_param(location), do: [literal_param("collect", location, "collect")]

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

  @spec error_parts(Context.t()) ::
          {:ok, nil | {Context.child_summary(), String.t()}}
          | {:error, {:invalid_outcome, Block.id(), String.t()}}
  defp error_parts(context) do
    case Context.children(context, @error_slot) do
      [] ->
        {:ok, nil}

      [child | _rest] ->
        with {:ok, final} <- Context.outcome_id(context, "error") do
          {:ok, {child, final}}
        end
    end
  end

  defp failure_transition(nil), do: []

  defp failure_transition({child, _final}),
    do: [Emit.transition(event: @error_event, target: child.state_id)]

  defp error_children(nil), do: []
  defp error_children({child, final}), do: chain(child, final)

  defp error_final(nil), do: []
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
  defp collect(value) when value in [nil, ""], do: {:ok, nil}

  defp collect(value) do
    if Config.identifier?(value),
      do: {:ok, value},
      else: {:error, [{"collect", @collect_message}]}
  end

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
