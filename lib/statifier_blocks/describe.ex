defmodule StatifierBlocks.Describe do
  @moduledoc """
  A block document described in words: an outline of its blocks joined by
  the ways control passes between them, and one line of English per block
  and per edge (ADR-0016).

      iex> alias StatifierBlocks.{Block, Describe, Document, Palette}
      iex> root =
      ...>   Block.new("core.sequence",
      ...>     id: "root",
      ...>     slots: %{
      ...>       "body" => [
      ...>         Block.new("core.wait", id: "wait", config: %{"duration" => "14d"}),
      ...>         Block.new("core.send", id: "send", config: %{"event" => "loan.overdue"})
      ...>       ]
      ...>     }
      ...>   )
      iex> root |> Document.new() |> Describe.outline(Palette.core(), []) |> Describe.render([])
      [
        "Run its steps in order",
        "Wait 14d",
        "Send loan.overdue",
        "The steps start with Wait 14d",
        "After Wait 14d (done), Send loan.overdue",
        "Send loan.overdue (done) ends the steps"
      ]

  ## Pure, and no model anywhere

  `outline/3` is a function of the document, the palette and its options,
  and `render/2` of the outline and its options. Neither compiles the
  document, reads a clock or a random source, starts a process or sends a
  message of its own, reaches a network or asks a language model, and
  equal input answers byte-identical output. The one way either can reach
  another process is not of its own making: a module is made sure of
  (`Code.ensure_loaded?/1`) before it is asked - a palette's block-type
  module by `StatifierBlocks.Palette.declares?/3`, the host's phrasing
  module by `render/2` - and a module not yet loaded is loaded by the
  runtime's code server. The only code either runs that this package does
  not own is the palette's block-type callbacks, the host's phrasing
  module and, because `outline/3` builds the document's view model with
  `StatifierBlocks.ViewModel.build/3`, every
  `StatifierBlocks.DocumentValidator` in the palette's `validators` list.
  Each is held to be a pure function of its arguments by its own contract
  (`StatifierBlocks.BlockType`, `StatifierBlocks.Describe.Phrasing`,
  `StatifierBlocks.DocumentValidator`), and by contract only: nothing here
  enforces it, so a host callback that reads a clock or sends a message
  does so inside `outline/3` or `render/2`. A validator's findings take no
  part in the outline: a document describes the same with or without its
  palette's validators.

  ## Nodes

  One `StatifierBlocks.Describe.Node` per block, every block exactly once,
  in `StatifierBlocks.ViewModel.outline/1`'s order. A block whose type the
  palette cannot resolve is described as its placeholder rather than
  refused.

  ## Edges, from the document's structure

  The edges are the block-level flow graph of the package's note
  `docs/block-level-flow-graph.md`, read from the document's tree and the
  block types' declarations; nothing is compiled. Edges are found inside a
  resolved block of exactly the four types the note works through:

    * **`core.sequence`**: an `:entry` edge from its entry to its first
      child, a `:sequence` edge from each child to the next, and an `:exit`
      edge from the last child to its exit. An empty body is one `:entry`
      edge from its entry straight to its exit.
    * **`core.group`, `core.resumable_group`**: the same three over the
      `body` slot, then one `:interrupt` edge per handler in the
      `interrupts` slot whose `outcome` is `abandon` (to the group's exit)
      or `resume` (to the group's body, carrying a resumable group's
      `history`).
    * **`core.branch`**: per arm, in slot order, a `:branch` edge from the
      branch's entry to the arm's first child - or to the branch's exit
      for an empty arm - followed by that arm's `:sequence` edges and the
      `:exit` edge from its last child to the branch's exit, where the arms
      converge. `otherwise` always has its edge; `undecided` has one only
      when it holds a block.

  A type is recognised here by the module the palette resolves the
  block's type name to - `StatifierBlocks.Core.Sequence`,
  `StatifierBlocks.Core.Group`, `StatifierBlocks.Core.ResumableGroup` or
  `StatifierBlocks.Core.Branch` - not by the name itself; under
  `StatifierBlocks.Palette.core/0` the two agree. A palette that registers
  a host's own module under `core.sequence` gets that block described by
  containment only, and one that registers `StatifierBlocks.Core.Sequence`
  under a name of the host's own gets a sequence's edges. The timer edge
  below recognises its sends, rules and awaits the same way.

  A child here is one `StatifierBlocks.ViewModel.flow_children/1` answers
  for the slot: a drafts shelf is a node and takes part in no edge.

  A `:sequence` or `:exit` edge carries every outcome name the source
  block's type declares, on the one edge. They are the declared outcomes,
  not a compile's finals: `core.await` declares `received` and `timed_out`
  whatever its config, so both ride its edge even with no timeout set.

  Every other type - `core.parallel`, `core.foreach`, `core.map`,
  `core.subchart`, `core.invoke`, a composite, a host type - is described
  by containment and its node's `fan_label` alone, and draws no edge among
  its children; a block of one still takes part in its parent's edges.

  ## The timer edge, the one edge an event name draws

  An event name shared by a send and a handler is not an edge, with one
  named exception (ADR-0016's amendment of 2026-09-27, ADR-0017 decision
  3): a delayed `core.send`, one whose `delay` is a duration
  `StatifierBlocks.Core.Duration.duration?/1` accepts, draws one `:timer`
  edge to every `core.on_event` and `core.await` anywhere in the document
  whose `event` is the send's `event`, the same string. The edge runs from
  the send to the rule or await, its container is the send's parent, and
  it carries the event and the delay as the send's config holds it. Only
  blocks the palette resolved take part, and a block inside a drafts shelf
  takes part in none. An undelayed send draws none. It is read from config,
  never compiled, and it is not a transition: it says that the send arms an
  event the other block waits for.

  Timer edges follow every other edge, in the outline's order of their
  sends and, for one send, of their targets. A document with no delayed
  send describes exactly as it would without them.

  ## Lines

  `render/2` answers one line per node, then one per edge, in the
  outline's orders; ADR-0016 decision 2 gives each default line's words,
  and a timer edge's line is `In <delay>, <event> reaches <target>`, the
  delay written in the words `core.send`'s own sentence uses (`24h` reads
  as `24 hours`).

  An edge line names a step by its sentence and a container - the block
  whose structure drew the edge, and that block's entry, exit or body -
  by the container's node's `noun` (ADR-0016's amendment of 2026-09-29):
  its title where it has one; else the noun its module is known by, `the
  steps` for a sequence, `the group` for a group or a resumable group,
  `the branch`, `the lanes` for a parallel and `the loop` for a for-each;
  else `the` and its palette label in lower case. A noun that opens a
  line with a lower-case `the`, a title included, is written with a
  capital there, and a noun whose text is `the steps` or `the lanes`,
  a title included, takes `start` where the others take `starts`, as in
  `The steps start with Wait 14d` and `Send loan.overdue (done) ends the
  steps`. A node that carries no noun is named by its sentence.

  A step keeps its sentence in an edge line, first letter and all, and a
  delayed send's sentence, `In 7 days, send loan.overdue`, is set there in
  double quotation marks, because its comma would otherwise read as the
  line's own: `The steps start with "In 7 days, send loan.overdue"`,
  `After "In 7 days, send loan.overdue" (done), Wait 14d`. A delayed send
  is read from its node alone - the type name `core.send` and the
  sentence `core.send` writes for a delay - because `render/2` holds no
  palette. Its own node line, and every other embedded sentence, is
  written without the marks.

  Every line is non-blank English with no newline, carriage return or tab,
  and uncapped: a newline, carriage return or tab inside an author's text
  is written as one space. A block's id never appears in a default line.
  """

  alias StatifierBlocks.{Block, BlockType, Document, Palette, Shelf, ViewModel}

  alias StatifierBlocks.Core.{
    Await,
    Branch,
    Duration,
    Foreach,
    Group,
    OnEvent,
    Parallel,
    ResumableGroup,
    Send,
    Sequence
  }

  alias StatifierBlocks.Describe.{Edge, Node}

  @type t :: %__MODULE__{
          id: Document.id(),
          revision: non_neg_integer(),
          nodes: [Node.t()],
          edges: [Edge.t()]
        }

  @enforce_keys [:id, :revision]
  defstruct [:id, :revision, nodes: [], edges: []]

  # The outcome a type declaring no `outcomes/1` has (ADR-0002 amendment
  # A1), which is all a placeholder can be said to declare.
  @placeholder_outcomes ["done"]

  # What an edge line calls a container it names as a whole, where the
  # block has no title of its own (ADR-0016's amendment of 2026-09-29):
  # keyed by the module the palette resolves the type to, as the edges
  # are. A container of any other module falls back to "the" and its
  # palette label in lower case.
  @nouns %{
    Sequence => "the steps",
    Group => "the group",
    ResumableGroup => "the group",
    Branch => "the branch",
    Parallel => "the lanes",
    Foreach => "the loop"
  }

  # The noun texts that take a plural verb, read from the text alone: a
  # title with one of these texts takes it too.
  @plural_nouns ["the steps", "the lanes"]

  @typep resolution :: {:ok, Palette.type_ref(), Block.t()} | {:unresolvable, Block.t()}
  @typep lookup :: %{optional(Block.id()) => {Block.id() | nil, resolution()}}

  @doc """
  The outline of `document` under `palette`: its id and revision, one node
  per block and the edges between them, as the moduledoc describes.

  `opts` is a keyword list; no key is read, and an unknown one is ignored.
  """
  @spec outline(Document.t(), Palette.t(), keyword()) :: t()
  def outline(%Document{} = document, %Palette{} = palette, opts) when is_list(opts) do
    entries = document |> ViewModel.build(palette, []) |> ViewModel.outline()

    lookup =
      document.root
      |> walk(nil)
      |> Map.new(fn {block, parent} -> {block.id, {parent, resolve(palette, block)}} end)

    nodes = Enum.map(entries, fn {vm_node, depth, kind} -> node(vm_node, depth, kind, lookup) end)
    outcomes = Map.new(nodes, fn %Node{id: id, outcomes: names} -> {id, names} end)

    edges =
      Enum.flat_map(entries, fn {vm_node, _depth, _kind} -> edges(vm_node, lookup, outcomes) end) ++
        timer_edges(entries, lookup)

    %__MODULE__{id: document.id, revision: document.revision, nodes: nodes, edges: edges}
  end

  @doc """
  One line per node in the outline's node order, then one line per edge in
  its edge order.

  Every line is first written in the package's own words. With
  `phrasing: module`, a module implementing
  `StatifierBlocks.Describe.Phrasing`, each line is then offered to the
  module's callback for the node's or edge's `kind`, where it declares one;
  a usable answer replaces the line, and `:default` or a refused answer
  keeps it (`Phrasing` gives the refusal set). Without the option every
  line is the default.

  The option's value is a module atom, and `phrasing: nil` is the same as
  leaving it out. An atom that names no loadable module answers the
  default lines; a value that is not an atom is outside this contract and
  raises.
  """
  @spec render(t(), keyword()) :: [String.t()]
  def render(%__MODULE__{nodes: nodes, edges: edges}, opts) when is_list(opts) do
    phrasing = Keyword.get(opts, :phrasing)
    names = Map.new(nodes, &{&1.id, {embedded_name(&1), container_name(&1)}})

    node_lines = Enum.map(nodes, &phrase(phrasing, &1.kind, &1, node_line(&1)))
    edge_lines = Enum.map(edges, &phrase(phrasing, &1.kind, &1, edge_line(&1, names)))

    node_lines ++ edge_lines
  end

  # -- nodes -----------------------------------------------------------------

  @spec node(ViewModel.Node.t(), non_neg_integer(), ViewModel.kind(), lookup()) :: Node.t()
  defp node(%ViewModel.Node{block_id: id} = vm_node, depth, kind, lookup) do
    {parent, resolution} = Map.get(lookup, id, {nil, :unresolvable})

    %Node{
      id: id,
      type: vm_node.type,
      parent: parent,
      depth: depth,
      kind: kind,
      sentence: ViewModel.sentence(vm_node),
      outcomes: outcomes(resolution),
      summary: vm_node.summary,
      fan_label: ViewModel.fan_label(vm_node),
      noun: node_noun(vm_node, resolution)
    }
  end

  # A block with slots is named by its title, else by its module's noun,
  # else by "the" and its palette label in lower case. A block with no
  # slots is never an edge's container, and a block the palette cannot
  # resolve draws no edge inside itself: neither carries a noun.
  @spec node_noun(ViewModel.Node.t(), resolution() | :unresolvable) :: String.t() | nil
  defp node_noun(%ViewModel.Node{slots: []}, _resolution), do: nil

  defp node_noun(%ViewModel.Node{title: title}, {:ok, _ref, _block}) when is_binary(title),
    do: flat(title)

  defp node_noun(%ViewModel.Node{} = vm_node, {:ok, ref, _block}),
    do: Map.get(@nouns, module(ref)) || "the " <> String.downcase(label(vm_node))

  defp node_noun(%ViewModel.Node{}, _unresolvable), do: nil

  # The palette label, falling back to the type name as the view model's
  # own title does.
  @spec label(ViewModel.Node.t()) :: String.t()
  defp label(%ViewModel.Node{entry: entry, type: type}) do
    case Map.get(entry, :label) do
      label when is_binary(label) -> if String.trim(label) == "", do: type, else: flat(label)
      _undeclared -> type
    end
  end

  @spec walk(Block.t(), Block.id() | nil) :: [{Block.t(), Block.id() | nil}]
  defp walk(%Block{id: id, slots: slots} = block, parent) do
    children =
      slots
      |> Enum.sort_by(fn {name, _children} -> name end)
      |> Enum.flat_map(fn {_name, children} -> Enum.flat_map(children, &walk(&1, id)) end)

    [{block, parent} | children]
  end

  @spec resolve(Palette.t(), Block.t()) :: resolution()
  defp resolve(palette, block) do
    case Palette.resolve(palette, block) do
      {:ok, ref, migrated} -> {:ok, ref, migrated}
      {:error, _reason} -> {:unresolvable, block}
    end
  end

  @spec outcomes(resolution()) :: [String.t()]
  defp outcomes({:ok, ref, block}),
    do: ref |> BlockType.outcomes(block.config) |> BlockType.outcome_names()

  defp outcomes(_unresolvable), do: @placeholder_outcomes

  # -- edges -----------------------------------------------------------------

  @spec edges(ViewModel.Node.t(), lookup(), %{optional(Block.id()) => [String.t()]}) ::
          [Edge.t()]
  defp edges(%ViewModel.Node{block_id: id} = vm_node, lookup, outcomes) do
    case Map.get(lookup, id) do
      {_parent, {:ok, ref, block}} ->
        container_edges(module(ref), vm_node, block, {lookup, outcomes})

      _unresolvable ->
        []
    end
  end

  @spec container_edges(module(), ViewModel.Node.t(), Block.t(), {lookup(), map()}) ::
          [Edge.t()]
  defp container_edges(Sequence, vm_node, _block, {_lookup, outcomes}),
    do: body_edges(vm_node, outcomes)

  defp container_edges(Group, vm_node, _block, {lookup, outcomes}),
    do: body_edges(vm_node, outcomes) ++ interrupt_edges(vm_node, nil, lookup)

  defp container_edges(ResumableGroup, vm_node, block, {lookup, outcomes}) do
    history = history(Map.get(block.config, "history"))
    body_edges(vm_node, outcomes) ++ interrupt_edges(vm_node, history, lookup)
  end

  defp container_edges(Branch, vm_node, _block, {_lookup, outcomes}),
    do: branch_edges(vm_node, outcomes)

  defp container_edges(_other, _vm_node, _block, _context), do: []

  @spec body_edges(ViewModel.Node.t(), map()) :: [Edge.t()]
  defp body_edges(%ViewModel.Node{block_id: id, slots: slots}, outcomes) do
    slots
    |> Enum.filter(&(&1.name == "body"))
    |> Enum.flat_map(fn slot ->
      children = ViewModel.flow_children(slot)

      [
        %Edge{kind: :entry, container: id, from: {:entry, id}, to: first(children, id)}
        | chain(children, id, outcomes)
      ]
    end)
  end

  @spec branch_edges(ViewModel.Node.t(), map()) :: [Edge.t()]
  defp branch_edges(%ViewModel.Node{block_id: id} = vm_node, outcomes) do
    vm_node
    |> ViewModel.body_slots()
    |> Enum.reject(&unwired_undecided?/1)
    |> Enum.flat_map(fn slot ->
      children = ViewModel.flow_children(slot)

      pick = %Edge{
        kind: :branch,
        container: id,
        from: {:entry, id},
        to: first(children, id),
        condition: condition(slot)
      }

      [pick | chain(children, id, outcomes)]
    end)
  end

  @spec first([ViewModel.Node.t()], Block.id()) :: Edge.endpoint()
  defp first([], container), do: {:exit, container}
  defp first([%ViewModel.Node{block_id: id} | _rest], _container), do: {:block, id}

  @spec unwired_undecided?(ViewModel.Slot.t()) :: boolean()
  defp unwired_undecided?(%ViewModel.Slot{name: "undecided"} = slot),
    do: ViewModel.flow_children(slot) == []

  defp unwired_undecided?(%ViewModel.Slot{}), do: false

  @spec condition(ViewModel.Slot.t()) :: Edge.condition()
  defp condition(%ViewModel.Slot{name: "otherwise"}), do: :otherwise
  defp condition(%ViewModel.Slot{name: "undecided"}), do: :undecided
  defp condition(%ViewModel.Slot{condition: condition}), do: condition

  # A `:sequence` edge per adjacent pair and the last child's `:exit` edge
  # into the container's exit; `[]` for an empty slot.
  @spec chain([ViewModel.Node.t()], Block.id(), map()) :: [Edge.t()]
  defp chain([], _container, _outcomes), do: []

  defp chain(children, container, outcomes) do
    ids = Enum.map(children, & &1.block_id)

    steps =
      ids
      |> Enum.zip(tl(ids))
      |> Enum.map(fn {from, to} ->
        %Edge{
          kind: :sequence,
          container: container,
          from: {:block, from},
          to: {:block, to},
          outcomes: Map.get(outcomes, from, [])
        }
      end)

    last = List.last(ids)

    exit = %Edge{
      kind: :exit,
      container: container,
      from: {:block, last},
      to: {:exit, container},
      outcomes: Map.get(outcomes, last, [])
    }

    steps ++ [exit]
  end

  @spec interrupt_edges(ViewModel.Node.t(), :shallow | :deep | nil, lookup()) :: [Edge.t()]
  defp interrupt_edges(%ViewModel.Node{block_id: id, slots: slots}, history, lookup) do
    slots
    |> Enum.filter(&(&1.name == "interrupts"))
    |> Enum.flat_map(fn slot ->
      slot
      |> ViewModel.flow_children()
      |> Enum.flat_map(fn handler ->
        select = select(handler, slot.outcome_key, lookup)
        interrupt_edge(select, handler.block_id, id, {history, event(handler, lookup)})
      end)
    end)
  end

  @spec interrupt_edge(
          String.t() | nil,
          Block.id(),
          Block.id(),
          {:shallow | :deep | nil, String.t() | nil}
        ) :: [Edge.t()]
  defp interrupt_edge("abandon", handler, group, {_history, event}),
    do: [
      %Edge{
        kind: :interrupt,
        container: group,
        from: {:block, handler},
        to: {:exit, group},
        event: event
      }
    ]

  defp interrupt_edge("resume", handler, group, {history, event}) do
    [
      %Edge{
        kind: :interrupt,
        container: group,
        from: {:block, handler},
        to: {:body, group},
        event: event,
        history: history
      }
    ]
  end

  defp interrupt_edge(_other, _handler, _group, _context), do: []

  # What the arrival does to the group: the handler's `outcome` select, read
  # at the slot's declared outcome key from the handler's resolved config
  # (the document's own config for a block the palette cannot resolve).
  # Never the view model node's `outcome`, which answers the name a handler
  # finishes with (`finish_as`) ahead of the select when one is set.
  @spec select(ViewModel.Node.t(), String.t() | nil, lookup()) :: String.t() | nil
  defp select(%ViewModel.Node{block_id: id}, key, lookup) do
    case Map.get(lookup, id) do
      {_parent, {:ok, _ref, %Block{config: config}}} -> BlockType.outcome_name(config, key)
      {_parent, {:unresolvable, %Block{config: config}}} -> BlockType.outcome_name(config, key)
      nil -> nil
    end
  end

  # The event a handler listens for, as its resolved config holds it.
  @spec event(ViewModel.Node.t(), lookup()) :: String.t() | nil
  defp event(%ViewModel.Node{block_id: id}, lookup) do
    case Map.get(lookup, id) do
      {_parent, {:ok, _ref, %Block{config: config}}} -> config_event(config)
      _unresolvable -> nil
    end
  end

  # A config's `event`, when it is a non-blank string.
  @spec config_event(map()) :: String.t() | nil
  defp config_event(%{"event" => event}) when is_binary(event) do
    if String.trim(event) == "", do: nil, else: event
  end

  defp config_event(_config), do: nil

  # One `:timer` edge per delayed send and rule or await naming its event,
  # in the outline's order of the sends and then of the targets. Read over
  # the whole document rather than inside a container: only blocks the
  # palette resolved take part, and nothing inside a drafts shelf. A block
  # with no usable event is filtered out where its `event` is bound: a
  # comprehension's `event = nil` is a false filter.
  @spec timer_edges([{ViewModel.Node.t(), non_neg_integer(), ViewModel.kind()}], lookup()) ::
          [Edge.t()]
  defp timer_edges(entries, lookup) do
    blocks =
      Enum.flat_map(entries, fn {vm_node, _depth, _kind} -> timer_party(vm_node, lookup) end)

    targets =
      for {id, _parent, module, config} when module in [OnEvent, Await] <- blocks,
          event = config_event(config),
          do: {id, event}

    # A send at the document root has no parent to carry as the edge's container.
    for {id, parent, Send, config} when is_binary(parent) <- blocks,
        delayed?(Map.get(config, "delay")),
        event = config_event(config),
        {target, ^event} <- targets,
        do: timer_edge({id, parent, config}, target, event)
  end

  # A block that may take part in a timer edge: resolved, and not shelved.
  @spec timer_party(ViewModel.Node.t(), lookup()) ::
          [{Block.id(), Block.id() | nil, module(), map()}]
  defp timer_party(%ViewModel.Node{block_id: id}, lookup) do
    with {parent, {:ok, ref, %Block{config: config}}} <- Map.get(lookup, id),
         false <- shelved?(id, lookup) do
      [{id, parent, module(ref), config}]
    else
      _unresolvable_or_shelved -> []
    end
  end

  @spec timer_edge({Block.id(), Block.id(), map()}, Block.id(), String.t()) :: Edge.t()
  defp timer_edge({send, parent, config}, target, event) do
    %Edge{
      kind: :timer,
      container: parent,
      from: {:block, send},
      to: {:block, target},
      event: event,
      delay: Map.get(config, "delay")
    }
  end

  # ADR-0017 decision 2's test: a delay counts when it is a duration.
  @spec delayed?(term()) :: boolean()
  defp delayed?(delay), do: Duration.duration?(delay)

  # Whether the block, or any block above it, is a drafts shelf.
  @spec shelved?(Block.id() | nil, lookup()) :: boolean()
  defp shelved?(nil, _lookup), do: false

  defp shelved?(id, lookup) do
    case Map.get(lookup, id) do
      {parent, {:ok, _ref, %Block{type: type}}} ->
        Shelf.shelf_type?(type) or shelved?(parent, lookup)

      {parent, {:unresolvable, %Block{type: type}}} ->
        Shelf.shelf_type?(type) or shelved?(parent, lookup)

      nil ->
        false
    end
  end

  @spec history(term()) :: :shallow | :deep | nil
  defp history("shallow"), do: :shallow
  defp history("deep"), do: :deep
  defp history(_other), do: nil

  @spec module(Palette.type_ref()) :: module()
  defp module({module, _state}), do: module
  defp module(module), do: module

  # -- default lines -----------------------------------------------------------

  @spec node_line(Node.t()) :: String.t()
  defp node_line(%Node{fan_label: nil} = node), do: name(node)
  defp node_line(%Node{fan_label: label} = node), do: "#{name(node)} (#{flat(label)})"

  @spec edge_line(Edge.t(), names()) :: String.t()
  defp edge_line(%Edge{kind: :entry} = edge, s) do
    container = noun(s, edge.container)
    starts = if container in @plural_nouns, do: "start", else: "starts"

    "#{opening(container)} #{starts} with #{target(s, edge.to)}"
  end

  defp edge_line(%Edge{kind: :sequence} = edge, s),
    do: "After #{target(s, edge.from)}#{carried(edge)}, #{target(s, edge.to)}"

  defp edge_line(%Edge{kind: :exit} = edge, s),
    do: "#{target(s, edge.from)}#{carried(edge)} ends #{noun(s, edge.container)}"

  defp edge_line(%Edge{kind: :branch} = edge, s),
    do: "#{opening(noun(s, edge.container))}: #{arm(edge.condition)}, #{target(s, edge.to)}"

  defp edge_line(%Edge{kind: :interrupt} = edge, s) do
    on = if edge.event, do: "On #{flat(edge.event)}", else: "On its event"
    does = if match?({:body, _id}, edge.to), do: "resumes", else: "abandons"
    at = if edge.history, do: " at #{edge.history} history", else: ""

    "#{on}, #{target(s, edge.from)} #{does} #{noun(s, edge.container)}#{at}"
  end

  defp edge_line(%Edge{kind: :timer} = edge, s) do
    delay = Send.delay_words(edge.delay) || "its delay"
    event = if edge.event, do: flat(edge.event), else: "its event"

    "In #{delay}, #{event} reaches #{target(s, edge.to)}"
  end

  @spec arm(Edge.condition()) :: String.t()
  defp arm(:otherwise), do: "otherwise"
  defp arm(:undecided), do: "if undecided"
  defp arm(nil), do: "when (no condition)"
  defp arm(condition), do: "when #{flat(condition)}"

  @spec carried(Edge.t()) :: String.t()
  defp carried(%Edge{outcomes: []}), do: ""

  defp carried(%Edge{outcomes: outcomes}),
    do: " (#{Enum.map_join(outcomes, ", ", &flat/1)})"

  # A step is named by its sentence; a container's entry, exit or body by
  # the container's noun.
  @spec target(names(), Edge.endpoint()) :: String.t()
  defp target(s, {:block, id}), do: sentence(s, id)
  defp target(s, {:exit, id}), do: "the end of #{noun(s, id)}"
  defp target(s, {_entry_or_body, id}), do: noun(s, id)

  @typep names :: %{optional(Block.id()) => {String.t(), String.t()}}

  @spec sentence(names(), Block.id()) :: String.t()
  defp sentence(s, id) do
    {sentence, _noun} = Map.get(s, id, {"a block", "a block"})
    sentence
  end

  @spec noun(names(), Block.id()) :: String.t()
  defp noun(s, id) do
    {_sentence, noun} = Map.get(s, id, {"a block", "a block"})
    noun
  end

  # A noun that opens a line with a lower-case "the" takes a capital
  # there, read from the text alone: a title beginning "the " is
  # capitalised the same way as a type's noun.
  @spec opening(String.t()) :: String.t()
  defp opening("the " <> rest), do: "The " <> rest
  defp opening(name), do: name

  # A node's noun, falling back to its sentence for a node that carries
  # none (one built by hand, say).
  @spec container_name(Node.t()) :: String.t()
  defp container_name(%Node{noun: noun} = node) do
    if is_binary(noun) and String.trim(noun) != "", do: flat(noun), else: embedded_name(node)
  end

  # A node's sentence as an edge line embeds it: a delayed send's sentence
  # in double quotation marks, because its own comma would otherwise read
  # as a template's comma (ADR-0016's amendment of 2026-09-29, item 7);
  # every other sentence as it stands. `render/2` holds no palette and no
  # config, so a delayed send is read from the node alone: the type name
  # `core.send` and the sentence `core.send` writes for a delay,
  # `In <delay>, send <event>`.
  @spec embedded_name(Node.t()) :: String.t()
  defp embedded_name(%Node{type: "core.send"} = node) do
    name = name(node)
    if delayed_send?(name), do: ~s("#{name}"), else: name
  end

  defp embedded_name(%Node{} = node), do: name(node)

  @spec delayed_send?(String.t()) :: boolean()
  defp delayed_send?(sentence),
    do: String.starts_with?(sentence, "In ") and String.contains?(sentence, ", send ")

  # A node's sentence as one non-blank line, falling back to its type.
  @spec name(Node.t()) :: String.t()
  defp name(%Node{sentence: sentence, type: type}) do
    [sentence, type]
    |> Enum.map(&flat(&1 || ""))
    |> Enum.find("a block", &(String.trim(&1) != ""))
  end

  @spec flat(String.t()) :: String.t()
  defp flat(text) when is_binary(text), do: String.replace(text, ["\r", "\n", "\t"], " ")

  # -- phrasing ------------------------------------------------------------------

  @spec phrase(module() | nil, atom(), Node.t() | Edge.t(), String.t()) :: String.t()
  defp phrase(nil, _callback, _item, default), do: default

  defp phrase(module, callback, item, default) when is_atom(module) do
    if Code.ensure_loaded?(module) and function_exported?(module, callback, 2),
      do: module |> ask(callback, item, default) |> usable() || default,
      else: default
  end

  @spec ask(module(), atom(), Node.t() | Edge.t(), String.t()) :: term()
  defp ask(module, callback, item, default) do
    apply(module, callback, [item, default])
  rescue
    _raised -> nil
  catch
    :throw, _thrown -> nil
    :exit, _reason -> nil
  end

  # `StatifierBlocks.BlockType.sentence/2`'s refusal set: a line is a
  # non-blank binary carrying no newline, carriage return or tab.
  @spec usable(term()) :: String.t() | nil
  defp usable(text) when is_binary(text) do
    cond do
      String.trim(text) == "" -> nil
      String.contains?(text, ["\n", "\r", "\t"]) -> nil
      true -> text
    end
  end

  defp usable(_default_or_refused), do: nil
end
