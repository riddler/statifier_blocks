# ADR-0005 decision 1: with `phoenix_live_view` absent the editor does not
# compile, so neither can a test that drives it. The pure half of the note
# command - apply/2, its inverse, the history, the gate and a recipe's reach -
# is `StatifierBlocks.Edit.NoteTest`, deliberately outside this guard.
if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.NoteFieldTest do
    @moduledoc """
    The Config tab's note textarea (ADR-0005's Amendment of 2026-09-29, 2s):
    a change applies `{:update_note, id, note}` through the editor's one
    funnel, so the host is told, undo takes the note back and redo puts it
    back; a read-only mount draws no textarea and refuses the event.
    """

    use StatifierBlocks.EditorLiveCase

    alias StatifierBlocks.Edit

    @note "Sent once the patron submits the form; the desk resends by hand."

    defp select(view, id) do
      view
      |> element(~s([data-block-id="#{id}"] > .sb-node__chrome > .sb-node__label))
      |> render_click()

      view
    end

    defp write_note(view, id, note) do
      view
      |> form("#sb-inspector-note-" <> id, %{"note" => note})
      |> render_change()

      view
    end

    defp note_of(%Document{} = document, id),
      do: Enum.find(Document.blocks(document), &(&1.id == id)).note

    defp crafted(view, event, params) do
      view |> with_target("#editor") |> render_click(event, params)
      view
    end

    describe "the note textarea" do
      # Sabotage: the inspector's `note_section` rendered for no tab (its
      # `:if` reading `@tab == :findings`) - the Config tab draws no
      # textarea and every assertion here goes red.
      test "is the first thing on the Config tab once a block is selected", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        refute has_element?(view, "textarea.sb-inspector__note-input")

        select(view, "blk_email_step")

        assert has_element?(view, ~s(#sb-inspector-note-blk_email_step textarea[name="note"]))

        assert has_element?(
                 view,
                 ".sb-inspector__panel > :first-child textarea.sb-inspector__note-input"
               )
      end

      # Sabotage: the `note-change` handler committing `{:update_note, id, ""}`
      # whatever the author typed - the host is handed a document with no
      # note on the block, and the first assertion goes red.
      test "a change applies the command, and undo and redo move the note", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)
        select(view, "blk_email_step")

        write_note(view, "blk_email_step", @note)
        assert %Document{} = noted = latest_document()
        assert note_of(noted, "blk_email_step") == @note
        assert view |> element("#sb-inspector-note-input-blk_email_step") |> render() =~ @note

        view |> element(~s(button[phx-click="undo"])) |> render_click()
        assert note_of(latest_document(), "blk_email_step") == ""
        refute view |> element("#sb-inspector-note-input-blk_email_step") |> render() =~ @note

        view |> element(~s(button[phx-click="redo"])) |> render_click()
        assert latest_document() == noted
        assert view |> element("#sb-inspector-note-input-blk_email_step") |> render() =~ @note
      end

      # Sabotage: the handler's equality guard removed, so every change event
      # commits - the unchanged post notifies the host and the refutation
      # goes red.
      test "a change that moves nothing commits nothing", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)
        select(view, "blk_email_step")

        write_note(view, "blk_email_step", @note)
        assert latest_document()

        write_note(view, "blk_email_step", @note)
        refute latest_document()
      end

      # Sabotage: the handler committing a compound of the note and an
      # `{:update_config, id, %{"duration" => "2h"}}` - the config the block
      # held is replaced and the last assertion goes red.
      test "writes the block's note and leaves its config alone", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)
        select(view, "blk_email_step")
        before = Document.committed_config(EditorFixtures.signup_wizard(), "blk_email_step")

        write_note(view, "blk_email_step", @note)
        assert %Document{} = document = latest_document()

        assert note_of(document, "blk_email_step") == @note
        assert Document.committed_config(document, "blk_email_step") == before
      end
    end

    describe "a block term stored before the note field existed" do
      # The editor's fixture as a host could have kept it outside JSON before
      # blocks had a note: every `%Block{}` in it lacks the `:note` key.
      defp old_shape(%Document{root: root} = document) do
        %{document | root: strip_note(root)}
        |> :erlang.term_to_binary()
        |> :erlang.binary_to_term()
      end

      defp strip_note(%Block{slots: slots} = block) do
        block
        |> Map.delete(:note)
        |> Map.put(
          :slots,
          Map.new(slots, fn {name, children} -> {name, Enum.map(children, &strip_note/1)} end)
        )
      end

      # Sabotage: the editor's private `block_note/2` defaulting a missing
      # note to "x" rather than "" -> the empty change commits -> red.
      test "selects as a note-free block, and a change writes the note", %{conn: conn} do
        old = old_shape(EditorFixtures.signup_wizard())
        refute Map.has_key?(Enum.find(Document.blocks(old), &(&1.id == "blk_email_step")), :note)

        {:ok, view, _html} = mount_editor(conn, document: old)
        select(view, "blk_email_step")

        assert has_element?(view, ~s(#sb-inspector-note-blk_email_step textarea[name="note"]))

        write_note(view, "blk_email_step", "")
        refute latest_document()

        write_note(view, "blk_email_step", @note)
        assert note_of(latest_document(), "blk_email_step") == @note

        view |> element(~s(button[phx-click="undo"])) |> render_click()
        assert note_of(latest_document(), "blk_email_step") == ""
      end
    end

    describe "a read-only mount" do
      # Sabotage: the read-only `note_section` clause removed, so the editing
      # clause draws the textarea on a read-only mount too.
      test "draws no textarea, and draws a note as text", %{conn: conn} do
        document =
          EditorFixtures.signup_wizard()
          |> Edit.apply({:update_note, "blk_email_step", @note})
          |> then(fn {:ok, noted, _inverse} -> noted end)

        {:ok, view, _html} =
          mount_editor(conn, document: document, profile: %{read_only?: true})

        select(view, "blk_email_step")

        refute has_element?(view, "textarea.sb-inspector__note-input")
        refute render(view) =~ ~s(phx-change="note-change")
        assert view |> element(".sb-inspector__note-text") |> render() =~ @note
      end

      # Sabotage: `note-change` dropped from `@read_only_refused` - the
      # crafted event commits, the host is handed a document, and the
      # refutation goes red.
      test "refuses the note event", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, profile: %{read_only?: true})
        select(view, "blk_email_step")

        crafted(view, "note-change", %{"block-id" => "blk_email_step", "note" => @note})

        refute latest_document()
      end
    end
  end
end
