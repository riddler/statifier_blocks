# ADR-0005 decision 1: with `phoenix_live_view` absent the editor does not
# compile, so neither can a test that drives it. The `:liveview` tag on
# `StatifierBlocks.EditorLiveCase` excludes these from a headless *run*; this
# guard is what keeps them out of a headless *compile*.
if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.RunProfileTest do
    @moduledoc """
    The `run?` profile key (ADR-0005's 2026-09-12 Note).

    The Note's clause 1 is a contract rather than a mechanism: **a `run?: false`
    mount never holds a run, on any render.** "Any render" is what most of this
    file is about, because there are three ways a host reaches the state and
    only one of them is the mount - the profile and the run can arrive in the
    same update, the run can arrive after the profile, and the profile can
    arrive after the run. Each is its own test, and the implementation meets
    all three in `put_run/2` and `put_run_session/2`, which put the two
    assigns back to `nil` on every update a `run?: false` profile is in reach
    of - `update/2` opens by writing the host's assigns straight onto the
    socket, so declining to write is not enough.

    The fourth claim is the one the key is built around: **a mount that says
    nothing about `run?` is the editor it was before the key existed.** It is
    asserted as byte identity against an unprofiled mount with the same run
    seated, which is the oracle `profile_test.exs` uses for the other five keys.

    The fifth is the Note's section 4: `run?` addresses the run, not the marks.
    A host that paints `active_marks` itself still gets them - "no *run* marks",
    not "no marks".

    `async: false`, for `run_pane_test.exs`'s reason: the sibling runtime tests
    install stand-ins under the same application-config keys a real run needs
    the real package at.

    Every selector that asks about a mark is scoped to `.sb-node`, the rule
    `run_marks_test.exs` sets.
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

    defp mount_document(conn, extra \\ []) do
      {:ok, view, _html} =
        mount_editor(
          conn,
          Keyword.merge(
            [
              document: CardRunFixtures.document(),
              palette: CardRunFixtures.palette(),
              declare: CardRunFixtures.declare()
            ],
            extra
          )
        )

      view
    end

    defp update(view, assigns) do
      Phoenix.LiveView.send_update(view.pid, Editor, [{:id, "editor"} | assigns])
      render(view)
      view
    end

    defp editor(view), do: view |> element("#editor") |> render()

    defp pane?(view), do: has_element?(view, ".sb-run")

    defp active?(view, block_id) do
      has_element?(view, ~s(.sb-node[data-block-id="#{block_id}"][data-run-active="true"]))
    end

    defp select(view, block_id) do
      view
      |> element(~s(.sb-node[data-block-id="#{block_id}"] > .sb-node__chrome > .sb-node__label))
      |> render_click()

      view
    end

    defp open_datamodel(view) do
      view |> element(".sb-drawer__strip") |> render_click()
      view |> element(~s(.sb-drawer__tab[phx-value-tab="datamodel"])) |> render_click()
      view
    end

    describe "a mount at run?: false" do
      # The sabotage for this whole describe block, run once: had the
      # `run?: false` clause of `put_run/2` return the socket untouched
      # instead of assigning `nil`. `update/2` opens with `assign(assigns)`,
      # so the host's `run` is on the socket before the clause runs and a
      # clause that only declines to write leaves it seated - six of these
      # ten went red (verified).
      test "seats no run, whatever the host passes", %{conn: conn, run: run} do
        view = mount_document(conn, profile: %{run?: false})

        update(view, run: run.state)

        refute pane?(view)
        refute active?(view, CardRunFixtures.settle_block())
      end

      # The second arrival order: the profile and the run in one update,
      # which is the render the Note's clause 1 decides the pipeline order
      # for. It is honest about what this test does and does not
      # discriminate: it goes red under the describe block's sabotage, and
      # it does **not** move when the `update/2` pipeline is put back to
      # `put_run |> put_run_session |> put_profile` (verified). The reason
      # is `assign(assigns)` again - it writes the host's *raw* profile map
      # onto the socket before either function runs, so the guard happens to
      # match an unnormalized `%{run?: false}` in the old order too. The
      # order is kept because the Note decides it and because the guard
      # should read the profile `normalize_profile/1` returned rather than
      # whatever shape the host passed, not because this assertion proves it.
      test "takes the key before the run, when both arrive in one update", %{
        conn: conn,
        run: run
      } do
        view = mount_document(conn)

        update(view, profile: %{run?: false}, run: run.state)

        refute pane?(view)
        refute active?(view, CardRunFixtures.settle_block())
      end

      # The third arrival order: a host that mounts with a run and then
      # narrows the mount. Without `unseat_run/1` the key would govern only
      # what came after it, and "never holds a run" would be false of this
      # render.
      #
      # This is the arrival order that makes the guard's placement matter:
      # the update carries no `run` key at all, so nothing but a clause that
      # writes `nil` unconditionally can put the seat back. Red under the
      # describe block's sabotage (verified).
      test "unseats a run that was seated before it arrived", %{conn: conn, run: run} do
        view = mount_document(conn)

        update(view, run: run.state)
        assert pane?(view), "the run seats on an unprofiled mount"

        update(view, profile: %{run?: false})

        refute pane?(view)
        refute active?(view, CardRunFixtures.settle_block())
      end

      # Red under the describe block's sabotage: with the run still seated
      # the `:if={@run?}` header cell drew and this failed on the first
      # assertion (verified).
      test "drops the Held here column", %{conn: conn, run: run} do
        view = mount_document(conn, profile: %{run?: false})

        html =
          view
          |> update(run: run.state)
          |> select(CardRunFixtures.settle_block())
          |> open_datamodel()
          |> render()

        refute html =~ "Held here"
        refute html =~ "data-held"
      end

      # The Note's section 2: the canvas draws in the seat it drew in with no
      # run passed. Asserted as byte identity on one view rather than across
      # two mounts, so the comparison cannot be satisfied by two mounts that
      # are both wrong in the same way.
      #
      # Red under the describe block's sabotage (verified).
      test "renders what the same mount renders with nothing passed", %{conn: conn, run: run} do
        view = mount_document(conn, profile: %{run?: false})
        before = editor(view)

        assert editor(update(view, run: run.state)) == before
      end

      # The Note's section 4, and its phrase "no *run* marks": `active_marks`
      # is a different seam and the key does not reach it.
      #
      # Sabotage, run on its own: had the `run?: false` clause of `put_run/2`
      # clear `active_ids` beside the run - the host's own mark disappeared
      # and this was the only one of the ten that went red (verified), which
      # is what makes it the test for section 4 rather than a restatement of
      # the ones above it.
      test "leaves the marks a host paints itself", %{conn: conn, run: run} do
        view = mount_document(conn, profile: %{run?: false})

        update(view, run: run.state, active_marks: [CardRunFixtures.entry_block()])

        assert active?(view, CardRunFixtures.entry_block())
        refute active?(view, CardRunFixtures.settle_block())
        refute pane?(view)
      end
    end

    describe "the default" do
      # Sabotage: made `normalize_profile/1` resolve `run?` with
      # `Map.get(profile, :run?) == true`, which turns an unmentioned key
      # into `false` - three of the four tests in this describe block went
      # red and none of the six above them moved (verified). The fourth,
      # *a profile that is not a map at all still seats the run*, stays green
      # under it, and that is not a gap: `normalize_profile(_other)` answers
      # `@default_profile` whole and never reaches the expression the
      # sabotage changes.
      test "run?: true renders byte-identically to the unprofiled editor", %{
        conn: conn,
        run: run
      } do
        plain = conn |> mount_document() |> update(run: run.state)
        named = conn |> mount_document(profile: %{run?: true}) |> update(run: run.state)
        empty = conn |> mount_document(profile: %{}) |> update(run: run.state)

        assert editor(named) == editor(plain)
        assert editor(empty) == editor(plain)
      end

      test "a profile naming another key still seats the run", %{conn: conn, run: run} do
        view = mount_document(conn, profile: %{drawer_tabs: [:findings]})

        update(view, run: run.state)

        assert pane?(view)
        assert active?(view, CardRunFixtures.settle_block())
      end

      # The normaliser keeps `run?` and resolves a malformed value the way it
      # resolves a malformed list: to the default for that key, which is the
      # surface the host had before it named anything.
      test "a malformed run? value drops to true", %{conn: conn, run: run} do
        view = mount_document(conn, profile: %{run?: :nonsense})

        update(view, run: run.state)

        assert pane?(view)
      end

      # Before this bead `normalize_profile/1` rebuilt the map out of the five
      # keys it knew and dropped everything else, so `run?: false` was
      # silently discarded. This is that regression, asserted from the outside:
      # the key survives normalization or the mount below seats a run.
      test "a profile that is not a map at all still seats the run", %{conn: conn, run: run} do
        view = mount_document(conn, profile: :operations)

        update(view, run: run.state)

        assert pane?(view)
      end
    end
  end
end
