defmodule StatifierBlocks.Core.Wait do
  @moduledoc """
  `core.wait`: a leaf whose whole meaning is its config (ADR-0002 decision
  10).

  No slots, one `:duration` field. The duration is an ISO-8601 duration
  string rather than a number of seconds because ADR-0001 decision 6
  forbids floats in `config`, and a bare integer would have to carry its
  unit somewhere else. `"PT30S"`, `"PT48H"`, `"P1D"` - integer components
  only, for the same reason.

  This type validates the *string*; it does not resolve it to a number of
  milliseconds, mint a timer, or know that durable timers exist. Turning it
  into a delayed send is the compiler's job.
  """

  @behaviour StatifierBlocks.BlockType

  alias StatifierBlocks.Block
  alias StatifierBlocks.Compiler.Context
  alias StatifierBlocks.Core.{Config, Emit}
  alias StatifierBlocks.Emission

  @impl true
  def current_version, do: 1

  @impl true
  def slots(_config), do: []

  @impl true
  def config_schema(_config),
    do: [
      %{
        key: "duration",
        type: :duration,
        label: "Wait for",
        required?: true,
        default: "PT1H"
      }
    ]

  @impl true
  def validate_config(config) do
    case Map.fetch(config, "duration") do
      {:ok, duration} ->
        if Config.duration?(duration) do
          :ok
        else
          {:error, [{"duration", "must be an ISO-8601 duration, like PT30S or P1D"}]}
        end

      :error ->
        {:error, [{"duration", "required"}]}
    end
  end

  @doc """
  A wait constrains nothing and is constrained by nothing beyond being a
  step: it declares `kinds` and leaves `consumes` and `produces` to
  ADR-0003 decision 5's permissive default, since waiting transforms no
  data.
  """
  @impl true
  def io(_config), do: %{kinds: [:step]}

  @impl true
  def palette_entry,
    do: %{
      label: "Wait",
      group: "Structure",
      description: "Pauses for a fixed duration before continuing.",
      icon: "clock",
      keywords: ["delay", "timer", "pause", "sleep"],
      order: 5
    }

  @doc """
  A compound state that sends itself a delayed event on entry and finishes
  when that event arrives.

      <state id="s_WAI" initial="s_WAI__waiting">
        <state id="s_WAI__waiting">
          <onentry><send delay="48h" event="statifier_blocks.wait.blk_WAI" id="s_WAI__timer"/></onentry>
          <transition event="statifier_blocks.wait.blk_WAI" target="s_WAI__done"/>
        </state>
        <final id="s_WAI__done"/>
      </state>

  The event name carries the block id, so two waits in the same chart never
  wake each other. `<send>` names no `target`, which under spec 6.2.2 is
  the running session's own external queue - and a delayed send on that
  queue is exactly what `statifier_oban` turns into a durable timer. This
  type still does not know durable timers exist; it emits an ordinary
  delayed send and the host's session decides what backs it.

  ## The duration translation is component-wise and lossless

  ADR-0001 decision 6 forbids floats in `config`, so `duration` is an
  ISO-8601 duration with integer components only. Statifier resolves a
  `delay` attribute through `Statifier.Duration`, which delegates to
  `Predicator.Duration.parse/1` and recognizes `y`, `mo`, `w`, `d`, `h`,
  `m`, `s` and `ms` - a strict superset of the SCXML schema's five units.
  Every ISO component therefore has an exact counterpart, and the
  translation is a rename rather than an arithmetic conversion:

  | ISO | `delay` |
  |---|---|
  | `P1Y` | `1y` |
  | `P1M` (before `T`) | `1mo` |
  | `P1W` / `P1D` | `1w` / `1d` |
  | `PT1H` / `PT1M` / `PT1S` | `1h` / `1m` / `1s` |

  Nothing here decides how many days a month is, because nothing here has
  to: the ambiguity stays where the author wrote it and is resolved by the
  one duration vocabulary the platform shares.
  """
  @impl true
  def emit(%Block{id: block_id, config: config}, context) do
    done = Context.done_id(context)

    with {:ok, waiting} <- Context.role_id(context, "waiting"),
         {:ok, timer} <- Context.role_id(context, "timer"),
         {:ok, delay} <- delay(Map.get(config, "duration")) do
      event = "statifier_blocks.wait." <> block_id

      send_element =
        Emission.element("send", [{"delay", delay}, {"event", event}, {"id", timer}])

      armed =
        Emit.state(waiting, nil, [
          Emission.element("onentry", [], [send_element]),
          Emit.transition(event: event, target: done)
        ])

      {:ok, Emit.state(context.state_id, waiting, [armed, Emit.final(done)])}
    end
  end

  # `PT48H` -> `48h`. Returns an ordinary Emit finding rather than raising
  # for a duration `validate_config/1` would have rejected, since `emit/2`
  # has to answer for the config it was handed.
  defp delay(duration) do
    if Config.duration?(duration) do
      {:ok, translate(duration)}
    else
      {:error, [{"duration", "must be an ISO-8601 duration, like PT30S or P1D"}]}
    end
  end

  defp translate("P" <> rest) do
    {date, time} =
      case String.split(rest, "T", parts: 2) do
        [date] -> {date, ""}
        [date, time] -> {date, time}
      end

    components(date, %{"Y" => "y", "M" => "mo", "W" => "w", "D" => "d"}) <>
      components(time, %{"H" => "h", "M" => "m", "S" => "s"})
  end

  defp components(source, units) do
    ~r/(\d+)([A-Z])/
    |> Regex.scan(source)
    |> Enum.map_join(fn [_whole, value, unit] -> value <> Map.fetch!(units, unit) end)
  end
end
