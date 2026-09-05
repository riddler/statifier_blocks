defmodule StatifierBlocks.Core.Await do
  @moduledoc """
  `core.await`: an in-flow leaf that holds until a named event arrives,
  with an optional deadline (ADR-0002 decision 10, the 2026-09-05
  amendment).

  No slots, two config fields, and two outcomes. `event` is required and
  reads the event-name grammar `core.on_event` and `core.send` already
  read; `timeout` is an optional `:duration` in the one grammar
  `core.wait`'s `duration` and `core.send`'s `delay` are written in. The
  two outcomes, `received` and `timed_out`, are the two ways an await can
  end.

  ## An await is not a wait

  The names are one word apart because the things are close, so this
  moduledoc says which is meant rather than leaning on the verb. A
  **wait** (`core.wait`) holds for a duration and ends one way. An
  **await** holds for an event and ends one of two ways, one of which is
  a duration elapsing. `io/1` is `core.wait`'s declaration byte for byte,
  which is the whole of what "valid wherever a wait is" means: both are
  `kinds: [:step]`, and both leave `consumes` and `produces` to ADR-0003
  decision 5's permissive default, because holding transforms no data.

  ## Why this is a type rather than an arrangement

  The nearest arrangement is a `core.group` whose `interrupts` rail
  carries a `core.on_event` for the awaited event and, for the deadline,
  the deadline recipe's `core.send` and a second handler. It does not
  express this type, because a handler's outcome word becomes one of
  exactly two package-owned interrupt events
  (`StatifierBlocks.Core.Emit.interrupt_events/0`) and a group declares
  no outcomes at all: two `abandon` handlers on one rail are
  indistinguishable to everything downstream. This type declares the two
  outcomes directly, which is the seam the arrangement is missing.

  ## Both outcomes are declared whether or not a deadline is stored

  `outcomes/1` returns `received` and `timed_out` for every config,
  including one with no `timeout`. An outcome's wiring is an event rather
  than a target (ADR-0004's outcome amendment, 2c), so a parent may
  transition on an outcome whose `<final>` was never emitted and the
  transition simply never fires - which is what lets `core.invoke` omit
  its error path entirely when `on_error` is empty. Deriving the list
  from `timeout` instead would take a declared seam away from an author
  who cleared the field, which is the failure ADR-0002 decision 6's
  `slots/1` stability rule exists to avoid on the slot side. The emitted
  bytes stay honest either way: with no `timeout`, no timer is armed and
  no `timed_out` final is written.

  ## The deadline's timer cannot outlive the await

  When `timeout` holds a duration, the compiled waiting state arms a
  delayed `<send>` whose id is minted with
  `StatifierBlocks.Compiler.Context.role_id/2` under
  `StatifierBlocks.Compiler.Cancels.armed_role/0` - the reserved role
  `core.wait` and `core.send` mint under. `StatifierBlocks.Compiler.Cancels`
  therefore reaches it like any other armed send and cancels it in the
  enclosing scope's `<onexit>`, so an await left before its deadline -
  because the awaited event arrived, because an interrupt fired, because
  a losing lane exited, because a group was abandoned - leaves no timer
  behind. Nothing in that module changes for this type; an await with no
  `timeout` arms nothing and there is nothing to cancel.
  """

  @behaviour StatifierBlocks.BlockType

  alias StatifierBlocks.Block
  alias StatifierBlocks.Compiler.{Cancels, Context}
  alias StatifierBlocks.Core.{Config, Duration, Emit}
  alias StatifierBlocks.Emission

  @event_message "must be an event name, like order.approved"

  # One sentence at both refusal sites, naming what is accepted and
  # nothing else (ADR-0005 clause 9d). It reads like `core.send`'s rather
  # than `core.wait`'s because this field is optional too.
  @timeout_message "must be a duration like 30s or 1h30m - or empty for no deadline"

  @received "received"
  @timed_out "timed_out"

  @impl true
  def current_version, do: 1

  @impl true
  def slots(_config), do: []

  @doc """
  The event first, then the deadline.

  `timeout`'s default is `""` and not a duration: an await with no
  deadline is the ordinary case, and a default that armed a timer would
  be this type deciding an author's policy for them.
  """
  @impl true
  def config_schema(_config),
    do: [
      %{
        key: "event",
        type: :string,
        label: "Wait for this event",
        required?: true,
        default: ""
      },
      %{
        key: "timeout",
        type: :duration,
        label: "Give up after",
        required?: false,
        default: ""
      }
    ]

  @doc """
  The two ways an await can finish, for every config.

  See the moduledoc: the list does not follow `timeout`, because an
  unreached outcome costs a parent nothing and a disappearing one costs
  an author their wiring.
  """
  @impl true
  def outcomes(_config), do: [{@received, "Received"}, {@timed_out, "Timed out"}]

  @impl true
  def validate_config(config) do
    []
    |> check_event(config)
    |> check_timeout(config)
    |> Config.verdict()
  end

  defp check_event(findings, config) do
    if Config.event_name?(Map.get(config, "event")) do
      findings
    else
      [{"event", @event_message} | findings]
    end
  end

  # An absent key and the field's own default are both "no deadline", and
  # the default is what the config form writes into every block of this
  # type, so `""` cannot be a finding. A stored `nil` is a different
  # thing from an absent key under ADR-0001 decision 6 and reaches the
  # refusal arm.
  defp check_timeout(findings, config) do
    case Map.fetch(config, "timeout") do
      :error -> findings
      {:ok, ""} -> findings
      {:ok, value} -> timeout_finding(findings, value)
    end
  end

  defp timeout_finding(findings, value) do
    if Duration.duration?(value), do: findings, else: [{"timeout", @timeout_message} | findings]
  end

  @doc """
  `core.wait`'s declaration byte for byte: a step that constrains nothing
  and is constrained by nothing beyond being one.
  """
  @impl true
  def io(_config), do: %{kinds: [:step]}

  @impl true
  def palette_entry,
    do: %{
      label: "Wait for event",
      group: "Structure",
      description: "Holds until a named event arrives, or a deadline passes.",
      icon: "bolt",
      keywords: ["await", "wait", "event", "timeout", "deadline"],
      order: 15
    }

  @doc """
  The event name, then the deadline when one is stored (ADR-0002
  amendment H6).

  The event comes first because it is what the block is for; the deadline
  is only the other way out. Each half is dropped on its own when it is
  absent or not well formed, so an await mid-edit shows the half the
  author has filled in rather than nothing, and the stored bytes are
  shown rather than the compiled ones for `core.wait`'s reason - the card
  reads back what the inspector field beside it holds.

      iex> StatifierBlocks.Core.Await.summary(%{"event" => "order.approved"})
      ["order.approved"]

      iex> StatifierBlocks.Core.Await.summary(%{"event" => "order.approved", "timeout" => "48h"})
      ["order.approved", "by 48h"]

      iex> StatifierBlocks.Core.Await.summary(%{})
      []
  """
  @impl true
  def summary(config) do
    [event_chip(Map.get(config, "event")), timeout_chip(Map.get(config, "timeout"))]
    |> Enum.reject(&is_nil/1)
  end

  defp event_chip(event) do
    if Config.event_name?(event), do: event, else: nil
  end

  defp timeout_chip(timeout) do
    if Duration.duration?(timeout), do: "by " <> timeout, else: nil
  end

  @doc """
  One example event payload, so a palette panel can show what
  `_event.data` looks like when the awaited event arrives.

  Under statifier-ui's `docs/fixture-bundles.md`, `events` is one sample
  `_event.data` payload per event name. The name here is an example, not
  this block's configured `event` - `fixtures/0` takes no config and
  could not read one.
  """
  @impl true
  def fixtures do
    %{
      events: %{
        "order.approved" => %{"approver" => "ops", "at" => "2026-09-05T17:00:00Z"}
      }
    }
  end

  @doc """
  A compound state whose one waiting child transitions to the `received`
  outcome when the event arrives, and - when a `timeout` is stored - arms
  a delayed send on entry and transitions to the `timed_out` outcome when
  that send's event comes back.

      <state id="s_AWT" initial="s_AWT__waiting">
        <state id="s_AWT__waiting">
          <onentry><send delay="48h" event="statifier_blocks.await.blk_AWT" id="s_AWT__send"/></onentry>
          <transition event="order.approved" target="s_AWT__o_received"/>
          <transition event="statifier_blocks.await.blk_AWT" target="s_AWT__o_timed_out"/>
        </state>
        <final id="s_AWT__o_received">
          <onentry><raise event="done.outcome.s_AWT.received"/></onentry>
        </final>
        <final id="s_AWT__o_timed_out">
          <onentry><raise event="done.outcome.s_AWT.timed_out"/></onentry>
        </final>
      </state>

  The timer event carries the block id, so two awaits in the same chart
  never wake each other, and the `<send>` names no `target`, which under
  spec 6.2.2 is the running session's own external queue - the queue a
  durable host turns into a durable timer. This type does not know
  durable timers exist; it emits an ordinary delayed send.

  With no `timeout` stored, the `<onentry>`, the timer transition and the
  `timed_out` `<final>` are all absent, so an await with no deadline
  compiles to the awaited transition and one final. The `timed_out`
  outcome stays declared: a parent wiring
  `done.outcome.s_AWT.timed_out` gets a transition that never fires
  rather than an unresolved target (ADR-0004's outcome amendment, 2c).

  ## What is annotated and what is not

  The awaited `event` attribute is stamped as coming from the `event`
  config key, so an upstream finding inside it reads as the author's typo
  rather than a bug in this type (ADR-0004 decision 9). The `delay`
  attribute is not, for the reason `core.wait` and `core.send` both give:
  those bytes are not the author's verbatim, since a repeated unit
  accumulates and a fraction expands.
  """
  @impl true
  def emit(%Block{id: block_id, config: config}, context) do
    with {:ok, waiting} <- Context.role_id(context, "waiting"),
         {:ok, send_id} <- Context.role_id(context, Cancels.armed_role()),
         {:ok, received} <- Context.outcome_id(context, @received),
         {:ok, timed_out} <- Context.outcome_id(context, @timed_out),
         {:ok, event} <- event(Map.get(config, "event")),
         {:ok, delay} <- delay(config) do
      arrival =
        [event: event, target: received]
        |> Emit.transition()
        |> Emission.attribute_from_config("event", "event")

      deadline = deadline(delay, block_id, send_id, timed_out)

      armed = Emit.state(waiting, nil, deadline.onentry ++ [arrival] ++ deadline.transitions)

      {:ok,
       Emit.state(context.state_id, waiting, [armed, Emit.final(received)] ++ deadline.finals)}
    end
  end

  # The `<onentry>` send, the transition it wakes, and the outcome final
  # that transition targets - or none of the three. Returning them
  # together keeps "a deadline is all of this, or none of it" one
  # decision rather than three tests of the same value.
  @spec deadline(String.t() | nil, Block.id(), String.t(), String.t()) ::
          %{onentry: [Emission.t()], transitions: [Emission.t()], finals: [Emission.t()]}
  defp deadline(nil, _block_id, _send_id, _timed_out),
    do: %{onentry: [], transitions: [], finals: []}

  defp deadline(delay, block_id, send_id, timed_out) do
    event = "statifier_blocks.await." <> block_id

    send_element =
      Emission.element("send", [{"delay", delay}, {"event", event}, {"id", send_id}])

    %{
      onentry: [Emission.element("onentry", [], [send_element])],
      transitions: [Emit.transition(event: event, target: timed_out)],
      finals: [Emit.final(timed_out)]
    }
  end

  # `emit/2` has to answer for a config `validate_config/1` would reject
  # rather than raising on it - the compiler's Config stage makes this
  # arm unreachable in practice, never impossible.
  defp event(event) do
    if Config.event_name?(event) do
      {:ok, event}
    else
      {:error, [{"event", @event_message}]}
    end
  end

  # `nil` here means "no deadline", which is what an absent or empty
  # `timeout` compiles to. Anything else is parsed to the expression
  # language's normalised duration and rendered from it as the attribute
  # `Statifier.Duration` reads.
  @spec delay(Block.config()) :: {:ok, String.t() | nil} | {:error, [{String.t(), String.t()}]}
  defp delay(config) do
    case Map.fetch(config, "timeout") do
      :error -> {:ok, nil}
      {:ok, ""} -> {:ok, nil}
      {:ok, value} -> compiled(value)
    end
  end

  defp compiled(value) do
    case Duration.parse(value) do
      {:ok, parsed} -> {:ok, Duration.to_delay(parsed)}
      :error -> {:error, [{"timeout", @timeout_message}]}
    end
  end
end
