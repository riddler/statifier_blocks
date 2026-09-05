defmodule StatifierBlocks.Core.Duration do
  @moduledoc """
  The one duration spelling a `:duration` field may hold, and the
  attribute the engine reads.

  ## One grammar in, one attribute out

  A `:duration` field is **stored** as the string a person types -
  `30s`, `15m`, `1h30m`, `2d`, `3d8h`. That is the whole of the accepted
  form. Whichever string was typed is what `config` holds, byte for byte:
  nothing canonicalises on the way in. That is ADR-0005 decision 9 as
  amended 2026-09-05 (clause 9a; ADR-0002 decision 7's field type is
  untouched - `:duration` still holds a string, and what changed is which
  strings). Every type with a `:duration` field reads this module:
  `core.send`'s `delay` and `core.wait`'s `duration`.

  Compiling one is a single step. `parse/1` hands the stored string to
  `Predicator.Duration.parse/1` and gets back that grammar's normalised
  duration; `to_delay/1` renders that normalised value as the `delay`
  attribute the engine reads. There is no intermediate spelling and
  therefore no third form to keep in step - clause 9c's whole point.

  Two things follow that the earlier arrangement could not give.
  Sub-second and fractional spellings become expressible: `500ms` renders
  as `500ms`, and `1.5s` normalises to one second and five hundred
  milliseconds and renders as `1s500ms`. Both are values
  `Statifier.Duration.to_ms/1` resolves, because the engine reads the
  same grammar this module does.

  ## The grammar has one home, and it is not here

  `Predicator.Duration.parse/1` is the grammar's owner and this module
  calls it rather than re-deriving any part of it. Whatever predicator
  accepts, this module accepts; whatever predicator normalises - a
  fraction expanded into whole components, a repeated unit accumulated,
  the documented 30-day and 365-day approximations on `mo` and `y` - is
  predicator's semantics arriving here already decided, not a second
  opinion formed here. There is no value predicator parses that this
  module refuses.
  """

  # The normalized duration map's keys, largest first, with the unit each
  # one is written with in a `delay` attribute. `Statifier.Duration`
  # recognizes all eight - a strict superset of the SCXML schema's five -
  # so every component has an exact counterpart and rendering is a rename
  # rather than an arithmetic conversion.
  #
  # This is the vocabulary's one such table, and the emitters cite it
  # rather than carrying their own. Nothing here decides how many days a
  # month is, because nothing here has to: the ambiguity stays where the
  # author wrote it and is resolved by the one duration vocabulary the
  # platform shares.
  @units [
    {:years, "y"},
    {:months, "mo"},
    {:weeks, "w"},
    {:days, "d"},
    {:hours, "h"},
    {:minutes, "m"},
    {:seconds, "s"},
    {:milliseconds, "ms"}
  ]

  @zero "0s"

  @doc """
  True for a stored duration this module can compile. Total for any term -
  a non-binary is simply not a duration.

      iex> StatifierBlocks.Core.Duration.duration?("1h30m")
      true

      iex> StatifierBlocks.Core.Duration.duration?("soon")
      false

      iex> StatifierBlocks.Core.Duration.duration?(nil)
      false

  """
  @spec duration?(term()) :: boolean()
  def duration?(value), do: match?({:ok, _duration}, parse(value))

  @doc """
  Parses a stored duration into the expression language's normalised
  duration.

  Anything the grammar does not accept is `:error`, and the caller turns
  that into a finding rather than a raise.

      iex> StatifierBlocks.Core.Duration.parse("1h30m")
      {:ok, %{years: 0, months: 0, weeks: 0, days: 0, hours: 1, minutes: 30, seconds: 0, milliseconds: 0}}

      iex> StatifierBlocks.Core.Duration.parse("soon")
      :error

  """
  @spec parse(term()) :: {:ok, map()} | :error
  def parse(value) when is_binary(value), do: Predicator.Duration.parse(value)
  def parse(_value), do: :error

  @doc """
  Renders a normalised duration as the `delay` attribute the engine reads.

  Component-wise and lossless, largest unit first, omitting the components
  that are zero. A duration whose components are all zero renders as
  `0s` rather than as the empty string, because an empty `delay` is not a
  delay of no time.

      iex> {:ok, duration} = StatifierBlocks.Core.Duration.parse("2h")
      iex> StatifierBlocks.Core.Duration.to_delay(duration)
      "2h"

      iex> {:ok, duration} = StatifierBlocks.Core.Duration.parse("1.5s")
      iex> StatifierBlocks.Core.Duration.to_delay(duration)
      "1s500ms"

  """
  @spec to_delay(map()) :: String.t()
  def to_delay(duration) do
    case Enum.map_join(@units, &component(duration, &1)) do
      "" -> @zero
      rendered -> rendered
    end
  end

  @spec component(map(), {atom(), String.t()}) :: String.t()
  defp component(duration, {key, unit}) do
    case Map.get(duration, key, 0) do
      0 -> ""
      value -> Integer.to_string(value) <> unit
    end
  end
end
