if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.Toolbar do
    @moduledoc """
    The canvas toolbar (ADR-0005, the 2026-08-29 shell amendment, ruling 8A).

    8A splits the chrome: the package ships everything that operates on the
    document that is **open** - this toolbar, the tabbed inspector, the drawer,
    the grouped palette - and the host ships everything that decides **which**
    document is open. So there is no document name here, no switcher, no theme
    control and no compile button, and their absence is the ruling rather than
    an omission. The host renders those into the editor's `:header` slot.

    What is here is zoom, the two fits, and the two document metrics.

    ## The fits set a mode, they do not measure

    `Fit width` and `Fit active` are modes, not computed percentages, and that
    is decision 7's constraint showing through: nothing in this section adds a
    JavaScript hook, and a fit that resolves to a number needs the rendered
    width of an element, which only the client knows. So the toolbar records
    *which* fit the author asked for, the canvas carries it as `data-fit`, and
    a stylesheet does what a stylesheet can do with it. The measured form
    arrives with the read-only measurement hook the decision 7 amendment
    records (`sb-k7r`); until then a mode is the honest half, and it is the
    half a server can test.

    `Fit active` is disabled with nothing selected, because "fit the active
    block" with no active block is a control whose only outcome is nothing
    happening.

    ## Undo and redo are here too

    They are not in 8A's list, which enumerates what was newly arranged rather
    than what the toolbar already held. They operate on the open document,
    which is the package's half of the split by 8A's own rule.
    """

    use Phoenix.Component

    alias StatifierBlocks.Shell

    attr(:zoom, :integer, required: true)
    attr(:fit, :atom, default: :manual, doc: ":manual, :width or :active")
    attr(:depth, :integer, required: true)
    attr(:count, :integer, required: true)
    attr(:can_undo?, :boolean, required: true)
    attr(:can_redo?, :boolean, required: true)
    attr(:selected?, :boolean, default: false)
    attr(:inserting?, :boolean, default: false)
    attr(:target, :any, required: true)
    attr(:class, :string, default: nil)

    @doc "Zoom, the two fits, the document metrics, and the history controls."
    def toolbar(assigns) do
      ~H"""
      <div class={["sb-toolbar", @class]} data-zoom={@zoom} data-fit={@fit}>
        <button
          type="button"
          class="sb-toolbar__button"
          phx-click="undo"
          phx-target={@target}
          disabled={not @can_undo?}
        >
          Undo
        </button>
        <button
          type="button"
          class="sb-toolbar__button"
          phx-click="redo"
          phx-target={@target}
          disabled={not @can_redo?}
        >
          Redo
        </button>
        <button
          :if={@inserting?}
          type="button"
          class="sb-toolbar__button"
          phx-click="palette-close"
          phx-target={@target}
        >
          Cancel insert
        </button>

        <div class="sb-toolbar__group sb-toolbar__zoom">
          <button
            type="button"
            class="sb-toolbar__button"
            phx-click="zoom-out"
            phx-target={@target}
            disabled={@zoom <= hd(Shell.zoom_steps())}
            aria-label="Zoom out"
          >
            &minus;
          </button>
          <output class="sb-toolbar__zoom-level">{@zoom}%</output>
          <button
            type="button"
            class="sb-toolbar__button"
            phx-click="zoom-in"
            phx-target={@target}
            disabled={@zoom >= List.last(Shell.zoom_steps())}
            aria-label="Zoom in"
          >
            +
          </button>
        </div>

        <div class="sb-toolbar__group">
          <button
            type="button"
            class="sb-toolbar__button"
            phx-click="fit"
            phx-value-fit="width"
            phx-target={@target}
            aria-pressed={to_string(@fit == :width)}
          >
            Fit width
          </button>
          <button
            type="button"
            class="sb-toolbar__button"
            phx-click="fit"
            phx-value-fit="active"
            phx-target={@target}
            disabled={not @selected?}
            aria-pressed={to_string(@fit == :active)}
          >
            Fit active
          </button>
        </div>

        <p class="sb-toolbar__metrics">
          <span class="sb-toolbar__metric" data-metric="blocks">{@count} blocks</span>
          <span class="sb-toolbar__metric" data-metric="depth">depth {@depth}</span>
        </p>
      </div>
      """
    end
  end
end
