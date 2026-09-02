# ADR-0005 decision 1: with `phoenix_live_view` absent the editor does not
# compile, so neither can a test that drives it. The `:liveview` tag on
# `StatifierBlocks.EditorLiveCase` excludes these from a headless *run*; this
# guard is what keeps them out of a headless *compile*.
if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.TableDetailTest do
    @moduledoc """
    What a truth-table row says beyond its verdict: the mismatch detail, and
    the row's own note.

    Both were on the structs and off the screen. A `:mismatch` cell carries
    the row's declared `expected` and the `selected?` one first-match-wins
    pass actually chose, and the two mismatches - an arm expected to win that
    lost, and an arm expected to lose that won - are the same word without
    them. A row carries an author's `note`, which is the only place a fixture
    says why the case is in the table at all.

    The rows here are built through the real `TruthTable.build/2` from real
    predicator sources, so what is asserted is what the builder produces
    against what the drawer draws, not a hand-shaped struct meeting a hand-
    shaped renderer.
    """

    use StatifierBlocks.EditorLiveCase

    alias StatifierBlocks.Predicates.TruthTable

    @block_id "blk_BR"

    defp document do
      root =
        Block.new("core.branch",
          id: @block_id,
          config: %{"arms" => [%{"slot" => "arm_a", "cond" => "amount > 100"}]},
          slots: %{"arm_a" => [Block.new("core.sequence", id: "blk_A")]}
        )

      Document.new(root, id: "bdoc_DET")
    end

    # One real arm and the fallback, which is what makes both directions of
    # mismatch reachable: a row can expect the arm and get `otherwise`, or
    # expect `otherwise` and have the arm taken out from under it.
    defp table(rows) do
      {:ok, table} =
        TruthTable.build(
          %{
            name: "arms",
            columns: [
              %{key: "arm_a", label: "over 100", source: "amount > 100"},
              %{key: "otherwise", label: "otherwise", source: nil}
            ]
          },
          rows
        )

      table
    end

    defp open_table(conn, table) do
      {:ok, view, _html} =
        mount_editor(conn,
          document: document(),
          palette: Palette.core(),
          fixtures: %{@block_id => [table]}
        )

      view |> element(".sb-drawer__strip") |> render_click()
      view |> element(~s(.sb-drawer__jump[phx-value-block-id="#{@block_id}"])) |> render_click()

      view
    end

    defp cell(view, row_name, column) do
      view
      |> element(~s(tr[data-row="#{row_name}"] td[data-column="#{column}"]))
      |> render()
    end

    defp row_header(view, row_name) do
      view |> element(~s(tr[data-row="#{row_name}"] th)) |> render()
    end

    describe "a mismatched cell" do
      # Sabotage: made `mismatch_detail/1` return `nil` for every cell, so the
      # cells rendered the bare status word again - this test and the title
      # test below both went red. Reverted.
      test "says what was expected against what was selected", %{conn: conn} do
        rows = [
          %{
            name: "wrong guess",
            bindings: %{"amount" => "50"},
            expected: %{"arm_a" => true, "otherwise" => false}
          }
        ]

        view = open_table(conn, table(rows))

        # `amount` is 50, so the arm does not hold and `otherwise` is what a
        # branch would run. The row declared the opposite of both.
        assert cell(view, "wrong guess", "arm_a") =~ "mismatch"
        assert cell(view, "wrong guess", "arm_a") =~ "expected yes, selected no"
        assert cell(view, "wrong guess", "otherwise") =~ "expected no, selected yes"
      end

      # The detail is a tooltip as well as a line, so the reading survives a
      # column narrow enough to clip it.
      #
      # Sabotage: dropped the `title={detail}` attribute from the cell - this
      # went red on the `title=` assertion while the visible line still
      # passed, which is the point of asserting both. Reverted.
      test "carries the same reading as the cell's title", %{conn: conn} do
        rows = [
          %{
            name: "wrong guess",
            bindings: %{"amount" => "50"},
            expected: %{"arm_a" => true}
          }
        ]

        view = open_table(conn, table(rows))

        assert cell(view, "wrong guess", "arm_a") =~ ~s(title="expected yes, selected no")
      end

      # The four other statuses have nothing honest to say here, and a detail
      # on a matching cell would be noise on every well-behaved row in the
      # table - which is most of them.
      #
      # Sabotage: dropped `status: :mismatch` from `mismatch_detail/1`'s
      # first clause so it matched every cell - four of the five tests in this
      # module went red, this one included: `yes_no/1` has no clause for the
      # `nil` an unchecked cell's `expected` carries. Reverted.
      test "no other status carries a detail", %{conn: conn} do
        rows = [
          %{name: "agrees", bindings: %{"amount" => "500"}, expected: %{"arm_a" => true}},
          %{name: "undeclared", bindings: %{"amount" => "500"}}
        ]

        view = open_table(conn, table(rows))

        assert cell(view, "agrees", "arm_a") =~ "match"
        refute cell(view, "agrees", "arm_a") =~ "expected"
        assert cell(view, "undeclared", "arm_a") =~ "unchecked"
        refute cell(view, "undeclared", "arm_a") =~ "expected"
      end
    end

    describe "a row's note" do
      # Sabotage: deleted the note `<span>` from the row header - this went
      # red, the header carrying only the row name. Reverted.
      test "renders under the row name", %{conn: conn} do
        rows = [
          %{
            name: "at the boundary",
            bindings: %{"amount" => "100"},
            note: "100 is not over 100; the fallback is correct here."
          }
        ]

        header = conn |> open_table(table(rows)) |> row_header("at the boundary")

        assert header =~ "at the boundary"
        assert header =~ "sb-table__row-note"
        assert header =~ "100 is not over 100"
      end

      # A row without a note renders no empty element for one: the note line
      # is a second row of type, and an empty one would set every row in the
      # table two lines tall for the sake of the few that have something to
      # say.
      #
      # Sabotage: changed the `:if={row.note}` guard to `:if={true}` - this
      # went red on the `refute`. Reverted.
      test "is absent when the row declares none", %{conn: conn} do
        rows = [%{name: "plain", bindings: %{"amount" => "500"}}]

        header = conn |> open_table(table(rows)) |> row_header("plain")

        assert header =~ "plain"
        refute header =~ "sb-table__row-note"
      end
    end
  end
end
