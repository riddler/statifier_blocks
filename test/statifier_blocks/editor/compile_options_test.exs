# ADR-0005 decision 1: with `phoenix_live_view` absent the editor does not
# compile, so neither can a test that drives it. The `:liveview` tag on
# `StatifierBlocks.EditorLiveCase` excludes these from a headless *run*; this
# guard is what keeps them out of a headless *compile*.
if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.CompileOptionsTest do
    @moduledoc """
    The `compile_options` assign: the host's own compile options reaching
    every compile the editor runs - the provenance recompile behind the Run
    pane's marks, and the Source tab's listing. The fixture runs are the
    third, asserted in `StatifierBlocks.Editor.FixturesTabTest` where the
    tab's own fixtures live.

    The editor recompiles the open document to resolve a run's state ids to
    blocks. A host that runs a document to completion compiles it with
    `terminate: true`, which adds a top-level `<final>` per root-block outcome
    - so the chart the run is a run of owns a state that the same document
    compiled without the option does not. The two provenance maps disagree
    exactly there, and the disagreement is observable: the run finishes, the
    configuration is that final, and a Run pane resolving it through the
    editor's own recompile marks nothing.

    The claim is *the two maps agree*, and it is asserted twice over. Once
    directly, on the maps themselves and the resolution that reads them
    (`StatifierBlocks.Runtime.Marks.from_trace/2` is pure, and the fixture's
    run is a real recorded session rather than an implied one). Once through
    the editor, where the assign has to arrive and be forwarded: the canvas
    marks the root block with the options and does not without them.

    `async: false`, because the sibling runtime tests install stand-ins under
    the application-config key the marks resolution reads and this file needs
    the real package there.

    Every selector that asks about a mark is scoped to `.sb-node`, the rule
    `run_marks_test.exs` sets: `.sb-palette` carries data attributes of its
    own and a bare `[data-run-active]` assertion would be about whatever
    matched first.
    """

    use StatifierBlocks.EditorLiveCase, async: false

    alias StatifierBlocks.{CardRunFixtures, Editor, Provenance}
    alias StatifierBlocks.Runtime.Marks

    setup do
      Application.delete_env(:statifier_blocks, :trace_inspector_module)
      Application.delete_env(:statifier_blocks, :trace_datamodel_module)

      {:ok, run: CardRunFixtures.finished_run()}
    end

    defp mount_run(conn) do
      mount_editor(conn,
        document: CardRunFixtures.document(),
        palette: CardRunFixtures.palette(),
        declare: CardRunFixtures.declare()
      )
    end

    # The host's update: the document, the run, and - when the host has them -
    # the options it compiled that run's chart with. Driven through
    # `send_update/3` rather than by mounting with the assign, because that is
    # how a host holding a live session delivers everything else here.
    defp seat(view, state, extra \\ []) do
      Phoenix.LiveView.send_update(
        view.pid,
        Editor,
        [
          {:id, "editor"},
          {:document, CardRunFixtures.document()},
          {:palette, CardRunFixtures.palette()},
          {:declare, CardRunFixtures.declare()},
          {:run, state} | extra
        ]
      )

      render(view)
      view
    end

    # The same host update as `seat/2`, without a run: the Source tab and the
    # fixture runs are compiled whether or not anything is being watched, so
    # these cases have no run to seat.
    defp seat_options(view, extra) do
      Phoenix.LiveView.send_update(
        view.pid,
        Editor,
        [
          {:id, "editor"},
          {:document, CardRunFixtures.document()},
          {:palette, CardRunFixtures.palette()},
          {:declare, Keyword.get(extra, :declare, CardRunFixtures.declare())}
          | Keyword.delete(extra, :declare)
        ]
      )

      render(view)
      view
    end

    # The Source drawer tab's panel, opened the way `SourceTabTest` opens it.
    defp source_panel(view) do
      view |> element(".sb-drawer__strip") |> render_click()
      view |> element(~s(.sb-drawer__tab[phx-value-tab="source"])) |> render_click()
      view |> element(".sb-drawer__panel") |> render()
    end

    defp active?(view, block_id) do
      has_element?(view, ~s(.sb-node[data-block-id="#{block_id}"][data-run-active="true"]))
    end

    describe "the two provenance maps" do
      # The premise everything below rests on, asserted rather than assumed:
      # the finished run's configuration names a state the host's compile owns
      # and the editor's plain recompile has never heard of.
      #
      # sabotage: made the compiler's `completion_finals` clause unreachable,
      # so `terminate: true` emits no top-level final -> the host's own map
      # owns the state no better than the plain one and this goes red
      # (verified)
      test "only the compile that carries the host's options owns the run's last state" do
        state_id = CardRunFixtures.terminal_state_id()

        assert {:ok, owner} =
                 Provenance.owner_of_state(
                   CardRunFixtures.terminating_compiled().provenance,
                   state_id
                 )

        assert owner.block_id == CardRunFixtures.root_block()

        assert Provenance.owner_of_state(CardRunFixtures.compiled().provenance, state_id) ==
                 :error
      end

      # The same disagreement where it is felt: the resolution reads a map,
      # and which map it reads decides whether a finished run marks the root
      # block or nothing at all.
      #
      # sabotage: made `Marks.marks/2` answer a marks map even with nothing
      # marked -> a configuration the plain map owns none of comes back as an
      # empty mark set rather than no run at all and this goes red (verified)
      test "the marks a finished run resolves to differ with the map", %{run: run} do
        assert %{active: active} =
                 Marks.from_trace(run.state, CardRunFixtures.terminating_compiled().provenance)

        assert MapSet.equal?(active, MapSet.new([CardRunFixtures.root_block()]))
        assert Marks.from_trace(run.state, CardRunFixtures.compiled().provenance) == nil
      end
    end

    describe "the assign" do
      # sabotage: dropped `compile_options` from the option list
      # `refresh_run_provenance/1` passes -> the recompile is the plain one
      # again, the finished run resolves to nothing and this goes red
      # (verified)
      test "the host's options reach the recompile, so the run marks its block", %{
        conn: conn,
        run: run
      } do
        {:ok, view, _html} = mount_run(conn)
        view = seat(view, run.state, compile_options: CardRunFixtures.terminate_options())

        assert active?(view, CardRunFixtures.root_block())
      end

      # The default, pinned in the same file as the behaviour it changes: a
      # host that says nothing gets the recompile it got before the assign
      # existed.
      #
      # sabotage: defaulted the assign to `[terminate: true]` -> a host that
      # passed nothing gets a chart it never compiled and this goes red
      # (verified)
      test "without them the recompile is what it was, and marks nothing", %{
        conn: conn,
        run: run
      } do
        {:ok, view, _html} = mount_run(conn)
        view = seat(view, run.state)

        refute active?(view, CardRunFixtures.root_block())
      end

      # The recompile is keyed on its inputs, so an option list arriving after
      # the run has to move the key or the editor keeps the map it already
      # built.
      #
      # sabotage: keyed the recompile on `declare` alone rather than on the
      # whole option list -> the later update does not move the key, the map
      # built without the options stands and this goes red (verified)
      test "options arriving after the run recompile the map", %{conn: conn, run: run} do
        {:ok, view, _html} = mount_run(conn)
        view = seat(view, run.state)

        refute active?(view, CardRunFixtures.root_block())

        view = seat(view, run.state, compile_options: CardRunFixtures.terminate_options())

        assert active?(view, CardRunFixtures.root_block())
      end
    end

    describe "the Source tab" do
      # The same option list, at the second of the three compiles. The Source
      # listing is a read of what one compile produced, so a host compiling
      # with `terminate: true` and a tab listing the chart without it are
      # reading different charts - and this one is visible directly, as the
      # top-level `<final>` the option adds.
      #
      # sabotage: restored `SourceView.build(document, palette, declare:
      # declare, previous: ...)` in `refresh_source_view/1` -> the listing is
      # the plain chart again, the top-level final is absent and this goes red
      # (verified)
      test "lists the chart the host's options compile", %{conn: conn} do
        {:ok, view, _html} = mount_run(conn)
        view = seat_options(view, compile_options: CardRunFixtures.terminate_options())

        assert source_panel(view) =~ CardRunFixtures.terminal_state_id()
      end

      # The default beside the behaviour, as above.
      #
      # sabotage: made the component's own `compile_options` mount default
      # `[terminate: true]` -> a host that passed nothing gets a listing of a
      # chart it never compiled and this goes red (verified)
      test "and without them lists what it listed before", %{conn: conn} do
        {:ok, view, _html} = mount_run(conn)
        view = seat_options(view, [])

        refute source_panel(view) =~ CardRunFixtures.terminal_state_id()
      end
    end

    describe "a host that contradicts itself about :declare" do
      # The precedence the moduledoc states, asserted at a seam that can see
      # it. It could not be asserted at the marks seam: the roots change the
      # emitted `<data>` elements and the offsets around them, and the marks
      # resolution reads neither, so every assertion available there passed
      # whichever list won. The Source listing reads the bytes themselves, so
      # the losing list is simply absent from it.
      #
      # sabotage: `Keyword.put_new(:declare, ...)` instead of
      # `Keyword.put/3` in `compile_options/1` -> the option list's own
      # `:declare` wins, the decoy root is emitted and the assign's is not,
      # and both assertions below go red (verified)
      test "the declare assign wins, and the option list's :declare is not emitted", %{conn: conn} do
        {:ok, view, _html} = mount_run(conn)

        view =
          seat_options(view,
            declare: CardRunFixtures.declare() ++ [{"host_root", nil}],
            compile_options: [declare: [{"decoy_root", nil}]]
          )

        panel = source_panel(view)

        assert panel =~ "host_root"
        refute panel =~ "decoy_root"
      end
    end
  end
end
