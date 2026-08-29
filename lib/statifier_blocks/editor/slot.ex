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

    ## The rail partition

    `:secondary` and `:failure` are both **attached rails** rather than body
    slots (amendment 10h's placement row), and `ViewModel.rail?/1` is that
    partition. What is stamped here is the placement the two share; the
    vocabulary that tells them apart - dashed and warning-family for an
    interrupt, solid and error-family for a failure path - belongs to the
    bead that renders `:failure`, and `data-slot-style` is the hook it
    needs. The container's boundary box is derived from the same partition,
    one level up in `BlockNode`.

    ## Recursion

    `Slot` renders children via `BlockNode` and `BlockNode` renders slots via
    `Slot`, and that is the whole tree. Groups, lanes, branch arms and
    interrupt rails are these same two components differing only by the
    `layout` and `slot_style` metadata decision 10 put on `palette_entry/0`.
    There is no `Group` component and no `Parallel` component, and decision 13
    says there must never be one.
    """

    use Phoenix.Component

    alias StatifierBlocks.Editor.BlockNode
    alias StatifierBlocks.ViewModel

    attr(:slot, ViewModel.Slot, required: true)
    attr(:parent_id, :string, required: true)
    attr(:drag, :any, default: nil)
    attr(:selected_id, :string, default: nil)
    attr(:target, :any, required: true)
    attr(:icon, :any, default: nil)
    attr(:class, :string, default: nil)

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
          not @slot.declared? && "sb-slot--undeclared",
          @class
        ]}
        data-slot-name={@slot.name}
        data-parent-id={@parent_id}
        data-declared={to_string(@slot.declared?)}
        data-arity={@slot.arity}
        data-slot-style={@slot.style}
        data-drop={@drop}
        data-drop-reason={@drop_reason}
      >
        <div class="sb-slot__header">
          <span class="sb-slot__label">{@slot.label}</span>
          <span :for={finding <- @slot.findings} class={["sb-finding", severity_class(finding)]}>
            {finding.message}
          </span>
        </div>

        <.gap parent_id={@parent_id} slot={@slot.name} index={0} target={@target} />
        <.child
          :for={{child, index} <- Enum.with_index(@slot.children)}
          node={child}
          parent_id={@parent_id}
          slot={@slot.name}
          index={index}
          drag={@drag}
          selected_id={@selected_id}
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
    attr(:target, :any, required: true)
    attr(:icon, :any, default: nil)

    defp child(assigns) do
      ~H"""
      <BlockNode.block_node
        node={@node}
        drag={@drag}
        selected_id={@selected_id}
        target={@target}
        icon={@icon}
      />
      <.gap parent_id={@parent_id} slot={@slot} index={@index + 1} target={@target} />
      """
    end

    attr(:parent_id, :string, required: true)
    attr(:slot, :string, required: true)
    attr(:index, :integer, required: true)
    attr(:target, :any, required: true)

    defp gap(assigns) do
      ~H"""
      <div
        class="sb-gap"
        data-parent-id={@parent_id}
        data-slot={@slot}
        data-index={@index}
      >
        <button
          type="button"
          class="sb-gap__add"
          phx-click="palette-open"
          phx-target={@target}
          phx-value-parent-id={@parent_id}
          phx-value-slot={@slot}
          phx-value-index={@index}
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
