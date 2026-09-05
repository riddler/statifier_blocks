defmodule StatifierBlocks.Core.DurationMigrationTest do
  @moduledoc """
  The recogniser behind `core.wait`'s and `core.send`'s `migrate_config/2`.

  This file is the second of the two exceptions ADR-0005 decision 9's
  2026-09-05 Note leaves to clause 9d: the recogniser has to recognise the
  thing, so its test holds whole retired-spelling strings as literals to
  pin that it does. It is the only file in the repository that may, and a
  repo-wide sweep for the spelling should find it here and nowhere else.

  The pairs are the corpus `sb-4r1p` migrated, reused here as the oracle
  rather than re-derived: every value in the retired spelling that change
  removed, taken from its own diff, so the recogniser is pinned against
  what real documents actually held.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.Core.{Duration, DurationMigration}

  # Every value in the retired spelling the corpus migration touched: the
  # rendering table's own pairs, the round-trip examples beside them, and
  # every literal its documents and fixtures held. Assembled by diffing the
  # migrating change, so a value it moved and this list forgot is a gap in
  # the oracle rather than a judgement call.
  @corpus [
    {"PT1S", "1s"},
    {"PT2S", "2s"},
    {"PT3S", "3s"},
    {"PT4S", "4s"},
    {"PT8S", "8s"},
    {"PT9S", "9s"},
    {"PT30S", "30s"},
    {"PT99S", "99s"},
    {"PT1M", "1m"},
    {"PT2M", "2m"},
    {"PT5M", "5m"},
    {"PT10M", "10m"},
    {"PT15M", "15m"},
    {"PT45M", "45m"},
    {"PT1H", "1h"},
    {"PT3H", "3h"},
    {"PT5H", "5h"},
    {"PT7H", "7h"},
    {"PT2H", "2h"},
    {"PT9H", "9h"},
    {"PT24H", "24h"},
    {"PT48H", "48h"},
    {"PT1H30M", "1h30m"},
    {"P1D", "1d"},
    {"P2D", "2d"},
    {"P7D", "7d"},
    {"P14D", "14d"},
    {"P1W", "1w"},
    {"P2W", "2w"},
    {"P1M", "1mo"},
    {"P1Y", "1y"},
    {"P3DT8H", "3d8h"},
    {"P1DT6H", "1d6h"},
    {"P1Y2M3DT4H5M6S", "1y2mo3d4h5m6s"},
    {"P1Y2M3W4DT5H6M7S", "1y2mo3w4d5h6m7s"},
    {"PT0S", "0s"}
  ]

  describe "rewrite/1" do
    # Sabotage: swapped the date table's `M` from `mo` to `m` -> `P1M`
    # migrated to a minute and this went red on that pair, which is the
    # pair the whole two-table arrangement exists for.
    test "turns every corpus value into the accepted spelling" do
      for {retired, accepted} <- @corpus do
        assert DurationMigration.rewrite(retired) == {:ok, accepted}, retired
      end
    end

    # A migrated value is only useful if the field it lands in reads it.
    #
    # Sabotage: rendered the components largest-last -> `1y2mo3d4h5m6s`
    # came out reversed and the grammar refused it, red here.
    test "every migrated value is one the accepted grammar reads" do
      for {retired, _accepted} <- @corpus do
        {:ok, migrated} = DurationMigration.rewrite(retired)
        assert Duration.duration?(migrated), retired
      end
    end

    # Sabotage: dropped the `(?!\z)` after `P` -> a bare designator
    # migrated to the empty string instead of refusing, red here.
    test "refuses everything that is not in the retired spelling" do
      for value <- [
            "",
            "P",
            "PT",
            "1h30m",
            "48h",
            "500ms",
            "soon",
            "48h later",
            "P1YT",
            "P1Y2M3W4DT7S5H6M",
            "PT1.5S",
            30,
            nil,
            %{}
          ] do
        assert DurationMigration.rewrite(value) == :error, inspect(value)
      end
    end
  end

  describe "migrate_field/2" do
    # Sabotage: had `migrate_field/2` write the key back unconditionally ->
    # an absent key appeared as `nil` and this went red.
    test "rewrites only the named key, and only when it holds the retired spelling" do
      assert DurationMigration.migrate_field(
               %{"duration" => "PT1H30M", "label" => "PT1H30M"},
               "duration"
             ) == %{"duration" => "1h30m", "label" => "PT1H30M"}

      assert DurationMigration.migrate_field(%{"delay" => "2h"}, "delay") == %{"delay" => "2h"}
      assert DurationMigration.migrate_field(%{"delay" => ""}, "delay") == %{"delay" => ""}

      assert DurationMigration.migrate_field(%{"delay" => "soon"}, "delay") == %{
               "delay" => "soon"
             }

      assert DurationMigration.migrate_field(%{"delay" => nil}, "delay") == %{"delay" => nil}

      assert DurationMigration.migrate_field(%{"event" => "signup.abandoned"}, "delay") == %{
               "event" => "signup.abandoned"
             }
    end
  end
end
