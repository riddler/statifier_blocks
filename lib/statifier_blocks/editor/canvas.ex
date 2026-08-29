if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.Canvas do
    @moduledoc """
    The tree's root and the drag hook's element (ADR-0005 decisions 7, 13, 14).

    This component is small on purpose. It is the one element carrying
    `phx-hook="StatifierBlocksDrag"`, and every drag event in the editor
    arrives through it: the hook is attached to the canvas root rather than to
    each block, so adding a block adds no listeners and the hook has one
    lifetime rather than one per node.

    It is also the measurement stage. The 2026-08-29 amendment to decision 7
    admits a second hook whose whole job is reading laid-out boxes, and every
    box it reads is relative to this element - which is why this element
    carries `data-sb-anchor="stage"` and why the connector overlay is drawn
    inside it, in its own untransformed coordinate space. The hook itself
    rides a child element rather than this one, because an element carries one
    `phx-hook` and this one is the drag hook's; `ConnectorLayer` renders that
    child and says why.

    It is also where decision 14's theming lands. The `--sb-*` custom
    properties are declared on this element by the package's stylesheet, so a
    host that wants a different palette sets them here through the `theme`
    assign - a map of property name to value, rendered as an inline `style` -
    and needs no stylesheet of its own to do it.

    ## The panel is the scroller; this element is the stage

    Parity item 1.2 gives the canvas a bordered, dotted ground, and both halves
    of that land on two elements rather than one. `.sb-canvas-panel` is the
    box - the border, and `overflow` - and this element stays the stage inside
    it, sized by the tree it holds.

    The split is forced by the connector overlay above, not chosen for tidiness.
    `.sb-connectors` is absolutely positioned against this element and sized
    from the stage's scroll extent; put `overflow` on the same element and the
    overlay is sized to the padding box instead, so the connectors stay put
    while the tree scrolls out from under them. A scroller one level out leaves
    the overlay's containing block exactly where the measurement hook already
    reads it from.

    The dots ride the panel for the same reason, one step on. A ground has to
    be visible to be a ground, and the only place it can show is the band the
    panel's padding opens around the tree - the root block's own surface covers
    everything inside it. Painting them on the stage instead and padding the
    stage to make room is the version that displaces every connector by the
    padding, which is the trade the paragraph above already made.

    So `--sb-canvas-grid` is a stylesheet-tier override rather than a `theme`
    assign one: it is consumed above the element that assign writes to, exactly
    as the pane widths and the drawer height are. `docs/theming.md` calls a
    stylesheet the ordinary case and the assign the computed one, so this is
    where the grid was always going to land.
    """

    use Phoenix.Component

    alias StatifierBlocks.Connectors
    alias StatifierBlocks.Editor.BlockNode
    alias StatifierBlocks.Editor.ConnectorLayer
    alias StatifierBlocks.ViewModel

    attr(:root, ViewModel.Node, required: true)
    attr(:drag, :any, default: nil)
    attr(:selected_id, :string, default: nil)
    attr(:target, :any, required: true)
    attr(:icon, :any, default: nil)
    attr(:theme, :map, default: %{})
    attr(:edges, :list, default: [])
    attr(:stage, :any, default: nil)
    attr(:class, :string, default: nil)

    @doc "The canvas root: the hook's element, and the tree beneath it."
    def canvas(assigns) do
      ~H"""
      <div class="sb-canvas-panel">
        <div
          class={["sb-canvas", @class]}
          id="sb-canvas"
          phx-hook="StatifierBlocksDrag"
          phx-target={@target}
          data-dragging={to_string(@drag != nil)}
          data-sb-anchor={Connectors.stage_anchor()}
          style={theme_style(@theme)}
        >
          <ConnectorLayer.connector_layer edges={@edges} stage={@stage} target={@target} />
          <BlockNode.block_node
            root?={true}
            node={@root}
            drag={@drag}
            selected_id={@selected_id}
            target={@target}
            icon={@icon}
          />
        </div>
      </div>
      """
    end

    # Only `--sb-*` names are emitted. A host that passes something else gets
    # it ignored rather than injected: this attribute is assembled from
    # caller-supplied strings, and an unfiltered one is how a style attribute
    # becomes an injection surface.
    @spec theme_style(map()) :: String.t() | nil
    defp theme_style(theme) when map_size(theme) == 0, do: nil

    defp theme_style(theme) do
      theme
      |> Enum.filter(fn {name, _value} -> String.starts_with?(to_string(name), "--sb-") end)
      |> Enum.sort()
      |> Enum.map_join(";", fn {name, value} -> "#{name}:#{value}" end)
      |> case do
        "" -> nil
        style -> style
      end
    end
  end
end
