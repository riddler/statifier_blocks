if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.BlockNode do
    @moduledoc """
    One block's chrome, dispatching to its slots (ADR-0005 decisions 10, 11,
    12, 13).

    ## No branch on a type name, ever

    Decision 10's `layout` and `slot_style` are how nested groups, lanes and
    interrupt rails render distinctly **without the editor branching on a type
    name**. `core.parallel` declares `layout: :columns`, so its lane slots sit
    side by side and the absence of ordering between them is visible;
    `core.resumable_group` declares `slot_style: %{"interrupts" => :secondary}`,
    so its interrupt rules render as an attached rail rather than a second
    body. A host block type with the same structural shape gets the same
    rendering by declaring the same thing, which is the property that matters.
    There is no branch anywhere in this module on `"core.parallel"` or on any
    other type string, and the operator pre-decision behind ADR-0005 is that
    there never will be.

    `icon` is a **name**, never markup. This component takes an icon component
    as an assign and passes the name to it; a host that ships heroicons
    renders heroicons, a host that ships nothing gets a neutral glyph.
    Accepting raw SVG from a callback would be injecting host-authored markup
    into this package's own render tree - an injection surface, and a
    guarantee that the icon set fragments across palettes.

    ## Unresolvable blocks (decision 12)

    A block whose type does not resolve renders rather than vanishing: its
    type name, unavailable chrome, a `:block` finding, its config read-only as
    canonical JSON (there is no `config_schema/1` to drive a form and
    inventing one would be guessing), and **its existing children rendered
    normally, recursively** - the document's `slots` map preserved every one
    of them, decoding never having consulted a registry.

    It may be selected, moved and deleted. Its config may not be edited. It is
    never a drop target, because decision 5's first rule needs `slots/1` and
    there is none - `Edit.Targets` already leaves it out of the droppable set,
    so nothing here has to re-derive that.

    The acceptance property is preservation: open a document containing a
    block type the host does not have, edit an unrelated part of the tree,
    save, and the unresolvable block's bytes are unchanged. An editor that
    quietly dropped it would turn a missing palette entry into silent data
    loss.

    ## The badge

    `findings_count` covers the whole subtree, so a collapsed node still shows
    that something inside it needs attention. Decision 11's last sentence is
    explicit that a finding must never hide inside something folded shut -
    that is the failure mode that makes tree editors feel unreliable.
    """

    use Phoenix.Component

    alias StatifierBlocks.Editor.Slot
    alias StatifierBlocks.ViewModel

    attr(:node, ViewModel.Node, required: true)
    attr(:drag, :any, default: nil)
    attr(:selected_id, :string, default: nil)
    attr(:target, :any, required: true)
    attr(:icon, :any, default: nil)
    attr(:class, :string, default: nil)

    attr(:root?, :boolean,
      default: false,
      doc: """
      The document's root. It is neither draggable nor deletable, because
      `Edit.apply/2` refuses both for it (`check_not_root/2`) - rendering the
      affordances anyway would be an interface that lies about what it can do.
      """
    )

    @doc "One block: chrome, findings, and its slots, recursively."
    def block_node(assigns) do
      ~H"""
      <div
        class={[
          "sb-node",
          @node.block_id == @selected_id && "sb-node--selected",
          unresolvable?(@node) && "sb-node--unresolvable",
          @class
        ]}
        id={"sb-block-" <> @node.block_id}
        data-block-id={@node.block_id}
        data-type={@node.type}
        data-status={status_tag(@node)}
        data-findings-count={@node.findings_count}
        data-dragging={to_string(@drag != nil and @drag.block_id == @node.block_id)}
        data-root={to_string(@root?)}
        draggable={to_string(not @root?)}
      >
        <div class="sb-node__chrome">
          <.icon_glyph icon={@icon} name={@node.entry.icon} />
          <button
            type="button"
            class="sb-node__label"
            phx-click="select"
            phx-target={@target}
            phx-value-block-id={@node.block_id}
          >
            {@node.entry.label}
          </button>
          <span :if={unresolvable?(@node)} class="sb-node__type">{@node.type}</span>
          <span :if={@node.findings_count > 0} class="sb-badge">{@node.findings_count}</span>
          <button
            :if={not @root?}
            type="button"
            class="sb-node__remove"
            phx-click="remove"
            phx-target={@target}
            phx-value-block-id={@node.block_id}
          >
            delete
          </button>
        </div>

        <p :for={finding <- @node.findings} class={["sb-finding", severity_class(finding)]}>
          {finding.message}
        </p>

        <pre :if={@node.raw_config_json} class="sb-node__raw-config">{@node.raw_config_json}</pre>

        <div class={["sb-node__slots", layout_class(@node)]}>
          <Slot.slot
            :for={slot <- @node.slots}
            slot={slot}
            parent_id={@node.block_id}
            drag={@drag}
            selected_id={@selected_id}
            target={@target}
            icon={@icon}
          />
        </div>
      </div>
      """
    end

    attr(:icon, :any, default: nil)
    attr(:name, :string, default: nil)

    # A host-supplied icon component gets the name; a host that supplied none
    # gets a neutral glyph. Either way this package never emits markup a
    # callback handed it.
    defp icon_glyph(%{icon: nil} = assigns) do
      ~H"""
      <span class="sb-node__icon" data-icon={@name} aria-hidden="true">&#9633;</span>
      """
    end

    defp icon_glyph(assigns) do
      ~H"""
      {@icon.(%{name: @name, class: "sb-node__icon"})}
      """
    end

    @spec unresolvable?(ViewModel.Node.t()) :: boolean()
    defp unresolvable?(%ViewModel.Node{status: {:unresolvable, _reason}}), do: true
    defp unresolvable?(%ViewModel.Node{}), do: false

    @spec status_tag(ViewModel.Node.t()) :: String.t()
    defp status_tag(%ViewModel.Node{status: {:unresolvable, _reason}}), do: "unresolvable"
    defp status_tag(%ViewModel.Node{}), do: "ok"

    @spec layout_class(ViewModel.Node.t()) :: String.t()
    defp layout_class(%ViewModel.Node{entry: %{layout: :columns}}), do: "sb-node__slots--columns"
    defp layout_class(%ViewModel.Node{}), do: "sb-node__slots--stack"

    @spec severity_class(StatifierBlocks.Finding.t()) :: String.t()
    defp severity_class(%StatifierBlocks.Finding{severity: :warning}), do: "sb-finding--warning"
    defp severity_class(%StatifierBlocks.Finding{}), do: "sb-finding--error"
  end
end
