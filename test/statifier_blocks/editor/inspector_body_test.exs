# ADR-0005 decision 1: with `phoenix_live_view` absent the editor does not
# compile, so neither can a test that drives it. The `:liveview` tag on
# `StatifierBlocks.EditorLiveCase` excludes these from a headless *run*; this
# guard is what keeps them out of a headless *compile*.
if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.InspectorBodyTest do
    @moduledoc """
    The Config tab's two sections, the required tag and the Findings badge
    (parity item 1.9).

    Asserted against the components rather than through a mounted editor, for
    the reason the pane headers are: this is presentation with no state of its
    own beyond the assigns it is handed. Where the slot label comes FROM is
    `StatifierBlocks.Shell.slot_label/2` and is asserted headless in
    `StatifierBlocks.ShellTest`; what this file asserts is that the three rows
    exist, keep their order, and read a dash when they have nothing to say.

    The empty case is the half worth having twice. A section that renders only
    when something is selected passes every test written against a selection
    and still leaves an author looking at a pane that says nothing.
    """

    use StatifierBlocks.EditorLiveCase

    alias StatifierBlocks.Editor.{Field, Inspector}
    alias StatifierBlocks.{Finding, Shell, ViewModel}

    # One meta row's rendered value, with the markup around it taken off, so an
    # assertion is about what an author reads rather than about how the
    # formatter chose to indent a `<dd>`.
    defp meta_value(html, label) do
      [_whole, value] =
        Regex.run(
          ~r{<dt class="sb-inspector__meta-key">#{label}</dt>\s*<dd[^>]*>(.*?)</dd>}s,
          html
        )

      value |> String.replace(~r{<[^>]*>}, "") |> String.trim()
    end

    defp view_model(findings) do
      ViewModel.build(EditorFixtures.signup_wizard(), EditorFixtures.palette(), findings)
    end

    defp node_for(block_id, findings \\ []) do
      findings |> view_model() |> Map.fetch!(:root) |> find_node(block_id)
    end

    defp find_node(%ViewModel.Node{block_id: id} = node, id), do: node

    defp find_node(%ViewModel.Node{} = node, id) do
      node.slots
      |> Enum.flat_map(& &1.children)
      |> Enum.find_value(&find_node(&1, id))
    end

    # One field on its own, so the required tag is asserted against a field
    # that declares it and one that does not - the fixtures have no optional
    # field, and a form of one required field cannot tell the tag's `:if` from
    # a tag rendered unconditionally.
    defp field_html(required?) do
      render_component(&Field.field/1,
        field: %ViewModel.Field{
          key: "duration",
          type: :string,
          label: "Wait for",
          required?: required?,
          default: "",
          value: "1h",
          value_path: ["duration"]
        },
        target: "#editor",
        expression_component: nil
      )
    end

    defp inspector_html(opts) do
      render_component(
        &Inspector.inspector/1,
        Keyword.merge([tab: :config, target: "#editor"], opts)
      )
    end

    describe "the BLOCK section" do
      # The three values are three different sources - the type's palette
      # label, the block id verbatim, and the containing slot's label - so an
      # implementation that reached for the wrong one of any of them renders
      # something visibly different here. `blk_email_step` is a `core.wait`
      # sitting in the slot named `body`, which is why "Wait" and "Steps" are
      # the assertions rather than "core.wait" and "body".
      # Sabotage: rendering `@node.type` in the Type row - the row reads
      # `core.wait` and this goes red, which is the pane naming the block in a
      # vocabulary the palette and the canvas never showed the author.
      test "states the type's label, the id, and the slot the block sits in" do
        html = inspector_html(node: node_for("blk_email_step"), slot_label: "Steps")

        assert html =~ ~s(<h3 class="sb-inspector__section-title">Block</h3>)
        assert meta_value(html, "Type") == "Wait"
        assert meta_value(html, "Id") == "blk_email_step"
        assert meta_value(html, "Slot") == "Steps"
      end

      # The id is the string that appears in a finding, in a provenance map and
      # in a URL, so it is the one row set in mono - matching it character for
      # character is what an author does with it.
      # Sabotage: dropping the `mono` attr from the Id row - the id is set in
      # the body face beside two other proportional rows and this goes red.
      test "sets the id in mono and nothing else" do
        html = inspector_html(node: node_for("blk_email_step"), slot_label: "Steps")

        assert html =~ ~s(class="sb-inspector__meta-value sb-inspector__meta-value--mono")
        assert length(Regex.scan(~r{sb-inspector__meta-value--mono}, html)) == 1
      end

      # The section is the pane's statement of what it is about, so it is there
      # before the author has selected anything - three rows in the same place,
      # reading as empty.
      # Sabotage: guarding the section with `:if={@node != nil}` - the rows
      # disappear with the selection and every assertion below goes red at
      # once, which is what an author would see as a pane that changes shape.
      test "renders with nothing selected, and its rows read as empty" do
        html = inspector_html(node: nil)

        assert html =~ ~s(<h3 class="sb-inspector__section-title">Block</h3>)
        assert meta_value(html, "Type") == "&mdash;"
        assert meta_value(html, "Id") == "&mdash;"
        assert meta_value(html, "Slot") == "&mdash;"
        assert length(Regex.scan(~r{data-empty="true"}, html)) == 3
      end

      # Campaign-017 ruling D4: the stored config sits under the three rows,
      # and only for the block that has one. A resolvable block's values are
      # in the form below; a pane that showed the JSON as well would be
      # saying the same thing twice, in the notation an author does not edit
      # in.
      # Sabotage: dropping the `:if` from the `<pre>` - it renders for
      # `blk_email_step` as an empty box under its rows, and this goes red on
      # a card that had nothing to preserve in the first place.
      test "holds the stored config, for an unresolvable block only" do
        unresolvable = inspector_html(node: node_for("blk_track_conversion"))

        assert unresolvable =~ ~s(class="sb-inspector__raw-config")
        assert unresolvable =~ "&quot;event&quot;:&quot;signup.completed&quot;"

        refute inspector_html(node: node_for("blk_email_step")) =~ "sb-inspector__raw-config"
        refute inspector_html(node: nil) =~ "sb-inspector__raw-config"
      end
    end

    describe "the CONFIGURATION section" do
      # The boxed sentence is the empty state that stands where a control
      # would, and it says what selecting a block would let the author DO -
      # which is a different sentence from the one the other tabs use.
      # Sabotage: reusing the one-line `sb-inspector__empty` without the
      # `--boxed` modifier - the sentence reads as a caption for whatever is
      # under it and the class assertion goes red.
      test "shows a boxed empty state when nothing is selected" do
        html = inspector_html(node: nil)

        assert html =~ ~s(<h3 class="sb-inspector__section-title">Configuration</h3>)
        assert html =~ ~s(class="sb-inspector__empty sb-inspector__empty--boxed")
        assert html =~ "Select a block on the canvas to edit its configuration."
        refute html =~ "Select a block on the canvas to inspect it."
      end

      # The Condition tab keeps the one-line sentence: its empty state is
      # "nothing to read", not "nothing to edit", and 3A's rule is stated once
      # per pane rather than once per tab. It used to be both of the other two;
      # sb-dbqq gave the Findings tab something to say with no selection, so the
      # sentence is asserted on the tab that still has nothing.
      # Sabotage: widening the guard back to `@tab != :config` - the Findings
      # tab renders this sentence above its grouped list and sb-dbqq's refute
      # goes red; narrowing it to `false` makes this assertion the red one.
      test "the Condition tab keeps the pane's one-line empty state" do
        html = inspector_html(node: nil, tab: :condition)

        assert html =~ "Select a block on the canvas to inspect it."
        refute html =~ "sb-inspector__empty--boxed"
      end

      # Sabotage: closing the section before the form - the pane renders a
      # `CONFIGURATION` label with nothing under it and the form floating below
      # both sections, and this goes red on the containment rather than on the
      # form being present at all, which is the part a `=~` over the whole pane
      # would not have noticed.
      test "wraps the selected block's form" do
        html = inspector_html(node: node_for("blk_email_step"), slot_label: "Steps")

        [_whole, inside] =
          Regex.run(~r{<h3[^>]*>Configuration</h3>(.*?)</section>}s, html)

        assert inside =~ ~s(id="sb-form-blk_email_step")
        refute html =~ "sb-inspector__empty--boxed"
      end
    end

    describe "a required field" do
      # The word rather than an asterisk: an asterisk has to be learned from a
      # legend the editor does not have, and it is read aloud as "star".
      # Sabotage: putting `*` back in the span - the assertion goes red on the
      # text, which is the whole of what this row changed.
      test "is marked with the word, not with an asterisk" do
        html = field_html(true)

        assert html =~ ~s(<span class="sb-field__required">Required</span>)
        refute html =~ ~s(<span class="sb-field__required">*</span>)
      end

      # Sabotage: dropping the `:if={@field.required?}` guard - every field is
      # marked and this goes red, which is a form where the mark means nothing.
      test "an optional field carries no tag at all" do
        refute field_html(false) =~ "sb-field__required"
      end

      # `core.wait`'s duration is `required?: true`, so the tag reaches a real
      # form by the ordinary route rather than only through a hand-built field.
      # Sabotage: rendering the label without the `sb-field__label-text` span -
      # the tag has nothing to sit beside in the flex row and this goes red on
      # the markup the CSS lays out.
      test "reaches the inspector's form from the block type's own schema" do
        html = inspector_html(node: node_for("blk_email_step"), slot_label: "Steps")

        assert html =~ ~s(<span class="sb-field__label-text">Wait for</span>)
        assert html =~ ~s(<span class="sb-field__required">Required</span>)
      end
    end

    describe "the Findings tab's count" do
      # The badge is the block's own findings, which is `Shell.block_findings/1`
      # and not the subtree's - the second finding here is on a block INSIDE
      # the branch precisely so a badge counting the subtree would read 2 and
      # report a child's problem on its parent.
      # Sabotage: counting `@node.findings_count` instead - the subtree number
      # is a different number for any container, and the badge starts reporting
      # a child's problem on its parent.
      test "counts the selected block's own findings" do
        findings = [
          Finding.new({:block, "blk_variant"}, :lint, "on the branch itself"),
          Finding.new({:block, "blk_variant_b_pause"}, :lint, "on a block inside it")
        ]

        html =
          inspector_html(
            node: node_for("blk_variant", findings),
            slot_label: "Steps",
            tab: :findings
          )

        assert html =~ ~s(class="sb-inspector__tab-count")

        [_whole, count] =
          Regex.run(~r{<span class="sb-inspector__tab-count">\s*(\d+)\s*</span>}s, html)

        assert count == "1"
      end

      # Sabotage: dropping the `@findings != []` guard - every block gets an
      # empty pill beside the Findings tab and this goes red, which is chrome
      # claiming there is something to fix on a document that is clean.
      test "is absent when the block has none" do
        html = inspector_html(node: node_for("blk_email_step"), tab: :findings)

        refute html =~ "sb-inspector__tab-count"
      end
    end

    # sb-dbqq. The grouping itself is `StatifierBlocks.ShellTest`'s and runs
    # headless; what is asserted here is the half that only exists once there
    # is markup - that the chip reads the document with nothing selected, that
    # the panel is the grouped list rather than a "select a block" line, and
    # that a row pushes the canvas's own select event.
    describe "the Findings tab with nothing selected (sb-dbqq)" do
      defp document_findings do
        [
          Finding.new({:block, "blk_variant"}, :lint, "no handler for this invoke type",
            severity: :warning
          ),
          Finding.new({:slot, "blk_wizard", "body"}, :assignability, "this slot wants a step"),
          Finding.new({:block, "blk_deleted_long_ago"}, :resolution, "no such block any more")
        ]
      end

      defp unselected_html(findings) do
        model = view_model(findings)

        inspector_html(
          node: nil,
          tab: :findings,
          root: model.root,
          document_findings: model.findings,
          orphan_findings: model.orphan_findings
        )
      end

      defp chip(html) do
        [_whole, count] =
          Regex.run(~r{<span class="sb-inspector__tab-count">\s*(\d+)\s*</span>}s, html)

        count
      end

      # The number is the document's and it is `Shell.findings_count/1`'s, not
      # a length taken at the chip: the wizard fixture derives a `:resolution`
      # finding of its own on top of the three passed in, so a chip counting
      # only what the caller supplied reads 3 where the drawer reads 4.
      # Sabotage: `tab_count/3`'s nil clause returning `length(block_findings)`
      # - the chip disappears entirely (no selection means no block findings)
      # and both assertions go red.
      test "the chip is the document's count, not the selection's" do
        model = view_model(document_findings())
        html = unselected_html(document_findings())

        assert chip(html) == to_string(Shell.findings_count(model.findings))
        assert chip(html) == "4"
      end

      # Sabotage: leaving the panel's `:if` at `@node == nil and @tab != :config`
      # on the "select a block" line - the tab goes back to the dead end this
      # bead is about and the refute goes red.
      test "the panel is the grouped list, not the select-a-block line" do
        html = unselected_html(document_findings())

        refute html =~ "Select a block on the canvas to inspect it."
        assert html =~ ~s(class="sb-inspector__groups")

        headings =
          Regex.scan(~r{<h3 class="sb-inspector__group-title">\s*(.*?)\s*</h3>}s, html)
          |> Enum.map(fn [_whole, heading] -> heading end)

        assert "Unanchored" in headings
        assert List.last(headings) == "Unanchored"
      end

      # Sabotage: rendering the unanchored group's rows as buttons too - the
      # refute goes red, and an author gets a control that selects a block the
      # document does not hold.
      test "an unanchored finding is listed with nothing to select" do
        html = unselected_html(document_findings())

        assert html =~ ~s(data-unanchored="true")

        # The unanchored group is last, so everything after its marker is that
        # group and the panel's closing tags - and none of it is a control.
        [_before, unanchored] = String.split(html, ~s(data-unanchored="true"), parts: 2)

        assert unanchored =~ "no such block any more"
        refute unanchored =~ "<button"
      end

      # The row reuses the canvas's select event rather than an inspector one,
      # so a block is selected the same way however an author reaches it.
      # Sabotage: the row pushing "inspector-select" instead of "select" - the
      # node never gains the selected class and this goes red.
      test "a row selects the block it is about", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, findings: document_findings())

        view |> element(~s(.sb-inspector__tab[phx-value-tab="findings"])) |> render_click()

        view
        |> element(
          ~s(.sb-inspector__group[data-block-id="blk_variant"] button.sb-inspector__group-row)
        )
        |> render_click()

        assert has_element?(view, ~s([data-block-id="blk_variant"].sb-node--selected))
      end
    end
  end
end
