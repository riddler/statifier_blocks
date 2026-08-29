defmodule StatifierBlocks.BlockType.PresentationMetadataTest do
  @moduledoc """
  ADR-0002 amendment B's presentation trio, declaration side.

  One test per row of B3's normalizer table, for the two declarations this
  module owns - `badge/1` and `join_label/2`. The third, `accent_token`,
  landed with the graduation work and is covered one module over in
  `view_model/accent_and_rail_test.exs`; the table below is the same
  discipline arriving at the other two keys.

  The properties under test are B3's two named ones. **Refuse, never
  truncate**: every malformed declaration answers the default, and an
  over-long badge is `nil` rather than a 24-character prefix - which is
  why each over-long case asserts the answer is `nil` rather than merely
  that it is not the input. And **a callback that raises degrades to the
  default**, which is the one place this package rescues to a default on
  purpose.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.BlockType

  doctest StatifierBlocks.BlockType, only: [badge: 1, join_label: 2]

  # 24 graphemes, the cap itself, and one more.
  @at_cap "calls the host and waits"
  @over_cap "calls the host and waited"

  describe "badge/1" do
    # Sabotage: made `badge/1` read `Map.get(entry, :label)` - red here,
    # since the entry's label is not its chip (verified).
    test "answers a declared chip" do
      assert BlockType.badge(%{badge: "manual review"}) == "manual review"
      assert BlockType.badge(%{badge: "timer"}) == "timer"
    end

    # Sabotage: changed the cap comparison to `>=` - red on the at-cap
    # assert, which is what pins the boundary rather than its neighbourhood
    # (verified).
    test "accepts a chip exactly at the cap and refuses the one past it" do
      assert String.length(@at_cap) == 24
      assert String.length(@over_cap) == 25

      assert BlockType.badge(%{badge: @at_cap}) == @at_cap
      assert BlockType.badge(%{badge: @over_cap}) == nil
    end

    # Sabotage: replaced the over-cap arm with
    # `String.slice(text, 0, @presentation_cap)` - red here, which is the
    # assert that makes "refuse, never truncate" a test rather than a
    # comment (verified).
    test "an over-long chip is dropped, not clipped" do
      refused = BlockType.badge(%{badge: @over_cap})

      assert refused == nil
      refute refused == String.slice(@over_cap, 0, 24)
    end

    # Sabotage: dropped the whitespace and control-character arms from
    # `chip/1` - red on each row here (verified).
    test "refuses every malformed declaration B3 names" do
      for declared <- [
            "",
            "   ",
            "\t",
            "two\nlines",
            "two\r\nlines",
            "tab\tseparated",
            @over_cap,
            :manual_review,
            42,
            nil,
            ["manual review"]
          ] do
        assert BlockType.badge(%{badge: declared}) == nil,
               "#{inspect(declared)} should have been refused"
      end
    end

    # Sabotage: dropped the total `def badge(_entry), do: nil` clause, so a
    # non-map entry raised FunctionClauseError - red here, and totality is
    # the whole point of a normalizer (verified).
    test "is total over an entry that declares nothing at all" do
      assert BlockType.badge(%{}) == nil
      assert BlockType.badge(%{label: "Risk hold"}) == nil
      assert BlockType.badge("not an entry") == nil
      assert BlockType.badge(nil) == nil
    end
  end

  describe "join_label/2" do
    # Sabotage: made `join_label/2` ignore its config argument and call the
    # declared function with `%{}` - red here, since B2's whole point is
    # that the marker is a function of *this block's* config (verified).
    test "calls the declared function with the block's config" do
      entry = %{join_label: fn config -> Map.get(config, "join_word", "and") end}

      assert BlockType.join_label(entry, %{"join_word" => "all of"}) == "all of"
      assert BlockType.join_label(entry, %{}) == "and"
    end

    # Sabotage: removed the `rescue` from `call_join_label/2` - red here,
    # which is B3's "a callback that raises degrades to the default" and
    # the one rescue-to-default this package allows (verified).
    test "a raising callback degrades to the default" do
      entry = %{join_label: fn _config -> raise "host bug" end}

      assert BlockType.join_label(entry, %{}) == nil
    end

    # Sabotage: removed the `catch` block - red on both rows, since a throw
    # and an exit leave the layout pass exactly where a raise does
    # (verified).
    test "a throwing or exiting callback degrades to the default" do
      assert BlockType.join_label(%{join_label: fn _config -> throw(:nope) end}, %{}) == nil
      assert BlockType.join_label(%{join_label: fn _config -> exit(:nope) end}, %{}) == nil
    end

    # Sabotage: widened the guard to `is_function(declared)`, then dropped
    # the guard and the `_refused` arm entirely - BOTH STAYED GREEN, which is
    # a real finding rather than a missing assert. A wrong-arity or
    # non-function call raises, and the rescue below it degrades that to the
    # same `nil` this test asserts, so no mutation of the guard alone can be
    # observed from outside. The guard is therefore defence in depth - B3
    # says a non-function is refused *without being called*, and that is a
    # property of the mechanism, not of the answer. What this test pins is
    # the answer, and it would catch a clause that returned the declaration
    # itself or let the exception out.
    test "refuses a declaration that is not a one-argument function" do
      for declared <- [
            "not a function",
            fn -> "no argument" end,
            fn _one, _two -> "two arguments" end,
            :join_label,
            nil
          ] do
        assert BlockType.join_label(%{join_label: declared}, %{}) == nil,
               "#{inspect(declared)} should have been refused unread"
      end
    end

    # Sabotage: had `join_label/2` return the callback's value directly
    # instead of piping it through `chip/1` - red on every row here, which
    # is B3's "the same set, applied to the callback's return" (verified).
    test "applies the badge refusal set to the callback's return" do
      for returned <- ["", "  ", "in\ntwo lines", "tab\there", @over_cap, :atom, 7, nil] do
        assert BlockType.join_label(%{join_label: fn _config -> returned end}, %{}) == nil,
               "#{inspect(returned)} should have been refused"
      end

      assert BlockType.join_label(%{join_label: fn _config -> @at_cap end}, %{}) == @at_cap
    end

    # Sabotage: dropped the total `def join_label(_entry, _config), do: nil`
    # clause - red here (verified).
    test "is total over an entry that declares nothing at all" do
      assert BlockType.join_label(%{}, %{}) == nil
      assert BlockType.join_label(%{label: "Parallel"}, %{}) == nil
      assert BlockType.join_label("not an entry", %{}) == nil
    end

    # Sabotage: had `chip/1` append `:erlang.unique_integer/1` to what it
    # returns - red here, which is the only mechanical check this file has on
    # decision 4 reaching the layout path (verified).
    test "is a pure function of the entry and the config: two calls agree" do
      entry = %{join_label: &join_word/1}
      config = %{"lanes" => ["capture", "notify"]}

      assert BlockType.join_label(entry, config) == BlockType.join_label(entry, config)
      assert BlockType.join_label(entry, config) == "2 lanes"
    end
  end

  describe "the trio as palette-entry keys" do
    # Sabotage: dropped `:badge` from the `palette_entry/0` typespec - not
    # red (a typespec is dialyzer's business, not ExUnit's), so this test
    # asserts the behavioural half instead: an entry declaring all three
    # normalizes through the three readers rather than through none.
    test "an entry may declare all three at once and each reader finds its own" do
      entry = %{
        label: "Risk hold",
        accent_token: "--sb-accent-risk",
        badge: "manual review",
        join_label: fn _config -> "both paths" end
      }

      assert StatifierBlocks.ViewModel.accent_token(entry) == "--sb-accent-risk"
      assert BlockType.badge(entry) == "manual review"
      assert BlockType.join_label(entry, %{}) == "both paths"
    end
  end

  # A captured named function, which is the form `t:join_label/0` tells a
  # host to prefer over a closure: it can reach nothing but its argument.
  @spec join_word(map()) :: String.t()
  defp join_word(config), do: "#{length(Map.get(config, "lanes", []))} lanes"
end
