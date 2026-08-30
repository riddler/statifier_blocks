if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.Findings do
    @moduledoc """
    The document-level findings list (ADR-0005 decision 11), rendered as the
    drawer's Findings tab.

    Decision 11 makes the anchor the whole routing mechanism, and the three
    inline positions - beneath a field, on a slot header, on a block's chrome
    - are rendered by the components that own those positions. What is left
    for this one is the list view: every finding in the document, in one
    place, where selecting one selects and reveals its anchor.

    ## Why it is a drawer tab

    It shipped as a text block under the canvas, and operator ruling R4
    (2026-08-29) retired that position: a list of findings is a grid of rows
    about the whole document, which is exactly 1A's admission test for the
    drawer, and the canvas is for the document rather than for a report about
    it. The inspector's Findings tab is unaffected and stays the **selected
    block's** findings (3A), as do the per-card counts - three positions for
    three scopes, which is the distinction that stopped being legible while a
    fourth list sat under the canvas saying "Findings" with no scope on it.

    A row is severity, subject, anchor tail, source and message, in that
    order, and `row/1` is where that anatomy is defined - for this list and
    for both of the inspector's findings panels, which called to render a
    finding and got the bare message until campaign-019 ruling D4. The
    severity is what an author scans down, the subject is the block they will
    click, the tail and the chip say which part of that block and who is
    complaining, and the message is the sentence they read once they have
    found the row they want. The subject carries both the block's label and
    its id - the label is what they recognise, the id is what they will paste
    into a bug report - and it is this list's column alone, because in the
    inspector the block is the group heading.

    Above the list, `severity_pills/1` renders `Shell.severity_counts/1` as a
    row of pills. The grouping is unchanged and still by block (D2): the
    pills say how much, the list says where.

    Two cases are easy to render wrong and are handled explicitly.

    A finding whose anchor names a block id the document does not contain is
    an **orphan**. `StatifierBlocks.ViewModel` collects those separately
    rather than dropping them, and they are listed here without a reveal
    control, because there is nothing to reveal. A caller that supplies a
    finding against a block that has since been deleted sees it, which is the
    only honest thing to do with it.

    Severity is three-valued since the 2026-08-29 amendments, and every
    source except `:lint` produces `:error`. `:lint` covers both of the
    others. It renders as a **warning** for something still compilable and
    correct once the host acts - the record's example, an invoke type with
    no registered handler. It renders as **`:info`** for something worth
    the author's attention with nothing wrong at all: the first producer is
    `StatifierBlocks.Datamodel`'s undeclared-path advisory (amendment
    11e-11g), which arrives here rather than through a channel of its own,
    because 11g says there is no second channel to build.

    Nothing in this panel branches on which of the two it is. The severity
    reaches the markup as a class and a `data-severity`, exactly as it did
    when there were two values, which is the property that let a third one
    be added without touching the list view.
    """

    use Phoenix.Component

    alias StatifierBlocks.{Finding, Shell, ViewModel}

    attr(:findings, :list, required: true)

    attr(:orphans, :any,
      required: true,
      doc: "a `MapSet` of the findings with no block to reveal"
    )

    attr(:root, ViewModel.Node, required: true)
    attr(:target, :any, required: true)

    @doc "Every finding in the document, each one reachable from its entry."
    def findings(assigns) do
      ~H"""
      <div class="sb-findings" data-findings-count={Shell.findings_count(@findings)}>
        <p :if={@findings == []} class="sb-drawer__empty sb-findings__empty">No findings.</p>
        <.severity_pills counts={Shell.severity_counts(@findings)} />
        <ul class="sb-findings__list">
          <li
            :for={finding <- @findings}
            class={["sb-finding", "sb-findings__row", Finding.severity_class(finding)]}
            data-source={finding.source}
            data-severity={finding.severity}
            data-anchor={anchor_tag(finding)}
            data-orphan={to_string(MapSet.member?(@orphans, finding))}
          >
            <button
              :if={not MapSet.member?(@orphans, finding)}
              type="button"
              class="sb-findings__reveal sb-findings__cells"
              phx-click="select"
              phx-target={@target}
              phx-value-block-id={block_id(finding)}
            >
              <.row finding={finding} root={@root} subject />
            </button>
            <span
              :if={MapSet.member?(@orphans, finding)}
              class="sb-findings__orphan sb-findings__cells"
            >
              <.row finding={finding} root={@root} subject />
            </span>
          </li>
        </ul>
      </div>
      """
    end

    attr(:counts, :list,
      required: true,
      doc: "`Shell.severity_counts/1`'s answer for the list the pills sit above"
    )

    @doc """
    How many findings there are at each severity, as a row of pills above the
    list.

    It renders on both document-level surfaces - this tab and the inspector's
    unselected Findings tab - because both are answering "what is wrong with
    this document", and a reader who has to count rows to learn there is one
    error among eleven advisories is reading the list to get a number that
    could have been given to them.

    It is not a filter. Nothing here is clickable, the list beneath is
    unchanged, and the grouping stays by block (`Shell.findings_groups/3`):
    the pills say how much, the groups say where. The spike grouped by
    severity instead, and campaign-019 ruling D2 did not adopt that - a
    severity is a property of a finding, and the thing an author acts on is
    the block.

    A severity with nothing at it has no pill; `Shell.severity_counts/1`
    documents why, and holds the invariant that the pills sum to the count on
    the tab beside them.
    """
    def severity_pills(assigns) do
      ~H"""
      <ul :if={@counts != []} class="sb-findings__pills">
        <li
          :for={pill <- @counts}
          class={["sb-finding", "sb-findings__pill", "sb-finding--#{pill.severity}"]}
          data-severity={pill.severity}
        >
          <span class="sb-findings__pill-count">{pill.count}</span>
          <span class="sb-findings__pill-label">{pill.severity}</span>
        </li>
      </ul>
      """
    end

    attr(:finding, Finding, required: true)

    attr(:root, :any,
      default: nil,
      doc: "the view model's root `ViewModel.Node`, read only for the subject's label"
    )

    attr(:subject, :boolean,
      default: false,
      doc: "render the block's label and id, which only the drawer's list carries"
    )

    @doc """
    One finding, in the anatomy every surface shows a finding in (D4).

    Severity, subject, anchor tail, source, message. There were three
    renderings of a finding before this one - this list's row, the
    inspector's selected-block panel and its document panel - and they
    disagreed: two of them were the bare message, so the same finding told an
    author three different amounts depending on which pane they happened to
    be reading. This is the single renderer all three call, which is what
    makes "what a finding looks like" a thing with one answer.

    * **Severity** is a word as well as the row's colour, for the reason
      `Shell.cell_word/1` records about truth-table cells: a reader who
      cannot tell two hues apart gets the same list as everyone else. It is
      the enum's own word - `error`, `warning`, `info` (ruling D3) - and not
      a synonym, so the word on screen is the value a host would match on.
      The colour stays on the row's own element (`.sb-finding` and its
      severity modifier), so a host restyling one severity restyles it in one
      place.
    * **Subject** is the block's label and its id, and it is the drawer's
      column alone. In the inspector the block is the group's heading, and a
      row repeating it under every heading would spend the widest column
      saying what the line above already said. An orphan's subject is its id
      and nothing else: `Shell.label_for/2` falls back to the id for a block
      the tree does not hold, and a row reading "blk_gone blk_gone" says the
      same thing twice.
    * **Anchor tail** is the part of the anchor the subject does not already
      carry - `config.duration` for a `{:config, id, key}`, `slot:body` for a
      `{:slot, id, name}`, and **nothing at all** for a `{:block, id}`, whose
      anchor is the subject. It is what tells an author whether a finding is
      about a field, a slot or the block itself, which is decision 11's whole
      routing rule made visible.
    * **Source** is the enum value, as a chip: `:config`, `:assignability`,
      `:resolution`, `:lint`, `:compile`. It answers "who says so", which is
      the question an author asks about a finding they disagree with.
    * **Message** is the sentence, and the only cell allowed to wrap.
    """
    def row(assigns) do
      id = block_id(assigns.finding)

      assigns =
        assigns
        |> assign(:block_id, id)
        |> assign(:label, subject_label(assigns, id))
        |> assign(:tail, anchor_tail(assigns.finding))

      ~H"""
      <span class="sb-findings__severity">{@finding.severity}</span>
      <span :if={@subject} class="sb-findings__subject">
        <span :if={@label} class="sb-findings__label">{@label}</span>
        <span class="sb-findings__id">{@block_id}</span>
      </span>
      <span :if={@tail} class="sb-findings__anchor">{@tail}</span>
      <span class="sb-findings__source">{@finding.source}</span>
      <span class="sb-findings__message">{@finding.message}</span>
      """
    end

    @doc """
    The whole anchor, flattened into one string, for the `data-anchor` a row
    is stamped with on every surface.

    It is the anchor and not a summary of it - block id included - because it
    is what a test, a host's stylesheet or a debugging author uses to name one
    row exactly. The `row/1` tail above is the reader-facing half of the same
    tuple; this is the machine-facing whole of it.
    """
    @spec anchor_tag(Finding.t()) :: String.t()
    def anchor_tag(%Finding{anchor: {:config, id, key}}), do: "config:#{id}:#{key}"
    def anchor_tag(%Finding{anchor: {:slot, id, name}}), do: "slot:#{id}:#{name}"
    def anchor_tag(%Finding{anchor: {:block, id}}), do: "block:#{id}"

    # Nothing to add for a `{:block, id}`: its anchor is the subject, and a
    # tail reading `block:blk_x` beside a subject reading `blk_x` is noise.
    @spec anchor_tail(Finding.t()) :: String.t() | nil
    defp anchor_tail(%Finding{anchor: {:config, _id, key}}), do: "config.#{key}"
    defp anchor_tail(%Finding{anchor: {:slot, _id, name}}), do: "slot:#{name}"
    defp anchor_tail(%Finding{anchor: {:block, _id}}), do: nil

    @spec subject_label(map(), StatifierBlocks.Block.id()) :: String.t() | nil
    defp subject_label(%{subject: true, root: %ViewModel.Node{} = root}, id) do
      case Shell.label_for(root, id) do
        ^id -> nil
        label -> label
      end
    end

    defp subject_label(_assigns, _id), do: nil

    @spec block_id(Finding.t()) :: StatifierBlocks.Block.id()
    defp block_id(%Finding{anchor: {:config, id, _key}}), do: id
    defp block_id(%Finding{anchor: {:slot, id, _name}}), do: id
    defp block_id(%Finding{anchor: {:block, id}}), do: id
  end
end
