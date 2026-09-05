defmodule StatifierBlocks.DurationInput do
  @moduledoc """
  The `:duration` control's reading of the text an author typed.

  ADR-0005 decision 9, as amended 2026-08-29 and again 2026-09-05 (clause
  9a, one grammar), renders `:duration` as **one text control**:

  | Field type | Rendering |
  |---|---|
  | `:duration` | one text control; duration strings the expression language reads, with on-screen examples |

  The amendment's terms are the whole of this module's job. Each one is a
  function of the typed text and nothing else, which is why the reading
  lives here rather than in `StatifierBlocks.Editor.Field` - this module
  compiles and is asserted with LiveView absent, on the same principle as
  `StatifierBlocks.Finding.severity_class/1`, and ADR-0005 decision 1's
  namespace boundary is what makes that a property rather than a habit.

  ## The three readings, and what each one means to the form

    * `:empty` - the key is **omitted**. A cleared field and a never-set
      field are the same value: there is no zero-duration stand-in and no
      third state for "the author touched this and then did not finish",
      so both read `:empty` and both leave the key out of config.
      `StatifierBlocks.Editor.ConfigForm` is where the omission is
      performed, because that is the module that decides where a decoded
      value is written.
    * `:duration` - a duration string a person types (`30s`, `1h30m`,
      `3d8h`), which is the only form a `:duration` field accepts.
    * `:invalid` - carries the sentence the field shows instead of
      offering an edit at all.

  **The stored form is the author's string verbatim** - nothing here
  canonicalises on the way in, and `duration` is a projection for the
  caller that wants the normalised value, not something to write back.

  ## Acceptance is `StatifierBlocks.Core.Duration`, exactly

  This module decides nothing about which strings are durations. It asks
  `StatifierBlocks.Core.Duration.parse/1`, which asks
  `Predicator.Duration.parse/1`, which owns the grammar. The amendment is
  explicit about why: "A grammar restated here would be a second opinion
  that drifts."

  That is a deliberate difference from the spike control this graduates
  (`sb-709`, `spike/js/panes.js`), which refused a strict subset - a
  sub-second unit, fractional components and repeated units alike. None
  of those three refusals survives. A fraction that normalises into whole
  components (`1.5h` is an hour and a half), a repeated unit that
  accumulates (`3h2h` is five hours) and a sub-second value (`500ms`) are
  all things the amendment names as the grammar's to define, and
  `Core.Duration` compiles all three, so refusing any of them here would
  be the second opinion.

  ## Nothing is trimmed

  `"2d "` is refused rather than read as `"2d"`. The stored form is
  verbatim and `Core.Duration` does not trim either, so trimming here
  would make the inline check and the document gate disagree about the
  same bytes - the inline check would pass a value the gate then refuses,
  which is the one failure a per-field check exists to prevent.

  ## The refusal says what is accepted, and stops there

  One grammar means one thing can be wrong: the text is not a duration.
  The message names the shape a duration takes and offers the examples the
  form already shows, which is the difference between a form that teaches
  and a form that sulks. It is clause 9d that makes that wording part of
  the decision rather than a matter of style. The type-level messages that
  `StatifierBlocks.Core.Send` and `StatifierBlocks.Core.Wait` attach to a
  stored value are theirs.
  """

  alias StatifierBlocks.Core.Duration

  @examples ["30s", "15m", "1h30m", "2d", "3d8h"]
  @placeholder "1h30m"

  @refusal_message "Not a duration. Try #{Enum.join(@examples, ", ")}."

  @typedoc """
  One typed duration, read. `form` is the whole decision; `duration` is
  the normalised projection of a valid reading and `nil` otherwise;
  `message` is the sentence the field shows and is `""` for every reading
  but `:invalid`.
  """
  @type reading :: %{
          form: :empty | :duration | :invalid,
          duration: map() | nil,
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
  The placeholder the empty control carries - one example, in the spelling
  the field stores.

      iex> StatifierBlocks.DurationInput.placeholder()
      "1h30m"

  """
  @spec placeholder() :: String.t()
  def placeholder, do: @placeholder

  @doc """
  The sentence the field shows beneath a refused value.

      iex> StatifierBlocks.DurationInput.refusal_message()
      "Not a duration. Try 30s, 15m, 1h30m, 2d, 3d8h."

  """
  @spec refusal_message() :: String.t()
  def refusal_message, do: @refusal_message

  @doc """
  Reads one stored or typed duration.

  Total for any term. A non-binary stored value - a number an older
  document carried, say - is not a duration and is refused, but it is
  never discarded: the control still renders the bytes the document holds,
  on the same principle as ADR-0005 decision 12.

      iex> StatifierBlocks.DurationInput.read("")
      %{form: :empty, duration: nil, message: ""}

      iex> StatifierBlocks.DurationInput.read("1h30m").form
      :duration

      iex> StatifierBlocks.DurationInput.read("500ms").form
      :duration

      iex> StatifierBlocks.DurationInput.read("soon").message
      "Not a duration. Try 30s, 15m, 1h30m, 2d, 3d8h."

  """
  @spec read(term()) :: reading()
  def read(nil), do: %{form: :empty, duration: nil, message: ""}
  def read(""), do: %{form: :empty, duration: nil, message: ""}

  def read(text) when is_binary(text) do
    case Duration.parse(text) do
      {:ok, duration} -> %{form: :duration, duration: duration, message: ""}
      :error -> %{form: :invalid, duration: nil, message: @refusal_message}
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
end
