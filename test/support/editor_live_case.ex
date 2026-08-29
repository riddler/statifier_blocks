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
         theme: session["theme"] || %{},
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
        theme={@theme}
        on_change={notifier(@test_pid)}
      />
      """
    end

    defp notifier(nil), do: nil
    defp notifier(pid), do: fn document -> send(pid, {:document, document}) end
  end

  defmodule StatifierBlocks.EditorLiveCase do
    @moduledoc """
    Case template for the tests that drive the editor through
    `Phoenix.LiveViewTest`.

    Every test using it is tagged `:liveview`, which is what the headless run
    excludes: with `phoenix_live_view` absent the editor does not compile, so
    there is nothing for these to drive. The tag is on the case rather than on
    each test so a new editor test cannot forget it.
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

    Options: `:document`, `:palette`, `:findings`, `:datamodel`, `:theme`. The
    `:datamodel` default is `nil` - no datamodel supplied - which is what the
    editor's own default is and what ADR-0005 amendment 11f makes meaningful.
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
        "theme" => Keyword.get(opts, :theme, %{}),
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
