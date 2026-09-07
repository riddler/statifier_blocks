# ADR-0005 decision 1: with `phoenix_live_view` absent the editor does not
# compile, so neither can a test that drives it. The `:liveview` tag on
# `StatifierBlocks.EditorLiveCase` excludes these from a headless *run*; this
# guard is what keeps them out of a headless *compile*.
if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.SelectedIdTest do
    @moduledoc """
    The selection seam *in*: ADR-0005's 2026-09-07 amendment, *a `selected_id`
    a host may write, honoured in `update/2` through `rebuild/1`*.

    Everything here drives the seam the way a host does - `send_update/3` into
    the mounted component - rather than by reaching into assigns, for the
    reason the marks tests give: `send_update/3` carries only the keys it
    names, and the guard that makes an unnamed key mean *leave it alone* is
    half of what is under test (1S).

    The other half is 3S: an id the open document does not hold is not a
    selection, it is `nil`, and the `on_select` callback hears that (4S). The
    id is asserted through the markup the canvas draws rather than through
    component state, because what the record promises a host is that the
    editor is *about* that block - the selected card and the inspector
    addressing it - not that an assign holds a string.
    """

    use StatifierBlocks.EditorLiveCase

    alias StatifierBlocks.Editor

    defp select_input(view, id) do
      Phoenix.LiveView.send_update(view.pid, Editor, id: "editor", selected_id: id)
      render(view)
    end

    defp selected?(html, block_id) do
      html =~ ~r/class="[^"]*sb-node--selected[^"]*"[^>]*id="sb-block-#{block_id}"/
    end

    defp any_selection?(html), do: html =~ "sb-node--selected"

    describe "1S: a documented input, honoured only when the update carries it" do
      # Sabotage: dropped the branch and leaned on the `assign(assigns)` at the
      # head of `update/2` - GREEN here, which is worth stating rather than
      # hiding: a raw write does move the selection, and that it appears to
      # work is exactly why the record calls it out. What the branch buys shows
      # up in the three tests after this one - the normalization, the guard's
      # own case, and the companion resets - and each of those is red without
      # it.
      test "a host's write moves the selection", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        assert selected?(select_input(view, "blk_email_step"), "blk_email_step")
      end

      # Sabotage: made the branch unconditional, reading
      # `Map.get(assigns, :selected_id)` instead of guarding on
      # `Map.has_key?/2` - red, because the host's next re-render, made for a
      # reason of its own, carries no `selected_id` and the author's selection
      # is cleared under them (verified).
      test "an update that does not carry the key leaves the selection alone",
           %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        select_input(view, "blk_email_step")

        Phoenix.LiveView.send_update(view.pid, Editor, id: "editor", findings: [])

        assert selected?(render(view), "blk_email_step")
      end

      # `nil` is a selection, per the 2026-09-05 amendment, and a host clears
      # by writing it.
      #
      # Sabotage: treated `nil` as "no key passed" - red, because the host then
      # has no way to clear a selection it set.
      test "a host clears the selection by writing nil", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        select_input(view, "blk_email_step")

        refute any_selection?(select_input(view, nil))
      end
    end

    describe "3S: an id the document does not hold clears the selection" do
      # The record rejects refusing the update by name: a host whose pane is one
      # render behind the document is the normal case, not an error. So the
      # stale id is *dropped*, and what the author is left with is no selection
      # rather than the one the host has just superseded.
      #
      # Sabotage: refused the update by keeping the last selection the
      # component reported - the alternative 3S rejects by name - red, because
      # the canvas then keeps a card selected that the host has explicitly
      # moved off (verified).
      test "an unknown id selects nothing, and does not leave the old selection",
           %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        select_input(view, "blk_email_step")

        refute any_selection?(select_input(view, "blk_not_in_this_document"))
      end

      # The case the normalization is actually load-bearing for, and the one no
      # assertion about markup can see: an unknown id written over NO selection
      # has changed nothing, so `notified_id` must record `nil` and the seam
      # must stay quiet. Written through unnormalized, the component believes
      # it holds a selection the canvas cannot draw, and says so.
      #
      # Sabotage: wrote the incoming id through unnormalized - red, because a
      # stale row click then reports a selection that does not exist and leaves
      # the unknown id in `notified_id` to be compared against later
      # (verified).
      test "an unknown id over no selection is not a change", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        select_input(view, "blk_not_in_this_document")

        assert selections() == []
      end
    end

    describe "4S: the write is reported back out through `on_select`" do
      # Sabotage: suppressed the echo, writing `notified_id` beside the
      # selection so the input's own write never reaches the callback - red,
      # because a host that both writes and listens then never learns what the
      # component actually did with its write, which 4S says is the whole point
      # in the case where the two differ (verified).
      test "a resolved id fires `on_select` with the descriptor", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        select_input(view, "blk_email_step")

        assert selections() == [%{id: "blk_email_step", type: "core.wait", label: "Wait"}]
      end

      # The case the record calls out by name: the host's pane is one render
      # behind, its id no longer resolves, and the host has to be told so its
      # own pane can empty itself.
      #
      # Sabotage: refused the update as above, keeping the last reported
      # selection instead of clearing - red, because the pane is then never
      # told the row it clicked is gone and keeps it marked (verified).
      test "an unknown id fires `on_select` with nil", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        select_input(view, "blk_email_step")
        select_input(view, "blk_not_in_this_document")

        assert selections() == [
                 %{id: "blk_email_step", type: "core.wait", label: "Wait"},
                 nil
               ]
      end

      # 4S reads the 2026-09-05 amendment's rule from this side: the callback
      # fires when the selection CHANGES, and a host writing the id already
      # selected has changed nothing.
      #
      # Sabotage: cleared `notified_id` in the branch, which notifies on every
      # update carrying the key - red, because a host that re-passes its own
      # assigns then hears itself on every render (verified).
      test "re-writing the id already selected fires nothing", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        select_input(view, "blk_email_step")
        assert selections() == [%{id: "blk_email_step", type: "core.wait", label: "Wait"}]

        # `Phoenix.Component.assign/3` drops a value equal to the one held, so
        # the key has to arrive beside something that moved for `update/2` to
        # run at all.
        Phoenix.LiveView.send_update(view.pid, Editor,
          id: "editor",
          selected_id: "blk_email_step",
          theme: %{"--sb-canvas-bg" => "#fff"}
        )

        render(view)

        assert selections() == []
      end
    end

    describe "6S: the input takes the canvas gestures companion resets" do
      # The sheet is an overlay over the canvas below 780, so a selection made
      # while it is open leaves the block the host just named behind the thing
      # covering it - the same reason the canvas gestures own handler closes
      # it.
      #
      # Sabotage: dropped the `palette_sheet: false` reset - red, because the
      # sheet then stays over the canvas the host just re-aimed (verified).
      test "a host write closes the palette sheet", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        view |> element(~s(button[phx-click="palette-sheet"])) |> render_click()
        assert render(view) =~ ~s(data-sheet="open")

        refute select_input(view, "blk_email_step") =~ ~s(data-sheet="open")
      end
    end

    describe "5S: an input, not a command" do
      # Decision 2's closed command set is untouched: a selection is not a
      # document edit, so `on_change` says nothing about one.
      #
      # Sabotage: reported the selection out through `notify_change/2` as an
      # edit would be - red, because the host then receives a document it never
      # asked for and cannot tell a selection from a change (verified).
      test "moving the selection is not a document change", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        select_input(view, "blk_email_step")

        refute_receive {:document, _document}
        assert has_element?(view, ~s(button[phx-click="undo"][disabled]))
      end
    end
  end
end
