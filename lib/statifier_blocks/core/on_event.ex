defmodule StatifierBlocks.Core.OnEvent do
  @moduledoc """
  `core.on_event`: an interrupt handler, valid inside an `interrupts` slot
  and nowhere else (ADR-0002 decision 10).

  A leaf with two config fields: the `event` that fires it, and the
  `outcome` that decides what happens to the group it interrupts.

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
  """
  @impl true
  def emit(%Block{config: config}, context) do
    done = Context.done_id(context)

    with {:ok, armed} <- Context.role_id(context, "armed"),
         {:ok, outcome} <- outcome_event(Map.get(config, "outcome")),
         {:ok, event} <- event_name(Map.get(config, "event")) do
      watcher =
        Emit.state(armed, nil, [
          Emit.transition([event: event, target: done], [
            Emission.element("raise", [{"event", outcome}])
          ])
        ])

      {:ok, Emit.state(context.state_id, armed, [watcher, Emit.final(done)])}
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
