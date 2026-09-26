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
      ...>         Block.new("core.wait", id: "wait", config: %{"duration" => "30s"}),
      ...>         Block.new("core.send", id: "send", config: %{"event" => "order.paid"})
      ...>       ]
      ...>     }
      ...>   )
      iex> root |> Document.new() |> Describe.outline(Palette.core(), []) |> Describe.render([])
      [
        "Run its steps in order",
        "Wait 30s",
        "Send order.paid",
        "Run its steps in order starts with Wait 30s",
        "After Wait 30s (done), Send order.paid",
        "Send order.paid (done) ends Run its steps in order"
      ]

  ## Pure, and no model anywhere

  `outline/3` is a function of the document, the palette and its options,
  and `render/2` of the outline and its options. Neither compiles the
  document, reads a clock or a random source, starts or messages a
  process, reaches a network or asks a language model, and equal input
  answers byte-identical output. The only code either runs that this
  package does not own is the palette's block-type callbacks and the
  host's phrasing module, each held to be a pure function of its arguments
  by its own contract (`StatifierBlocks.BlockType`,
  `StatifierBlocks.Describe.Phrasing`).

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

  A child here is one `StatifierBlocks.ViewModel.flow_children/1` answers
  for the slot: a drafts shelf is a node and takes part in no edge.

  A `:sequence` or `:exit` edge carries every outcome name the source
  block's type declares, on the one edge. They are the declared outcomes,
  not a compile's finals: `core.await` declares `received` and `timed_out`
  whatever its config, so both ride its edge even with no timeout set.

  Every other type - `core.parallel`, `core.foreach`, `core.map`,
  `core.subchart`, `core.invoke`, a composite, a host type - is described
  by containment and its node's `fan_label` alone, and draws no edge among
  its children; a block of one still takes part in its parent's edges. An
  event name shared by a send and a handler is not an edge.

  ## Lines

  `render/2` answers one line per node, then one per edge, in the
  outline's orders; ADR-0016 decision 2 gives each default line's words.
  Every line is non-blank English with no newline, carriage return or tab,
  and uncapped: a newline, carriage return or tab inside an author's text
  is written as one space. A block's id never appears in a default line.
  """

  alias StatifierBlocks.{Block, BlockType, Document, Palette, ViewModel}
  alias StatifierBlocks.Core.{Branch, Group, ResumableGroup, Sequence}
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

  @typep resolution :: {:ok, Palette.type_ref(), Block.t()} | :unresolvable
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
      Enum.flat_map(entries, fn {vm_node, _depth, _kind} -> edges(vm_node, lookup, outcomes) end)

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
  """
  @spec render(t(), keyword()) :: [String.t()]
  def render(%__MODULE__{nodes: nodes, edges: edges}, opts) when is_list(opts) do
    phrasing = Keyword.get(opts, :phrasing)
    sentences = Map.new(nodes, &{&1.id, name(&1)})

    node_lines = Enum.map(nodes, &phrase(phrasing, &1.kind, &1, node_line(&1)))
    edge_lines = Enum.map(edges, &phrase(phrasing, &1.kind, &1, edge_line(&1, sentences)))

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
      fan_label: ViewModel.fan_label(vm_node)
    }
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
      {:error, _reason} -> :unresolvable
    end
  end

  @spec outcomes(resolution()) :: [String.t()]
  defp outcomes({:ok, ref, block}),
    do: ref |> BlockType.outcomes(block.config) |> BlockType.outcome_names()

  defp outcomes(:unresolvable), do: @placeholder_outcomes

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
    |> Enum.flat_map(&ViewModel.flow_children/1)
    |> Enum.flat_map(&interrupt_edge(&1, id, history, event(&1, lookup)))
  end

  @spec interrupt_edge(ViewModel.Node.t(), Block.id(), :shallow | :deep | nil, String.t() | nil) ::
          [Edge.t()]
  defp interrupt_edge(
         %ViewModel.Node{outcome: "abandon", block_id: handler},
         group,
         _history,
         event
       ),
       do: [
         %Edge{
           kind: :interrupt,
           container: group,
           from: {:block, handler},
           to: {:exit, group},
           event: event
         }
       ]

  defp interrupt_edge(
         %ViewModel.Node{outcome: "resume", block_id: handler},
         group,
         history,
         event
       ) do
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

  defp interrupt_edge(%ViewModel.Node{}, _group, _history, _event), do: []

  # The event a handler listens for, as its resolved config holds it.
  @spec event(ViewModel.Node.t(), lookup()) :: String.t() | nil
  defp event(%ViewModel.Node{block_id: id}, lookup) do
    with {_parent, {:ok, _ref, %Block{config: %{"event" => event}}}} when is_binary(event) <-
           Map.get(lookup, id),
         false <- String.trim(event) == "" do
      event
    else
      _no_event -> nil
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

  @spec edge_line(Edge.t(), %{optional(Block.id()) => String.t()}) :: String.t()
  defp edge_line(%Edge{kind: :entry} = edge, s),
    do: "#{sentence(s, edge.container)} starts with #{target(s, edge.to)}"

  defp edge_line(%Edge{kind: :sequence} = edge, s),
    do: "After #{target(s, edge.from)}#{carried(edge)}, #{target(s, edge.to)}"

  defp edge_line(%Edge{kind: :exit} = edge, s),
    do: "#{target(s, edge.from)}#{carried(edge)} ends #{sentence(s, edge.container)}"

  defp edge_line(%Edge{kind: :branch} = edge, s),
    do: "#{sentence(s, edge.container)}: #{arm(edge.condition)}, #{target(s, edge.to)}"

  defp edge_line(%Edge{kind: :interrupt} = edge, s) do
    on = if edge.event, do: "On #{flat(edge.event)}", else: "On its event"
    does = if match?({:body, _id}, edge.to), do: "resumes", else: "abandons"
    at = if edge.history, do: " at #{edge.history} history", else: ""

    "#{on}, #{target(s, edge.from)} #{does} #{sentence(s, edge.container)}#{at}"
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

  @spec target(%{optional(Block.id()) => String.t()}, Edge.endpoint()) :: String.t()
  defp target(s, {:exit, id}), do: "the end of #{sentence(s, id)}"
  defp target(s, {_block_entry_or_body, id}), do: sentence(s, id)

  @spec sentence(%{optional(Block.id()) => String.t()}, Block.id()) :: String.t()
  defp sentence(s, id), do: Map.get(s, id, "a block")

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
