defmodule StatifierBlocks.BlockType.SummaryTest do
  @moduledoc """
  ADR-0002 amendment H, declaration side: the optional `summary/1` callback
  and the `summary/2` resolver every consumer reads it through.

  Two properties carry the section. **One shape out**: `nil`, a string, a
  list and an absent callback all leave the resolver as a chip list, so
  nothing downstream branches on what a type chose. And **refuse, never
  truncate** - amendment B3's discipline, arriving at a third declaration:
  an over-long chip is dropped and its siblings still draw, which is the
  one behavior the authoring spike's truncated parallel line does not have.

  The five core summaries are asserted here rather than in each type's own
  file because H6 is one table and reads as one.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{Block, BlockType}
  alias StatifierBlocks.Core.{Branch, OnEvent, Parallel, Send, Wait}

  doctest StatifierBlocks.BlockType, only: [summary: 2]

  doctest StatifierBlocks.Core.Parallel, only: [summary: 1]
  doctest StatifierBlocks.Core.Wait, only: [summary: 1]
  doctest StatifierBlocks.Core.OnEvent, only: [summary: 1]
  doctest StatifierBlocks.Core.Send, only: [summary: 1]
  doctest StatifierBlocks.Core.Branch, only: [summary: 1]

  # 24 graphemes, the cap itself, and one more.
  @at_cap "waiting for the operator"
  @over_cap "waiting for the operators"

  defmodule Silent do
    @moduledoc "A type that exports no `summary/1`, which is every type today."

    @behaviour StatifierBlocks.BlockType

    @impl true
    def current_version, do: 1

    @impl true
    def slots(_config), do: []

    @impl true
    def config_schema(_config), do: []

    @impl true
    def validate_config(_config), do: :ok

    @impl true
    def emit(%Block{id: id}, _context), do: {:ok, {:emitted, id}}
  end

  defmodule Declaring do
    @moduledoc """
    A host type whose summary is whatever its config says, so one module
    covers every return shape the callback allows.
    """

    @behaviour StatifierBlocks.BlockType

    @impl true
    def current_version, do: 1

    @impl true
    def slots(_config), do: []

    @impl true
    def config_schema(_config), do: []

    @impl true
    def validate_config(_config), do: :ok

    @impl true
    def emit(%Block{id: id}, _context), do: {:ok, {:emitted, id}}

    @impl true
    def summary(config), do: Map.get(config, "summary")
  end

  defmodule Exploding do
    @moduledoc "Host code with a bug in it, on the editor's layout path."

    @behaviour StatifierBlocks.BlockType

    @impl true
    def current_version, do: 1

    @impl true
    def slots(_config), do: []

    @impl true
    def config_schema(_config), do: []

    @impl true
    def validate_config(_config), do: :ok

    @impl true
    def emit(%Block{id: id}, _context), do: {:ok, {:emitted, id}}

    @impl true
    def summary(%{"how" => "raise"}), do: raise("boom")
    def summary(%{"how" => "throw"}), do: throw(:boom)
    def summary(%{"how" => "exit"}), do: exit(:boom)
  end

  describe "summary/2, the resolver" do
    # sabotage: made the `function_exported?/3` branch return `["?"]` instead
    # of `[]` - every one of the eight silent core types then grows a second
    # line saying nothing, which is the default this arm exists to protect.
    test "a type that exports no summary/1 has none" do
      assert BlockType.summary(Silent, %{}) == []
      assert BlockType.summary(Silent, %{"summary" => "ignored"}) == []
    end

    # sabotage: dropped the `Code.ensure_loaded?/1` half of the check - an
    # unloadable module raises UndefinedFunctionError inside the layout pass
    # instead of rendering the card it has always rendered.
    test "a module that does not exist has none" do
      assert BlockType.summary(NoSuchModuleAnywhere, %{}) == []
    end

    # sabotage: replaced `List.wrap/1` with `Enum.to_list/1` - a declared
    # string is then exploded into one chip per grapheme, which is the shape
    # confusion the single-shape resolver exists to make impossible.
    test "a declared string is a one-chip list" do
      assert BlockType.summary(Declaring, %{"summary" => "timer 30s"}) == ["timer 30s"]
    end

    # sabotage: made the nil case fall through to `List.wrap/1` without the
    # chip filter - `nil` wraps to `[]` either way, so this pins the pair
    # rather than one arm: an explicit nil and an absent key must agree.
    test "a declared nil is no chips" do
      assert BlockType.summary(Declaring, %{"summary" => nil}) == []
      assert BlockType.summary(Declaring, %{}) == []
    end

    # sabotage: dropped the `Enum.map(&chip/1)` step - the list comes back
    # verbatim, so a non-string entry reaches the renderer and the cap stops
    # governing chip lists at all.
    test "a declared list keeps its order and drops nothing that is well formed" do
      assert BlockType.summary(Declaring, %{"summary" => ["capture", "receipt"]}) ==
               ["capture", "receipt"]
    end
  end

  describe "amendment B3's refusal set, arriving at a summary chip" do
    # sabotage: changed the cap comparison in `chip/1` to `>=` - red on the
    # at-cap assert, which is what pins the boundary rather than its
    # neighbourhood.
    test "accepts a chip exactly at the cap and refuses the one past it" do
      assert String.length(@at_cap) == 24
      assert String.length(@over_cap) == 25

      assert BlockType.summary(Declaring, %{"summary" => @at_cap}) == [@at_cap]
      assert BlockType.summary(Declaring, %{"summary" => @over_cap}) == []
    end

    # This is the section's whole point, so it is asserted as a list rather
    # than as one chip: the spike clips the joined line, and H3 drops the one
    # chip that does not fit.
    # sabotage: made the over-long chip truncate to the cap instead of
    # answering nil - the first assert then reads a 24-character prefix and
    # the sibling lanes are indistinguishable from a rendering bug.
    test "an over-long chip is dropped and its siblings survive" do
      assert BlockType.summary(Declaring, %{"summary" => ["capture", @over_cap, "receipt"]}) ==
               ["capture", "receipt"]
    end

    # sabotage: dropped the whitespace and control-character arms of `chip/1`
    # - a summary carrying a newline draws a chip that is blank or two lines
    # tall, neither of which reads as the declaration it is.
    test "blank, whitespace and control-carrying chips are refused" do
      assert BlockType.summary(Declaring, %{"summary" => ["", "   ", "a\nb", "a\tb", "a\rb"]}) ==
               []
    end

    # sabotage: dropped the `Enum.reject(&is_nil/1)` - refused chips survive
    # as nils and the joined line reads with holes in it.
    test "a non-string entry is refused rather than inspected" do
      assert BlockType.summary(Declaring, %{"summary" => [7, :atom, %{}, "kept"]}) == ["kept"]
    end
  end

  describe "H4: a callback that fails degrades to no summary" do
    # sabotage: removed the rescue from `call_summary/2` - one host type with
    # a bug in its summary takes the whole canvas down, which is the failure
    # mode B3 wrote the bounded exception for.
    test "a raise, a throw and an exit all answer no chips" do
      assert BlockType.summary(Exploding, %{"how" => "raise"}) == []
      assert BlockType.summary(Exploding, %{"how" => "throw"}) == []
      assert BlockType.summary(Exploding, %{"how" => "exit"}) == []
    end
  end

  describe "H6: the five core summaries" do
    # sabotage: made `Parallel.summary/1` read `Map.get(config, "lanes")`
    # directly instead of the private filter - a malformed lane appears on
    # the card while `slots/1` refuses it, so the card and the slot list
    # disagree about which lanes exist.
    test "core.parallel says its lane names" do
      assert Parallel.summary(%{"lanes" => ["fraud_review", "balance_check"]}) ==
               ["fraud_review", "balance_check"]

      assert Parallel.summary(%{"lanes" => ["capture", 7, "capture", "receipt"]}) ==
               ["capture", "receipt"]

      assert Parallel.summary(%{}) == []
    end

    # sabotage: made `Wait.summary/1` read the schema default when the key is
    # absent - a wait with no duration asserts "timer 1h" while the finding
    # beside it says the key is required.
    test "core.wait says timer and the stored duration" do
      assert Wait.summary(%{"duration" => "30s"}) == "timer 30s"
      assert Wait.summary(%{"duration" => "PT1H30M"}) == "timer PT1H30M"
      assert Wait.summary(%{}) == nil
      assert Wait.summary(%{"duration" => "  "}) == nil
      assert Wait.summary(%{"duration" => 30}) == nil
    end

    # sabotage: swapped the two chips - the card reads the event before what
    # the block does with it, which is the spike's order reversed.
    test "core.on_event says the outcome, then the event" do
      assert OnEvent.summary(%{"outcome" => "abandon", "event" => "fraud.aborted"}) ==
               ["Abandon", "fraud.aborted"]

      assert OnEvent.summary(%{"outcome" => "resume", "event" => "fraud.cleared"}) ==
               ["Resume", "fraud.cleared"]

      assert OnEvent.summary(%{"outcome" => "abandon"}) == ["Abandon"]
      assert OnEvent.summary(%{"event" => "fraud.aborted"}) == ["fraud.aborted"]
      assert OnEvent.summary(%{"outcome" => "sideways"}) == []
    end

    # sabotage: made `Send.summary/1` return the raw value without the event
    # name check - a half-typed event draws a chip nobody can read, where
    # emit/2 refuses the same bytes.
    test "core.send says its event" do
      assert Send.summary(%{"event" => "signup.abandoned"}) == "signup.abandoned"
      assert Send.summary(%{"event" => "not an event"}) == nil
      assert Send.summary(%{}) == nil
    end

    # sabotage: dropped the `+ otherwise` half - the card under-reports the
    # paths out of a branch by one, on every branch in the document at once.
    test "core.branch counts its arms and names otherwise" do
      one = %{"arms" => [%{"slot" => "arm_approved", "cond" => "x"}]}

      two = %{
        "arms" => [
          %{"slot" => "arm_approved", "cond" => "x"},
          %{"slot" => "arm_review", "cond" => "y"}
        ]
      }

      assert Branch.summary(one) == "1 arm + otherwise"
      assert Branch.summary(two) == "2 arms + otherwise"
      assert Branch.summary(%{"arms" => [%{"no" => "slot"}]}) == nil
      assert Branch.summary(%{}) == nil
    end

    # sabotage: added `summary/1` to `core.sequence` - the eight silent core
    # types are silent by declaration, and this is what says so.
    test "the other core types declare none" do
      for module <- [
            StatifierBlocks.Core.Sequence,
            StatifierBlocks.Core.Group,
            StatifierBlocks.Core.Invoke,
            StatifierBlocks.Core.Assign
          ] do
        assert BlockType.summary(module, %{}) == []
      end
    end
  end
end
