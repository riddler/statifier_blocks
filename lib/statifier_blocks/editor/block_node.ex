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

    ## The accent, and why the stylesheet still names no type

    A palette entry may declare `accent_token`, the NAME of a `--sb-*`
    custom property (ADR-0005 decision 14's amendment). This component
    stamps it on the card and rebinds `--sb-block-accent` there; the
    stylesheet reads that property in exactly two rules, an icon tile and a
    card stripe, so adding a block type with its own identity adds no CSS
    and no branch. The value is the theme's - a descriptor carries a name,
    never a colour - and a name that does not validate resolves to the
    editor's accent rather than to a broken card.

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
          ViewModel.boundary?(@node) && "sb-node--boundary",
          @class
        ]}
        data-sb-block-accent={accent_token(@node)}
        style={accent_style(@node)}
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

    # 14d's consumption side, and the only place a card learns it has an
    # identity. `ViewModel.accent_token/1` decides whether the palette entry
    # declared a usable one; this renders the rebinding on that card and
    # nothing else, so the stylesheet still reads one property and still
    # names no block type.
    @spec accent_token(ViewModel.Node.t()) :: String.t() | nil
    defp accent_token(%ViewModel.Node{entry: entry}), do: ViewModel.accent_token(entry)

    @spec accent_style(ViewModel.Node.t()) :: String.t() | nil
    defp accent_style(node) do
      case accent_token(node) do
        nil -> nil
        name -> "--sb-block-accent: var(#{name}, var(--sb-accent))"
      end
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

    # One place spells the severity modifiers, and it is outside
    # `StatifierBlocks.Editor.*` so it is asserted with LiveView absent
    # (ADR-0005 decision 11, amended 2026-08-29 for `:info`).
    @spec severity_class(StatifierBlocks.Finding.t()) :: String.t()
    defp severity_class(finding), do: StatifierBlocks.Finding.severity_class(finding)
  end
end
