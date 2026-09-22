if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.AcceptedEventsTest do
    @moduledoc """
    The declarations panel's accepted-events row as an author drives it
    (ADR-0014 decision 6).

    `StatifierBlocks.AcceptsTest` holds the list arithmetic, the command and
    its refusals with no LiveView present; this file holds the translation -
    that the row is drawn, that each gesture reaches `{:set_accepts, names}`,
    that the host is told, that undo steps back through it, that a refusal is
    held rather than dropped, and that a read-only mount draws values only.

    The document is the patron registration fixture, which declares
    `email.verified` and `registration.abandoned`.
    """

    use StatifierBlocks.EditorLiveCase

    alias StatifierBlocks.{Document, DocumentFixtures}

    defp patron(accepts \\ ["email.verified", "registration.abandoned"]) do
      %{DocumentFixtures.patron_registration() | accepts: accepts}
    end

    defp open(view) do
      view |> element("button.sb-drawer__strip") |> render_click()
      view |> element("#sb-drawer-tab-declarations") |> render_click()
      view
    end

    defp names(view) do
      view
      |> render()
      |> then(&Regex.scan(~r/class="sb-accepts__row" data-index="\d+" data-name="([^"]*)"/, &1))
      |> Enum.map(&Enum.at(&1, 1))
    end

    defp rename(view, index, name) do
      view
      |> element("#sb-accepted-#{index}")
      |> render_change(%{"index" => to_string(index), "name" => name})
    end

    defp click(view, index, selector) do
      view
      |> element(~s(.sb-accepts__row[data-index="#{index}"] #{selector}))
      |> render_click()
    end

    describe "the row" do
      # Sabotage: dropping `accepted={@accepted}` from the drawer's call into
      # `Declarations.declarations/1` - the component's `[]` default draws the
      # empty sentence and no rows.
      test "shows the document's accepted events, in order", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, document: patron())

        open(view)

        assert names(view) == ["email.verified", "registration.abandoned"]
        assert has_element?(view, "#sb-drawer-panel-declarations .sb-accepts")
        refute has_element?(view, ".sb-accepts__empty")
      end

      # Sabotage: `Shell.drawer_view/1` counting only `:declarations` - the
      # strip says `(0)` for a document declaring two accepted events.
      test "counts toward the tab's declarations", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, document: patron())

        open(view)

        assert view |> element("#sb-drawer-tab-declarations") |> render() =~ "(2)"
      end

      # Sabotage: dropping the `.sb-accepts__empty` paragraph from
      # `Declarations.declarations/1` - a document declaring none draws an
      # empty heading and nothing saying what that means.
      test "says so when the document declares none", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, document: patron([]))

        open(view)

        assert names(view) == []
        assert has_element?(view, ".sb-accepts__empty")
      end
    end

    describe "add" do
      # Sabotage: `handle_event("accepted-add", ...)` skipping
      # `notify_change/2` in `commit_accepted/2` - the host never learns the
      # document moved.
      test "appends a placeholder name and tells the host", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, document: patron(["email.verified"]))

        open(view)
        view |> element("button.sb-accepts__add") |> render_click()

        assert names(view) == ["email.verified", "event_1"]
        assert %Document{accepts: ["email.verified", "event_1"]} = latest_document()
      end
    end

    describe "edit" do
      # Sabotage: `handle_event("accepted-change", ...)` reading the index as
      # the name - the row is not renamed and the document does not move.
      test "renames an accepted event through the form", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, document: patron())

        open(view)
        rename(view, 1, "patron.blocked")

        assert names(view) == ["email.verified", "patron.blocked"]
        assert %Document{accepts: ["email.verified", "patron.blocked"]} = latest_document()
      end
    end

    describe "reorder" do
      # Sabotage: `accepted-move` calling `set_declarations/2` instead of
      # `set_accepted/2` - the roots are moved (or nothing is) and the
      # accepted events stay put.
      test "moves a row through the panel's own buttons", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, document: patron())

        open(view)
        click(view, 1, ~s(button[phx-value-dir="up"]))

        assert names(view) == ["registration.abandoned", "email.verified"]

        assert %Document{accepts: ["registration.abandoned", "email.verified"]} =
                 latest_document()
      end

      # Sabotage: dropping the `candidate == document.accepts` guard in
      # `set_accepted/2` - a move off the end pushes an undo entry and
      # notifies the host of a document that did not move.
      test "a move off the end commits nothing", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, document: patron())

        open(view)

        view
        |> with_target("#editor")
        |> render_click("accepted-move", %{"index" => "0", "dir" => "up"})

        assert names(view) == ["email.verified", "registration.abandoned"]
        assert latest_document() == nil
      end
    end

    describe "remove" do
      # Sabotage: `accepted-remove` calling `set_declarations/2` instead of
      # `set_accepted/2` - the roots are asked to lose an entry, and the
      # accepted event stays.
      test "drops the row and tells the host", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, document: patron())

        open(view)
        click(view, 0, "button.sb-accepts__remove")

        assert names(view) == ["registration.abandoned"]
        assert %Document{accepts: ["registration.abandoned"]} = latest_document()
      end
    end

    describe "a refused edit" do
      # Sabotage: `commit_accepted/2` dropping the draft on refusal - the
      # author's typed name is replaced by the document's, and the sentence
      # saying why is never drawn.
      test "is held as a draft, with the sentence saying why", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, document: patron())

        open(view)
        rename(view, 1, "email.verified")

        assert view |> element(".sb-accepts__refusal") |> render() =~ "email.verified"
        assert names(view) == ["email.verified", "email.verified"]
        assert latest_document() == nil
        refute has_element?(view, ".sb-declarations__refusal")
      end

      # Sabotage: `commit_accepted/2`'s success arm leaving `accepted_draft`
      # as it was - the refusal sentence outlives the fix.
      test "clears once a change the document accepts arrives", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, document: patron())

        open(view)
        rename(view, 0, "")
        assert has_element?(view, ".sb-accepts__refusal")

        rename(view, 0, "copy.returned")

        refute has_element?(view, ".sb-accepts__refusal")
        assert names(view) == ["copy.returned", "registration.abandoned"]
      end
    end

    describe "the undo stack" do
      # Sabotage: `commit_accepted/2` not taking `history: session.history`
      # from the session - the removal lands but undo has nothing to step
      # back through, and a declared name is document content.
      test "steps back through an accepted-event edit like any other", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, document: patron())

        open(view)
        click(view, 0, "button.sb-accepts__remove")
        assert names(view) == ["registration.abandoned"]

        view |> with_target("#editor") |> render_click("undo", %{})

        assert names(view) == ["email.verified", "registration.abandoned"]

        assert %Document{accepts: ["email.verified", "registration.abandoned"]} =
                 latest_document()
      end
    end

    describe "a read-only mount" do
      # Sabotage: dropping the `accepted-*` names from `@read_only_refused` -
      # the crafted add lands and the host is told of a document a read-only
      # mount changed.
      test "draws values with no controls, and refuses a crafted gesture", %{conn: conn} do
        {:ok, view, _html} =
          mount_editor(conn, document: patron(), profile: %{read_only?: true})

        open(view)
        html = render(view)

        refute has_element?(view, "#sb-accepted-0")

        assert html =~
                 ~s(class="sb-accepts__row" data-index="0" data-name="email.verified" data-read-only="true")

        refute html =~ ~s(phx-click="accepted-add")
        refute html =~ ~s(phx-change="accepted-change")

        view |> with_target("#editor") |> render_click("accepted-add", %{})

        assert latest_document() == nil
      end
    end

    describe "a document the host swaps in" do
      # Sabotage: leaving `accepted_draft` out of `switch_document/2`'s reset
      # - the previous document's refusal stays drawn over the new one.
      test "clears a held draft", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, document: patron())

        open(view)
        rename(view, 0, "")
        assert has_element?(view, ".sb-accepts__refusal")

        send(view.pid, {:swap_document, %{patron(["loan.due"]) | id: "bdoc_OTHER"}})
        _rendered = render(view)
        open(view)

        refute has_element?(view, ".sb-accepts__refusal")
        assert names(view) == ["loan.due"]
      end
    end
  end
end
