if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.Findings do
    @moduledoc """
    The document-level findings panel (ADR-0005 decision 11).

    Decision 11 makes the anchor the whole routing mechanism, and the three
    inline positions - beneath a field, on a slot header, on a block's chrome
    - are rendered by the components that own those positions. What is left
    for this one is the list view: every finding in the document, in one
    place, where selecting one selects and reveals its anchor.

    Two cases are easy to render wrong and are handled explicitly.

    A finding whose anchor names a block id the document does not contain is
    an **orphan**. `StatifierBlocks.ViewModel` collects those separately
    rather than dropping them, and they are listed here without a reveal
    control, because there is nothing to reveal. A caller that supplies a
    finding against a block that has since been deleted sees it, which is the
    only honest thing to do with it.

    Severity is two-valued and every source except `:lint` produces
    `:error`. `:lint` exists because a block type can emit an invoke type for
    which the host has registered no runtime handler; it renders as a warning
    because a document carrying one is still compilable and still correct
    once the host registers the handler. Whether the lint belongs to the
    compiler or the editor is not this record's to settle - decision 11
    commits only to there being a place to put the answer, and this is it.
    """

    use Phoenix.Component

    alias StatifierBlocks.{Finding, ViewModel}

    attr(:view_model, ViewModel, required: true)
    attr(:target, :any, required: true)
    attr(:class, :string, default: nil)

    @doc "Every finding in the document, each one reachable from its entry."
    def findings(assigns) do
      assigns = assign(assigns, :orphans, MapSet.new(assigns.view_model.orphan_findings))

      ~H"""
      <section class={["sb-findings", @class]} data-findings-count={length(@view_model.findings)}>
        <h2 class="sb-findings__heading">Findings</h2>
        <p :if={@view_model.findings == []} class="sb-findings__empty">No findings.</p>
        <ul class="sb-findings__list">
          <li
            :for={finding <- @view_model.findings}
            class={["sb-finding", severity_class(finding)]}
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
              {finding.message}
            </button>
            <span :if={MapSet.member?(@orphans, finding)} class="sb-findings__orphan">
              {finding.message}
            </span>
          </li>
        </ul>
      </section>
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

    @spec severity_class(Finding.t()) :: String.t()
    defp severity_class(%Finding{severity: :warning}), do: "sb-finding--warning"
    defp severity_class(%Finding{}), do: "sb-finding--error"
  end
end
