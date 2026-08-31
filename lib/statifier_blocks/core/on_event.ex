defmodule StatifierBlocks.Core.OnEvent do
  @moduledoc """
  `core.on_event`: an interrupt handler, valid inside an `interrupts` slot
  and nowhere else (ADR-0002 decision 10).

  A leaf with three config fields: the `event` that fires it, an optional
  `cond` that decides whether it fires at all, and the `outcome` that
  decides what happens to the group it interrupts.

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
  """

  @behaviour StatifierBlocks.BlockType

  alias StatifierBlocks.Block
  alias StatifierBlocks.Compiler.Context
  alias StatifierBlocks.Core.{Config, Emit}
  alias StatifierBlocks.Emission

  @outcomes ["abandon", "resume"]

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
  """
  @impl true
  def emit(%Block{config: config}, context) do
    done = Context.done_id(context)

    with {:ok, armed} <- Context.role_id(context, "armed"),
         {:ok, outcome} <- outcome_event(Map.get(config, "outcome")),
         {:ok, event} <- event_name(Map.get(config, "event")) do
      watcher =
        Emit.state(armed, nil, [
          Emit.transition(
            [event: event, cond: guard(config), cond_key: "cond", target: done],
            [Emission.element("raise", [{"event", outcome}])]
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
