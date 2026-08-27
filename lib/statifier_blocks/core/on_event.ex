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

  alias StatifierBlocks.Core.Config

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

  @impl true
  def emit(block, _context), do: Config.emit_deferred(block)
end
