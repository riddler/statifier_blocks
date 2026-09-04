if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.EditorEndpoint do
    @moduledoc """
    The smallest endpoint `Phoenix.LiveViewTest.live_isolated/3` will accept.

    It serves nothing. It exists because a LiveView needs an endpoint to sign
    its session and to own its socket, and ADR-0005's consequence that
    "`LiveViewTest` covers the shell's event translation" needs a real
    connected mount to be true rather than aspirational.
    """

    use Phoenix.Endpoint, otp_app: :statifier_blocks

    socket("/live", Phoenix.LiveView.Socket)

    plug(:not_found)

    @doc false
    def not_found(conn, _opts), do: Plug.Conn.send_resp(conn, 404, "")
  end

  defmodule StatifierBlocks.EditorHost do
    @moduledoc """
    A host LiveView that does nothing but embed the editor - which is exactly
    what a real host does, and the reason the editor is a `LiveComponent`
    rather than a `LiveView`.

    `on_change` is built here rather than passed through the session: a
    session is signed with `:erlang.term_to_binary/1`, which carries pids
    happily and functions not at all. So the test's pid crosses the boundary
    and the closure is made on this side.
    """

    use Phoenix.LiveView

    @impl Phoenix.LiveView
    def mount(_params, session, socket) do
      {:ok,
       assign(socket,
         document: session["document"],
         palette: session["palette"],
         findings: session["findings"] || [],
         datamodel: session["datamodel"],
         declare: session["declare"] || [],
         theme: session["theme"] || %{},
         fit: session["fit"],
         fixtures: session["fixtures"],
         invoke_types: session["invoke_types"] || [],
         value_candidates: session["value_candidates"] || %{},
         drawer_height: session["drawer_height"],
         header: session["header"],
         host_tabs: session["host_tabs"] || [],
         feed: session["feed"] || [],
         icon: session["icon"] && (&host_icon/1),
         test_pid: session["test_pid"]
       )}
    end

    @impl Phoenix.LiveView
    def render(assigns) do
      ~H"""
      <.live_component
        module={StatifierBlocks.Editor}
        id="editor"
        document={@document}
        palette={@palette}
        findings={@findings}
        datamodel={@datamodel}
        declare={@declare}
        theme={@theme}
        fit={@fit}
        icon={@icon}
        fixtures={@fixtures}
        invoke_types={@invoke_types}
        value_candidates={@value_candidates}
        drawer_height={@drawer_height}
        drawer_tabs={drawer_tabs(@host_tabs, @feed)}
        on_change={notifier(@test_pid)}
        on_drawer_resize={height_notifier(@test_pid)}
      >
        <:header :if={@header}>
          <p class="host-header">{@header}</p>
        </:header>
      </.live_component>
      """
    end

    # A host swapping the open document, which is 8A's half of the split: which
    # document is open is the host's decision, and 2A says the drawer closes
    # when it changes.
    @impl Phoenix.LiveView
    def handle_info({:swap_document, document}, socket),
      do: {:noreply, assign(socket, :document, document)}

    # The seam's live half, driven the way a host drives it: the feed is this
    # LiveView's own assign, and the descriptors carrying it are rebuilt on
    # the re-render that assign causes.
    def handle_info({:feed, line}, socket),
      do: {:noreply, assign(socket, :feed, socket.assigns.feed ++ [line])}

    def handle_info({:host_tabs, tabs}, socket),
      do: {:noreply, assign(socket, :host_tabs, tabs)}

    # The `drawer_tabs` descriptors. The tab called `runs` renders the feed
    # and counts it, which is what makes both live; every other tab draws its
    # own name and reports the count it was declared with.
    defp drawer_tabs(tabs, feed) do
      Enum.map(tabs, fn
        %{id: "runs"} = tab ->
          %{tab | count: length(feed)} |> Map.put(:content, &host_feed(&1, feed))

        tab ->
          Map.put(tab, :content, &host_panel/1)
      end)
    end

    defp host_feed(assigns, feed) do
      assigns = assign(assigns, :feed, feed)

      ~H"""
      <ul class="host-feed" data-tab={@id} data-count={@count}>
        <li :for={line <- @feed}>{line}</li>
      </ul>
      """
    end

    defp host_panel(assigns) do
      ~H"""
      <p class="host-panel" data-tab={@id}>panel for {@id}</p>
      """
    end

    # A host's own icon component, in the shape the `icon` assign takes: a
    # name in, markup out. Built here for the same reason `on_change` is - a
    # session is signed with `:erlang.term_to_binary/1` and carries no
    # functions - and deliberately unlike the shipped set, so a test can tell
    # which one rendered.
    #
    # It derives its one value with `assign/3` rather than inline in the
    # template, which is what an ordinary host component does and what the
    # seam used to make impossible (sb-b8g): the editor applied this function
    # to a bare map with no `__changed__` key, so the helper raised. Every
    # test that mounts with `icon: :host` now runs through that path.
    defp host_icon(assigns) do
      assigns = assign(assigns, :label, "icon: #{assigns.name}")

      ~H"""
      <span class={@class} data-icon={@name} data-host-icon="true" title={@label} aria-hidden="true">
        <svg viewBox="0 0 16 16"><circle cx="8" cy="8" r="6" /></svg>
      </span>
      """
    end

    defp notifier(nil), do: nil
    defp notifier(pid), do: fn document -> send(pid, {:document, document}) end

    # 8A's other half of the host seam: the height arrives as an event and the
    # host is what remembers it. Here the "host" is a test process.
    defp height_notifier(nil), do: nil
    defp height_notifier(pid), do: fn height -> send(pid, {:drawer_height, height}) end
  end

  defmodule StatifierBlocks.EditorLiveCase do
    @moduledoc """
    Case template for the tests that drive the editor through
    `Phoenix.LiveViewTest`.

    Every test using it is tagged `:liveview`, which is what the headless run
    excludes: with `phoenix_live_view` absent the editor does not compile, so
    there is nothing for these to drive. The tag is on the case rather than on
    each test so a new editor test cannot forget it.

    `Phoenix.Component.assign/3` drops a value equal to the one already held, so
    re-sending an identical value never reaches `update/2`: a re-render test has
    to move a value for there to be a re-render at all.
    """

    use ExUnit.CaseTemplate

    alias StatifierBlocks.EditorFixtures

    using do
      quote do
        import Phoenix.ConnTest
        import Phoenix.LiveViewTest
        import StatifierBlocks.EditorLiveCase

        alias StatifierBlocks.{Block, Document, EditorFixtures, Finding, Palette}

        @endpoint StatifierBlocks.EditorEndpoint
        @moduletag :liveview
      end
    end

    setup do
      {:ok, conn: Phoenix.ConnTest.build_conn()}
    end

    @doc """
    Mounts the editor over a document, connected, and returns the live view.

    Options: `:document`, `:palette`, `:findings`, `:datamodel`, `:declare`, `:theme`,
    `:fit`, `:fixtures`, `:invoke_types`, `:value_candidates`, `:drawer_height`,
    `:header`, `:icon`,
    `:host_tabs` and `:feed` - the last five being the
    shell amendment's host seam (8A), a truth-table source, the height the host
    remembered, markup for the header slot, and the drawer tabs the host
    contributes together with the feed the one called `runs` renders.
    `:host_tabs` takes `%{id:, title:, count:}` descriptors; this host supplies
    the `content` function for each. The
    `:datamodel` default is `nil` - no datamodel supplied - which is what the
    editor's own default is and what ADR-0005 amendment 11f makes meaningful.
    `:declare` defaults to `[]`, the compile call's roots the editor reads
    for amendment 11k.
    The other defaults are
    the signup wizard and the core palette, which is the pairing that leaves
    `signup.track_conversion` unresolvable.

    A macro rather than a function because `Phoenix.LiveViewTest.live_isolated/3`
    is one: it expands to a call carrying the *caller's* `@endpoint`, so a
    helper that wrapped it in a plain function would capture this module's
    endpoint attribute instead of the test's.
    """
    defmacro mount_editor(conn, opts \\ []) do
      quote do
        Phoenix.LiveViewTest.live_isolated(unquote(conn), StatifierBlocks.EditorHost,
          session: StatifierBlocks.EditorLiveCase.session(unquote(opts), self())
        )
      end
    end

    @doc "The session `mount_editor/2` signs, exposed so the macro stays one line."
    @spec session(keyword(), pid()) :: map()
    def session(opts, test_pid) do
      %{
        "document" => Keyword.get_lazy(opts, :document, &EditorFixtures.signup_wizard/0),
        "palette" => Keyword.get_lazy(opts, :palette, &EditorFixtures.palette/0),
        "findings" => Keyword.get(opts, :findings, []),
        "datamodel" => Keyword.get(opts, :datamodel),
        "declare" => Keyword.get(opts, :declare, []),
        "theme" => Keyword.get(opts, :theme, %{}),
        "fit" => Keyword.get(opts, :fit),
        "fixtures" => Keyword.get(opts, :fixtures),
        "invoke_types" => Keyword.get(opts, :invoke_types, []),
        "value_candidates" => Keyword.get(opts, :value_candidates, %{}),
        "drawer_height" => Keyword.get(opts, :drawer_height),
        "header" => Keyword.get(opts, :header),
        "host_tabs" => Keyword.get(opts, :host_tabs, []),
        "feed" => Keyword.get(opts, :feed, []),
        "icon" => Keyword.get(opts, :icon),
        "test_pid" => test_pid
      }
    end

    @doc """
    The document the editor last handed its host, or `nil` if it has not
    changed. Read from the mailbox, so it is the real notification path a host
    would use rather than a peek into the component's assigns.
    """
    @spec latest_document() :: StatifierBlocks.Document.t() | nil
    def latest_document do
      receive do
        {:document, document} -> drain(document)
      after
        0 -> nil
      end
    end

    defp drain(document) do
      receive do
        {:document, next} -> drain(next)
      after
        0 -> document
      end
    end
  end
end
