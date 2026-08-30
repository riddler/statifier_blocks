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

    ## The card face

    Four lines at most, and every one of them is a different question:

      * the icon tile, which says what KIND of thing this is before anything
        is read;
      * the title, the most specific name available for this step - the
        author's own when the block carries one, and the type's label
        otherwise (`ViewModel.title/1`);
      * the second line, which is one of two facts and never both: the
        type's label when the title above is the author's
        (`ViewModel.subtitle/1`), so a named block never hides what type it
        is; otherwise the type's summary of this block's config, drawn as a
        row of chips (`ViewModel.summary_chips/1`, ADR-0005's 2026-08-30
        amendment) and absent entirely when the type declares none, so an
        unnamed block never says its type twice;
      * the invoke type in mono, when the block's config carries one - the
        one fact about a step that calls out to a handler that an author
        checks most and a label cannot carry.

    None of the four is a branch on a type name. The title and the subtitle
    read a declared field and a palette label; the invoke line reads a
    config KEY, so a host type that calls a handler gets the same line
    `core.invoke` does by carrying the same key.

    ## The unresolvable card's face (campaign-017 ruling D4)

    Decision 12's card is the one exception to "the face is four lines", and
    since ruling D4 it is a *smaller* exception than it was: a type name and
    **one** short reason, and nothing else. Its findings and its raw config
    are the inspector's - the Block section holds the bytes, the Findings tab
    holds every finding - which is what keeps the card the same width as the
    siblings it sits beside.

    Before D4 this face carried both, and the pair is what made the card
    misread. The findings are sentences, the config is a canonical JSON
    object, and a lane is as wide as the widest thing in it: one unresolvable
    block pushed its whole column out and buried the shape of the document
    under the detail of its one broken part. Detail an author reads once, on
    demand, is what a selection is for.

    The reason is read off `status` - `Palette.resolve/2`'s own error term,
    which has three shapes - and phrased here, rather than taken from the
    first finding. Two reasons, and neither is about length alone:

      * a finding's message is a sentence written for a list, and the only
        presentation cap this package has (`BlockType`'s 24-character chip)
        **refuses rather than truncates** under ADR-0002 amendment B3. Fed a
        finding, it would answer `nil` every time and leave the face blank;
        truncating one here instead would be a second, contradictory
        presentation policy on the same card.
      * a phrase chosen from a closed set is bounded by construction. No
        host-authored string reaches this line, so no host can widen the
        card by writing a longer finding - which is the failure D4 is
        undoing.

    The chrome stays dashed and the badge still counts, so the card says it
    is broken and how much is wrong with it; what it no longer does is say
    all of it at once.

    ## The container box

    A container draws a box around its body only when it is a BOUNDARY, and
    `ViewModel.boundary?/1` is the whole of that question: the node has a slot
    in the rail partition (ADR-0005 decision 10c, as amended by 10h, which
    widened the partition from `:secondary` to any rail style and left 10c's
    reason - an attached rule is about a region, so the region needs a visible
    edge - unchanged). This module stamps `sb-node--boundary` from that
    predicate and decides nothing else about it.

    Every other container draws no box, which is the rest of 10c: a box around
    each of them turns a deep document into nested rectangles that read as
    noise, and what an author needs to see there is the cards and the edges
    between them. The container's own card stays at the head of its body, so
    the block is still a thing on the canvas without its subtree being fenced.

    None of that is in this file beyond the class and `data-container`: the
    box is paint, the stylesheet owns paint, and a host restyling the editor
    reads the same two hooks the package's own stylesheet does.

    ## The delete affordance (operator ruling R2, campaign 016)

    "`x` on hover, `-` + `x` on the selected card, nothing at rest." A
    delete control on every one of forty cards at rest is noise competing
    with the workflow itself.

    Hidden by opacity and by nothing else. `display: none` and
    `visibility: hidden` both take the button out of the tab order, which
    would make deleting a block a pointer-only gesture - so the rest state
    is a control that is present, focusable, and revealed by `:focus-visible`
    the moment a keyboard reaches it. `data-reveal` on the button is what the
    stylesheet's rest rule selects and what the presentation test asserts,
    so the contract is one string rather than a computed style nothing can
    check.

    The `-` half of R2 now ships too, on container chrome only, as
    `.sb-node__fold`. It is not a fifth command: ADR-0005's command set is
    still `:insert`, `:move`, `:remove`, `:update_config`, and which
    containers are folded shut is editor state the shell holds beside the
    selection (the amendment to decision 2, 2026-08-30). The fold is a native
    `<button>` carrying `aria-expanded`, so Enter and Space are the browser's
    and no window key binding exists. Its rest state differs from the `x` in
    one way the stylesheet reads off `data-reveal`: revealed on hover or
    selection while the container is open, and **always** visible while it is
    shut, because a control that hides a region has to be the way back.

    ## Unresolvable blocks (decision 12)

    A block whose type does not resolve renders rather than vanishing: its
    type name, unavailable chrome, one reason line, and **its existing
    children rendered normally, recursively** - the document's `slots` map
    preserved every one of them, decoding never having consulted a registry.

    Its findings and its config read-only as canonical JSON (there is no
    `config_schema/1` to drive a form and inventing one would be guessing)
    are still rendered, and still nowhere else in the editor - campaign-017
    ruling D4 moved them from this card to the inspector's Block and Findings
    sections, for the reason the card-face section above gives. Decision 12's
    "nothing is lost" is unchanged by that; what changed is which surface
    shows it.

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

    ## The badge, and the one face that carries it

    ADR-0005 puts the count badge on a **collapsed** subtree (:461, :1457):
    `findings_count` covers a whole subtree precisely so that a node folded
    shut can still say something inside it needs attention. Decision 11's last
    sentence is what that is for - a finding must never hide inside something
    folded shut, which is the failure mode that makes tree editors feel
    unreliable.

    So `.sb-badge` renders on a **collapsed** container whose subtree rollup is
    greater than zero, and nowhere else: never on an expanded face, and never
    at a count of zero. What shipped before `sb-vamn` was a badge on every
    container whenever its rollup was non-zero, which is not what the record
    says and read as an error on every container face as the counts multiplied
    up the tree; `sb-vamn` removed it and left the class as the seam this
    renders into.

    The rollup itself is unchanged and is still on every node as
    `data-findings-count`, expanded or not, so the drawer's Findings tab and
    the inspector's grouping read exactly what they read before. The badge is
    a **ring** rather than a fill - the treatment :1233-1235 argues for, and
    the reason `--sb-fg-on-accent` had no consumer left to justify it.
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

    attr(:collapsed, :any,
      default: nil,
      doc: """
      The `MapSet` of block ids the author has folded shut, threaded down the
      recursion the way `selected_id` is. A node reads its own membership and
      passes the whole set on; nothing here holds state.
      """
    )

    attr(:armed, :any,
      default: nil,
      doc: "The `{parent_id, slot, index}` the palette is armed at, passed through to `Slot`."
    )

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

    attr(:depth, :integer,
      default: 0,
      doc: """
      How many slots this node sits inside, counted from the root. The
      recursion carries it because nothing else can: `Shell.depth/1` is a
      subtree MAXIMUM for the toolbar, and a node has no way of asking where
      it is from inside its own render. `Slot` stamps it and the stylesheet
      bands on it (sb-d7g).
      """
    )

    @doc "One block: chrome, findings, and its slots, recursively."
    def block_node(assigns) do
      assigns = assign(assigns, :collapsed?, collapsed?(assigns.node, assigns.collapsed))

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
        data-container={to_string(container?(@node))}
        data-collapsed={to_string(@collapsed?)}
        data-arrangement={ViewModel.arrangement(@node)}
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
            {ViewModel.title(@node)}
          </button>
          <span :if={ViewModel.subtitle(@node)} class="sb-node__type">
            {ViewModel.subtitle(@node)}
          </span>
          <div :if={ViewModel.summary_chips(@node) != []} class="sb-node__summary">
            <span :for={chip <- ViewModel.summary_chips(@node)} class="sb-node__chip">
              {chip}
            </span>
          </div>
          <span :if={@node.invoke_type} class="sb-node__invoke">{@node.invoke_type}</span>
          <button
            :if={container?(@node)}
            type="button"
            class="sb-node__fold"
            data-reveal={if @collapsed?, do: "always", else: "hover-or-selected"}
            aria-expanded={to_string(not @collapsed?)}
            aria-label={fold_label(@collapsed?) <> " " <> ViewModel.title(@node)}
            title={fold_label(@collapsed?)}
            phx-click="collapse-toggle"
            phx-target={@target}
            phx-value-block-id={@node.block_id}
          >
            {if @collapsed?, do: "+", else: "-"}
          </button>
          <span :if={@collapsed? and @node.findings_count > 0} class="sb-badge">
            {@node.findings_count}
          </span>
          <button
            :if={not @root?}
            type="button"
            class="sb-node__remove"
            data-reveal="hover-or-selected"
            aria-label={"Delete " <> ViewModel.title(@node)}
            title="Delete"
            phx-click="remove"
            phx-target={@target}
            phx-value-block-id={@node.block_id}
          >
            x
          </button>
        </div>

        <p :if={unresolvable?(@node)} class="sb-node__reason">{reason_line(@node)}</p>

        <p :for={finding <- face_findings(@node)} class={["sb-finding", severity_class(finding)]}>
          {finding.message}
        </p>

        <div
          :if={not @collapsed? and ViewModel.fan_label(@node)}
          class="sb-node__fan"
          data-sb-anchor={Connectors.fan_anchor(@node.block_id)}
        >
          <span class="sb-node__fan-label">{ViewModel.fan_label(@node)}</span>
        </div>

        <div
          :if={not @collapsed?}
          class={["sb-node__slots", layout_class(@node)]}
          data-sb-anchor={Connectors.slots_anchor(@node.block_id)}
        >
          <Slot.slot
            :for={slot <- @node.slots}
            slot={slot}
            depth={@depth}
            parent_id={@node.block_id}
            drag={@drag}
            selected_id={@selected_id}
            collapsed={@collapsed}
            armed={@armed}
            target={@target}
            icon={@icon}
          />
        </div>

        <div
          :if={not @collapsed? and join_label(@node)}
          class="sb-node__join"
          data-sb-anchor={Connectors.join_anchor(@node.block_id)}
        >
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

    # A container is a node with at least one declared slot, which is exactly
    # what `data-container` has always said. A container with an empty subtree
    # is still a container and may still fold: what folds is the region, not
    # the children that happen to be in it.
    @spec container?(ViewModel.Node.t()) :: boolean()
    defp container?(%ViewModel.Node{slots: slots}), do: slots != []

    # A leaf is never collapsed, whatever the set says. It renders no fold
    # button, so nothing can put it in there - and a set that somehow held one
    # would otherwise hide a card with no way to get it back.
    @spec collapsed?(ViewModel.Node.t(), MapSet.t(String.t()) | nil) :: boolean()
    defp collapsed?(_node, nil), do: false

    defp collapsed?(%ViewModel.Node{} = node, collapsed),
      do: container?(node) and MapSet.member?(collapsed, node.block_id)

    @spec fold_label(boolean()) :: String.t()
    defp fold_label(true), do: "Expand"
    defp fold_label(false), do: "Collapse"

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

    # D4's split, stated once. A resolvable card still reads its findings on
    # the face - a lint on a `core.wait` is one line and belongs where the
    # author is looking. An unresolvable card reads the reason line above
    # instead, and every one of its findings is in the inspector's Findings
    # tab, counted by the badge the chrome already draws.
    @spec face_findings(ViewModel.Node.t()) :: [StatifierBlocks.Finding.t()]
    defp face_findings(%ViewModel.Node{status: {:unresolvable, _reason}}), do: []
    defp face_findings(%ViewModel.Node{findings: findings}), do: findings

    # The moduledoc says why this is a closed set of phrases rather than a
    # clipped finding. The three shapes are `Palette.resolve/2`'s own error
    # terms; the fourth clause is totality, not a guess - `status` is typed
    # `{:unresolvable, term()}`, so a card cannot be the thing that raises
    # when that set grows.
    @spec reason_line(ViewModel.Node.t()) :: String.t()
    defp reason_line(%ViewModel.Node{status: {:unresolvable, reason}}), do: reason_words(reason)

    @spec reason_words(term()) :: String.t()
    defp reason_words({:unknown_block_type, _type}), do: "type is not registered here"
    defp reason_words({:block_type_too_new, _id, _stored}), do: "stored by a newer version"
    defp reason_words({:migration_failed, _id, _reason}), do: "config migration failed"
    defp reason_words(_unnamed), do: "type did not resolve"

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

    # The slot box's arrangement, read off `ViewModel.arrangement/1` so the
    # class, the pill's words and the connector geometry cannot disagree
    # (ADR-0005 amendment 10b). A branch reaches `:fan` by declaring one slot
    # per arm and a parallel reaches `:lanes` by declaring `layout: :columns`;
    # both put their columns side by side, and neither is named here.
    #
    # Before campaign 016 only `:columns` was arranged, so a branch stacked
    # its arms full-width - every fan edge then ran straight down through the
    # arm above the one it was going to, which is the picture `sb-ay0`
    # recorded.
    #
    # One class, and `data-arrangement` on the card above carries which of the
    # two arranged answers it was. A `--fan` and a `--lanes` modifier here
    # would be a second spelling of a fact the attribute already states, and
    # the two spellings are one edit apart from disagreeing.
    @spec layout_class(ViewModel.Node.t()) :: String.t()
    defp layout_class(%ViewModel.Node{} = node) do
      case ViewModel.arrangement(node) do
        :stack -> "sb-node__slots--stack"
        _arranged -> "sb-node__slots--columns"
      end
    end

    # One place spells the severity modifiers, and it is outside
    # `StatifierBlocks.Editor.*` so it is asserted with LiveView absent
    # (ADR-0005 decision 11, amended 2026-08-29 for `:info`).
    @spec severity_class(StatifierBlocks.Finding.t()) :: String.t()
    defp severity_class(finding), do: StatifierBlocks.Finding.severity_class(finding)
  end
end
