# ADR-0005 decision 1: with `phoenix_live_view` absent the editor does not
# compile, so neither can a test that drives it. The `:liveview` tag on
# `StatifierBlocks.EditorLiveCase` excludes these from a headless *run*; this
# guard is what keeps them out of a headless *compile*.
if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.RunPaneTest do
    @moduledoc """
    The Run pane end to end: a real card-processing run, statifier-ui's own
    components, and the canvas in the diagram's seat.

    Everything here drives the pane the way an author does - clicking the
    scrubber's buttons and the event log's entries - rather than by calling the
    read model's functions and re-rendering. The claim the bead makes is that
    *scrubbing moves the marks*, and a test that moved the selection itself
    would assert the resolution while leaving the two events, their names and
    their target untested, which is the half most likely to be wrong.

    `async: false`, because the sibling runtime tests install stand-ins under
    the same application-config keys this file needs the real package at.

    Every selector that asks about a mark is scoped to `.sb-node`, the rule
    `run_marks_test.exs` sets: `.sb-palette` carries data attributes of its own
    and a bare `[data-run-active]` assertion would be about whatever matched
    first.
    """

    use StatifierBlocks.EditorLiveCase, async: false

    alias StatifierBlocks.{CardRunFixtures, Editor}

    setup do
      Application.delete_env(:statifier_blocks, :trace_inspector_module)
      Application.delete_env(:statifier_blocks, :trace_datamodel_module)
      Application.delete_env(:statifier_blocks, :run_pane_module)

      on_exit(fn ->
        Application.delete_env(:statifier_blocks, :run_pane_module)
      end)

      {:ok, run: CardRunFixtures.run()}
    end

    defp seat(view, run) do
      Phoenix.LiveView.send_update(view.pid, Editor,
        id: "editor",
        document: CardRunFixtures.document(),
        palette: CardRunFixtures.palette(),
        declare: CardRunFixtures.declare(),
        run: run
      )

      render(view)
      view
    end

    defp mount_run(conn, run) do
      {:ok, view, _html} =
        mount_editor(conn,
          document: CardRunFixtures.document(),
          palette: CardRunFixtures.palette(),
          declare: CardRunFixtures.declare()
        )

      {:ok, seat(view, run)}
    end

    defp active?(view, block_id) do
      has_element?(view, ~s(.sb-node[data-block-id="#{block_id}"][data-run-active="true"]))
    end

    defp scrub(view, move) do
      view |> element(~s(.sb-run [data-move="#{move}"])) |> render_click()
      view
    end

    defp open_datamodel(view) do
      view |> element(".sb-drawer__strip") |> render_click()
      view |> element(~s(.sb-drawer__tab[phx-value-tab="datamodel"])) |> render_click()
      view
    end

    defp select(view, block_id) do
      view
      |> element(~s(.sb-node[data-block-id="#{block_id}"] > .sb-node__chrome > .sb-node__label))
      |> render_click()

      view
    end

    describe "the canvas in the diagram's seat" do
      # Sabotage: dropped the run clause from `Editor`'s `marks/1`, so the
      # marks fell back to the host's empty `active_ids` - nothing on the
      # canvas lit at all and this went red on the first assertion (verified).
      test "marks the block the run is at, at the tip", %{conn: conn, run: run} do
        {:ok, view} = mount_run(conn, run.state)

        assert active?(view, CardRunFixtures.settle_block())
        refute active?(view, CardRunFixtures.entry_block())
      end

      # Two Prevs from the live tip: the first pins the newest macrostep, the
      # second selects the one below it, which in a two-macrostep run is the
      # one the document opened at.
      #
      # Sabotage: had the `"run-scrub"` handler write the move's atom into
      # `:selection` directly instead of going through
      # `Runtime.Selection.scrub/2` - the read model held `{:macrostep, :prev}`,
      # every read fell to its catch-all, and the marks stayed on the tip
      # (verified).
      test "scrubbing back moves the marks to where the run was", %{conn: conn, run: run} do
        {:ok, view} = mount_run(conn, run.state)

        view |> scrub("prev") |> scrub("prev")

        assert active?(view, CardRunFixtures.entry_block())
        refute active?(view, CardRunFixtures.settle_block())
      end

      # Sabotage: dropped `phx-target` from the pane's call, so the events went
      # to the host LiveView instead of the component - the click raised
      # rather than moving anything (verified).
      test "Live brings the marks back to the tip", %{conn: conn, run: run} do
        {:ok, view} = mount_run(conn, run.state)

        view |> scrub("first") |> scrub("live")

        assert active?(view, CardRunFixtures.settle_block())
      end

      # Sabotage: had the pane render `diagram/1` beside the canvas - the
      # Mermaid `<pre>` reached the markup, which is the one statifier-ui
      # surface this pane exists to replace (verified).
      test "mounts no diagram", %{conn: conn, run: run} do
        {:ok, view} = mount_run(conn, run.state)

        html = render(view)

        refute html =~ "statifier-ui-diagram"
        refute html =~ ~s(class="mermaid)
        assert has_element?(view, ".sb-run__stage .sb-canvas")
      end
    end

    describe "the event log" do
      # The capture event was handled by the block that was waiting for it, and
      # that is the block a click on its entry selects.
      #
      # Sabotage: had `select_handling_block/2` resolve the transition's first
      # TARGET rather than its source - the click selected the block the run
      # moved into rather than the one that handled the event, and this went
      # red naming it (verified).
      test "a click selects the block whose state handled the step", %{conn: conn, run: run} do
        {:ok, view} = mount_run(conn, run.state)

        refute has_element?(
                 view,
                 ~s(.sb-node.sb-node--selected[data-block-id="#{CardRunFixtures.entry_block()}"])
               )

        view
        |> element(~s(.sb-run [phx-value-macrostep="2"]))
        |> render_click()

        assert has_element?(
                 view,
                 ~s(.sb-node.sb-node--selected[data-block-id="#{CardRunFixtures.entry_block()}"])
               )
      end

      # The initialize step entered states rather than transitioning between
      # them, so no block handled it and the selection is left alone.
      #
      # Sabotage: had `select_handling_block/2` fall back to the run's first
      # marked block on `:error` - clicking the initialize step moved the
      # author's selection off the block they had chosen (verified).
      test "a step no transition was selected in leaves the selection alone", %{
        conn: conn,
        run: run
      } do
        {:ok, view} = mount_run(conn, run.state)

        select(view, CardRunFixtures.settle_block())

        view |> element(~s(.sb-run [phx-value-macrostep="1"])) |> render_click()

        assert has_element?(
                 view,
                 ~s(.sb-node.sb-node--selected[data-block-id="#{CardRunFixtures.settle_block()}"])
               )
      end
    end

    describe "the Datamodel tab" do
      # Sabotage: had `held_values/1` answer `%{}` whatever the run held - the
      # cell read "not written" for a path the run had plainly written, and
      # this went red (verified).
      test "shows what the run held beside what the document declares", %{conn: conn, run: run} do
        {:ok, view} = mount_run(conn, run.state)

        html = view |> select(CardRunFixtures.settle_block()) |> open_datamodel() |> render()

        row = known_row(html, CardRunFixtures.written_path())

        assert row != nil, "the declared environment holds the written path"
        assert row =~ ~s(data-held="&quot;settled&quot;")
      end

      # Sabotage: dropped the `:if={@run?}` from the header cell, leaving a
      # table whose body rows carry one more cell than its head - the column
      # appeared over a document nobody was running (verified).
      test "draws no held column with no run seated", %{conn: conn, run: run} do
        {:ok, view} = mount_run(conn, run.state)

        html =
          view
          |> seat(nil)
          |> select(CardRunFixtures.settle_block())
          |> open_datamodel()
          |> render()

        refute html =~ "Held here"
        refute html =~ "data-held"
      end
    end

    describe "a document with no run" do
      # The pane is a wrapper or it is nothing: with no run its clause renders
      # its inner block and no element of its own, so the editor draws exactly
      # what it drew before this component existed.
      #
      # Sabotage: had the `state: nil` clause render `<div class="sb-run">`
      # around the slot instead of the bare slot - the two renders stopped
      # matching and this went red on the diff (verified).
      test "renders exactly what it renders with the pane never seated", %{conn: conn, run: run} do
        {:ok, view} = mount_run(conn, nil)
        before = render(view)

        seated = view |> seat(run.state) |> render()
        after_clearing = view |> seat(nil) |> render()

        assert before == after_clearing
        assert seated != before
      end

      test "carries no run pane in the markup", %{conn: conn} do
        {:ok, view} = mount_run(conn, nil)

        refute has_element?(view, ".sb-run")
        assert has_element?(view, ".sb-canvas")
      end

      # Sabotage: removed `run` from `switch_document/2`'s reset - the run
      # followed the author into a document whose blocks its provenance map
      # does not name, and this went red (verified).
      test "a different document puts the run away", %{conn: conn, run: run} do
        {:ok, view} = mount_run(conn, run.state)
        assert has_element?(view, ".sb-run")

        send(view.pid, {:swap_document, EditorFixtures.signup_wizard()})
        render(view)

        refute has_element?(view, ".sb-run")
      end
    end

    describe "with statifier-ui off the load path" do
      defmodule NoComponents do
        @moduledoc "A module with none of the three components: the absent-package branch."
      end

      # A host that forgot the optional dependency should still see its
      # document. The pane says what is missing and seats the canvas anyway.
      #
      # Sabotage: made `component/1` skip its `function_exported?/3` check -
      # the render raised `UndefinedFunctionError` and took the whole editor
      # with it (verified).
      test "the canvas still draws and the pane says what is missing", %{conn: conn, run: run} do
        Application.put_env(:statifier_blocks, :run_pane_module, NoComponents)

        {:ok, view} = mount_run(conn, run.state)

        assert has_element?(view, ".sb-run__stage .sb-canvas")
        assert has_element?(view, ".sb-run__unavailable")
        refute has_element?(view, ".statifier-ui-scrubber")
      end
    end

    # The `known-here` section only, because the tab draws three tables and a
    # path can appear in more than one of them.
    defp known_row(html, path) do
      with [section] <- Regex.run(~r/data-section="known-here".*?<\/section>/s, html),
           [row] <- Regex.run(~r/<tr data-path="#{Regex.escape(path)}"[^>]*>/, section) do
        row
      else
        _no_row -> nil
      end
    end
  end
end
