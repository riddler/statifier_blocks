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

  alias StatifierBlocks.Core.Config

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

  @impl true
  def emit(block, _context), do: Config.emit_deferred(block)
end
