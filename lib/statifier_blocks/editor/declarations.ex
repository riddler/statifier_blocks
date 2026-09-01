if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.Declarations do
    @moduledoc """
    The declarations panel: the document's own `datamodel` roots, added,
    edited and reordered in the drawer (ADR-0005's 2026-09-01 amendment,
    clauses 2i-2m; the key itself is ADR-0001 decision 11).

    ADR-0001's 11i named this surface and declined to design it - "A host
    may now carry roots in the tree the author edits rather than in the
    publish call, which is what makes an editor able to show and edit them
    one day. **No editor surface is proposed here**; that is ADR-0005's,
    when taken." This is that surface.

    ## Why it is a drawer tab

    1A's admission test is two words, tabular and document-level, and a
    declaration list passes both without an argument: it is a grid of rows -
    a name, an initial value, a description - and it is about the envelope,
    which is the whole document rather than any block in it. 3A keeps it out
    of the inspector for the same reason it kept Datamodel and Fixtures out:
    those tabs were never about the selected block.

    It fills the place 1A reserved for "the datamodel declared-path view",
    and it is not that view. The reserved sentence described a read-only
    report over every declared path, which under the 11k union would mean
    three sources at once - the host's datamodel, the compile call's
    `:declare` roots and this key. What ships here is the one source an
    author can actually change. The report is still unbuilt and this section
    reserves nothing for it.

    ## What a row is, and what it is not

    Three fields, because ADR-0001 11b gives an entry three: a required `id`,
    an optional `expr` the root starts with, and an optional `description`
    that is prose for a reader and never reaches the chart. No `type`, no
    `label`, no `one_of`, no `sensitive?` - 11b refuses all four in the
    model, and offering a box for one here would grow the second, thinner
    datamodel vocabulary beside ADR-0006's that both records exist to
    prevent.

    ## Reorder is buttons

    Decision 7 ships exactly one JavaScript hook, on the canvas's cards, and
    a second drag surface would be a second hook or a widening of the first.
    Neither is bought by a list of three rows. Up and down are native
    buttons, and decision 8's rule that every drop target is reachable
    without dragging is met here by construction rather than by a parallel
    path: there is no gap, no slot and no geometry, so the button is not the
    fallback - it is the gesture.

    Order is load-bearing all the same. It is the emission order of the
    document's `<data>` elements (ADR-0001 11a), which is why moving a row is
    a document edit on the undo stack and not a display preference.

    ## Every field is a form, and a refusal is shown here

    Editing sends `phx-change`, which is `ConfigForm`'s shape and for
    `ConfigForm`'s reason. A refused change is held as a draft and the
    sentence saying why is rendered in this panel: decision 11's anchors name
    a block, a slot or a config key, and none of them can name a declaration
    entry, so a refusal here is not a finding and never enters the findings
    pipeline. `StatifierBlocks.Declarations.refusal/1` is the one place a
    refusal becomes a sentence.
    """

    use Phoenix.Component

    alias StatifierBlocks.Document.DatamodelEntry

    attr(:entries, :list,
      required: true,
      doc: """
      The entries to draw: the document's `datamodel`, or the draft list an
      author is mid-edit on. The panel never reads the document itself -
      which list is showing is the editor's decision, made once.
      """
    )

    attr(:refusal, :string,
      default: nil,
      doc: "the sentence for a refused change, or `nil` when the document holds what is drawn"
    )

    attr(:target, :any, required: true)

    @doc "The declarations table: one row per declared root, plus the Add control."
    def declarations(assigns) do
      ~H"""
      <div class="sb-declarations" data-count={length(@entries)}>
        <p :if={@refusal} class="sb-declarations__refusal" role="status">{@refusal}</p>

        <p :if={@entries == []} class="sb-drawer__empty">
          This document declares no roots of its own. A root declared here exists in
          every run of the document, and the compile call can still declare more.
        </p>

        <div :if={@entries != []} class="sb-declarations__scroll">
          <table>
            <thead>
              <tr>
                <th scope="col">Name</th>
                <th scope="col">Initial value</th>
                <th scope="col">Description</th>
                <th scope="col"><span class="sb-declarations__actions-head">Order</span></th>
              </tr>
            </thead>
            <tbody>
              <.row
                :for={{entry, index} <- Enum.with_index(@entries)}
                entry={entry}
                index={index}
                last={index == length(@entries) - 1}
                target={@target}
              />
            </tbody>
          </table>
        </div>

        <button
          type="button"
          class="sb-declarations__add"
          phx-click="declaration-add"
          phx-target={@target}
        >
          Add a declaration
        </button>
      </div>
      """
    end

    attr(:entry, DatamodelEntry, required: true)
    attr(:index, :integer, required: true)
    attr(:last, :boolean, required: true)
    attr(:target, :any, required: true)

    # One form per row rather than one for the panel. The index is a hidden
    # input rather than a `phx-value-index`, because a form's change payload
    # carries its inputs and not the attributes on the element - the value
    # has to be in the form to arrive with it.
    defp row(assigns) do
      ~H"""
      <tr class="sb-declarations__row" data-index={@index} data-id={@entry.id}>
        <td colspan="3" class="sb-declarations__fields">
          <form
            id={"sb-declaration-#{@index}"}
            class="sb-declarations__form"
            phx-change="declaration-change"
            phx-submit="declaration-change"
            phx-target={@target}
          >
            <input type="hidden" name="index" value={@index} />

            <label class="sb-declarations__field">
              <span class="sb-declarations__label">Name</span>
              <input
                type="text"
                name="name"
                value={@entry.id}
                autocomplete="off"
                spellcheck="false"
                aria-label={"Name of declaration #{@index + 1}"}
              />
            </label>

            <label class="sb-declarations__field">
              <span class="sb-declarations__label">Initial value</span>
              <input
                type="text"
                name="expr"
                value={@entry.expr}
                autocomplete="off"
                spellcheck="false"
                aria-label={"Initial value of declaration #{@index + 1}"}
              />
            </label>

            <label class="sb-declarations__field">
              <span class="sb-declarations__label">Description</span>
              <input
                type="text"
                name="description"
                value={@entry.description}
                aria-label={"Description of declaration #{@index + 1}"}
              />
            </label>
          </form>
        </td>

        <td class="sb-declarations__actions">
          <button
            type="button"
            class="sb-declarations__move"
            phx-click="declaration-move"
            phx-value-index={@index}
            phx-value-dir="up"
            phx-target={@target}
            disabled={@index == 0}
            aria-label={"Move declaration #{@index + 1} earlier"}
          >
            Up
          </button>
          <button
            type="button"
            class="sb-declarations__move"
            phx-click="declaration-move"
            phx-value-index={@index}
            phx-value-dir="down"
            phx-target={@target}
            disabled={@last}
            aria-label={"Move declaration #{@index + 1} later"}
          >
            Down
          </button>
          <button
            type="button"
            class="sb-declarations__remove"
            phx-click="declaration-remove"
            phx-value-index={@index}
            phx-target={@target}
            aria-label={"Remove declaration #{@index + 1}"}
          >
            Remove
          </button>
        </td>
      </tr>
      """
    end
  end
end
