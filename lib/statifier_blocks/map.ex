defmodule StatifierBlocks.Map do
  @moduledoc """
  The Map: the block document drawn as boxes in boxes, laid out by ELK in
  the browser. This module builds the graph a layout hook lays out and
  draws; it computes no position itself and calls no layout engine. Its
  input is the view model and the host's two options below; it never
  reads the document itself.

  ## A reader of the view model, never a second model

  The graph is derived from `StatifierBlocks.ViewModel` on every change
  and is never stored: no coordinate, no connector and no hand-placed
  position reaches the document or any table. What an author edits is the
  block tree, and the map is one more way of reading it, beside the
  indented list a host draws from the same
  `StatifierBlocks.ViewModel.outline/1`. The two cannot disagree about what
  is in the document, because `nodes/1` below is the outline's own block
  list and the test beside this module holds them equal. It is not a
  layout mode of the editor: it reads the struct the editor reads, and
  changes nothing in it.

  ## Its input

  `graph/2` takes the view model and two options, both the host's:

  | Option | What it is | Default |
  |---|---|---|
  | `:selected` | the block id the host has selected, or `nil` | `nil` |
  | `:phrase` | a function from an event name to the words a reader reads for it, answering `nil` for a name it has no words for | no words: every name as authored |

  The selection marks one block's node `"selected" => true` and changes
  nothing else in the graph, so a host whose selection moves hands the hook
  the same boxes. A selection naming no block marks nothing.

  ## The shape

  | Graph node | What it is | Where its children come from |
  |---|---|---|
  | a block | one `ViewModel.Node`, keyed by its block id | its slots, below |
  | a slot | one of a block's slots, keyed `<block id>/<slot name>` | the slot's blocks, in slot order |
  | an empty marker | a slot with nothing in it, keyed `<slot id>/empty`, carrying `parent` and `slot` | nothing |

  Every block but the root carries `gap: true`: it sits in a slot, so there
  is a place right after it an insert can target, the same place the list's
  "+" under its row targets. The root sits in no slot. An empty marker is
  the other kind of gap: the head of the slot it stands for.

  A block whose only body slot stacks (`ViewModel.arrangement/1` is
  `:stack`) holds that slot's blocks directly, because a sequence drawn
  inside a box inside a box says nothing the one box does not. Every other
  slot is a node of its own: a branch's arms side by side, a parallel's
  lanes, a group's interrupt rules and a drafts shelf. A group is the one
  exception the other way: its body stacks, but it is drawn as a slot node
  of its own all the same (see "The Group" below). An empty slot is
  drawn as a marker rather than left out - an outcome nobody has written a
  step for yet is exactly what a reader of the map has to be able to see.

  Consecutive blocks in one body slot are joined by a `sequence` edge, in
  `ViewModel.flow_children/1` order (a `rejoin` edge where the first is a
  branch; see "The Branch" below); besides the edges out of the start
  dot and into the end marks (below), nothing else is an edge the layout
  sees (a group's interrupt edges are drawn after it, below). A rail's
  blocks are not joined - a group's interrupt rules are alternatives that
  each watch the whole body, not steps that run one after another - and
  neither is a tray's. Connectors are drawn, never authored.

  A box's title is its type's name and the line under it is the block's
  sentence, with the event names the host's `:phrase` has words for read
  as words: a send reads "Send word that" and the words, a wait "Wait
  until" and the words, a name anywhere else the words alone, and a name
  the host has no words for stays as authored. Where the title and the
  sentence are the same words ("Invoke", "Raise") the line is left off
  rather than said twice.

  ## The Branch

  A branch is one decision, and its box says so in three ways.

  - **The header names every arm, in order.** Where every other container
    carries its sentence, a `core.branch` carries the package's own "one
    of" and then one numbered entry per arm, in slot order, each the arm's
    label and its condition as authored (`When "renew": copy.holds == 0
    AND loan.renewals < 2`), the arms with no condition ("Otherwise",
    "Cannot be decided") by their label alone. An entry wider than a line
    wraps, and its later lines are indented under its label, by the width
    of its number, so a wrapped condition does not read as an entry of its
    own.
    This header is the map's own: the branch type's sentence, which the
    list draws, is not changed by it.
  - **The arms sit under one band.** The branch's node carries `band: true`
    and room above its arms; the hook draws one band spanning every arm,
    with a small fork mark at its left, from the boxes the layout placed.
    The band and the mark are drawn inside the branch's own box, so a click
    on either is a click on the branch.
  - **The arms rejoin at its bottom edge.** The edge from a branch to the
    step after it carries `kind: "rejoin"`, and the hook draws it with a
    join dot where it leaves the branch. A branch that is the last step of
    the document's own flow rejoins into the document's end (see "The
    end"); a branch that ends a nested flow needs none, since the flow it
    ends is itself joined to what follows it.
  - **The band carries a caption.** The branch's node carries `caption`,
    `caption/1` of its type (see "Captions"), and `caption_width`, the
    room the caption and the fork mark need; the hook writes the caption
    inside the band, after the fork mark, and never draws the band
    narrower than that room.

  ## The start

  A document starts when its host starts an execution of it, and the map
  says where that execution begins the way a state chart does: one filled
  dot, the initial mark, carrying the word Start, and one edge from it into
  the first step of the document's own flow. The dot is a node of
  `kind: "start"`, keyed `<root id>/start`, and the graph's first node,
  ahead of the root's box rather than inside it: the layout puts it above
  that box, so the dot and its caption come first in reading order, above
  the root's title and every box under it. The word is the dot's one ELK
  label, which the node asks the layout to place outside it, on its
  right and level with it, so the layout leaves the word its room and the
  edge still leaves the dot itself; an end mark carries End the same way.
  Its edge is the graph's own, carries
  `kind: "start"` and one ELK label, `start_text/0`, so the layout leaves
  the caption its room. The caption names who starts the document, "Starts
  when the system is told to", and reads the same on every document: what
  the document listens for while it runs is the description region's to
  say, not the edge's.

  A root whose flow is not drawn inside it has no first step there, so its
  edge goes into the root's box itself. Like the end marks, the dot is not
  a block: it is in no outline, selects nothing and arms no insert.

  ## The end

  Where the document finishes is drawn the way a state chart draws it too:
  a final mark, a dot inside a ring, at every end of the document's own
  flow, one per way it finishes, with the outcome named on the edge into
  it. The ends are the ones `StatifierBlocks.Describe.outline/3` answers,
  read here off the same view model, and the test beside this module holds
  the two equal for every fixture:

  | End | Where it comes from | Mark | Edge into it |
  |---|---|---|---|
  | `done` | the `:exit` edge from the last step of the root's flow into the root's exit | a solid ring | from that step, captioned `done` |
  | `abandon` | an `abandon` interrupt rule of a group in tail position - that last step, or the last step of a flow it runs, and so on down - which leaves the group with nothing after it | a dashed ring | from each such group, dashed, captioned `abandon` |

  The root's last step is in tail position, and so is the last step of the
  body of a sequence or a group in tail position, or of any arm of a
  branch in tail position: the steps the outline's `:exit` edges chain
  from, container by container, into the root's exit. However many such
  groups abandon, the document has one `abandon` end, and each of them
  has its own edge into it.

  Each mark is a node of `kind: "end"` carrying its `outcome`, keyed
  `<root id>/end/<outcome>`, drawn right after the last step, and carrying
  the word End as its one ELK label, whichever way it finishes: the
  outcome stays on the edge into it, not on the mark. Its edge
  carries the same `outcome` and one ELK label, the outcome's name, so the
  layout leaves the caption its room. The edge out of a branch stays a
  rejoin (see "The Branch"); any other edge into a mark is of
  `kind: "end"`. `done` is written here rather than read from the palette:
  it is the outcome every block type declaring no outcomes of its own has,
  the one a root that runs its steps finishes with, and the test holds it
  equal to the outline's own outcome for every fixture's root.

  Only the document's own flow ends. A step that is last in a nested flow
  - a Send at the foot of an arm or of a group's body - hands back to the
  block around it, which goes on, so nothing is drawn after it and it does
  not read as an end. A root whose flow is not drawn inside it, or that has
  no step yet, draws no end. Like the start dot, an end mark is not a
  block: it is in no outline, selects nothing and arms no insert.

  ## The Group

  A group's body is what it is for, and its interrupt rules watch that
  body from beside it, so the map draws the body first and larger.

  - **The body is a pane.** A `core.group` or `core.resumable_group`
    draws its body slot as a slot node with `style: "body"`, first among
    its children, rather than holding the body's blocks directly. The pane
    is held wider than the rules column and at least as tall, at the same
    per-character estimate as every other size here, so the body is the
    larger of the two whatever the rules say.
  - **The rules are a side column.** The interrupt rules' slot node is
    laid out on its own, in one column, rules top to bottom in rail order,
    and ELK places it beside the pane. It is laid out apart from the rest
    of the graph (`hierarchyHandling: SEPARATE_CHILDREN`) because nothing
    joins a rule to anything ELK sees: the interrupt edges are the hook's
    (below), so no edge crosses into the column. It is laid out left to
    right, where rules nothing joins share one layer, and a layer runs top
    to bottom. Its minimum size is written width first, the documented
    way round: a layout of its own is not transposed (see "Sizes").
  - **The column carries a caption.** The rules' slot node carries
    `caption`, the words "Rules: watch the steps while they run", which
    the hook draws under the column's label, and `explanation_lines`,
    `caption/1` of the group's type (see "Captions") wrapped to lines,
    which the hook draws under that, one line each.

  ## Captions

  A structural container the map draws apart says what its type does: a
  branch on its band, a group on its rules column, under the column's
  label and its caption. Nothing else carries one, and a leaf never does.
  The words are the type's own: `caption/1` is the first sentence of
  `StatifierBlocks.BlockType.explain/1`, the paragraph the package's
  optional `explain/0` callback answers, and the description region shows
  the whole paragraph. The sentence is whole: never cut, never ended in
  "...". A branch's band carries it as one line and is held wide enough
  for it; a group's rules column carries it as `explanation_lines`, the
  sentence wrapped to lines no wider than a box's (a word longer than a
  line keeps a line of its own), the way the key carries a mark's `line`
  as its `lines`, and the column is held wide and tall enough for every
  one of them.

  ## Interrupt edges

  A group's interrupt rules are not joined to each other, but each one does
  lead somewhere: an `abandon` rule leaves the group by its exit and a
  `resume` rule goes back to the head of its body. The group's node carries
  those as `interrupts`, one per rule, in rail order, and the hook draws
  each one dashed from the rule's box to where it leads; the head of the
  body is the first node drawn in the body's pane. They are handed to
  the hook beside the graph's `edges`, not among them, and drawn after the
  layout from the boxes it placed, so an interrupt edge never moves a box.
  They are the edges `StatifierBlocks.Describe.outline/3` answers with
  `kind: :interrupt`, read here off the same view model - a rule's
  `outcome`, on the `interrupts` rail of a `core.group` or a
  `core.resumable_group` - because the map is built from the view model
  alone; the test beside this module holds the two equal for every fixture.

  ## Timer edges

  A send with a delay arms an event that arrives later, and what it arms
  is the interrupt rule or the hourglass step that hears it. The graph's root
  carries those as `timers`, one per delayed send and rule or await naming
  its event, sends in reading order and each send's targets in reading
  order, each with its `event` and its `delay` as the send's config holds
  it; the hook draws each one dotted from the send's box to the rule's or
  the await's, labelled with the delay. Like the interrupt edges they are
  handed to the hook beside the graph's `edges`, not among them, and drawn
  after the layout, so a timer edge never moves a box. They are the edges
  `StatifierBlocks.Describe.outline/3` answers with `kind: :timer`, read
  here off the same view model - only blocks the palette resolved, and
  nothing on a drafts shelf - and the tests beside this module hold the two
  equal for every fixture and for a delayed send that is the document's
  root, from which neither draws one. A timer edge is not a transition: it
  says which block hears the event a send arms, so it is dotted where an
  interrupt edge is dashed.

  ## Timer marks

  Blocks wait on a clock in different ways, and a box says which with a
  small mark at its top right: a `core.await` carries the wait mark (it
  waits, in its own step, for an event or its timeout), a `core.wait`
  carries the clock mark (time passes: it holds its step for its
  duration, which it always has, since the duration is required), and a
  `core.send` with a delay carries the clock mark too (the event it arms
  fires later, after the step has moved on). The clock says time passes;
  the hourglass says a step waits for an event. The clock on a wait is a
  mark only: a wait hears no timer edge. A delay counts when
  `StatifierBlocks.Core.Duration.duration?/1` accepts it, the test the
  send's own sentence and the timer edges use; a send with no delay
  carries neither mark. A mark is drawn inside its block's box, so a click
  on it is a click on the box.

  ## The happy path runs straight

  A reader follows the steps that run when nothing goes wrong, so those
  are drawn on one vertical line, and what can interrupt them sits to the
  side. Inside a group's pane the body's steps already share a line: ELK
  centres a chain of steps on one another, against the pane's left edge.
  What would bend the line is the group itself, which is wider than its
  body by the rules column: an edge attached to the middle of the group
  lands between the body and the column, and the steps before and after
  the group follow it there.

  So a group attaches its edges where its body's line is. Its node
  carries two `ports`, one on its top side for the edge in and one on its
  bottom side for the edge out, at a fixed x (`portConstraints:
  FIXED_POS`): the group's and the pane's left padding plus half the
  widest step in the body. The steps before and after the group line up
  under that point, and the rules column and its dashed abandon edges
  stand to the right of it. The edges themselves still join block to
  block: the hook moves an edge onto its node's port only for the layout,
  and hands the edge back with its own ends.

  The line is placed by estimate, from the widths this module gives its
  leaves, so a group puts out its ports only when every step in its body
  is a leaf or an empty marker. A body that holds a container has a width
  only ELK can find, so this module gives that group no ports and places
  nothing: the hook lays such a graph out twice. The first layout says
  where the body's steps stand; the hook then puts the group's two ports
  at the centre of the widest of them, in the same shape as the ones
  above, and lays the graph out again. A graph whose every group carries
  its ports is laid out once. The first layout is already a whole
  drawing, its line bent at the group, so when the second layout fails
  the hook draws the first rather than the error pane.

  ## The drafts shelf

  A drafts shelf holds steps an author has put down but not wired into the
  flow, so the path is read without it. Its block's node carries `drafts`,
  `%{"count" => count, "label" => label}`: `count` is how many steps sit on
  the shelf, the blocks in its slot, and `label` is the row its drawer
  reads, "Drafts: 2 steps not wired in" ("1 step" for one). The node stays
  where the outline visits it, so `nodes/1` is unchanged; the hook takes it
  out of the drawing before the layout and lays it out on its own, so the
  path is laid out as though the shelf were not there.

  The hook draws the shelf in a drawer under the drawing and outside it: a
  native disclosure element whose row reads `label`, holding the shelf as
  its own drawing. On a page that cannot edit the drawer is closed, and a
  click on its row opens it in place; on a page that can edit it is drawn
  open, in the same place. Whether it is open lives in that element, not in
  the hook. The shelf's entry in the key (below) is the same row.

  ## The key

  The graph's root carries `legend`, the key the hook draws beside the
  drawing: one entry per kind of mark the drawing uses, each
  `%{"mark" => mark, "line" => line, "lines" => lines}`, in a fixed
  order, and none for a mark the drawing does not use. `line` is what the
  mark means, in words, and `lines` is the same words wrapped to a line
  somewhat wider than a box's, which is what the hook writes beside the
  mark's glyph.

  | Mark | Drawn where the graph has |
  |---|---|
  | `start` | the start dot, which every graph has |
  | `end` | a `done` end mark |
  | `end-abandon` | an `abandon` end mark |
  | `arrow` | a solid edge: the start edge, a connector, or an edge into the `done` end |
  | `fork` | a branch's band, with its fork mark |
  | `join` | a `rejoin` edge, with its join dot |
  | `interrupt` | a dashed edge: an interrupt edge, or an edge into the `abandon` end |
  | `wait` | a block carrying the `wait` mark |
  | `clock` | a block carrying the `clock` mark |
  | `timer` | a timer edge |
  | `drafts` | a drafts shelf, its line the drawer's own row, `label` |

  The key is data in the graph, read off the graph itself, so the Map stays
  pure and the key cannot name a mark the drawing lacks. The map region is
  hidden from assistive technology, so the same lines reach the description
  region as text: `StatifierBlocks.Map.Info.idle/4` carries them as its
  "Legend" fact.

  ## Order is semantic, so it is forced

  A branch evaluates its arms in slot order and a sequence runs its steps
  in order, so a layout that swapped two arms to save a crossing would draw
  a different chart. Two ELK options keep the model order, and the two are
  set differently on purpose:

  - `crossingMinimization.forceNodeModelOrder` is set on EVERY container,
    because under `hierarchyHandling: INCLUDE_CHILDREN` a value set on the
    root does not reach a nested graph;
  - `considerModelOrder.strategy` is set on the ROOT ONLY. The root value
    is all the order this map needs, and a per-container value has been
    seen to throw inside elkjs on a differently shaped graph, so it is kept
    off the containers rather than found out again.

  The test beside this module pins both.

  A group's rules column is laid out on its own, and there
  `forceNodeModelOrder` alone does not hold the order: rules that nothing
  joins are each a connected component, and ELK packs separate components
  by size, not in model order. The column keeps its components together
  (`separateConnectedComponents: false`), so its rules share one layer and
  that layer keeps model order.

  ## Sizes

  Text is measured by estimate, a fixed width per character, rather than
  by the browser: the graph is built on the server, and a node sized after
  the page measured it would be a layout that depends on which fonts
  loaded. The estimate errs wide, and no box is narrower than the widest
  line it carries, its title included: a single word longer than a line
  widens its box rather than running out of it, and a container is held
  at least that wide whatever its children need.
  """

  alias StatifierBlocks.BlockType
  alias StatifierBlocks.Core.Duration
  alias StatifierBlocks.Map.Phrasing
  alias StatifierBlocks.Palette
  alias StatifierBlocks.Shelf
  alias StatifierBlocks.ViewModel
  alias StatifierBlocks.ViewModel.Node
  alias StatifierBlocks.ViewModel.Slot

  @char_width 7
  # The indent of a wrapped arm entry's later lines; see `arm_entry/2`.
  @no_break_space <<0xA0::utf8>>
  @line_height 16
  @leaf_min_width 150
  @leaf_max_width 260
  @leaf_padding 24
  @header_base 12
  @empty_text "Nothing here yet"
  @mark_room 22
  @group_types ["core.group", "core.resumable_group"]
  @branch_type "core.branch"
  @sequence_type "core.sequence"
  @captioned_types [@branch_type | @group_types]
  @timer_targets ["core.on_event", "core.await"]
  @band_room 24
  @done "done"
  @abandon "abandon"
  @end_size 20
  @start_text "Starts when the system is told to"
  @start_word "Start"
  @end_word "End"
  @start_size 14
  # What a group's rules column says under its label; see "The Group".
  @rules_caption "Rules: watch the steps while they run"
  @rule_spacing 24
  @body_lead 48
  @fork_room 26
  @pad 12
  # The characters a line of the key holds: wider than a box's, so the key
  # stays short beside the drawing.
  @key_line 46

  # The key's entries, in the order the hook draws them: each mark and what
  # it means; see the moduledoc's "The key".
  @legend [
    {"start",
     "The filled dot marked Start is where the document starts, its arrow captioned " <>
       "with what starts it"},
    {"end",
     "A dot inside a solid ring marked End is where the document finishes when its " <>
       "last step finishes, the outcome named on the arrow into it"},
    {"end-abandon",
     "A dashed ring, reached by a dashed arrow, is where the document finishes when " <>
       "an interrupt rule abandons its last step"},
    {"arrow", "An arrow runs from a step to the one after it"},
    {"fork", "A band with a fork mark stands over a branch's arms"},
    {"join",
     "After whichever arm runs, the arms come back together at a dot, where a heavier " <>
       "arrow leads on"},
    {"interrupt",
     "A dashed arrow runs from an interrupt rule to where it takes its group: out of " <>
       "it, or back to the head of its body"},
    {"wait", "An hourglass marks a step that waits for an event"},
    {"clock", "A clock marks a timed wait or a message sent after a delay"},
    {"timer",
     "A dotted arrow, labelled with the delay, runs from a message sent after a delay " <>
       "to the interrupt rule or the hourglass step that hears it"}
  ]

  @force_model_order "org.eclipse.elk.layered.crossingMinimization.forceNodeModelOrder"
  @consider_model_order "org.eclipse.elk.layered.considerModelOrder.strategy"
  @layer_constraint "org.eclipse.elk.layered.layering.layerConstraint"
  @port_constraints "org.eclipse.elk.portConstraints"
  @port_side "org.eclipse.elk.port.side"
  @node_labels "org.eclipse.elk.nodeLabels.placement"
  @beside "OUTSIDE V_CENTER H_RIGHT"

  @root_options %{
    "org.eclipse.elk.algorithm" => "layered",
    "org.eclipse.elk.direction" => "DOWN",
    "org.eclipse.elk.hierarchyHandling" => "INCLUDE_CHILDREN",
    "org.eclipse.elk.spacing.nodeNode" => "24",
    "org.eclipse.elk.layered.spacing.nodeNodeBetweenLayers" => "28",
    "org.eclipse.elk.edgeRouting" => "ORTHOGONAL",
    @force_model_order => "true",
    @consider_model_order => "NODES_AND_EDGES"
  }

  @typedoc """
  One graph node, in elkjs's JSON shape plus the fields the hook draws
  from: `kind` (with `outcome`, all the start dot and an end mark carry
  beside the ELK `labels` holding their word and the `layoutOptions`
  placing it),
  `title` and `lines`, on a slot `style`, on a timer block
  `mark`, on a group with interrupt rules `interrupts`, on a branch `band`,
  `caption` and `caption_width`, on a group's rules column `caption` and
  `explanation_lines`, on
  a group whose body is all leaves the `ports` its edges attach to, on a
  drafts shelf `drafts`, and on the selected block `selected`.
  """
  @type graph_node :: %{required(String.t()) => term()}

  @typedoc """
  The whole graph: the ELK root, with the start dot and the document's root
  block as its two children, the start edge as its one edge, `timers`, the
  timer edges the hook draws after the layout, and `legend`, the key the
  hook draws beside the drawing.
  """
  @type t :: %{required(String.t()) => term()}

  @typedoc "The options `graph/2` takes; see the moduledoc's \"Its input\"."
  @type option ::
          {:selected, String.t() | nil} | {:phrase, (String.t() -> String.t() | nil)}

  @doc """
  The graph for `view_model`, ready to be JSON-encoded onto the hook.

  The root carries the layout options every container inherits and the two
  it alone may carry; see the moduledoc on why `considerModelOrder` is one
  of them. `opts` are the host's selection and its words for event names;
  see the moduledoc's "Its input".
  """
  @spec graph(ViewModel.t(), [option()]) :: t()
  def graph(%ViewModel{root: %Node{} = root} = view_model, opts \\ []) when is_list(opts) do
    opts = Keyword.validate!(opts, selected: nil, phrase: &Phrasing.none/1)
    phrase = Keyword.fetch!(opts, :phrase)

    %{
      "id" => "plan-map",
      "layoutOptions" => @root_options,
      "children" => [root |> block(phrase) |> Map.put("gap", false) |> put_ends(root)],
      "edges" => []
    }
    |> put_start(root)
    |> put_timers(view_model)
    |> put_legend()
    |> put_selected(Keyword.fetch!(opts, :selected))
  end

  @doc """
  The block ids in `graph`, in the order a pre-order walk of it meets them.

  The map's claim to be the document is that this list is the outline's:
  every block exactly once, in reading order. Slot nodes and empty markers
  are not blocks and are not in it.
  """
  @spec nodes(t() | graph_node()) :: [String.t()]
  def nodes(%{"children" => children} = node) do
    own = if node["kind"] == "block", do: [node["id"]], else: []
    own ++ Enum.flat_map(children, &nodes/1)
  end

  def nodes(%{"kind" => "block", "id" => id}), do: [id]
  def nodes(%{}), do: []

  @doc """
  Every interrupt edge in `graph`, groups in the order a pre-order walk
  meets them and each group's rules in rail order, as
  `%{"from" => rule, "group" => group, "to" => "exit" | "body"}`.
  """
  @spec interrupts(t() | graph_node()) :: [%{String.t() => String.t()}]
  def interrupts(%{} = node) do
    own =
      for %{"sources" => [from], "targets" => [group], "to" => to} <-
            Map.get(node, "interrupts", []),
          do: %{"from" => from, "group" => group, "to" => to}

    own ++ Enum.flat_map(Map.get(node, "children", []), &interrupts/1)
  end

  @doc """
  Every timer edge in `graph`, in the order it is drawn, as
  `%{"from" => send, "to" => rule_or_await, "event" => event, "delay" => delay}`.
  """
  @spec timers(t()) :: [%{String.t() => String.t()}]
  def timers(%{} = graph) do
    for %{"sources" => [from], "targets" => [to], "event" => event, "delay" => delay} <-
          Map.get(graph, "timers", []),
        do: %{"from" => from, "to" => to, "event" => event, "delay" => delay}
  end

  @doc """
  The caption the map draws for a block of `type`, or `nil`: the whole
  first sentence of the type's explanation for a branch and the two group
  types, never cut; see the moduledoc's "Captions".
  """
  @spec caption(String.t()) :: String.t() | nil
  def caption(type) when type in @captioned_types do
    with {:ok, ref} <- Palette.fetch(Palette.core(), type),
         text when is_binary(text) <- BlockType.explain(ref) do
      first_sentence(text)
    else
      _unexplained -> nil
    end
  end

  def caption(type) when is_binary(type), do: nil

  @doc "The text an empty slot's marker carries."
  @spec empty_text() :: String.t()
  def empty_text, do: @empty_text

  @doc """
  What starts a document, in the words the map's start edge carries and the
  description region says: the one place the sentence is written.
  """
  @spec start_text() :: String.t()
  def start_text, do: @start_text

  # ----------------------------------------------------------------- the key

  # The key: one entry per kind of mark `graph` draws, in the key's own
  # order; see the moduledoc's "The key".
  @spec put_legend(t()) :: t()
  defp put_legend(graph) do
    used = graph |> drawn_marks() |> MapSet.new()

    # The drafts shelf's entry is its drawer's own row, after every mark:
    # one drawer, the first shelf's, as the hook draws one.
    shelves = for %{"drafts" => %{"label" => label}} <- walk(graph), do: {"drafts", label}
    drafts = Enum.take(shelves, 1)

    legend =
      for {mark, line} <- Enum.filter(@legend, &MapSet.member?(used, elem(&1, 0))) ++ drafts,
          do: %{"mark" => mark, "line" => line, "lines" => wrap(line, "", @key_line)}

    Map.put(graph, "legend", legend)
  end

  # `graph_node` and every node under it, parents first.
  @spec walk(graph_node()) :: [graph_node()]
  defp walk(%{} = graph_node),
    do: [graph_node | Enum.flat_map(Map.get(graph_node, "children", []), &walk/1)]

  # Every kind of mark a graph node, its edges and everything under it
  # draw, with repeats; the graph's timer edges are its root's.
  @spec drawn_marks(graph_node()) :: [String.t()]
  defp drawn_marks(%{} = graph_node) do
    own =
      node_marks(graph_node) ++
        Enum.flat_map(Map.get(graph_node, "edges", []), &edge_marks/1) ++
        if(Map.get(graph_node, "interrupts", []) == [], do: [], else: ["interrupt"]) ++
        if(Map.get(graph_node, "timers", []) == [], do: [], else: ["timer"])

    own ++ Enum.flat_map(Map.get(graph_node, "children", []), &drawn_marks/1)
  end

  @spec node_marks(graph_node()) :: [String.t()]
  defp node_marks(%{"kind" => "start"}), do: ["start"]
  defp node_marks(%{"kind" => "end", "outcome" => @abandon}), do: ["end-abandon"]
  defp node_marks(%{"kind" => "end"}), do: ["end"]

  defp node_marks(%{} = graph_node) do
    Enum.reject([graph_node["mark"], if(graph_node["band"] == true, do: "fork")], &is_nil/1)
  end

  # A rejoin is drawn with its join dot, an edge into the abandon end
  # dashed, and every other edge solid.
  @spec edge_marks(map()) :: [String.t()]
  defp edge_marks(%{"kind" => "rejoin"}), do: ["join"]
  defp edge_marks(%{"kind" => "end", "outcome" => @abandon}), do: ["interrupt"]
  defp edge_marks(%{}), do: ["arrow"]

  # --------------------------------------------------------------- selection

  # The host's selection marks the one block node it names, and nothing
  # else; see the moduledoc's "Its input". Slot nodes, empty markers, the
  # start dot and the end marks are not blocks and are never marked.
  @spec put_selected(graph_node(), String.t() | nil) :: graph_node()
  defp put_selected(graph_node, nil), do: graph_node

  defp put_selected(%{} = graph_node, selected) when is_binary(selected) do
    graph_node =
      if graph_node["kind"] == "block" and graph_node["id"] == selected,
        do: Map.put(graph_node, "selected", true),
        else: graph_node

    case graph_node do
      %{"children" => children} ->
        Map.put(graph_node, "children", Enum.map(children, &put_selected(&1, selected)))

      %{} ->
        graph_node
    end
  end

  # ------------------------------------------------------------------ blocks

  @spec block(Node.t(), Phrasing.phrase()) :: graph_node()
  defp block(%Node{slots: []} = node, phrase) do
    lines = node |> Phrasing.sentence(phrase) |> under(ViewModel.title(node))
    title = ViewModel.title(node)

    %{
      "id" => node.block_id,
      "kind" => "block",
      "gap" => true,
      "title" => title,
      "lines" => lines,
      "width" => leaf_width([title | lines]),
      "height" => @header_base + (length(lines) + 1) * @line_height
    }
    |> put_mark(mark(node), title, lines)
  end

  defp block(%Node{} = node, phrase) do
    title = ViewModel.title(node)

    {lines, extra, least} =
      if branch?(node),
        do: {arm_lines(node), @band_room, band_width(node)},
        else: {node |> header(phrase) |> under(title), 0, 0}

    {children, edges} =
      node
      |> drawn_slots()
      |> Enum.map(&slot_part(node, &1, phrase))
      |> Enum.unzip()

    %{
      "id" => node.block_id,
      "kind" => "block",
      "gap" => true,
      "title" => title,
      "lines" => lines,
      "layoutOptions" =>
        container_options([title | lines], lines, extra, least: least + 2 * @pad),
      "children" => List.flatten(children),
      "edges" => List.flatten(edges)
    }
    |> put_band(node)
    |> put_interrupts(node)
    |> put_ports(node)
    |> put_drafts(node)
  end

  # ------------------------------------------------------------ the drafts

  # The drafts shelf carries its drawer's row: how many steps are on it,
  # and the words the row reads; see the moduledoc's "The drafts shelf".
  @spec put_drafts(graph_node(), Node.t()) :: graph_node()
  defp put_drafts(graph_node, %Node{slots: slots} = node) do
    if ViewModel.shelf?(node) do
      count = slots |> Enum.map(&length(&1.children)) |> Enum.sum()
      Map.put(graph_node, "drafts", %{"count" => count, "label" => drafts_label(count)})
    else
      graph_node
    end
  end

  # The drawer's row, in the words ruled for it; one step is a step.
  @spec drafts_label(non_neg_integer()) :: String.t()
  defp drafts_label(1), do: "Drafts: 1 step not wired in"
  defp drafts_label(count), do: "Drafts: #{count} steps not wired in"

  # ------------------------------------------------------------ the Branch

  @spec branch?(Node.t()) :: boolean()
  defp branch?(%Node{type: type}), do: type == @branch_type

  # A branch's header: the package's "one of", then one numbered entry per
  # arm, in slot order, each the arm's label and its condition as authored;
  # see the moduledoc's "The Branch". An entry wider than a line wraps onto
  # the next, indented under its label (see `arm_entry/2`).
  @spec arm_lines(Node.t()) :: [String.t()]
  defp arm_lines(%Node{} = node) do
    arms =
      node
      |> ViewModel.body_slots()
      |> Enum.with_index(1)
      |> Enum.flat_map(fn {slot, n} -> arm_entry(slot, n) end)

    case ViewModel.fan_label(node) do
      nil -> arms
      label -> ["#{String.capitalize(label)}, in order:" | arms]
    end
  end

  # One arm's entry: its number, then its label and condition, wrapped.
  # Every line after the first is indented by the number's width, so it
  # stands under the label and a wrapped condition does not read as an
  # entry of its own. The indent is no-break spaces: the hook draws each
  # line as its own SVG text, which would fold plain leading spaces away.
  @spec arm_entry(Slot.t(), pos_integer()) :: [String.t()]
  defp arm_entry(%Slot{} = slot, n) do
    number = "#{n}. "
    indent = String.duplicate(@no_break_space, String.length(number))
    wrap(number <> slot_header(slot), indent)
  end

  @spec put_band(graph_node(), Node.t()) :: graph_node()
  defp put_band(graph_node, %Node{} = node) do
    if branch?(node),
      do:
        Map.merge(graph_node, %{
          "band" => true,
          "caption" => caption(node.type),
          "caption_width" => band_width(node)
        }),
      else: graph_node
  end

  # The least width a branch's band is drawn at: its fork mark and its
  # caption, at the map's estimate.
  @spec band_width(Node.t()) :: non_neg_integer()
  defp band_width(%Node{} = node) do
    case caption(node.type) do
      nil -> 0
      caption -> @fork_room + text_width([caption])
    end
  end

  # ------------------------------------------------------------- the Group

  @spec group?(Node.t()) :: boolean()
  defp group?(%Node{type: type}), do: type in @group_types

  # The rules column of a group, as `{width, height}` at the map's estimate:
  # the slot node `slot/2` builds for it, its rules stacked one above the
  # next. The body's pane is held larger than this; see the moduledoc's
  # "The Group".
  @spec column_size(Node.t(), Phrasing.phrase()) :: {pos_integer(), pos_integer()}
  defp column_size(%Node{block_id: block_id, slots: slots} = node, phrase) do
    case Enum.find(slots, &ViewModel.rail?/1) do
      nil ->
        {0, 0}

      %Slot{} = rail ->
        lines = column_lines(node, rail)

        parts =
          case rail.children do
            [] -> [empty(block_id, rail.name)]
            _blocks -> slot_children(rail, phrase)
          end

        top = header_height(lines)
        heights = Enum.map(parts, &part_height/1)
        widths = Enum.map(parts, &part_width/1)
        height = top + Enum.sum(heights) + @rule_spacing * (length(parts) - 1) + @pad
        width = Enum.max([Enum.max(widths) + 2 * @pad, text_width(lines)])
        {width, height}
    end
  end

  # What a rules column says under its title: its label, then its caption,
  # then the group's sentence on lines of its own.
  @spec column_lines(Node.t(), Slot.t()) :: [String.t()]
  defp column_lines(%Node{} = node, %Slot{} = slot) do
    case caption(node.type) do
      nil -> wrap(slot_header(slot))
      sentence -> wrap(slot_header(slot)) ++ [@rules_caption | wrap(sentence)]
    end
  end

  # A rule's size at the estimate. A rule is an interrupt handler, a leaf
  # in the core vocabulary, so it carries its own; a host handler drawn as a
  # container counts at a leaf's least, and the layout tests hold the pane
  # larger for every fixture.
  @spec part_width(graph_node()) :: pos_integer()
  defp part_width(part), do: Map.get(part, "width", @leaf_min_width)

  @spec part_height(graph_node()) :: pos_integer()
  defp part_height(part), do: Map.get(part, "height", @header_base + 2 * @line_height)

  # ---------------------------------------------------------------- the end

  # The document's ends, after the last step of the root's own flow: one
  # final mark per way the document finishes, each joined to that step by
  # an edge captioned with its outcome; see the moduledoc's "The end". A
  # root whose flow is not drawn inside it, or is empty, is left as it is.
  @spec put_ends(graph_node(), Node.t()) :: graph_node()
  defp put_ends(%{"children" => children} = graph_node, %Node{block_id: root_id} = root) do
    with [%Slot{} = body] <- ViewModel.body_slots(root),
         true <- inline?(root, body),
         %Node{block_id: last} = step <- List.last(ViewModel.flow_children(body)) do
      done = if branch?(step), do: "rejoin", else: "end"
      abandons = for group <- abandons(step), do: {group, @abandon, "end"}
      outcomes = if abandons == [], do: [@done], else: [@done, @abandon]
      marks = for outcome <- outcomes, do: end_mark(root_id, outcome)

      edges =
        for {from, outcome, kind} <- [{last, @done, done} | abandons],
            do: end_edge(from, root_id, outcome, kind)

      {before, [drawn | rest]} = Enum.split_while(children, &(&1["id"] != last))

      graph_node
      |> Map.put("children", before ++ [drawn | marks] ++ rest)
      |> Map.update!("edges", &(&1 ++ edges))
    else
      _no_end -> graph_node
    end
  end

  defp put_ends(graph_node, %Node{}), do: graph_node

  # The groups in tail position whose rules abandon them, in reading order:
  # the root's last step, the last step of each flow it runs, and so on
  # down. Abandoning such a group leaves it with nothing after it in any
  # flow around it, so the document finishes. One end, however many groups
  # and rules abandon; a group whose rules only resume has none.
  @spec abandons(Node.t()) :: [String.t()]
  defp abandons(%Node{} = step) do
    for %Node{block_id: id} = node <- tail(step), abandoned?(node), do: id
  end

  # `step` and every block in tail position under it: the last step of each
  # flow it runs - a sequence's or a group's body, each of a branch's arms -
  # and the same under those, the way `StatifierBlocks.Describe.outline/3`
  # chains `:exit` edges into a container's exit.
  @spec tail(Node.t()) :: [Node.t()]
  defp tail(%Node{} = step) do
    lasts =
      for %Slot{} = slot <- tail_slots(step),
          %Node{} = last <- [List.last(ViewModel.flow_children(slot))],
          do: last

    [step | Enum.flat_map(lasts, &tail/1)]
  end

  @spec tail_slots(Node.t()) :: [Slot.t()]
  defp tail_slots(%Node{type: type} = node) when type in [@sequence_type, @branch_type],
    do: ViewModel.body_slots(node)

  defp tail_slots(%Node{slots: slots} = node) do
    if group?(node), do: Enum.filter(slots, &(&1.name == "body")), else: []
  end

  @spec abandoned?(Node.t()) :: boolean()
  defp abandoned?(%Node{slots: slots} = node) do
    group?(node) and
      Enum.any?(
        for(%Slot{name: "interrupts"} = slot <- slots, do: ViewModel.flow_children(slot)),
        fn rules -> Enum.any?(rules, &(leads_to(&1.outcome) == "exit")) end
      )
  end

  @spec end_mark(String.t(), String.t()) :: graph_node()
  defp end_mark(root_id, outcome) do
    id = "#{root_id}/end/#{outcome}"

    Map.merge(
      %{
        "id" => id,
        "kind" => "end",
        "outcome" => outcome,
        "width" => @end_size,
        "height" => @end_size
      },
      word(id, @end_word)
    )
  end

  @spec end_edge(String.t(), String.t(), String.t(), String.t()) :: map()
  defp end_edge(from, root_id, outcome, kind) do
    to = "#{root_id}/end/#{outcome}"
    id = "#{from}->#{to}"

    %{
      "id" => id,
      "sources" => [from],
      "targets" => [to],
      "kind" => kind,
      "outcome" => outcome,
      "labels" => [
        %{
          "id" => "#{id}/caption",
          "text" => outcome,
          "width" => text_width([outcome]),
          "height" => @line_height
        }
      ]
    }
  end

  # ------------------------------------------------------------- the start

  # The start dot and its edge; see the moduledoc's "The start". The dot
  # goes first in the graph, before the root's box, so the layout puts it
  # above that box and its title; the edge, the graph's own, goes into the
  # first step of the root's own flow, or into the root's box for a root
  # whose flow is not drawn inside it.
  @spec put_start(t(), Node.t()) :: t()
  defp put_start(%{"children" => [drawn]} = graph, %Node{block_id: root_id} = root) do
    id = "#{root_id}/start"

    Map.merge(graph, %{
      "children" => [start_mark(id), drawn],
      "edges" => [start_edge(id, start_target(drawn, root))]
    })
  end

  # Where the start edge goes: the first step of the root's own flow, or the
  # empty marker standing for it; the root's box when the flow is not drawn
  # inside it.
  @spec start_target(graph_node(), Node.t()) :: String.t()
  defp start_target(drawn, %Node{block_id: root_id} = root) do
    with [%Slot{} = body] <- ViewModel.body_slots(root),
         true <- inline?(root, body),
         [first | _rest] <- drawn["children"] do
      case ViewModel.flow_children(body) do
        [%Node{block_id: step} | _rest] -> step
        [] -> unflowed_target(first, root_id)
      end
    else
      _not_inline -> root_id
    end
  end

  # A body with no step in its flow: its empty marker, or, when it holds
  # only a drafts shelf, the root's box, since the shelf is drawn apart
  # from the path.
  @spec unflowed_target(graph_node(), String.t()) :: String.t()
  defp unflowed_target(%{"drafts" => _drafts}, root_id), do: root_id
  defp unflowed_target(%{"id" => id}, _root_id), do: id

  @spec start_mark(String.t()) :: graph_node()
  defp start_mark(id),
    do:
      Map.merge(
        %{"id" => id, "kind" => "start", "width" => @start_size, "height" => @start_size},
        word(id, @start_word)
      )

  # The word a start dot or an end mark carries: its one ELK label, sized
  # at the estimate and placed outside the mark, on its right and level
  # with it, so the layout leaves the word its room beside the mark and an
  # edge still meets the mark itself; see the moduledoc's "The start".
  @spec word(String.t(), String.t()) :: graph_node()
  defp word(id, text),
    do: %{
      "labels" => [
        %{
          "id" => "#{id}/word",
          "text" => text,
          "width" => text_width([text]),
          "height" => @line_height
        }
      ],
      "layoutOptions" => %{@node_labels => @beside}
    }

  @spec start_edge(String.t(), String.t()) :: map()
  defp start_edge(from, to) do
    %{
      "id" => "#{from}->#{to}",
      "sources" => [from],
      "targets" => [to],
      "kind" => "start",
      "labels" => [
        %{
          "id" => "#{from}/caption",
          "text" => @start_text,
          "width" => text_width([@start_text]),
          "height" => @line_height
        }
      ]
    }
  end

  # ------------------------------------------------------------ timer marks

  # The mark a leaf carries, and the room for it beside the title: the mark
  # sits at the box's top right, level with the title, so the title line is
  # the one that has to leave it space.
  @spec put_mark(graph_node(), String.t() | nil, String.t(), [String.t()]) :: graph_node()
  defp put_mark(graph_node, nil, _title, _lines), do: graph_node

  defp put_mark(graph_node, mark, title, lines) do
    width = Enum.max([graph_node["width"], text_width([title]) + @mark_room, leaf_width(lines)])
    Map.merge(graph_node, %{"mark" => mark, "width" => width})
  end

  # See the moduledoc's "Timer marks".
  @spec mark(Node.t()) :: String.t() | nil
  defp mark(%Node{type: "core.await"}), do: "wait"
  defp mark(%Node{type: "core.wait"}), do: "clock"
  defp mark(%Node{type: "core.send"} = node), do: if(delayed?(node), do: "clock")
  defp mark(%Node{}), do: nil

  # Whether a send's `delay` is a duration, as its form reads it: the test
  # the send's sentence and `StatifierBlocks.Describe`'s timer edges use.
  @spec delayed?(Node.t()) :: boolean()
  defp delayed?(%Node{} = node), do: node |> field("delay") |> Duration.duration?()

  # A field's value off a block's form, or `nil`.
  @spec field(Node.t(), String.t()) :: term()
  defp field(%Node{form: %{fields: fields}}, key) do
    case Enum.find(fields, &(&1.key == key)) do
      %{value: value} -> value
      nil -> nil
    end
  end

  defp field(%Node{}, _key), do: nil

  # ------------------------------------------------------------ timer edges

  # One timer edge per delayed send and interrupt rule or await naming its
  # event, sends in reading order and then targets; see the moduledoc's
  # "Timer edges". A block the palette cannot resolve, or one on a drafts
  # shelf, takes part in none.
  @spec put_timers(t(), ViewModel.t()) :: t()
  defp put_timers(graph, %ViewModel{} = view_model) do
    blocks = timer_parties(view_model)

    targets =
      for %Node{type: type} = node when type in @timer_targets <- blocks,
          event = event(node),
          do: {node.block_id, event}

    timers =
      for %Node{type: "core.send"} = send <- blocks,
          delayed?(send),
          event = event(send),
          {target, ^event} <- targets,
          do: timer(send, target, event)

    if timers == [], do: graph, else: Map.put(graph, "timers", timers)
  end

  # The blocks that can take part in a timer edge, in reading order:
  # resolved, and neither a drafts shelf nor inside one. The outline is a
  # pre-order walk, so a block is on a shelf exactly when a shelf opened at
  # a lesser depth has not yet been left.
  @spec timer_parties(ViewModel.t()) :: [Node.t()]
  defp timer_parties(%ViewModel{} = view_model) do
    view_model
    |> ViewModel.outline()
    |> Enum.map_reduce(nil, fn {%Node{type: type} = node, depth, _kind}, shelf ->
      shelf = if shelf != nil and depth > shelf, do: shelf, else: nil
      shelf = if shelf == nil and Shelf.shelf_type?(type), do: depth, else: shelf
      {if(shelf == nil and node.status == :ok, do: node), shelf}
    end)
    |> elem(0)
    |> Enum.reject(&is_nil/1)
  end

  # A block's `event`, when it is a non-blank string.
  @spec event(Node.t()) :: String.t() | nil
  defp event(%Node{} = node) do
    case field(node, "event") do
      event when is_binary(event) -> if String.trim(event) == "", do: nil, else: event
      _none -> nil
    end
  end

  @spec timer(Node.t(), String.t(), String.t()) :: map()
  defp timer(%Node{block_id: from} = send, to, event) do
    delay = field(send, "delay")
    id = "#{from}->#{to}/timer"

    %{
      "id" => id,
      "sources" => [from],
      "targets" => [to],
      "kind" => "timer",
      "event" => event,
      "delay" => delay
    }
  end

  # -------------------------------------------------------- interrupt edges

  # One edge per interrupt rule on a group's rail: `abandon` to the group's
  # exit, `resume` to the head of its body, which is the first node drawn
  # in the body's pane, the group's first child. A rule with neither
  # outcome leads nowhere and has no edge, as in `StatifierBlocks.Describe`.
  @spec put_interrupts(graph_node(), Node.t()) :: graph_node()
  defp put_interrupts(graph_node, %Node{type: type, block_id: group, slots: slots})
       when type in @group_types do
    head =
      graph_node["children"]
      |> List.first(%{})
      |> Map.get("children", [])
      |> List.first(%{})
      |> Map.get("id")

    edges =
      for %Slot{name: "interrupts"} = slot <- slots,
          %Node{outcome: outcome, block_id: rule} <- ViewModel.flow_children(slot),
          to = leads_to(outcome),
          to != nil do
        %{
          "id" => "#{rule}->#{group}/#{to}",
          "sources" => [rule],
          "targets" => [group],
          "kind" => "interrupt",
          "to" => to,
          "head" => head
        }
      end

    if edges == [], do: graph_node, else: Map.put(graph_node, "interrupts", edges)
  end

  defp put_interrupts(graph_node, %Node{}), do: graph_node

  # ------------------------------------------------------- the happy path

  # A group's two ports, where its body's steps stand: the group's and the
  # pane's left padding, plus half the widest step. Only a body of leaves
  # and empty markers has widths to read; see the moduledoc's "The happy
  # path runs straight".
  @spec put_ports(graph_node(), Node.t()) :: graph_node()
  defp put_ports(
         %{"id" => id, "children" => [%{"style" => "body", "children" => steps} | _]} =
           graph_node,
         %Node{} = node
       ) do
    widths = for %{"width" => width} <- steps, do: width

    if group?(node) and widths != [] and length(widths) == length(steps) do
      x = 2 * @pad + Enum.max(widths) / 2

      graph_node
      |> Map.update!("layoutOptions", &Map.put(&1, @port_constraints, "FIXED_POS"))
      |> Map.put("ports", [port("#{id}#in", x, "NORTH"), port("#{id}#out", x, "SOUTH")])
    else
      graph_node
    end
  end

  defp put_ports(graph_node, %Node{}), do: graph_node

  @spec port(String.t(), number(), String.t()) :: graph_node()
  defp port(id, x, side),
    do: %{
      "id" => id,
      "x" => x,
      "y" => 0,
      "width" => 0,
      "height" => 0,
      "layoutOptions" => %{@port_side => side}
    }

  @spec leads_to(term()) :: String.t() | nil
  defp leads_to("abandon"), do: "exit"
  defp leads_to("resume"), do: "body"
  defp leads_to(_other), do: nil

  # What one slot adds to its block: the slot's blocks drawn straight into
  # the block when the slot is inlined, or one slot node otherwise.
  @spec slot_part(Node.t(), Slot.t(), Phrasing.phrase()) :: {[graph_node()], [map()]}
  defp slot_part(%Node{} = node, %Slot{} = slot, phrase) do
    cond do
      not inline?(node, slot) -> {[slot(node, slot, phrase)], []}
      slot.children == [] -> {[empty(node.block_id, slot.name)], []}
      true -> {slot_children(slot, phrase), sequence_edges(slot)}
    end
  end

  # The words at the top of a container: its sentence, and for a fan or a
  # parallel the package's own "one of" / "all of", which is the only
  # place the exclusive/concurrent distinction is stated.
  @spec header(Node.t(), Phrasing.phrase()) :: String.t()
  defp header(%Node{} = node, phrase) do
    case ViewModel.fan_label(node) do
      nil -> Phrasing.sentence(node, phrase)
      label -> "#{Phrasing.sentence(node, phrase)} (#{label})"
    end
  end

  # The slots a container draws, in the outline's order: body, then rails,
  # then trays.
  @spec drawn_slots(Node.t()) :: [Slot.t()]
  defp drawn_slots(%Node{slots: slots} = node) do
    ViewModel.body_slots(node) ++
      Enum.filter(slots, &ViewModel.rail?/1) ++ Enum.filter(slots, &ViewModel.tray?/1)
  end

  # A stacking block's one body slot is drawn inside the block itself, but
  # for a group's, which is a pane of its own; see the moduledoc.
  @spec inline?(Node.t(), Slot.t()) :: boolean()
  defp inline?(%Node{} = node, %Slot{name: name}) do
    not group?(node) and
      match?(
        {:stack, [%Slot{name: ^name}]},
        {ViewModel.arrangement(node), ViewModel.body_slots(node)}
      )
  end

  # ------------------------------------------------------------------- slots

  @spec slot(Node.t(), Slot.t(), Phrasing.phrase()) :: graph_node()
  defp slot(%Node{block_id: block_id} = node, %Slot{} = slot, phrase) do
    id = "#{block_id}/#{slot.name}"
    style = style(node, slot)
    lines = slot |> slot_header() |> wrap()

    {children, edges} =
      case slot.children do
        [] -> {[empty(block_id, slot.name)], []}
        _blocks -> {slot_children(slot, phrase), flow_edges(slot)}
      end

    %{
      "id" => id,
      "kind" => "slot",
      "style" => style,
      "title" => slot.label,
      "lines" => lines,
      "layoutOptions" => slot_options(style, node, slot, lines, phrase),
      "children" => children,
      "edges" => edges
    }
    |> put_caption(style, node)
  end

  # A group's rules column carries its caption and its type's sentence,
  # wrapped; see the moduledoc's "The Group".
  @spec put_caption(graph_node(), String.t(), Node.t()) :: graph_node()
  defp put_caption(graph_node, "rail", %Node{type: type}) when type in @group_types do
    case caption(type) do
      nil ->
        graph_node

      sentence ->
        Map.merge(graph_node, %{
          "caption" => @rules_caption,
          "explanation_lines" => wrap(sentence)
        })
    end
  end

  defp put_caption(graph_node, _style, %Node{}), do: graph_node

  # A rail or a tray is not a step in the flow: it watches the whole of it,
  # or holds what is kept to one side. ELK's last layer puts it beside the
  # flow's last step, rather than beside its first as if it came next. A
  # group's rules column is laid out on its own and its body's pane is held
  # larger than it; see the moduledoc's "The Group".
  @spec slot_options(String.t(), Node.t(), Slot.t(), [String.t()], Phrasing.phrase()) ::
          %{String.t() => String.t()}
  defp slot_options("rail", %Node{type: type} = node, %Slot{} = slot, _lines, _phrase)
       when type in @group_types do
    lines = column_lines(node, slot)

    %{
      @force_model_order => "true",
      @layer_constraint => "LAST",
      "org.eclipse.elk.hierarchyHandling" => "SEPARATE_CHILDREN",
      "org.eclipse.elk.algorithm" => "layered",
      "org.eclipse.elk.direction" => "RIGHT",
      "org.eclipse.elk.separateConnectedComponents" => "false",
      "org.eclipse.elk.spacing.nodeNode" => "#{@rule_spacing}",
      "org.eclipse.elk.padding" =>
        "[top=#{header_height(lines)},left=#{@pad},bottom=#{@pad},right=#{@pad}]",
      "org.eclipse.elk.nodeSize.constraints" => "MINIMUM_SIZE",
      "org.eclipse.elk.nodeSize.minimum" =>
        "(#{text_width(lines)},#{header_height(lines) + @pad})"
    }
  end

  defp slot_options("body", %Node{} = node, %Slot{}, lines, phrase) do
    {width, height} = column_size(node, phrase)
    container_options(lines, lines, 0, least: width + @body_lead, tall: height)
  end

  defp slot_options(style, %Node{}, %Slot{}, lines, _phrase) when style in ["rail", "tray"],
    do: Map.put(container_options(lines, lines), @layer_constraint, "LAST")

  defp slot_options(_arm, %Node{}, %Slot{}, lines, _phrase), do: container_options(lines, lines)

  @spec slot_header(Slot.t()) :: String.t()
  defp slot_header(%Slot{label: label, condition: condition}) when is_binary(condition),
    do: "#{label}: #{condition}"

  defp slot_header(%Slot{label: label}), do: label

  # A group's body is its pane; every other slot is an arm, a rail (a
  # group's rules column among them) or a tray.
  @spec style(Node.t(), Slot.t()) :: String.t()
  defp style(%Node{} = node, %Slot{} = slot) do
    cond do
      group?(node) and not ViewModel.rail?(slot) and not ViewModel.tray?(slot) -> "body"
      ViewModel.rail?(slot) -> "rail"
      ViewModel.tray?(slot) -> "tray"
      true -> "arm"
    end
  end

  # A slot's blocks: the flow in order, then the shelf at its foot, the
  # order `ViewModel.outline/1` visits them in.
  @spec slot_children(Slot.t(), Phrasing.phrase()) :: [graph_node()]
  defp slot_children(%Slot{} = slot, phrase) do
    Enum.map(ViewModel.flow_children(slot) ++ ViewModel.shelf_children(slot), &block(&1, phrase))
  end

  # A rail's or a tray's blocks are not a sequence; see the moduledoc.
  @spec flow_edges(Slot.t()) :: [map()]
  defp flow_edges(%Slot{} = slot) do
    if ViewModel.rail?(slot) or ViewModel.tray?(slot), do: [], else: sequence_edges(slot)
  end

  @spec sequence_edges(Slot.t()) :: [map()]
  defp sequence_edges(%Slot{} = slot) do
    slot
    |> ViewModel.flow_children()
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn [%Node{block_id: from} = source, %Node{block_id: to}] ->
      %{"id" => "#{from}->#{to}", "sources" => [from], "targets" => [to], "kind" => kind(source)}
    end)
  end

  # The edge out of a branch is where its arms rejoin; see the moduledoc.
  @spec kind(Node.t()) :: String.t()
  defp kind(%Node{} = node), do: if(branch?(node), do: "rejoin", else: "sequence")

  # An empty slot's marker carries the block and the slot it stands for,
  # which is the gap an insert into it targets.
  @spec empty(String.t(), String.t()) :: graph_node()
  defp empty(block_id, slot_name) do
    %{
      "id" => "#{block_id}/#{slot_name}/empty",
      "kind" => "empty",
      "parent" => block_id,
      "slot" => slot_name,
      "title" => @empty_text,
      "lines" => [],
      "width" => leaf_width([@empty_text]),
      "height" => @header_base + @line_height
    }
  end

  # ------------------------------------------------------------------ sizing

  # Every container orders its own children; see the moduledoc on why this
  # is set per container and `considerModelOrder` is not. `texts` is every
  # line the container draws, title included, and holds its width; `lines`
  # is what sits under the title, and sets the header's height.
  #
  # The minimum is written HEIGHT first. Under `direction: DOWN` with
  # `hierarchyHandling: INCLUDE_CHILDREN`, elkjs 0.9.3 applies a nested
  # container's `nodeSize.minimum` transposed - `(w,h)` comes back `w` tall
  # and `h` wide - so the pair is handed over in the order it is read back
  # in. Written the documented way round, a container whose header is
  # wider than its children stays narrow and grows a tall empty band.
  # An elkjs that stops transposing would narrow such a box quietly, so
  # only a layout through the real elkjs, holding every box at least as
  # wide as its text, can see it.
  #
  # `extra` is room under the header and above the children: a branch's
  # band. `least` and `tall` raise the minimum width and height past what
  # the text needs: a branch's band caption, a group body's pane.
  @spec container_options([String.t()], [String.t()], non_neg_integer(), keyword()) ::
          %{String.t() => String.t()}
  defp container_options(texts, lines, extra \\ 0, opts \\ []) do
    top = header_height(lines) + extra
    width = max(text_width(texts), Keyword.get(opts, :least, 0))
    height = max(top + @pad, Keyword.get(opts, :tall, 0))

    %{
      @force_model_order => "true",
      "org.eclipse.elk.padding" => "[top=#{top},left=#{@pad},bottom=#{@pad},right=#{@pad}]",
      "org.eclipse.elk.nodeSize.constraints" => "MINIMUM_SIZE",
      "org.eclipse.elk.nodeSize.minimum" => "(#{height},#{width})"
    }
  end

  # The height of a container's header: its title and `lines` under it.
  @spec header_height([String.t()]) :: pos_integer()
  defp header_height(lines), do: @header_base + (length(lines) + 1) * @line_height

  @spec leaf_width([String.t()]) :: pos_integer()
  defp leaf_width(texts), do: max(text_width(texts), @leaf_min_width)

  # The width the widest of `texts` needs at the estimate, padding included.
  @spec text_width([String.t()]) :: pos_integer()
  defp text_width(texts) do
    widest = texts |> Enum.map(&String.length/1) |> Enum.max(fn -> 0 end)
    widest * @char_width + @leaf_padding
  end

  # The first sentence of a paragraph: up to the first full stop that ends
  # a word and is followed by a space, or the whole paragraph.
  @spec first_sentence(String.t()) :: String.t()
  defp first_sentence(text) do
    case Regex.run(~r/^.*?\w[.!?](?=\s)/u, text) do
      [sentence] -> sentence
      nil -> text
    end
  end

  # The lines under a box's title: `text` wrapped, or none when it only
  # repeats the title.
  @spec under(String.t(), String.t()) :: [String.t()]
  defp under(title, title), do: []
  defp under(text, _title), do: wrap(text)

  # Words onto lines no wider than a leaf holds, or than `per_line`
  # characters where one is given (the key's). A single word longer than a
  # line keeps its own line rather than being cut: nothing on the map
  # truncates, a caption included (see the moduledoc's "Captions"). Every line
  # after the first starts with `indent`, which counts against its room.
  @spec wrap(String.t(), String.t(), pos_integer()) :: [String.t()]
  defp wrap(text, indent \\ "", per_line \\ div(@leaf_max_width - @leaf_padding, @char_width)) do
    continued = per_line - String.length(indent)

    lines =
      text
      |> String.split(~r/\s+/, trim: true)
      |> Enum.reduce([], fn
        word, [] -> [word]
        word, [line] -> join(word, line, [], per_line)
        word, [line | rest] -> join(word, line, rest, continued)
      end)
      |> Enum.reverse()

    case lines do
      [] -> []
      [first | rest] -> [first | Enum.map(rest, &(indent <> &1))]
    end
  end

  @spec join(String.t(), String.t(), [String.t()], pos_integer()) :: [String.t()]
  defp join(word, line, rest, per_line) do
    if String.length(line) + 1 + String.length(word) <= per_line,
      do: ["#{line} #{word}" | rest],
      else: [word, line | rest]
  end
end
