defmodule StatifierBlocks.Connectors do
  @moduledoc """
  Connector geometry: pure functions from measured rectangles to SVG path
  data (ADR-0005 decision 10, and the 2026-08-29 amendment to decision 7).

  The amendment admits a second JavaScript hook, `StatifierBlocksMeasure`,
  whose entire job is to read the boxes the browser laid out and push them.
  Clause 7b.2 then says where the drawing happens: **the connector geometry
  itself is computed on the server, as pure functions from measured
  rectangles to path data.** That is this module. It is the graduation of the
  geometry half of the campaign-012/013 spike's `spike/js/layout.js`, which
  kept the same split for the same reason and which
  `spike/dev/selftest.html` could only assert inside Chrome.

  Here it runs in the gate. Nothing below reads the DOM, names a block type,
  or reaches for the web framework: a rectangle is a rectangle, and that is
  what keeps decision 13's promise that rendering is testable without a
  browser. This module therefore lives outside `StatifierBlocks.Editor.*`
  and loads in the headless tree, exactly as `ViewModel` and `Shell` do.

  ## The three stages

  1. `measurement/1` decodes the hook's push into `%{anchor key => rect}`.
     It is **total**: the payload arrives from the DOM, which is not a
     trusted source, and anything malformed is dropped rather than raised on.
  2. `edges/2` walks a `ViewModel.Node` tree and, for every edge adjacency
     and nesting imply, resolves the anchors it needs and emits one `Edge`.
     An edge whose anchors were not measured is **skipped**, which is what
     makes the whole layer degrade to nothing when the hook is absent.
  3. The path functions - `flow_path/3`, `fan_path/3`, `join_path/3`,
     `interrupt_path/4` - turn two points into orthogonal path data with
     rounded corners. Orthogonal rather than bezier because at nesting depth
     7 a curve that passes near a card reads as ambiguous and a right angle
     never does.

  ## The 7d choices this module records

  Clause 7d left four questions to the implementation, each to be answered
  "with a test rather than by guess". All four are written down here,
  because a wire has two ends and the record should be readable from the
  end that is testable in the gate.

  ### Payload shape: whole stage, flat, keyed by the server's own string

  One push carries **every measured anchor**, never a delta:

      %{
        "stage" => %{"w" => 1200.0, "h" => 2400.0},
        "anchors" => [%{"k" => "card:blk_a", "x" => 8.0, "y" => 8.0,
                        "w" => 300.0, "h" => 32.0}, ...]
      }

  A delta needs a shared memory of the previous measurement on both ends,
  and 7a forbids the hook holding "state that survives a re-render". A whole
  stage also satisfies 7c's plainest statement of what a measurement is -
  that the push be reconstructible from the rendering alone - which a delta
  by construction is not.

  The key is the **string the server stamped** in `data-sb-anchor`. The hook
  never composes one and this module never parses one: keys are built by
  `card_anchor/1` and its siblings and compared whole, so a block id may
  contain any character an id may contain without the wire having an opinion
  about it.

  ### Coordinate space: the stage's own untransformed space

  Every rectangle is relative to the stage's top-left corner, in the stage's
  **untransformed** pixels. The hook subtracts the stage origin and divides
  by the scale it reads off the stage, which is the single arithmetic step
  the spike's `render.js` found necessary under zoom: the `<svg>` these
  coordinates are written into is a child of the stage, drawn in the stage's
  own space and sized from `scrollWidth`, so rendered coordinates would
  scale twice and detach every line from the card it joins.

  The alternative 7d names - push rendered coordinates and a scale, and let
  the server divide - was rejected because it would put the zoom into the
  server's geometry, and the property below is what it would have cost:
  **nothing in this module knows a scale or an origin exists.** Translating
  every measured rectangle translates every path by the same amount, and no
  other transform is applied anywhere.

  ### Push cadence: mount, update, and a stage resize, over two frames

  The hook measures on mount, on every `updated()`, and on a resize of the
  stage, and each of those is scheduled through TWO animation frames and
  coalesced into a single push. Two rather than one because the first frame
  is merely when the DOM is live and the second is after a font swap or a
  scrollbar has settled - the spike found exactly this, and routing against
  a pre-swap measurement is the classic way connectors end up a few pixels
  off the cards they join.

  The cadence terminates without the hook remembering anything, which is
  what 7a's "no state that survives a re-render" costs and why it costs
  nothing: `edges/2` is a pure function of the tree and the measurement, so
  an unchanged measurement renders unchanged markup, LiveView computes an
  empty diff, no patch is sent, and `updated()` is not called again. The
  loop closes on this module's purity rather than on the client's memory.

  ### Anchor attribute names: one attribute, one opaque value

  Decision 7's DOM contract gains exactly one attribute, `data-sb-anchor`,
  whose value is the anchor key. One attribute rather than a family of them
  because the hook's read is then `querySelectorAll("[data-sb-anchor]")` -
  one query, no knowledge of block structure, and no key composed on the
  client. The seven kinds of anchor the shipped markup stamps:

    * `stage` - the canvas root, which is what makes the other boxes
      comparable to each other (7c names the stage box explicitly);
    * `node:<block id>` - a block's whole box, which is where an interrupt
      channel is placed relative to;
    * `card:<block id>` - a block's chrome, the box an edge arrives at;
    * `outlet:<block id>` - a zero-height anchor at the bottom of a block,
      the box flow leaves from;
    * `slot:<block id>/<slot name>` - a slot's header, which is where a fan
      edge lands. Not the first card inside it: the header carries the
      slot's name and its guard, and an edge that ran past it would cross
      the very condition it is subject to;
    * `fan:<block id>` - the `ONE OF` / `ALL OF` pill below an arranged
      container, the point its fan leaves from;
    * `join:<block id>` - the join marker below that container's columns,
      the point their rejoins arrive at.

  The last two are the only anchors that may be absent while the block they
  name is on the page: a stacked container renders no pill and a type that
  phrased no join renders no marker. Both fall back to the card and the
  outlet, which is where every fan left and arrived before campaign 016.
  """

  alias StatifierBlocks.ViewModel
  alias StatifierBlocks.ViewModel.{Node, Slot}

  defmodule Rect do
    @moduledoc """
    One measured rectangle, in the stage's untransformed coordinate space.

    A plain struct rather than a map so that a malformed payload fails to
    build one rather than travelling half-decoded into the geometry.
    """

    @type t :: %__MODULE__{x: float(), y: float(), width: float(), height: float()}

    @enforce_keys [:x, :y, :width, :height]
    defstruct [:x, :y, :width, :height]
  end

  defmodule Edge do
    @moduledoc """
    One connector: the vocabulary it is drawn in, and its SVG path data.

    `kind` is what the stylesheet reads to pick a stroke token, and it is
    derived from the slot's `style` through `ViewModel.exit_edge/1` rather
    than from any type name (ADR-0005 decision 10h).

    There are four kinds and there is deliberately no fifth for a failure
    rail. `sb-67s` ruled that a failure exit leaves by the ORDINARY flow
    edge, and the spike's own assertion of that ruling is the sentence
    "a failure exit takes no class of its own": it shares one stylesheet
    rule with the edge between two adjacent steps, so it can never pick up
    the dashes or the warning hue that mark a way out of band. Giving it a
    `:failure` kind here would have re-created the distinction the ruling
    removed, one layer down.
    """

    @type kind :: :flow | :fan | :join | :interrupt

    @type t :: %__MODULE__{kind: kind(), d: String.t()}

    @enforce_keys [:kind, :d]
    defstruct [:kind, :d]
  end

  @typedoc "A point in the stage's untransformed coordinate space."
  @type point :: %{x: float(), y: float()}

  @typedoc "Every measured anchor, keyed by the string the server stamped."
  @type measurement :: %{optional(String.t()) => Rect.t()}

  # How far outside a container's own box an interrupt channel runs, and how
  # far apart two channels sit. Both are the spike's numbers: the channel is
  # outside the box so an exit edge has nothing to cross however deep the
  # group is nested, and two rules on one rail otherwise share every pixel of
  # their exit path, which looks like one edge rather than two.
  @channel_offset 10
  @channel_lane 6

  # Path data is rounded to a tenth of a pixel: shorter strings, no visible
  # difference. It happens here rather than in the hook so the hook does no
  # arithmetic beyond the two steps the coordinate space forces on it.
  @rounding 1

  # Below this the two ends count as vertically aligned and the edge is drawn
  # straight, which is the common case inside a sequence.
  @straight_epsilon 0.75

  @default_radius 10

  # ------------------------------------------------------------- anchors

  @doc "The canvas root's key: the origin every other box is relative to."
  @spec stage_anchor() :: String.t()
  def stage_anchor, do: "stage"

  @doc "A block's whole box."
  @spec node_anchor(StatifierBlocks.Block.id()) :: String.t()
  def node_anchor(block_id), do: "node:" <> block_id

  @doc "A block's chrome: the box an edge arrives at."
  @spec card_anchor(StatifierBlocks.Block.id()) :: String.t()
  def card_anchor(block_id), do: "card:" <> block_id

  @doc "The zero-height anchor at the bottom of a block: where flow leaves."
  @spec outlet_anchor(StatifierBlocks.Block.id()) :: String.t()
  def outlet_anchor(block_id), do: "outlet:" <> block_id

  @doc "A slot's header: where a fan edge lands."
  @spec slot_anchor(StatifierBlocks.Block.id(), StatifierBlocks.Block.slot_name()) :: String.t()
  def slot_anchor(parent_id, slot_name), do: "slot:" <> parent_id <> "/" <> slot_name

  @doc """
  The `ONE OF` / `ALL OF` pill below an arranged container: the point the
  fan leaves from, when one is drawn.

  A hub anchor rather than a decoration the edges ignore. The pill sits on
  the flow line between the container's card and its columns, and the
  connector overlay paints ABOVE the tree - so a fan that left the card
  would draw a line straight through the pill's own words. Leaving from the
  pill instead makes it what it looks like: the point the flow divides at.

  Absent from the measurement whenever no pill is rendered, and the fan
  falls back to the card. That is the same skip-when-unmeasured rule every
  other anchor here follows, so the pill is never a thing the geometry
  requires to exist.
  """
  @spec fan_anchor(StatifierBlocks.Block.id()) :: String.t()
  def fan_anchor(block_id), do: "fan:" <> block_id

  @doc """
  The join marker below an arranged container's columns: the point the
  rejoins arrive at, when one is drawn.

  The mirror of `fan_anchor/1`, and there for the same reason - a rejoin
  aimed past the marker crosses the word that says what the rejoin means.
  Absent unless the container's type phrased a join (ADR-0002 amendment B),
  and the rejoin falls back to the container's outlet.
  """
  @spec join_anchor(StatifierBlocks.Block.id()) :: String.t()
  def join_anchor(block_id), do: "join:" <> block_id

  # ------------------------------------------------------------- decoding

  @doc """
  The hook's push, decoded into `%{anchor key => Rect.t()}`.

  Total by construction. The payload crosses from the DOM, so every arm that
  is not a well-formed anchor - a missing key, a non-numeric coordinate, a
  shape that is not the one documented above - drops that anchor and keeps
  the rest. A payload that is not a map at all decodes to `%{}`, which is
  the same thing the editor holds before the first measurement arrives and
  the same thing it holds when no hook is imported at all.

  The stage's own extent decodes to `stage_anchor/0` with its origin at
  `{0, 0}`, because the stage IS the origin: the scroll extent is what the
  `<svg>` is sized from, and it is a layout measurement no transform on the
  stage touches.
  """
  @spec measurement(term()) :: measurement()
  def measurement(%{} = params) do
    params
    |> Map.get("anchors")
    |> anchors()
    |> put_stage(Map.get(params, "stage"))
  end

  def measurement(_other), do: %{}

  @spec anchors(term()) :: measurement()
  defp anchors(list) when is_list(list) do
    Enum.reduce(list, %{}, fn entry, acc ->
      case anchor(entry) do
        {key, %Rect{} = rect} -> Map.put(acc, key, rect)
        :error -> acc
      end
    end)
  end

  defp anchors(_other), do: %{}

  @spec anchor(term()) :: {String.t(), Rect.t()} | :error
  defp anchor(%{"k" => key, "x" => x, "y" => y, "w" => w, "h" => h}) when is_binary(key) do
    with {:ok, x} <- number(x),
         {:ok, y} <- number(y),
         {:ok, w} <- number(w),
         {:ok, h} <- number(h) do
      {key, %Rect{x: x, y: y, width: w, height: h}}
    end
  end

  defp anchor(_other), do: :error

  @spec put_stage(measurement(), term()) :: measurement()
  defp put_stage(acc, %{"w" => w, "h" => h}) do
    with {:ok, w} <- number(w),
         {:ok, h} <- number(h) do
      Map.put(acc, stage_anchor(), %Rect{x: 0.0, y: 0.0, width: w, height: h})
    else
      :error -> acc
    end
  end

  defp put_stage(acc, _other), do: acc

  @spec number(term()) :: {:ok, float()} | :error
  defp number(value) when is_float(value), do: {:ok, value}
  defp number(value) when is_integer(value), do: {:ok, value * 1.0}
  defp number(_other), do: :error

  @doc """
  The stage's extent, or `nil` when nothing has been measured.

  The `<svg>`'s own width, height and `viewBox`, which is why it is asked
  for separately rather than looked up as one anchor among the rest: a
  connector layer with no stage has no box to draw in and renders nothing.
  """
  @spec stage(measurement()) :: Rect.t() | nil
  def stage(measurement), do: Map.get(measurement, stage_anchor())

  # ---------------------------------------------------------------- walk

  @doc """
  Every connector the tree implies, given what the browser measured.

  Adjacency inside a slot and the nesting of slots are the only sources of
  truth here, exactly as ADR-0005 decision 10a requires - connectors are
  rendered, never authored, and nothing below branches on a type name. The
  three derivations, all of them reading decision 10's presentation
  metadata:

    * **flow between adjacent children of one slot**, from the earlier
      block's outlet to the later block's card. Every slot, rails included:
      two rules attached to one rail still run in the order they are in.

    * **the fan and the rejoin**, for a container `ViewModel.arrangement/1`
      says is arranged side by side - `layout: :columns`, or more than one
      body slot, which gives `core.parallel` and `core.branch` the same
      treatment without naming either. It is the same function the renderer
      read to lay those columns out, so the lines and the layout answer one
      question once. A fan edge runs from the container's hub to each slot's
      HEADER, and a rejoin runs from the last thing in that slot back to the
      container's join hub; the hubs are the `ONE OF` / `ALL OF` pill and the
      join marker when those were measured, and the card and the outlet when
      they were not. A container with a single body slot instead gets one
      flow edge from its card into the first block of that slot.

    * **rail exits**, one per attached rule, in the vocabulary
      `ViewModel.exit_edge/1` derives from the slot's style: a `:failure`
      rail leaves by the ordinary flow edge, in the ordinary `:flow`
      vocabulary (the `sb-67s` ruling), and an
      `:secondary` rail leaves out of band, through a channel outside the
      container's own box so it crosses nothing at any depth.

  An edge whose anchors are not in `measurement` is skipped rather than
  guessed at. With an empty measurement - no hook imported, or a first
  render that has not been measured yet - the result is `[]` and the editor
  is the editor it was before, minus the drawn connectors. That is clause
  7b.3's standing test, and it is a property of this function rather than of
  a flag anywhere.

  Idempotent, and a pure function of its two arguments: the same tree and
  the same measurement give the same list, which is what makes a re-push
  safe. A measurement that has not changed produces markup that has not
  changed, so the render loop the hook could otherwise drive terminates on
  its own without the hook remembering anything.
  """
  @spec edges(Node.t(), measurement()) :: [Edge.t()]
  def edges(%Node{}, measurement) when map_size(measurement) == 0, do: []

  def edges(%Node{} = root, measurement) when is_map(measurement),
    do: root |> node_edges(measurement) |> List.flatten()

  @spec node_edges(Node.t(), measurement()) :: [term()]
  defp node_edges(%Node{} = node, m) do
    [
      adjacency_edges(node, m),
      entry_edges(node, m),
      rail_edges(node, m),
      for(slot <- node.slots, child <- slot.children, do: node_edges(child, m))
    ]
  end

  # Flow between adjacent children of one slot. Read off adjacency and
  # nothing else, which is the whole of decision 10a on this edge.
  @spec adjacency_edges(Node.t(), measurement()) :: [Edge.t()]
  defp adjacency_edges(%Node{slots: slots}, m) do
    for slot <- slots,
        [%Node{block_id: from}, %Node{block_id: to}] <-
          Enum.chunk_every(slot.children, 2, 1, :discard),
        edge = flow_edge(:flow, outlet_anchor(from), card_anchor(to), m),
        do: edge
  end

  # A container's own entry: either a fan into several arranged slots, or one
  # edge into the single body slot it has.
  @spec entry_edges(Node.t(), measurement()) :: [Edge.t()]
  defp entry_edges(%Node{} = node, m) do
    case {arranged?(node), body_slots(node)} do
      {_arranged, []} -> []
      {true, body} -> fan_edges(node, body, m)
      {false, [only | _rest]} -> Enum.reject([single_entry(node, only, m)], &is_nil/1)
    end
  end

  @spec single_entry(Node.t(), Slot.t(), measurement()) :: Edge.t() | nil
  defp single_entry(%Node{}, %Slot{children: []}, _m), do: nil

  defp single_entry(%Node{} = node, %Slot{} = slot, m),
    do: flow_edge(:flow, card_anchor(node.block_id), first_card(slot), m)

  # The side-by-side arrangement's edges. `ViewModel.arrangement/1` is what
  # decided the columns exist - the same function the renderer read to put
  # them side by side and to word the pill above them - so the picture and
  # the lines cannot disagree about what is arranged.
  #
  # Both hubs are the MARKER when one was measured and the card or the outlet
  # otherwise. The markers sit on the flow line and the overlay paints above
  # the tree, so a fan leaving the card would cross the pill's own words on
  # the way past it; leaving from the pill draws what the pill looks like.
  # The short edge from the card into the pill, and out of the join marker
  # into the container's outlet, are ordinary flow.
  @spec fan_edges(Node.t(), [Slot.t()], measurement()) :: [Edge.t()]
  defp fan_edges(%Node{} = node, slots, m) do
    card = card_anchor(node.block_id)
    outlet = outlet_anchor(node.block_id)
    hub = marker_or(fan_anchor(node.block_id), card, m)
    join = marker_or(join_anchor(node.block_id), outlet, m)

    arm_edges =
      Enum.flat_map(slots, fn slot ->
        head = slot_anchor(node.block_id, slot.name)

        [
          path_edge(:fan, hub, head, m, &fan_path(outlet(&1), inlet(&2))),
          path_edge(:join, slot_exit(node, slot), join, m, &join_path(outlet(&1), inlet(&2)))
        ]
      end)

    marker_edges =
      [
        if(hub != card, do: flow_edge(:flow, card, hub, m)),
        if(join != outlet, do: flow_edge(:flow, join, outlet, m))
      ]

    Enum.reject(marker_edges ++ arm_edges, &is_nil/1)
  end

  # A marker's anchor when the browser measured one, and the fallback when it
  # did not. A container whose type phrased no join renders no join marker,
  # and a stacked container renders no pill: neither is a hole to guess at.
  @spec marker_or(String.t(), String.t(), measurement()) :: String.t()
  defp marker_or(marker, fallback, m),
    do: if(Map.has_key?(m, marker), do: marker, else: fallback)

  # A slot's exit anchor: the last block's outlet, or the slot's own header
  # when it is empty. An empty arm is a real arm of the branch, and a fan
  # that silently skipped it would tell an author their empty arm does not
  # exist.
  @spec slot_exit(Node.t(), Slot.t()) :: String.t()
  defp slot_exit(%Node{block_id: parent_id}, %Slot{children: []} = slot),
    do: slot_anchor(parent_id, slot.name)

  defp slot_exit(%Node{block_id: parent_id}, %Slot{} = slot) do
    case List.last(slot.children) do
      %Node{block_id: id} -> outlet_anchor(id)
      _other -> slot_anchor(parent_id, slot.name)
    end
  end

  @spec first_card(Slot.t()) :: String.t() | nil
  defp first_card(%Slot{children: [%Node{block_id: id} | _rest]}), do: card_anchor(id)
  defp first_card(%Slot{}), do: nil

  # Rail exits. The walk is per SLOT rather than over the whole rail, because
  # the slot is what carries the style and one container can attach both
  # kinds at once. Lanes are counted over the interrupt edges only: a flow
  # exit never enters the channel, so letting one consume a lane would leave
  # a visible gap between two interrupt edges that are in fact adjacent.
  @spec rail_edges(Node.t(), measurement()) :: [Edge.t()]
  defp rail_edges(%Node{} = node, m) do
    exit_key = outlet_anchor(node.block_id)

    node.slots
    |> Enum.filter(&ViewModel.rail?/1)
    |> Enum.flat_map(fn slot -> Enum.map(slot.children, &{ViewModel.exit_edge(slot), &1}) end)
    |> Enum.reduce({[], 0}, fn {vocabulary, child}, {acc, lane} ->
      case rail_edge(node, vocabulary, child, exit_key, lane, m) do
        {edge, next_lane} -> {[edge | acc], next_lane}
        :none -> {acc, lane}
      end
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  @spec rail_edge(Node.t(), :flow | :interrupt, Node.t(), String.t(), non_neg_integer(), map()) ::
          {Edge.t(), non_neg_integer()} | :none
  defp rail_edge(%Node{}, :flow, %Node{block_id: id}, exit_key, lane, m) do
    # From the rule's OUTLET, the same anchor an ordinary flow edge leaves
    # any block from, so a failure subtree that is itself a container leaves
    # from its bottom rather than from its header. `:flow` rather than a kind
    # of its own is the `sb-67s` ruling itself: a failure exit takes no class
    # of its own, so it cannot pick up the dashes or the hue that mark an
    # out-of-band way out.
    case flow_edge(:flow, outlet_anchor(id), exit_key, m) do
      nil -> :none
      edge -> {edge, lane}
    end
  end

  defp rail_edge(%Node{} = node, :interrupt, %Node{block_id: id}, exit_key, lane, m) do
    with %Rect{} = box <- Map.get(m, node_anchor(node.block_id)),
         %Rect{} = card <- Map.get(m, card_anchor(id)),
         %Rect{} = target <- Map.get(m, exit_key) do
      from = %{x: card.x + card.width, y: card.y + card.height / 2}
      channel_x = box.x + box.width + @channel_offset + lane * @channel_lane

      {%Edge{kind: :interrupt, d: interrupt_path(from, inlet(target), channel_x)}, lane + 1}
    else
      _missing -> :none
    end
  end

  @spec body_slots(Node.t()) :: [Slot.t()]
  defp body_slots(%Node{} = node), do: ViewModel.body_slots(node)

  # One derivation of "is this arranged", shared with the renderer. A
  # container the editor drew side by side and this module drew a single
  # entry edge into would be a line contradicting the layout it was measured
  # off, which is the class of bug ADR-0005 amendment 10b's measure-never-
  # compute rule cannot catch on its own.
  @spec arranged?(Node.t()) :: boolean()
  defp arranged?(%Node{} = node), do: ViewModel.arrangement(node) != :stack

  @spec flow_edge(Edge.kind(), String.t() | nil, String.t() | nil, measurement()) ::
          Edge.t() | nil
  defp flow_edge(kind, from, to, m),
    do: path_edge(kind, from, to, m, &flow_path(outlet(&1), inlet(&2)))

  @spec path_edge(Edge.kind(), String.t() | nil, String.t() | nil, measurement(), fun()) ::
          Edge.t() | nil
  defp path_edge(kind, from, to, m, build) when is_binary(from) and is_binary(to) do
    with %Rect{} = a <- Map.get(m, from),
         %Rect{} = b <- Map.get(m, to) do
      %Edge{kind: kind, d: build.(a, b)}
    else
      _missing -> nil
    end
  end

  defp path_edge(_kind, _from, _to, _m, _build), do: nil

  # ------------------------------------------------------------ geometry

  @doc "The point flow leaves a rectangle from."
  @spec outlet(Rect.t()) :: point()
  def outlet(%Rect{} = rect), do: %{x: rect.x + rect.width / 2, y: rect.y + rect.height}

  @doc "The point flow enters a rectangle at."
  @spec inlet(Rect.t()) :: point()
  def inlet(%Rect{} = rect), do: %{x: rect.x + rect.width / 2, y: rect.y}

  @doc """
  A flow edge from one point down to another, orthogonally.

  Straight when the two are vertically aligned; otherwise down to the
  halfway line, across, and down again, with the corners rounded by `radius`
  - clamped so a short edge cannot turn its own corners inside out.
  """
  @spec flow_path(point(), point(), number()) :: String.t()
  def flow_path(from, to, radius \\ @default_radius)

  def flow_path(%{x: fx, y: fy}, %{x: tx, y: ty}, _radius)
      when abs(tx - fx) < @straight_epsilon,
      do: "M #{n(fx)} #{n(fy)} L #{n(fx)} #{n(ty)}"

  def flow_path(%{x: fx, y: fy}, %{x: tx, y: ty}, radius) do
    mid_y = (fy + ty) / 2
    dir = if tx > fx, do: 1, else: -1
    r = clamp(radius, [abs(tx - fx) / 2, abs(ty - fy) / 2])

    Enum.join(
      [
        "M #{n(fx)} #{n(fy)}",
        "V #{n(mid_y - r)}",
        "Q #{n(fx)} #{n(mid_y)} #{n(fx + dir * r)} #{n(mid_y)}",
        "H #{n(tx - dir * r)}",
        "Q #{n(tx)} #{n(mid_y)} #{n(tx)} #{n(mid_y + r)}",
        "V #{n(ty)}"
      ],
      " "
    )
  end

  @doc """
  A fan edge: from a hub down and out to one slot's inlet.

  The same routing a flow edge takes - the difference is the class the
  renderer puts on it, not the geometry - but the elbow is pulled up close
  to the hub rather than sitting halfway, so every arm of one fan turns on
  the same line and the result reads as a distribution bar rather than as
  several unrelated edges.
  """
  @spec fan_path(point(), point(), number()) :: String.t()
  def fan_path(hub, to, radius \\ @default_radius)

  def fan_path(%{x: hx, y: hy}, %{x: tx, y: ty}, _radius)
      when abs(tx - hx) < @straight_epsilon,
      do: "M #{n(hx)} #{n(hy)} L #{n(hx)} #{n(ty)}"

  def fan_path(%{x: hx, y: hy}, %{x: tx, y: ty}, radius) do
    elbow_y = hy + min(radius * 1.6, abs(ty - hy) / 2)
    dir = if tx > hx, do: 1, else: -1
    r = clamp(radius, [abs(tx - hx) / 2, abs(ty - elbow_y)])

    Enum.join(
      [
        "M #{n(hx)} #{n(hy)}",
        "V #{n(elbow_y - r)}",
        "Q #{n(hx)} #{n(elbow_y)} #{n(hx + dir * r)} #{n(elbow_y)}",
        "H #{n(tx - dir * r)}",
        "Q #{n(tx)} #{n(elbow_y)} #{n(tx)} #{n(elbow_y + r)}",
        "V #{n(ty)}"
      ],
      " "
    )
  end

  @doc """
  A rejoin edge: from one slot's exit down and in to a join hub.

  The mirror of `fan_path/3` - the elbow sits close to the HUB, which here
  is the lower end, so every arm turns on one line again.
  """
  @spec join_path(point(), point(), number()) :: String.t()
  def join_path(from, hub, radius \\ @default_radius)

  def join_path(%{x: fx, y: fy}, %{x: hx, y: hy}, _radius)
      when abs(hx - fx) < @straight_epsilon,
      do: "M #{n(fx)} #{n(fy)} L #{n(fx)} #{n(hy)}"

  def join_path(%{x: fx, y: fy}, %{x: hx, y: hy}, radius) do
    elbow_y = hy - min(radius * 1.6, abs(hy - fy) / 2)
    dir = if hx > fx, do: 1, else: -1
    r = clamp(radius, [abs(hx - fx) / 2, abs(elbow_y - fy)])

    Enum.join(
      [
        "M #{n(fx)} #{n(fy)}",
        "V #{n(elbow_y - r)}",
        "Q #{n(fx)} #{n(elbow_y)} #{n(fx + dir * r)} #{n(elbow_y)}",
        "H #{n(hx - dir * r)}",
        "Q #{n(hx)} #{n(elbow_y)} #{n(hx)} #{n(elbow_y + r)}",
        "V #{n(hy)}"
      ],
      " "
    )
  end

  @doc """
  An interrupt exit edge: from a rule on the interrupt rail, out past the
  right-hand side of its container, and down to the container's exit point.

  One corner rather than two, and it leaves the rule's card from its RIGHT
  edge and travels down a channel to the right of everything the container
  holds. `channel_x` is that channel, and placing it outside the container's
  own box is the routing rule that keeps interrupt edges from crossing the
  body of the container at any depth: there is nothing out there to cross.
  """
  @spec interrupt_path(point(), point(), number(), number()) :: String.t()
  def interrupt_path(from, exit_point, channel_x, radius \\ @default_radius)

  def interrupt_path(%{x: fx, y: fy}, %{x: ex, y: ey}, channel_x, radius) do
    r = clamp(radius, [abs(channel_x - fx), abs(ey - fy) / 2])

    Enum.join(
      [
        "M #{n(fx)} #{n(fy)}",
        "H #{n(channel_x - r)}",
        "Q #{n(channel_x)} #{n(fy)} #{n(channel_x)} #{n(fy + r)}",
        "V #{n(ey - r)}",
        "Q #{n(channel_x)} #{n(ey)} #{n(channel_x - r)} #{n(ey)}",
        "H #{n(ex)}"
      ],
      " "
    )
  end

  @spec clamp(number(), [number()]) :: number()
  defp clamp(radius, bounds), do: max(0, Enum.min([radius | bounds]))

  # A whole number renders without a decimal point, which is what makes the
  # shipped path strings literally the strings `spike/dev/selftest.html`
  # asserted in Chrome. `10.0` and `10` draw the same line; only one of them
  # can be compared against the spike's own evidence.
  @spec n(number()) :: String.t()
  defp n(value) do
    rounded = Float.round(value / 1, @rounding)

    if rounded == trunc(rounded),
      do: Integer.to_string(trunc(rounded)),
      else: Float.to_string(rounded)
  end
end
