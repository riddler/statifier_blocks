# ADR-0005 decision 1: with `phoenix_live_view` absent the editor does not
# compile, so neither can a test that drives it. The `:liveview` tag on
# `StatifierBlocks.EditorLiveCase` excludes these from a headless *run*; this
# guard is what keeps them out of a headless *compile*, which is the earlier
# of the two problems.
if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.PaneHeaderTest do
    @moduledoc """
    The two side panes' header rows, and both panes' folds - the palette's
    (parity item 1.1) and the inspector's (ADR-0005, the 2026-08-30 shell
    amendment, ruling 1B).

    The header rows are asserted against the components themselves rather than
    through a mounted editor, because that is what they are: presentation, with
    no state of their own beyond the assigns they are handed. The fold is the
    other kind and is driven through `LiveViewTest` - it is one more `phx-`
    event translated into one boolean, which is the only part of the shell
    amendment's gestures that has ever needed a connected mount.

    What the inspector's status says is the load-bearing assertion here. It is
    the **type's label**, not the block id and not the type name, and the third
    test is what separates those three: the fixture's `blk_email_step` is a
    `core.wait`, so an implementation that reached for either of the other two
    would render something visibly different from `Wait`.
    """

    use StatifierBlocks.EditorLiveCase

    alias StatifierBlocks.Editor.{Inspector, PaletteBrowser}
    alias StatifierBlocks.ViewModel

    # The header's rendered text, with the markup around it taken off, so an
    # assertion is about what an author reads rather than about how the
    # formatter chose to indent a one-element span.
    defp status_text(html) do
      [_whole, text] = Regex.run(~r{<span class="sb-inspector__status"[^>]*>(.*?)</span>}s, html)
      String.trim(text)
    end

    defp view_model do
      ViewModel.build(EditorFixtures.signup_wizard(), EditorFixtures.palette(), [])
    end

    defp node_for(block_id) do
      view_model()
      |> Map.fetch!(:root)
      |> find_node(block_id)
    end

    defp find_node(%ViewModel.Node{block_id: id} = node, id), do: node

    defp find_node(%ViewModel.Node{} = node, id) do
      node.slots
      |> Enum.flat_map(& &1.children)
      |> Enum.find_value(&find_node(&1, id))
    end

    defp palette_html(opts \\ []) do
      render_component(
        &PaletteBrowser.palette_browser/1,
        Keyword.merge([groups: view_model().palette_groups, target: "#editor"], opts)
      )
    end

    defp inspector_html(opts) do
      render_component(
        &Inspector.inspector/1,
        Keyword.merge([tab: :config, target: "#editor"], opts)
      )
    end

    describe "the palette's header row" do
      # Sabotage: deleting the `<h2 class="sb-palette__title">` from
      # `PaletteBrowser` - the pane loses the only thing that says which pane
      # it is, and this goes red on the title before the chevron assertions.
      test "names the pane and carries the fold's control" do
        html = palette_html()

        assert html =~ ~s(class="sb-palette__header")
        assert html =~ ~s(<h2 class="sb-palette__title">Palette</h2>)
        assert html =~ ~s(class="sb-palette__toggle")
        assert html =~ ~s(phx-click="palette-collapse")
      end

      # The control describes its EFFECT, which is the reading that survives an
      # author who arrived at an already-folded pane. Both directions are
      # asserted because a one-sided label is the defect that looks correct in
      # whichever state the author happened to open the editor in.
      # Sabotage: hard-coding `aria-label="Collapse the palette"` - the expanded
      # case still passes and the folded one goes red naming the wrong word.
      test "the chevron says what the press will do, in both states" do
        expanded = palette_html(collapsed: false)
        folded = palette_html(collapsed: true)

        assert expanded =~ ~s(aria-label="Collapse the palette")
        assert expanded =~ ~s(data-collapsed="false")

        assert folded =~ ~s(aria-label="Expand the palette")
        assert folded =~ ~s(data-collapsed="true")
      end

      # 7A is not disturbed: the strip and the sheet are still the palette's
      # narrow shape and the header is an addition beside them, not a
      # replacement for them.
      # Sabotage: renaming the strip's `palette-sheet` event, which is what a
      # rewrite that folded the strip into the new header would do - the sheet's
      # whole affordance disappears below 780 and this is what notices.
      test "the strip the narrow arrangement opens is still in the markup" do
        html = palette_html(sheet_open: true)

        assert html =~ ~s(phx-click="palette-sheet")
        assert html =~ ~s(data-sheet="open")
      end
    end

    describe "the inspector's header row" do
      # Sabotage: dropping the `sb-inspector__header` div - the pane goes back
      # to three tabs with no statement of its subject, which is what 3A is
      # invisible without.
      test "names the pane and says nothing is selected" do
        html = inspector_html(node: nil)

        assert html =~ ~s(class="sb-inspector__header")
        assert html =~ ~s(<h2 class="sb-inspector__title">Inspector</h2>)
        assert html =~ ~s(data-selected="false")
        assert status_text(html) == "no selection"
      end

      # The one that separates the label from the id and from the type name.
      # Sabotage: rendering `node.block_id` instead of `entry.label` - the
      # header reads `blk_email_step` instead of `Wait`.
      test "a selection is named by its type's label, not its id or type name" do
        html = inspector_html(node: node_for("blk_email_step"))

        assert html =~ ~s(data-selected="true")
        assert status_text(html) == "Wait"
      end

      # Decision 12's read-only case reaches the header too. The placeholder
      # entry is what an unresolvable block's `entry` is, so the status falls
      # back to the raw type name - which is the only thing still known about
      # it, and is what the card beside it reads.
      # Sabotage: dropping the `_none -> node.type` clause so every node falls
      # through to the empty case - an unresolvable block stops being named at
      # all and reads as though nothing were selected.
      test "an unresolvable block is named by its type name" do
        html = inspector_html(node: node_for("blk_track_conversion"))

        assert html =~ ~s(data-selected="true")
        assert status_text(html) == EditorFixtures.unknown_type()
      end

      # The fold's control, asserted where the palette's is: on the component,
      # because a chevron with no event on it is a chevron that looks right in
      # a screenshot and does nothing.
      # Sabotage: deleting the `<button class="sb-inspector__toggle">` from
      # `Inspector` - the pane keeps its header and loses the only way to fold
      # it, and this goes red on the class before the event assertion.
      test "carries the fold's control" do
        html = inspector_html(node: nil)

        assert html =~ ~s(class="sb-inspector__toggle")
        assert html =~ ~s(phx-click="inspector-collapse")
      end

      # Both directions, for the palette's reason: a one-sided label is the
      # defect that reads correctly in whichever state the author opened in.
      # The words are the inspector's own, not the palette's, because a control
      # that offers to collapse the wrong pane is worse than an unlabelled one.
      # Sabotage: hard-coding `aria-label="Collapse the inspector"` - the
      # expanded case still passes and the folded one goes red on the word.
      test "the chevron says what the press will do, in both states" do
        expanded = inspector_html(node: nil, collapsed: false)
        folded = inspector_html(node: nil, collapsed: true)

        assert expanded =~ ~s(aria-label="Collapse the inspector")
        assert expanded =~ ~s(aria-expanded="true")
        assert expanded =~ ~s(data-collapsed="false")

        assert folded =~ ~s(aria-label="Expand the inspector")
        assert folded =~ ~s(aria-expanded="false")
        assert folded =~ ~s(data-collapsed="true")
      end
    end

    describe "folding the palette" do
      # Sabotage: making `palette-collapse` assign `true` rather than negating
      # - the first press folds, the second does nothing, and the pane can
      # never be got back, which is the failure the toggle exists to avoid.
      test "the chevron folds the pane and unfolds it again", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        assert has_element?(view, ~s(.sb-palette[data-collapsed="false"]))
        assert has_element?(view, ~s(.sb-editor__layout[data-palette="expanded"]))

        view |> element(".sb-palette__toggle") |> render_click()

        assert has_element?(view, ~s(.sb-palette[data-collapsed="true"]))
        assert has_element?(view, ~s(.sb-editor__layout[data-palette="collapsed"]))

        view |> element(".sb-palette__toggle") |> render_click()

        assert has_element?(view, ~s(.sb-palette[data-collapsed="false"]))
        assert has_element?(view, ~s(.sb-editor__layout[data-palette="expanded"]))
      end

      # The fold is chrome about the pane, not state about the document, so it
      # deliberately does NOT go with the sheet in `switch_document/2`: an
      # author who asked for the width still wants it when a different document
      # opens. The sheet is the opposite case and is reset there, because a
      # sheet left open covers the new document's canvas.
      # Sabotage: adding `palette_collapsed: false` to `switch_document/2`'s
      # assign list - the preference silently resets on every host swap.
      test "the fold survives the host swapping the document", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        view |> element(".sb-palette__toggle") |> render_click()
        assert has_element?(view, ~s(.sb-palette[data-collapsed="true"]))

        send(view.pid, {:swap_document, EditorFixtures.credit_card()})
        _rendered = render(view)

        assert has_element?(view, ~s(.sb-palette[data-collapsed="true"]))
      end
    end

    describe "folding the inspector (ruling 1B)" do
      # The same three-press shape the palette's fold is held to, because 1B's
      # claim is that this IS that mechanism on the other side of the canvas -
      # a fold that cannot be undone is the failure a toggle exists to avoid,
      # and the pane it hides is the one the author edits in.
      # Sabotage: making `inspector-collapse` assign `true` rather than
      # negating - the first press folds, the second does nothing, and the
      # inspector can never be got back.
      test "the chevron folds the pane and unfolds it again", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        assert has_element?(view, ~s(.sb-inspector[data-collapsed="false"]))
        assert has_element?(view, ~s(.sb-editor__layout[data-inspector="expanded"]))

        view |> element(".sb-inspector__toggle") |> render_click()

        assert has_element?(view, ~s(.sb-inspector[data-collapsed="true"]))
        assert has_element?(view, ~s(.sb-editor__layout[data-inspector="collapsed"]))

        view |> element(".sb-inspector__toggle") |> render_click()

        assert has_element?(view, ~s(.sb-inspector[data-collapsed="false"]))
        assert has_element?(view, ~s(.sb-editor__layout[data-inspector="expanded"]))
      end

      # 1B's "in the palette's shape" is load-bearing here and nowhere else:
      # the two folds are the only editor state that survives a document swap,
      # and they survive it for the same reason - a pane fold addresses no
      # block. The collapsed-ids set, which does address blocks, is cleared by
      # the same function, so this is not a claim about `switch_document/2`
      # being lax.
      # Sabotage: adding `inspector_collapsed: false` to `switch_document/2`'s
      # assign list - the preference silently resets on every host swap.
      test "the fold survives the host swapping the document", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        view |> element(".sb-inspector__toggle") |> render_click()
        assert has_element?(view, ~s(.sb-inspector[data-collapsed="true"]))

        send(view.pid, {:swap_document, EditorFixtures.credit_card()})
        _rendered = render(view)

        assert has_element?(view, ~s(.sb-inspector[data-collapsed="true"]))
      end

      # The two folds are independent booleans, and the both-shut state is the
      # one the stylesheet needs a third template for - so the markup that
      # template selects on is asserted here rather than inferred from the two
      # single-fold tests.
      # Sabotage: passing `@palette_collapsed` to `data-inspector` on the
      # layout - every assertion above still passes, and this one goes red the
      # moment the two panes disagree.
      test "the two folds are independent", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        view |> element(".sb-palette__toggle") |> render_click()

        assert has_element?(view, ~s(.sb-editor__layout[data-palette="collapsed"]))
        assert has_element?(view, ~s(.sb-editor__layout[data-inspector="expanded"]))

        view |> element(".sb-inspector__toggle") |> render_click()

        assert has_element?(
                 view,
                 ~s(.sb-editor__layout[data-palette="collapsed"][data-inspector="collapsed"])
               )
      end
    end
  end
end
