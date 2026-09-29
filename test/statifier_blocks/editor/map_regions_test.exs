# ADR-0005 decision 1: the components name Phoenix, so this test compiles
# only where LiveView resolves; the `:liveview` tag on
# `StatifierBlocks.EditorLiveCase` keeps it out of a headless run.
if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.MapRegionsTest do
    @moduledoc """
    The Map's two function components, mounted the way a host mounts them:
    beside a plain list of the document's steps, in a LiveView of the
    test's own that handles the list's events and nothing else.

    What is proven here, and only here, is the accessibility the Map is
    held to (ADR-0018): the map region is hidden from assistive technology
    and takes no focus, the description region is live and is what the
    list's rows point at, and every block the map draws is reachable from
    the list. None of it is claimed from a browser.
    """

    use StatifierBlocks.EditorLiveCase

    alias StatifierBlocks.Describe
    alias StatifierBlocks.Map, as: BlockMap
    alias StatifierBlocks.Map.Info
    alias StatifierBlocks.MapFixtures
    alias StatifierBlocks.ViewModel

    defmodule Host do
      @moduledoc false
      # A host at its smallest: the two regions and a list. The list's two
      # events are the only events it handles, and the map is handed their
      # names rather than names of its own.

      use Phoenix.LiveView

      alias StatifierBlocks.Editor.MapRegions
      alias StatifierBlocks.MapFixtures
      alias StatifierBlocks.Palette
      alias StatifierBlocks.ViewModel

      @impl Phoenix.LiveView
      def mount(_params, session, socket) do
        palette = Palette.core()
        document = session["document"]

        {:ok,
         assign(socket,
           document: document,
           palette: palette,
           view_model: ViewModel.build(document, palette, []),
           editable: Map.get(session, "editable", true),
           selected: nil,
           inserting: nil
         )}
      end

      @impl Phoenix.LiveView
      def handle_event("select-row", %{"block-id" => id}, socket),
        do: {:noreply, assign(socket, selected: id, inserting: nil)}

      def handle_event("insert-open", params, socket),
        do: {:noreply, assign(socket, inserting: params)}

      @impl Phoenix.LiveView
      def render(assigns) do
        ~H"""
        <MapRegions.map_region
          id="map"
          view_model={@view_model}
          selected={@selected}
          select_event="select-row"
          insert_event="insert-open"
          editable={@editable}
          phrase={&MapFixtures.phrase/1}
          description="map-description"
          insert_reveal="#inserting"
        />
        <MapRegions.description_region
          id="map-description"
          document={@document}
          view_model={@view_model}
          palette={@palette}
          selected={@selected}
          phrase={&MapFixtures.phrase/1}
        />
        <ol data-list="true">
          <li
            :for={{node, _depth, _kind} <- ViewModel.outline(@view_model)}
            data-row={node.block_id}
            aria-describedby="map-description"
          >
            <button
              type="button"
              phx-click="select-row"
              phx-value-block-id={node.block_id}
              aria-describedby="map-description"
            >
              {ViewModel.sentence(node)}
            </button>
          </li>
        </ol>
        <p :if={@inserting} id="inserting">{@inserting["block-id"]}</p>
        """
      end
    end

    defp mount_host(conn, document, session \\ %{}) do
      live_isolated(conn, Host, session: Map.put(session, "document", document))
    end

    defp one(html, selector) do
      [node] = html |> LazyHTML.from_fragment() |> LazyHTML.query(selector) |> Enum.to_list()
      node
    end

    # The attribute's value, or nil where the element does not carry it, so
    # a missing stamp fails the assertion that reads it.
    defp attribute(node, name), do: node |> LazyHTML.attribute(name) |> List.first()

    defp graph_on(view),
      do: view |> render() |> one("#map") |> attribute("data-graph") |> JSON.decode!()

    defp selected_ids(%{} = node) do
      own = if node["selected"] == true, do: [node["id"]], else: []
      own ++ Enum.flat_map(Map.get(node, "children", []), &selected_ids/1)
    end

    defp region(view), do: view |> render() |> one("#map-description")

    defp described(key) do
      document = MapFixtures.document!(key)
      view_model = MapFixtures.view_model!(key)
      graph = BlockMap.graph(view_model, phrase: &MapFixtures.phrase/1)
      outline = Describe.outline(document, Palette.core(), [])

      elements =
        Info.elements(document, graph, view_model, outline, Palette.core(),
          phrase: &MapFixtures.phrase/1
        )

      {graph, elements, Info.idle(document, graph, view_model, outline)}
    end

    defp put_note(%Document{root: root} = document, id, note),
      do: %{document | root: note_block(root, id, note)}

    defp note_block(%Block{id: id} = block, id, note), do: %{block | note: note}

    defp note_block(%Block{slots: slots} = block, id, note),
      do: %{
        block
        | slots:
            Map.new(slots, fn {name, kids} ->
              {name, Enum.map(kids, &note_block(&1, id, note))}
            end)
      }

    describe "selection through the list" do
      # Sabotage: made `current/3` answer the idle description whatever was
      # selected; this went red on the region's kind.
      # Sabotage: made `graph_opts/2` drop `:selected`; this went red on the
      # map's mark.
      test "a row's own event marks the block on the map and fills the region", %{conn: conn} do
        for key <- MapFixtures.keys() do
          {:ok, view, _html} = mount_host(conn, MapFixtures.document!(key))
          {_graph, elements, idle} = described(key)

          assert selected_ids(graph_on(view)) == []
          assert attribute(region(view), "data-map-description") == "idle"
          assert LazyHTML.text(region(view)) =~ idle.title

          [_root, {second, _depth, _kind} | _rest] =
            ViewModel.outline(MapFixtures.view_model!(key))

          view
          |> element(~s([data-row="#{second.block_id}"] button))
          |> render_click()

          assert selected_ids(graph_on(view)) == [second.block_id]
          assert attribute(one(render(view), "#map"), "data-selected") == second.block_id

          expected = Enum.find(elements, &(&1.id == second.block_id))
          assert attribute(region(view), "data-map-description") == to_string(expected.kind)
          assert LazyHTML.text(region(view)) =~ expected.title
          assert LazyHTML.text(region(view)) =~ expected.explanation
        end
      end

      # The keyboard's path through the Map is the list: every block the map
      # draws has a row whose button, a focusable control, selects it, and
      # the region then describes that block.
      # Sabotage: made `current/3` look the selection up under an id it
      # never carries; this went red on the first block.
      test "every block the map draws is reachable from the list", %{conn: conn} do
        for key <- MapFixtures.keys() do
          {:ok, view, _html} = mount_host(conn, MapFixtures.document!(key))
          {graph, elements, _idle} = described(key)
          by_id = Map.new(elements, &{&1.id, &1})

          for id <- BlockMap.nodes(graph) do
            view |> element(~s([data-row="#{id}"] button)) |> render_click()

            assert attribute(region(view), "data-map-description") in ["block", "rule"], id
            assert LazyHTML.text(region(view)) =~ by_id[id].title, id
            assert selected_ids(graph_on(view)) == [id], id
          end
        end
      end

      # Sabotage: stamped `data-select-event` from a fixed name instead of
      # the host's; this went red.
      test "a gesture on the map arrives under the list's own name", %{conn: conn} do
        {:ok, view, _html} = mount_host(conn, MapFixtures.document!("library_loan"))

        [_root, {second, _depth, _kind} | _rest] =
          ViewModel.outline(MapFixtures.view_model!("library_loan"))

        map = one(render(view), "#map")
        select = attribute(map, "data-select-event")
        insert = attribute(map, "data-insert-event")
        assert {select, insert} == {"select-row", "insert-open"}

        view |> element("#map") |> render_hook(select, %{"block-id" => second.block_id})
        assert selected_ids(graph_on(view)) == [second.block_id]

        view |> element("#map") |> render_hook(insert, %{"block-id" => second.block_id})
        assert has_element?(view, "#inserting", second.block_id)
      end
    end

    describe "what the map region stamps" do
      # Sabotage: dropped `data-info-store` from the element; this went red.
      # Sabotage: dropped `phx-update="ignore"` from the canvas child; this
      # went red.
      test "the element carries every attribute the hook reads", %{conn: conn} do
        document = MapFixtures.document!("library_loan")
        {:ok, view, _html} = mount_host(conn, document)
        map = one(render(view), "#map")

        assert attribute(map, "phx-hook") == "StatifierBlocksMap"
        assert attribute(map, "data-editable") == "true"
        assert attribute(map, "data-insert-reveal") == "#inserting"
        assert attribute(map, "data-info-region") == "map-description"
        assert attribute(map, "data-info-store") == "map-description-store"
        assert has_element?(view, "#map-description-store[hidden]")

        canvas = one(render(view), "#map [data-map-canvas]")
        assert attribute(canvas, "phx-update") == "ignore"
        assert attribute(canvas, "id") == "map-canvas"

        assert graph_on(view) ==
                 MapFixtures.view_model!("library_loan")
                 |> BlockMap.graph(phrase: &MapFixtures.phrase/1)
                 |> JSON.encode!()
                 |> JSON.decode!()
      end

      # Sabotage: stamped `data-editable` as a constant "true"; this went red.
      test "a page that cannot edit says so to the hook", %{conn: conn} do
        {:ok, view, _html} =
          mount_host(conn, MapFixtures.document!("library_loan"), %{"editable" => false})

        assert attribute(one(render(view), "#map"), "data-editable") == "false"
      end
    end

    describe "accessibility" do
      # Sabotage: dropped `aria-hidden` from the region; this went red.
      # Sabotage: dropped `tabindex="-1"` from the element; this went red.
      test "the map region is hidden from assistive technology and takes no focus", %{conn: conn} do
        {:ok, view, _html} = mount_host(conn, MapFixtures.document!("library_loan"))
        view |> element("[data-list] li:nth-child(2) button") |> render_click()

        region = one(render(view), "section.sb-map__region")
        assert attribute(region, "aria-hidden") == "true"
        assert attribute(one(render(view), "#map"), "tabindex") == "-1"

        markup = LazyHTML.to_html(region)
        refute markup =~ ~r/<(button|input|select|textarea|a)[\s>]/
        assert markup |> String.split("tabindex") |> length() == 2
      end

      # Sabotage: dropped `aria-live` from the region; this went red.
      # Sabotage: rendered the region inside the map's section; this went
      # red on the aria-hidden ancestor.
      test "the description region is live, outside the hidden map, under the rows' id", %{
        conn: conn
      } do
        {:ok, view, html} = mount_host(conn, MapFixtures.document!("patron_registration"))

        region = one(html, "#map-description")
        assert attribute(region, "aria-live") == "polite"
        refute has_element?(view, "section.sb-map__region #map-description")
        refute has_element?(view, "[aria-hidden] #map-description")

        described_by =
          html
          |> LazyHTML.from_fragment()
          |> LazyHTML.query("[data-list] [aria-describedby]")
          |> LazyHTML.attribute("aria-describedby")
          |> Enum.uniq()

        assert described_by == ["map-description"]
      end
    end

    describe "the store and the note" do
      # Sabotage: dropped `data-describes` from the store's entries; this
      # went red.
      test "the store holds one entry per element the map draws, in its order", %{conn: conn} do
        for key <- MapFixtures.keys() do
          {:ok, _view, html} = mount_host(conn, MapFixtures.document!(key))
          {_graph, elements, _idle} = described(key)

          entries =
            html
            |> LazyHTML.from_fragment()
            |> LazyHTML.query("#map-description-store > [data-describes]")

          assert LazyHTML.attribute(entries, "data-describes") == Enum.map(elements, & &1.id)

          for {entry, description} <- Enum.zip(entries, elements) do
            assert LazyHTML.text(entry) =~ description.title
          end
        end
      end

      # Sabotage: moved the note's paragraph below the title; this went red.
      # Sabotage: dropped the note's `:if`; this went red on the block with
      # no note.
      test "a block's note leads the region, and a block with none shows none", %{conn: conn} do
        note = "Three weeks is the branch's standard loan."

        document =
          "library_loan" |> MapFixtures.document!() |> put_note("blk_ll_loan_period", note)

        {:ok, view, _html} = mount_host(conn, document)

        view |> element(~s([data-row="blk_ll_loan_period"] button)) |> render_click()

        [first | _rest] = region(view) |> LazyHTML.query("p") |> Enum.to_list()

        assert LazyHTML.attribute(first, "class") == ["sb-map__description-note"]
        assert LazyHTML.text(first) == note

        [_root, {second, _depth, _kind} | _rest] =
          ViewModel.outline(MapFixtures.view_model!("library_loan"))

        assert second.block_id != "blk_ll_loan_period"
        view |> element(~s([data-row="#{second.block_id}"] button)) |> render_click()

        refute LazyHTML.to_html(region(view)) =~ "sb-map__description-note"
      end
    end

    # ADR-0005 decision 14 holds for these components as for the editor.
    # Sabotage: renamed the canvas's class to `map__canvas`; this went red.
    test "every class the components emit is prefixed sb-", %{conn: conn} do
      {:ok, view, _html} = mount_host(conn, MapFixtures.document!("library_loan"))
      html = view |> element("[data-list] li:nth-child(2) button") |> render_click()

      classes =
        ~r/class="([^"]*)"/
        |> Regex.scan(html)
        |> Enum.flat_map(fn [_all, value] -> String.split(value, ~r/\s+/, trim: true) end)
        |> Enum.uniq()

      assert Enum.reject(classes, &String.starts_with?(&1, "sb-")) == []
      assert "sb-map__canvas" in classes
      assert "sb-map__description-title" in classes
    end
  end
end
