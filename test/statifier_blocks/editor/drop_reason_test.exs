if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.DropReasonTest do
    @moduledoc """
    The last leg of the wire: a host's widening relation, riding on
    `palette.assignability`, reaching the markup the author sees.

    `StatifierBlocks.Assignability.HostRelationTest` proves the relation
    moves the drop set and the validation findings together with LiveView
    absent. What can only be proved here is that the editor shell hands
    that answer to the DOM - `data-drop` for the verdict, and
    `data-drop-reason` beside it for the 2026-08-29 ADR-0003 amendment's
    vocabulary - with no round-trip and no JavaScript between the two.
    """

    use StatifierBlocks.EditorLiveCase

    alias StatifierBlocks.AssignabilityFixtures

    defp canvas(view), do: element(view, "#sb-canvas")

    # authorize, then an empty resumable group: the group's `body` has one
    # gap whose inbound type is `myapp.credit_card_txn`, and a
    # `myapp.post_to_ledger` dropped there consumes `myapp.card_txn` - not
    # identity, so the verdict is the host relation's and nothing else's.
    defp document do
      authorize = Block.new("myapp.authorize", id: "blk_AUTH")
      ledger = Block.new("myapp.post_to_ledger", id: "blk_LDG")

      group =
        Block.new("core.resumable_group",
          id: "blk_GRP",
          slots: %{"body" => [], "interrupts" => []}
        )

      root =
        Block.new("core.sequence", id: "blk_ROOT", slots: %{"body" => [authorize, group, ledger]})

      Document.new(root, id: "bdoc_drop_reason")
    end

    defp slot_attrs(html, parent_id, slot) do
      case Regex.run(
             ~r/data-slot-name="#{slot}" data-parent-id="#{parent_id}"([^>]*)>/,
             html
           ) do
        [_all, attrs] ->
          %{
            drop: capture(attrs, ~r/data-drop="([^"]*)"/),
            reason: capture(attrs, ~r/data-drop-reason="([^"]*)"/)
          }

        nil ->
          nil
      end
    end

    defp capture(attrs, regex) do
      case Regex.run(regex, attrs) do
        [_all, value] -> value
        nil -> nil
      end
    end

    defp drag_ledger(conn, relation) do
      {:ok, view, _html} =
        mount_editor(conn, document: document(), palette: AssignabilityFixtures.palette(relation))

      canvas(view) |> render_hook("dragstart", %{"block-id" => "blk_LDG"})
    end

    describe "the host relation reaches the markup" do
      # Sabotage: `Assignability.assignable?/3`'s step-4 clause returning
      # `false` instead of calling `module.assignable?/2` - this goes red,
      # because the slot the host's widening opens goes dark in the DOM,
      # which is the whole end-to-end path failing at its one host seam.
      test "a slot the host widens open is stamped accepting, with nothing to explain" do
        html = drag_ledger(build_conn(), AssignabilityFixtures.Widens)

        assert slot_attrs(html, "blk_GRP", "body") == %{drop: "ok", reason: nil}
      end

      # Sabotage: `Editor.drag_session/2` building `:reasons` from the `:ok`
      # rows instead of the `{:refused, _}` rows - this goes red, because the
      # refused slot loses its reason attribute entirely.
      test "the same slot without the relation is stamped refusing, and says why" do
        html = drag_ledger(build_conn(), nil)

        # `fixable_by:<id>` rather than `not_assignable`, per ADR-0011
        # decision 8: the environment names the block whose write signature
        # put the offending type at the path, so the attribute now sends the
        # author to a declaration instead of to nothing.
        assert slot_attrs(html, "blk_GRP", "body") == %{
                 drop: "no",
                 reason: "fixable_by:blk_AUTH"
               }
      end

      # Sabotage: `Slot.drop_reason/3`'s `reasons` lookup keyed
      # `{slot_name, parent_id}` instead of `{parent_id, slot_name}` - this
      # goes red, because every reason lands on the wrong slot or on none.
      test "a structural refusal carries no reason from the data-flow vocabulary" do
        html = drag_ledger(build_conn(), nil)

        # `interrupts` admits only `:interrupt_handler`, and the ledger is a
        # `:step` - ADR-0003 decision 3's gate, whose finding names both kind
        # sets itself.
        assert slot_attrs(html, "blk_GRP", "interrupts") == %{drop: "no", reason: nil}
      end

      # Sabotage: `Slot.slot/1` stamping `data-drop-reason` unconditionally
      # rather than from `drop_reason/3` - this goes red, because the
      # attribute appears before any drag has started.
      test "outside a drag session neither attribute is present" do
        {:ok, _view, html} =
          mount_editor(build_conn(),
            document: document(),
            palette: AssignabilityFixtures.palette(nil)
          )

        assert slot_attrs(html, "blk_GRP", "body") == %{drop: nil, reason: nil}
      end

      # Sabotage: `Editor.handle_event("dragend", ...)` left assigning the
      # drag session instead of `nil` - this goes red, because the reason
      # outlives the drag it belongs to.
      test "dragend clears the reason along with the verdict" do
        {:ok, view, _html} =
          mount_editor(build_conn(),
            document: document(),
            palette: AssignabilityFixtures.palette(nil)
          )

        html = canvas(view) |> render_hook("dragstart", %{"block-id" => "blk_LDG"})
        assert slot_attrs(html, "blk_GRP", "body").reason == "fixable_by:blk_AUTH"

        html = canvas(view) |> render_hook("dragend", %{})
        assert slot_attrs(html, "blk_GRP", "body") == %{drop: nil, reason: nil}
      end
    end
  end
end
