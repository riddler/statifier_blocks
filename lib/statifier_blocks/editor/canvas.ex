if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.Canvas do
    @moduledoc """
    The tree's root and the drag hook's element (ADR-0005 decisions 7, 13, 14).

    This component is small on purpose. It is the one element carrying
    `phx-hook="StatifierBlocksDrag"`, and every drag event in the editor
    arrives through it: the hook is attached to the canvas root rather than to
    each block, so adding a block adds no listeners and the hook has one
    lifetime rather than one per node.

    It is also where decision 14's theming lands. The `--sb-*` custom
    properties are declared on this element by the package's stylesheet, so a
    host that wants a different palette sets them here through the `theme`
    assign - a map of property name to value, rendered as an inline `style` -
    and needs no stylesheet of its own to do it.
    """

    use Phoenix.Component

    alias StatifierBlocks.Editor.BlockNode
    alias StatifierBlocks.ViewModel

    attr(:root, ViewModel.Node, required: true)
    attr(:drag, :any, default: nil)
    attr(:selected_id, :string, default: nil)
    attr(:target, :any, required: true)
    attr(:icon, :any, default: nil)
    attr(:theme, :map, default: %{})
    attr(:class, :string, default: nil)

    @doc "The canvas root: the hook's element, and the tree beneath it."
    def canvas(assigns) do
      ~H"""
      <div
        class={["sb-canvas", @class]}
        id="sb-canvas"
        phx-hook="StatifierBlocksDrag"
        phx-target={@target}
        data-dragging={to_string(@drag != nil)}
        style={theme_style(@theme)}
      >
        <BlockNode.block_node
          root?={true}
          node={@root}
          drag={@drag}
          selected_id={@selected_id}
          target={@target}
          icon={@icon}
        />
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
