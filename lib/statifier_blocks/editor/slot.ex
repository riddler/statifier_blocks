if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.Slot do
    @moduledoc """
    One named slot: its header, its children, its gaps, and its "+" buttons
    (ADR-0005 decisions 5, 6, 8, 11, 13).

    ## Validity is a property of the slot, and it arrives as markup

    Decision 5 makes drop-target validity per-slot rather than per-gap, and
    decision 6 makes it reach the client as markup. So during a drag session
    this component stamps `data-drop="ok"` on the slot when the server's
    one-shot `Edit.Targets.droppable_slots/3` accepted it and `data-drop="no"`
    when it did not, and hover highlighting is CSS on that attribute. There is
    zero round-trip per hover, the client holds no validity logic to fall out
    of sync, and the highlight cannot disagree with the server because it is
    the server's answer.

    Outside a drag session the attribute is absent entirely, which is what
    distinguishes "not a target for the block being dragged" from "no drag is
    happening".

    A refused slot that has a data-flow reason to give also carries
    `data-drop-reason` - `not_assignable`, or `fixable_by:<block id>` naming
    the block whose declaration an author would change (ADR-0003's 2026-08-29
    amendment). It is absent when the refusal was structural, when it was for
    room or for the dragged block's own subtree, or when different gaps in
    the slot refused for different reasons: those are refusals with no single
    honest sentence to show, and an attribute is not the place to guess one.
    Nothing reads it yet; it is markup so that the hover affordance that
    eventually does needs no round-trip and no JavaScript, exactly as
    `data-drop` needs none.

    ## The gaps, and why "+" is always there

    A slot with n children has n+1 gaps, each carrying `data-parent-id`,
    `data-slot` and `data-index` - the DOM contract decision 7's hook reads.
    Each also carries a "+" button, and it is rendered whether or not a drag
    is in progress: decision 8 wants every drop target reachable *without*
    dragging, and an affordance that only appears mid-drag would be reachable
    only by dragging. The palette that opens is filtered by the same predicate
    the drag uses, not a parallel implementation of it.

    ## The gap IS the insertion marker (R3, operator ruling 2026-08-29)

    The ruling asks for "a marker on the edge between siblings, subtle at
    rest, highlighted on hover and during drag; empty slots keep a
    placeholder". A gap already sits between two siblings, and the flow edge
    between them already runs through it - the marker is therefore the gap,
    restyled, rather than a second thing drawn on the overlay beside it.

    That is the whole reason it is not on the connector layer. The overlay is
    `aria-hidden`, carries `pointer-events: none`, and is redrawn from a
    measurement that does not exist until a host imports the measure hook; a
    marker living there would be an insertion affordance that is invisible to
    a screen reader, unreachable by keyboard, and absent entirely from the
    hook-absent editor. Riding the gap keeps every server event, the
    `phx-click` palette path and the keyboard path exactly as they shipped,
    and the marker degrades to the affordance it already was.

    `data-empty` is the placeholder half: a slot with no children has one gap
    and nothing else, so it is the gap that has to say an empty arm is a real
    arm you can drop into. It is stamped on the slot rather than derived in
    CSS from the absence of a child, because "this slot is empty" is a fact
    the view model already has and `:has()` would be re-deriving.

    ## The armed gap (sb-dfyk)

    A gap is also where an insertion is *aimed*, and until sb-dfyk it said so
    nowhere. Clicking a "+" opened the palette against that one position and
    left forty other plus signs looking exactly like the one that had just
    become the destination of the next pick, so the mode the editor was now in
    was legible only to the server.

    `armed` is that position, threaded down here the way `drag` and
    `selected_id` already are, and for the same reason: which gap is armed is
    a fact about the whole editor, and a component that decided it locally
    would be a second answer to a question that has one. The gap compares the
    tuple to its own three coordinates and says `data-armed` and
    `aria-pressed` - the attribute for the stylesheet, the ARIA state for
    everyone the stylesheet cannot reach, since a "+" that has become a live
    toggle is exactly the case `aria-pressed` exists for.

    ## The rail partition

    `:secondary` and `:failure` are both **attached rails** rather than body
    slots (amendment 10h's placement row), and `ViewModel.rail?/1` is that
    partition. The container's boundary box is derived from the same
    partition, one level up in `BlockNode`.

    What tells the two apart is a class each and nothing else:
    `sb-slot--secondary` for the interrupt's dashed warning edge, and
    `sb-slot--failure` for the failure path's solid error-family one. The
    vocabularies say opposite things about the same placement - an interrupt
    fires whether or not you get there, a failure path is the continuation
    this step takes when it goes badly - so a shared placement with no
    distinction read as a second set of interrupt rules, which is what
    campaign 013's screens recorded.

    ## The exit edge

    A rail's exit is the second question 10h asks of the style, and the
    operator ruled it on `sb-67s`: a failure rail leaves by the **ordinary
    flow edge**, and the dashed exit channel stays interrupt vocabulary.
    `ViewModel.exit_edge/1` is that derivation and `data-exit-edge` is it in
    the markup, stamped on the rails and nowhere else: a rail is the only
    slot whose exit rejoins a flow the reader can see, and the stylesheet
    draws the mark off the attribute's presence, so an attribute on a body
    slot would be a claim about a mark that is not there. The function is
    total over the three styles all the same - the rail test belongs here,
    not in every caller. Nothing here reads a type name to reach either
    answer: `core.invoke` gets the failure vocabulary by declaring
    `slot_style: %{"on_error" => :failure}`, and a host type declaring the
    same gets the same.

    ## The fan's landing point

    The header carries `data-sb-anchor`, which is where a fan edge lands when
    the container above arranges more than one slot (the amendment to decision
    7, and `StatifierBlocks.Connectors`). The header rather than the first
    card inside it: the header is what carries the slot's name and its guard,
    and an edge that ran past it to the card would cross the very condition
    the edge is subject to. An empty slot's header is also its exit anchor -
    an arm with nothing in it yet is a real arm, and a fan that silently
    skipped it would tell an author their empty arm does not exist.

    ## The label, and the condition under it

    A slot's name and the condition it is subject to are ONE unit in the
    header, wrapped in `sb-slot__name`, and the findings sit beside that unit
    rather than beside the label. The wrapper is what lets the chip sit
    *under* the words it qualifies while the header stays the baseline row
    the fan lands on and the column layout centres: a header that stacked its
    own children would have to be a column, and the arrangement rules above
    it place a row.

    The chip carries `ViewModel.Slot.condition` - the expression source, in
    the author's own text, read-only. Read-only because this is the canvas:
    the condition is editable in the inspector's form, where it is a field
    with a schema, a finding anchor and a value path, and a second editable
    spelling of one value on a surface with none of those is two controls
    that can disagree about what was typed.

    A slot with no condition source renders NO chip - not an empty one. Every
    slot in a stacked group would otherwise grow a blank box, and a blank box
    under a label reads as a condition that evaluated to nothing rather than
    as a slot that is not subject to one.

    Nothing here reads a type name to decide any of it. `core.branch` gets
    chips because its arms declare an `:expression` field keyed by the arm's
    slot, and a host type that declares the same gets the same.

    ## Depth, and why it is threaded (sb-d7g)

    `data-sb-depth` is this slot's ROOT-RELATIVE nesting depth, and it is the
    counter the recursion carries down rather than a number looked up. The
    root block's own slots are `0`, and each `BlockNode` a slot renders is one
    deeper than the slot that rendered it.

    `Shell.depth/1` does NOT answer this. It is the subtree MAXIMUM the
    toolbar reports - how deep the document goes - so every slot of one
    document would get one number from it and the bands would be flat.

    The attribute is the whole of the markup contract: the stylesheet bands on
    its parity, alternating a ground per nesting level, and there is no class
    and no wrapper element beside it. Depth `0` is deliberately unbanded, so
    the canvas keeps its own dotted ground and the first band is the first
    level of nesting.

    ## Recursion

    `Slot` renders children via `BlockNode` and `BlockNode` renders slots via
    `Slot`, and that is the whole tree. Groups, lanes, branch arms and
    interrupt rails are these same two components differing only by the
    `layout` and `slot_style` metadata decision 10 put on `palette_entry/0`.
    There is no `Group` component and no `Parallel` component, and decision 13
    says there must never be one.
    """

    use Phoenix.Component

    alias StatifierBlocks.Connectors
    alias StatifierBlocks.Editor.BlockNode
    alias StatifierBlocks.ViewModel

    attr(:slot, ViewModel.Slot, required: true)
    attr(:parent_id, :string, required: true)
    attr(:drag, :any, default: nil)
    attr(:selected_id, :string, default: nil)

    attr(:armed, :any,
      default: nil,
      doc: """
      The `{parent_id, slot, index}` the palette is armed at, or nil. Threaded
      the way `drag` and `selected_id` are, and for the same reason: the gap
      that was clicked is the one that has to look different, and only the
      editor knows which one that is.
      """
    )

    attr(:target, :any, required: true)
    attr(:icon, :any, default: nil)
    attr(:class, :string, default: nil)

    attr(:depth, :integer,
      default: 0,
      doc: """
      This slot's ROOT-RELATIVE nesting depth: the root block's own slots are
      0, the slots of a block inside one of those are 1, and so on. Stamped as
      `data-sb-depth` and banded on by the stylesheet (sb-d7g).
      """
    )

    @doc "One slot: header, findings, and alternating gaps and children."
    def slot(assigns) do
      assigns =
        assigns
        |> assign(:drop, drop_state(assigns.drag, assigns.parent_id, assigns.slot))
        |> assign(:drop_reason, drop_reason(assigns.drag, assigns.parent_id, assigns.slot))

      ~H"""
      <div
        class={[
          "sb-slot",
          ViewModel.rail?(@slot) && "sb-slot--rail",
          @slot.style == :secondary && "sb-slot--secondary",
          @slot.style == :failure && "sb-slot--failure",
          not @slot.declared? && "sb-slot--undeclared",
          @class
        ]}
        data-slot-name={@slot.name}
        data-parent-id={@parent_id}
        data-sb-depth={@depth}
        data-declared={to_string(@slot.declared?)}
        data-arity={@slot.arity}
        data-empty={to_string(@slot.children == [])}
        data-slot-style={@slot.style}
        data-exit-edge={ViewModel.rail?(@slot) && ViewModel.exit_edge(@slot)}
        data-drop={@drop}
        data-drop-reason={@drop_reason}
      >
        <div class="sb-slot__header" data-sb-anchor={Connectors.slot_anchor(@parent_id, @slot.name)}>
          <span class="sb-slot__name">
            <span class="sb-slot__label">{@slot.label}</span>
            <code :if={@slot.condition} class="sb-slot__condition" title={@slot.condition}>
              {@slot.condition}
            </code>
          </span>
          <span :for={finding <- @slot.findings} class={["sb-finding", severity_class(finding)]}>
            {finding.message}
          </span>
        </div>

        <.gap
          parent_id={@parent_id}
          slot={@slot.name}
          index={0}
          armed={@armed}
          target={@target}
        />
        <.child
          :for={{child, index} <- Enum.with_index(@slot.children)}
          node={child}
          parent_id={@parent_id}
          slot={@slot.name}
          index={index}
          depth={@depth}
          drag={@drag}
          selected_id={@selected_id}
          armed={@armed}
          target={@target}
          icon={@icon}
        />
      </div>
      """
    end

    # One child and the gap that follows it. A function component rather than
    # a wrapper element, because n children need n+1 gaps interleaved and
    # anything wrapping the pair would change the tree the CSS lays out.
    attr(:node, ViewModel.Node, required: true)
    attr(:parent_id, :string, required: true)
    attr(:slot, :string, required: true)
    attr(:index, :integer, required: true)
    attr(:drag, :any, default: nil)
    attr(:selected_id, :string, default: nil)
    attr(:armed, :any, default: nil)
    attr(:target, :any, required: true)
    attr(:icon, :any, default: nil)
    attr(:depth, :integer, default: 0)

    defp child(assigns) do
      ~H"""
      <BlockNode.block_node
        node={@node}
        depth={@depth + 1}
        drag={@drag}
        selected_id={@selected_id}
        armed={@armed}
        target={@target}
        icon={@icon}
      />
      <.gap
        parent_id={@parent_id}
        slot={@slot}
        index={@index + 1}
        armed={@armed}
        target={@target}
      />
      """
    end

    attr(:parent_id, :string, required: true)
    attr(:slot, :string, required: true)
    attr(:index, :integer, required: true)
    attr(:armed, :any, default: nil)
    attr(:target, :any, required: true)

    defp gap(assigns) do
      assigns =
        assign(
          assigns,
          :armed?,
          assigns.armed == {assigns.parent_id, assigns.slot, assigns.index}
        )

      ~H"""
      <div
        class={["sb-gap", @armed? && "sb-gap--armed"]}
        data-parent-id={@parent_id}
        data-slot={@slot}
        data-index={@index}
        data-armed={to_string(@armed?)}
      >
        <button
          type="button"
          class="sb-button sb-gap__add"
          phx-click="palette-open"
          phx-target={@target}
          phx-value-parent-id={@parent_id}
          phx-value-slot={@slot}
          phx-value-index={@index}
          aria-pressed={to_string(@armed?)}
        >
          +
        </button>
      </div>
      """
    end

    # `nil` outside a drag session, so "no drag" and "not a target" are
    # distinguishable in the markup rather than collapsed into one value.
    @spec drop_state(map() | nil, StatifierBlocks.Block.id(), ViewModel.Slot.t()) ::
            String.t() | nil
    defp drop_state(nil, _parent_id, _slot), do: nil

    defp drop_state(%{droppable: droppable}, parent_id, %ViewModel.Slot{name: name}) do
      if MapSet.member?(droppable, {parent_id, name}), do: "ok", else: "no"
    end

    # The refusal reason for a slot the drag session refused, as a string
    # the CSS and a future hover affordance can read (ADR-0003's 2026-08-29
    # amendment). `nil` - so the attribute is absent - outside a drag, for
    # an accepted slot, and for a refusal with no data-flow reason to give.
    #
    # It is stamped beside `data-drop`, not folded into it. `data-drop`
    # decides what the slot looks like and the graduation made that marking
    # one-sided; the reason decides what it could later say, and a reader
    # that does not care never has to parse one attribute to find the
    # other. No JavaScript is added by either (ADR-0005 decision 7 ships one
    # hook, and this is not it).
    #
    # Only the two refusing arms can appear: the untyped arms sit on
    # admitted seams, and an admitted gap makes its slot `"ok"`.
    @spec drop_reason(map() | nil, StatifierBlocks.Block.id(), ViewModel.Slot.t()) ::
            String.t() | nil
    defp drop_reason(nil, _parent_id, _slot), do: nil

    defp drop_reason(%{reasons: reasons}, parent_id, %ViewModel.Slot{name: name}) do
      case Map.fetch(reasons, {parent_id, name}) do
        {:ok, reason} -> reason_string(reason)
        :error -> nil
      end
    end

    defp drop_reason(_drag_without_reasons, _parent_id, _slot), do: nil

    # `{:fixable_by, id}` keeps the id in the attribute: it is the whole
    # point of that arm - the block an author would go and change - and an
    # attribute that dropped it would be `:not_assignable` spelled longer.
    @spec reason_string(StatifierBlocks.Assignability.reason()) :: String.t()
    defp reason_string({:fixable_by, block_id}), do: "fixable_by:" <> block_id
    defp reason_string(reason) when is_atom(reason), do: Atom.to_string(reason)

    # One place spells the severity modifiers, and it is outside
    # `StatifierBlocks.Editor.*` so it is asserted with LiveView absent
    # (ADR-0005 decision 11, amended 2026-08-29 for `:info`).
    @spec severity_class(StatifierBlocks.Finding.t()) :: String.t()
    defp severity_class(finding), do: StatifierBlocks.Finding.severity_class(finding)
  end
end
