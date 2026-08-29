defmodule StatifierBlocks.Core.DurationTest do
  @moduledoc """
  The two stored spellings a `:duration` field may hold, the ISO-8601
  pivot between them, and the `delay` attribute the engine actually reads
  (campaign 014's D4 proposal, `sb-709`).
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{Block, Compiler, Document, Palette}
  alias StatifierBlocks.Core.Duration

  doctest StatifierBlocks.Core.Duration

  describe "to_iso/1" do
    # Sabotage: made `to_iso/1` compile every value instead of checking
    # `Config.duration?/1` first -> `P1DT6H` came back re-rendered rather
    # than as the stored bytes, and the identity assertions went red
    # (verified).
    test "an ISO value passes through byte for byte" do
      for iso <- ["PT30S", "PT48H", "P1D", "P1Y2M3DT4H5M6S", "P2W", "P1DT6H"] do
        assert Duration.to_iso(iso) == {:ok, iso}
      end
    end

    # The last three assertions are the canonical-order property, and it
    # is worth pinning rather than assuming: an emitter that leaked the
    # order the author typed would emit two different charts for two
    # spellings of one duration. `Predicator.Duration.parse/1` returns a
    # keyed map rather than an ordered token run, so the stored order is
    # already gone by the time this module renders - but only as long as
    # the render walks the ISO vocabulary rather than the map.
    #
    # Sabotage: dropped the `T` from `render/1`'s date-and-time arm so a
    # time-only duration rendered as `P1H30M` -> red on every case with an
    # hour, minute or second in it. Second sabotage, for the ordering
    # half: had `section/2` walk `Map.keys(duration)` rather than the
    # ordered `@date_components` / `@time_components` -> the map's keys
    # come out alphabetically, so `1y2mo3w4d5h6m7s` compiled to
    # `P1Y2M3W4DT7S5H6M`, taking this red (both verified).
    test "a predicator string compiles to ISO-8601, components in ISO order" do
      assert Duration.to_iso("2h") == {:ok, "PT2H"}
      assert Duration.to_iso("1h30m") == {:ok, "PT1H30M"}
      assert Duration.to_iso("2d") == {:ok, "P2D"}
      assert Duration.to_iso("3d8h") == {:ok, "P3DT8H"}
      assert Duration.to_iso("1y2mo3w4d5h6m7s") == {:ok, "P1Y2M3W4DT5H6M7S"}
      assert Duration.to_iso("0s") == {:ok, "PT0S"}

      assert Duration.to_iso("8h3d") == Duration.to_iso("3d8h")
      assert Duration.to_iso("30m1h") == {:ok, "PT1H30M"}
    end

    # Milliseconds are the one thing predicator holds and ISO-8601 cannot
    # spell, so they are the one thing this module refuses that predicator
    # accepts - after normalisation, which is why `1.5s` (one second and
    # 500ms) is refused and `1.5h` (an hour and 30 minutes) is not.
    #
    # Sabotage: dropped `render/1`'s `milliseconds != 0` clause -> every
    # value below compiled, `500ms` to a bare `PT0S`-shaped duration that
    # silently lost half a second, taking this red (verified).
    test "refuses a duration with milliseconds left after normalisation" do
      assert Duration.to_iso("500ms") == :error
      assert Duration.to_iso("1.5s") == :error
      assert Duration.to_iso("0.5ms") == :error
    end

    # Predicator owns the grammar, so what it normalises arrives here
    # already decided: a fraction is expanded into whole components and a
    # repeated unit accumulates. `sb-709`'s control refuses both, which
    # makes this module the more permissive of the two - the safe
    # direction, since every value that control can write compiles here.
    #
    # Sabotage: had `compile/1` re-derive the grammar from
    # `Predicator.Lexer.tokenize/1` instead of calling
    # `Predicator.Duration.parse/1` -> the token stream carries no
    # normalisation, `1.5h` lexed as a `:fractional_number` and `3h2h` as
    # two hour components, and both went `:error`, taking this red
    # (verified).
    test "predicator's normalisation arrives already decided" do
      assert Duration.to_iso("1.5h") == {:ok, "PT1H30M"}
      assert Duration.to_iso("3h2h") == {:ok, "PT5H"}
    end

    # Sabotage: had `compile/1` answer `{:ok, "PT0S"}` on
    # `Predicator.Duration.parse/1`'s `:error` -> every value below became
    # a zero duration rather than a finding, taking this red (verified).
    test "refuses everything that is not a duration in either spelling" do
      for bad <- [
            "",
            "   ",
            "soon",
            "7200",
            "P",
            "PT",
            "PT48H later",
            "2 h",
            "h",
            "-1h",
            30,
            nil,
            :h
          ] do
        assert Duration.to_iso(bad) == :error
      end
    end
  end

  describe "to_delay/1" do
    # Sabotage: mapped the date-part `M` to `m` rather than `mo` -> a
    # month-valued duration emitted as minutes, which is the one mistake
    # this table exists to prevent (verified).
    test "renames ISO components onto the predicator unit vocabulary" do
      assert Duration.to_delay("P1Y") == "1y"
      assert Duration.to_delay("P1M") == "1mo"
      assert Duration.to_delay("P2W") == "2w"
      assert Duration.to_delay("P1D") == "1d"
      assert Duration.to_delay("PT1H") == "1h"
      assert Duration.to_delay("PT1M") == "1m"
      assert Duration.to_delay("PT30S") == "30s"
      assert Duration.to_delay("P1Y2M3DT4H5M6S") == "1y2mo3d4h5m6s"
    end

    # Sabotage: passed `:date` for both halves in `to_delay/1` -> `PT1M`
    # rendered as `1mo`, so the round trip landed a month where a minute
    # was stored, taking this red (verified).
    test "round-trips a predicator string through the ISO pivot unchanged" do
      for stored <- ["2h", "1h30m", "2d", "3d8h", "1y2mo3w4d5h6m7s"] do
        {:ok, iso} = Duration.to_iso(stored)
        assert Duration.to_delay(iso) == stored
      end
    end
  end

  describe "duration?/1 and predicator?/1" do
    # Sabotage: made `duration?/1` answer `predicator?/1` alone -> the ISO
    # value went red, which is the half `core.wait` has always accepted
    # (verified).
    test "duration?/1 accepts either stored spelling and nothing else" do
      assert Duration.duration?("PT2H")
      assert Duration.duration?("1h30m")
      refute Duration.duration?("soon")
      refute Duration.duration?(nil)
    end

    # Sabotage: made `predicator?/1` fall back to `Config.duration?/1` ->
    # `PT2H` was reported as a predicator string, blurring the two
    # spellings this pair of predicates exists to keep apart (verified).
    # `PT2H` is not a predicator duration for a reason worth stating: `P`
    # and `T` are not units, so predicator refuses the whole string.
    test "predicator?/1 is the narrower one: an ISO value is not one" do
      assert Duration.predicator?("1h30m")
      refute Duration.predicator?("PT2H")
    end
  end

  describe "the sb-dkb authored-spelling flip emits identical bytes" do
    # Every duration literal `sb-dkb` retyped, as it was stored before and
    # as it is stored now. Adding a conversion to a fixture without adding
    # it here is the mistake this table is the guard against.
    @flipped [
      {"PT2M", "2m"},
      {"PT24H", "24h"},
      {"PT30S", "30s"},
      {"PT10M", "10m"},
      {"PT15M", "15m"},
      {"PT1M", "1m"},
      {"P2D", "2d"},
      {"PT2H", "2h"},
      {"P7D", "7d"},
      {"P14D", "14d"},
      {"PT1H", "1h"}
    ]

    # Sabotage: dropped `to_iso/1`'s `Config.duration?/1` branch so a stored
    # ISO value went to `compile/1` rather than passing through -> predicator
    # does not lex `P` or `T`, every left-hand spelling came back `:error`,
    # and the match on `{:ok, from_iso}` took this red (verified).
    test "each retyped literal renders the same delay attribute as before" do
      for {iso, predicator} <- @flipped do
        {:ok, from_iso} = Duration.to_iso(iso)
        {:ok, from_predicator} = Duration.to_iso(predicator)

        assert Duration.to_delay(from_iso) == Duration.to_delay(from_predicator),
               "#{iso} and #{predicator} must emit one delay, not two"
      end
    end

    # The same claim one level up, through the real compiler rather than
    # the duration module alone: a `core.wait` document is compiled with
    # each spelling and the two SCXML strings are compared byte for byte.
    #
    # Sabotage: had `Core.Wait.emit/2` write the stored bytes as the
    # `delay` attribute instead of `Duration.to_delay/1`'s rendering ->
    # every pair produced two different documents (verified).
    test "a core.wait document compiles to the same SCXML under either spelling" do
      for {iso, predicator} <- @flipped do
        assert wait_scxml(iso) == wait_scxml(predicator),
               "core.wait #{iso} and core.wait #{predicator} must compile to one chart"
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

      {:ok, compiled} = Compiler.compile(Document.new(root, id: "bdoc_DKB"), Palette.core())
      compiled.scxml
    end
  end
end
