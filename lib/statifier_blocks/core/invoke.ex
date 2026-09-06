defmodule StatifierBlocks.Core.Invoke do
  @moduledoc """
  `core.invoke`: a step that calls the host and waits for it to answer,
  with an optional subtree for the failure case (ADR-0002 decision 10, as
  amended 2026-08-29 section D).

  This type **names** an invoke type; it never runs one. Which handler a
  name resolves to is deployment state supplied per session (st-ADR-0051),
  and the palette is authoring state supplied per operation - the
  two-registry seam ADR-0002 decision 2 draws, which this is the first
  `core.*` type to stand on. `StatifierBlocks.Compiler.InvokeTypes` is what
  a host compares the two against, at the one moment it holds both.

  ## The failure path is a slot, not a port

  A failing call is one of the two ways this block can finish, and the way
  an author says what happens then is by putting blocks in the `on_error`
  slot. It is not a second outlet with an author-drawn edge: every edge in
  a document is a parent/slot/child relationship, which is the invariant
  the editor's rendered connectors rest on (D13, and ADR-0002's amendment
  section A2). The slot is a rail beside the step, declared with
  `zero_or_one` arity and the `:failure` slot style ADR-0005 decision 10's
  2026-08-29 amendment (10g) names for exactly this slot: an in-band
  continuation path taken on a bad outcome, rendered on the rail
  `core.group`'s `interrupts` already uses but in the error family rather
  than the interrupt one. The rendering half of 10h is the renderer's, not
  this type's: all a block type does is declare the style.

  ## Two outcomes

  `done` and `error`, in that order. Under ADR-0004's outcome amendment
  each one the block reaches compiles to its own `<final>`, minted through
  `StatifierBlocks.Compiler.Context.outcome_id/2`, whose entry raises
  `done.outcome.<state id>.<outcome>`. A parent that does not care which
  way the call went wires the prefix and never learns an outcome name; one
  that does names the full event. **The block decides nothing about what
  comes next**: its emission ends at the final it enters.

  ## `assign_to` names a datamodel path

  The field is declared `{:path, %{}}` - ADR-0002 decision 7's eighth field
  type - so the editor offers the host's declared datamodel paths as
  candidates on it, a value the datamodel does not declare draws ADR-0005
  clause 11e's `:info` advisory rather than a refusal, and the write this
  block makes is visible to `StatifierBlocks.Environment` as `:unknown` at
  that path (ADR-0011 decision 2) instead of being emitted where nothing
  declared can see it. Its rule is `core.assign`'s and `core.subchart`'s -
  any non-empty path with no whitespace - for ADR-0011 decision 13's
  reason: one `<assign>` element writing one datamodel cannot have two
  rules about what a location may be. A blank `assign_to` is a call whose
  answer is thrown away, which is an answer rather than a gap.

  ## The params field is knowingly provisional

  ADR-0002 decision 7's field types are a closed set and none of them is "a
  list of name/path pairs", so `params` is a `:string` holding one
  `name=path` per line. That is the amendment's own compromise, recorded in
  its section D1 as a deferred question: whichever way it is resolved - a
  new field type, a dedicated control, or the flattening as shipped - it is
  a decision 7 change rather than a change to this type's row.
  """

  @behaviour StatifierBlocks.BlockType

  alias StatifierBlocks.Block
  alias StatifierBlocks.Compiler.Context
  alias StatifierBlocks.Core.{AssignLocation, Config, Emit}
  alias StatifierBlocks.Emission

  # ADR-0011 decision 13's argument, applied to this type's `assign_to` on
  # `sb-r313`: the `<assign location="...">` this block emits writes the
  # same datamodel `core.assign` writes through the same element, so the
  # location rule is `Config.datamodel_path?/1` here too, and the wording
  # is `core.subchart`'s sentence with this field's own example.
  @assign_to_message "must be a datamodel path, like cards.authorization"

  @error_event "error.communication.invoke"
  @done_event "done.invoke"

  @impl true
  def current_version, do: 1

  @doc """
  One optional slot, `on_error`, holding what runs when the call fails.

  Its arity is `zero_or_one` because a failure path is one continuation,
  not a list of them: an author who wants several steps there puts a
  `core.sequence` in it, exactly as anywhere else a single child is asked
  for.
  """
  @impl true
  def slots(_config), do: [{"on_error", :zero_or_one, "If it fails"}]

  @impl true
  def config_schema(_config),
    do: [
      %{
        key: "invoke_type",
        type: :string,
        label: "Invoke type",
        required?: true,
        default: ""
      },
      %{
        key: "assign_to",
        type: {:path, %{}},
        label: "Write the result to",
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
    |> check_invoke_type(config)
    |> check_assign_to(config)
    |> check_params(config)
    |> Config.verdict()
  end

  defp check_invoke_type(findings, config) do
    if invoke_type?(Map.get(config, "invoke_type")) do
      findings
    else
      [{"invoke_type", ~s(must look like "namespace:name", such as "myapp:authorize")} | findings]
    end
  end

  defp check_assign_to(findings, config) do
    AssignLocation.check(
      findings,
      config,
      "assign_to",
      &Config.datamodel_path?/1,
      @assign_to_message
    )
  end

  defp check_params(findings, config) do
    case param_rows(Map.get(config, "params")) do
      {:ok, _rows} -> findings
      {:error, message} -> [{"params", message} | findings]
    end
  end

  @doc """
  A step with two outcomes, so `produces` is `:unknown` for the reason
  `core.branch` declares it: joining the type this block's own call
  produces with the type its `on_error` subtree produces is the lattice
  ADR-0003 decision 4 refuses to build.

  `consumes` is absent - an invoke reads its inputs through `params`, out
  of the datamodel, rather than through the type flow.
  """
  @impl true
  def io(_config),
    do: %{kinds: [:step], produces: :unknown, slot_accepts: %{"on_error" => [:step]}}

  @impl true
  def palette_entry,
    do: %{
      label: "Invoke",
      group: "Structure",
      description: "Calls a host handler and waits for it to answer.",
      icon: "arrow-up-right",
      keywords: ["invoke", "call", "host", "service", "error"],
      order: 7,
      layout: :stack,
      slot_style: %{"on_error" => :failure}
    }

  @doc """
  A compound state that runs the call in an inner state and finishes at
  the `<final>` of whichever outcome it reached.

      <state id="s_INV" initial="s_INV__running">
        <state id="s_INV__running">
          <invoke type="myapp:authorize">
            <param expr="order.amount" name="amount"/>
          </invoke>
          <transition event="done.invoke" target="s_INV__o_done">
            <assign expr="_event.data" location="authorization"/>
          </transition>
          <transition event="error.communication.invoke" target="s_blk_PARK"/>
        </state>
        {the on_error child's own subtree}
        <transition event="done.state.s_blk_PARK" target="s_INV__o_error" type="internal"/>
        <final id="s_INV__o_done">
          <onentry><raise event="done.outcome.s_INV.done"/></onentry>
        </final>
        <final id="s_INV__o_error">
          <onentry><raise event="done.outcome.s_INV.error"/></onentry>
        </final>
      </state>

  ## Both transitions match by prefix, and neither names an id

  The `<invoke>` carries no `id`, so the engine mints one, and the two
  transitions match `done.invoke` and `error.communication.invoke` by
  SCXML's descriptor prefix rule rather than naming the invocation. That
  is safe for exactly the reason ADR-0004's worked example gives: both
  transitions sit on the inner state, which is active only while this
  block's own call is outstanding, so no other invocation's completion can
  be selected by them.

  `error.communication.invoke.<invoke_id>` is statifier-ex ADR-0068's
  name - a blessed suffix extension of the `error.communication` that
  st-ADR-0051 decision 1 already assigns to this failure - which is what
  makes the prefix match here and a host chart's existing
  `error.communication` handler both correct at once.

  ## An absent `on_error` emits no failure transition at all

  With the slot empty there is nothing to transition to, so neither the
  failure transition nor the `error` outcome's `<final>` is emitted and the
  error propagates as it does today. That costs a parent nothing: outcome
  wiring is an event rather than a target, so a parent may transition on an
  outcome whose final was never emitted and the transition simply never
  fires (ADR-0004's amendment, 2c).

  ## Who owns what

  Everything here is this block's except one transition: the one leaving
  the `on_error` child for the error final is attributed to **that child**,
  because "what happens after the parking step finishes" is a fact about
  the child (decision 5, the same rule `Emit.chain/2` follows). The
  `type` attribute's value is stamped as coming from `invoke_type` and the
  `location`'s from `assign_to`, so an upstream finding inside either is
  the author's typo rather than a bug in this type.
  """
  @impl true
  def emit(%Block{config: config}, context) do
    with {:ok, running} <- Context.role_id(context, "running"),
         {:ok, done_final} <- Context.outcome_id(context, "done"),
         {:ok, invoke_type} <- invoke_type(Map.get(config, "invoke_type")),
         {:ok, rows} <- params(Map.get(config, "params")),
         {:ok, result} <- assign(Map.get(config, "assign_to")),
         {:ok, error_parts} <- error_parts(context) do
      call =
        "invoke"
        |> Emission.element([{"type", invoke_type}], Enum.map(rows, &param/1))
        |> Emission.attribute_from_config("type", "invoke_type")

      inner =
        Emit.state(running, nil, [
          call,
          Emit.transition([event: @done_event, target: done_final], result)
          | failure_transition(error_parts)
        ])

      children =
        [inner] ++
          error_children(error_parts) ++
          [Emit.final(done_final)] ++ error_final(error_parts)

      {:ok, Emit.state(context.state_id, running, children)}
    end
  end

  # The error half is emitted only when the `on_error` slot is occupied,
  # and it is all of one piece: the transition out of the call, the
  # child's subtree, the transition into the final, and the final itself.
  # The completion event each outcome final raises is no longer carried
  # here: `StatifierBlocks.Core.Emit.final/1` derives it from the id, so
  # there is one implementation of an outcome final rather than this
  # type's and the shared vocabulary's.
  @spec error_parts(Context.t()) ::
          {:ok, nil | {Context.child_summary(), String.t()}}
          | {:error, {:invalid_outcome, Block.id(), String.t()}}
  defp error_parts(context) do
    case Context.children(context, "on_error") do
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

  defp error_children({child, final}) do
    [
      Emission.child_ref(child.block_id),
      [event: child.done_event, target: final, internal: true]
      |> Emit.transition()
      |> Emission.attributed_to(child.block_id)
    ]
  end

  defp error_final(nil), do: []
  defp error_final({_child, final}), do: [Emit.final(final)]

  # `assign_to` is written on the success transition rather than in a
  # `<finalize>`: the result is only a result when the call succeeded, and
  # `<finalize>` runs for every event the invocation delivers.
  @spec assign(term()) :: {:ok, [Emission.t()]} | {:error, [{String.t(), String.t()}]}
  defp assign(location) do
    case AssignLocation.location(
           location,
           "assign_to",
           &Config.datamodel_path?/1,
           @assign_to_message
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

  @spec param({String.t(), String.t()}) :: Emission.t()
  defp param({name, path}) do
    "param"
    |> Emission.element([{"expr", path}, {"name", name}])
    |> Emission.from_config("params")
  end

  @spec invoke_type(term()) :: {:ok, String.t()} | {:error, [{String.t(), String.t()}]}
  defp invoke_type(value) do
    if invoke_type?(value) do
      {:ok, value}
    else
      {:error, [{"invoke_type", ~s(must look like "namespace:name", such as "myapp:authorize")}]}
    end
  end

  @spec params(term()) :: {:ok, [{String.t(), String.t()}]} | {:error, [{String.t(), String.t()}]}
  defp params(value) do
    case param_rows(value) do
      {:ok, rows} -> {:ok, rows}
      {:error, message} -> {:error, [{"params", message}]}
    end
  end

  @doc """
  The `params` field's rows, as `{name, path}` pairs in the order the
  author wrote them.

  One `name=path` per line, blank lines ignored. Public because the editor
  and the tests both need the same reading of the flattened field, and two
  spellings of it would be two chances for them to disagree - the field is
  provisional (ADR-0002's amendment, D1) and this function is where the
  provisionality is contained.
  """
  @spec param_rows(term()) :: {:ok, [{String.t(), String.t()}]} | {:error, String.t()}
  def param_rows(value) when value in [nil, ""], do: {:ok, []}

  def param_rows(value) when is_binary(value) do
    value
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.reduce_while({:ok, []}, fn line, {:ok, rows} ->
      case row(line) do
        {:ok, row} -> {:cont, {:ok, [row | rows]}}
        {:error, message} -> {:halt, {:error, message}}
      end
    end)
    |> case do
      {:ok, rows} -> {:ok, Enum.reverse(rows)}
      {:error, message} -> {:error, message}
    end
  end

  def param_rows(_value), do: {:error, "must be text, one name=path per line"}

  @spec row(String.t()) :: {:ok, {String.t(), String.t()}} | {:error, String.t()}
  defp row(line) do
    case String.split(line, "=", parts: 2) do
      [name, path] -> pair(String.trim(name), String.trim(path))
      [_no_separator] -> {:error, ~s(each line is name=path, like amount=order.amount)}
    end
  end

  @spec pair(String.t(), String.t()) :: {:ok, {String.t(), String.t()}} | {:error, String.t()}
  defp pair(name, path) do
    cond do
      not Config.identifier?(name) ->
        {:error,
         ~s("#{name}" is not a name: use lowercase letters, digits and underscores, ) <>
           "starting with a letter"}

      not path?(path) ->
        {:error, ~s("#{name}" needs a datamodel path, like order.amount)}

      true ->
        {:ok, {name, path}}
    end
  end

  # Deliberately loose: this package does not own the datamodel path
  # grammar, and a tighter rule here would be a second, quieter proposal
  # about what a path may say. A non-empty run with no whitespace in it is
  # what the flattened line can carry on its right-hand side anyway.
  @spec path?(String.t()) :: boolean()
  defp path?(path), do: Config.non_empty_string?(path) and not String.contains?(path, " ")

  # The grammar lives in `StatifierBlocks.Core.Config` because
  # `StatifierBlocks.InvokeStep` reads the same one: two spellings of
  # "namespace:name" would be two chances for a core block and a host
  # step to disagree about the same field.
  @spec invoke_type?(term()) :: boolean()
  defp invoke_type?(value), do: Config.invoke_type?(value)
end
