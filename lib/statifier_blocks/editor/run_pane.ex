if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.RunPane do
    @moduledoc """
    The canvas with a run around it: statifier-ui's status and scrubber above
    it, its event log below, and the document's own blocks where an ops view
    would draw a diagram.

    An ops view built out of `StatifierUI.Live` draws four things - a status
    header, a scrubber, a Mermaid diagram of the chart, and the event log.
    Three of those are about the *run* and are the same wherever the run is
    watched from. The fourth is about the *chart*, and inside this editor
    there is something better to put in its seat: the blocks the author wrote,
    already laid out, already marked. So the diagram is not mounted, the
    canvas takes that seat, and the three run surfaces are composed around it
    exactly as statifier-ui ships them.

    ## The seam is a read, and it stays one

    statifier-ui owns the trace wire format and the components that draw it;
    this package owns blocks, the compiler and its provenance map. Nothing in
    that split needed a callback: the components take a
    `StatifierUI.Live.State` and draw it, `StatifierBlocks.Runtime.Marks`
    turns the same read model into the marks the canvas already accepts, and
    `StatifierBlocks.Runtime.Handled` turns a clicked log entry into the block
    whose state handled it. No statifier-ui module changed, no new wire type
    exists, and the two events the components emit are statifier-ui's own -
    renamed by the caller, which is what `scrub_event` and `select_event` are
    for.

    ## Optional, and quiet when absent

    `statifier_ui` is an optional dependency here, exactly as
    `phoenix_live_view` is. The three components are resolved at runtime from
    a module read out of `:statifier_blocks, :run_pane_module` and checked
    with `function_exported?/3` - the indirection
    `StatifierBlocks.Editor.Field` uses for the expression input and
    `StatifierBlocks.Runtime.Marks` uses for the inspector reads, and for the
    same two reasons: the compiler stays quiet in a tree without the package,
    and a test can point the key at a module of its own to exercise the
    absent branch on a machine where the package is present.

    With nothing resolvable the pane still draws, still seats the canvas, and
    says in one line that the run surfaces need the package. It does not
    refuse to render: an author whose host forgot a dependency should still
    see their document.

    ## A pane with no run is not a pane

    `run_pane/1` with `state: nil` renders its inner block and nothing else -
    no wrapper element, no class, no attribute. A document with no run over it
    therefore produces exactly the markup it produced before this component
    existed, which is a property the editor's tests assert rather than assume.
    """

    use Phoenix.Component

    alias Phoenix.LiveView.TagEngine

    @doc """
    The canvas, seated in a run.

    `state` is a `StatifierUI.Live.State`, or `nil` for no run - see the
    moduledoc for what `nil` renders. `scrub_event` and `select_event` are the
    names the two statifier-ui components push, and they default to this
    package's own namespace rather than statifier-ui's, so a host embedding
    both an ops view and this editor on one page does not get one component's
    clicks in the other's handler.
    """
    attr(:id, :string,
      required: true,
      doc: "DOM id root; the three surfaces derive theirs from it."
    )

    attr(:state, :any, required: true, doc: "a `StatifierUI.Live.State`, or `nil` for no run.")
    attr(:target, :any, default: nil, doc: "`phx-target` for the two events.")
    attr(:scrub_event, :string, default: "run-scrub")
    attr(:select_event, :string, default: "run-select")

    slot(:inner_block, required: true, doc: "the canvas, in the diagram's seat.")

    @spec run_pane(map()) :: Phoenix.LiveView.Rendered.t()
    def run_pane(assigns)

    def run_pane(%{state: nil} = assigns) do
      ~H"""
      {render_slot(@inner_block)}
      """
    end

    def run_pane(assigns) do
      assigns =
        assigns
        |> assign(:status, component(:status))
        |> assign(:scrubber, component(:scrubber))
        |> assign(:event_log, component(:event_log))

      ~H"""
      <section class="sb-run" data-run="true">
        <div class="sb-run__header">
          <h2 class="sb-run__title">Run</h2>
          <div :if={@status} class="sb-run__status">
            {call(@status, %{id: "#{@id}-status", state: @state})}
          </div>
        </div>

        <div :if={@scrubber} class="sb-run__controls">
          {call(@scrubber, %{
            id: "#{@id}-scrubber",
            state: @state,
            target: @target,
            scrub_event: @scrub_event
          })}
        </div>

        <p :if={@status == nil or @scrubber == nil or @event_log == nil} class="sb-run__unavailable">
          The run surfaces need the statifier_ui package on the load path.
        </p>

        <div class="sb-run__stage">
          {render_slot(@inner_block)}
        </div>

        <div :if={@event_log} class="sb-run__log">
          {call(@event_log, %{
            id: "#{@id}-log",
            state: @state,
            target: @target,
            select_event: @select_event
          })}
        </div>
      </section>
      """
    end

    # Called the way HEEx calls `<.component />` rather than by applying the
    # function to a bare map, which is `StatifierBlocks.Editor.Icons`' rule and
    # the drawer's rule for a host tab, for the same reason both of them give:
    # an ordinary component derives a value with `assign/3`, and `assign/3`
    # raises on an assigns map carrying no change-tracking key. All three of
    # these components do exactly that.
    #
    # Every key each component reads is passed explicitly, because a dynamic
    # call site is not a compiled `~H` one and an `attr` default is applied at
    # a compiled one.
    @spec call((map() -> term()), map()) :: term()
    defp call(component, assigns) do
      TagEngine.component(
        component,
        assigns,
        {__MODULE__, {:run_pane, 1}, __ENV__.file, __ENV__.line}
      )
    end

    # The three are resolved one at a time rather than the module being held:
    # what is checked is that the function this pane is about to call exists,
    # in a tree where the module it lives in may not.
    @spec component(atom()) :: (map() -> term()) | nil
    defp component(name) do
      module = Application.get_env(:statifier_blocks, :run_pane_module, StatifierUI.Live)

      if Code.ensure_loaded?(module) and function_exported?(module, name, 1) do
        &apply(module, name, [&1])
      end
    end
  end
end
