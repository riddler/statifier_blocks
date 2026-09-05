# ADR-0005 decision 1: with `phoenix_live_view` absent the editor does not
# compile, so neither can a test that drives it. The pure half of sb-r4w7's
# claim - the disagreement finding itself - lives in
# `StatifierBlocks.ViewModel.OutcomeFindingsTest`, deliberately outside this
# guard.
if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.OutcomeCandidatesTest do
    @moduledoc """
    `core.subchart`'s `outcomes` candidates (sb-r4w7): the finals the host
    says the referenced chart emits, offered as a `<datalist>` on a field that
    is still a `:string`, plus the disagreement finding rendered under it.

    What only exists once there is markup is the half here - that the names
    reach a datalist the input is bound to, that the list is looked up by the
    document id in `chart` rather than by anything derived, that a selection
    of some other type is offered nothing, and above all that with the assign
    left at its default the editor draws exactly what it drew before.
    """

    use StatifierBlocks.EditorLiveCase

    defp purchase_document(opts) do
      Document.new(
        Block.new("core.group",
          id: "blk_purchase",
          slots: %{
            "body" => [
              Block.new("core.subchart",
                id: "blk_credit",
                config: %{
                  "chart" => Keyword.get(opts, :chart, "bdoc_CREDIT"),
                  "outcomes" => Keyword.get(opts, :outcomes, "approved\ndeclined")
                }
              ),
              Block.new("core.await", id: "blk_wait", config: %{"event" => "order.paid"})
            ]
          }
        ),
        id: "doc_purchase"
      )
    end

    defp select(view, block_id) do
      view
      |> element(~s([data-block-id="#{block_id}"] > .sb-node__chrome > .sb-node__label))
      |> render_click()

      view
    end

    defp purchase_view(conn, opts \\ []) do
      {:ok, view, _html} =
        mount_editor(conn,
          document: purchase_document(opts),
          chart_outcomes: Keyword.get(opts, :chart_outcomes, %{})
        )

      select(view, Keyword.get(opts, :select, "blk_credit"))
    end

    describe "the candidate list" do
      # Sabotage: dropped `list={@list_id}` from the new control's input ->
      # 1 failure, here (verified), and only on the binding half - the
      # datalist below still renders. That is the point: a datalist attached
      # to nothing looks identical and suggests nothing, which is the defect a
      # "does the markup contain the names" assertion would miss.
      test "the chart's finals render as a datalist the input is bound to", %{conn: conn} do
        view =
          purchase_view(conn,
            chart_outcomes: %{"bdoc_CREDIT" => ["approved", "declined", "abandoned"]}
          )

        assert has_element?(
                 view,
                 ~s(input[name="config[outcomes]"][list="sb-field-outcomes-finals"])
               )

        assert has_element?(
                 view,
                 ~s(datalist#sb-field-outcomes-finals[data-outcome-candidates="3"])
               )
      end

      test "every final the host named is offered", %{conn: conn} do
        html =
          conn
          |> purchase_view(chart_outcomes: %{"bdoc_CREDIT" => ["approved", "abandoned"]})
          |> render()

        assert html =~ ~s(<option value="approved">)
        assert html =~ ~s(<option value="abandoned">)
      end

      # Sabotage: keying the lookup on the block id rather than on the
      # `chart` value -> 3 failures, this one among them (verified). The whole
      # seam is "what does the host say about THIS document id".
      test "the list is looked up by the document id in chart", %{conn: conn} do
        view =
          purchase_view(conn,
            chart: "bdoc_OTHER",
            chart_outcomes: %{"bdoc_CREDIT" => ["approved", "declined"]}
          )

        refute has_element?(view, ~s(datalist#sb-field-outcomes-finals))
      end

      test "a value the host handed over that is not a name is dropped", %{conn: conn} do
        view =
          purchase_view(conn, chart_outcomes: %{"bdoc_CREDIT" => ["approved", :declined]})

        assert has_element?(
                 view,
                 ~s(datalist#sb-field-outcomes-finals[data-outcome-candidates="1"])
               )
      end
    end

    describe "it suggests and never constrains" do
      test "a free-typed outcome name is still accepted", %{conn: conn} do
        view = purchase_view(conn, chart_outcomes: %{"bdoc_CREDIT" => ["approved"]})

        view
        |> form(~s(form[phx-change="config-change"]), %{
          "config" => %{"outcomes" => "handwritten"}
        })
        |> render_submit()

        assert_receive {:document, document}

        assert %Block{config: %{"outcomes" => "handwritten"}} =
                 document |> Document.blocks() |> Enum.find(&(&1.id == "blk_credit"))
      end
    end

    describe "with no chart_outcomes assigned" do
      # The regression the bead names: with the assign at its default the
      # editor draws exactly what it drew before this existed - a plain input,
      # no datalist, and no finding under the field.
      #
      # Sabotage: made the empty list draw the datalist anyway (matching on
      # `outcome_candidates: _any` rather than on a non-empty list) -> 2
      # failures, this one among them (verified).
      test "the outcomes field is the plain input it always was", %{conn: conn} do
        view = purchase_view(conn)

        assert has_element?(view, ~s(input[name="config[outcomes]"]))
        refute has_element?(view, ~s(input[name="config[outcomes]"][list]))
        refute has_element?(view, ~s(datalist#sb-field-outcomes-finals))
      end

      test "nothing is reported about the declared outcomes", %{conn: conn} do
        refute conn |> purchase_view() |> render() =~ "does not finish with"
      end
    end

    describe "the disagreement, under the field" do
      # Sabotage: dropped the `disagreements` term from the editor's
      # `view_model/6` concatenation -> 1 failure, here (verified). The
      # finding is derivable in the pure test either way; this is the one run
      # that proves it reaches the rendered form.
      test "a declared outcome the chart does not finish with is shown", %{conn: conn} do
        html =
          conn
          |> purchase_view(chart_outcomes: %{"bdoc_CREDIT" => ["approved"]})
          |> render()

        assert html =~ "bdoc_CREDIT does not finish with &quot;declined&quot;"
      end

      test "an agreeing subchart is told nothing", %{conn: conn} do
        html =
          conn
          |> purchase_view(chart_outcomes: %{"bdoc_CREDIT" => ["approved", "declined"]})
          |> render()

        refute html =~ "does not finish with"
        refute html =~ "also finishes with"
      end
    end

    describe "the number a host may show" do
      # sb-ukgu's invariant, and the reason `findings_count/3` grew a
      # `:chart_outcomes` option at all: the host's number and the drawer's
      # number are one number computed by one pipeline, and a host that hands
      # the editor an assign the seam cannot be told about is exactly how the
      # two come apart.
      #
      # sabotage: dropped `:chart_outcomes` from `findings_count/3`'s option
      # reads (defaulting it to `%{}` unconditionally) -> 1 failure, here
      # (verified).
      test "findings_count/3 counts the disagreement the drawer shows", %{conn: conn} do
        document = purchase_document([])
        outcomes = %{"bdoc_CREDIT" => ["approved"]}

        without = StatifierBlocks.Editor.findings_count(document, EditorFixtures.palette())

        assert StatifierBlocks.Editor.findings_count(document, EditorFixtures.palette(),
                 chart_outcomes: outcomes
               ) == without + 1

        html = conn |> purchase_view(chart_outcomes: outcomes) |> render()

        assert html =~ "bdoc_CREDIT does not finish with"
      end
    end

    describe "a selection of another type" do
      test "is offered no outcome list", %{conn: conn} do
        view =
          purchase_view(conn,
            select: "blk_wait",
            chart_outcomes: %{"bdoc_CREDIT" => ["approved", "declined"]}
          )

        refute has_element?(view, ~s(datalist#sb-field-outcomes-finals))
      end
    end
  end
end
