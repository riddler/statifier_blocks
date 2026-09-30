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
    alias StatifierBlocks.Editor.MapRegions
    alias StatifierBlocks.Map, as: BlockMap
    alias StatifierBlocks.Map.Info
    alias StatifierBlocks.MapFixtures
    alias StatifierBlocks.ViewModel

    defmodule UnexpandableRenewal do
      @moduledoc false
      # A composite whose declaration cannot expand, in the shape of
      # `StatifierBlocks.Editor.CompositeExpandTest`'s `BrokenSubtree`:
      # `subtree/1` answers two members under one local id for "duplicate",
      # which `Composite.expand/2` refuses with an `ArgumentError`, and has
      # no clause for any other value, a `FunctionClauseError`. The view
      # model draws it as a leaf; only the outline has to expand it.

      use StatifierBlocks.Composite,
        name: "library.renew_loan",
        params: [
          %{key: "break", type: :string, label: "Break", required?: true, default: "duplicate"}
        ],
        sentence: "Renew the loan: {break}",
        palette_entry: %{label: "Renew the loan", group: "Structure"},
        version: 1

      alias StatifierBlocks.Block

      @impl StatifierBlocks.Composite
      def subtree(%{"break" => "duplicate"}), do: [renewed(), renewed()]

      defp renewed do
        Block.new("core.assign",
          id: "renewed",
          config: %{"path" => "loan.renewed", "value" => "true"}
        )
      end
    end

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
      # Sabotage: dropped `data-info-hover` from the element; this went red.
      # Sabotage: dropped `phx-update="ignore"` from the canvas child; this
      # went red.
      # Sabotage: stamped `data-info-region={@description}` on the element
      # again; this went red.
      test "the element carries every attribute the hook reads", %{conn: conn} do
        document = MapFixtures.document!("library_loan")
        {:ok, view, _html} = mount_host(conn, document)
        map = one(render(view), "#map")

        assert attribute(map, "phx-hook") == "StatifierBlocksMap"
        assert attribute(map, "data-editable") == "true"
        assert attribute(map, "data-insert-reveal") == "#inserting"
        assert attribute(map, "data-info-region") == nil
        assert attribute(map, "data-info-hover") == "map-description-hover"
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

    describe "selection speaks, hover is silent" do
      # What the region announces is what the server wrote there, and the
      # server writes it on a selection. A hover is drawn by the hook in the
      # layer beside the region, which the server renders empty, hidden,
      # hidden from assistive technology and left alone by LiveView; the
      # region never holds it. `StatifierBlocks.MapHoverTest` proves the hook
      # never writes the region; this proves where the layer sits and that a
      # selection does change the region. Nothing is claimed from a screen
      # reader.
      #
      # Sabotage: rendered the hover layer inside the region's section; this
      # went red on the layer's place.
      # Sabotage: dropped `phx-update="ignore"` from the hover layer; this
      # went red.
      # Sabotage: rendered the layer after the region, which the
      # stylesheet's sibling rule cannot reach; this went red on the order.
      test "a selection rewrites the live region, and the hover layer sits outside it", %{
        conn: conn
      } do
        {:ok, view, html} = mount_host(conn, MapFixtures.document!("library_loan"))
        {_graph, elements, idle} = described("library_loan")

        layer = one(html, "#map-description-hover")
        assert attribute(layer, "aria-hidden") == "true"
        assert attribute(layer, "phx-update") == "ignore"
        assert LazyHTML.attribute(layer, "hidden") == [""]
        assert LazyHTML.text(layer) |> String.trim() == ""
        assert attribute(layer, "aria-live") == nil

        refute has_element?(view, "#map-description #map-description-hover")
        refute has_element?(view, "#map-description-hover #map-description")

        ids =
          html
          |> LazyHTML.from_fragment()
          |> LazyHTML.query(".sb-map__description-frame > *")
          |> LazyHTML.attribute("id")

        assert ids == ["map-description-hover", "map-description"]

        before = LazyHTML.text(region(view))
        assert before =~ idle.title

        [_root, {second, _depth, _kind} | _rest] =
          ViewModel.outline(MapFixtures.view_model!("library_loan"))

        view |> element(~s([data-row="#{second.block_id}"] button)) |> render_click()

        expected = Enum.find(elements, &(&1.id == second.block_id))
        assert attribute(region(view), "aria-live") == "polite"
        assert LazyHTML.text(region(view)) =~ expected.title
        refute LazyHTML.text(region(view)) == before

        layer = one(render(view), "#map-description-hover")
        assert LazyHTML.attribute(layer, "hidden") == [""]
        assert LazyHTML.text(layer) |> String.trim() == ""
      end

      # The stylesheet draws the layer in the region's place: one grid cell,
      # the region transparent while the layer is shown, and the layer with
      # no display of its own, so `hidden` keeps it out. The region's rule
      # under a shown layer is read whole: transparent and nothing else, so
      # the region stays in the accessibility tree.
      # Sabotage: dropped the rule that makes the region transparent under a
      # shown layer; this went red.
      # Sabotage: added `visibility: hidden` to that rule; this went red.
      # Sabotage: added a second rule selecting the region under a shown
      # layer with `display: none`; this went red.
      test "the stylesheet stacks the shown layer over the region" do
        css = File.read!(Path.expand("../../../assets/css/statifier_blocks.css", __DIR__))
        rules = Regex.scan(~r/([^{}]+)\{([^}]*)\}/, css, capture: :all_but_first)

        region_rules =
          for [selectors, body] <- rules,
              selector <- String.split(selectors, ","),
              selector = String.trim(selector),
              selector =~ ~r/\.sb-map__description-hover:not\(\[hidden\]\)/,
              String.ends_with?(selector, ".sb-map__description"),
              do: body |> String.split() |> Enum.join(" ")

        assert region_rules == ["opacity: 0;"]

        assert css =~ ~r/\.sb-map__description-frame\s*\{\s*display:\s*grid;/

        layer_rules =
          for [selectors, body] <- rules,
              selector <- String.split(selectors, ","),
              String.ends_with?(String.trim(selector), ".sb-map__description-hover"),
              do: body

        refute layer_rules == []
        refute Enum.any?(layer_rules, &(&1 =~ "display"))
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

    defp region_html(document, attrs) do
      palette = Palette.core()

      base = %{
        id: "map-description",
        document: document,
        view_model: ViewModel.build(document, palette, []),
        palette: palette,
        selected: nil
      }

      render_component(
        &MapRegions.description_region/1,
        Map.merge(base, attrs)
      )
    end

    describe "the map attr" do
      # A host's page passes no `map`, and its region is the region it had:
      # the how-to-read paragraph in the idle description, the hover layer
      # and the store.
      # Sabotage: made the attr default to `false`; this went red on the
      # paragraph, the layer and the store.
      test "its default leaves a host's region unchanged", %{conn: conn} do
        document = MapFixtures.document!("library_loan")
        {_graph, _elements, idle} = described("library_loan")

        default = region_html(document, %{})
        assert default == region_html(document, %{map: true})

        assert LazyHTML.text(one(default, "#map-description .sb-map__description-text")) ==
                 idle.explanation

        assert count_of(default, "#map-description-hover") == 1
        assert count_of(default, "#map-description-store") == 1

        {:ok, view, _html} = mount_host(conn, document)
        assert LazyHTML.text(region(view)) =~ idle.explanation
      end

      # Sabotage: dropped the `:if` on the explanation paragraph; this went
      # red on the idle paragraph.
      # Sabotage: made the paragraph's `:if` read `@map` alone; this went
      # red on the selected block's explanation.
      test "false drops the how-to-read paragraph, the layer and the store, and nothing else" do
        document = MapFixtures.document!("library_loan")
        {_graph, elements, idle} = described("library_loan")

        none = region_html(document, %{map: false})
        assert count_of(none, "#map-description-hover") == 0
        assert count_of(none, "#map-description-store") == 0
        assert count_of(none, "#map-description .sb-map__description-text") == 0
        refute LazyHTML.text(one(none, "#map-description")) =~ idle.explanation
        assert LazyHTML.text(one(none, "#map-description")) =~ idle.title
        assert LazyHTML.attribute(one(none, "#map-description"), "aria-live") == ["polite"]

        [_root, {second, _depth, _kind} | _rest] =
          ViewModel.outline(MapFixtures.view_model!("library_loan"))

        expected = Enum.find(elements, &(&1.id == second.block_id))
        selected = region_html(document, %{map: false, selected: second.block_id})

        assert count_of(selected, "#map-description .sb-map__description-text") == 1

        assert LazyHTML.text(one(selected, "#map-description .sb-map__description-text")) ==
                 expected.explanation
      end
    end

    describe "the label attr" do
      # A host's page passes no `label`, and its region keeps the accessible
      # name it had.
      # Sabotage: made the attr default to `"Map description"`; this went
      # red on the region's aria-label.
      test "its default is Description, which leaves a host's region unchanged" do
        document = MapFixtures.document!("library_loan")

        default = region_html(document, %{})

        assert LazyHTML.attribute(one(default, "#map-description"), "aria-label") == [
                 "Description"
               ]

        assert default == region_html(document, %{label: "Description"})
      end

      # Sabotage: rendered `aria-label="Description"` whatever the attr
      # held; this went red on the host's label.
      test "a host's label names the live region, and nothing else changes" do
        document = MapFixtures.document!("library_loan")

        labelled = region_html(document, %{label: "Loan plan"})
        region = one(labelled, "#map-description")
        assert LazyHTML.attribute(region, "aria-label") == ["Loan plan"]
        assert LazyHTML.attribute(region, "aria-live") == ["polite"]

        assert String.replace(labelled, ~s(aria-label="Loan plan"), ~s(aria-label="Description")) ==
                 region_html(document, %{})
      end
    end

    describe "the class attr" do
      # A host styles the region through `class`, and while a hover shows
      # the region is transparent under the layer, so the layer wears the
      # host's class too.
      # Sabotage: rendered the hover layer with its own class alone; this
      # went red on the layer's class.
      # Sabotage: dropped `@class` from the region's section; this went red
      # on the region's class.
      test "a host's class goes on the region and on its hover layer" do
        document = MapFixtures.document!("library_loan")

        classed = region_html(document, %{class: "loan-plan"})

        assert LazyHTML.attribute(one(classed, "#map-description"), "class") == [
                 "sb-map__description loan-plan"
               ]

        assert LazyHTML.attribute(one(classed, "#map-description-hover"), "class") == [
                 "sb-map__description-hover loan-plan"
               ]

        none = region_html(document, %{class: "loan-plan", map: false})
        assert count_of(none, "#map-description-hover") == 0

        assert LazyHTML.attribute(one(none, "#map-description"), "class") == [
                 "sb-map__description loan-plan"
               ]
      end

      # A host's page passes no `class`, and its region and layer keep the
      # classes they had, the layer's byte for byte.
      # Sabotage: rendered the layer's class by interpolation,
      # `"sb-map__description-hover #{@class}"`; this went red on the
      # layer's class, which then ends in a space.
      test "its default adds nothing to the region or the layer" do
        document = MapFixtures.document!("library_loan")

        default = region_html(document, %{})
        assert default == region_html(document, %{class: nil})

        assert one(default, "#map-description") |> attribute("class") |> String.split() == [
                 "sb-map__description"
               ]

        assert LazyHTML.attribute(one(default, "#map-description-hover"), "class") == [
                 "sb-map__description-hover"
               ]
      end

      # A host's class on the layer may set a display, which beats the
      # browser's own rule for `hidden`; the stylesheet keeps a hidden layer
      # out with a rule more specific than a single class.
      # Sabotage: dropped the `[hidden]` rule from the stylesheet; this went
      # red.
      test "the stylesheet keeps a hidden layer out whatever display a host's class sets" do
        css = File.read!(Path.expand("../../../assets/css/statifier_blocks.css", __DIR__))

        assert css =~
                 ~r/\.sb-map__description-frame\s*>\s*\.sb-map__description-hover\[hidden\]\s*{\s*display:\s*none;\s*}/
      end
    end

    describe "the phrase attr" do
      # A host passes nil or a function of one argument, which the tests
      # above render; anything else is refused under the attr's name.
      # Sabotage: dropped the refusing clause of `phrase_opts/1`; this went
      # red on a FunctionClauseError where ArgumentError was asserted.
      # Sabotage: dropped "the phrase attr" from the message; this went red
      # on the message.
      test "a value that is not nil or a one-argument function is refused by name" do
        document = MapFixtures.document!("library_loan")
        view_model = MapFixtures.view_model!("library_loan")

        for phrase <- ["loan words", :phrase, fn a, b -> {a, b} end] do
          assert_raise ArgumentError,
                       ~r/^the phrase attr takes nil or a function of one argument, got: /,
                       fn ->
                         region_html(document, %{phrase: phrase})
                       end

          assert_raise ArgumentError,
                       ~r/^the phrase attr takes nil or a function of one argument, got: /,
                       fn ->
                         render_component(&MapRegions.map_region/1, %{
                           id: "map",
                           view_model: view_model,
                           selected: nil,
                           phrase: phrase
                         })
                       end
        end
      end
    end

    defp unexpandable_region_html(break, attrs) do
      palette =
        Palette.new(Map.put(Palette.core_types(), "library.renew_loan", UnexpandableRenewal))

      document =
        Document.new(
          Block.new("core.sequence",
            id: "blk_ROOT",
            slots: %{
              "body" => [
                Block.new("library.renew_loan", id: "blk_RL", config: %{"break" => break})
              ]
            }
          ),
          id: "bdoc_RENEW"
        )

      {document, palette,
       render_component(
         &MapRegions.description_region/1,
         Map.merge(
           %{
             id: "map-description",
             document: document,
             view_model: ViewModel.build(document, palette, []),
             palette: palette,
             selected: nil
           },
           attrs
         )
       )}
    end

    describe "a document whose composite declaration cannot expand" do
      # The outline expands every composite, so it raises on this document,
      # and the region degrades as the editor does: it renders, with no
      # description in it, rather than raising out of the host's render.
      # Sabotage: dropped the `rescue` from `outline/2`; red at both cases
      # and the one below, the outline's raise out of `render_component/2`,
      # which is the defect.
      # Sabotage: narrowed the `rescue` in `outline/2` to `ArgumentError`;
      # red at the FunctionClauseError case only, on the same raise.
      # Sabotage: stamped `data-map-description="idle"` on the empty
      # region; red at both cases on the attribute.
      # Sabotage: rendered the store only when there is a description; red
      # at both cases on the store's count.
      for {break, exception, what} <- [
            {"duplicate", ArgumentError, "a duplicated local id"},
            {"no_clause", FunctionClauseError, "a subtree/1 with no clause for the param"}
          ] do
        test "#{what}: the region renders empty, its layer and store beside it" do
          {document, palette, html} = unexpandable_region_html(unquote(break), %{})

          assert_raise unquote(exception), fn -> Describe.outline(document, palette, []) end

          assert count_of(html, "#map-description") == 1
          region = one(html, "#map-description")
          assert LazyHTML.attribute(region, "aria-live") == ["polite"]
          assert LazyHTML.attribute(region, "aria-label") == ["Description"]
          assert LazyHTML.attribute(region, "data-map-description") == []
          assert String.trim(LazyHTML.text(region)) == ""

          assert count_of(html, "#map-description-hover") == 1
          assert count_of(html, "#map-description-store") == 1
          assert count_of(html, "#map-description-store [data-describes]") == 0
        end
      end

      # A selection names a block the map draws, and the region still says
      # nothing: there is no description of it to show.
      # Sabotage: rendered the region only when there is a description; red
      # here and at both cases above on the region's count.
      test "a selection leaves the region empty, and map={false} drops only the layer and store" do
        {_document, _palette, selected} =
          unexpandable_region_html("duplicate", %{selected: "blk_RL"})

        assert count_of(selected, "#map-description") == 1
        assert String.trim(LazyHTML.text(one(selected, "#map-description"))) == ""

        {_document, _palette, none} = unexpandable_region_html("duplicate", %{map: false})
        assert count_of(none, "#map-description") == 1
        assert count_of(none, "#map-description-hover") == 0
        assert count_of(none, "#map-description-store") == 0
        assert String.trim(LazyHTML.text(one(none, "#map-description"))) == ""
      end

      # The degrade covers a raise out of the outline and nothing else: the
      # phrase attr's refusal holds on this document as on every other.
      # Sabotage: moved `phrase_opts/1` and `graph_opts/2` back inside the
      # outline's `{:ok, _}` branch; red on the assert_raise.
      test "a phrase the attr refuses is still refused by name" do
        assert_raise ArgumentError,
                     ~r/^the phrase attr takes nil or a function of one argument, got: /,
                     fn -> unexpandable_region_html("duplicate", %{phrase: "loan words"}) end
      end
    end

    defp count_of(html, selector),
      do: html |> LazyHTML.from_fragment() |> LazyHTML.query(selector) |> Enum.count()

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
