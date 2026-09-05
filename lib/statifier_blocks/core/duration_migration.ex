defmodule StatifierBlocks.Core.DurationMigration do
  @moduledoc false

  # The one reader left of the duration spelling ADR-0005 decision 9's
  # 2026-09-05 amendment retired, and the second of the two exceptions that
  # decision's 2026-09-05 Note leaves to clause 9d. It is private on
  # purpose and it has exactly two callers -
  # `StatifierBlocks.Core.Wait.migrate_config/2` and
  # `StatifierBlocks.Core.Send.migrate_config/2`. `validate_config/1`,
  # `Core.Config`, `DurationInput` and every message text are none of them:
  # a `:duration` field still reads one grammar, because by the time the
  # field sees a value this module has already run.
  #
  # The recogniser is the one that shipped before the pivot, character for
  # character - it was `Core.Config`'s own until the amendment removed it:
  # integer components only, since ADR-0001 decision 6 forbids floats in
  # `config`, so no document can hold a shape this does not match. `P` on
  # its own, and a `T` with nothing after it, are both rejected.
  @retired ~r/\AP(?!\z)(\d+Y)?(\d+M)?(\d+W)?(\d+D)?(T(?!\z)(\d+H)?(\d+M)?(\d+S)?)?\z/

  # Component letter to the unit the accepted grammar writes it with,
  # keyed by which side of the `T` it falls on: the same letter means two
  # different units there, which is the whole reason the accepted grammar
  # spells months `mo` at all. This is a rename and never an arithmetic
  # conversion - every component has an exact counterpart, so nothing here
  # decides how many days a month is.
  @date_units %{"Y" => "y", "M" => "mo", "W" => "w", "D" => "d"}
  @time_units %{"H" => "h", "M" => "m", "S" => "s"}

  @component ~r/(\d+)([A-Z])/

  @doc false
  # Rewrites `config[key]` when it holds a value in the retired spelling,
  # and leaves `config` alone otherwise - an absent key, an empty string, a
  # value already in the accepted spelling and a value in neither are all
  # pass-through. A value the rewrite cannot read is a value the field's
  # own refusal is the right answer for, and a failed migration would
  # render the block unopenable rather than fixable.
  @spec migrate_field(map(), String.t()) :: map()
  def migrate_field(config, key) when is_map(config) and is_binary(key) do
    with {:ok, stored} <- Map.fetch(config, key),
         {:ok, migrated} <- rewrite(stored) do
      Map.put(config, key, migrated)
    else
      _other -> config
    end
  end

  @doc false
  # `{:ok, accepted spelling}` for a value in the retired one, `:error` for
  # anything else at all - including a value already accepted, which has
  # nothing to migrate.
  @spec rewrite(term()) :: {:ok, String.t()} | :error
  def rewrite(value) when is_binary(value) do
    if Regex.match?(@retired, value) do
      {date, time} = halves(value)
      {:ok, units(date, @date_units) <> units(time, @time_units)}
    else
      :error
    end
  end

  def rewrite(_value), do: :error

  @spec halves(String.t()) :: {String.t(), String.t()}
  defp halves("P" <> rest) do
    case String.split(rest, "T", parts: 2) do
      [date, time] -> {date, time}
      [date] -> {date, ""}
    end
  end

  @spec units(String.t(), map()) :: String.t()
  defp units(half, table) do
    @component
    |> Regex.scan(half)
    |> Enum.map_join(fn [_whole, count, letter] -> count <> Map.fetch!(table, letter) end)
  end
end
