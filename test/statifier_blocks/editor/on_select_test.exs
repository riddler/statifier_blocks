defmodule StatifierBlocks.Editor.OnSelectTest do
  @moduledoc """
  The `on_select` seam: ADR-0005's 2026-09-05 amendment, *the host seams,
  `on_select` and a selection descriptor*.

  Two claims are under test and they are separable. What the host is handed -
  three keys, and `nil` for no selection - and when it is handed anything at
  all, which the record states as a rule about changes rather than renders.
  The second is why nearly every test here reads the whole mailbox instead of
  the last message in it: a seam that fired three times looks exactly like one
  that fired once to a helper that drains.
  """

  use StatifierBlocks.EditorLiveCase

  alias StatifierBlocks.EditorFixtures

  defp select(view, id) do
    view
    |> element(~s([data-block-id="#{id}"] > .sb-node__chrome > .sb-node__label))
    |> render_click()

    view
  end

  defp remove(view, id) do
    view
    |> element(~s([data-block-id="#{id}"] > .sb-node__chrome > .sb-node__remove))
    |> render_click()

    view
  end

  describe "the descriptor" do
    # The assertion is an equality rather than a match on purpose: a pattern
    # would pass a descriptor carrying the block's config as a fourth key,
    # which is the one shape the record rules out by name.
    #
    # Sabotage: `label` built from the node's type instead of the view model's
    # title -> red here alone (verified).
    test "is the id, the type, and the card's first line", %{conn: conn} do
      {:ok, view, _html} = mount_editor(conn)

      select(view, "blk_email_step")

      assert selections() == [%{id: "blk_email_step", type: "core.wait", label: "Wait"}]
    end

    # A block whose type the palette does not have is still a block the author
    # can select, so it is still a selection the host is told about - with the
    # string the card itself draws, which for the placeholder is the type.
    #
    # Sabotage: `selection/1` answering `nil` for an unresolvable node, the
    # plausible defect of deciding a host only wants blocks the editor can
    # render -> red here alone (verified).
    test "labels an unresolvable block with its type", %{conn: conn} do
      {:ok, view, _html} = mount_editor(conn)

      select(view, "blk_track_conversion")

      assert selections() ==
               [
                 %{
                   id: "blk_track_conversion",
                   type: "signup.track_conversion",
                   label: "signup.track_conversion"
                 }
               ]
    end
  end

  describe "when it fires" do
    # Sabotage for this describe block: dropping the comparison against the
    # last id notified, so `rebuild/1` fires every time -> 9 of the 10 tests
    # in this file go red, this one included; a mount alone then delivers a
    # `nil` the record says it must not (verified).
    test "not on a mount with nothing selected", %{conn: conn} do
      {:ok, _view, _html} = mount_editor(conn)

      assert [] = selections()
    end

    test "once per selection, not once per render", %{conn: conn} do
      {:ok, view, _html} = mount_editor(conn)

      select(view, "blk_email_step")
      render(view)
      render(view)

      assert [%{id: "blk_email_step"}] = selections()
    end

    # "Selecting the already-selected block is not a change and does not
    # fire." The second click is a real event that reaches the handler and
    # re-assigns the same id; what stops the message is the comparison.
    test "not on re-selecting the block already selected", %{conn: conn} do
      {:ok, view, _html} = mount_editor(conn)

      view |> select("blk_email_step") |> select("blk_email_step")

      assert [%{id: "blk_email_step"}] = selections()
    end

    test "again when the selection moves to another block", %{conn: conn} do
      {:ok, view, _html} = mount_editor(conn)

      view |> select("blk_email_step") |> select("blk_variant")

      assert [%{id: "blk_email_step"}, %{id: "blk_variant"}] = selections()
    end

    # An edit is `on_change`'s subject, not this one's. The two callbacks are
    # siblings precisely so a host that wants documents is not made to receive
    # selections, and the last line is the other half of that: the document
    # did reach the host, down the other seam.
    test "not on an edit to the selected block", %{conn: conn} do
      {:ok, view, _html} = mount_editor(conn)

      select(view, "blk_email_step")
      assert [%{id: "blk_email_step"}] = selections()

      view
      |> form(~s(#sb-form-blk_email_step), %{"config" => %{"duration" => "2h"}})
      |> render_change()

      assert [] = selections()
      refute is_nil(latest_document())
    end
  end

  describe "deselection" do
    # "Deselection calls `on_select` with `nil`" - the whole point being that
    # a host panel can empty itself. A seam that only ever named a new block
    # would leave the panel showing a block that is no longer selected, and in
    # the delete case one that is no longer in the document at all.
    #
    # Sabotage: delivering only descriptors and swallowing the `nil` -> both
    # tests here go red and the other eight stay green (verified).
    test "a deleted selection hands the host nil", %{conn: conn} do
      {:ok, view, _html} = mount_editor(conn)

      view |> select("blk_email_step") |> remove("blk_email_step")

      assert [%{id: "blk_email_step"}, nil] = selections()
    end

    test "a document the host swaps in hands the host nil", %{conn: conn} do
      {:ok, view, _html} = mount_editor(conn)

      select(view, "blk_email_step")

      send(view.pid, {:swap_document, EditorFixtures.credit_card()})
      render(view)

      assert [%{id: "blk_email_step"}, nil] = selections()
    end
  end

  describe "a host that does not pass it" do
    # The record's "the host acquires no obligation": no new assign to supply,
    # and nothing that changes for a host that ignores the seam.
    test "selects exactly as before and is told nothing", %{conn: conn} do
      {:ok, view, _html} = mount_editor(conn, on_select: false)

      select(view, "blk_email_step")

      assert has_element?(view, ~s([data-block-id="blk_email_step"].sb-node--selected))
      assert [] = selections()
    end
  end
end
