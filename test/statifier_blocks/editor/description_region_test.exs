# ADR-0005 decision 1: the editor and the region name Phoenix, so this test
# compiles only where LiveView resolves.
if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.DescriptionRegionTest do
    @moduledoc """
    The description region the editor draws under its canvas (ADR-0005's
    Amendment of 2026-09-29 on the shell arrangement): the same
    `StatifierBlocks.Editor.MapRegions.description_region/1` a host mounts
    beside the Map, read from the editor's own document, view model, palette
    and selection, with no Map anywhere in the editor. Nothing is claimed
    from a browser or a screen reader.
    """

    use StatifierBlocks.EditorLiveCase

    alias StatifierBlocks.Describe
    alias StatifierBlocks.Edit
    alias StatifierBlocks.Map, as: BlockMap
    alias StatifierBlocks.Map.Info
    alias StatifierBlocks.ViewModel

    @note "Sent once the patron submits the form; the desk resends by hand."

    # What the region is built from, computed the way a host's page computes
    # it, so the assertions compare against the component's own inputs rather
    # than against copied text.
    defp described(document) do
      palette = EditorFixtures.palette()
      view_model = ViewModel.build(document, palette, [])
      graph = BlockMap.graph(view_model, [])
      outline = Describe.outline(document, palette, [])

      {Info.elements(document, graph, view_model, outline, palette),
       Info.idle(document, graph, view_model, outline)}
    end

    defp select(view, id) do
      view
      |> element(~s([data-block-id="#{id}"] > .sb-node__chrome > .sb-node__label))
      |> render_click()

      view
    end

    defp region(view), do: one(render(view), "#editor-description")

    defp one(html, selector) do
      [node] = html |> LazyHTML.from_fragment() |> LazyHTML.query(selector) |> Enum.to_list()
      node
    end

    defp count(html, selector),
      do: html |> LazyHTML.from_fragment() |> LazyHTML.query(selector) |> Enum.count()

    describe "under the canvas" do
      # Sabotage: dropped the region from the editor's render; this went
      # red on the region's place.
      # Sabotage: moved the region above the run pane; this went red on the
      # order.
      test "one live region is drawn in the canvas column, after the canvas", %{conn: conn} do
        {:ok, _view, html} = mount_editor(conn)

        assert count(html, "#editor-description") == 1
        assert count(html, ".sb-editor__main > .sb-editor__description #editor-description") == 1

        order =
          html
          |> LazyHTML.from_fragment()
          |> LazyHTML.query(".sb-editor__main > *")
          |> LazyHTML.attribute("class")

        run_at = Enum.find_index(order, &(&1 =~ ~r/^sb-(canvas-panel|run)\b/))
        region_at = Enum.find_index(order, &(&1 =~ "sb-editor__description"))
        assert run_at != nil
        assert region_at == length(order) - 1
        assert run_at < region_at

        region = one(html, "#editor-description")
        assert LazyHTML.attribute(region, "aria-live") == ["polite"]
      end

      # Sabotage: made the editor pass `selected={nil}` to the region; this
      # went red on the selected block's kind.
      test "idle, it describes the document; selected on the canvas, the block", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)
        {elements, idle} = described(EditorFixtures.signup_wizard())

        assert LazyHTML.attribute(region(view), "data-map-description") == ["idle"]
        assert LazyHTML.text(region(view)) =~ idle.title
        assert LazyHTML.text(region(view)) =~ "What starts it"

        select(view, "blk_email_step")

        expected = Enum.find(elements, &(&1.id == "blk_email_step"))

        assert LazyHTML.attribute(region(view), "data-map-description") == [
                 to_string(expected.kind)
               ]

        assert LazyHTML.text(region(view)) =~ expected.title
        assert LazyHTML.text(region(view)) =~ expected.explanation
      end

      # Sabotage: made the editor pass `map={true}`; the how-to-read
      # paragraph came back and this went red.
      test "the idle description carries no paragraph on how to read a map", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)
        {_elements, idle} = described(EditorFixtures.signup_wizard())

        refute LazyHTML.text(region(view)) =~ idle.explanation
        assert count(render(view), "#editor-description .sb-map__description-text") == 0
      end

      # Sabotage: made the region read the document it was mounted with
      # rather than the editor's current one (`EditorFixtures.signup_wizard()`
      # in place of `@document`); the note never reached it and this went red.
      test "a note written in the inspector leads the region on the next render", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)
        select(view, "blk_email_step")

        refute LazyHTML.to_html(region(view)) =~ "sb-map__description-note"

        view
        |> form("#sb-inspector-note-blk_email_step", %{"note" => @note})
        |> render_change()

        [first | _rest] = region(view) |> LazyHTML.query("p") |> Enum.to_list()
        assert LazyHTML.attribute(first, "class") == ["sb-map__description-note"]
        assert LazyHTML.text(first) == @note
      end

      # Sabotage: guarded the region with `:if={not @read_only?}`; this went
      # red.
      test "a read-only mount draws it too, the note included", %{conn: conn} do
        {:ok, document, _inverse} =
          Edit.apply(EditorFixtures.signup_wizard(), {:update_note, "blk_email_step", @note})

        {:ok, view, _html} =
          mount_editor(conn, document: document, profile: %{read_only?: true})

        assert has_element?(view, ".sb-editor__main #editor-description[aria-live=polite]")

        select(view, "blk_email_step")
        assert LazyHTML.text(region(view)) =~ @note
      end
    end

    describe "no Map in the editor" do
      # Sabotage: rendered `map_region/1` beside the region in the editor;
      # this went red on the map region and the hook.
      # Sabotage: made the editor pass `map={true}`; this went red on the
      # store and the hover layer.
      test "no map region, no Map hook, no store and no hover layer", %{conn: conn} do
        {:ok, view, html} = mount_editor(conn)
        selected = view |> select("blk_email_step") |> render()

        for page <- [html, selected] do
          assert count(page, "[data-map-region]") == 0
          assert count(page, ~s([phx-hook="StatifierBlocksMap"])) == 0
          assert count(page, "#editor-description-store") == 0
          assert count(page, "#editor-description-hover") == 0
          assert count(page, "[data-map-descriptions]") == 0
        end
      end

      # The region shows values and never controls: the inspector stays the
      # one place that edits.
      # Sabotage: rendered a button inside the region's description; this
      # went red.
      test "nothing in the region is a control", %{conn: conn} do
        {:ok, view, html} = mount_editor(conn)
        selected = view |> select("blk_email_step") |> render()

        controls =
          ~w(button input textarea select a [phx-click] [phx-change] [tabindex] [contenteditable])

        for page <- [html, selected], control <- controls do
          assert count(page, ".sb-editor__description #{control}") == 0,
                 "found #{control} in the editor's description region"
        end
      end
    end
  end
end
