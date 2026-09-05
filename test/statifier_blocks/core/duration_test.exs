defmodule StatifierBlocks.Core.DurationTest do
  @moduledoc """
  The one stored spelling a `:duration` field may hold and the `delay`
  attribute the engine actually reads (ADR-0005 decision 9 as amended
  2026-09-05, clause 9a).
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{Block, Compiler, CoreFixtures, Document, Palette}
  alias StatifierBlocks.Core.Duration

  doctest StatifierBlocks.Core.Duration

  describe "parse/1" do
    # Sabotage: had `parse/1` answer `{:ok, value}` with the stored string
    # instead of calling `Predicator.Duration.parse/1` -> nothing was
    # normalised, this went red on the first assertion, and 16 of this
    # file's cases went with it (verified).
    test "hands the stored string to the grammar's owner and returns its normalisation" do
      assert Duration.parse("2h") == Predicator.Duration.parse("2h")
      assert {:ok, %{hours: 1, minutes: 30}} = Duration.parse("1h30m")
      assert {:ok, %{days: 3, hours: 8}} = Duration.parse("3d8h")
    end

    # Whatever the grammar normalises arrives here already decided: a
    # fraction is expanded into whole components and a repeated unit
    # accumulates. This module forms no second opinion about either.
    #
    # Sabotage: had `parse/1` refuse any string containing `.` -> `1.5h`
    # went `:error` while `1h30m` did not, taking this red on the first
    # assertion (verified).
    test "the grammar's normalisation arrives already decided" do
      assert Duration.parse("1.5h") == Duration.parse("1h30m")
      assert Duration.parse("3h2h") == Duration.parse("5h")
      assert Duration.parse("8h3d") == Duration.parse("3d8h")
      assert Duration.parse("30m1h") == Duration.parse("1h30m")
    end

    # The retired spelling is no longer read. It is refused for the
    # ordinary reason every other non-duration is: the grammar does not
    # parse it, and there is no second recogniser left to catch it.
    #
    # Sabotage: restored a calendar-format branch ahead of the grammar
    # call -> the first two values below parsed and this went red
    # (verified).
    test "a value the one grammar does not parse is refused, whatever else it might have meant" do
      for bad <-
            ["", "   ", "soon", "7200", "2 h", "h", "-1h", "2d ", 30, nil, :h] ++
              CoreFixtures.retired_durations() do
        assert Duration.parse(bad) == :error, "#{inspect(bad)} must not parse"
      end
    end
  end

  describe "to_delay/1" do
    # Sabotage: mapped `:months` to `m` rather than `mo` -> a
    # month-valued duration emitted as minutes, which is the one mistake
    # this table exists to prevent (verified).
    test "renders each component onto the unit vocabulary the engine reads" do
      assert delay("1y") == "1y"
      assert delay("1mo") == "1mo"
      assert delay("2w") == "2w"
      assert delay("1d") == "1d"
      assert delay("1h") == "1h"
      assert delay("1m") == "1m"
      assert delay("30s") == "30s"
      assert delay("1y2mo3d4h5m6s") == "1y2mo3d4h5m6s"
    end

    # The rendering walks the unit table largest-first rather than the
    # map, so the order the author typed is gone by the time anything is
    # emitted: an emitter that leaked it would emit two different charts
    # for two spellings of one duration.
    #
    # Sabotage: had `to_delay/1` walk `Map.keys(duration)` rather than the
    # ordered `@units` -> the map's keys come out alphabetically, so the
    # components rendered in the wrong order and 4 of this file's tests
    # went red, this one among them (verified).
    test "components come out largest first, whatever order they were typed in" do
      assert delay("7s6m5h4d3w2mo1y") == "1y2mo3w4d5h6m7s"
      assert delay("30m1h") == "1h30m"
    end

    # Sub-second and fractional spellings are the two the retired
    # intermediate form could not express, and they are the reason this
    # change is a breaking one rather than a tidy-up.
    #
    # Sabotage: reinstated the millisecond refusal in `parse/1` -> the
    # sub-second and fractional values went `:error` and this test and the
    # one below it went red, with the `1.5s` doctest (verified).
    test "a sub-second duration round-trips" do
      assert delay("500ms") == "500ms"
      assert {:ok, 500} = Statifier.Duration.to_ms("500ms")
    end

    # Sabotage: the same millisecond refusal noted above - red here too,
    # `1.5s` normalising to a second plus 500ms (verified).
    test "a fractional-second duration round-trips through its normalisation" do
      assert delay("1.5s") == "1s500ms"
      assert {:ok, 1500} = Statifier.Duration.to_ms(delay("1.5s"))
    end

    # Sabotage: dropped the all-zero clause so a zero duration rendered as
    # `""` -> `core.wait` emitted `delay=""`, which is not a delay of no
    # time but an unparseable attribute (verified).
    test "a zero duration renders as a zero, never as the empty string" do
      assert delay("0s") == "0s"
      assert {:ok, 0} = Statifier.Duration.to_ms(delay("0s"))
    end

    # Sabotage: had `to_delay/1` emit `mo` as `M` -> `to_ms/1` refused the
    # emitted attribute, which is the property this whole module exists to
    # hold (verified).
    test "every rendered attribute is one the engine resolves" do
      for stored <- ["30s", "1h30m", "2d", "3d8h", "1y2mo3w4d5h6m7s", "500ms", "1.5s", "0s"] do
        assert {:ok, _ms} = Statifier.Duration.to_ms(delay(stored)),
               "#{stored} must render an attribute the engine reads"
      end
    end
  end

  describe "duration?/1" do
    # Sabotage: made `duration?/1` answer `true` for any binary -> the
    # last three below went red (verified).
    test "accepts what the grammar parses and nothing else" do
      assert Duration.duration?("1h30m")
      assert Duration.duration?("500ms")
      refute Enum.any?(CoreFixtures.retired_durations(), &Duration.duration?/1)
      refute Duration.duration?("soon")
      refute Duration.duration?(nil)
    end
  end

  describe "the compiled chart is the normalisation, not the stored bytes" do
    # Two spellings of one span are one chart, because the emitter renders
    # the normalised value rather than what the author typed.
    #
    # Sabotage: had `Core.Wait.emit/2` write the stored bytes as the
    # `delay` attribute instead of `Duration.to_delay/1`'s rendering ->
    # every pair produced two different documents (verified).
    test "a core.wait document compiles to the same SCXML under either spelling of one span" do
      for {typed, normalised} <- [
            {"1.5h", "1h30m"},
            {"3h2h", "5h"},
            {"8h3d", "3d8h"},
            {"30m1h", "1h30m"},
            {"1.5s", "1s500ms"}
          ] do
        assert wait_scxml(typed) == wait_scxml(normalised),
               "core.wait #{typed} and core.wait #{normalised} must compile to one chart"
      end
    end

    defp wait_scxml(duration) do
      root =
        Block.new("core.sequence",
          id: "blk_ROOT",
          slots: %{
            "body" => [
              Block.new("core.wait", id: "blk_WAIT", config: %{"duration" => duration})
            ]
          }
        )

      {:ok, compiled} = Compiler.compile(Document.new(root, id: "bdoc_DUR"), Palette.core())
      compiled.scxml
    end
  end

  defp delay(stored) do
    {:ok, duration} = Duration.parse(stored)
    Duration.to_delay(duration)
  end
end
