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
    renders heroicons. Accepting raw SVG from a callback would be injecting
    host-authored markup into this package's own render tree - an injection
    surface, and a guarantee that the icon set fragments across palettes.

    A host that ships nothing gets `StatifierBlocks.Editor.Icons`, this
    package's own set for the names its own palette emits, and an entry that
    names no icon at all gets no tile. Neither is a hole in the paragraph
    above: the default is markup this package wrote, resolved from a name by
    the same seam, and the host's `icon` still wins wherever it is passed.

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

    ## The measurement anchors

    Three of them per block, stamped as `data-sb-anchor` and read by nothing
    in this module: the node's own box, its card, and a zero-height outlet at
    the very bottom of everything it contains. The outlet exists so that flow
    leaves a container from BELOW its children rather than from its header -
    a sequence's last block and the sequence itself have to leave from the
    same line, or every edge out of a nested container starts in the wrong
    place.

    They are markup, and the amendment to decision 7 is why that is all they
    are: the measurement hook reads these boxes and pushes them, and
    `StatifierBlocks.Connectors` decides what to draw from the numbers. A host
    that never imports the hook has three inert attributes and an empty div.

    ## The join marker

    A container whose slots sit side by side draws a marker under them saying
    what happens when they are done - `core.parallel` completing on its first
    lane says "continue at first". The words are the block type's, resolved by
    `StatifierBlocks.BlockType.join_label/2` and carried on the view model, so
    this component draws a string and never learns that a completion rule
    exists. A type that declares none gets the editor's own word, which is what
    ADR-0002 amendment B's `nil` means and what the spike drew before any type
    could carry a completion rule: the marker is about the arrangement, so an
    arrangement that fans out still says where it comes back together.

    A node whose slots stack draws no marker at all. There is nothing to
    rejoin, and a word under a single column reads as a rendering bug.

    ## The badge

    `findings_count` covers the whole subtree, so a collapsed node still shows
    that something inside it needs attention. Decision 11's last sentence is
    explicit that a finding must never hide inside something folded shut -
    that is the failure mode that makes tree editors feel unreliable.
    """

    use Phoenix.Component

    # The editor's own word, drawn under a side-by-side arrangement whose
    # type declares none of its own. It says what every join has in common
    # and nothing a type would have to correct.
    @default_join_label "continue"

    alias StatifierBlocks.Connectors
    alias StatifierBlocks.Editor.{Icons, Slot}
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
        data-sb-anchor={Connectors.node_anchor(@node.block_id)}
        draggable={to_string(not @root?)}
      >
        <div class="sb-node__chrome" data-sb-anchor={Connectors.card_anchor(@node.block_id)}>
          <Icons.glyph icon={@icon} name={@node.entry.icon} class="sb-node__icon" />
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

        <div :if={join_label(@node)} class="sb-node__join">
          <span class="sb-node__join-label">{join_label(@node)}</span>
        </div>

        <div
          class="sb-node__outlet"
          data-sb-anchor={Connectors.outlet_anchor(@node.block_id)}
          aria-hidden="true"
        >
        </div>
      </div>
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

    # The join marker's words, when one is drawn at all. Two facts, and
    # neither of them a type name: the slots are arranged side by side
    # (decision 10's `layout`, the same metadata `layout_class/1` reads), and
    # what the marker says (`ViewModel.Node.join_label`, resolved through
    # ADR-0002 amendment B's callback, falling back to this module's own word
    # when the type declared none - which is what the record's `nil` means).
    # A stacked node draws nothing: there is nothing to rejoin.
    @spec join_label(ViewModel.Node.t()) :: String.t() | nil
    defp join_label(%ViewModel.Node{entry: %{layout: :columns}, join_label: label}),
      do: label || @default_join_label

    defp join_label(%ViewModel.Node{}), do: nil

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
