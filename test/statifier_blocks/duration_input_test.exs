defmodule StatifierBlocks.DurationInputTest do
  @moduledoc """
  ADR-0005 decision 9 as amended 2026-08-29: the `:duration` control's
  reading of typed text, asserted with `Phoenix.LiveView` absent.

  That absence is the point of the module existing at all. What a typed
  string means is a function of the string, so it is checkable without a
  LiveView in the room; the renderer that shows the result is the part
  that needs one.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.Core.Duration
  alias StatifierBlocks.DurationInput

  doctest StatifierBlocks.DurationInput

  describe "the two accepted spellings" do
    test "a predicator string reads as :predicator, with its ISO projection" do
      for {typed, iso} <- [
            {"30s", "PT30S"},
            {"15m", "PT15M"},
            {"1h30m", "PT1H30M"},
            {"2d", "P2D"},
            {"3d8h", "P3DT8H"}
          ] do
        assert DurationInput.read(typed) == %{form: :predicator, iso: iso, message: ""}
      end
    end

    # Sabotage: made `form_of/1` return `:predicator` unconditionally -> 3 of
    # this file's tests went red, this one first, on `:predicator` where the
    # spelling the author typed was ISO (verified).
    test "ISO-8601 is still accepted, and reads as itself" do
      for iso <- ["PT30S", "PT1H30M", "P1DT6H", "P2W", "PT0S"] do
        assert DurationInput.read(iso) == %{form: :iso, iso: iso, message: ""}
      end
    end

    # The examples on the form have to be values the form accepts. A
    # control that teaches a spelling it then refuses is worse than one
    # that teaches nothing.
    test "every example the form shows is a value the control accepts" do
      for example <- DurationInput.examples() do
        assert DurationInput.read(example).form == :predicator
      end

      assert DurationInput.read(DurationInput.placeholder()).form == :predicator
    end
  end

  describe "empty means the key is omitted" do
    # Sabotage: dropped the `read("")` clause so `""` fell through to
    # `Core.Duration.to_iso/1` -> `""` read as `:invalid`, a cleared field
    # grew a refusal it should never show, and 3 tests went red (verified).
    test "a cleared field and a never-set field read identically" do
      cleared = DurationInput.read("")
      never_set = DurationInput.read(nil)

      assert cleared == never_set
      assert cleared == %{form: :empty, iso: "", message: ""}
      refute DurationInput.set?("")
      refute DurationInput.set?(nil)
    end

    test "there is no third state - PT0S is a value, not an emptiness" do
      assert DurationInput.read("PT0S").form == :iso
      assert DurationInput.set?("PT0S")
    end
  end

  describe "acceptance is Core.Duration's, not a second grammar" do
    # The amendment's "a grammar restated here would be a second opinion
    # that drifts", held mechanically. The spike control this graduates
    # refused fractions and repeated units; the shipped module compiles
    # both, and the record makes that predicator's call rather than the
    # editor's.
    #
    # Sabotage: added a `String.contains?(text, ".")` refusal ahead of the
    # `to_iso/1` call -> `1.5h` went `:invalid` and this went red on the
    # first assertion (verified).
    test "every string Core.Duration compiles, this control accepts" do
      for typed <- ["1.5h", "3h2h", "1y2mo", "2w", "P1Y", "1h30m", "PT1H30M"] do
        assert {:ok, iso} = Duration.to_iso(typed)
        assert %{form: form, iso: ^iso, message: ""} = DurationInput.read(typed)
        assert form in [:predicator, :iso]
      end
    end

    test "and every string it refuses, Core.Duration refuses too" do
      for typed <- ["500ms", "1.5s", "soon", "2d ", "2dx", "P", "PT", "60"] do
        assert Duration.to_iso(typed) == :error
        assert DurationInput.read(typed).form == :invalid
      end
    end
  end

  describe "the refusal says which limit was hit" do
    # Sabotage: collapsed `refusal/1` to the generic sentence -> every
    # millisecond case came back "Not a duration" and 3 tests went red, the
    # doctest for `read("500ms")` among them (verified).
    test "milliseconds spelled as a unit" do
      assert DurationInput.read("500ms").message =~ "Milliseconds are not stored here"
      assert DurationInput.read("1h500ms").message =~ "Milliseconds are not stored here"
    end

    test "a fraction that leaves milliseconds behind" do
      assert DurationInput.read("1.5s").message =~ "leaves milliseconds"
    end

    test "anything predicator does not parse at all" do
      for typed <- ["soon", "tomorrow", "2d ", "next tuesday"] do
        assert DurationInput.read(typed).message =~
                 "Not a duration. Try 30s, 15m, 1h30m, 2d, 3d8h"
      end
    end

    test "a valid reading carries no message and an invalid one carries no ISO" do
      assert DurationInput.read("2d").message == ""
      assert DurationInput.read("soon").iso == ""
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
