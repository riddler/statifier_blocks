if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor do
    @moduledoc """
    The block editor: the only stateful module in the package's rendered half
    (ADR-0005 decisions 6, 8, 9, 13).

    Everything this component does is **translation**. Every author gesture
    reduces to one of the four commands `StatifierBlocks.Edit` defines, and
    the mutation, its inverse and the set of places a block may be dropped are
    all pure functions of `{document, palette}` that were tested with LiveView
    absent from the dependency tree. What is left here is turning a `phx-`
    event into a command, offering it to `StatifierBlocks.Edit.History`, and
    re-rendering.

    That split is the single most load-bearing constraint in ADR-0005, and the
    reason is drag-and-drop specifically: it is the interaction most likely to
    be tested by clicking around and declared fine, and the one most likely to
    corrupt a document when it is wrong. If the semantics of a drag lived
    here, they would be testable only through a browser driver.

    ## The drag, in two round-trips

    `dragstart` pushes one event. `Edit.Targets.slot_verdicts/3` runs once,
    the result goes into the drag session, and the re-render stamps
    `data-drop` on every slot - so every valid target highlights before the
    pointer has moved, and hover costs nothing. `drop` pushes the position, one
    `:move` is built and applied, and the tree re-renders. `dragend` clears the
    session. There is no third round-trip and no client-side validity logic.

    That one enumeration answers both halves of the drag. The accepting slots
    are `data-drop`; the refusing ones that have a data-flow reason to give
    (the 2026-08-29 ADR-0003 amendment's vocabulary) carry it as
    `data-drop-reason` beside it, so a later hover affordance has the reason
    already in the markup and still needs no round-trip and no JavaScript.
    The host's widening relation reaches all of this the way ADR-0003
    decision 6 says it does and the way nothing else could: through
    `palette.assignability`, consulted by the one `Assignability` the
    compiler's `validate/3` consults.

    ## Config, and the gate that keeps the document sound

    ADR-0002 decision 6 guarantees `slots/1` returns without raising only for
    config `validate_config/1` accepts - and an author halfway through typing
    an identifier has invalid config almost continuously. So an
    `:update_config` reaches the document only when it validates, which
    `Edit.check_config/3` enforces inside `History.commit/4`.

    In-progress form state that does not validate lives in this component's
    `drafts` assign: never in the document, never on the undo stack. It is
    overlaid onto the selected block's form at render time - values and
    findings both - so the author keeps their keystrokes and sees findings
    about the value they are currently typing, while the tree, the slot set
    and every consumer downstream still see the last config that validated.
    Crucially, the overlay never calls `slots/1`: it touches the form and
    nothing else, which is what keeps the draft from reaching a callback that
    was only promised valid config.

    ## The datamodel, and why it is one assign and no logic

    A host may hand the editor the datamodel paths it declares. The only
    thing that buys is the undeclared-path advisory ADR-0005 amendment
    11e-11g specifies: a config field a block type annotated
    `datamodel_path?: true` whose value is not in that set gets an `:info`
    finding anchored on the field. The rule itself is
    `StatifierBlocks.Datamodel`'s and is pure, so it is tested with
    LiveView absent; what happens here is one normalization on `update/3`
    and one concatenation in `rebuild/1`, which is the same translation-only
    posture as everything else in this module.

    `nil` is the default and means *no datamodel supplied*, which per 11f
    produces nothing anywhere - the check does not run at all. That is not
    the same as an empty set, which is a host declaring that its documents
    address nothing.

    ## What stays the host's

    Which palette entries a tenant may use, who may edit or publish a
    document, where it is stored, and what publishing means are all outside
    this package (decision 15).

    The 2026-08-29 shell amendment's ruling 8A adds two more, and names the
    seam for each: **slots for markup, events for actions.** The outer header -
    document identity, the document switcher, the theme control, compile and
    publish - is the `:header` slot, because markup is exactly the thing a host
    wants to own and a slot costs this package no API surface. The drawer's
    height is `on_drawer_resize` out and `drawer_height` back in, because the
    height is remembered per viewer and this package has no viewer. A host that
    renders its own publish button into the slot and receives the press as its
    own event is the intended shape; the editor draws no header of its own and
    is not waiting for permission to. So is concurrency: this is a single-session
    component, it surfaces the `revision` it loaded so a host can do
    optimistic concurrency on save, and it does not merge, rebase or resolve
    anything.

    ## Assigns

    | Assign | Required | Meaning |
    |---|---|---|
    | `id` | yes | the LiveComponent id |
    | `document` | yes | the document being edited |
    | `palette` | yes | the host's palette |
    | `findings` | no | caller-supplied findings, merged with the two `ViewModel` derives |
    | `datamodel` | no | the paths the host declares; drives the undeclared-path advisories, and `nil` (the default) turns them off entirely |
    | `on_change` | no | one-argument function called with each new document |
    | `icon` | no | function component resolving an icon *name* to markup |
    | `expression_component` | no | override for `:expression` fields (sui-bob's seam) |
    | `theme` | no | `--sb-*` custom properties for the canvas root |
    | `fixtures` | no | `%{block_id => [TruthTable.t()]}` the drawer's truth-table tab reads; `nil` (the default) means *no fixtures source*, and the drawer is still there with a count of 0 |
    | `drawer_height` | no | the drawer's height in rem, remembered **by the host** per viewer (2A); bounded on the way in |
    | `on_drawer_resize` | no | one-argument function called with each new drawer height, which is how the host comes to have one to remember |
    | `class` | no | appended to the root element's own classes |
    | `history_limit` | no | bound on the undo stack; `:infinity` by default |
    """

    use Phoenix.LiveComponent

    alias StatifierBlocks.{
      Block,
      BlockType,
      Connectors,
      Datamodel,
      Document,
      Edit,
      Finding,
      Palette,
      ViewModel
    }

    alias StatifierBlocks.Edit.{History, Targets}

    alias StatifierBlocks.Editor.{
      Canvas,
      ConfigForm,
      Drawer,
      Findings,
      Inspector,
      PaletteBrowser,
      Toolbar
    }

    alias StatifierBlocks.Shell

    @impl Phoenix.LiveComponent
    def mount(socket) do
      {:ok,
       assign(socket,
         findings: [],
         datamodel: nil,
         declared_paths: nil,
         on_change: nil,
         icon: nil,
         expression_component: nil,
         theme: %{},
         class: nil,
         history_limit: :infinity,
         history: History.new(),
         selected_id: nil,
         drag: nil,
         drafts: %{},
         pending_fields: [],
         palette_position: nil,
         palette_allowed: nil,
         palette_query: "",
         palette_sheet: false,
         fixtures: nil,
         inspector_tab: :config,
         drawer_open: false,
         drawer_height: Shell.clamp_height(nil),
         on_drawer_resize: nil,
         zoom: Shell.default_zoom(),
         fit: :manual,
         measurement: %{},
         last_error: nil
       )}
    end

    @impl Phoenix.LiveComponent
    def update(assigns, socket) do
      previous = Map.get(socket.assigns, :document)
      socket = socket |> assign(assigns) |> switch_document(previous)

      # 2A puts the remembered height on the host, so what arrives here is
      # whatever the host stored - possibly from a build with a different band,
      # possibly nothing at all. It is bounded on the way in rather than on the
      # way to the style attribute, so every reader sees one value.
      socket =
        if Map.has_key?(assigns, :drawer_height) do
          assign(socket, :drawer_height, Shell.clamp_height(assigns.drawer_height))
        else
          socket
        end

      # Normalized once per update rather than once per render: the declared
      # set is the host's input, and it changes when the host changes it, not
      # when the author moves a block.
      socket =
        if Map.has_key?(assigns, :datamodel) do
          assign(socket, :declared_paths, Datamodel.declared_paths(assigns.datamodel))
        else
          socket
        end

      socket =
        if Map.has_key?(assigns, :history_limit) and socket.assigns.history.undo == [] do
          assign(socket, :history, History.new(limit: socket.assigns.history_limit))
        else
          socket
        end

      {:ok, rebuild(socket)}
    end

    slot(:header,
      doc: """
      The host's outer header (8A): document identity, the document switcher,
      the theme control, compile and publish. The package renders the slot's
      markup and none of its own, and a host that fills nothing gets no header
      element at all.
      """
    )

    @impl Phoenix.LiveComponent
    def render(assigns) do
      assigns =
        assigns
        |> assign(:drawer, drawer_view(assigns))
        |> assign(:depth, Shell.depth(assigns.view_model.root))
        |> assign(:block_count, Shell.block_count(assigns.view_model.root))
        |> assign(:edges, Connectors.edges(assigns.view_model.root, assigns.measurement))
        |> assign(:stage, Connectors.stage(assigns.measurement))

      ~H"""
      <div
        class={["sb-editor", @class]}
        id={@id}
        data-revision={@view_model.revision}
        data-zoom={@zoom}
        data-fit={@fit}
      >
        <header :if={@header != []} class="sb-editor__header">
          {render_slot(@header)}
        </header>

        <div class="sb-editor__layout">
          <PaletteBrowser.palette_browser
            groups={@view_model.palette_groups}
            query={@palette_query}
            allowed={@palette_allowed}
            sheet_open={@palette_sheet}
            target={@myself}
            icon={@icon}
          />

          <div class="sb-editor__main">
            <Toolbar.toolbar
              zoom={@zoom}
              fit={@fit}
              depth={@depth}
              count={@block_count}
              can_undo?={History.can_undo?(@history)}
              can_redo?={History.can_redo?(@history)}
              selected?={@selected_id != nil}
              inserting?={@palette_position != nil}
              target={@myself}
            />

            <Canvas.canvas
              root={@view_model.root}
              drag={@drag}
              selected_id={@selected_id}
              target={@myself}
              icon={@icon}
              theme={@theme}
              edges={@edges}
              stage={@stage}
            />

            <Findings.findings view_model={@view_model} target={@myself} />
          </div>

          <Inspector.inspector
            tab={@inspector_tab}
            node={@selected_node}
            pending={@pending_fields}
            expression_component={@expression_component}
            target={@myself}
          />

          <Drawer.drawer
            view={@drawer}
            height={@drawer_height}
            root={@view_model.root}
            target={@myself}
          />
        </div>
      </div>
      """
    end

    # -------------------------------------------------------------- events

    @impl Phoenix.LiveComponent
    def handle_event("select", %{"block-id" => id}, socket) do
      # The sheet is an overlay over the canvas below 780 (7A), so a selection
      # made from inside it has to put it away - otherwise the block the author
      # just chose is behind the thing they chose it from.
      {:noreply, socket |> assign(selected_id: id, palette_sheet: false) |> rebuild()}
    end

    # ------------------------------------------------------------ measurement
    #
    # The 2026-08-29 amendment to decision 7, and the only event in this
    # module that is not an author's intent. `StatifierBlocksMeasure` pushes
    # the boxes the browser laid out; this stores them and nothing else.
    #
    # It touches no document, no history entry, no selection, no draft and no
    # finding - which is clause 7b's distinction between an input and a
    # decision, expressed as the shape of one clause. Feed it a different
    # measurement and the same document comes back. The payload crosses from
    # the DOM, so it is decoded by a total function rather than pattern
    # matched: `Connectors.measurement/1` drops what it cannot read and
    # anything unreadable at all becomes the empty measurement, which is the
    # same state the editor holds before the first push and with no hook
    # imported at all.
    def handle_event("measure", params, socket),
      do: {:noreply, assign(socket, :measurement, Connectors.measurement(params))}

    # ---------------------------------------------------------------- shell
    #
    # The 2026-08-29 shell amendment, and every one of its gestures is a
    # server-side command: no hook, no resize observer, no client-side state.
    # Decision 7 ships one JavaScript hook and this section adds none.

    def handle_event("zoom-in", _params, socket),
      do: {:noreply, assign(socket, zoom: Shell.zoom_in(socket.assigns.zoom), fit: :manual)}

    def handle_event("zoom-out", _params, socket),
      do: {:noreply, assign(socket, zoom: Shell.zoom_out(socket.assigns.zoom), fit: :manual)}

    # A mode, not a measurement: a computed fit needs the rendered width of an
    # element and nothing on the server has it. The canvas carries the mode as
    # `data-fit` and the stylesheet does what it can with it; the measured form
    # arrives with the read-only measurement hook (decision 7's amendment).
    def handle_event("fit", %{"fit" => "width"}, socket),
      do: {:noreply, assign(socket, :fit, :width)}

    def handle_event("fit", %{"fit" => "active"}, socket) do
      fit = if socket.assigns.selected_id, do: :active, else: socket.assigns.fit
      {:noreply, assign(socket, :fit, fit)}
    end

    def handle_event("fit", _params, socket), do: {:noreply, socket}

    def handle_event("inspector-tab", %{"tab" => tab}, socket),
      do: {:noreply, assign(socket, :inspector_tab, Shell.inspector_tab(tab))}

    def handle_event("drawer-open", _params, socket),
      do: {:noreply, assign(socket, :drawer_open, true)}

    def handle_event("drawer-close", _params, socket),
      do: {:noreply, assign(socket, :drawer_open, false)}

    # One tab today. The event exists because 1A reserves the other two places
    # (fixture runs, the datamodel view) and a tab strip that grows a handler
    # later is a different change from one that grows a tab.
    def handle_event("drawer-tab", _params, socket), do: {:noreply, socket}

    # 2A's resize, in one round trip. The height is bounded here and handed to
    # the host, which is where a per-viewer preference belongs: the package has
    # no viewer, and a component that persists one has quietly acquired a
    # session.
    def handle_event("drawer-resize", %{"height" => height}, socket) do
      clamped = Shell.clamp_height(height)

      case socket.assigns.on_drawer_resize do
        fun when is_function(fun, 1) -> fun.(clamped)
        _none -> :ok
      end

      {:noreply, assign(socket, :drawer_height, clamped)}
    end

    def handle_event("palette-sheet", _params, socket),
      do: {:noreply, update(socket, :palette_sheet, &(not &1))}

    # One round-trip, one enumeration. Everything the client needs for the
    # rest of the drag is in the markup this re-render produces.
    #
    # The root is excluded before the enumeration rather than after it. It has
    # no valid target in any case - `Edit.apply/2`'s `check_not_root/2`
    # refuses a `:move` of the root, so the correct answer is the empty set,
    # and `Targets.slot_verdicts/3` (which the drag session runs) now
    # independently arrives at the same empty set (rule 4 excludes the root's
    # own subtree, which is every block). The guard stays because it says why
    # the answer is empty at the place that asks, and it short-circuits an
    # enumeration whose result is known; it is not a workaround for the `MatchError`
    # `Assignability.valid_targets/4` used to raise here (sb-rzr).
    def handle_event("dragstart", %{"block-id" => id}, socket) do
      {:noreply, assign(socket, :drag, drag_session(socket, id))}
    end

    def handle_event("dragend", _params, socket) do
      {:noreply, assign(socket, :drag, nil)}
    end

    def handle_event("drop", params, socket) do
      %{"block-id" => id, "parent-id" => parent_id, "slot" => slot, "index" => index} = params

      socket =
        socket
        |> assign(:drag, nil)
        |> commit({:move, id, {parent_id, slot, to_index(index)}})

      {:noreply, socket}
    end

    def handle_event("remove", %{"block-id" => id}, socket) do
      socket =
        socket
        |> update(:selected_id, fn selected -> if selected == id, do: nil, else: selected end)
        |> update(:drafts, &Map.delete(&1, id))
        |> commit({:remove, id})

      {:noreply, socket}
    end

    def handle_event("undo", _params, socket) do
      %{history: history, palette: palette, document: document} = socket.assigns
      {:noreply, replay(socket, History.undo(history, palette, document))}
    end

    def handle_event("redo", _params, socket) do
      %{history: history, palette: palette, document: document} = socket.assigns
      {:noreply, replay(socket, History.redo(history, palette, document))}
    end

    # d8: the "+" path. The palette opens filtered by the same predicate a
    # drag uses, against a probe block of each candidate type.
    def handle_event("palette-open", params, socket) do
      %{"parent-id" => parent_id, "slot" => slot, "index" => index} = params
      position = {parent_id, slot, to_index(index)}

      {:noreply,
       assign(socket,
         palette_position: position,
         palette_allowed: accepted_types(socket, parent_id, slot),
         palette_query: ""
       )}
    end

    def handle_event("palette-close", _params, socket) do
      {:noreply, assign(socket, palette_position: nil, palette_allowed: nil)}
    end

    def handle_event("palette-search", %{"q" => query}, socket) do
      {:noreply, assign(socket, :palette_query, query)}
    end

    def handle_event("palette-pick", %{"type" => type}, socket) do
      socket = assign(socket, :palette_sheet, false)
      {:noreply, insert_from_palette(socket, type, socket.assigns.palette_position)}
    end

    def handle_event("config-change", %{"block-id" => id} = params, socket) do
      config = ConfigForm.decode(fields_for(socket, id), params, effective_config(socket, id))
      {:noreply, change_config(socket, id, config)}
    end

    # A draft is config the document never accepted, so there is no command
    # to invert and no history entry to step back through - discarding is the
    # only way out of one, and the form returns to what the document holds.
    def handle_event("discard-draft", %{"block-id" => id}, socket) do
      {:noreply, socket |> update(:drafts, &Map.delete(&1, id)) |> rebuild()}
    end

    def handle_event("field-list-add", %{"key" => key}, socket) do
      {:noreply, update_list(socket, key, &(&1 ++ [""]))}
    end

    def handle_event("field-list-remove", %{"key" => key, "index" => index}, socket) do
      {:noreply, update_list(socket, key, &List.delete_at(&1, to_index(index)))}
    end

    # ------------------------------------------------------------ commands

    # The one place a command reaches the document. Every gesture funnels
    # here, so the gate, the undo stack and the host notification each have
    # one implementation rather than one per event.
    @spec commit(Phoenix.LiveView.Socket.t(), Edit.t()) :: Phoenix.LiveView.Socket.t()
    defp commit(socket, command) do
      %{history: history, palette: palette, document: document} = socket.assigns

      case History.commit(history, palette, document, command) do
        {:ok, new_history, new_document} ->
          socket
          |> assign(history: new_history, document: new_document, last_error: nil)
          |> notify_change(new_document)
          |> rebuild()

        {:error, reason} ->
          socket |> assign(:last_error, reason) |> rebuild()
      end
    end

    # Undo and redo differ only in which stack they pop, and `History` has
    # already done that by the time this runs - so both arrive here as the
    # same result tuple and there is one place that reconciles the socket.
    # Drafts are dropped wholesale: a draft is by definition config the
    # document never accepted, and keeping one across a history move would
    # mean showing the author a value that belongs to a document state they
    # just stepped out of.
    @spec replay(Phoenix.LiveView.Socket.t(), {:ok, History.t(), Document.t()} | {:error, term()}) ::
            Phoenix.LiveView.Socket.t()
    defp replay(socket, result) do
      case result do
        {:ok, new_history, new_document} ->
          socket
          |> assign(history: new_history, document: new_document, drafts: %{}, last_error: nil)
          |> notify_change(new_document)
          |> rebuild()

        {:error, reason} ->
          socket |> assign(:last_error, reason) |> rebuild()
      end
    end

    # Ids are minted here, at gesture time, and baked into the `:insert`
    # (decision 2). That is what keeps the recorded command serializable and
    # a command log replayable: duplication and palette insertion need
    # entropy, and admitting an id generator into the pure algebra would
    # have cost it determinism.
    @spec insert_from_palette(Phoenix.LiveView.Socket.t(), Block.type_name(), Edit.target() | nil) ::
            Phoenix.LiveView.Socket.t()
    defp insert_from_palette(socket, _type, nil), do: socket

    defp insert_from_palette(socket, type, position) do
      case new_block(socket.assigns.palette, type) do
        {:ok, block} ->
          socket
          |> assign(palette_position: nil, palette_allowed: nil, selected_id: block.id)
          |> commit({:insert, position, block})

        :error ->
          assign(socket, :last_error, {:unknown_block_type, type})
      end
    end

    @spec new_block(Palette.t(), Block.type_name()) :: {:ok, Block.t()} | :error
    defp new_block(palette, type) do
      case Palette.fetch(palette, type) do
        {:ok, module} ->
          config =
            %{}
            |> module.config_schema()
            |> Map.new(fn %{key: key, default: default} -> {key, default} end)

          {:ok, Block.new(type, config: config, type_version: module.current_version())}

        _error ->
          :error
      end
    end

    @spec change_config(Phoenix.LiveView.Socket.t(), Block.id(), Block.config()) ::
            Phoenix.LiveView.Socket.t()
    defp change_config(socket, id, config) do
      %{history: history, palette: palette, document: document} = socket.assigns

      case History.commit(history, palette, document, {:update_config, id, config}) do
        {:ok, new_history, new_document} ->
          socket
          |> assign(history: new_history, document: new_document, last_error: nil)
          |> update(:drafts, &Map.delete(&1, id))
          |> notify_change(new_document)
          |> rebuild()

        {:error, {:invalid_config, ^id, _findings}} ->
          socket |> update(:drafts, &Map.put(&1, id, config)) |> rebuild()

        {:error, reason} ->
          socket |> assign(:last_error, reason) |> rebuild()
      end
    end

    # `key` arrives from the row's `phx-value-key`, which is the field's
    # identity rather than its address - so the rows are read and written
    # through the field's own `value_path` (ADR-0002 decision 7, amended
    # 2026-08-27), the same place the form's other writes go. A key naming
    # no field in the selected block's schema edits nothing, which is the
    # same crafted-payload guard `ConfigForm.decode/3` applies.
    @spec update_list(Phoenix.LiveView.Socket.t(), String.t(), ([term()] -> [term()])) ::
            Phoenix.LiveView.Socket.t()
    defp update_list(socket, key, fun) do
      with id when not is_nil(id) <- socket.assigns.selected_id,
           %ViewModel.Field{} = field <- Enum.find(fields_for(socket, id), &(&1.key == key)) do
        config = effective_config(socket, id)
        path = ViewModel.Field.value_path(field)

        rows =
          case BlockType.fetch_value(config, path) do
            {:ok, value} -> List.wrap(value)
            :error -> []
          end

        change_config(socket, id, BlockType.put_value(config, path, fun.(rows)))
      else
        _none -> socket
      end
    end

    # 2A: the drawer closes on a document switch. A drawer left open across one
    # would be showing the new document's blocks under the old one's subject,
    # and the selection it follows names a block that is not there any more -
    # so the selection goes with it, along with the drafts and the pending
    # insert, all three of which address ids the new document does not hold.
    @spec switch_document(Phoenix.LiveView.Socket.t(), Document.t() | nil) ::
            Phoenix.LiveView.Socket.t()
    defp switch_document(socket, nil), do: socket

    defp switch_document(socket, %Document{id: id}) do
      if socket.assigns.document.id == id do
        socket
      else
        assign(socket,
          drawer_open: false,
          selected_id: nil,
          drafts: %{},
          palette_position: nil,
          palette_allowed: nil,
          palette_sheet: false
        )
      end
    end

    @spec drawer_view(map()) :: Shell.drawer()
    defp drawer_view(assigns) do
      Shell.drawer_view(%{
        open?: assigns.drawer_open,
        fixtures: assigns.fixtures,
        selected_id: assigns.selected_id
      })
    end

    # ------------------------------------------------------------ derived

    # The view model is rebuilt from `{document, palette, findings}` after
    # every state change rather than patched. It is a projection: nothing
    # here memoizes a schema across an edit, because `config_schema/1` is a
    # function of config (ADR-0002 decision 7), not a cache of one.
    @spec rebuild(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
    defp rebuild(socket) do
      %{
        document: document,
        palette: palette,
        findings: findings,
        declared_paths: declared_paths
      } = socket.assigns

      # The advisories go in through the same caller-findings seam every
      # other supplied finding uses, so `ViewModel.build/3` needs no notion
      # of a datamodel and the routing is the one already tested.
      advisories = Datamodel.findings(document, palette, declared_paths)
      view_model = ViewModel.build(document, palette, findings ++ advisories)

      selected = selected_node(socket, view_model)

      socket
      |> assign(:view_model, view_model)
      |> assign(:selected_node, selected)
      |> assign(:pending_fields, pending_fields(socket, selected))
    end

    # The fields the author has typed that the document does not hold.
    #
    # Decision 9 commits a config as a unit, which is the invariant that makes
    # a block type with two required fields and no usable defaults impossible
    # to fill one field at a time - fill the first and the gate refuses,
    # because the second is still empty. The draft is what carries the first
    # value forward into the second edit, and this is what says so on screen:
    # without it the author is told twice that a value they typed correctly is
    # wrong, and the revision never moves.
    #
    # Compared against the document rather than against the draft's key set,
    # so a field the author typed and then typed back is not still reported as
    # outstanding.
    @spec pending_fields(Phoenix.LiveView.Socket.t(), ViewModel.Node.t() | nil) ::
            [ViewModel.Field.t()]
    defp pending_fields(_socket, nil), do: []
    defp pending_fields(_socket, %ViewModel.Node{form: nil}), do: []

    defp pending_fields(socket, %ViewModel.Node{block_id: id, form: form}) do
      case Map.fetch(socket.assigns.drafts, id) do
        :error ->
          []

        {:ok, draft} ->
          committed = committed_config(socket.assigns.document, id)

          Enum.filter(form.fields, fn field ->
            path = ViewModel.Field.value_path(field)

            BlockType.fetch_value(draft, path) != BlockType.fetch_value(committed, path)
          end)
      end
    end

    @spec selected_node(Phoenix.LiveView.Socket.t(), ViewModel.t()) :: ViewModel.Node.t() | nil
    defp selected_node(socket, %ViewModel{root: root}) do
      case socket.assigns.selected_id do
        nil -> nil
        id -> root |> find_node(id) |> overlay_draft(socket, id)
      end
    end

    @spec find_node(ViewModel.Node.t(), Block.id()) :: ViewModel.Node.t() | nil
    defp find_node(%ViewModel.Node{block_id: id} = node, id), do: node

    defp find_node(%ViewModel.Node{slots: slots}, id) do
      slots
      |> Enum.flat_map(& &1.children)
      |> Enum.find_value(fn child -> find_node(child, id) end)
    end

    # Decision 9's draft, made visible without letting it near the document.
    # Values come from the draft so the author keeps their keystrokes;
    # findings come from `validate_config/1` on the draft so they are about
    # the value being typed rather than the last one that validated. Only
    # the form is touched - `slots/1` is never called on a draft, which is
    # the promise ADR-0002 decision 6 is owed.
    @spec overlay_draft(ViewModel.Node.t() | nil, Phoenix.LiveView.Socket.t(), Block.id()) ::
            ViewModel.Node.t() | nil
    defp overlay_draft(nil, _socket, _id), do: nil
    defp overlay_draft(%ViewModel.Node{form: nil} = node, _socket, _id), do: node

    defp overlay_draft(%ViewModel.Node{} = node, socket, id) do
      case Map.fetch(socket.assigns.drafts, id) do
        :error -> node
        {:ok, draft} -> apply_draft(node, socket.assigns.palette, draft)
      end
    end

    @spec apply_draft(ViewModel.Node.t(), Palette.t(), Block.config()) :: ViewModel.Node.t()
    defp apply_draft(%ViewModel.Node{} = node, palette, draft) do
      by_key = draft_findings(palette, node, draft)
      keys = MapSet.new(node.form.fields, & &1.key)

      fields =
        Enum.map(node.form.fields, fn field ->
          %{
            field
            | value: Map.get(draft, field.key, field.value),
              findings: Map.get(by_key, field.key, [])
          }
        end)

      unrouted =
        by_key
        |> Enum.reject(fn {key, _findings} -> MapSet.member?(keys, key) end)
        |> Enum.sort()
        |> Enum.flat_map(fn {_key, findings} -> findings end)

      %{node | form: %{node.form | fields: fields, unrouted: unrouted}}
    end

    @spec draft_findings(Palette.t(), ViewModel.Node.t(), Block.config()) ::
            %{optional(String.t()) => [Finding.t()]}
    defp draft_findings(palette, %ViewModel.Node{block_id: id, type: type}, draft) do
      with {:ok, module} <- Palette.fetch(palette, type),
           {:error, findings} <- module.validate_config(draft) do
        Enum.group_by(
          findings,
          fn {key, _message} -> key end,
          fn {key, message} -> Finding.new({:config, id, key}, :config, message) end
        )
      else
        _ok_or_missing -> %{}
      end
    end

    # d8's filter is d5's predicate, asked once per candidate type against a
    # probe block. Not a parallel implementation - the same function, with a
    # block that is not in the document yet, which is exactly the case
    # `droppable_slots_for/3` exists to serve.
    @spec accepted_types(Phoenix.LiveView.Socket.t(), Block.id(), Block.slot_name()) ::
            MapSet.t(Block.type_name())
    defp accepted_types(socket, parent_id, slot) do
      %{document: document, palette: palette} = socket.assigns

      palette.types
      |> Map.keys()
      |> Enum.filter(fn type ->
        case new_block(palette, type) do
          {:ok, probe} ->
            {parent_id, slot} in Targets.droppable_slots_for(document, palette, probe)

          :error ->
            false
        end
      end)
      |> MapSet.new()
    end

    # Everything the drag needs, from one enumeration: the accepting slots,
    # and the reason for each slot that refused.
    #
    # The reasons ride *beside* `:droppable` rather than replacing it. The
    # accepting set is what decides `data-drop`, and it is a `MapSet` for
    # the membership test `Slot` runs once per rendered slot; a reason is
    # only ever read for a slot that already lost that test, so folding the
    # two into one map would make the hot path pay for the explanation.
    # Refusals with no data-flow reason (`nil`) are left out of the map
    # entirely - absent and "present, `nil`" would render identically, and
    # one of them is a lie about having asked.
    @spec drag_session(Phoenix.LiveView.Socket.t(), Block.id()) :: map()
    defp drag_session(socket, id) do
      verdicts = slot_verdicts_for(socket, id)

      droppable =
        for({slot_ref, :ok} <- verdicts, do: slot_ref) |> MapSet.new()

      reasons =
        for {slot_ref, {:refused, reason}} <- verdicts, reason != nil, into: %{} do
          {slot_ref, reason}
        end

      %{block_id: id, droppable: droppable, reasons: reasons}
    end

    @spec slot_verdicts_for(Phoenix.LiveView.Socket.t(), Block.id()) ::
            [{{Block.id(), Block.slot_name()}, Targets.slot_verdict()}]
    defp slot_verdicts_for(socket, id) do
      %{document: document, palette: palette, view_model: view_model} = socket.assigns

      with false <- id == view_model.root.block_id,
           block when not is_nil(block) <- find_document_block(document, id) do
        Targets.slot_verdicts(document, palette, block)
      else
        _root_or_missing -> []
      end
    end

    @spec find_document_block(Document.t(), Block.id()) :: Block.t() | nil
    defp find_document_block(document, id),
      do: Enum.find(Document.blocks(document), &(&1.id == id))

    @spec fields_for(Phoenix.LiveView.Socket.t(), Block.id()) :: [ViewModel.Field.t()]
    defp fields_for(socket, id) do
      case find_node(socket.assigns.view_model.root, id) do
        %ViewModel.Node{form: %ViewModel.Form{fields: fields}} -> fields
        _none -> []
      end
    end

    @spec effective_config(Phoenix.LiveView.Socket.t(), Block.id()) :: Block.config()
    defp effective_config(socket, id) do
      case Map.fetch(socket.assigns.drafts, id) do
        {:ok, draft} -> draft
        :error -> committed_config(socket.assigns.document, id)
      end
    end

    @spec committed_config(Document.t(), Block.id()) :: Block.config()
    defp committed_config(document, id) do
      case Enum.find(Document.blocks(document), &(&1.id == id)) do
        %Block{config: config} -> config
        nil -> %{}
      end
    end

    @spec notify_change(Phoenix.LiveView.Socket.t(), Document.t()) :: Phoenix.LiveView.Socket.t()
    defp notify_change(socket, document) do
      case socket.assigns.on_change do
        fun when is_function(fun, 1) -> fun.(document)
        _none -> :ok
      end

      socket
    end

    # A DOM value, so it is a string; `to_index/1` is total because the DOM
    # is not a trusted source. A non-numeric index becomes 0, which
    # `Edit.apply/2` then accepts or refuses on its own terms.
    @spec to_index(term()) :: non_neg_integer()
    defp to_index(index) when is_integer(index) and index >= 0, do: index

    defp to_index(index) when is_binary(index) do
      case Integer.parse(index) do
        {int, ""} when int >= 0 -> int
        _other -> 0
      end
    end

    defp to_index(_index), do: 0
  end
end
