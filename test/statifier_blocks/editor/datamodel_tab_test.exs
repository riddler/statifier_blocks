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
    declared path with the surface that declared it, the shape the ADR-0006
    projection carries and the `one_of` values it declares (cut at eight, with
    the remainder counted), that a document nothing declares for gets the empty
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

    # The same shape again, carrying enumerations: two values on one path,
    # eleven on another so that the eight-value cut has a remainder to count,
    # and a third path with a type and no `one_of` at all.
    @enumerated %{
      "version" => 1,
      "scopes" => [
        %{
          "scope" => "local",
          "entries" => [
            %{
              "path" => "card.brand",
              "type" => "string",
              "one_of" => ["visa", "amex"]
            },
            %{
              "path" => "signup.step",
              "type" => "string",
              "one_of" => Enum.map(1..11, &"step_#{&1}")
            },
            %{"path" => "signup.email", "type" => "string"}
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

    # The Values cell of one row, as markup: the assertions below are about
    # which values landed in WHICH row, and a match against the whole panel
    # would pass on a cell that drew every path's enumeration.
    defp values_cell(html, path) do
      case Regex.run(
             ~r{<tr data-path="#{Regex.escape(path)}".*?<td data-cell="values">(.*?)</td>}s,
             html
           ) do
        [_whole, cell] -> cell
        nil -> nil
      end
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

    describe "the values column" do
      # Sabotage: the Values `<td>` reading `@values` rather than
      # `Map.get(@values, row.path, [])` - every row drew every path's
      # enumeration and the first assertion caught the brand values on the
      # step's row.
      test "lists the values a path's one_of declares", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, datamodel: @enumerated)

        open(view)

        html = render(view)

        assert values_cell(html, "card.brand") =~ "visa"
        assert values_cell(html, "card.brand") =~ "amex"
        refute values_cell(html, "card.brand") =~ "more"
      end

      # Eight is the cut, and the ninth value is what proves it is a cut
      # rather than a coincidence of this fixture's length.
      # Sabotage: `Enum.take/2` given the whole list - the count went to
      # "+0 more", the ninth value appeared, and both halves went red.
      test "cuts at eight values and counts the rest", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, datamodel: @enumerated)

        open(view)

        cell = values_cell(render(view), "signup.step")

        assert cell =~ "step_1"
        assert cell =~ "step_8"
        refute cell =~ "step_9"
        assert cell =~ "+3 more"
      end

      # A shape is not an enumeration: the column is empty for a path that
      # declared a type and nothing else, and for the two declaring surfaces
      # that carry no shape at all.
      # Sabotage: the cell's `:if={@shown != []}` dropped - an empty
      # enumeration drew an empty chip row, and the refutation on the wrapper
      # class went red.
      test "is empty for a path that declares no enumeration", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, datamodel: @enumerated, declare: ["host_root"])

        open(view)

        html = render(view)

        refute values_cell(html, "signup.email") =~ "sb-datamodel__values"
        refute values_cell(html, "host_root") =~ "sb-datamodel__values"
      end

      # `value_candidates` is a host's correction to the PICKER, and this
      # table is a report of what the document declared. A host's map reaching
      # this column would put values in a "Declared paths" grid that no
      # declaration carries.
      # Sabotage: `declared_values/1` in the editor calling
      # `Datamodel.value_candidates/2` with `assigns.value_candidates` - the
      # host's single value replaced the declaration's two and this went red.
      test "reports the declaration and not a host's picker override", %{conn: conn} do
        {:ok, view, _html} =
          mount_editor(conn,
            datamodel: @enumerated,
            value_candidates: %{"card.brand" => ["diners"]}
          )

        open(view)

        cell = values_cell(render(view), "card.brand")

        assert cell =~ "visa"
        refute cell =~ "diners"
      end
    end
  end
end
