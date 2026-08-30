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

    A row is severity, subject and message, in that order: the severity is
    what an author scans down, the subject is the block they will click, and
    the message is the sentence they read once they have found the row they
    want. The subject carries both the block's label and its id - the label is
    what they recognise, the id is what they will paste into a bug report.

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
      <div class="sb-findings" data-findings-count={length(@findings)}>
        <p :if={@findings == []} class="sb-drawer__empty sb-findings__empty">No findings.</p>
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
              class="sb-findings__reveal"
              phx-click="select"
              phx-target={@target}
              phx-value-block-id={block_id(finding)}
            >
              <.row finding={finding} root={@root} />
            </button>
            <span :if={MapSet.member?(@orphans, finding)} class="sb-findings__orphan">
              <.row finding={finding} root={@root} />
            </span>
          </li>
        </ul>
      </div>
      """
    end

    attr(:finding, Finding, required: true)
    attr(:root, ViewModel.Node, required: true)

    # An orphan's subject is its id and nothing else: `Shell.label_for/2` falls
    # back to the id for a block the tree does not hold, and a row reading
    # "blk_deleted_long_ago blk_deleted_long_ago" spends the subject column on
    # saying the same thing twice.
    #
    # Severity, subject, message. The severity is a word as well as the row's
    # colour, for the reason `Shell.cell_word/1` records about truth-table
    # cells: a reader who cannot tell two hues apart gets the same list as
    # everyone else. The colour itself stays on the row - `.sb-finding` and
    # its severity modifier, unchanged from when this list sat under the
    # canvas - so a host restyling one severity still restyles it in one
    # place.
    defp row(assigns) do
      id = block_id(assigns.finding)
      label = Shell.label_for(assigns.root, id)

      assigns =
        assigns |> assign(:block_id, id) |> assign(:label, if(label == id, do: nil, else: label))

      ~H"""
      <span class="sb-findings__severity">{@finding.severity}</span>
      <span class="sb-findings__subject">
        <span :if={@label} class="sb-findings__label">{@label}</span>
        <span class="sb-findings__id">{@block_id}</span>
      </span>
      <span class="sb-findings__message">{@finding.message}</span>
      """
    end

    @spec block_id(Finding.t()) :: StatifierBlocks.Block.id()
    defp block_id(%Finding{anchor: {:config, id, _key}}), do: id
    defp block_id(%Finding{anchor: {:slot, id, _name}}), do: id
    defp block_id(%Finding{anchor: {:block, id}}), do: id

    @spec anchor_tag(Finding.t()) :: String.t()
    defp anchor_tag(%Finding{anchor: {:config, id, key}}), do: "config:#{id}:#{key}"
    defp anchor_tag(%Finding{anchor: {:slot, id, name}}), do: "slot:#{id}:#{name}"
    defp anchor_tag(%Finding{anchor: {:block, id}}), do: "block:#{id}"
  end
end
