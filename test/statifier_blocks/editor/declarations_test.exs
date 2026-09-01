if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.DeclarationsTest do
    @moduledoc """
    The declarations panel as an author drives it (ADR-0005's 2026-09-01
    amendment, 2i-2m).

    `StatifierBlocks.DeclarationsTest` holds the arithmetic with no LiveView
    present; this file holds the translation - that the tab is on the strip,
    that each gesture reaches `{:set_datamodel, entries}`, that the host is
    told, that undo steps back through a declaration edit like any other, and
    that a refusal is held rather than dropped.

    Reorder is asserted through the panel's own buttons, and that is the
    surface rather than a fallback: the amendment's 2j puts the gesture on
    native controls precisely so that no HTML5 drag - which an emulated mouse
    cannot start anyway - stands between an author and the order of the
    emitted `<data>` elements.
    """

    use StatifierBlocks.EditorLiveCase

    alias StatifierBlocks.Document
    alias StatifierBlocks.Document.DatamodelEntry
    alias StatifierBlocks.EditorFixtures

    defp declaring(entries, opts \\ []) do
      document = %{EditorFixtures.signup_wizard() | datamodel: entries}

      case Keyword.get(opts, :id) do
        nil -> document
        id -> %{document | id: id}
      end
    end

    defp entry(id, opts \\ []) do
      %DatamodelEntry{
        id: id,
        expr: Keyword.get(opts, :expr),
        description: Keyword.get(opts, :description)
      }
    end

    defp open(view) do
      view |> element("button.sb-drawer__strip") |> render_click()
      view |> element("#sb-drawer-tab-declarations") |> render_click()
      view
    end

    defp row_ids(view) do
      view
      |> render()
      |> then(
        &Regex.scan(~r/class="sb-declarations__row" data-index="\d+" data-id="([^"]*)"/, &1)
      )
      |> Enum.map(&Enum.at(&1, 1))
    end

    defp change(view, index, params) do
      view
      |> element("#sb-declaration-#{index}")
      |> render_change(Map.put(params, "index", to_string(index)))
    end

    describe "the tab" do
      # Sabotage: dropping `:declarations` from `Shell`'s `@drawer_tabs` - the
      # tab is not on the strip, the panel has no way in, and every test in
      # this file goes red at `open/1`.
      test "is on the strip, and its count is the document's declarations", %{conn: conn} do
        document = declaring([entry("signup"), entry("card_last4")])
        {:ok, view, _html} = mount_editor(conn, document: document)

        open(view)

        assert has_element?(view, ~s(#sb-drawer-tab-declarations[aria-selected="true"]))
        assert view |> element("#sb-drawer-tab-declarations") |> render() =~ "Declarations"
        assert view |> element("#sb-drawer-tab-declarations") |> render() =~ "(2)"
        assert has_element?(view, ~s(#sb-drawer-panel-declarations .sb-declarations))
      end

      # 1A's test is tabular and document-level; 3A keeps anything that is not
      # about the selected block out of the inspector. Sabotage: rendering the
      # panel from `Inspector` as a fourth tab - this refutation goes red and
      # 3A's "exactly Config, Findings, Condition" stops being true.
      test "is a drawer tab and never an inspector one", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, document: declaring([entry("signup")]))

        open(view)

        refute has_element?(view, ".sb-inspector .sb-declarations")
        assert has_element?(view, ".sb-drawer #sb-drawer-tab-declarations")
        assert has_element?(view, ".sb-drawer #sb-drawer-panel-declarations .sb-declarations")

        assert view |> element(".sb-inspector__tabs") |> render() =~ "Condition"
        refute view |> element(".sb-inspector__tabs") |> render() =~ "Declarations"
      end

      test "shows an empty panel with no declarations, and no rows", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        open(view)

        assert has_element?(view, ".sb-declarations .sb-drawer__empty")
        assert row_ids(view) == []
      end
    end

    describe "add" do
      # Sabotage: `handle_event("declaration-add", ...)` calling `commit/2`
      # with `{:update_config, ...}` or skipping the notify - the host never
      # learns the document moved, which is the whole outbound contract.
      test "appends a named row and tells the host", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        open(view)
        view |> element("button.sb-declarations__add") |> render_click()

        assert row_ids(view) == ["root_1"]

        assert %Document{datamodel: [%DatamodelEntry{id: "root_1", expr: nil}]} =
                 latest_document()
      end

      test "keeps minting past the names already taken", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, document: declaring([entry("root_1")]))

        open(view)
        view |> element("button.sb-declarations__add") |> render_click()

        assert row_ids(view) == ["root_1", "root_2"]
      end
    end

    describe "edit" do
      # Sabotage: the name input going back to `name="id"` and the mapping in
      # `Declarations.change/3` with it - LiveView refuses that markup at
      # compile time, so the defect this guards is the mapping drifting away
      # from the markup after someone "fixes" one half.
      test "renames a declaration through the form", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, document: declaring([entry("root_1")]))

        open(view)
        change(view, 0, %{"name" => "signup"})

        assert row_ids(view) == ["signup"]
        assert %Document{datamodel: [%DatamodelEntry{id: "signup"}]} = latest_document()
      end

      test "writes an initial value and a description", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, document: declaring([entry("signup")]))

        open(view)
        change(view, 0, %{"name" => "signup", "expr" => "'start'", "description" => "the wizard"})

        assert %Document{datamodel: [entry]} = latest_document()
        assert {entry.id, entry.expr, entry.description} == {"signup", "'start'", "the wizard"}
      end

      # Sabotage: `Declarations.cast/2` writing `""` for a cleared optional
      # box - the change is refused rather than applied, so this test sees the
      # refusal banner instead of the cleared value.
      test "clearing the initial value box removes it rather than storing a blank", %{conn: conn} do
        document = declaring([entry("signup", expr: "'start'")])
        {:ok, view, _html} = mount_editor(conn, document: document)

        open(view)
        change(view, 0, %{"name" => "signup", "expr" => "", "description" => ""})

        assert %Document{datamodel: [entry]} = latest_document()
        assert {entry.expr, entry.description} == {nil, nil}
        refute has_element?(view, ".sb-declarations__refusal")
      end
    end

    describe "reorder" do
      # Sabotage: `declaration-move` reading `phx-value-dir` as the index -
      # the rows do not move and the order the compiled chart emits stops
      # being the order the author set (ADR-0001 11a).
      test "moves a row up and down through the panel's own buttons", %{conn: conn} do
        document = declaring([entry("alpha"), entry("bravo"), entry("charlie")])
        {:ok, view, _html} = mount_editor(conn, document: document)

        open(view)

        view
        |> element(~s(.sb-declarations__row[data-index="2"] button[phx-value-dir="up"]))
        |> render_click()

        assert row_ids(view) == ["alpha", "charlie", "bravo"]

        view
        |> element(~s(.sb-declarations__row[data-index="0"] button[phx-value-dir="down"]))
        |> render_click()

        assert row_ids(view) == ["charlie", "alpha", "bravo"]
        assert %Document{datamodel: entries} = latest_document()
        assert Enum.map(entries, & &1.id) == ["charlie", "alpha", "bravo"]
      end

      # Sabotage: dropping the no-op guard in `set_declarations/2` - the ends
      # push an undo entry that undoes nothing, so an author's undo appears
      # to be broken on the press after a move that did not move.
      test "a move off the end commits nothing", %{conn: conn} do
        document = declaring([entry("alpha"), entry("bravo")])
        {:ok, view, _html} = mount_editor(conn, document: document)

        open(view)

        # Pushed rather than clicked, because the control is disabled - which
        # is the point of the test below. The event still arrives from a stale
        # render or a crafted payload, and the server is what has to answer it.
        view
        |> with_target("#editor")
        |> render_click("declaration-move", %{"index" => "0", "dir" => "up"})

        assert row_ids(view) == ["alpha", "bravo"]
        assert latest_document() == nil
      end

      # Sabotage: dropping the `disabled` attribute - the first row offers an
      # "up" that does nothing, which is the affordance 2j says a no-op
      # control must not be.
      test "the ends are disabled rather than inert-looking", %{conn: conn} do
        document = declaring([entry("alpha"), entry("bravo")])
        {:ok, view, _html} = mount_editor(conn, document: document)

        open(view)

        assert has_element?(
                 view,
                 ~s(.sb-declarations__row[data-index="0"] button[phx-value-dir="up"][disabled])
               )

        assert has_element?(
                 view,
                 ~s(.sb-declarations__row[data-index="1"] button[phx-value-dir="down"][disabled])
               )
      end
    end

    describe "remove" do
      test "drops the row and tells the host", %{conn: conn} do
        document = declaring([entry("alpha"), entry("bravo")])
        {:ok, view, _html} = mount_editor(conn, document: document)

        open(view)

        view
        |> element(~s(.sb-declarations__row[data-index="0"] button.sb-declarations__remove))
        |> render_click()

        assert row_ids(view) == ["bravo"]
        assert %Document{datamodel: [%DatamodelEntry{id: "bravo"}]} = latest_document()
      end

      # Sabotage: `declaration_index/1` falling back to `0` the way
      # `to_index/1` does - a crafted index removes the FIRST declaration
      # instead of none, which is a payload editing a document. The `nil`
      # notification is the second half: `set_declarations/2` commits nothing
      # when the candidate is what the document already holds, so a no-op
      # gesture leaves the undo stack and the host alone too.
      test "a crafted index removes nothing, and notifies nothing", %{conn: conn} do
        document = declaring([entry("alpha"), entry("bravo")])
        {:ok, view, _html} = mount_editor(conn, document: document)

        open(view)

        view
        |> with_target("#editor")
        |> render_click("declaration-remove", %{"index" => "not-a-number"})

        assert row_ids(view) == ["alpha", "bravo"]
        assert latest_document() == nil
      end
    end

    describe "a refused edit" do
      # Sabotage: `set_declarations/2` assigning `last_error` the way
      # `commit/2` does instead of holding a draft - the author's keystrokes
      # are replaced by the document's value, so a typo silently deletes the
      # name they were halfway through typing.
      test "is held as a draft, with the sentence saying why", %{conn: conn} do
        document = declaring([entry("signup"), entry("card_last4")])
        {:ok, view, _html} = mount_editor(conn, document: document)

        open(view)
        change(view, 1, %{"name" => "signup"})

        assert view |> element(".sb-declarations__refusal") |> render() =~ "signup"
        assert row_ids(view) == ["signup", "signup"]
        assert latest_document() == nil
      end

      # 2A's count is a statement about the document. Sabotage: passing the
      # draft to `Shell.drawer_view/1` as well as to the panel - the strip
      # reports a document that does not exist.
      test "does not move the document, the tab count, or the undo stack", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, document: declaring([entry("signup")]))

        open(view)
        change(view, 0, %{"name" => ""})

        assert has_element?(view, ".sb-declarations__refusal")
        assert view |> element("#sb-drawer-tab-declarations") |> render() =~ "(1)"
        assert latest_document() == nil
      end

      test "clears once a change the document accepts arrives", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, document: declaring([entry("signup")]))

        open(view)
        change(view, 0, %{"name" => ""})
        assert has_element?(view, ".sb-declarations__refusal")

        change(view, 0, %{"name" => "checkout"})

        refute has_element?(view, ".sb-declarations__refusal")
        assert row_ids(view) == ["checkout"]
      end
    end

    describe "the undo stack" do
      # Sabotage: `set_declarations/2` writing the document straight into the
      # assigns instead of going through `Edit.History.commit/4` - the edit
      # lands but is not undoable, and a deleted declaration is document
      # content the author cannot get back.
      test "steps back through a declaration edit like any other", %{conn: conn} do
        document = declaring([entry("signup")])
        {:ok, view, _html} = mount_editor(conn, document: document)

        open(view)

        view
        |> element(~s(.sb-declarations__row[data-index="0"] button.sb-declarations__remove))
        |> render_click()

        assert row_ids(view) == []

        view |> with_target("#editor") |> render_click("undo", %{})

        assert row_ids(view) == ["signup"]
        assert %Document{datamodel: [%DatamodelEntry{id: "signup"}]} = latest_document()

        view |> with_target("#editor") |> render_click("redo", %{})

        assert row_ids(view) == []
      end
    end

    describe "a document the host swaps in" do
      # Sabotage: leaving `declaration_draft` out of `switch_document/2`'s
      # reset - the refusal banner from the previous document stays on screen
      # over a panel drawing entries the new document does not hold.
      test "clears a held draft, exactly as it clears the config drafts", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, document: declaring([entry("signup")]))

        open(view)
        change(view, 0, %{"name" => ""})
        assert has_element?(view, ".sb-declarations__refusal")

        send(view.pid, {:swap_document, declaring([entry("checkout")], id: "bdoc_OTHER")})
        _rendered = render(view)

        view |> element("button.sb-drawer__strip") |> render_click()
        view |> element("#sb-drawer-tab-declarations") |> render_click()

        refute has_element?(view, ".sb-declarations__refusal")
        assert row_ids(view) == ["checkout"]
      end
    end
  end
end
