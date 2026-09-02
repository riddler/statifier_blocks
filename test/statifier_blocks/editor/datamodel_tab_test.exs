# ADR-0005 decision 1: with `phoenix_live_view` absent the editor does not
# compile, so neither can a test that drives it. The `:liveview` tag on
# `StatifierBlocks.EditorLiveCase` excludes these from a headless *run*; this
# guard is what keeps them out of a headless *compile*.
if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.DatamodelTabTest do
    @moduledoc """
    The Datamodel drawer tab: the read-only view over every declared path.

    What is asserted here is what only a rendered drawer can show - that the
    tab is on the strip carrying the row count, that the grid draws a row per
    declared path with the surface that declared it and the shape the ADR-0006
    projection carries, that a document nothing declares for gets the empty
    state rather than an empty table, and that the panel offers no way to
    change any of it. The projection itself is
    `StatifierBlocks.DatamodelTest`'s claim, headless, where the rule lives.

    Read-only is asserted by refutation rather than by inspection, because the
    editable neighbour is one tab away: the Declarations tab is the surface
    that changes the document's own roots, and this one shows two surfaces the
    package cannot write to at all.
    """

    use StatifierBlocks.EditorLiveCase

    alias StatifierBlocks.Document.DatamodelEntry

    # ADR-0006's shape, small enough to read in the assertions below: an
    # object with two fields (one of them sensitive) and a list that names its
    # element type, which is the one type in decision 4's set that does not
    # describe a value on its own.
    @datamodel %{
      "version" => 1,
      "scopes" => [
        %{
          "scope" => "local",
          "entries" => [
            %{
              "path" => "card",
              "type" => "object",
              "label" => "Card",
              "fields" => [
                %{"path" => "card.brand", "type" => "string", "label" => "Brand"},
                %{"path" => "card.number", "type" => "string", "sensitive?" => true}
              ]
            },
            %{"path" => "risk_reasons", "type" => "list", "item_type" => "string"}
          ]
        }
      ]
    }

    defp open(view) do
      view |> element(".sb-drawer__strip") |> render_click()
      view |> element(~s(.sb-drawer__tab[phx-value-tab="datamodel"])) |> render_click()
      view
    end

    defp declaring(entries) do
      %{EditorFixtures.signup_wizard() | datamodel: entries}
    end

    defp paths(html) do
      ~r/<tr data-path="([^"]*)"/
      |> Regex.scan(html)
      |> Enum.map(&Enum.at(&1, 1))
    end

    describe "the tab" do
      # Sabotage: dropping `:datamodel` from `Shell`'s `@drawer_tabs` - the
      # tab is not on the strip, `open/1` cannot reach the panel, and every
      # test in this file goes red at the first click.
      test "is on the strip and its count is the number of declared paths", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, datamodel: @datamodel, declare: ["signup"])

        open(view)

        assert has_element?(view, ~s(#sb-drawer-tab-datamodel[aria-selected="true"]))
        assert view |> element("#sb-drawer-tab-datamodel") |> render() =~ "Datamodel"
        assert view |> element("#sb-drawer-tab-datamodel") |> render() =~ "(5)"
      end

      # The strip is the count's real reader, and 2A says it reports the
      # document rather than the selection.
      # Sabotage: `drawer_view/1` counting `length(declared_view)` for
      # `:declarations` instead of `Declarations.count/1` - the two tabs
      # reported the same number and this went red on the second assertion.
      test "its count is its own, not the Declarations tab's", %{conn: conn} do
        {:ok, view, _html} =
          mount_editor(conn,
            document: declaring([%DatamodelEntry{id: "signup"}]),
            datamodel: @datamodel
          )

        open(view)

        assert view |> element("#sb-drawer-tab-datamodel") |> render() =~ "(5)"
        assert view |> element("#sb-drawer-tab-declarations") |> render() =~ "(1)"
      end
    end

    describe "the grid" do
      # Sabotage: the panel's `cond` arm rendering `@view.tab == :datamodel`
      # after the catch-all `true ->` - the truth-table branch swallowed the
      # tab and no row reached the DOM.
      test "draws one row per declared path, in the projection's order", %{conn: conn} do
        {:ok, view, _html} =
          mount_editor(conn,
            document: declaring([%DatamodelEntry{id: "signup"}]),
            datamodel: @datamodel,
            declare: ["host_root"]
          )

        open(view)

        assert paths(render(view)) == [
                 "card",
                 "card.brand",
                 "card.number",
                 "host_root",
                 "risk_reasons",
                 "signup"
               ]
      end

      # Sabotage: `Shell.declared_shape/1` swapped for `row.type` in the
      # template - the `list of string` cell read `list`, and the shapeless
      # root's cell went blank. Both assertions went red.
      test "carries the declaring surface and the shape as the projection has it", %{conn: conn} do
        {:ok, view, _html} =
          mount_editor(conn, datamodel: @datamodel, declare: ["host_root"])

        open(view)

        html = render(view)

        assert html =~ ~r{<tr data-path="risk_reasons".*?list of string}s
        assert html =~ ~r{<tr data-path="host_root".*?<td>Host</td>\s*<td>unspecified</td>}s
        assert html =~ ~r{<tr data-path="card.brand".*?<td>Datamodel</td>\s*<td>string</td>}s
        assert html =~ ~r{<tr data-path="card.number" data-sensitive="true"}
      end

      # Sabotage: the panel's `:if={@rows == []}` empty-state paragraph
      # deleted - an author with nothing declared got a table head over no
      # rows, which says nothing about why.
      test "says so when nothing declares a path, rather than drawing an empty table", %{
        conn: conn
      } do
        {:ok, view, _html} = mount_editor(conn)

        open(view)

        assert view |> element("#sb-drawer-panel-datamodel") |> render() =~
                 "Nothing declares a datamodel path for this document"

        refute has_element?(view, ".sb-datamodel__scroll")
        assert view |> element("#sb-drawer-tab-datamodel") |> render() =~ "(0)"
      end

      # 11f's distinction, drawn where an author can see it: a host that
      # supplies an EMPTY document has claimed its documents may address
      # nothing, and that is the same empty view as no datamodel at all
      # because neither declares a path. The difference is in the advisories,
      # not here.
      # Sabotage: `declared_paths/1`'s document arm answering an empty
      # projection with `MapSet.new(["*"])` - the "empty document means we do
      # not know" defect the module's own moduledoc warns against. The panel
      # grew a wildcard row and this went red.
      test "an empty datamodel document declares nothing and draws nothing", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, datamodel: %{"version" => 1, "scopes" => []})

        open(view)

        assert paths(render(view)) == []
      end

      # Read-only, asserted against the panel rather than against the
      # moduledoc.
      # Sabotage: rendering `Declarations.declarations/1` in this tab's `cond`
      # arm - the form, its inputs and its buttons appeared inside this panel
      # and every refutation went red.
      test "offers nothing to change", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, datamodel: @datamodel)

        open(view)

        panel = view |> element("#sb-drawer-panel-datamodel") |> render()

        refute panel =~ "<form"
        refute panel =~ "<input"
        refute panel =~ "<button"
        refute panel =~ "phx-click"
      end
    end
  end
end
