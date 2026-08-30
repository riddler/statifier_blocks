defmodule StatifierBlocks.ZoomLadderTest do
  @moduledoc """
  The zoom ladder, from the arithmetic to the stylesheet that spends it.

  Deliberately **not** tagged `:liveview` and deliberately not behind the
  LiveView guard. Every claim below is either a pure function in
  `StatifierBlocks.Shell` or a string in `assets/css/statifier_blocks.css`, so
  all of it runs in the headless tree - which is where it matters, because the
  headless tree is the one that proves the ladder is a package fact rather
  than a template's.

  The two halves of a zoom are split the way ADR-0005 splits everything else:
  the client measures, `Shell` decides which step, and the stylesheet scales.
  The rule this file exists to hold is that the last two agree - a ladder step
  with no rule behind it is a button that changes a number and moves nothing,
  which is the defect `sb-6ai` was filed for.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.Shell

  @stylesheet "assets/css/statifier_blocks.css"

  describe "the stylesheet spends the ladder (sb-6ai)" do
    # Sabotage: deleting the `[data-zoom="150"]` rule from the stylesheet -
    # 150% becomes a step whose readout moves and whose canvas does not, which
    # is exactly the state this bead found the editor in, and this goes red
    # naming the step.
    test "every ladder step has a rule that scales the stage by it" do
      css = File.read!(@stylesheet)

      for step <- Shell.zoom_steps() do
        assert css =~ ~s(.sb-editor[data-zoom="#{step}"] .sb-canvas {), """
        Ladder step #{step}% has no rule in #{@stylesheet}. `data-zoom` is
        stamped for every step the ladder offers, so a step with no rule is a
        control that changes a number and scales nothing.
        """

        assert css =~ "transform: scale(#{step / 100});", """
        Ladder step #{step}% has a rule that does not scale by #{step / 100}.
        The percentage in the toolbar and the scale on the canvas are the same
        claim made twice, and an author reads the disagreement as a zoom that
        lies.
        """
      end
    end

    # Sabotage: dropping `transform-origin: 0 0` - every step above 100% then
    # scales about the centre and pushes the root block's first card off the
    # left edge of a scroller that cannot scroll left, so the top of the chart
    # becomes unreachable.
    test "the stage scales about its own top left corner" do
      assert File.read!(@stylesheet) =~ """
             .sb-editor[data-zoom] .sb-canvas {
               transform-origin: 0 0;
             }
             """
    end

    # Not a claim about the stylesheet: it is what stops the check above from
    # passing vacuously if the ladder is ever emptied.
    # Sabotage: `def zoom_steps, do: []` - the loop above runs zero times and
    # this is what notices.
    test "the ladder actually has steps" do
      assert length(Shell.zoom_steps()) >= 2
      assert 100 in Shell.zoom_steps()
    end
  end

  describe "the scroller's box off the wire (sb-6ai)" do
    # Sabotage: having `viewport/1` read `params["stage"]` - every fit is then
    # computed against the tree's own extent, so `Fit width` resolves to the
    # step where the tree fits itself, which is 100% forever.
    test "a well-formed viewport decodes to its box" do
      assert Shell.viewport(%{"viewport" => %{"w" => 800, "h" => 600}}) ==
               %{width: 800.0, height: 600.0}
    end

    # Sabotage: dropping the total clause - a payload from a hook that could
    # not find the scroller raises in the middle of a measure event, which
    # takes the editor down over a number nothing was waiting for.
    test "anything else decodes to nothing at all" do
      for payload <- [
            %{},
            %{"viewport" => nil},
            %{"viewport" => %{"w" => 0, "h" => 600}},
            %{"viewport" => %{"w" => "800", "h" => "600"}},
            %{"viewport" => %{"w" => -8, "h" => 600}},
            %{"viewport" => %{"w" => 800}},
            "not a map"
          ] do
        assert Shell.viewport(payload) == nil
      end
    end
  end

  describe "which step a fit lands on (sb-6ai)" do
    # Sabotage: `Enum.find` over the ascending ladder rather than the reversed
    # one - every fit resolves to the smallest step that fits, so `Fit width`
    # on a chart that fits at 175% shrinks it to 50%.
    test "the largest step at which the content fits" do
      # 400 wide fits 800 at 200%, and 200 is the top of the ladder.
      assert Shell.fit_zoom(400, 800, 100) == 200

      # 1000 wide fits 800 at 80% (800) but not at 90% (900).
      assert Shell.fit_zoom(1000, 800, 100) == 80

      # Exactly one step: 800 into 800 is 100% and nothing above it.
      assert Shell.fit_zoom(800, 800, 50) == 100
    end

    # Sabotage: returning `hd(@zoom_steps)` from the guarded clause's fallback
    # by dropping the `Enum.find/3` default - a chart too wide for even 50%
    # resolves to nil and the canvas is stamped `data-zoom=""`.
    test "content too wide for any step lands on the bottom of the ladder" do
      assert Shell.fit_zoom(100_000, 100, 125) == hd(Shell.zoom_steps())
    end

    # Sabotage: dropping the total clause and pattern-matching a Rect - a fit
    # pressed before the first measurement, or in a host that never imported
    # the hook, raises instead of leaving the canvas where it is.
    test "an unmeasured side leaves the author on the step they are on" do
      assert Shell.fit_zoom(nil, 800, 125) == 125
      assert Shell.fit_zoom(400, nil, 90) == 90
      assert Shell.fit_zoom(0, 800, 150) == 150
      assert Shell.fit_zoom(nil, nil, "not a step") == Shell.default_zoom()
    end
  end

  describe "the width the stage is laid out at (sb-6ai)" do
    # Sabotage: returning the stage's own measured width instead of the
    # scroller's - the stage is then pinned to a number the wrapper it sits in
    # decides, which is the loop this function exists to break. The live check
    # at 150% found it as a wrapper 33,554,428 pixels wide.
    test "a zoomed stage is pinned to the scroller's width" do
      assert Shell.zoom_stage_width(%{width: 782.0, height: 900.0}, 150) == 782.0
      assert Shell.zoom_stage_width(%{width: 782.0, height: 900.0}, 50) == 782.0
    end

    # Sabotage: pinning at 100% too - an unzoomed stage grows an inline width,
    # so a host that resizes the window has a canvas that stays the width it
    # was measured at until something else re-renders it.
    test "100% and an unmeasured scroller both carry no width at all" do
      assert Shell.zoom_stage_width(%{width: 782.0, height: 900.0}, 100) == nil
      assert Shell.zoom_stage_width(nil, 150) == nil
    end
  end

  describe "the scaled extent the wrapper carries (sb-6ai)" do
    # Sabotage: returning the unscaled box - the transform still draws the
    # tree at the new size and the scroller still scrolls the old one, so at
    # 200% the bottom right half of the chart cannot be reached. That is the
    # half of this bead a screenshot at 100% would never show.
    test "a measured box scales by the step" do
      box = %{width: 400.0, height: 300.0}

      assert Shell.zoom_extent(box, 200) == {800.0, 600.0}
      assert Shell.zoom_extent(box, 50) == {200.0, 150.0}
    end

    # Sabotage: returning `{width, height}` at 100% - an unzoomed editor grows
    # an inline size on the wrapper, so the stage stops filling the panel and
    # the default rendering changes for a zoom nobody applied.
    test "100% and an unmeasured stage both carry no size at all" do
      assert Shell.zoom_extent(%{width: 400.0, height: 300.0}, 100) == nil
      assert Shell.zoom_extent(nil, 200) == nil
      assert Shell.zoom_extent(%{width: 400.0}, 200) == nil
    end
  end

  describe "the fit a host opens at (sb-ehqn)" do
    # Sabotage: dropping the guarded clause so every value falls through to
    # the default - a host that asks for `:width` opens at `:manual`, and the
    # attr is a documented no-op.
    test "the three modes are themselves" do
      assert Shell.fit_mode(:manual) == :manual
      assert Shell.fit_mode(:width) == :width
      assert Shell.fit_mode(:active) == :active
    end

    # Sabotage: dropping the binary clause - a host templating the attr from
    # a query string or a stored preference gets `:manual` for the value it
    # asked for, silently.
    test "a mode spelled as a string is the same mode" do
      assert Shell.fit_mode("manual") == :manual
      assert Shell.fit_mode("width") == :width
      assert Shell.fit_mode("active") == :active
    end

    # Sabotage: making the fallback `raise` - a typo in a host's template
    # takes the whole editor down on mount, where the same typo in a tab name
    # only picks the first tab. An unknown attr is refused, not fatal.
    test "anything else is refused into the default" do
      for value <- [:cover, :Width, "Width", "fit-width", nil, 100, %{}, ["width"]] do
        assert Shell.fit_mode(value) == :manual
      end
    end
  end
end
