# ADR-0005 decision 1: with `phoenix_live_view` absent the editor does not
# compile, so neither can a test that drives it. The `:liveview` tag on
# `StatifierBlocks.EditorLiveCase` excludes these from a headless *run*; this
# guard is what keeps them out of a headless *compile*.
if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.EnvironmentTabTest do
    @moduledoc """
    ADR-0011 decision 9's second surface: the Datamodel tab answers "what is
    known here" for the selected block, and lists the declared records and
    shapes with their fields and required marks.

    Driven by the record's own worked shape (`test/support/card_processing_fixtures.ex`):
    an entry block that puts `cards.credit_txn` at the subject path, and a
    settle step after it. Selecting the settle leaf is the acceptance the
    bead names, and what the tab has to say there is the subject path with
    its record type - which is the one thing no surface in this package could
    say before the walk existed.

    The rows themselves are a rendering of `StatifierBlocks.Environment.at/4`
    and `StatifierBlocks.Datamodel.declared_types/1`, both asserted headless
    where their rules live. What only a rendered drawer can show is what is
    asserted here: that the tab asks for the SELECTED block's position, that
    it distinguishes nothing-selected from nothing-known, and that a declared
    type reads as its label with its nominal name beside it.
    """

    use StatifierBlocks.EditorLiveCase

    alias StatifierBlocks.CardProcessingFixtures, as: Cards

    defp document do
      Cards.document([Cards.open(), Cards.settle("blk_STL")])
    end

    defp mount_cards(conn) do
      mount_editor(conn,
        document: document(),
        palette: Cards.palette(),
        datamodel: Cards.datamodel()
      )
    end

    defp open(view) do
      view |> element(".sb-drawer__strip") |> render_click()
      view |> element(~s(.sb-drawer__tab[phx-value-tab="datamodel"])) |> render_click()
      view
    end

    defp known_here(html) do
      case Regex.run(~r/data-section="known-here".*?<\/section>/s, html) do
        [section] -> section
        nil -> nil
      end
    end

    defp known_rows(html) do
      ~r/<tr data-path="([^"]*)" data-type="([^"]*)"/
      |> Regex.scan(known_here(html) || "")
      |> Enum.map(fn [_all, path, type] -> {path, type} end)
    end

    describe "what is known here" do
      # Sabotage: `Editor.environment_view/1` answering `nil` for a selected
      # block - the panel shows the nothing-selected prompt instead of the
      # row, and both assertions below go red.
      test "lists the subject path with its record type at the settle leaf", %{conn: conn} do
        {:ok, view, _html} = mount_cards(conn)

        view |> element(~s([phx-click="select"][phx-value-block-id="blk_STL"])) |> render_click()

        html = open(view) |> render()

        assert known_rows(html) == [{"cards.current_txn", "Credit card transaction"}]
      end

      # Sabotage: `environment_view/1` reading `List.first(path)` rather than
      # `List.last(path)` - it answers for the root's own position instead of
      # the block's, so the entry block sees what the settle step sees and
      # this goes red.
      test "answers for the block's own position, before its own writes", %{conn: conn} do
        {:ok, view, _html} = mount_cards(conn)

        view |> element(~s([phx-click="select"][phx-value-block-id="blk_OPEN"])) |> render_click()

        html = open(view) |> render()

        assert known_rows(html) == [],
               "the entry block is the first position walked, so nothing is known in front of it"

        assert known_here(html) =~ "Nothing is known at this block&#39;s position"
      end

      # Sabotage: `environment_view/1` dropping its `nil` clause and answering
      # `[]` with nothing selected - the two empty states collapse into one
      # and this goes red on the prompt.
      test "distinguishes nothing selected from nothing known", %{conn: conn} do
        {:ok, view, _html} = mount_cards(conn)

        html = open(view) |> render()

        assert known_here(html) =~ "Select a block"
        refute known_here(html) =~ "Nothing is known"
      end
    end

    describe "a labelled finding on the page" do
      # The whole route, not the renderer alone: the compiler builds the
      # message against the datamodel it checked with, `Finding.from_compiler/2`
      # carries it across, and the editor draws it on the block's chrome. A
      # test that asserted the message in isolation would pass with the
      # declarations never reaching the stage.
      #
      # Sabotage: `structure_stage/3` reading `Environment.declarations(%{})` -
      # the nominal names reach the page and both assertions go red.
      test "carries the declaration's label onto the block", %{conn: conn} do
        document =
          Cards.document([Cards.open(), Cards.settle("blk_STL", %{"expects" => "Settled"})])

        {:error, compiler_findings} =
          StatifierBlocks.Compiler.compile(document, Cards.palette(),
            datamodel: Cards.datamodel()
          )

        {findings, []} = StatifierBlocks.Finding.from_compiler_all(compiler_findings)

        {:ok, _view, html} =
          mount_editor(conn,
            document: document,
            palette: Cards.palette(),
            datamodel: Cards.datamodel(),
            findings: findings
          )

        assert html =~ "left &quot;Credit card transaction&quot;"
        refute html =~ "left &quot;cards.credit_txn&quot;"
      end
    end

    describe "declared types" do
      # Sabotage: `Datamodel.declared_types/1` dropping `required?` - the
      # required marks disappear and the third assertion goes red.
      test "lists the records and shapes with their fields and required marks", %{conn: conn} do
        {:ok, view, _html} = mount_cards(conn)

        html = open(view) |> render()

        assert html =~ ~s(data-type="cards.credit_txn" data-kind="record")
        assert html =~ ~s(data-type="Settleable" data-kind="shape")

        assert html =~ ~s(data-field="amount_minor" data-required="true")
        assert html =~ ~s(data-field="authorized_at" data-required="false")
      end

      # Sabotage: rendering `row.name` in place of `row.label || row.name` -
      # the label never reaches the page and this goes red.
      test "reads a declaration as its label, with the nominal name beside it", %{conn: conn} do
        {:ok, view, _html} = mount_cards(conn)

        html = open(view) |> render()

        assert html =~ ~r{sb-datamodel__type-label">\s*Credit card transaction\s*<}
        assert html =~ ~r{sb-datamodel__type-name">\s*cards\.credit_txn\s*<}

        refute html =~ ~r{sb-datamodel__type-name">\s*Settleable\s*<},
               "a shape whose label IS its name says it once, not twice"
      end

      # The empty state is a statement about the document, not a blank table.
      # Sabotage: dropping the `:if` on the empty paragraph - the sentence is
      # gone and this goes red.
      test "says so when the datamodel declares no types at all", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, document: document(), palette: Cards.palette())

        html = open(view) |> render()

        assert html =~ "declares no records or shapes"
      end
    end
  end
end
