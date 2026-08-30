if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.Inspector do
    @moduledoc """
    The tabbed inspector: Config, Findings, Condition (ADR-0005, the 2026-08-29
    shell amendment, ruling 3A).

    3A is one rule and a list, and the rule is the part that matters: **the
    inspector is about the selected block, and anything about the document goes
    to the drawer.** The list of three tabs follows from it rather than the
    other way round, which is why Datamodel and Fixtures - inspector tabs in
    the spike - are drawer tabs here. They were never about the selected block.

    Two things a reader will look for and not find:

      * There is no fourth tab and no `:if` that would add one. A pane that is
        about the document has one place to go, and 3A exists so that "which
        inspector tab does this become" stops being asked.
      * The Findings tab is **not** the document-level findings panel decision
        13 names. That panel still exists, still lists every finding in the
        document, and still lives beside the canvas. This tab is the selected
        block's own findings, which is the distinction the campaign-014 polish
        pass filed as `sb-3l1` item a.

    ## The Condition tab reads; it does not evaluate

    It renders the per-arm predicator source the block carries, one entry per
    `:expression` field, and it evaluates nothing. Evaluation is
    `StatifierBlocks.Predicates`, it is server-side, and what it produces - a
    truth table - is tabular and document-level, so 1A puts it in the drawer.
    The tab that shows an author what a branch asks and the drawer that shows
    what it answers are different surfaces on purpose.

    Editing a condition stays on the Config tab, where every other field is
    edited, so there is exactly one form in the editor and one place a draft
    can live (decision 9).

    ## The pane header, and what its status says (parity item 1.1)

    Above the tabs sits the pane's own header row: the name of the pane, and a
    right-aligned status. The status is the inspector's subject stated in
    words - the selected block's type label, or `no selection` - and it is
    there because 3A's rule ("the inspector is about the selected block") is
    invisible in an empty pane otherwise: three tabs with nothing under them
    do not say whether the author has selected nothing or selected something
    that has nothing to show.

    It reads the **type's label**, not the block's id. A label is what the
    author picked the block by in the palette and what its card reads on the
    canvas, so the header names the block in the vocabulary the rest of the
    editor already uses. An unresolvable block reaches the placeholder entry
    by the ordinary route and falls back to its raw type name, which is the
    only thing about it that is still known.

    The inspector has no collapse. The palette's fold is the wide
    arrangement's answer to a cramped canvas and one pane is enough of an
    answer; a second one is a separate ruling and is not made here.

    ## The Config tab's two sections (parity item 1.9)

    Under the tabs the Config tab is two labelled sections rather than a form
    dropped into a pane. **Block** states what the pane's subject IS - its
    type, its id, and the slot it sits in - and **Configuration** holds the
    form.

    The Block section is the one that has to be there when nothing is
    selected, which is why its three rows render either way and read as a
    dash when they have no value. A section that appears and disappears with
    the selection teaches an author nothing about what the pane will show
    them; three rows that are always in the same place, sometimes empty, say
    what the inspector is about before they have selected anything.

    The three rows are deliberately the three an author can act on. `Type` is
    the type's label, the same string the header status reads, so the pane
    names the block the way the palette and the canvas do. `Id` is the block
    id verbatim and set in mono, because it is the string that appears in a
    finding, in a provenance map and in a URL, and an author reading one of
    those needs to match it character for character. `Slot` is the slot's
    label - `StatifierBlocks.Shell.slot_label/2`'s answer - because a card
    seen on its own does not say which arm of a branch it is in.

    Under the three rows, and only for a block whose type did not resolve,
    the Block section holds that block's **stored config as canonical JSON**
    (campaign-017 ruling D4). It used to sit on the card, where it made the
    one broken block the widest thing in its lane; it is the same bytes in
    the same order, moved to the surface an author reaches by asking about
    that block in particular. It is read-only here for the reason the Config
    tab is empty there: nothing declares which of those values are editable,
    and a form over them would be invented rather than derived.

    It is the only thing in this pane that wraps mid-token. A block id
    ellipsises and a condition source scrolls, because both are strings an
    author matches character by character and neither is long by design; a
    stored config carries whatever the host that wrote it carried, so the
    only two honest choices are wrapping anywhere and clipping bytes the
    author is here to read.

    The Configuration section's empty state is a **box**, not the one-line
    sentence the other tabs use. It is the only empty state in the editor
    standing where a control would be, and an unboxed sentence in that
    position reads as a caption for the form below it rather than as the
    reason there is no form.
    """

    use Phoenix.Component

    alias StatifierBlocks.Editor.ConfigForm
    alias StatifierBlocks.{Finding, Shell, ViewModel}

    attr(:tab, :atom, required: true)
    attr(:node, :any, default: nil, doc: "the selected `ViewModel.Node`, or nil")

    attr(:slot_label, :any,
      default: nil,
      doc: "`Shell.slot_label/2` for the selection - the slot it sits in, or nil"
    )

    attr(:pending, :list, default: [])
    attr(:expression_component, :any, default: nil)
    attr(:target, :any, required: true)
    attr(:class, :string, default: nil)

    @doc "The three tabs and the panel of whichever one is showing."
    def inspector(assigns) do
      assigns =
        assigns
        |> assign(:findings, Shell.block_findings(assigns.node))
        |> assign(:conditions, Shell.condition_fields(assigns.node && assigns.node.form))

      ~H"""
      <section
        class={["sb-inspector", @class]}
        data-tab={@tab}
        data-block-id={@node && @node.block_id}
      >
        <div class="sb-inspector__header">
          <h2 class="sb-inspector__title">Inspector</h2>
          <span class="sb-inspector__status" data-selected={to_string(@node != nil)}>
            {selection_status(@node)}
          </span>
        </div>

        <div class="sb-inspector__tabs" role="tablist" aria-label="Inspector">
          <button
            :for={tab <- Shell.inspector_tabs()}
            type="button"
            role="tab"
            id={"sb-inspector-tab-#{tab}"}
            class={["sb-inspector__tab", @tab == tab && "sb-inspector__tab--selected"]}
            aria-selected={to_string(@tab == tab)}
            aria-controls={"sb-inspector-panel-#{tab}"}
            tabindex={if @tab == tab, do: "0", else: "-1"}
            phx-click="inspector-tab"
            phx-value-tab={tab}
            phx-target={@target}
          >
            {label(tab)}
            <span :if={tab == :findings and @findings != []} class="sb-inspector__tab-count">
              {length(@findings)}
            </span>
          </button>
        </div>

        <div
          class="sb-inspector__panel"
          role="tabpanel"
          id={"sb-inspector-panel-#{@tab}"}
          aria-labelledby={"sb-inspector-tab-#{@tab}"}
        >
          <p :if={@node == nil and @tab != :config} class="sb-inspector__empty">
            Select a block on the canvas to inspect it.
          </p>

          <.block_section :if={@tab == :config} node={@node} slot_label={@slot_label} />

          <section :if={@tab == :config} class="sb-inspector__section">
            <h3 class="sb-inspector__section-title">Configuration</h3>
            <p :if={@node == nil} class="sb-inspector__empty sb-inspector__empty--boxed">
              Select a block on the canvas to edit its configuration.
            </p>
            <.config_panel
              :if={@node != nil}
              node={@node}
              pending={@pending}
              expression_component={@expression_component}
              target={@target}
            />
          </section>

          <.findings_panel :if={@node != nil and @tab == :findings} findings={@findings} />
          <.condition_panel
            :if={@node != nil and @tab == :condition}
            node={@node}
            conditions={@conditions}
          />
        </div>
      </section>
      """
    end

    attr(:node, :any, required: true)
    attr(:slot_label, :any, required: true)

    # Rendered with `node: nil` too - see the moduledoc. The rows read a dash
    # then, and they are the same three rows in the same order, so the pane's
    # shape does not change under the author when they click a card.
    defp block_section(assigns) do
      ~H"""
      <section class="sb-inspector__section">
        <h3 class="sb-inspector__section-title">Block</h3>
        <dl class="sb-inspector__meta">
          <.meta_row label="Type" value={@node && selection_status(@node)} />
          <.meta_row label="Id" value={@node && @node.block_id} mono />
          <.meta_row label="Slot" value={@node && @slot_label} />
        </dl>
        <pre :if={@node && @node.raw_config_json} class="sb-inspector__raw-config">{@node.raw_config_json}</pre>
      </section>
      """
    end

    attr(:label, :string, required: true)
    attr(:value, :any, required: true)
    attr(:mono, :boolean, default: false)

    # The dash is markup rather than a `::before`, so what an author reads is
    # what a test reads; `data-empty` is what the CSS and a host style against,
    # for the same reason the condition source stamps one.
    defp meta_row(assigns) do
      ~H"""
      <div class="sb-inspector__meta-row">
        <dt class="sb-inspector__meta-key">{@label}</dt>
        <dd
          class={["sb-inspector__meta-value", @mono && "sb-inspector__meta-value--mono"]}
          data-empty={to_string(@value in [nil, ""])}
        >
          <span :if={@value in [nil, ""]} class="sb-inspector__meta-dash">&mdash;</span>{@value}
        </dd>
      </div>
      """
    end

    attr(:node, ViewModel.Node, required: true)
    attr(:pending, :list, required: true)
    attr(:expression_component, :any, required: true)
    attr(:target, :any, required: true)

    # Decision 12's read-only case reaches here as `form: nil`, and it is the
    # ConfigForm's own message rather than a second one written here: the tab
    # says why there is nothing to edit, and points at the Block section
    # above, which is where D4 moved the bytes themselves.
    defp config_panel(assigns) do
      ~H"""
      <ConfigForm.config_form
        :if={@node.form}
        node={@node}
        target={@target}
        pending={@pending}
        expression_component={@expression_component}
      />
      <p :if={@node.form == nil} class="sb-inspector__empty">
        This block's type is not registered here, so nothing declares which of its
        stored values are editable. Its config is preserved, and shown as stored
        under Block above.
      </p>
      """
    end

    attr(:findings, :list, required: true)

    defp findings_panel(assigns) do
      ~H"""
      <p :if={@findings == []} class="sb-inspector__empty">No findings on this block.</p>
      <ul :if={@findings != []} class="sb-inspector__findings">
        <li
          :for={finding <- @findings}
          class={["sb-finding", Finding.severity_class(finding)]}
          data-source={finding.source}
          data-severity={finding.severity}
        >
          {finding.message}
        </li>
      </ul>
      """
    end

    attr(:node, ViewModel.Node, required: true)
    attr(:conditions, :list, required: true)

    # One entry per `:expression` field, which for `core.branch` is one per arm
    # and in the arms' stored order - the order the branch tries them in, so
    # reading down the list is reading the branch.
    defp condition_panel(assigns) do
      ~H"""
      <ol :if={@conditions != []} class="sb-conditions">
        <li :for={field <- @conditions} class="sb-condition" data-field-key={field.key}>
          <span class="sb-condition__label">{field.label}</span>
          <code class="sb-condition__source" data-empty={to_string(field.value in [nil, ""])}>{Shell.condition_source(
            field
          )}</code>
        </li>
      </ol>

      <div :if={@conditions == []} class="sb-inspector__empty">
        <p>This block carries no condition.</p>
        <p class="sb-condition__where">
          Conditions live on a branch's arms - one per arm, deciding which way the
          chart goes - and on the guarded rules attached to a container's rail.
          Select one of those to read its condition here.
        </p>
      </div>
      """
    end

    # The header's subject, in the vocabulary the palette and the canvas use.
    # `entry.label` is decision 10's default-applied label, so it is a string
    # for every resolvable block; the fall through to `type` is the
    # unresolvable case, whose entry is the placeholder's.
    @spec selection_status(ViewModel.Node.t() | nil) :: String.t()
    defp selection_status(nil), do: "no selection"

    defp selection_status(%ViewModel.Node{} = node) do
      case Map.get(node.entry, :label) do
        label when is_binary(label) and label != "" -> label
        _none -> node.type
      end
    end

    @spec label(Shell.inspector_tab()) :: String.t()
    defp label(:config), do: "Config"
    defp label(:findings), do: "Findings"
    defp label(:condition), do: "Condition"
  end
end
