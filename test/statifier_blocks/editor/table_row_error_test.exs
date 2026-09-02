# ADR-0005 decision 1: with `phoenix_live_view` absent the editor does not
# compile, so neither can a test that drives it. The `:liveview` tag on
# `StatifierBlocks.EditorLiveCase` excludes these from a headless *run*; this
# guard is what keeps them out of a headless *compile*.
if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.TableRowErrorTest do
    @moduledoc """
    The truth-table row-error cell: a row whose bindings never built a context
    reads as a sentence about the fixture, not as a tagged tuple.

    Two claims, and they are different. The first is that every reason
    `StatifierBlocks.Predicates.context/1` actually hands a row - the whole
    set `StatifierBlocks.Predicates.TruthTable.build/2` can put in
    `row.error` - is read out; those rows are built through the real builder
    from real binding sources, so the enumeration cannot drift from what the
    seam produces without this going red. The second is that a reason outside
    that set still shows its term rather than an empty cell; those rows carry
    a hand-made `%Row{}`, because a reason the builder cannot produce is
    exactly what no document could set up.
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

      Document.new(root, id: "bdoc_ERR")
    end

    defp table(rows) do
      {:ok, table} =
        TruthTable.build(
          %{name: "arms", columns: [%{key: "arm_a", source: "amount > 100"}]},
          rows
        )

      table
    end

    # Opens the drawer and lands on the block's tables tab, which is where the
    # index page's jump goes with nothing selected.
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

    defp error_cell(view, row_name) do
      view |> element(~s(tr[data-row="#{row_name}"] .sb-table__row-error)) |> render()
    end

    defp bad_binding(name, source), do: %{name: name, bindings: %{"amount" => source}}

    # A row carrying a reason no binding source can produce, put on a real
    # built table so everything around the cell is the shipped path.
    defp synthetic(table, name, error) do
      %{table | rows: [%TruthTable.Row{name: name, bindings: %{}, error: error, cells: []}]}
    end

    describe "the reasons the builder produces" do
      # Sabotage: dropped the `{:binding, path, reason}` clause from
      # `row_error_sentence/1`, so the row fell through to the general clause
      # - every assertion below went red, reading `{:binding, "amount", ...}`
      # instead of the sentence. Reverted.
      test "each one renders as a sentence naming the binding", %{conn: conn} do
        rows = [
          bad_binding("unparseable", "amount >"),
          bad_binding("unbound", "missing.thing > 1"),
          bad_binding("undefined", "1 > 'usd'"),
          bad_binding("uncomputable", "true + 1")
        ]

        view = open_table(conn, table(rows))

        # The four wrapped reasons, each with its own reading of the inner
        # tag. `{:non_boolean, _}` is deliberately absent: `evaluate_value/1`
        # returns a non-boolean value as `{:ok, value}`, so no binding source
        # can produce it and no fixture could set this row up.
        assert error_cell(view, "unparseable") =~ ~s(The binding for &quot;amount&quot; failed:)
        assert error_cell(view, "unparseable") =~ "could not be parsed"
        assert error_cell(view, "unbound") =~ "nothing binds the variable"
        assert error_cell(view, "unbound") =~ "missing"
        assert error_cell(view, "undefined") =~ "evaluated to undefined"
        assert error_cell(view, "uncomputable") =~ "could not be evaluated"
      end

      # Predicator's own parse message runs past 130 characters, and the table
      # cell is `nowrap`: quoting it into the sentence puts a horizontal
      # scroll on a table that otherwise fits. The failing source is already
      # in the row's binding column, so the sentence stops at the tag.
      #
      # Sabotage: appended `" (#{error.message})"` to the `:parse_error`
      # clause - this went red on the parser prose. Reverted.
      test "the sentence does not quote predicator's own message", %{conn: conn} do
        view = open_table(conn, table([bad_binding("unparseable", "amount >")]))
        cell = error_cell(view, "unparseable")

        assert cell =~ "the source could not be parsed."
        refute cell =~ "Expected number"
        refute cell =~ "end of input"
      end

      # Sabotage: dropped the `{:binding_conflict, path}` clause - this went
      # red, the cell reading `{:binding_conflict, "transaction.amount"}`.
      # Reverted.
      test "a binding conflict names the path and says what conflicts", %{conn: conn} do
        rows = [
          %{
            name: "conflict",
            bindings: %{"transaction" => "120", "transaction.amount" => "5"}
          }
        ]

        view = open_table(conn, table(rows))
        cell = error_cell(view, "conflict")

        assert cell =~ ~s(The binding for &quot;transaction.amount&quot; conflicts)
        assert cell =~ "cannot both nest"
      end

      # The point of a sentence is that the tuple is gone. Asserted against
      # the whole rendered table rather than one cell so a tag leaking through
      # any other row is caught here too.
      #
      # Sabotage: restored `{inspect(row.error)}` in `table/1` - this went
      # red on the `{:binding,` fragment. Reverted.
      test "no rendered row carries a raw tagged tuple", %{conn: conn} do
        rows = [
          bad_binding("unparseable", "amount >"),
          %{name: "conflict", bindings: %{"transaction" => "120", "transaction.amount" => "5"}}
        ]

        html = conn |> open_table(table(rows)) |> element(".sb-table") |> render()

        refute html =~ "{:binding,"
        refute html =~ "{:binding_conflict,"
        refute html =~ "%Predicator.Errors"
      end
    end

    describe "a reason the builder cannot produce" do
      # Sabotage: changed `clause(_other)` to return a fixed string instead of
      # `nil`, so an unknown reason got a sentence claiming something about it
      # - this went red, the term no longer in the cell. Reverted.
      test "an unrecognised reason still shows the term", %{conn: conn} do
        table = synthetic(table([]), "unknown", {:something_new, "detail"})

        assert error_cell(open_table(conn, table), "unknown") =~ "{:something_new"
      end

      # `{:non_boolean, value}` is in `Predicates.reason()` and so is in
      # `Row`'s declared `error` type, even though `context/1` never returns
      # it. It is read out rather than inspected, and the offending value is
      # shown.
      #
      # Sabotage: dropped the `{:non_boolean, value}` clause from `clause/1`
      # - this went red, the cell reading `{:non_boolean, 120}`. Reverted.
      test "a bare evaluate-level tag reads as a sentence", %{conn: conn} do
        table = synthetic(table([]), "bare", {:non_boolean, 120})
        cell = error_cell(open_table(conn, table), "bare")

        assert cell =~ "This case&#39;s bindings failed:"
        assert cell =~ "the source produced 120"
        refute cell =~ "{:non_boolean"
      end
    end
  end
end
