defmodule StatifierBlocks.ConnectorsTest do
  @moduledoc """
  The connector layer, asserted with no browser anywhere.

  ADR-0005 decision 7's 2026-08-29 amendment, clause 7b.2: *the connector
  geometry itself is computed on the server, as pure functions from measured
  rectangles to path data*. This file is what that clause buys. The campaign
  012/013 spike kept the same split and asserted the same arithmetic in
  `spike/dev/selftest.html`, which could only ever run inside Chrome; the
  geometry assertions below are those assertions, re-expressed against the
  shipped functions, and they run in the gate.

  Deliberately **not** tagged `:liveview`: `StatifierBlocks.Connectors` is
  outside the Phoenix guard by design, so this is one of the files that has
  to pass in the headless tree.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.Connectors
  alias StatifierBlocks.Connectors.{Edge, Rect}
  alias StatifierBlocks.ViewModel.{Node, Slot}

  describe "the path functions, which are the spike's own assertions (7b.2)" do
    # Sabotage: dropping the `@straight_epsilon` clause from `flow_path/3` -
    # the common case inside a sequence acquires two corners it does not need
    # and this goes red with the path it drew instead.
    test "an aligned flow edge is one straight line" do
      assert Connectors.flow_path(%{x: 10, y: 20}, %{x: 10, y: 60}) == "M 10 20 L 10 60"
    end

    # Sabotage: moving `mid_y` off the halfway line - every offset edge turns
    # somewhere else and this goes red with the whole path, which is the only
    # form of this assertion a reviewer can check against the spike.
    test "an offset flow edge turns on the halfway line" do
      assert Connectors.flow_path(%{x: 10, y: 20}, %{x: 50, y: 60}) ==
               "M 10 20 V 30 Q 10 40 20 40 H 40 Q 50 40 50 50 V 60"
    end

    # Sabotage: giving `fan_path/3` the halfway elbow `flow_path/3` uses - the
    # arms stop turning on one line, the fan stops reading as a distribution
    # bar, and this goes red.
    test "a fan edge elbows just below its hub" do
      assert Connectors.fan_path(%{x: 100, y: 10}, %{x: 40, y: 100}) ==
               "M 100 10 V 16 Q 100 26 90 26 H 50 Q 40 26 40 36 V 100"
    end

    # Sabotage: elbowing `join_path/3` near the SOURCE rather than the hub -
    # the mirror property is lost, the rejoins stop sharing a line, and this
    # goes red.
    test "a rejoin edge elbows just above its hub" do
      assert Connectors.join_path(%{x: 40, y: 100}, %{x: 100, y: 200}) ==
               "M 40 100 V 174 Q 40 184 50 184 H 90 Q 100 184 100 194 V 200"
    end

    # Sabotage: routing the interrupt path through the container's own box
    # instead of the channel - it crosses everything the container holds and
    # this goes red on the H that no longer reaches the channel.
    test "an interrupt edge leaves right, runs the channel, and comes back" do
      assert Connectors.interrupt_path(%{x: 100, y: 50}, %{x: 20, y: 200}, 140) ==
               "M 100 50 H 130 Q 140 50 140 60 V 190 Q 140 200 130 200 H 20"
    end

    # The corroborator for all five: a radius that is not clamped turns a
    # short edge's corners inside out, which is invisible in a long one.
    # Sabotage: removing the `clamp/2` call - the path below stops starting
    # and ending where it was told to and this goes red.
    test "a short edge cannot turn its corners inside out" do
      path = Connectors.flow_path(%{x: 0, y: 0}, %{x: 3, y: 2})

      assert String.starts_with?(path, "M 0 0")
      assert String.ends_with?(path, "V 2")
    end

    # Sabotage: rendering every coordinate as a float - the paths stop being
    # comparable to the spike's evidence, which is the only reason the numbers
    # above can be checked by eye at all.
    test "a whole number renders without a decimal point, and a fraction keeps one" do
      assert Connectors.flow_path(%{x: 10, y: 20}, %{x: 10, y: 60.25}) == "M 10 20 L 10 60.3"
    end

    # Sabotage: making `outlet/1` and `inlet/1` return the same edge of the
    # rectangle - every edge starts and ends on one side of its cards and the
    # rendering reads as a bundle of vertical lines.
    test "flow leaves the bottom of a rectangle and enters the top" do
      rect = %Rect{x: 10.0, y: 20.0, width: 100.0, height: 40.0}

      assert Connectors.outlet(rect) == %{x: 60.0, y: 60.0}
      assert Connectors.inlet(rect) == %{x: 60.0, y: 20.0}
    end
  end

  describe "the payload shape, decoded totally (7d, 7c)" do
    # Sabotage: pattern matching the payload in the function head instead of
    # decoding it - a malformed push from the DOM raises inside the component
    # rather than being dropped, and this goes red as a crash.
    test "a well-formed push decodes to rectangles keyed by the server's own string" do
      decoded =
        Connectors.measurement(%{
          "stage" => %{"w" => 1200, "h" => 2400.5},
          "anchors" => [
            %{"k" => "card:blk_a", "x" => 8, "y" => 8.5, "w" => 300, "h" => 32}
          ]
        })

      assert decoded == %{
               "stage" => %Rect{x: 0.0, y: 0.0, width: 1200.0, height: 2400.5},
               "card:blk_a" => %Rect{x: 8.0, y: 8.5, width: 300.0, height: 32.0}
             }
    end

    # 7c's contract as arithmetic: an anchor this module cannot read is
    # dropped, and the rest of the stage still draws.
    # Sabotage: letting `number/1` accept a binary - a string coordinate
    # travels half-decoded into the geometry and comes out as an ArithmeticError
    # in a path function, a long way from the push that caused it.
    test "a malformed anchor is dropped and its neighbours survive" do
      decoded =
        Connectors.measurement(%{
          "anchors" => [
            %{"k" => "card:blk_a", "x" => "8", "y" => 8, "w" => 300, "h" => 32},
            %{"k" => 17, "x" => 0, "y" => 0, "w" => 1, "h" => 1},
            %{"k" => "card:blk_b"},
            "not an anchor at all",
            %{"k" => "card:blk_c", "x" => 1, "y" => 2, "w" => 3, "h" => 4}
          ]
        })

      assert Map.keys(decoded) == ["card:blk_c"]
    end

    # Sabotage: dropping the fallback clause of `measurement/1` - a push that
    # is not a map raises instead of decoding to the same empty measurement
    # the editor holds before the first frame.
    test "an unreadable payload decodes to the state the editor already had" do
      assert Connectors.measurement(nil) == %{}
      assert Connectors.measurement("stage") == %{}
      assert Connectors.measurement(%{"anchors" => "none"}) == %{}
      assert Connectors.measurement(%{"stage" => %{"w" => "wide", "h" => 10}}) == %{}
    end

    # Sabotage: reading the stage out of `anchors` like any other key - the
    # stage's own box stops being the origin, `stage/1` returns nil, and the
    # overlay never gets a viewBox.
    test "the stage is the origin, and it is what the overlay is sized from" do
      decoded = Connectors.measurement(%{"stage" => %{"w" => 800, "h" => 600}})

      assert Connectors.stage(decoded) == %Rect{x: 0.0, y: 0.0, width: 800.0, height: 600.0}
      assert Connectors.stage(%{}) == nil
    end

    # Sabotage: composing an anchor key on the client, or parsing one here -
    # a block id containing `:` or `/` then splits wrong; keys are built here
    # and compared whole, and this is the check that says so.
    test "the anchor keys are the five the markup stamps" do
      assert Connectors.stage_anchor() == "stage"
      assert Connectors.node_anchor("blk_a") == "node:blk_a"
      assert Connectors.card_anchor("blk_a") == "card:blk_a"
      assert Connectors.outlet_anchor("blk_a") == "outlet:blk_a"
      assert Connectors.slot_anchor("blk_a", "on_error") == "slot:blk_a/on_error"
    end
  end

  describe "the walk, and what it derives from adjacency alone (10a)" do
    # Clause 7b.3's standing test, as a property of `edges/2` rather than of a
    # flag: no hook imported means nothing measured means no connectors, and
    # the editor is otherwise the editor it was.
    # Sabotage: making the empty-measurement clause guess a default rectangle -
    # an unmeasured editor draws lines through nothing and this goes red.
    test "with nothing measured there are no connectors at all" do
      assert Connectors.edges(sequence(), %{}) == []
    end

    # Sabotage: emitting an edge whose anchors are missing from the
    # measurement - a first frame that has measured half the tree draws
    # connectors to the origin, and this goes red.
    test "an edge whose anchors were not measured is skipped, not guessed" do
      partial = measured(%{"outlet:blk_one" => {0, 40, 100, 0}})

      assert Connectors.edges(sequence(), partial) == []
    end

    # Sabotage: chunking the children by 2 without `:discard` - the last block
    # pairs with nothing and the walk emits an edge into a missing anchor.
    test "adjacent children of one slot are joined, each leaving from an outlet" do
      edges = Connectors.edges(sequence(), sequence_measurement())

      # Each block's outlet spans the full width of its box, so the point flow
      # leaves from is its centre: `blk_one` at (200, 80), `blk_two` at
      # (200, 140). Naming the points rather than counting the edges is what
      # makes this an assertion about adjacency rather than about arithmetic.
      assert Enum.any?(edges, &String.starts_with?(&1.d, "M 200 80"))
      assert Enum.any?(edges, &String.starts_with?(&1.d, "M 200 140"))
      assert Enum.all?(edges, &(&1.kind == :flow))
    end

    # Sabotage: taking the flow edge off the container's card into the first
    # child - a sequence's own entry disappears and the tree reads as three
    # unrelated stacks.
    test "a container with one body slot gets one edge into its first child" do
      edges = Connectors.edges(sequence(), sequence_measurement())

      # The container's own card is 400 wide at the top of the stage, so its
      # entry edge leaves from (200, 30) - and it is the only edge that does.
      assert Enum.count(edges, &String.starts_with?(&1.d, "M 200 30")) == 1

      # Two adjacency edges plus that one, and nothing else.
      assert length(edges) == 3
    end

    # Sabotage: deriving the fan from a type name instead of from the slot
    # count - `core.branch` keeps working and every host type of the same
    # shape silently loses its fan, which is exactly what d10 forbids.
    test "a container with several primary slots fans out and rejoins" do
      edges = Connectors.edges(branch(), branch_measurement())

      assert Enum.count(edges, &(&1.kind == :fan)) == 2
      assert Enum.count(edges, &(&1.kind == :join)) == 2
    end

    # Sabotage: skipping an empty slot in `slot_exit/2` - an arm an author has
    # not filled yet silently stops having a rejoin, which tells them their
    # empty arm does not exist.
    test "an empty arm is a real arm: it fans and it rejoins from its header" do
      edges = Connectors.edges(branch(), branch_measurement())
      empty_arm = Connectors.slot_anchor("blk_branch", "arm_b")

      assert Map.has_key?(branch_measurement(), empty_arm)
      assert Enum.count(edges, &(&1.kind == :join)) == 2
    end

    # The `sb-67s` ruling, at the layer it was made about: a failure rail
    # leaves by the ORDINARY flow edge and takes no vocabulary of its own, so
    # it can never pick up the dashes or the hue that mark a way out of band.
    # Sabotage: giving the failure arm its own `:failure` kind - the stylesheet
    # gains a rule the ruling removed and this goes red.
    test "a failure rail exits as flow, in the flow vocabulary" do
      edges = Connectors.edges(railed(:failure), rail_measurement())

      # The rule's own outlet is at (330, 110), so the rail exit is the edge
      # leaving there - and it is a `:flow` edge, which is the ruling.
      assert [%Edge{kind: :flow}] = Enum.filter(edges, &String.starts_with?(&1.d, "M 330 110"))
      refute Enum.any?(edges, &(&1.kind == :interrupt))
    end

    # Sabotage: routing an interrupt exit as flow too - the two vocabularies
    # collapse into one, which is the bug `sb-67s` ruled in the other
    # direction and this is the control that keeps the check above honest.
    test "a secondary rail still exits out of band" do
      edges = Connectors.edges(railed(:secondary), rail_measurement())

      assert [%Edge{kind: :interrupt}] = Enum.filter(edges, &(&1.kind == :interrupt))
    end

    # Sabotage: placing the interrupt channel inside the container's box -
    # the exit edge crosses the body it is escaping at every depth, which is
    # the routing bug the channel exists to prevent.
    test "the interrupt channel runs outside the container's own box" do
      [interrupt] =
        railed(:secondary)
        |> Connectors.edges(rail_measurement())
        |> Enum.filter(&(&1.kind == :interrupt))

      # `node:blk_group` is measured 0..400 wide, so an edge that never left the
      # box would reach at most 400. The channel is outside it, which is the
      # routing rule that keeps an exit from crossing the body at any depth.
      assert Enum.max(x_coordinates(interrupt.d)) > 400
    end

    # Sabotage: making `edges/2` read anything but its two arguments - a
    # re-push stops being safe and the measure/render loop stops converging,
    # which is the property the hook's lack of memory is paid for with.
    test "the same tree and the same measurement give the same list" do
      assert Connectors.edges(branch(), branch_measurement()) ==
               Connectors.edges(branch(), branch_measurement())
    end
  end

  # ------------------------------------------------------------- fixtures

  defp block(id, opts \\ []) do
    %Node{
      block_id: id,
      type: Keyword.get(opts, :type, "core.step"),
      type_version: 1,
      status: :ok,
      entry: Keyword.get(opts, :entry, %{layout: :stack}),
      slots: Keyword.get(opts, :slots, [])
    }
  end

  defp slot(name, children, style \\ :primary) do
    %Slot{name: name, label: name, declared?: true, style: style, children: children}
  end

  defp sequence do
    block("blk_seq",
      type: "core.sequence",
      slots: [slot("body", [block("blk_one"), block("blk_two"), block("blk_three")])]
    )
  end

  # Every x in a path. This module puts x first in each coordinate pair and
  # `H` takes one alone, which is enough to read a path's horizontal extent
  # without parsing SVG.
  defp x_coordinates(d) do
    ~r/(?:M|H|Q|L) (-?[0-9.]+)/
    |> Regex.scan(d)
    |> Enum.map(fn [_all, x] -> as_float(x) end)
  end

  defp as_float(text) do
    if String.contains?(text, "."),
      do: String.to_float(text),
      else: String.to_integer(text) * 1.0
  end

  defp branch do
    block("blk_branch",
      type: "core.branch",
      slots: [slot("arm_a", [block("blk_a")]), slot("arm_b", [])]
    )
  end

  defp railed(style) do
    block("blk_group",
      type: "core.group",
      slots: [slot("body", [block("blk_inner")]), slot("rail", [block("blk_rule")], style)]
    )
  end

  # `{x, y, w, h}` per key, which keeps the fixtures readable: what each test
  # is about is the shape of the walk, never the arithmetic, and the
  # arithmetic has its own describe block above.
  defp measured(boxes) do
    Map.new(boxes, fn {key, {x, y, w, h}} ->
      {key, %Rect{x: x / 1, y: y / 1, width: w / 1, height: h / 1}}
    end)
  end

  defp sequence_measurement do
    measured(%{
      "stage" => {0, 0, 400, 400},
      "card:blk_seq" => {0, 0, 400, 30},
      "outlet:blk_seq" => {0, 300, 400, 0},
      "card:blk_one" => {10, 40, 380, 30},
      "outlet:blk_one" => {10, 80, 380, 0},
      "card:blk_two" => {10, 100, 380, 30},
      "outlet:blk_two" => {10, 140, 380, 0},
      "card:blk_three" => {10, 160, 380, 30},
      "outlet:blk_three" => {10, 200, 380, 0}
    })
  end

  defp branch_measurement do
    measured(%{
      "stage" => {0, 0, 400, 400},
      "card:blk_branch" => {0, 0, 400, 30},
      "outlet:blk_branch" => {0, 300, 400, 0},
      "slot:blk_branch/arm_a" => {0, 50, 190, 20},
      "slot:blk_branch/arm_b" => {210, 50, 190, 20},
      "card:blk_a" => {0, 80, 190, 30},
      "outlet:blk_a" => {0, 120, 190, 0}
    })
  end

  defp rail_measurement do
    measured(%{
      "stage" => {0, 0, 600, 400},
      "node:blk_group" => {0, 0, 400, 300},
      "card:blk_group" => {0, 0, 400, 30},
      "outlet:blk_group" => {0, 290, 400, 0},
      "slot:blk_group/body" => {0, 40, 250, 20},
      "slot:blk_group/rail" => {260, 40, 140, 20},
      "card:blk_inner" => {0, 70, 250, 30},
      "outlet:blk_inner" => {0, 110, 250, 0},
      "card:blk_rule" => {260, 70, 140, 30},
      "outlet:blk_rule" => {260, 110, 140, 0}
    })
  end
end
