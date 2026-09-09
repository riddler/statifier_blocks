if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.RefusalSurfaceTest do
    @moduledoc """
    A refused gesture on the surface (ADR-0005's Note of 2026-09-08, item 6).

    The Note's ruling is one sentence long - "a refused gesture renders
    `last_error` on the surface" - and the defect it answers is one an author
    hits and a test could not see. Every refusal the editor makes writes its
    reason into `last_error` and moved nothing else, and until this bead
    nothing read the assign: `sb-spn7` could not assert a refusal's reason
    without `:sys.get_state/1` into LiveView's component table, and an author
    could not tell a gesture the editor refused from a gesture that did
    nothing at all. That is the same indistinguishability the emulated-input
    problem has, arriving from the other side.

    So what is under test here is the surface, not the funnel:
    `StatifierBlocks.Edit.SessionTest` holds the sentence for each reason and
    this holds that the sentence reaches the page, in the canvas column where
    the gesture was made, once, and that it goes away again.

    The refusals driven here are the ones a crafted payload reaches without a
    composite in the document. `5E`'s admission refusal and the
    broken-declaration one need one, and they are asserted where their
    fixtures already are, in
    `StatifierBlocks.Editor.CompositeExpandTest`.
    """

    use StatifierBlocks.EditorLiveCase

    @refusal "[data-refusal=\"gesture\"]"

    describe "the sentence reaches the page" do
      # Sabotage: dropped the `:if={@gesture_refusal != nil}` guard from the
      # editor's paragraph - red here, because the region is then on the page
      # over an editor that has refused nothing.
      test "nothing is drawn while nothing has been refused", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        refute has_element?(view, @refusal)
      end

      # The four events below are one refusal each, and each is a different
      # arm of `Edit.Session.refusal/1`. They are driven through
      # `with_target/2` rather than through a control because three of them
      # have no control to drive: the toolbar disables Undo on an empty
      # stack, and no card draws an Expand affordance unless the block is
      # made of steps. The server answers the payload either way, which is
      # why the refusals exist at all.
      # Sabotage for the four cases below: removed the paragraph from the
      # editor's template altogether - red at each, because the refused
      # gesture then renders exactly what a gesture that did nothing does.
      # Sabotage: removed the paragraph from the editor's template - red, because
      # the refused gesture then renders what a gesture that did nothing does.
      test "an empty undo stack says so", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        gesture(view, "undo")

        assert has_element?(view, @refusal, "There is nothing to undo.")
      end

      # Sabotage: the same removal - red here too, and this case is the second
      # arm, so a template that drew only the undo sentence would still fail.
      test "an empty redo stack says so", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        gesture(view, "redo")

        assert has_element?(view, @refusal, "There is nothing to redo.")
      end

      # Sabotage: the same removal - red, and additionally red if `refusal/1`
      # dropped the type name, which is the part the author acts on.
      test "a pick the palette cannot resolve names the type", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        gesture(view, "palette-open", %{
          "parent-id" => "blk_wizard",
          "slot" => "body",
          "index" => "0"
        })

        gesture(view, "palette-pick", %{"type" => "myapp.nope"})

        assert has_element?(view, @refusal, ~s(The palette has no block type "myapp.nope".))
      end

      # Sabotage: the same removal - red. The reason here comes from the gate
      # rather than from the editor, which is the arm this case pins.
      test "the outermost block cannot be removed, and says so", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        gesture(view, "remove", %{"block-id" => "blk_wizard"})

        assert has_element?(view, @refusal, "The outermost block cannot be removed.")
      end
    end

    describe "`5E`'s refusals that need no composite" do
      # The one member of `5E` a document without a composite still
      # reaches, plus the missing-block arm beside it: both are refused by
      # `fetch_composite/3` before the expansion is asked for. The other
      # three need a composite - `5E`'s root arm is unreachable without one,
      # because a root that is not made of steps is refused as
      # `{:not_a_composite, id}` first - and are asserted in
      # `CompositeExpandTest` and in `Edit.SessionTest`, where the
      # composites and the vocabulary are.
      #
      # Sabotage: made `gesture_refusal/1` answer the reason term rather
      # than the sentence - red here, because `inspect/1` of the tuple is
      # the thing item 6 rules out: a term an author cannot act on.
      test "a block that is not made of steps", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        gesture(view, "expand", %{"block-id" => "blk_email_step"})

        assert has_element?(
                 view,
                 @refusal,
                 "That block is not made of steps, so there is nothing to replace it with."
               )
      end

      # Sabotage: the same removal - red. `fetch_composite/3`'s missing-block arm
      # is what produces the reason, and nothing else on the page reports it.
      test "a block the document no longer holds", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        gesture(view, "expand", %{"block-id" => "blk_NOPE"})

        assert has_element?(view, @refusal, "That block is no longer in the document.")
      end
    end

    describe "the sentence is one sentence, and it clears itself" do
      # One region, not one per refusal: a second refused gesture replaces
      # the sentence rather than stacking under it, because what the author
      # needs to read is why the gesture they just made was refused.
      #
      # Sabotage: had `landed/3`'s `{:error, _}` arm keep the socket's own
      # `last_error` rather than the session's - red, because the page then
      # answers the second refused gesture with the first one's sentence.
      test "a second refusal replaces the first", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        gesture(view, "undo")
        gesture(view, "redo")

        assert has_element?(view, @refusal, "There is nothing to redo.")
        refute has_element?(view, @refusal, "There is nothing to undo.")
      end

      # `landed/3` writes `last_error: nil` on every commit that moves the
      # document, so the sentence needs no dismissal of its own: the next
      # gesture that works takes it away.
      #
      # Sabotage: dropped `last_error: nil` from `landed/3`'s `{:ok, _}` arm
      # - red, because a refusal from ten gestures ago then sits over a
      # canvas the author has since edited.
      test "a gesture that lands clears it", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        gesture(view, "undo")
        assert has_element?(view, @refusal)

        gesture(view, "remove", %{"block-id" => "blk_email_step"})

        refute has_element?(view, @refusal)
      end
    end

    # A gesture as the server receives it. `with_target/2` is how the other
    # editor tests reach a payload no control produces
    # (`DeclarationsTest`'s crafted index is the precedent).
    defp gesture(view, event, params \\ %{}) do
      view |> with_target("#editor") |> render_click(event, params)
    end
  end
end
