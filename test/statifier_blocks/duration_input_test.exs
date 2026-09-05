defmodule StatifierBlocks.DurationInputTest do
  @moduledoc """
  ADR-0005 decision 9 as amended 2026-08-29 and again 2026-09-05 (clause
  9a, one grammar): the `:duration` control's reading of typed text,
  asserted with `Phoenix.LiveView` absent.

  That absence is the point of the module existing at all. What a typed
  string means is a function of the string, so it is checkable without a
  LiveView in the room; the renderer that shows the result is the part
  that needs one.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.Core.Duration
  alias StatifierBlocks.CoreFixtures
  alias StatifierBlocks.DurationInput

  doctest StatifierBlocks.DurationInput

  describe "the one accepted spelling" do
    # Sabotage: made `read/1` answer `:invalid` for any string with a
    # letter in it -> every case below went red (verified).
    test "a duration string reads as :duration, carrying its normalisation" do
      for typed <- ["30s", "15m", "1h30m", "2d", "3d8h"] do
        assert {:ok, duration} = Duration.parse(typed)
        assert DurationInput.read(typed) == %{form: :duration, duration: duration, message: ""}
      end
    end

    # The refusal this control is here to pin: the retired spelling is no
    # longer read. It is not a second accepted form, not a form that is
    # canonicalised on the way in, and not a form the message mentions -
    # it is simply not a duration.
    #
    # Sabotage: restored a calendar-format branch in `Core.Duration` ->
    # every value below read `:duration` and this went red on the first
    # (verified).
    test "the calendar spelling is no longer read" do
      for typed <- CoreFixtures.retired_durations() do
        reading = DurationInput.read(typed)

        assert reading.form == :invalid, "#{typed} must not be read as a duration"
        assert reading.duration == nil
      end
    end

    # The examples on the form have to be values the form accepts. A
    # control that teaches a spelling it then refuses is worse than one
    # that teaches nothing.
    test "every example the form shows is a value the control accepts" do
      for example <- DurationInput.examples() do
        assert DurationInput.read(example).form == :duration
      end

      assert DurationInput.read(DurationInput.placeholder()).form == :duration
    end
  end

  describe "empty means the key is omitted" do
    # Sabotage: dropped the `read("")` clause so `""` fell through to
    # `Core.Duration.parse/1` -> `""` read as `:invalid`, a cleared field
    # grew a refusal it should never show, and 2 tests went red (verified).
    test "a cleared field and a never-set field read identically" do
      cleared = DurationInput.read("")
      never_set = DurationInput.read(nil)

      assert cleared == never_set
      assert cleared == %{form: :empty, duration: nil, message: ""}
      refute DurationInput.set?("")
      refute DurationInput.set?(nil)
    end

    # Sabotage: had `read/1` answer `:invalid` for any string carrying a
    # letter -> `0s` read `:invalid` rather than `:duration` and this went
    # red, with 6 others in this file (verified).
    test "there is no third state - a zero duration is a value, not an emptiness" do
      assert DurationInput.read("0s").form == :duration
      assert DurationInput.set?("0s")
    end
  end

  describe "acceptance is Core.Duration's, not a second grammar" do
    # The amendment's "a grammar restated here would be a second opinion
    # that drifts", held mechanically. The spike control this graduates
    # refused fractions, repeated units and sub-second values alike; the
    # shipped module compiles all three, and the record makes that the
    # grammar's call rather than the editor's.
    #
    # Sabotage: added a `String.contains?(text, ".")` refusal ahead of the
    # `parse/1` call -> `1.5h` and `1.5s` went `:invalid` and this went red
    # (verified).
    test "every string Core.Duration parses, this control accepts" do
      for typed <- ["1.5h", "3h2h", "1y2mo", "2w", "1h30m", "500ms", "1.5s", "0s"] do
        assert {:ok, duration} = Duration.parse(typed)
        assert %{form: :duration, duration: ^duration, message: ""} = DurationInput.read(typed)
      end
    end

    test "and every string it refuses, Core.Duration refuses too" do
      for typed <- ["soon", "2d ", "2dx", "P", "PT", "60"] ++ CoreFixtures.retired_durations() do
        assert Duration.parse(typed) == :error
        assert DurationInput.read(typed).form == :invalid
      end
    end
  end

  describe "the refusal says what is accepted, and stops there" do
    # Clause 9d: one grammar means one thing can be wrong, so there is one
    # sentence, and it teaches the shape a duration takes rather than the
    # shape it does not.
    #
    # Sabotage: had `read/1` interpolate the refused text into the message
    # -> a value carrying the retired spelling put it back on screen, and
    # the equality assertion below went red (verified).
    test "one sentence, naming only the accepted shape" do
      for typed <- ["soon", "tomorrow", "2d ", "next tuesday"] ++ CoreFixtures.retired_durations() do
        assert DurationInput.read(typed).message == DurationInput.refusal_message()
      end

      assert DurationInput.refusal_message() == "Not a duration. Try 30s, 15m, 1h30m, 2d, 3d8h."
    end

    # Sabotage: the same letter-refusing mutation noted above -> `2d` read
    # `:invalid` and carried a message, taking this red (verified).
    test "a valid reading carries no message and an invalid one carries no duration" do
      assert DurationInput.read("2d").message == ""
      assert DurationInput.read("soon").duration == nil
    end
  end

  describe "totality" do
    # Sabotage: replaced the catch-all `read/1` clause with a binary guard
    # -> the integer case raised FunctionClauseError instead of refusing
    # (verified).
    test "a non-binary stored value is refused rather than raising" do
      for value <- [3600, %{"a" => 1}, [1, 2], :soon, true] do
        assert DurationInput.read(value).form == :invalid
      end
    end

    # Nothing is trimmed: the stored form is verbatim and `Core.Duration`
    # does not trim either, so a control that trimmed would pass a value
    # the document gate then refuses.
    test "surrounding whitespace is refused, not silently removed" do
      assert DurationInput.read(" 2d").form == :invalid
      assert DurationInput.read("2d ").form == :invalid
      assert DurationInput.read("  ").form == :invalid
    end
  end
end
