# ADR-0005 decision 1: with `phoenix_live_view` absent the editor does not
# compile, so neither can a test that drives it. The `:liveview` tag on
# `StatifierBlocks.EditorLiveCase` excludes these from a headless *run*; this
# guard is what keeps them out of a headless *compile*.
if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.FixturesTabTest do
    @moduledoc """
    The Fixtures drawer tab (`sb-4yze`, Phase 2): the shell, the memoized
    recompute and the panel `StatifierBlocks.Runtime.FixtureRuns` (Phase 1)
    feeds.

    What is asserted here is what only a rendered drawer can show: that the
    tab is drawn, that opening it and picking it runs the rows, that a
    document mid-edit reads as mid-edit rather than as a failure, and that the
    memo actually refreshes when the document moves under it. The row
    driving itself - every status and every verdict `FixtureRuns.run/4` can
    produce - is `StatifierBlocks.Runtime.FixtureRunsTest`'s claim, headless.
    """

    use StatifierBlocks.EditorLiveCase

    alias StatifierBlocks.Predicates.TruthTable

    defp open(view) do
      view |> element(".sb-drawer__strip") |> render_click()
      view
    end

    defp pick_fixtures(view) do
      view |> element(~s(.sb-drawer__tab[phx-value-tab="fixtures"])) |> render_click()
      view
    end

    defp select(view, block_id) do
      view
      |> element(~s([data-block-id="#{block_id}"] > .sb-node__chrome > .sb-node__label))
      |> render_click()

      view
    end

    defp change_config(view, block_id, config) do
      view
      |> form(~s(#sb-form-#{block_id}), %{"config" => config})
      |> render_change()
    end

    # A branch with one condition arm, `amount > threshold`, over "arm_a" and
    # "otherwise" - the same shape
    # `StatifierBlocks.Runtime.FixtureRunsTest`'s `branch_document/0` builds,
    # parameterized on the threshold so the config-change test can move it.
    defp branch_document(threshold \\ 100) do
      root =
        Block.new("core.branch",
          id: "blk_BR",
          config: %{"arms" => [%{"slot" => "arm_a", "cond" => "amount > #{threshold}"}]},
          slots: %{
            "arm_a" => [container("blk_A")],
            "otherwise" => [container("blk_B")]
          }
        )

      Document.new(root, id: "bdoc_FIX")
    end

    defp container(id), do: Block.new("core.sequence", id: id)

    defp branch_table_spec do
      %{
        name: "arms",
        columns: [
          %{key: "arm_a", source: "amount > 100"},
          %{key: "otherwise", source: nil}
        ]
      }
    end

    defp branch_table(rows) do
      {:ok, table} = TruthTable.build(branch_table_spec(), rows)
      table
    end

    defp expect_row(name, amount, expected_column),
      do: %{name: name, bindings: %{"amount" => amount}, expected: %{expected_column => true}}

    defp fixtures_for(rows), do: %{"blk_BR" => [branch_table(rows)]}

    describe "a passing row" do
      # Sabotage: swapped the `:pass`/`:fail` branches in
      # `FixtureRuns.resolve_taken/3`'s `if taken == expected` - this went red,
      # reading `data-verdict="fail"` for a row whose expected arm is the one
      # taken.
      test "renders data-verdict=\"pass\" with the expected and taken slot equal", %{conn: conn} do
        fixtures = fixtures_for([expect_row("over", "150", "arm_a")])

        {:ok, view, _html} =
          mount_editor(conn,
            document: branch_document(),
            palette: Palette.core(),
            fixtures: fixtures
          )

        view |> open() |> pick_fixtures()

        assert has_element?(view, ~s(tr[data-row="over"] td[data-verdict="pass"]))
        row_html = view |> element(~s(tr[data-row="over"])) |> render()
        assert row_html =~ "arm_a"
      end
    end

    describe "a failing row" do
      # Sabotage: made `FixtureRuns.owner_ids/2` always return an empty
      # `MapSet` - this went red, the verdict reading `:unreached` instead of
      # `:fail`.
      test "renders data-verdict=\"fail\" and shows the slot actually taken", %{conn: conn} do
        # amount = 150 takes "arm_a" (150 > 100); the row wrongly expects
        # "otherwise".
        fixtures = fixtures_for([expect_row("wrong", "150", "otherwise")])

        {:ok, view, _html} =
          mount_editor(conn,
            document: branch_document(),
            palette: Palette.core(),
            fixtures: fixtures
          )

        view |> open() |> pick_fixtures()

        assert has_element?(view, ~s(tr[data-row="wrong"] td[data-verdict="fail"]))
        row_html = view |> element(~s(tr[data-row="wrong"])) |> render()
        # Expected ("otherwise") and taken ("arm_a") both show, so the panel
        # says what happened rather than only that it went wrong.
        assert row_html =~ "otherwise"
        assert row_html =~ "arm_a"
      end
    end

    describe "no fixtures" do
      # Sabotage: changed the panel's `:no_fixtures` clause condition from
      # `@runs.status == :no_fixtures` to `@runs.status == :ready` - the
      # `sb-drawer__empty` copy stopped rendering for a `nil` fixtures source
      # (verified red).
      test "shows the sb-drawer__empty copy and no run table", %{conn: conn} do
        {:ok, view, _html} =
          mount_editor(conn, document: branch_document(), palette: Palette.core(), fixtures: nil)

        view |> open() |> pick_fixtures()

        assert has_element?(view, ".sb-drawer__panel .sb-drawer__empty")
        refute has_element?(view, ".sb-fixtures__scroll")
      end
    end

    describe "the count" do
      # Sabotage: had `Shell.fixture_row_count/1` count tables instead of
      # rows (`table_count/1`'s own body) - this went red, the strip reading
      # "Fixtures (1)" for two rows in one table instead of "Fixtures (2)".
      test "the strip reads the number of rows, not the number of failures", %{conn: conn} do
        fixtures =
          fixtures_for([
            expect_row("a", "150", "arm_a"),
            expect_row("b", "200", "arm_a")
          ])

        {:ok, view, _html} =
          mount_editor(conn,
            document: branch_document(),
            palette: Palette.core(),
            fixtures: fixtures
          )

        open(view)

        assert view |> element("#sb-drawer-tab-fixtures") |> render() =~ "(2)"

        pick_fixtures(view)

        assert has_element?(view, ~s(td[data-verdict="pass"]))
        refute has_element?(view, ~s(td[data-verdict="fail"]))
      end
    end

    describe "no fallthrough" do
      # Sabotage: removed the `@view.tab == :fixtures ->` clause from the
      # drawer's `cond` in `StatifierBlocks.Editor.Drawer.drawer/1` - this
      # went red, the truth-tables surface (`.sb-table`) rendering under the
      # Fixtures tab instead of the run table.
      test "does not fall through to the truth-tables surface", %{conn: conn} do
        fixtures = fixtures_for([expect_row("over", "150", "arm_a")])

        {:ok, view, _html} =
          mount_editor(conn,
            document: branch_document(),
            palette: Palette.core(),
            fixtures: fixtures
          )

        view |> open() |> pick_fixtures()

        refute has_element?(view, ".sb-table")
        assert has_element?(view, ".sb-fixtures__scroll")
      end
    end

    describe "a document that does not compile" do
      # Sabotage: changed the panel's `:compile_error` clause condition from
      # `@runs.status == :compile_error` to `@runs.status == :ready` - the
      # compile message stopped rendering for a document that does not
      # compile (verified red).
      test "shows the compile message, not a run list", %{conn: conn} do
        document = Document.new(Block.new("core.nonexistent_type", id: "blk_BAD"), id: "bdoc_BAD")
        fixtures = %{"blk_BAD" => [branch_table([expect_row("x", "1", "arm_a")])]}

        {:ok, view, _html} =
          mount_editor(conn, document: document, palette: Palette.core(), fixtures: fixtures)

        view |> open() |> pick_fixtures()

        assert view |> element(".sb-drawer__panel") |> render() =~ "does not currently compile"
        refute has_element?(view, ".sb-fixtures__scroll")
      end
    end

    describe "editing the document while the tab is open" do
      # Sabotage: dropped `refresh_fixture_runs()` from the `rebuild/1`
      # pipeline (kept it only on `drawer-open`/`drawer-tab`) - this went red,
      # the verdict staying "pass" after the condition moved instead of
      # flipping to "fail".
      test "re-runs the rows when a config-form edit moves the condition", %{conn: conn} do
        fixtures = fixtures_for([expect_row("over", "150", "arm_a")])

        {:ok, view, _html} =
          mount_editor(conn,
            document: branch_document(100),
            palette: Palette.core(),
            fixtures: fixtures
          )

        view |> open() |> pick_fixtures()
        assert has_element?(view, ~s(tr[data-row="over"] td[data-verdict="pass"]))

        select(view, "blk_BR")
        change_config(view, "blk_BR", %{"arm_a" => "amount > 1000"})

        assert has_element?(view, ~s(tr[data-row="over"] td[data-verdict="fail"]))
      end
    end

    describe "the declare/host_roots regression guard" do
      # Sabotage: passed `assigns.host_roots` (the derived `MapSet`) instead
      # of `assigns.declare` (the raw `{id, expr}` list) to `FixtureRuns.run/4`
      # in `refresh_fixture_runs/1` - `Compiler.DeclaredRoots.declarations/1`
      # then answered every compile with
      # `{:error, [{:invalid_declaration, _}]}`, and this test went red: the
      # tab showed its compile-error panel with the whole rest of the suite
      # green.
      test "a non-empty declare assign still reaches :ready with a pass verdict", %{conn: conn} do
        fixtures = fixtures_for([expect_row("over", "150", "arm_a")])

        {:ok, view, _html} =
          mount_editor(conn,
            document: branch_document(),
            palette: Palette.core(),
            fixtures: fixtures,
            declare: [{"session_id", "'abc'"}]
          )

        view |> open() |> pick_fixtures()

        assert has_element?(view, ~s(tr[data-row="over"] td[data-verdict="pass"]))
        refute view |> element(".sb-drawer__panel") |> render() =~ "does not currently compile"
      end
    end
  end
end
