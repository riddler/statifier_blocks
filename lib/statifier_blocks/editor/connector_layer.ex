if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.ConnectorLayer do
    @moduledoc """
    The drawn connectors, and the element the measurement hook rides on
    (ADR-0005 decision 10, and the 2026-08-29 amendment to decision 7).

    Two elements, and neither holds a decision. `StatifierBlocks.Connectors`
    decided every path in the list this renders, from rectangles the browser
    measured; all this component does is put them on the page and hand the
    stylesheet a class to colour each one by.

    ## Why the hook rides its own element

    An element carries one `phx-hook`, and the canvas root already carries
    `StatifierBlocksDrag` - it is deliberately the drag hook's single
    element, so that adding a block adds no listeners. The measurement hook
    therefore rides a dedicated empty child of the canvas: the drag hook's
    element and its lifetime are untouched, and the measure hook finds its
    stage with one `closest('[data-sb-anchor="stage"]')` rather than by an
    id, so the hook holds no knowledge of what the canvas root is called.

    The element renders whether or not a host imported the hook. It is a
    zero-size div either way; with no hook attached it is inert, nothing is
    measured, `Connectors.edges/2` returns `[]`, and the `<svg>` below is not
    rendered at all. That is clause 7b.3's "fully usable with the hook
    absent", and it costs one empty element rather than a flag.

    ## Why the layer is absent rather than empty

    No measurement means no `<svg>` element, not an `<svg>` with no paths.
    An empty overlay is still a box in the layout with a scroll extent and a
    stacking context, and the amendment's standing test is that a host
    without the hook gets the editor it had before - which is an editor with
    no overlay in it.
    """

    use Phoenix.Component

    alias StatifierBlocks.Connectors

    attr(:edges, :list, default: [])
    attr(:stage, :any, default: nil)
    attr(:target, :any, required: true)

    @doc "The connector overlay: absent entirely until something is measured."
    def connector_layer(assigns) do
      ~H"""
      <div class="sb-measure" id="sb-measure" phx-hook="StatifierBlocksMeasure" phx-target={@target}>
      </div>
      <svg
        :if={drawable?(@edges, @stage)}
        class="sb-connectors"
        aria-hidden="true"
        width={@stage.width}
        height={@stage.height}
        viewBox={"0 0 #{@stage.width} #{@stage.height}"}
      >
        <defs>
          <%!-- Two arrowheads rather than one, because a marker's fill cannot
                inherit the stroke of the path that references it in every
                browser that matters yet. Both read a token, so a theme still
                moves them. --%>
          <marker
            :for={{id, class} <- markers()}
            id={id}
            class={class}
            markerWidth="6"
            markerHeight="6"
            refX="5"
            refY="3"
            orient="auto"
          >
            <path d="M 0 0 L 6 3 L 0 6 z" />
          </marker>
        </defs>
        <g class="sb-connectors__edges">
          <path
            :for={{edge, index} <- Enum.with_index(@edges)}
            id={"sb-edge-#{index}"}
            class={"sb-edge sb-edge--#{edge.kind}"}
            d={edge.d}
            fill="none"
            marker-end={marker_for(edge)}
          />
        </g>
      </svg>
      """
    end

    @spec markers() :: [{String.t(), String.t()}]
    defp markers,
      do: [{"sb-arrow", "sb-arrow--flow"}, {"sb-arrow-interrupt", "sb-arrow--interrupt"}]

    # An interrupt edge carries its own arrowhead, because the whole point of
    # the dashed channel is that it is a different way out; every other edge
    # carries the flow one. A rejoin carries none - an arrow into a hub that
    # the flow immediately leaves again reads as a second destination.
    @spec marker_for(Connectors.Edge.t()) :: String.t() | nil
    defp marker_for(%Connectors.Edge{kind: :interrupt}), do: "url(#sb-arrow-interrupt)"
    defp marker_for(%Connectors.Edge{kind: :join}), do: nil
    defp marker_for(%Connectors.Edge{}), do: "url(#sb-arrow)"

    @spec drawable?([Connectors.Edge.t()], Connectors.Rect.t() | nil) :: boolean()
    defp drawable?([], _stage), do: false
    defp drawable?(_edges, %Connectors.Rect{}), do: true
    defp drawable?(_edges, _stage), do: false
  end
end
