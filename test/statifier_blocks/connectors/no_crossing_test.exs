defmodule StatifierBlocks.Connectors.NoCrossingTest do
  @moduledoc """
  The property a reader actually checks the connector layer against: a line
  between two cards does not go through a third one.

  Every other assertion about this module is local - one path function, two
  points, one string. That is what `StatifierBlocks.ConnectorsTest` does, and
  it is worth doing, but it cannot see `sb-cwo`: on the `card_processing`
  document every path function was individually correct and the picture was
  still wrong, because a nested arrangement had overflowed its column and put
  two arms of one branch underneath the two lanes beside it. Cards never
  collided, so nothing about the page looked broken until a rejoin edge
  dropped down its own lane's band to reach the join marker and crossed three
  cards that were never in that lane.

  So this file asserts the whole picture at once, over one real document's
  real measurements. `test/fixtures/measurements/card_processing.json` is a
  verbatim capture of what the browser laid out - the same payload shape
  `StatifierBlocksMeasure` pushes, decoded here by the same
  `Connectors.measurement/1` that decodes the live one - and
  `card_processing_edges.json` names the anchors each drawn edge ran between.
  The paths below are recomputed from those rectangles by the shipped path
  functions, so the test fails if the geometry changes OR if the layout that
  produced the rectangles regresses.

  Deliberately **not** tagged `:liveview`, and it reads no DOM: capturing the
  measurement needed a browser once, checking it needs none. That is clause
  7b.2's whole point, and it is why this runs in the headless tree.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.Connectors
  alias StatifierBlocks.Connectors.Rect

  @measurement_fixture "test/fixtures/measurements/card_processing.json"
  @edges_fixture "test/fixtures/measurements/card_processing_edges.json"

  # A hair inside each card, so an edge that legitimately STARTS on a card's
  # bottom edge or ENDS on another's top edge is touching it, not crossing it.
  @inset 0.5

  describe "card_processing, as the browser laid it out" do
    setup do
      raw = @measurement_fixture |> File.read!() |> JSON.decode!()

      %{
        measurement: Connectors.measurement(raw),
        ancestry: ancestry(raw),
        edges: @edges_fixture |> File.read!() |> JSON.decode!() |> Map.fetch!("edges")
      }
    end

    # sabotage: dropping any one anchor from the measurement fixture, or any
    # one edge from the edge fixture, moves these counts and this goes red -
    # which is what stops a half-captured fixture passing the assertions
    # below by having nothing left in it to cross.
    test "the fixture is the document, not a fragment of it", ctx do
      assert map_size(ctx.measurement) == 178
      assert length(ctx.edges) == 68

      assert ctx.edges |> Enum.frequencies_by(& &1["kind"]) ==
               %{"flow" => 34, "fan" => 14, "join" => 14, "interrupt" => 6}
    end

    # sabotage: regenerating the fixture from the pre-fix capture - where
    # `node:blk_cp_lanes` was 338.5px wide and its lanes overflowed it - puts
    # six join crossings back and this names every one of them.
    test "no flow, fan or join edge crosses a card that is not its own end", ctx do
      crossings =
        for edge <- ctx.edges,
            edge["kind"] != "interrupt",
            path = path(edge, ctx.measurement),
            {key, rect} <- cards(ctx.measurement),
            key not in endpoints(edge),
            crosses?(path, rect),
            do: {edge["kind"], edge["from"], edge["to"], key}

      assert crossings == []
    end

    # sabotage: the same pre-fix fixture, where the overflow put descendants
    # of `blk_cp_authz` and `blk_cp_fraud` outside their own boxes - this
    # names each region and the card that escaped it.
    test "a region's own box contains everything laid out inside it", ctx do
      escaped =
        for edge <- ctx.edges,
            edge["kind"] == "interrupt",
            region = edge["region"],
            %Rect{} = box = Map.fetch!(ctx.measurement, Connectors.node_anchor(region)),
            {key, rect} <- descendants(ctx.measurement, ctx.ancestry, region),
            rect.x + rect.width > box.x + box.width,
            do: {region, key}

      assert escaped == []
    end

    # sabotage: collapsing `interrupt_path/4`'s channel onto the rule's own
    # right edge (`channel_x = fx`) runs every rail back down through its
    # region, and this goes red for all six at once with the x each took.
    test "every interrupt rail runs outside its region, not back across it", ctx do
      inside =
        for edge <- ctx.edges,
            edge["kind"] == "interrupt",
            path = path(edge, ctx.measurement),
            extent = extent(ctx.measurement, ctx.ancestry, edge["region"]),
            channel(path) <= extent,
            do: {edge["region"], edge["from"], channel(path), extent}

      assert inside == []
    end
  end

  # ------------------------------------------------------------- the paths

  # Recomputed by the shipped functions rather than stored, so a change to the
  # geometry is caught here and not only in the unit assertions.
  defp path(%{"kind" => "flow"} = edge, m),
    do: Connectors.flow_path(outlet(edge["from"], m), inlet(edge["to"], m))

  defp path(%{"kind" => "fan"} = edge, m),
    do: Connectors.fan_path(outlet(edge["from"], m), inlet(edge["to"], m))

  defp path(%{"kind" => "join"} = edge, m),
    do: Connectors.join_path(outlet(edge["from"], m), inlet(edge["to"], m))

  defp path(%{"kind" => "interrupt"} = edge, m) do
    %Rect{} = card = Map.fetch!(m, edge["from"])

    Connectors.interrupt_path(
      %{x: card.x + card.width, y: card.y + card.height / 2},
      inlet(edge["exit"], m),
      edge["channel_x"]
    )
  end

  defp outlet(key, m), do: m |> Map.fetch!(key) |> Connectors.outlet()
  defp inlet(key, m), do: m |> Map.fetch!(key) |> Connectors.inlet()

  # ------------------------------------------------------------ the boxes

  defp cards(m), do: Enum.filter(m, fn {key, _rect} -> String.starts_with?(key, "card:") end)

  # The card anchors an edge is allowed to touch: the blocks its own two
  # anchors name. `outlet:x`, `fan:x` and `join:x` are all block `x`, and
  # `slot:x/name` is block `x` too - a fan landing on a slot header may pass
  # its owner's chrome on the way there.
  defp endpoints(edge) do
    [edge["from"], edge["to"], edge["exit"]]
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&Connectors.card_anchor(block_id(&1)))
  end

  defp block_id("slot:" <> rest) do
    rest |> String.split("/") |> Enum.drop(-1) |> Enum.join("/")
  end

  defp block_id(key), do: key |> String.split(":", parts: 2) |> List.last()

  # The hook's payload carries no ancestry - this is the one thing the fixture
  # adds to it, because "inside this region" is a DOM question and the whole
  # point of the interrupt assertions is that the answer is not "whatever the
  # region's box happens to be".
  defp ancestry(%{"anchors" => anchors}) do
    Map.new(anchors, fn anchor -> {anchor["k"], Map.get(anchor, "anc", [])} end)
  end

  defp descendants(m, ancestry, region) do
    Enum.filter(cards(m), fn {key, _rect} -> region in Map.get(ancestry, key, []) end)
  end

  defp extent(m, ancestry, region) do
    m
    |> descendants(ancestry, region)
    |> Enum.map(fn {_key, rect} -> rect.x + rect.width end)
    |> Enum.max(fn -> 0.0 end)
  end

  # ---------------------------------------------------------- the geometry

  # The channel an interrupt path runs down: its right-most point, which is
  # where `interrupt_path/4` turns the corner.
  defp channel(path), do: path |> points() |> Enum.map(& &1.x) |> Enum.max()

  defp crosses?(path, %Rect{} = rect) do
    path |> points() |> Enum.chunk_every(2, 1, :discard) |> Enum.any?(&segment_enters?(&1, rect))
  end

  defp segment_enters?([%{x: x1, y: y1}, %{x: x2, y: y2}], %Rect{} = rect) do
    left = rect.x + @inset
    right = rect.x + rect.width - @inset
    top = rect.y + @inset
    bottom = rect.y + rect.height - @inset

    cond do
      left >= right or top >= bottom -> false
      close?(x1, x2) -> between?(x1, left, right) and overlaps?(y1, y2, top, bottom)
      close?(y1, y2) -> between?(y1, top, bottom) and overlaps?(x1, x2, left, right)
      true -> false
    end
  end

  defp close?(a, b), do: abs(a - b) < 0.01
  defp between?(v, lo, hi), do: v > lo and v < hi
  defp overlaps?(a, b, lo, hi), do: min(a, b) < hi and max(a, b) > lo

  # Path data back into a polyline. A quadratic is taken as its end point,
  # which is a rounded corner's own corner - the conservative reading, since a
  # curve stays inside the square its control point defines.
  defp points(path) do
    path
    |> String.split(" ", trim: true)
    |> Enum.reduce({[], %{x: 0.0, y: 0.0}, nil, []}, &step/2)
    |> collect()
  end

  defp step(token, {points, cursor, command, args}) do
    case Float.parse(token) do
      {value, ""} -> emit(points, cursor, command, args ++ [value])
      :error -> {points, cursor, token, []}
    end
  end

  defp emit(points, _cursor, "M", [x, y]), do: {[%{x: x, y: y} | points], %{x: x, y: y}, "M", []}
  defp emit(points, _cursor, "L", [x, y]), do: {[%{x: x, y: y} | points], %{x: x, y: y}, "L", []}

  defp emit(points, cursor, "V", [y]),
    do: {[%{cursor | y: y} | points], %{cursor | y: y}, "V", []}

  defp emit(points, cursor, "H", [x]),
    do: {[%{cursor | x: x} | points], %{cursor | x: x}, "H", []}

  defp emit(points, _cursor, "Q", [_cx, _cy, x, y]),
    do: {[%{x: x, y: y} | points], %{x: x, y: y}, "Q", []}

  defp emit(points, cursor, command, args), do: {points, cursor, command, args}

  defp collect({points, _cursor, _command, _args}), do: Enum.reverse(points)
end
