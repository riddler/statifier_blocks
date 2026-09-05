# ADR-0005 decision 1: with `phoenix_live_view` absent the editor does not
# compile, so neither can a test that drives it. The `:liveview` tag on
# `StatifierBlocks.EditorLiveCase` excludes these from a headless *run*; this
# guard is what keeps them out of a headless *compile*.
if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.InspectorFixturesTest do
    @moduledoc """
    The inspector's Fixtures tab: ADR-0005's 2026-09-05 amendment, "3A admits
    a Fixtures tab in the inspector".

    What is asserted here is what only a rendered inspector can show: that the
    tab is about the selected block and shows no other block's rows, that
    changing the selection changes the rows under it, that the chip counts the
    selected block's rows, and that a block with no rows gets an empty state
    rather than a stale list. The row driving itself - every status and every
    verdict `StatifierBlocks.Runtime.FixtureRuns.run/4` can produce - is
    `StatifierBlocks.Runtime.FixtureRunsTest`'s claim, headless, and the
    drawer's own Fixtures tab is `StatifierBlocks.Editor.FixturesTabTest`'s.
    """

    use StatifierBlocks.EditorLiveCase

    alias StatifierBlocks.Predicates.TruthTable

    defp select(view, block_id) do
      view
      |> element(~s([data-block-id="#{block_id}"] > .sb-node__chrome > .sb-node__label))
      |> render_click()

      view
    end

    defp pick_fixtures(view) do
      view |> element(~s(.sb-inspector__tab[phx-value-tab="fixtures"])) |> render_click()
      view
    end

    # Two branches in one sequence, each with its own condition arm over
    # `amount`, so each owns fixture rows and neither block's rows are the
    # other's.
    defp two_branch_document do
      root =
        Block.new("core.sequence",
          id: "blk_SEQ",
          slots: %{"body" => [branch("blk_BR1", "A"), branch("blk_BR2", "B")]}
        )

      Document.new(root, id: "bdoc_INSP")
    end

    defp branch(id, suffix) do
      Block.new("core.branch",
        id: id,
        config: %{"arms" => [%{"slot" => "arm_a", "cond" => "amount > 100"}]},
        slots: %{
          "arm_a" => [Block.new("core.sequence", id: "blk_#{suffix}_A")],
          "otherwise" => [Block.new("core.sequence", id: "blk_#{suffix}_B")]
        }
      )
    end

    defp branch_table(rows) do
      spec = %{
        name: "arms",
        columns: [
          %{key: "arm_a", source: "amount > 100"},
          %{key: "otherwise", source: nil}
        ]
      }

      {:ok, table} = TruthTable.build(spec, rows)
      table
    end

    defp expect_row(name, amount, expected_column),
      do: %{name: name, bindings: %{"amount" => amount}, expected: %{expected_column => true}}

    # blk_BR1 gets one passing and one failing row; blk_BR2 gets one row of its
    # own, which is what the "only this block's rows" claim is tested against.
    defp fixtures do
      %{
        "blk_BR1" => [
          branch_table([
            expect_row("over", "150", "arm_a"),
            expect_row("wrong", "150", "otherwise")
          ])
        ],
        "blk_BR2" => [branch_table([expect_row("other", "50", "otherwise")])]
      }
    end

    defp mount_two_branches(conn, opts \\ []) do
      {:ok, view, _html} =
        mount_editor(
          conn,
          Keyword.merge(
            [
              document: two_branch_document(),
              palette: Palette.core(),
              fixtures: fixtures()
            ],
            opts
          )
        )

      view
    end

    describe "the tab strip" do
      # Sabotage: dropped `:fixtures` from `Shell.inspector_tabs/0` - this went
      # red, the strip drawing three tabs with no Fixtures button to click.
      test "carries a fourth tab titled Fixtures, last", %{conn: conn} do
        view = mount_two_branches(conn)

        assert has_element?(view, ~s(.sb-inspector__tab[phx-value-tab="fixtures"]))
        assert view |> element("#sb-inspector-tab-fixtures") |> render() =~ "Fixtures"

        tabs =
          view
          |> render()
          |> then(&Regex.scan(~r/phx-value-tab="(\w+)"/, &1))
          |> Enum.map(&List.last/1)
          |> Enum.filter(&(&1 in ["config", "findings", "condition", "fixtures"]))
          |> Enum.uniq()

        assert tabs == ["config", "findings", "condition", "fixtures"]
      end
    end

    describe "the selected block's rows" do
      # Sabotage: had `block_runs/2` return `runs.runs` unfiltered - this went
      # red, blk_BR2's "other" row appearing under blk_BR1's selection.
      test "lists this block's rows and not another block's", %{conn: conn} do
        view = mount_two_branches(conn)

        view |> select("blk_BR1") |> pick_fixtures()

        assert has_element?(view, ~s(.sb-inspector__fixtures tr[data-row="over"]))
        assert has_element?(view, ~s(.sb-inspector__fixtures tr[data-row="wrong"]))
        refute has_element?(view, ~s(.sb-inspector__fixtures tr[data-row="other"]))
      end

      # Sabotage: had `block_runs/2` ignore its node and answer every run -
      # this went red, blk_BR1's two rows still on screen under blk_BR2.
      test "changing the selection changes the rows", %{conn: conn} do
        view = mount_two_branches(conn)

        view |> select("blk_BR1") |> pick_fixtures()
        assert has_element?(view, ~s(.sb-inspector__fixtures tr[data-row="over"]))

        select(view, "blk_BR2")

        assert has_element?(view, ~s(.sb-inspector__fixtures tr[data-row="other"]))
        refute has_element?(view, ~s(.sb-inspector__fixtures tr[data-row="over"]))
        refute has_element?(view, ~s(.sb-inspector__fixtures tr[data-row="wrong"]))
      end

      # Sabotage: dropped `refresh_fixture_runs()` from `rebuild/1`, leaving it
      # only on the two tab handlers - this went red: with the tab already
      # showing and nothing selected, selecting a block ran nothing and the
      # panel stayed on its no-rows copy.
      test "selecting a block with the tab already open runs its rows", %{conn: conn} do
        view = mount_two_branches(conn)

        pick_fixtures(view)
        refute has_element?(view, ".sb-inspector__fixtures")

        select(view, "blk_BR1")

        assert has_element?(view, ~s(.sb-inspector__fixtures tr[data-row="over"]))
      end

      # Sabotage: swapped the row's `expected_slot` and `taken_slot` cells in
      # `fixtures_panel/1` - this went red on the failing row, whose two slots
      # differ and whose order is the whole of what it says.
      test "each row shows its verdict, the slot expected and the slot taken", %{conn: conn} do
        view = mount_two_branches(conn)

        view |> select("blk_BR1") |> pick_fixtures()

        assert has_element?(
                 view,
                 ~s(.sb-inspector__fixtures tr[data-row="over"] td[data-verdict="pass"])
               )

        assert has_element?(
                 view,
                 ~s(.sb-inspector__fixtures tr[data-row="wrong"] td[data-verdict="fail"])
               )

        # "wrong" binds amount = 150, which takes arm_a, while the row expects
        # "otherwise": both slots show, in that order, so the panel says what
        # happened rather than only that it went wrong.
        cells =
          view
          |> element(~s(.sb-inspector__fixtures tr[data-row="wrong"]))
          |> render()
          |> then(&Regex.scan(~r/<td[^>]*>([^<]*)<\/td>/, &1))
          |> Enum.map(&List.last/1)

        assert ["arms", "wrong", "otherwise", "arm_a", "fail"] == cells
      end
    end

    describe "the count chip" do
      # Sabotage: counted `runs.runs` instead of the block's runs in the
      # `:fixture_count` assign - this went red, the chip reading 3 (the whole
      # document's rows) for a block that owns 2.
      test "reads the selected block's row count, in the Findings chip's style", %{conn: conn} do
        view = mount_two_branches(conn)

        select(view, "blk_BR1")
        assert view |> element("#sb-inspector-tab-fixtures") |> render() =~ "Fixtures"
        pick_fixtures(view)

        assert view
               |> element("#sb-inspector-tab-fixtures .sb-inspector__tab-count")
               |> render() =~ "2"

        select(view, "blk_BR2")

        assert view
               |> element("#sb-inspector-tab-fixtures .sb-inspector__tab-count")
               |> render() =~ "1"
      end
    end

    describe "a block with no rows" do
      # Sabotage: removed the `:ready when block_runs == []` clause from
      # `fixtures_state/3`, so `:ready` alone answered `:ready` - this went
      # red, an empty table rendering where the empty state belongs.
      test "shows an empty state and no table", %{conn: conn} do
        view = mount_two_branches(conn)

        view |> select("blk_A_A") |> pick_fixtures()

        assert view |> element(".sb-inspector__panel") |> render() =~
                 "No fixture rows are recorded for this block"

        refute has_element?(view, ".sb-inspector__fixtures")
      end
    end

    describe "no selection" do
      # Sabotage: made `fixtures_state/3`'s first clause answer `:ready` for a
      # `nil` node - this went red, the no-selection copy gone.
      test "says the pane has no subject", %{conn: conn} do
        view = mount_two_branches(conn)

        pick_fixtures(view)

        assert view |> element(".sb-inspector__panel") |> render() =~
                 "Select a block on the canvas to see its fixtures"

        refute has_element?(view, ".sb-inspector__fixtures")
      end
    end

    describe "no fixtures source" do
      # Sabotage: had `fixtures_state/3` answer `:none_for_block` for a
      # `:no_fixtures` run status - this went red, the panel blaming the block
      # for a source that is not attached at all.
      test "says no source is attached, not that this block has no rows", %{conn: conn} do
        view = mount_two_branches(conn, fixtures: nil)

        view |> select("blk_BR1") |> pick_fixtures()

        assert view |> element(".sb-inspector__panel") |> render() =~
                 "No fixtures source is attached to this editor"

        refute has_element?(view, ".sb-inspector__fixtures")
      end
    end

    describe "a document that does not compile" do
      # Sabotage: dropped the `:compile_error` clause from `fixtures_state/3`'s
      # case, leaving `:ready` to answer it - this went red with a
      # FunctionClauseError rather than the mid-edit message.
      test "reads as mid-edit, with the findings that say why", %{conn: conn} do
        document =
          Document.new(
            Block.new("core.sequence",
              id: "blk_SEQ",
              slots: %{"body" => [Block.new("core.nonexistent_type", id: "blk_BAD")]}
            ),
            id: "bdoc_BAD"
          )

        {:ok, view, _html} =
          mount_editor(conn,
            document: document,
            palette: Palette.core(),
            fixtures: %{"blk_BAD" => [branch_table([expect_row("x", "1", "arm_a")])]}
          )

        view |> select("blk_BAD") |> pick_fixtures()

        assert view |> element(".sb-inspector__panel") |> render() =~
                 "does not currently compile"

        refute has_element?(view, ".sb-inspector__fixtures")
      end
    end

    describe "the drawer is not involved" do
      # Sabotage: restored `refresh_fixture_runs/1`'s original drawer-only
      # guard (`not assigns.drawer_open -> socket`) - this went red, the tab
      # showing its empty state because nothing had ever run the rows for a
      # drawer that was never opened.
      test "the rows run with the drawer never opened", %{conn: conn} do
        view = mount_two_branches(conn)

        view |> select("blk_BR1") |> pick_fixtures()

        assert has_element?(
                 view,
                 ~s(.sb-inspector__fixtures tr[data-row="over"] td[data-verdict="pass"])
               )

        refute has_element?(view, ".sb-drawer__panel .sb-fixtures__scroll")
      end
    end
  end
end
