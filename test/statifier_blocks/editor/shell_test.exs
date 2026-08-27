# ADR-0005 decision 1: with `phoenix_live_view` absent the editor does not
# compile, so neither can a test that drives it. The `:liveview` tag on
# `StatifierBlocks.EditorLiveCase` excludes these from a headless *run*; this
# guard is what keeps them out of a headless *compile*, which is the earlier
# of the two problems.
if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.ShellTest do
    @moduledoc """
    The shell's event translation, driven through `Phoenix.LiveViewTest`.

    ADR-0005's consequence is that the great majority of the editor's behaviour
    is tested in plain ExUnit with no browser and no LiveView, and that
    `LiveViewTest` covers what is left: turning a `phx-` event into a command.
    These are those tests.
    """

    use StatifierBlocks.EditorLiveCase

    alias StatifierBlocks.Document

    describe "mounting" do
      test "renders every block in the document, unresolvable ones included", %{conn: conn} do
        {:ok, view, html} = mount_editor(conn)

        for id <- ~w(blk_wizard blk_email_step blk_variant blk_track_conversion blk_settle_pause) do
          assert html =~ ~s(data-block-id="#{id}")
        end

        assert has_element?(
                 view,
                 ~s([data-block-id="blk_track_conversion"][data-status="unresolvable"])
               )
      end

      test "surfaces the revision it loaded, for a host's optimistic concurrency", %{conn: conn} do
        document = EditorFixtures.signup_wizard()
        {:ok, _view, html} = mount_editor(conn, document: document)

        assert html =~ ~s(data-revision="#{document.revision}")
      end
    end

    describe "selection" do
      test "clicking a block's label selects it and opens its form", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        refute has_element?(view, ".sb-form")

        view
        |> element(~s([data-block-id="blk_email_step"] > .sb-node__chrome > .sb-node__label))
        |> render_click()

        assert has_element?(view, ~s(.sb-form[data-block-id="blk_email_step"]))
        assert has_element?(view, ~s([data-block-id="blk_email_step"].sb-node--selected))
      end

      test "an unresolvable block may be selected but gets no form (d12)", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        view
        |> element(
          ~s([data-block-id="blk_track_conversion"] > .sb-node__chrome > .sb-node__label)
        )
        |> render_click()

        assert has_element?(view, ~s([data-block-id="blk_track_conversion"].sb-node--selected))
        refute has_element?(view, ~s(.sb-form[data-block-id="blk_track_conversion"]))
      end
    end

    describe "delete" do
      test "removes the block and notifies the host", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        view
        |> element(~s([data-block-id="blk_email_step"] > .sb-node__chrome > .sb-node__remove))
        |> render_click()

        refute has_element?(view, ~s([data-block-id="blk_email_step"]))

        ids = latest_document() |> Document.blocks() |> Enum.map(& &1.id)
        refute "blk_email_step" in ids
      end

      test "an unresolvable block may be deleted, children and all", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        view
        |> element(
          ~s([data-block-id="blk_track_conversion"] > .sb-node__chrome > .sb-node__remove)
        )
        |> render_click()

        ids = latest_document() |> Document.blocks() |> Enum.map(& &1.id)
        refute "blk_track_conversion" in ids
        refute "blk_settle_pause" in ids
      end
    end

    describe "undo and redo" do
      test "step back to the document before the edit, and forward again", %{conn: conn} do
        {:ok, view, html} = mount_editor(conn)
        before = EditorFixtures.signup_wizard()

        assert html =~ ~s(<button type="button" class="sb-toolbar__button" phx-click="undo")

        view
        |> element(~s([data-block-id="blk_email_step"] > .sb-node__chrome > .sb-node__remove))
        |> render_click()

        view |> element(~s(button[phx-click="undo"])) |> render_click()
        assert Document.content_hash(latest_document()) == Document.content_hash(before)

        view |> element(~s(button[phx-click="redo"])) |> render_click()
        refute "blk_email_step" in Enum.map(Document.blocks(latest_document()), & &1.id)
      end

      test "undo is disabled with nothing to undo", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        assert has_element?(view, ~s(button[phx-click="undo"][disabled]))
        assert has_element?(view, ~s(button[phx-click="redo"][disabled]))
      end
    end
  end
end
