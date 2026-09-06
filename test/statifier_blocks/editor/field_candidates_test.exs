# ADR-0005 decision 1: with `phoenix_live_view` absent the editor does not
# compile, so neither can a test that drives it. The pure half of this feed -
# the compile-side lint, and the fact that a candidate list decides no value -
# lives in `StatifierBlocks.Compiler.FieldCandidatesTest`, deliberately
# outside this guard.
if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.FieldCandidatesTest do
    @moduledoc """
    The `field_candidates` feed ADR-0011 names beside `{:path, opts}`'s two
    keys: the values a host offers for one field, keyed
    `{type_name, field_key}`.

    What only exists once there is markup is the half here - that a closed
    list draws a `<select>` and an open one a `<datalist>`, that no list at
    all draws the input the field already had, that a picked value reaches
    the document, and that a stored value the list does not offer is drawn
    rather than rewritten.
    """

    use StatifierBlocks.EditorLiveCase

    @key {"core.subchart", "chart"}

    @charts [
      {"bdoc_CREDIT", "Credit check"},
      {"bdoc_KYC", "Identity check"},
      {"bdoc_FRAUD", "Fraud review"}
    ]

    defp document(chart) do
      Document.new(
        Block.new("core.sequence",
          id: "blk_wizard",
          slots: %{
            "body" => [
              Block.new("core.subchart",
                id: "blk_check",
                config: %{"chart" => chart, "outcomes" => "approved"},
                slots: %{"on_approved" => [], "on_error" => []}
              )
            ]
          }
        ),
        id: "doc_signup_wizard"
      )
    end

    defp view(conn, opts) do
      {:ok, view, _html} =
        mount_editor(conn,
          document: document(Keyword.get(opts, :chart, "bdoc_CREDIT")),
          field_candidates: Keyword.get(opts, :field_candidates, %{})
        )

      view
      |> element(~s([data-block-id="blk_check"] > .sb-node__chrome > .sb-node__label))
      |> render_click()

      view
    end

    describe "a closed list" do
      # Sabotage: reordered the two `:string` clauses so the open one is
      # tried first -> a closed list falls through to the text input and
      # every assertion here goes red (verified).
      test "renders a select over the offered values, in declared order", %{conn: conn} do
        view = view(conn, field_candidates: %{@key => @charts})

        assert has_element?(view, ~s(select[name="config[chart]"][data-field-candidates="3"]))

        for {value, label} <- @charts do
          assert has_element?(
                   view,
                   ~s(select[name="config[chart]"] option[value="#{value}"]),
                   label
                 )
        end

        refute has_element?(view, ~s(input[name="config[chart]"]))
      end

      # The picked value is stored, which is the only thing a control is
      # actually for.
      #
      # Sabotage: named the option's `value` after its label -> the picked
      # value reaches the document as the label and this goes red (verified).
      test "picking a value stores it", %{conn: conn} do
        view = view(conn, field_candidates: %{@key => @charts})

        view
        |> element(~s(form[data-block-id="blk_check"]))
        |> render_change(%{"block-id" => "blk_check", "config" => %{"chart" => "bdoc_KYC"}})

        assert has_element?(view, ~s(option[value="bdoc_KYC"][selected]))
      end

      # A `<select>` whose stored value is not among its options posts the
      # FIRST option on the next change, so opening a form would rewrite a
      # value nobody touched. The stored value gets an option of its own.
      #
      # Sabotage: made `unoffered_value/2` answer `nil` always -> the
      # stored value has no option, the browser would select the first one,
      # and this goes red (verified).
      test "a stored value the list does not offer is drawn, not rewritten", %{conn: conn} do
        view = view(conn, chart: "bdoc_LEGACY", field_candidates: %{@key => @charts})

        assert has_element?(view, ~s(select[name="config[chart]"] option[value="bdoc_LEGACY"]))
        refute has_element?(view, ~s(option[value="bdoc_CREDIT"][selected]))
      end
    end

    describe "an open list" do
      # Sabotage: dropped `list={@list_id}` from the open control's input ->
      # the datalist is attached to nothing, which renders identically and
      # suggests nothing, and this goes red on the binding (verified).
      test "renders the text input bound to a datalist", %{conn: conn} do
        view = view(conn, field_candidates: %{@key => {:open, @charts}})

        assert has_element?(
                 view,
                 ~s(input[name="config[chart]"][list="sb-field-chart-candidates"])
               )

        assert has_element?(
                 view,
                 ~s(datalist#sb-field-chart-candidates[data-field-candidates="3"])
               )

        refute has_element?(view, ~s(select[name="config[chart]"]))
      end
    end

    describe "no list supplied" do
      # Sabotage: widened the closed clause's `[_ | _]` to `_any` -> an
      # empty list draws a `<select>` with no options, which offers an
      # author nothing and refuses them everything, and this goes red
      # (verified).
      test "renders the plain input the field already had", %{conn: conn} do
        for candidates <- [%{}, %{@key => []}] do
          view = view(conn, field_candidates: candidates)

          assert has_element?(view, ~s(input[name="config[chart]"]))
          refute has_element?(view, ~s(select[name="config[chart]"]))
          refute has_element?(view, ~s(datalist#sb-field-chart-candidates))
        end
      end

      # Sabotage: keyed the lookup on the field key alone -> a list meant
      # for another type's `chart` field reaches this one and this goes red
      # (verified).
      test "a list keyed on another type does not reach this field", %{conn: conn} do
        view = view(conn, field_candidates: %{{"host.step", "chart"} => @charts})

        assert has_element?(view, ~s(input[name="config[chart]"]))
        refute has_element?(view, ~s(select[name="config[chart]"]))
      end
    end
  end
end
