defmodule StatifierBlocks.DurationInput do
  @moduledoc """
  The `:duration` control's reading of the text an author typed.

  ADR-0005 decision 9, as amended 2026-08-29 (the `:duration` control,
  predicator strings primary), renders `:duration` as **one text control**:

  | Field type | Rendering |
  |---|---|
  | `:duration` | one text control; predicator duration strings primary, with on-screen examples |

  The amendment's terms are the whole of this module's job. Each one is a
  function of the typed text and nothing else, which is why the reading
  lives here rather than in `StatifierBlocks.Editor.Field` - this module
  compiles and is asserted with LiveView absent, on the same principle as
  `StatifierBlocks.Finding.severity_class/1`, and ADR-0005 decision 1's
  namespace boundary is what makes that a property rather than a habit.

  ## The four readings, and what each one means to the form

    * `:empty` - the key is **omitted**. A cleared field and a never-set
      field are the same value: there is no `PT0S` and no third state for
      "the author touched this and then did not finish", so both read
      `:empty` and both leave the key out of config. `StatifierBlocks.Editor.ConfigForm`
      is where the omission is performed, because that is the module that
      decides where a decoded value is written.
    * `:predicator` - a duration string a person types (`1h30m`, `3d8h`),
      which the amendment makes the primary input.
    * `:iso` - ISO-8601 (`PT1H30M`), still accepted because it is the
      spelling ADR-0001 decision 6 already admits into config and the one
      existing documents hold. A field that refused it would refuse values
      already written.
    * `:invalid` - carries the sentence the field shows instead of
      offering an edit at all.

  The two valid readings differ only in what the author typed. **The
  stored form is the author's string verbatim** - nothing here
  canonicalises on the way in, and `iso` is a projection for the caller
  that wants one, not a value to write back.

  ## Acceptance is `StatifierBlocks.Core.Duration`, exactly

  This module decides nothing about which strings are durations. It asks
  `StatifierBlocks.Core.Duration.to_iso/1`, which asks
  `Predicator.Duration.parse/1`, which owns the grammar. The amendment is
  explicit about why: "A grammar restated here would be a second opinion
  that drifts."

  That is a deliberate difference from the spike control this graduates
  (`sb-709`, `spike/js/panes.js`), which refused a strict subset -
  milliseconds, fractional components and repeated units alike. Two of
  those three refusals do not survive the amendment. A fraction that
  normalises into whole ISO components (`1.5h` is `PT1H30M`) and a
  repeated unit that accumulates (`3h2h` is `PT5H`) are both things the
  amendment names as predicator's to define, and `Core.Duration` compiles
  both, so refusing them here would be the second opinion. Milliseconds
  are the one refusal that stays, because it is a fact about the ISO
  pivot rather than a reading of the grammar: ISO-8601 has no millisecond
  component, so `500ms` and `1.5s` have no canonical form to compile to.

  ## Nothing is trimmed

  `"2d "` is refused rather than read as `"2d"`. The stored form is
  verbatim and `Core.Duration` does not trim either, so trimming here
  would make the inline check and the document gate disagree about the
  same bytes - the inline check would pass a value the gate then refuses,
  which is the one failure a per-field check exists to prevent.

  ## Why the refusal is three sentences and not one

  "Not a duration" is true of `soon` and of `500ms` alike, and the second
  is a person who knows the grammar hitting the pivot's limit. Telling
  them which of the two they hit is the difference between a form that
  teaches and a form that sulks. The three messages are this module's;
  the type-level messages that `StatifierBlocks.Core.Send` and
  `StatifierBlocks.Core.Wait` attach to a stored value are theirs.
  """

  alias StatifierBlocks.Core.Duration

  @examples ["30s", "15m", "1h30m", "2d", "3d8h"]
  @placeholder "1h30m"

  @milliseconds_message "Milliseconds are not stored here - the smallest unit is a second."
  @fraction_message "A part-unit that leaves milliseconds is not stored here - say 1h30m rather than 1.5s."
  @refusal_message "Not a duration. Try #{Enum.join(@examples, ", ")}, or ISO-8601 like PT1H30M."

  @typedoc """
  One typed duration, read. `form` is the whole decision; `iso` is the
  canonical projection of a valid reading and `""` otherwise; `message` is
  the sentence the field shows and is `""` for every reading but
  `:invalid`.
  """
  @type reading :: %{
          form: :empty | :predicator | :iso | :invalid,
          iso: String.t(),
          message: String.t()
        }

  @doc """
  The examples the form shows beside the field, in the amendment's order.

  They are what replaces the affordance the retired unit dropdown used to
  carry: they are the form a person types, and showing them is how an
  author who has never typed a duration learns the spelling.

      iex> StatifierBlocks.DurationInput.examples()
      ["30s", "15m", "1h30m", "2d", "3d8h"]

  """
  @spec examples() :: [String.t()]
  def examples, do: @examples

  @doc """
  The placeholder the empty control carries - one example, in the primary
  spelling.

      iex> StatifierBlocks.DurationInput.placeholder()
      "1h30m"

  """
  @spec placeholder() :: String.t()
  def placeholder, do: @placeholder

  @doc """
  Reads one stored or typed duration.

  Total for any term. A non-binary stored value - a number an older
  document carried, say - is not a duration and is refused, but it is
  never discarded: the control still renders the bytes the document holds,
  on the same principle as ADR-0005 decision 12.

      iex> StatifierBlocks.DurationInput.read("")
      %{form: :empty, iso: "", message: ""}

      iex> StatifierBlocks.DurationInput.read("1h30m")
      %{form: :predicator, iso: "PT1H30M", message: ""}

      iex> StatifierBlocks.DurationInput.read("PT1H30M")
      %{form: :iso, iso: "PT1H30M", message: ""}

      iex> StatifierBlocks.DurationInput.read("500ms").message
      "Milliseconds are not stored here - the smallest unit is a second."

  """
  @spec read(term()) :: reading()
  def read(nil), do: %{form: :empty, iso: "", message: ""}
  def read(""), do: %{form: :empty, iso: "", message: ""}

  def read(text) when is_binary(text) do
    case Duration.to_iso(text) do
      {:ok, iso} -> %{form: form_of(text), iso: iso, message: ""}
      :error -> %{form: :invalid, iso: "", message: refusal(text)}
    end
  end

  def read(value), do: read(inspect(value))

  @doc """
  True when a value belongs in config at all - `false` exactly for the
  reading that omits the key.

      iex> StatifierBlocks.DurationInput.set?("2d")
      true

      iex> StatifierBlocks.DurationInput.set?("")
      false

  """
  @spec set?(term()) :: boolean()
  def set?(value), do: read(value).form != :empty

  # The two grammars cannot collide - an ISO duration starts with `P` and a
  # predicator one starts with a digit - so which spelling was typed is a
  # property of the first byte rather than of a parse.
  @spec form_of(String.t()) :: :predicator | :iso
  defp form_of("P" <> _rest), do: :iso
  defp form_of(_text), do: :predicator

  # Why this string is not a duration, said as specifically as the text
  # allows. A refusal that predicator itself parsed can only be the
  # millisecond gap - see the moduledoc - and the author's own text says
  # whether they spelled it `ms` or reached it through a fraction.
  @spec refusal(String.t()) :: String.t()
  defp refusal(text) do
    case Predicator.Duration.parse(text) do
      {:ok, %{milliseconds: ms}} when ms != 0 ->
        if String.contains?(text, "."), do: @fraction_message, else: @milliseconds_message

      _other ->
        @refusal_message
    end
  end
end
