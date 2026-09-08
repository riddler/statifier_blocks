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

  doctest StatifierBlocks.BlockType,
    only: [summary: 3, summary_titles: 3, summary_refusals: 3, summary_refusal_message: 4]

  doctest StatifierBlocks.Core.Parallel, only: [summary: 1]
  doctest StatifierBlocks.Core.Wait, only: [summary: 1]
  doctest StatifierBlocks.Core.OnEvent, only: [summary: 1]
  doctest StatifierBlocks.Core.Send, only: [summary: 1]
  doctest StatifierBlocks.Core.Branch, only: [summary: 1]

  # 32 graphemes, the cap itself, and one more.
  @at_cap "waiting for the operator to sign"
  @over_cap "waiting for the operators to sign"

  # What the cap draws for `@over_cap`: thirty-one graphemes and the
  # ellipsis, so a drawn chip is never wider than a chip at the cap.
  @over_cap_clipped "waiting for the operators to si…"

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
    test "accepts a chip exactly at the cap and clips the one past it" do
      assert String.length(@at_cap) == 32
      assert String.length(@over_cap) == 33

      assert BlockType.summary(Declaring, %{"summary" => @at_cap}) == [@at_cap]
      assert BlockType.summary(Declaring, %{"summary" => @over_cap}) == [@over_cap_clipped]

      # The ellipsis is inside the cap, not beside it.
      assert String.length(@over_cap_clipped) == 32
    end

    # This is the section's whole point, so it is asserted as a list rather
    # than as one chip: an over-long chip costs its own text and nothing
    # around it.
    # sabotage: dropped the `:too_long` arm from `drawn_chips/3` back to the
    # refusal branch - the middle chip disappears and the card is again
    # indistinguishable from one whose type declared two lanes.
    test "an over-long chip is clipped and its siblings survive" do
      declared = %{"summary" => ["capture", @over_cap, "receipt"]}

      assert BlockType.summary(Declaring, declared) ==
               ["capture", @over_cap_clipped, "receipt"]

      # And the clipped chip's full text is on its title, index-aligned.
      assert BlockType.summary_titles(Declaring, declared) == [nil, @over_cap, nil]
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

  describe "summary_refusals/2, the cap's signal (ADR-0005 decision 10 Note)" do
    # Sabotage: made `chip_refusal/1`'s cap arm answer `nil` instead of
    # `:too_long` - `summary/2` still drops the chip, so the card is
    # unchanged and the only thing that goes red is the signal, which is
    # exactly the silence this bead exists to remove.
    test "an over-long chip is reported at the position it was declared" do
      assert BlockType.summary_refusals(Declaring, %{"summary" => @over_cap}) == [{0, :too_long}]

      assert BlockType.summary_refusals(Declaring, %{
               "summary" => ["capture", @over_cap, "receipt"]
             }) == [{1, :too_long}]
    end

    # Sabotage: indexed `summary/2`'s surviving chips instead of the declared
    # list - the second refusal then reports position 1 rather than 2,
    # because the first refusal already closed the gap in front of it.
    test "the index is the declared position, not the surviving one" do
      assert BlockType.summary_refusals(Declaring, %{
               "summary" => [@over_cap, "capture", @over_cap]
             }) == [{0, :too_long}, {2, :too_long}]
    end

    # Sabotage: collapsed the four arms of `chip_refusal/1` to one `:too_long`
    # - a blank chip and a non-string then read as a length problem and the
    # message tells the author to shorten something that has no length.
    test "each arm of B3's refusal set names itself" do
      assert BlockType.summary_refusals(Declaring, %{"summary" => ["   "]}) == [{0, :blank}]
      assert BlockType.summary_refusals(Declaring, %{"summary" => [""]}) == [{0, :blank}]
      assert BlockType.summary_refusals(Declaring, %{"summary" => ["a\nb"]}) == [{0, :multiline}]
      assert BlockType.summary_refusals(Declaring, %{"summary" => ["a\tb"]}) == [{0, :multiline}]
      assert BlockType.summary_refusals(Declaring, %{"summary" => ["a\rb"]}) == [{0, :multiline}]
      assert BlockType.summary_refusals(Declaring, %{"summary" => [7]}) == [{0, :not_a_string}]

      assert BlockType.summary_refusals(Declaring, %{"summary" => [:atom]}) == [
               {0, :not_a_string}
             ]
    end

    # The property that keeps the two readers honest: a chip is refused here
    # if and only if `summary/2` dropped it. Asserted over one list carrying
    # every arm, so neither reader can grow a case the other does not have.
    # Sabotage: gave `chip/1` its own copy of the cond instead of delegating
    # to `chip_refusal/1`, then changed one arm - the two readers disagree
    # and this is the only test that notices.
    test "the refusals are exactly the chips summary/2 did not draw as declared" do
      declared = ["capture", @over_cap, "", "a\nb", 7, @at_cap]
      config = %{"summary" => declared}

      refused = BlockType.summary_refusals(Declaring, config) |> Enum.map(&elem(&1, 0))

      assert refused == [1, 2, 3, 4]

      # Every reported position is one the card does not draw as declared:
      # three of them are gone, and the fourth is there under a clip.
      assert BlockType.summary(Declaring, config) == ["capture", @over_cap_clipped, @at_cap]
      assert BlockType.summary_titles(Declaring, config) == [nil, @over_cap, nil]
    end

    # Sabotage: made `declared_chips/2`'s no-callback branch read the config
    # directly instead of answering `[]` - a type that never declared a
    # summary starts reporting refusals for a key it does not own, which is
    # the same totality `summary/2` has always had, arriving at the signal.
    test "a silent type, a missing module and a failing callback refuse nothing" do
      assert BlockType.summary_refusals(Silent, %{"summary" => @over_cap}) == []
      assert BlockType.summary_refusals(NoSuchModuleAnywhere, %{}) == []
      assert BlockType.summary_refusals(Exploding, %{"how" => "raise"}) == []
      assert BlockType.summary_refusals(Exploding, %{"how" => "throw"}) == []
      assert BlockType.summary_refusals(Exploding, %{"how" => "exit"}) == []
    end

    # Sabotage: removed `List.wrap/1` from `declared_chips/2` - a declared
    # string is enumerated per grapheme, so a 33-character summary reports 33
    # refusals of a one-character chip instead of one refusal of a long one.
    test "a declared string is the one-chip case here too" do
      assert BlockType.summary_refusals(Declaring, %{"summary" => @at_cap}) == []
      assert BlockType.summary_refusals(Declaring, %{"summary" => @over_cap}) == [{0, :too_long}]
    end
  end

  describe "summary_refusal_message/3, the words the author reads" do
    # Sabotage: dropped the `index + 1` - the message counts from zero while
    # the author counts chips from one, so the sentence names the wrong chip
    # on every multi-chip summary.
    test "the message names the position, the length and the cap" do
      message =
        BlockType.summary_refusal_message(
          Declaring,
          %{"summary" => ["capture", @over_cap]},
          {1, :too_long}
        )

      assert message == "summary chip 2 is 33 characters; the cap is 32, so it is drawn clipped"
    end

    # Sabotage: made every arm answer the `:too_long` sentence - a blank chip
    # is then reported as being 0 characters against a cap of 32, which reads
    # as a cap problem and sends the author to the wrong end of the fix.
    test "each reason has its own sentence" do
      config = %{"summary" => ["", "a\nb", 7]}

      assert BlockType.summary_refusal_message(Declaring, config, {0, :blank}) ==
               "summary chip 1 is blank, so it is not drawn"

      assert BlockType.summary_refusal_message(Declaring, config, {1, :multiline}) ==
               "summary chip 2 carries a line break or a tab, so it is not drawn"

      assert BlockType.summary_refusal_message(Declaring, config, {2, :not_a_string}) ==
               "summary chip 3 is not a string, so it is not drawn"
    end

    # Sabotage: removed the non-binary `:too_long` clause - an entry naming a
    # position the type no longer declares raises inside the layout pass,
    # which is the one thing a total normalizer may never do.
    test "an entry naming a position that is no longer declared still answers" do
      assert BlockType.summary_refusal_message(Silent, %{}, {3, :too_long}) ==
               "summary chip 4 is longer than the cap of 32 characters, so it is drawn clipped"
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
      assert Wait.summary(%{"duration" => "30m1h"}) == "timer 30m1h"
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

  describe "summary_refusal_message?/1, the recognizer the card face reads" do
    # ADR-0005's Note of 2026-09-08 item 2 sends the presentation-cap
    # diagnostic to the drawer, which means the face has to be able to tell
    # one from every other finding a block carries. Decision 11's four fields
    # carry no mark finer than the source, so the recognizer is the sentence -
    # and it lives here, in the module that writes it, so the pair cannot
    # drift. This is the test that pins them together.
    #
    # Sabotage: reword any arm of `refusal_message/3` to open with something
    # other than the chip's position - that arm's finding comes back onto the
    # card face, which is the one place the item forbids it.
    test "every arm's own sentence is recognized" do
      config = %{"summary" => ["", "a\nb", 7, @over_cap]}

      for {index, reason} <- [{0, :blank}, {1, :multiline}, {2, :not_a_string}, {3, :too_long}] do
        message = BlockType.summary_refusal_message(Declaring, config, {index, reason})

        assert BlockType.summary_refusal_message?(message),
               "#{reason}: #{inspect(message)} was not recognized"
      end

      # The totality arm too - it is the sentence an entry naming a position
      # the type no longer declares answers with.
      assert BlockType.summary_refusal_message?(
               BlockType.summary_refusal_message(Silent, %{}, {3, :too_long})
             )
    end

    # Sabotage: widen the shape to `~r/^summary/` - a host validator writing
    # "summary of the document is incomplete" stops drawing on the card it is
    # about, which is a routing change nobody ruled.
    test "a sentence this module did not write is not recognized" do
      refute BlockType.summary_refusal_message?("no handler registered for this invoke type")
      refute BlockType.summary_refusal_message?("summary chip is blank, so it is not drawn")
      refute BlockType.summary_refusal_message?("this slot wants at least one step")
      refute BlockType.summary_refusal_message?(nil)
      refute BlockType.summary_refusal_message?(:too_long)
    end
  end

  describe "the generated done-event chip (ADR-0005 decision 10w, 10x, 10y)" do
    @labels %{"blk_AUTH" => "Authorize", "blk_SEQ" => "Collect"}

    defp chips(summary, labels \\ @labels),
      do: BlockType.summary(Declaring, %{"summary" => summary}, labels)

    defp titles(summary, labels \\ @labels),
      do: BlockType.summary_titles(Declaring, %{"summary" => summary}, labels)

    defp refusals(summary, labels \\ @labels),
      do: BlockType.summary_refusals(Declaring, %{"summary" => summary}, labels)

    defp refusal_message(summary, refusal, labels \\ @labels),
      do: BlockType.summary_refusal_message(Declaring, %{"summary" => summary}, refusal, labels)

    # 10w's first row. The author wrote five characters of the twenty-nine.
    #
    # sabotage: draw the outcome first - `error · Authorize` reads as a
    # block called error, and the card stops matching 10w's table
    test "an outcome event draws the block's label and the outcome" do
      assert chips(["done.outcome.s_blk_AUTH.error"]) == ["Authorize · error"]
    end

    # 10w's second row. `done.state` carries no outcome name at all
    # (ADR-0004 decision 2), so the literal role the completion final is
    # minted under is what is honest to draw.
    #
    # sabotage: invent a friendlier word than `done` -> the card names a
    # concept ADR-0004 does not have
    test "a plain done-state event draws the literal role" do
      assert chips(["done.state.s_blk_SEQ"]) == ["Collect · done"]
    end

    # 10x, and the whole reason this section exists. The generated name is
    # 37 characters against a cap of 32: measured BEFORE translation it is
    # clipped mid-identifier and raises a lint naming a string the author
    # cannot shorten because they did not write it.
    #
    # sabotage: translate AFTER the cap (move `translate_chip/2` out of
    # `translated_chips/3` and into `drawn_chips/3`, past the clip) ->
    # this goes red on both assertions at once, which is the failure mode
    # 10w exists to prevent arriving exactly as recorded
    test "the cap measures the translated text, not the generated one" do
      assert String.length("done.outcome.s_blk_AUTH.manual_review") == 37
      assert chips(["done.outcome.s_blk_AUTH.manual_review"]) == ["Authorize · manual_review"]
      assert refusals(["done.outcome.s_blk_AUTH.manual_review"]) == []
    end

    # 10o, unchanged and unweakened: a translated chip that is STILL over
    # the cap is clipped exactly as any other over-long chip is, and the
    # sentence names a length the author can act on, because the length is
    # their own label's.
    #
    # The title is the FULL TRANSLATED text rather than the declared event
    # name: a title that completed neither the visible chip nor the string
    # behind it would leave a reader with two halves and no whole.
    #
    # sabotage: exempt a translated chip from the cap instead of shortening
    # it before the cap -> 10o loses its one home and an author who named a
    # block a paragraph gets no warning
    test "a translated chip over the cap is clipped like any other" do
      long = %{"blk_AUTH" => "Authorize the payment card"}
      summary = ["done.outcome.s_blk_AUTH.error"]

      assert chips(summary, long) == ["Authorize the payment card · er…"]
      assert titles(summary, long) == ["Authorize the payment card · error"]
      assert refusals(summary, long) == [{0, :too_long}]

      assert refusal_message(summary, {0, :too_long}, long) ==
               "summary chip 1 is 34 characters; the cap is 32, so it is drawn clipped"
    end

    # 10w's other half: the translation is lossless because the raw name
    # survives on `title`, verbatim and untruncated.
    #
    # sabotage: return the DRAWN text as the title -> a screenshot beside a
    # trace answers nothing, and the chip is no longer reversible
    test "the raw event name is kept, aligned with the drawn chips" do
      summary = ["capture", "done.outcome.s_blk_AUTH.error", "done.state.s_blk_SEQ"]

      assert chips(summary) == ["capture", "Authorize · error", "Collect · done"]
      assert titles(summary) == [nil, "done.outcome.s_blk_AUTH.error", "done.state.s_blk_SEQ"]
    end

    # sabotage: keep the refused chip in `summary_titles/3` -> the two lists
    # fall out of step by one and every chip after a refusal carries the
    # wrong block's event name
    test "a refused chip drops out of both lists together" do
      summary = ["a\nb", "done.outcome.s_blk_AUTH.error"]

      assert chips(summary) == ["Authorize · error"]
      assert titles(summary) == ["done.outcome.s_blk_AUTH.error"]
    end

    # 10y. A chip may name a block that was deleted, and a label looked up
    # for a block that is gone is not a label.
    #
    # sabotage: fall back to the block id when the lookup misses -> the card
    # draws `blk_AUTH · error`, which is the derivation the author never
    # sees, dressed up as a label
    test "a name that inverts to a block this document does not carry is left alone" do
      assert chips(["done.state.s_blk_GONE"]) == ["done.state.s_blk_GONE"]
      assert titles(["done.state.s_blk_GONE"]) == [nil]

      # And the cap still measures the string as written, which is exactly
      # what an untranslated chip has always been held to.
      assert chips(["done.outcome.s_blk_GONE.manual_review"]) ==
               ["done.outcome.s_blk_GONE.manual_…"]

      assert refusals(["done.outcome.s_blk_GONE.manual_review"]) == [{0, :too_long}]
    end

    # 10y again, at the two hazards `StatifierBlocks.Validation` leaves open
    # by admitting any non-empty UTF-8 block id. `state_id_test.exs` pins
    # the inversion itself; this pins that the chip pass takes its answer.
    #
    # sabotage: guess the longest prefix that names a known block -> the
    # first assertion draws `Authorize · error` for a block called
    # `blk_AUTH__retry`, which is a card that says a different block
    # completed
    test "an authored block id that breaks the inversion leaves the chip as written" do
      labels = %{"a__b" => "Retry", "a.b" => "Authorize"}

      assert chips(["done.state.s_a__b"], labels) == ["done.state.s_a__b"]
      assert titles(["done.state.s_a__b"], labels) == [nil]
      assert chips(["done.outcome.s_a.b.error"], labels) == ["done.outcome.s_a.b.error"]
      assert titles(["done.outcome.s_a.b.error"], labels) == [nil]
    end

    # The default arity is what every caller that has only one block's
    # config keeps using, and no labels is the same absence as a missing
    # block: draw the chip as written.
    #
    # sabotage: default `labels` to something other than an empty map ->
    # a consumer on `summary/2` starts translating against a map it never
    # supplied
    test "with no labels supplied nothing is translated" do
      assert BlockType.summary(Declaring, %{"summary" => ["done.state.s_blk_SEQ"]}) ==
               ["done.state.s_blk_SEQ"]

      assert BlockType.summary_titles(Declaring, %{"summary" => ["done.state.s_blk_SEQ"]}) ==
               [nil]
    end

    # sabotage: translate before the `is_binary` guard -> a type that
    # declares a non-string chip takes the layout pass down instead of
    # having its chip refused
    test "a chip that is not a string is refused as it always was" do
      assert chips([7, "done.state.s_blk_SEQ"]) == ["Collect · done"]
      assert refusals([7, "done.state.s_blk_SEQ"]) == [{0, :not_a_string}]

      assert refusal_message([7, "done.state.s_blk_SEQ"], {0, :not_a_string}) ==
               "summary chip 1 is not a string, so it is not drawn"
    end

    # `core.on_event`'s event chip is the other producer of a chip naming an
    # event, and it reaches the card through this same pass - so wiring an
    # interrupt onto a generated completion event gets the translation
    # without that type knowing anything about it.
    #
    # sabotage: translate inside a block type instead of in the shared pass
    # -> this goes red, and every producer needs its own copy
    test "the interrupt handler's event chip is translated by the same pass" do
      config = %{"outcome" => "abandon", "event" => "done.outcome.s_blk_AUTH.error"}

      assert BlockType.summary(OnEvent, config, @labels) == ["Abandon", "Authorize · error"]

      assert BlockType.summary_titles(OnEvent, config, @labels) ==
               [nil, "done.outcome.s_blk_AUTH.error"]
    end
  end
end
