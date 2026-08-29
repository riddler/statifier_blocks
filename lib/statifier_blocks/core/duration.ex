defmodule StatifierBlocks.Core.Duration do
  @moduledoc """
  The two duration spellings a `:duration` field may hold, and the one
  form the engine reads.

  ## The three forms, and why there are three

  A `:duration` field may be **stored** two ways:

    * a predicator duration string - `1h30m`, `2d`, `3d8h` - the primary
      form, because it is the form a person types;
    * ISO-8601 with integer components - `PT2H`, `P1DT6H` - which is what
      documents written before the two-spelling rule hold and what
      ADR-0001 decision 6's no-floats rule permits.

  Whichever was typed is what `config` holds, byte for byte: the stored
  form is the author's own spelling and nothing canonicalises on the way
  in. That is ADR-0005's 2026-08-29 `:duration` amendment (accepted;
  ADR-0002 decision 7's field type is untouched - `:duration` still holds
  a string, and what changed is which strings). Every type with a
  `:duration` field reads this module: `core.send`'s `delay` and
  `core.wait`'s `duration`.

  Neither stored form is what SCXML's `delay` attribute wants. Statifier
  resolves a `delay` through `Statifier.Duration.to_ms/1`, which reads the
  predicator unit grammar **only** - it answers
  `{:error, {:invalid_delay, "PT2H"}}` for the ISO spelling - so the
  emitted form is the shorthand `48h`, never `PT48H`. A chart carrying ISO
  in a `delay` attribute compiles and then fails to arm, which is why an
  emitter never writes out what it was handed.

  So a compile is two steps rather than one: `to_iso/1` canonicalises
  whichever spelling was stored into ISO-8601, and `to_delay/1` renders
  that canonical value as the attribute the engine reads. ISO is the pivot
  because it is the spelling ADR-0001 already admits into `config` - a
  single canonical form keeps "which of the two did the author type?" out
  of everything downstream of the emitter.

  ## The predicator grammar has one home, and it is not here

  `Predicator.Duration.parse/1` is the grammar's owner and this module
  calls it rather than re-deriving any part of it. Whatever predicator
  accepts, this module accepts; whatever predicator normalises - a
  fraction expanded into whole components, a repeated unit accumulated,
  the documented 30-day and 365-day approximations on `mo` and `y` - is
  predicator's semantics arriving here already decided, not a second
  opinion formed here.

  There is exactly **one** value predicator parses that this module still
  refuses: a duration with milliseconds left in it after normalisation.
  ISO-8601 has no millisecond component and ADR-0001 decision 6 forbids
  the fractional seconds that would be needed to spell one, so `500ms`
  has no canonical form to compile to. That is a fact about the pivot,
  not a disagreement about the grammar, and it is the whole of the gap.

  `sb-709`'s control refuses a wider set - `ms`, fractional components and
  repeated units alike. Being the more permissive of the two is the safe
  direction: every value that control can write, this module compiles.
  """

  alias StatifierBlocks.Core.Config

  # The normalized duration map's keys, in the order ISO-8601 writes them,
  # with the component letter each one takes. `:months` is the date-part
  # `M` and `:minutes` the time-part one, which is the whole reason the
  # predicator grammar spells months `mo` at all.
  @date_components [{:years, "Y"}, {:months, "M"}, {:weeks, "W"}, {:days, "D"}]
  @time_components [{:hours, "H"}, {:minutes, "M"}, {:seconds, "S"}]

  # The reverse map, for rendering a canonical ISO value back out as the
  # `delay` attribute. Keyed by {section, letter} because `M` means two
  # different units depending on which side of the `T` it falls.
  @delay_units %{
    {:date, "Y"} => "y",
    {:date, "M"} => "mo",
    {:date, "W"} => "w",
    {:date, "D"} => "d",
    {:time, "H"} => "h",
    {:time, "M"} => "m",
    {:time, "S"} => "s"
  }

  @zero "PT0S"

  @doc """
  True for either stored spelling: an ISO-8601 duration, or a predicator
  duration string this module can canonicalise.
  """
  @spec duration?(term()) :: boolean()
  def duration?(value), do: Config.duration?(value) or predicator?(value)

  @doc """
  True for a predicator duration string this module can compile. Total for
  any term - a non-binary is simply not a duration.
  """
  @spec predicator?(term()) :: boolean()
  def predicator?(value), do: match?({:ok, _iso}, compile(value))

  @doc """
  Canonicalises a stored duration to ISO-8601.

  An ISO value passes through unchanged - byte for byte, so a document
  that stored `P1DT6H` compiles from exactly those bytes. A predicator
  string is compiled through `Predicator.Duration.parse/1`. Anything else
  is `:error`, and the caller turns that into a finding rather than a
  raise.

      iex> StatifierBlocks.Core.Duration.to_iso("PT2H")
      {:ok, "PT2H"}

      iex> StatifierBlocks.Core.Duration.to_iso("1h30m")
      {:ok, "PT1H30M"}

      iex> StatifierBlocks.Core.Duration.to_iso("3d8h")
      {:ok, "P3DT8H"}

      iex> StatifierBlocks.Core.Duration.to_iso("soon")
      :error

  """
  @spec to_iso(term()) :: {:ok, String.t()} | :error
  def to_iso(value) do
    if Config.duration?(value) do
      {:ok, value}
    else
      compile(value)
    end
  end

  @doc """
  Renders a canonical ISO-8601 duration as the `delay` attribute the
  engine reads.

  Component-wise and lossless. `Statifier.Duration` recognizes `y`, `mo`,
  `w`, `d`, `h`, `m`, `s` and `ms` - a strict superset of the SCXML
  schema's five units - so every ISO component has an exact counterpart
  and the translation is a rename rather than an arithmetic conversion:

  | ISO | `delay` |
  |---|---|
  | `P1Y` | `1y` |
  | `P1M` (before `T`) | `1mo` |
  | `P1W` / `P1D` | `1w` / `1d` |
  | `PT1H` / `PT1M` / `PT1S` | `1h` / `1m` / `1s` |

  This is the vocabulary's one such table, and the emitters cite it rather
  than carrying their own. Nothing here decides how many days a month is,
  because nothing here has to: the ambiguity stays where the author wrote
  it and is resolved by the one duration vocabulary the platform shares.

      iex> StatifierBlocks.Core.Duration.to_delay("PT2H")
      "2h"

      iex> StatifierBlocks.Core.Duration.to_delay("P1DT6H")
      "1d6h"

  """
  @spec to_delay(String.t()) :: String.t()
  def to_delay("P" <> rest) do
    {date, time} =
      case String.split(rest, "T", parts: 2) do
        [date] -> {date, ""}
        [date, time] -> {date, time}
      end

    units(date, :date) <> units(time, :time)
  end

  @spec units(String.t(), :date | :time) :: String.t()
  defp units(source, section) do
    ~r/(\d+)([A-Z])/
    |> Regex.scan(source)
    |> Enum.map_join(fn [_whole, value, letter] ->
      value <> Map.fetch!(@delay_units, {section, letter})
    end)
  end

  # `Predicator.Duration.parse/1` is the grammar; everything below it is
  # rendering. A non-binary never reaches it - `parse/1` has a binary
  # guard, and this module's callers hand it whatever a document stored.
  @spec compile(term()) :: {:ok, String.t()} | :error
  defp compile(value) when is_binary(value) do
    case Predicator.Duration.parse(value) do
      {:ok, duration} -> render(duration)
      :error -> :error
    end
  end

  defp compile(_value), do: :error

  # Milliseconds are the one thing predicator can hold and ISO-8601
  # cannot spell, so a duration still carrying them after normalisation
  # has no canonical form. See the moduledoc.
  @spec render(map()) :: {:ok, String.t()} | :error
  defp render(%{milliseconds: ms}) when ms != 0, do: :error

  defp render(duration) do
    date = section(duration, @date_components)
    time = section(duration, @time_components)

    case {date, time} do
      {"", ""} -> {:ok, @zero}
      {date, ""} -> {:ok, "P" <> date}
      {date, time} -> {:ok, "P" <> date <> "T" <> time}
    end
  end

  @spec section(map(), [{atom(), String.t()}]) :: String.t()
  defp section(duration, components) do
    Enum.map_join(components, fn {key, letter} ->
      case Map.get(duration, key, 0) do
        0 -> ""
        value -> Integer.to_string(value) <> letter
      end
    end)
  end
end
