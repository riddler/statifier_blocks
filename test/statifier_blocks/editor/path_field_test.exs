# ADR-0005 decision 1: with `phoenix_live_view` absent the editor does not
# compile, so neither can a test that drives it. The type's own claim - that
# `datamodel_path?/1` reads it, and that the advisory therefore reaches the
# field - is pure and lives in `StatifierBlocks.BlockTypeTest` and
# `StatifierBlocks.DatamodelTest`, both deliberately outside this guard.
if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.PathFieldTest do
    @moduledoc """
    The `{:path, opts}` control: ADR-0002 decision 7's eighth field type,
    reached by type alone.

    What only exists once there is markup is the half here - that the
    declared paths reach a datalist the input is bound to, that an
    undeclared value's `:info` advisory is drawn on this field, and that
    none of it constrains what an author may type. The set of candidates is
    `StatifierBlocks.Datamodel.candidates/3`'s and is asserted with LiveView
    absent.
    """

    use StatifierBlocks.EditorLiveCase

    alias StatifierBlocks.Document.DatamodelEntry

    @declared ["eligibility", "signup.step"]

    defp subchart_document(opts) do
      Document.new(
        Block.new("core.sequence",
          id: "blk_wizard",
          slots: %{
            "body" => [
              Block.new("core.subchart",
                id: "blk_eligibility",
                config: %{
                  "chart" => "bdoc_CHILD",
                  "outcomes" => "approved",
                  "assign_to" => Keyword.get(opts, :assign_to, "eligibility")
                },
                slots: %{"on_approved" => [], "on_error" => []}
              )
            ]
          }
        ),
        id: "doc_signup_wizard",
        datamodel: Keyword.get(opts, :entries, [])
      )
    end

    defp subchart_view(conn, opts) do
      {:ok, view, _html} =
        mount_editor(
          conn,
          [document: subchart_document(opts)] ++ Keyword.drop(opts, [:assign_to, :entries])
        )

      view
      |> element(~s([data-block-id="blk_eligibility"] > .sb-node__chrome > .sb-node__label))
      |> render_click()

      view
    end

    describe "the candidate list" do
      # Sabotage: dropped `list={@list_id}` from the new control's input ->
      # 2 failures, this one and the type assertion below, both on the
      # binding rather than on the options. A datalist attached to nothing
      # renders identically and suggests nothing, which is the defect a
      # "does the markup contain the paths" assertion would miss (verified).
      test "the declared paths render as a datalist the input is bound to", %{conn: conn} do
        view = subchart_view(conn, datamodel: @declared)

        assert has_element?(
                 view,
                 ~s(input[name="config[assign_to]"][list="sb-field-assign_to-paths"])
               )

        assert has_element?(view, ~s(datalist#sb-field-assign_to-paths[data-path-candidates="2"]))

        for path <- @declared do
          assert has_element?(view, ~s(datalist#sb-field-assign_to-paths option[value="#{path}"]))
        end
      end

      # Sabotage: widened the clause's `[_first | _rest]` to `_any` -> 1
      # failure, here (verified). No datamodel supplied is no candidates, and no
      # candidates is the plain input a `:string` rendered - an empty
      # `<datalist>` would be an element that suggests nothing.
      test "no declaring surface is the plain input, with no list to bind to", %{conn: conn} do
        view = subchart_view(conn, [])

        assert has_element?(view, ~s(input[name="config[assign_to]"]))
        refute has_element?(view, "datalist")
        refute has_element?(view, ~s(input[name="config[assign_to]"][list]))
      end

      # The document's own declarations are one of 11k's three surfaces, and
      # the editor threads all three into one list.
      #
      # Sabotage: `path_candidates/1` in `Editor` reading a document with
      # its own `datamodel` emptied -> this goes red and nothing else does,
      # which is the split it is drawn to make (verified).
      test "the document's own declarations reach the list", %{conn: conn} do
        view = subchart_view(conn, entries: [%DatamodelEntry{id: "eligibility"}])

        assert has_element?(view, ~s(datalist#sb-field-assign_to-paths[data-path-candidates="1"]))

        assert has_element?(
                 view,
                 ~s(datalist#sb-field-assign_to-paths option[value="eligibility"])
               )
      end

      # Sabotage: reverted `assign_to`'s declaration to `type: :string` ->
      # the field renders the plain input and the `data-field-type` reads
      # "string", so this goes red along with three of its neighbours
      # (verified). The control is reached by the
      # field TYPE, which is the whole reason the type exists beside the key.
      test "the control is reached by the field's type", %{conn: conn} do
        view = subchart_view(conn, datamodel: @declared)

        assert has_element?(view, ~s(.sb-field[data-field-type="path"] input[list]))
        refute has_element?(view, ~s(.sb-field[data-field-type="string"] input[list]))
      end
    end

    describe "the undeclared-path advisory (11e)" do
      # Sabotage: dropped `datamodel_path?/1`'s `{:path, _opts}` clause ->
      # the field is filtered out of `block_findings/5`, no advisory is
      # produced, and this goes red. The type is what carries the claim here;
      # the declaration names no key.
      test "an undeclared value draws the advisory on this field", %{conn: conn} do
        view = subchart_view(conn, assign_to: "risk_tier", datamodel: @declared)

        assert has_element?(
                 view,
                 ~s(.sb-field[data-field="assign_to"] .sb-finding),
                 "risk_tier is not declared"
               )
      end

      # Sabotage: anchored the advisory on the block rather than the field ->
      # the finding renders somewhere other than beside this control and the
      # positive assertion above goes red while this one stays green.
      test "a declared value draws no advisory", %{conn: conn} do
        view = subchart_view(conn, datamodel: @declared)

        refute has_element?(view, ~s(.sb-field[data-field="assign_to"] .sb-finding))
      end
    end

    describe "it suggests, and never constrains" do
      # Sabotage: rendered the candidates as a `<select>` instead - the
      # control a constraint would use -> this goes red with "value for
      # select config[assign_to] must be one of ...". The gate on what
      # reaches the document stays `validate_config/1`'s (decision 9).
      test "a value not on the list still reaches the document", %{conn: conn} do
        view = subchart_view(conn, datamodel: @declared)

        view
        |> form(~s(#sb-form-blk_eligibility), %{"config" => %{"assign_to" => "risk_tier"}})
        |> render_change()

        assert %{"assign_to" => "risk_tier"} =
                 latest_document()
                 |> Document.blocks()
                 |> Enum.find(&(&1.id == "blk_eligibility"))
                 |> Map.fetch!(:config)
      end
    end
  end
end
