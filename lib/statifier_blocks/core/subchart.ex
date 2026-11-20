defmodule StatifierBlocks.Core.Subchart do
  @moduledoc """
  `core.subchart`: a step that runs **another chart** and waits for it to
  finish, routing on the outcome that chart finished with (ADR-0004's
  2026-08-29 amendment, C1 through C3).

  This type **names** a chart and an invoke type; it never runs either.
  A subchart is not a new execution mechanism - it is a particular invoke
  whose handler happens to start a child session, so it stands on the same
  two-registry seam `core.invoke` does (ADR-0002 decision 2,
  statifier-ex ADR-0051).

  ## The child is a reference, never a body

  A document is a tree and a chart is a build product of one, so a
  subchart whose body lived inside the parent would be a second copy of a
  document that already exists on its own, with its own id, its own
  revision and its own runs. The child is therefore **named** by the
  `chart` config field and this type declares no body slot at all.

  ## How a child's outcome reaches the parent

  Raised events are internal to the session that raises them, so
  `done.outcome.<state id>.<outcome>` - the event ADR-0004's outcome
  amendment gives a block - does not cross an `<invoke>`. What a parent
  observes is the completion event and the data the child chose to send
  with it (SCXML 3.7 and 5.5). C1 fixes the child half: a document
  compiled **for use as a child** (`StatifierBlocks.Compiler`'s
  `:child_use` option) emits one top-level `<final>` per root-block
  outcome, carrying `<donedata><param name="outcome" expr="'<outcome>'"/>`.
  C2 fixes this half: the block's state routes `done.invoke` on
  `_event.data.outcome`, one conditioned transition per declared outcome
  and an **unconditioned one last** as the default path.

  ### The condition is `===`, not `==`

  Statifier's `==` against an absent `_event.data.outcome` is non-boolean
  and raises a spurious `error.execution` beside the default arm's routing
  (pinned upstream in statifier-ex); `===` is clean, and an explicit `nil` donedata
  reads as `null` rather than as undefined. So the conditioned transitions
  are written `_event.data.outcome === '<outcome>'`. The record fixes the
  routing, not the operator; this is the campaign's recorded ruling on
  which operator expresses it.

  ## Which outcomes, and where the author says so

  A block type cannot read the document it references - `emit/2` is a pure
  function of its block and its context, and the context deliberately
  carries no palette and no other document. So the outcomes the referenced
  chart declares are **declared here**, in the `outcomes` config field, one
  name per line, in the order they should be routed. A subchart that
  declares none has the one outcome an ordinary block has, `done`.

  The failure outcome `error` is appended to whatever the author declared,
  unless they declared it themselves - a child chart may well finish with
  an outcome it calls `error`, and then the two are one outcome with one
  final and one slot rather than two spellings of the same thing.

  ## What the host knows that this type cannot

  The paragraph above is a statement about what a *compile of one
  document* can see. A **host** sees more: it holds every stored document,
  so it knows which of them it compiles with `:child_use` and what finals
  each of those emits. Two things follow, and both are the editor's rather
  than this type's.

    * The editor offers those finals as candidates on the `outcomes`
      field, keyed on the document id in `chart`, from the host's
      `chart_outcomes` assign. It is a `<datalist>` on a field that is
      still a `:string`: a free-typed name validates exactly as it did.
    * `StatifierBlocks.ViewModel.outcome_findings/3` reports a
      **disagreement** between what the author declared here and what the
      host says that chart finishes with, anchored on this key.

  The comparison is against `child_outcomes/1` - the author's own list -
  and not `outcome_names/1`, because the appended failure outcome is
  ADR-0068's event rather than a `<final>` the child reports, and a child
  chart is not expected to have one. A ref the host said nothing about
  produces nothing: *unknown is not disagreement*, which is ADR-0005
  amendment `11f`'s posture for the datamodel repeated here for the same
  reason.

  None of it constrains. The disagreement is a `:warning`, not an error:
  the document compiles either way, and what a mismatch actually costs is
  a conditioned transition that can never match - a routing arm that is
  dead rather than wrong. `validate_config/1` is untouched, because this
  type still cannot read the chart it names.

  ## Every outcome gets a slot, `on_error` included

  An outcome path is a **slot**, never a port (ADR-0002's amendment
  A2): every edge in a document is a parent/slot/child relationship, which
  is the invariant the editor's rendered connectors rest on. So each
  declared outcome gets one `zero_or_one` slot, `on_<outcome>`, holding
  what runs when the child finishes that way, and `on_error` is exactly
  `core.invoke`'s slot with exactly `core.invoke`'s `:failure` style - the
  same declaration for the same concept, not a second wording of it.

  A slot left empty is not a missing path: the routing transition simply
  targets that outcome's `<final>` directly, and the block finishes there.

  ## What it compiles to

      <state id="s_blk_ELIG" initial="s_blk_ELIG__running">
        <state id="s_blk_ELIG__running">
          <invoke id="blk_ELIG" src="bdoc_CHILD" type="statifier_blocks:subchart"/>
          <transition cond="_event.data.outcome === 'done'"
                      event="done.invoke" target="s_blk_ELIG__o_done"/>
          <transition cond="_event.data.outcome === 'abandoned'"
                      event="done.invoke" target="s_blk_ELIG__o_abandoned"/>
          <transition event="done.invoke" target="s_blk_ELIG__o_done"/>
          <transition event="error.communication.invoke" target="s_blk_PARK"/>
        </state>
        ...
      </state>

  `<invoke>` carries an explicit `id` (C3) so `_event.invokeid` is static
  and a parent running subcharts in parallel can tell its concurrent
  children apart by a value it knows at compile time. The id is the
  **block's own id**, which ADR-0001 already guarantees is document-unique
  and never reused, so nothing new has to be minted or kept unique.

  Both `done.invoke` transitions and the `error.communication.invoke` one
  match by SCXML's descriptor prefix rule and name no invocation, which is
  safe for `core.invoke`'s reason: they sit on the inner state, active only
  while this block's own call is outstanding.

  ## Where the outcome is written

  `assign_to` names a location in the host's datamodel, so it is declared
  a `{:path, %{}}` field - ADR-0002 decision 7's eighth field type, added
  by its 2026-09-05 amendment, which names this field as the one core
  field that held a path and declared nothing about it. Two things follow
  and a third deliberately does not:

    * the editor offers the declared datamodel paths as candidates, drawn
      from `StatifierBlocks.Datamodel.candidates/3`; and
    * a value the datamodel does not declare gets ADR-0005 clause 11e's
      `:info` advisory anchored on the `assign_to` key, which is a remark
      and not a refusal.

  **The field accepts a datamodel path** (ADR-0011 decision 13): any
  non-empty string with no whitespace in it, which is exactly what
  `core.assign` accepts for the path it writes, read out of one
  internal datamodel-path predicate. `validate_config/1` and
  `emit/2` are widened together, because the emission has to answer for a
  config the validation would have rejected.

  It is a widening and nothing else: a bare identifier is a one-segment
  path, so every document written before this type existed keeps
  validating and keeps compiling to the same bytes, and `emit/2` still
  writes the author's string verbatim into the `<assign>`'s `location`.
  What it settles is that the field no longer refuses the dotted paths its
  own candidate list offers - a control that offers what its validation
  refuses is a defect either way round. The identical refusal on an
  `<assign>` location elsewhere in the vocabulary is untouched: that
  decision was ruled about this field, and widening the others on the
  strength of one field's argument is a sweep it did not make.

  ## What `src` names, and what it does not

  The emitted `src` is the **document id** the author typed into `chart`,
  and nothing else (ADR-0004's subchart-src amendment). It is *not*
  statifier-ex ADR-0052 chart identity: that identity is a hash of emitted
  bytes, so it moves every time the child is republished and cannot be
  known when the parent is authored. A document id is the stable
  authoring-time reference, and the host's handler registered under
  `statifier_blocks:subchart` (st-ADR-0051) resolves it to whichever
  chart the host currently publishes for that document. Pinning a
  *particular* child revision at publish time is a host provenance
  concern, carried in run metadata; the compiler does not do it.

  One thing a compile of one document can decide about that id, and it
  does: a subchart may not name the document it sits in. See
  `StatifierBlocks.Compiler.SelfReference`, which also says why a cycle
  through two or more documents is the host resolver's to refuse.

  ## Naming the child from data: `chart_from`

  A block names its child by exactly one of two keys (ADR-0004's
  Amendment of 2026-11-19, J1). `chart` is the literal document id above.
  `chart_from` is a datamodel path, in the grammar `assign_to` takes,
  whose value when the invocation starts is the document id to run; it is
  written verbatim as the `<invoke>`'s `srcexpr` in place of `src`, and
  stamped as coming from `chart_from` so a finding inside it anchors on
  the field the author typed. Both keys non-empty is one finding on
  `chart_from`; neither is the finding `chart` has always raised. An empty
  string reads as absent.

      <invoke id="blk_SETUP" srcexpr="onboarding.setup_document"
              type="statifier_blocks:subchart">
        <param expr="'done skipped error'" name="statifier_blocks:outcomes"/>
      </invoke>

  A `chart_from` block's `<invoke>` carries one more `<param>` after the
  author's `params` rows (J2): `statifier_blocks:outcomes`, a single-quoted
  string of `outcome_names/1` joined by single spaces. The handler reads
  the block's declared outcomes from it, because neither handler's context
  carries the parent document, and removes it before the child is started,
  so it never reaches the child's datamodel. A block naming its child by
  `chart` emits no such param, which is how the literal form keeps the
  bytes it always had and how the handler tells the two forms apart.

  The engine evaluates the path when the invocation starts. A path that
  fails to evaluate raises `error.execution` and calls no handler; one
  that evaluates to anything but a string is refused `unknown_document`
  by the handler without the host's resolver being called; any string is
  the host's `resolve_chart/2` to answer.

  The compile-time checks that need the id stay with `chart`: the
  self-reference refusal reads `src` only (J4), and the compile records a
  child reference only for a block that names a literal `chart`, so the
  publish-time graph checks have nothing to judge for a `chart_from`
  block (J5).

  `io/1` is unchanged for a `chart_from` block: the path is not reported
  as a read for the typed environment, the same reading the block already
  gives its `params` paths, and its value is a document id rather than a
  datum the chart computes with.
  """

  @behaviour StatifierBlocks.BlockType

  alias StatifierBlocks.Block
  alias StatifierBlocks.Compiler.Context
  alias StatifierBlocks.Core.{AssignLocation, Config, Emit, Invoke}
  alias StatifierBlocks.Emission

  @invoke_type "statifier_blocks:subchart"

  @error_outcome "error"
  @error_event "error.communication.invoke"
  @done_event "done.invoke"

  @slot_prefix "on_"

  @default_outcome "done"

  @outcomes_param "statifier_blocks:outcomes"

  @impl true
  def current_version, do: 1

  @doc """
  The invoke type every `core.subchart` emits: the host-registered
  child-chart invoke type.

  It is a constant rather than a config field because *which handler*
  starts a child session is deployment state, not authoring state
  (st-ADR-0051): an author picks a chart, and the host registers one
  handler that knows how to run one. A host that registers nothing under
  this name gets the ordinary two-registry lint
  (`StatifierBlocks.Compiler.InvokeTypes`) rather than a runtime surprise,
  which is the whole point of naming it here where the lint can see it.
  """
  @spec invoke_type() :: String.t()
  def invoke_type, do: @invoke_type

  # The reserved `<param>` name a `chart_from` block's `<invoke>` carries
  # its declared outcomes on (ADR-0004's Amendment of 2026-11-19, J2): the
  # one definition site, read by the runtime handlers that remove it.
  @doc false
  @spec outcomes_param() :: String.t()
  def outcomes_param, do: @outcomes_param

  @doc """
  One `zero_or_one` slot per declared outcome, named `on_<outcome>`, in
  declaration order with `on_error` last.

  Arity is `zero_or_one` for `core.invoke`'s reason: an outcome path is
  one continuation, not a list of them, and an author who wants several
  steps there puts a `core.sequence` in it exactly as anywhere else a
  single child is asked for.
  """
  @impl true
  def slots(config) do
    config
    |> outcome_names()
    |> Enum.map(&{@slot_prefix <> &1, :zero_or_one, slot_label(&1)})
  end

  @doc """
  The outcomes the referenced chart declares, as the author listed them,
  with `error` appended unless they listed it themselves (ADR-0002
  amendment A1, ADR-0004's outcome amendment 2a).
  """
  @impl true
  def outcomes(config) do
    config
    |> outcome_names()
    |> Enum.map(&{&1, outcome_label(&1)})
  end

  @impl true
  def config_schema(_config),
    do: [
      %{
        key: "chart",
        type: :string,
        label: "Run this chart",
        required?: true,
        default: ""
      },
      %{
        key: "outcomes",
        type: :string,
        label: "It can finish with",
        required?: false,
        default: ""
      },
      %{
        key: "assign_to",
        type: {:path, %{}},
        label: "Write the outcome to",
        required?: false,
        default: ""
      },
      %{
        key: "params",
        type: :string,
        label: "Send along",
        required?: false,
        default: ""
      }
    ]

  @impl true
  def validate_config(config) do
    []
    |> check_child(config)
    |> check_outcomes(config)
    |> check_assign_to(config)
    |> check_params(config)
    |> Config.verdict()
  end

  # J1: exactly one of `chart` and `chart_from`. With no `chart_from` the
  # rule is `chart`'s own, finding for finding, so a config that never
  # carried the new key validates exactly as it did before it existed.
  defp check_child(findings, config) do
    case child_source(config) do
      {:ok, _source} -> findings
      {:error, [finding]} -> [finding | findings]
    end
  end

  defp check_outcomes(findings, config) do
    case outcome_rows(Map.get(config, "outcomes")) do
      {:ok, _names} -> findings
      {:error, message} -> [{"outcomes", message} | findings]
    end
  end

  # A datamodel path, not a bare identifier (ADR-0011 decision 13). The
  # field offers dotted paths as candidates, and a control that offers what
  # its own validation refuses is a defect either way round; the emission
  # is `<assign location="...">`, the same element `core.assign` writes any
  # non-empty whitespace-free path through, so the two read one rule out of
  # `Config.datamodel_path?/1` and cannot disagree about a location.
  defp check_assign_to(findings, config) do
    AssignLocation.check(
      findings,
      config,
      "assign_to",
      &Config.datamodel_path?/1,
      assign_to_message()
    )
  end

  defp assign_to_message, do: "must be a datamodel path, like eligibility.outcome"

  defp check_params(findings, config) do
    case Invoke.param_rows(Map.get(config, "params")) do
      {:ok, _rows} -> findings
      {:error, message} -> [{"params", message} | findings]
    end
  end

  @doc """
  `core.invoke`'s `io/1` exactly: a step with several outcomes, so
  `produces` is `:unknown` rather than a join over the subtrees that reach
  each one - the lattice ADR-0003 decision 4 refuses to build - and no
  `consumes`, because a subchart reads its inputs through `params`.
  """
  @impl true
  def io(config) do
    accepts = config |> slots() |> Map.new(fn {name, _arity, _label} -> {name, [:step]} end)

    %{kinds: [:step], produces: :unknown, slot_accepts: accepts}
  end

  @doc """
  This block as one line of prose (ADR-0002's 2026-09-07 amendment).

  The chart it runs and the fact that it waits, which are the two things
  that separate this block from every other step in a list. The chart name
  is repeated as the author wrote it - it is a key into the host's chart
  store, and a line that paraphrases it names nothing the author can look
  up.

  A block with no chart named yet says what it is and stops.

      iex> StatifierBlocks.Core.Subchart.sentence(%{"chart" => "signup.identity"})
      "Run signup.identity and wait"

      iex> StatifierBlocks.Core.Subchart.sentence(%{})
      "Run a chart and wait"
  """
  @impl true
  def sentence(config) do
    case Map.get(config, "chart") do
      chart when is_binary(chart) ->
        case String.trim(chart) do
          "" -> "Run a chart and wait"
          trimmed -> "Run " <> trimmed <> " and wait"
        end

      _absent_or_malformed ->
        "Run a chart and wait"
    end
  end

  @impl true
  def palette_entry,
    do: %{
      label: "Subchart",
      group: "Structure",
      description: "Runs another chart and waits for it to finish.",
      icon: "rectangle-group",
      keywords: ["subchart", "child", "chart", "call", "compose", "error"],
      order: 11,
      layout: :stack,
      slot_style: %{(@slot_prefix <> @error_outcome) => :failure}
    }

  @impl true
  def explain,
    do:
      "A subchart runs another chart as a child and waits for it to finish, then runs the steps under the outcome the child finished with; the outcome can also be written to a datamodel path. For example, a loan can run the patron registration chart when the borrower has no card yet."

  @doc """
  A compound state that runs the child chart in an inner state and
  finishes at the `<final>` of whichever outcome the child reported.

  Every declared outcome gets one conditioned `done.invoke` transition, in
  declaration order, and the **unconditioned one comes last** (C2):
  document order decides which of several matching transitions is taken,
  so an unconditioned transition placed anywhere but last would shadow
  every conditioned one after it. Where it lands is this type's call, and
  it lands on the **first declared outcome** - the outcome an author who
  declared only one has, so a subchart that declares nothing behaves
  exactly like a `core.invoke`.

  `error.communication.invoke` routing is `core.invoke`'s, unchanged: the
  transition is always emitted, targeting the `on_error` child when the
  slot holds one and the `error` final directly when it does not
  (ADR-0002's amendment of 2026-09-06, section 2). That final is emitted
  in both cases, whatever the referenced chart's own declared outcomes
  say, because a class is read off a final.

  ## Who owns what

  Everything here is this block's except one transition per occupied slot:
  the one leaving the slot's child for that outcome's final is attributed
  to **that child**, because "what happens after the parking step
  finishes" is a fact about the child (ADR-0004 decision 5, the rule
  `Emit.chain/2` follows). The `src` attribute's value is stamped as
  coming from `chart` and the `location`'s from `assign_to`, and each
  condition as coming from `outcomes`, so an upstream finding inside one
  is the author's typo rather than a bug in this type.
  """
  @impl true
  def emit(%Block{config: config}, context) do
    with {:ok, running} <- Context.role_id(context, "running"),
         {:ok, source} <- child_source(config),
         {:ok, rows} <- params(Map.get(config, "params")),
         {:ok, result} <- assign(Map.get(config, "assign_to")),
         {:ok, routes} <- routes(context, config) do
      call = invoke(context.block_id, source, Enum.map(rows, &param/1), config)

      inner =
        Emit.state(
          running,
          nil,
          [call] ++ done_transitions(routes, result) ++ failure_transition(routes)
        )

      children = [inner] ++ slot_children(routes) ++ finals(routes)

      {:ok, Emit.state(context.state_id, running, children)}
    end
  end

  # One route per declared outcome: the `<final>` it compiles to, the slot
  # child that runs before it (or `nil`), and where the routing transition
  # therefore points. `routed?` is false for the failure outcome when the
  # author did not declare it - that one is reached by ADR-0068's event
  # rather than by the child reporting it.
  @typep route :: %{
           name: String.t(),
           final: String.t(),
           child: Context.child_summary() | nil,
           target: String.t(),
           routed?: boolean()
         }

  @spec routes(Context.t(), Block.config()) ::
          {:ok, [route()]} | {:error, {:invalid_outcome, Block.id(), String.t()}}
  defp routes(context, config) do
    declared = child_outcomes(config)

    config
    |> outcome_names()
    |> Enum.reduce_while({:ok, []}, fn name, {:ok, acc} ->
      case Context.outcome_id(context, name) do
        {:ok, final} -> {:cont, {:ok, [route(context, name, final, declared) | acc]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, routes} -> {:ok, Enum.reverse(routes)}
      {:error, _reason} = error -> error
    end
  end

  @spec route(Context.t(), String.t(), String.t(), [String.t()]) :: route()
  defp route(context, name, final, declared) do
    child = context |> Context.children(@slot_prefix <> name) |> List.first()

    %{
      name: name,
      final: final,
      child: child,
      target: if(child, do: child.state_id, else: final),
      routed?: name in declared
    }
  end

  # C2: one conditioned transition per outcome the child can report, then
  # the unconditioned default, last.
  #
  # The condition is composed here from the outcome name rather than read
  # out of a config field, so it carries no `cond_key`: ADR-0004 decision
  # 9 attributes an attribute value to a config key only when the value
  # came from that field verbatim. Annotating it with "outcomes" would
  # make a chart finding landing in these bytes read `fault: :author` and
  # let decision 9's sub-expression span point into bytes this package
  # generated, in a field the author could not fix it from.
  @spec done_transitions([route()], [Emission.t()]) :: [Emission.t()]
  defp done_transitions(routes, result) do
    routed = Enum.filter(routes, & &1.routed?)

    conditioned =
      Enum.map(routed, fn route ->
        Emit.transition(
          [
            event: @done_event,
            cond: condition(route.name),
            target: route.target
          ],
          result
        )
      end)

    conditioned ++ [Emit.transition([event: @done_event, target: default_target(routed)], result)]
  end

  @spec condition(String.t()) :: String.t()
  defp condition(outcome), do: "_event.data.outcome === '" <> outcome <> "'"

  @spec default_target([route()]) :: String.t()
  defp default_target([first | _rest]), do: first.target

  # ADR-0002's amendment of 2026-09-06 section 2: the failure route's
  # transition is emitted whether or not its slot is occupied. With a
  # child it points at the child, without one it points straight at the
  # final - `route.target` is already that distinction.
  @spec failure_transition([route()]) :: [Emission.t()]
  defp failure_transition(routes) do
    case Enum.find(routes, &(&1.name == @error_outcome)) do
      nil -> []
      route -> [Emit.transition(event: @error_event, target: route.target)]
    end
  end

  @spec slot_children([route()]) :: [Emission.node_t()]
  defp slot_children(routes) do
    routes
    |> Enum.filter(& &1.child)
    |> Enum.flat_map(fn %{child: child, final: final} ->
      [
        Emission.child_ref(child.block_id),
        [event: child.done_event, target: final, internal: true]
        |> Emit.transition()
        |> Emission.attributed_to(child.block_id)
      ]
    end)
  end

  # An outcome the block can never reach emits no `<final>` - with one
  # exception, ADR-0002's amendment of 2026-09-06 section 2: the
  # failure-classed outcome's final is emitted always, because the class
  # is read off the final and an outcome whose final is sometimes absent
  # cannot be classed. So `error` is kept here whatever the author
  # declared and whatever the slot holds, and every other outcome keeps
  # the `routed? or child` rule it had.
  @spec finals([route()]) :: [Emission.t()]
  defp finals(routes) do
    routes
    |> Enum.filter(&(&1.routed? or &1.name == @error_outcome or &1.child != nil))
    |> Enum.map(&Emit.final(&1.final))
  end

  @doc """
  The outcomes this block declares: the ones the author listed, then
  `error` unless they listed it.

  Public because the editor and the tests both need the same reading of
  the flattened field, and two spellings of it would be two chances for
  them to disagree.
  """
  @spec outcome_names(Block.config()) :: [String.t()]
  def outcome_names(config) do
    declared = child_outcomes(config)

    if @error_outcome in declared, do: declared, else: declared ++ [@error_outcome]
  end

  @doc """
  `error` is failure-classed: a child that reported `error` is a child
  that finished badly (the failure seam, 2026-09-06).

  It is the one outcome this type appends itself, and the moduledoc
  already calls it "the failure outcome"; nothing else the author listed
  is classed, because this package cannot know what a chart's own
  `declined` or `expired` means. The class is a second axis on an outcome
  that already exists, so the outcome list, the `on_<outcome>` slots and
  the `error.communication.invoke` routing are all unchanged - and so is
  the `slot_style` `:failure` the palette entry already gives `on_error`,
  which is the editor's word for the same fact.

  It changes one thing, and only for a document whose **root** block is a
  `core.subchart`: the top-level `<final>` for `error` carries the
  reserved `<donedata>` `<param>` that tells a durable stepper the run
  failed.
  """
  @impl true
  def failure_outcomes(_config), do: [@error_outcome]

  @doc """
  The outcomes the **referenced chart** declares, in the order the author
  wrote them, defaulting to `["done"]`.

  Total: a field this type's `validate_config/1` rejects reads as the
  default rather than raising, so every callback stays answerable for a
  config the compiler will refuse anyway.
  """
  @spec child_outcomes(Block.config()) :: [String.t()]
  def child_outcomes(config) when is_map(config) do
    case outcome_rows(Map.get(config, "outcomes")) do
      {:ok, []} -> [@default_outcome]
      {:ok, names} -> names
      {:error, _message} -> [@default_outcome]
    end
  end

  def child_outcomes(_config), do: [@default_outcome]

  @doc """
  The `outcomes` field's rows: one outcome name per line, blank lines
  ignored, in the order the author wrote them.
  """
  @spec outcome_rows(term()) :: {:ok, [String.t()]} | {:error, String.t()}
  def outcome_rows(value) when value in [nil, ""], do: {:ok, []}

  def outcome_rows(value) when is_binary(value) do
    names =
      value
      |> String.split("\n")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    cond do
      Enum.any?(names, &(not Config.identifier?(&1))) ->
        {:error,
         "each line is one outcome name: lowercase letters, digits and underscores, " <>
           "starting with a letter"}

      names != Enum.uniq(names) ->
        {:error, "names an outcome twice; each line is one outcome"}

      true ->
        {:ok, names}
    end
  end

  def outcome_rows(_value), do: {:error, "must be text, one outcome name per line"}

  @spec slot_label(String.t()) :: String.t()
  defp slot_label(@error_outcome), do: "If it fails"
  defp slot_label(name), do: "If it finishes " <> String.replace(name, "_", " ")

  @spec outcome_label(String.t()) :: String.t()
  defp outcome_label(@error_outcome), do: "Failed"

  defp outcome_label(name) do
    name |> String.replace("_", " ") |> String.capitalize()
  end

  # The `<invoke>` itself. The literal form is built exactly as it was
  # before `chart_from` existed - the same attributes, the same children,
  # the same stamp - which is what keeps its bytes (J1). The data-driven
  # form writes the path as `srcexpr` and appends the reserved outcomes
  # param after the author's rows (J2).
  @spec invoke(Block.id(), {:chart | :chart_from, String.t()}, [Emission.t()], Block.config()) ::
          Emission.t()
  defp invoke(block_id, {:chart, chart}, params, _config) do
    "invoke"
    |> Emission.element([{"id", block_id}, {"src", chart}, {"type", @invoke_type}], params)
    |> Emission.attribute_from_config("src", "chart")
  end

  defp invoke(block_id, {:chart_from, path}, params, config) do
    "invoke"
    |> Emission.element(
      [{"id", block_id}, {"srcexpr", path}, {"type", @invoke_type}],
      params ++ [outcomes_carrier(config)]
    )
    |> Emission.attribute_from_config("srcexpr", "chart_from")
  end

  # Composed here from `outcome_names/1` rather than copied from a field,
  # so it carries no config stamp, for the reason the routing conditions
  # carry none: a finding in bytes this type generated is not the author's
  # to fix. An outcome name is an identifier, so it holds no space and no
  # quote, and the single-quoted literal needs no escaping.
  @spec outcomes_carrier(Block.config()) :: Emission.t()
  defp outcomes_carrier(config) do
    expr = "'" <> Enum.join(outcome_names(config), " ") <> "'"
    Emission.element("param", [{"expr", expr}, {"name", @outcomes_param}])
  end

  # Which key names the child (J1). An empty string reads as absent, as it
  # does for `outcomes`, `assign_to` and `params`. With `chart_from` absent
  # the answer is exactly the literal rule this type has always applied.
  @spec child_source(Block.config()) ::
          {:ok, {:chart | :chart_from, String.t()}} | {:error, [{String.t(), String.t()}]}
  defp child_source(config) do
    chart = Map.get(config, "chart")
    chart_from = Map.get(config, "chart_from")

    cond do
      blank?(chart_from) ->
        chart_source(chart)

      not blank?(chart) ->
        {:error,
         [{"chart_from", "names the document by chart or by chart_from, never both; clear one"}]}

      Config.datamodel_path?(chart_from) ->
        {:ok, {:chart_from, chart_from}}

      true ->
        {:error,
         [{"chart_from", "must be a datamodel path holding a document id, like onboarding.next"}]}
    end
  end

  @spec chart_source(term()) ::
          {:ok, {:chart, String.t()}} | {:error, [{String.t(), String.t()}]}
  defp chart_source(value) do
    if chart?(value) do
      {:ok, {:chart, value}}
    else
      {:error, [{"chart", "names the document to run, like bdoc_01JWIZ"}]}
    end
  end

  @spec blank?(term()) :: boolean()
  defp blank?(value), do: value in [nil, ""]

  # Deliberately loose, for the reason `core.invoke`'s path check is: the
  # value is a **document id** the host's handler resolves (ADR-0004's
  # subchart-src amendment), and this package does not own the shape of a
  # host's document ids any more than it owns statifier-ex ADR-0052's
  # chart identity. A tighter rule here would be a second, quieter
  # proposal about what a chart reference may say. The one thing a compile
  # can decide about the value it does decide, in
  # `StatifierBlocks.Compiler.SelfReference`: it may not be the id of the
  # document the block sits in.
  @spec chart?(term()) :: boolean()
  defp chart?(value), do: Config.non_empty_string?(value) and not String.contains?(value, " ")

  @spec assign(term()) :: {:ok, [Emission.t()]} | {:error, [{String.t(), String.t()}]}
  defp assign(location) do
    case AssignLocation.location(
           location,
           "assign_to",
           &Config.datamodel_path?/1,
           assign_to_message()
         ) do
      {:ok, nil} ->
        {:ok, []}

      {:ok, path} ->
        {:ok,
         [
           "assign"
           |> Emission.element([{"expr", "_event.data"}, {"location", path}])
           |> Emission.attribute_from_config("location", "assign_to")
         ]}

      {:error, findings} ->
        {:error, findings}
    end
  end

  @spec params(term()) :: {:ok, [{String.t(), String.t()}]} | {:error, [{String.t(), String.t()}]}
  defp params(value) do
    case Invoke.param_rows(value) do
      {:ok, rows} -> {:ok, rows}
      {:error, message} -> {:error, [{"params", message}]}
    end
  end

  @spec param({String.t(), String.t()}) :: Emission.t()
  defp param({name, path}) do
    "param"
    |> Emission.element([{"expr", path}, {"name", name}])
    |> Emission.from_config("params")
  end
end
