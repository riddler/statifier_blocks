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

    # Down, or level, and never up. An arrowhead is oriented along its path,
    # so an ascending edge renders an arrow pointing back at the block the
    # flow just left - a loop the document does not contain.
    # Sabotage: dropping the `ty < fy` clause from `flow_path/3` - the aligned
    # case draws "M 10 60 L 10 20", which is the upward-flipped head itself,
    # and this goes red on the second coordinate.
    test "an aligned edge whose head is above its tail is drawn level, never up" do
      assert Connectors.flow_path(%{x: 10, y: 60}, %{x: 10, y: 20}) == "M 10 60 L 10 60"
    end

    # The offset half of the same rule, and the one that shows what clamping
    # does to the elbow: the halfway line lands on the tail's own y, so the
    # whole path is level and every corner radius clamps to nothing.
    # Sabotage: clamping `fy` DOWN to `ty` instead of `ty` up to `fy` - the
    # edge is level but at the wrong height, leaving its own source, and this
    # goes red on every coordinate.
    test "an offset edge whose head is above its tail turns on the tail's own line" do
      assert Connectors.flow_path(%{x: 10, y: 60}, %{x: 50, y: 20}) ==
               "M 10 60 V 60 Q 10 60 10 60 H 50 Q 50 60 50 60 V 60"
    end

    # The other three paths carry the same clamp (campaign-022 ruling R8d).
    # A fan reaches the case first: one short lane beside a tall one puts a
    # slot's inlet ABOVE the bar that feeds it, and an unclamped arm drew the
    # arrowhead back into the hub.
    # Sabotage: dropping the `ty < hy` clause from `fan_path/3` - the arm
    # draws "M 100 100 L 100 20", an arm that climbs out of its own hub, and
    # this goes red on the second coordinate.
    test "a fan arm whose inlet is above its hub is drawn level, never up" do
      assert Connectors.fan_path(%{x: 100, y: 100}, %{x: 100, y: 20}) == "M 100 100 L 100 100"

      assert Connectors.fan_path(%{x: 100, y: 100}, %{x: 40, y: 20}) ==
               "M 100 100 V 100 Q 100 100 100 100 H 40 Q 40 100 40 100 V 100"
    end

    # The mirror: here the HUB is the head, so it is the hub that is clamped
    # down onto the exit's own line rather than the exit raised to it.
    # Sabotage: dropping the `hy < fy` clause from `join_path/3` - the rejoin
    # draws "M 40 100 L 40 20" and the arrow points back into the region the
    # flow is leaving, which is the loop the document does not contain.
    test "a rejoin arm whose hub is above its exit is drawn level, never up" do
      assert Connectors.join_path(%{x: 40, y: 100}, %{x: 40, y: 20}) == "M 40 100 L 40 100"

      assert Connectors.join_path(%{x: 40, y: 100}, %{x: 100, y: 20}) ==
               "M 40 100 V 100 Q 40 100 40 100 H 100 Q 100 100 100 100 V 100"
    end

    # And the interrupt, whose head is the container's exit point: a rule near
    # the bottom of a tall region can be measured below the exit it leaves by.
    # Sabotage: dropping the `ey < fy` clause from `interrupt_path/4` - the
    # channel leg becomes "V 50" and the edge climbs the channel with its head
    # pointing up, which is the rendering the clamp exists to refuse.
    test "an interrupt edge whose exit is above its rule runs level, never up" do
      assert Connectors.interrupt_path(%{x: 100, y: 200}, %{x: 20, y: 50}, 140) ==
               "M 100 200 H 140 Q 140 200 140 200 V 200 Q 140 200 140 200 H 20"
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
    test "the anchor keys are the seven the markup stamps" do
      assert Connectors.stage_anchor() == "stage"
      assert Connectors.node_anchor("blk_a") == "node:blk_a"
      assert Connectors.card_anchor("blk_a") == "card:blk_a"
      assert Connectors.outlet_anchor("blk_a") == "outlet:blk_a"
      assert Connectors.slot_anchor("blk_a", "on_error") == "slot:blk_a/on_error"
      assert Connectors.fan_anchor("blk_a") == "fan:blk_a"
      assert Connectors.join_anchor("blk_a") == "join:blk_a"
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

    # `sb-d4cr`, found by campaign-025 `sb-e2zy`: `slot_exit/2` read
    # `slot.children`, so an arm ending in a shelf rejoined FROM the shelf's
    # outlet - flow leaving the one card 10u says nothing enters and nothing
    # leaves.
    #
    # Sabotage: reading `slot.children` in `slot_exit/2` again - the join
    # leaves "M 95 190", the shelf's outlet, instead of the last step's.
    test "an arm ending in a shelf rejoins from the last step, not the shelf" do
      edges = Connectors.edges(shelved_branch(), shelved_branch_measurement())
      joins = Enum.filter(edges, &(&1.kind == :join))

      # `outlet:blk_a` is (95, 120) and `outlet:blk_drafts` is (95, 190).
      assert Enum.count(joins, &String.starts_with?(&1.d, "M 95 120")) == 1
      refute Enum.any?(joins, &String.starts_with?(&1.d, "M 95 190"))
    end

    # Sabotage: as above - the arm rejoins from "M 305 120", the shelf's own
    # outlet, rather than from the header an armful of drafts leaves it with.
    test "an arm holding nothing but a shelf rejoins from its header" do
      edges = Connectors.edges(shelved_branch(), shelved_branch_measurement())
      joins = Enum.filter(edges, &(&1.kind == :join))

      # `slot:blk_branch/arm_b` is (305, 70); `outlet:blk_only_drafts` is
      # (305, 120), which is the anchor the bug picked.
      assert length(joins) == 2
      assert Enum.count(joins, &String.starts_with?(&1.d, "M 305 70")) == 1
      refute Enum.any?(joins, &String.starts_with?(&1.d, "M 305 120"))
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

    # And the box it runs outside of is the container's BODY when one was
    # measured. A container's node box is only as wide as the width its parent
    # handed down; the body inside it is as wide as the work it holds, and
    # OVERFLOWS it. Offsetting the channel from the node box therefore turns
    # the edge down inside the very contents it is escaping, which is the one
    # thing the channel exists to prevent.
    # Sabotage: reading `node_anchor/1` in `channel_box/2` - the channel goes
    # back to 410, which is 190px inside the body, and this goes red.
    test "the channel is offset from the container's body, not its narrower node box" do
      [interrupt] =
        railed(:secondary)
        |> Connectors.edges(overflowing_measurement())
        |> Enum.filter(&(&1.kind == :interrupt))

      # The node box is 400 wide and the body inside it is 600, so the only
      # channel that clears the container's contents is the one offset from
      # the body: 600 + `@channel_offset`.
      assert Enum.max(x_coordinates(interrupt.d)) == 610
    end

    # The fallback, which is what keeps the rule above from silently dropping
    # an edge: a collapsed container renders no body at all, so its body anchor
    # is absent and the node box answers instead.
    # Sabotage: making `channel_box/2` return `nil` when the body anchor is
    # missing - a collapsed container's exit edge disappears entirely and this
    # goes red on the empty list rather than on the number.
    test "a container whose body was never measured falls back to its node box" do
      [interrupt] =
        railed(:secondary)
        |> Connectors.edges(rail_measurement())
        |> Enum.filter(&(&1.kind == :interrupt))

      refute Map.has_key?(rail_measurement(), "slots:blk_group")
      assert Enum.max(x_coordinates(interrupt.d)) == 410
    end

    # The collapse case, at the layer it is decided: a folded container
    # renders no child card, so the browser measures none of the subtree and
    # the walk finds no anchor to draw into. Nothing here knows what "folded"
    # means - that is the point. `edges/2` reads the tree and the measurement,
    # and an unmeasured subtree is one the author cannot see.
    # Sabotage: giving `path_edge/5` a fallback rectangle for a missing anchor
    # - a folded container sprouts connectors into cards that are not on the
    # canvas, and this goes red.
    test "a subtree nobody measured takes no edges, and the tree around it keeps its own" do
      folded =
        sequence_measurement()
        |> Map.drop(["card:blk_two", "outlet:blk_two"])

      edges = Connectors.edges(sequence(), folded)

      # `blk_two` is measured nowhere, so neither the edge into it from
      # `blk_one` nor the edge out of it into `blk_three` can be drawn.
      refute Enum.any?(edges, &String.starts_with?(&1.d, "M 200 80"))
      refute Enum.any?(edges, &String.starts_with?(&1.d, "M 200 140"))

      # The container's own entry into its first child is untouched: folding
      # one card inside a sequence is not folding the sequence.
      assert Enum.count(edges, &String.starts_with?(&1.d, "M 200 30")) == 1
    end

    # Sabotage: making `edges/2` read anything but its two arguments - a
    # re-push stops being safe and the measure/render loop stops converging,
    # which is the property the hook's lack of memory is paid for with.
    test "the same tree and the same measurement give the same list" do
      assert Connectors.edges(branch(), branch_measurement()) ==
               Connectors.edges(branch(), branch_measurement())
    end
  end

  describe "the hubs a fan turns on (10b, campaign 016)" do
    # The fallback, and the behaviour every fan had before the markers were
    # anchored: with no pill measured the fan still leaves the card.
    # Sabotage: making `marker_or/3` return the marker unconditionally - a
    # stacked-marker-less container's fan resolves to an anchor nothing
    # measured, `path_edge/5` drops every arm, and the branch loses its fan.
    test "with no pill measured the fan leaves the container's card" do
      edges = Connectors.edges(branch(), branch_measurement())

      # `card:blk_branch` is 400 wide at the top of the stage, so its outlet
      # is (200, 30) - and both arms turn there.
      assert Enum.count(edges, &(&1.kind == :fan)) == 2
      assert Enum.all?(fan_edges(edges), &String.starts_with?(&1.d, "M 200 30"))
    end

    # Sabotage: leaving the fan on the card once a pill is measured - the
    # overlay paints above the tree, so every arm is drawn straight through
    # the pill's own word on the way past it.
    test "a measured pill is the point the fan leaves from" do
      measurement =
        Map.merge(branch_measurement(), measured(%{"fan:blk_branch" => {150, 34, 100, 20}}))

      edges = Connectors.edges(branch(), measurement)

      # The pill is 100 wide from x=150, so its outlet is (200, 54).
      assert Enum.count(edges, &(&1.kind == :fan)) == 2
      assert Enum.all?(fan_edges(edges), &String.starts_with?(&1.d, "M 200 54"))
    end

    # The pill is a hub, not an island: the flow has to reach it.
    # Sabotage: dropping the `hub != card` marker edge - the card and the pill
    # are drawn with nothing between them, so the flow appears to stop at the
    # container's header and start again below it.
    test "a measured pill gains the short flow edge that reaches it" do
      measurement =
        Map.merge(branch_measurement(), measured(%{"fan:blk_branch" => {150, 34, 100, 20}}))

      edges = Connectors.edges(branch(), measurement)

      # From the card's outlet (200, 30) to the pill's inlet (200, 34): the one
      # `:flow` edge this tree has, and it is aligned, so it is one line.
      assert Enum.filter(edges, &(&1.kind == :flow)) == [
               %Edge{kind: :flow, d: "M 200 30 L 200 34"}
             ]
    end

    # Sabotage: aiming the rejoins past a measured join marker at the outlet -
    # every arm's rejoin crosses the word that says what the rejoin means.
    test "a measured join marker is the point the rejoins arrive at" do
      measurement =
        Map.merge(branch_measurement(), measured(%{"join:blk_branch" => {150, 260, 100, 20}}))

      edges = Connectors.edges(branch(), measurement)

      # The marker's inlet is (200, 260), and the rejoins end there rather
      # than at the container's outlet 40px below it.
      assert Enum.count(edges, &(&1.kind == :join)) == 2
      assert Enum.all?(join_edges(edges), &String.ends_with?(&1.d, "V 260"))

      # And the flow leaves the marker for the outlet: (200, 280) to (200, 300).
      assert Enum.filter(edges, &(&1.kind == :flow)) == [
               %Edge{kind: :flow, d: "M 200 280 L 200 300"}
             ]
    end

    # `ViewModel.arrangement/1` is what decides a fan exists, so a type that
    # declares `layout: :columns` fans into its single lane rather than taking
    # the single-entry edge a stacked container takes.
    # Sabotage: routing `entry_edges/2` on the body-slot count again - a
    # one-lane parallel is laid out as columns with a pill above it and drawn
    # with a straight edge into the first card, so the picture and the lines
    # disagree about what is arranged.
    test "a declared columns layout fans, even into one lane" do
      lane =
        block("blk_par",
          type: "core.parallel",
          entry: %{layout: :columns},
          slots: [slot("lane_a", [block("blk_a")])]
        )

      edges = Connectors.edges(lane, lane_measurement())

      assert Enum.count(edges, &(&1.kind == :fan)) == 1
      assert Enum.count(edges, &(&1.kind == :join)) == 1
    end
  end

  # ------------------------------------------------------------- fixtures

  defp fan_edges(edges), do: Enum.filter(edges, &(&1.kind == :fan))
  defp join_edges(edges), do: Enum.filter(edges, &(&1.kind == :join))

  defp lane_measurement do
    measured(%{
      "stage" => {0, 0, 400, 400},
      "card:blk_par" => {0, 0, 400, 30},
      "outlet:blk_par" => {0, 300, 400, 0},
      "slot:blk_par/lane_a" => {0, 50, 400, 20},
      "card:blk_a" => {0, 80, 400, 30},
      "outlet:blk_a" => {0, 120, 400, 0}
    })
  end

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

  # The `sb-d4cr` repro. The shelf sits in an arm literally named `body`,
  # which is the slot name `Shelf.validate/1` admits one in, so this is a
  # document the compiler accepts and not a shape only the view model can
  # hold: one arm ends in a shelf, the other holds nothing else.
  defp shelved_branch do
    block("blk_branch",
      type: "core.branch",
      slots: [
        slot("body", [block("blk_a"), block("blk_drafts", type: "core.drafts")]),
        slot("arm_b", [block("blk_only_drafts", type: "core.drafts")])
      ]
    )
  end

  defp shelved_branch_measurement do
    measured(%{
      "stage" => {0, 0, 400, 400},
      "card:blk_branch" => {0, 0, 400, 30},
      "outlet:blk_branch" => {0, 300, 400, 0},
      "slot:blk_branch/body" => {0, 50, 190, 20},
      "slot:blk_branch/arm_b" => {210, 50, 190, 20},
      "card:blk_a" => {0, 80, 190, 30},
      "outlet:blk_a" => {0, 120, 190, 0},
      "card:blk_drafts" => {0, 150, 190, 30},
      "outlet:blk_drafts" => {0, 190, 190, 0},
      "card:blk_only_drafts" => {210, 80, 190, 30},
      "outlet:blk_only_drafts" => {210, 120, 190, 0}
    })
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

  # The same rail, with the body OVERFLOWING the node box the way a stretched
  # container's does on the canvas: the node box stays 400 and the body is
  # 600. The two anchors disagreeing is the only condition under which
  # `channel_box/2` says anything at all.
  defp overflowing_measurement do
    Map.merge(rail_measurement(), measured(%{"slots:blk_group" => {0, 40, 600, 250}}))
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
