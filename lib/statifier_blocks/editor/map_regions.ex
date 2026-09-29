if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.MapRegions do
    @moduledoc """
    The two function components a host mounts to show the Map beside its own
    list: `map_region/1`, where the `StatifierBlocksMap` hook draws the
    document, and `description_region/1`, which says in words what the
    selected block is, or what the document is when nothing is selected.

    They live in the `StatifierBlocks.Editor.*` namespace because they name
    Phoenix, and that namespace is where ADR-0005 decision 1's compile guard
    lives. They are not part of the editor: neither reads or renders
    anything `StatifierBlocks.Editor` holds, and the editor draws no map
    (ADR-0018).

    ## What the host brings

    The components keep no state. A host passes four things, and each stays
    the host's:

    | The host's | What it is |
    |---|---|
    | view model | `StatifierBlocks.ViewModel.build/3` of the document, which both regions read; the description region also takes the document and the palette it was built from |
    | selection | the block id its list has selected, or `nil`; the map marks that block's box and the description region describes it |
    | event names | the names its list already sends to select a block and to open an insert; a gesture on the map is sent under those names, with the payload the list sends for the same gesture |
    | list | the list itself, which stays the keyboard and screen-reader path to every step |

    ## The map region

    `map_region/1` renders the element the hook is attached to, inside a
    region hidden from assistive technology (`aria-hidden="true"`): a reader
    of the host's list would otherwise meet every step twice. The element
    scrolls, and a browser makes a scroll box with nothing focusable in it a
    Tab stop of its own, so it carries `tabindex="-1"`; nothing else in the
    region takes focus.

    The element carries what the hook reads, in the attributes it reads them
    from: the graph `StatifierBlocks.Map.graph/2` answers as JSON in
    `data-graph`, with the selection marked in it; whether the page can edit
    in `data-editable`; the list's event names in `data-select-event` and
    `data-insert-event`; the element to scroll into view after an insert
    armed from the map in `data-insert-reveal`, when the host names one; and
    the description region's id, its hover layer's and its store's in
    `data-info-region`, `data-info-hover` and `data-info-store`, when the
    host names the region, which is what gives the map its hover. The
    drawing goes into a child marked `data-map-canvas`, which LiveView
    leaves alone (`phx-update="ignore"`).

    ## The description region

    `description_region/1` renders the region with `aria-live="polite"`, so
    a selection made in the list is read out, under the id the host's list
    rows name with `aria-describedby`. Its content is rendered on the
    server: the selected block's `StatifierBlocks.Map.Info` description, or
    `StatifierBlocks.Map.Info.idle/4` when nothing is selected. A block's
    author-written note leads, above the built-in text (ADR-0001's Amendment
    of 2026-09-28, clause `2g`). It shows values and never controls.

    Beside the region, and hidden, it renders the store the hook's hover
    reads: one child per element the map draws, `data-describes` naming the
    element's map id, holding the same markup the region shows for it. The
    store's id is the region's with `-store` after it, which is the id
    `map_region/1` stamps when it is handed the region's.

    ## Selection speaks, hover is silent

    What the region announces changes on a selection and never on a hover.
    The server writes the region, and only on a render: a row selected in
    the list, or a block selected on the map, which arrives as the list's
    own event. A hover is drawn in the hover layer instead, an element
    beside the region and outside it, with the region's id and `-hover`
    after it: `aria-hidden="true"`, `hidden` until the hook fills it, and
    left alone by LiveView (`phx-update="ignore"`). The two sit in one
    frame, `sb-map__description-frame`, and while the layer is shown the
    stylesheet stacks it over the region and makes the region transparent,
    so the visible text is the hovered element's while the region's own
    content, and its `aria-live`, stay as the server wrote them.
    """

    use Phoenix.Component

    alias StatifierBlocks.Describe
    alias StatifierBlocks.Document
    alias StatifierBlocks.Map, as: BlockMap
    alias StatifierBlocks.Map.Info
    alias StatifierBlocks.Palette
    alias StatifierBlocks.ViewModel

    attr(:id, :string, required: true, doc: "the id of the element the hook is attached to")
    attr(:view_model, ViewModel, required: true)
    attr(:selected, :string, default: nil, doc: "the block id the host's list has selected")

    attr(:select_event, :string,
      default: nil,
      doc: "the event the host's list sends to select a block"
    )

    attr(:insert_event, :string,
      default: nil,
      doc: "the event the host's list sends to open an insert"
    )

    attr(:editable, :boolean,
      default: false,
      doc: "whether the map's gaps and markers arm inserts"
    )

    attr(:phrase, :any,
      default: nil,
      doc: "the host's words for event names, as `StatifierBlocks.Map.graph/2` takes them"
    )

    attr(:description, :string,
      default: nil,
      doc: "the id of the host's `description_region/1`, which gives the map its hover"
    )

    attr(:insert_reveal, :string,
      default: nil,
      doc: "a selector for what to scroll into view after an insert armed from the map"
    )

    attr(:class, :string, default: nil, doc: "a class of the host's, added to the region's own")

    @doc "The region the `StatifierBlocksMap` hook draws the Map into; see the moduledoc."
    @spec map_region(map()) :: Phoenix.LiveView.Rendered.t()
    def map_region(assigns) do
      graph = BlockMap.graph(assigns.view_model, graph_opts(assigns.selected, assigns.phrase))
      assigns = assign(assigns, :graph, JSON.encode!(graph))

      ~H"""
      <section class={["sb-map__region", @class]} aria-hidden="true" data-map-region="true">
        <div
          id={@id}
          class="sb-map__canvas"
          phx-hook="StatifierBlocksMap"
          tabindex="-1"
          data-graph={@graph}
          data-selected={@selected}
          data-editable={to_string(@editable)}
          data-select-event={@select_event}
          data-insert-event={@insert_event}
          data-insert-reveal={@insert_reveal}
          data-info-region={@description}
          data-info-hover={@description && hover_id(@description)}
          data-info-store={@description && store_id(@description)}
        >
          <div id={"#{@id}-canvas"} data-map-canvas phx-update="ignore"></div>
        </div>
      </section>
      """
    end

    attr(:id, :string,
      required: true,
      doc: "the region's id, which the host's list rows name with `aria-describedby`"
    )

    attr(:document, Document, required: true, doc: "the document the view model was built from")
    attr(:view_model, ViewModel, required: true)
    attr(:palette, Palette, required: true, doc: "the palette the view model was built with")
    attr(:selected, :string, default: nil, doc: "the block id the host's list has selected")

    attr(:phrase, :any,
      default: nil,
      doc: "the host's words for event names, the function `map_region/1` takes"
    )

    attr(:class, :string, default: nil, doc: "a class of the host's, added to the region's own")

    @doc "The Map's description region, its hover layer and its hidden store; see the moduledoc."
    @spec description_region(map()) :: Phoenix.LiveView.Rendered.t()
    def description_region(assigns) do
      %{document: document, view_model: view_model, palette: palette} = assigns
      graph = BlockMap.graph(view_model, graph_opts(assigns.selected, assigns.phrase))
      outline = Describe.outline(document, palette, [])

      elements =
        Info.elements(document, graph, view_model, outline, palette, phrase_opts(assigns.phrase))

      idle = Info.idle(document, graph, view_model, outline)

      assigns =
        assigns
        |> assign(:elements, elements)
        |> assign(:current, current(elements, assigns.selected, idle))

      ~H"""
      <div class="sb-map__description-frame">
        <div
          id={hover_id(@id)}
          class="sb-map__description-hover"
          aria-hidden="true"
          hidden
          phx-update="ignore"
          data-map-description-hover="true"
        >
        </div>
        <section
          id={@id}
          class={["sb-map__description", @class]}
          aria-live="polite"
          aria-label="Description"
          data-map-description={@current.kind}
        >
          <.description description={@current} />
        </section>
      </div>
      <div id={store_id(@id)} hidden data-map-descriptions="true">
        <div
          :for={description <- @elements}
          data-describes={description.id}
          data-describes-kind={description.kind}
        >
          <.description description={description} />
        </div>
      </div>
      """
    end

    attr(:description, Info, required: true)

    # One description, in words: the region draws the current one and the
    # store draws every one. The note leads; values, never controls.
    defp description(assigns) do
      ~H"""
      <p :if={@description.note} class="sb-map__description-note">{@description.note}</p>
      <p class="sb-map__description-title">{@description.title}</p>
      <p :if={@description.sentence} class="sb-map__description-sentence">
        {@description.sentence}
      </p>
      <p class="sb-map__description-text">{@description.explanation}</p>
      <.facts :if={@description.settings != []} heading="Settings" facts={@description.settings} />
      <.facts :if={@description.facts != []} facts={@description.facts} />
      """
    end

    attr(:heading, :string, default: nil)
    attr(:facts, :list, required: true)

    defp facts(assigns) do
      ~H"""
      <p :if={@heading} class="sb-map__description-heading">{@heading}</p>
      <dl class="sb-map__description-facts">
        <%= for {label, value} <- @facts do %>
          <dt>{label}</dt>
          <dd :if={is_binary(value)}>{value}</dd>
          <dd :if={is_list(value)}>
            <ul>
              <li :for={item <- value}>{item}</li>
            </ul>
          </dd>
        <% end %>
      </dl>
      """
    end

    # What the region says: the selected block's description, or the
    # document's when nothing is selected or the selection names nothing
    # the map draws.
    @spec current([Info.t()], String.t() | nil, Info.t()) :: Info.t()
    defp current(_elements, nil, idle), do: idle
    defp current(elements, id, idle), do: Enum.find(elements, idle, &(&1.id == id))

    @spec store_id(String.t()) :: String.t()
    defp store_id(region_id), do: region_id <> "-store"

    @spec hover_id(String.t()) :: String.t()
    defp hover_id(region_id), do: region_id <> "-hover"

    @spec graph_opts(String.t() | nil, term()) :: keyword()
    defp graph_opts(selected, phrase), do: [selected: selected] ++ phrase_opts(phrase)

    @spec phrase_opts(term()) :: keyword()
    defp phrase_opts(nil), do: []
    defp phrase_opts(phrase) when is_function(phrase, 1), do: [phrase: phrase]
  end
end
