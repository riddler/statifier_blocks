# ADR-0005 decision 1: with `phoenix_live_view` absent the editor does not
# compile, so neither can a test that drives it. The `:liveview` tag on
# `StatifierBlocks.EditorLiveCase` excludes these from a headless *run*; this
# guard is what keeps them out of a headless *compile*, which is the earlier
# of the two problems.
if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.DragTest do
    @moduledoc """
    ADR-0005 decision 6, end to end: one round-trip at drag start, validity as
    markup, one round-trip at drop, and nothing in between.

    The semantics of the drag are not tested here - they were tested in
    `StatifierBlocks.Edit.TargetsTest` and `StatifierBlocks.EditPropertyTest`
    with LiveView absent from the dependency tree, which is the whole point of
    decision 5's split. What these tests cover is the part that could not be
    tested there: that the shell asks the right pure function at the right
    moment and puts its answer in the markup.
    """

    use StatifierBlocks.EditorLiveCase

    alias StatifierBlocks.Block
    alias StatifierBlocks.Edit.Targets

    defp canvas(view), do: element(view, "#sb-canvas")

    defp slot_drop(html, parent_id, slot) do
      case Regex.run(
             ~r/data-slot-name="#{slot}" data-parent-id="#{parent_id}"[^>]*data-drop="(\w+)"/,
             html
           ) do
        [_all, state] -> state
        nil -> nil
      end
    end

    describe "dragstart" do
      # Sabotage: `Slot.drop_state/3` returning "ok" unconditionally - the four
      # data-drop assertions below go red together.
      test "stamps every accepting slot before the pointer has moved", %{conn: conn} do
        {:ok, view, html} = mount_editor(conn)

        assert slot_drop(html, "blk_wizard", "body") == nil,
               "no drag session means no data-drop at all, not data-drop=no"

        html = canvas(view) |> render_hook("dragstart", %{"block-id" => "blk_email_step"})

        assert slot_drop(html, "blk_wizard", "body") == "ok"
        assert slot_drop(html, "blk_variant", "otherwise") == "ok"

        assert slot_drop(html, "blk_track_conversion", "after") == "no",
               "an unresolvable block has no slots/1, so decision 5 rule 1 excludes it"
      end

      # Sabotage: `Editor.handle_event("dragstart", ...)` computing
      # `droppable_slots/3` for the wrong id - this goes red because the two
      # sets differ.
      test "the stamped set is exactly droppable_slots/3's answer", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)
        document = EditorFixtures.signup_wizard()
        palette = EditorFixtures.palette()

        html = canvas(view) |> render_hook("dragstart", %{"block-id" => "blk_email_step"})

        expected = MapSet.new(Targets.droppable_slots(document, palette, "blk_email_step"))

        stamped =
          ~r/data-slot-name="([^"]+)" data-parent-id="([^"]+)"[^>]*data-drop="ok"/
          |> Regex.scan(html)
          |> MapSet.new(fn [_all, slot, parent] -> {parent, slot} end)

        assert stamped == expected
      end

      # Sabotage: dropping the `assign(socket, :drag, nil)` in the "dragend"
      # handler - the second assertion finds data-drop still stamped.
      test "dragend clears the session, and the stamps with it", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        html = canvas(view) |> render_hook("dragstart", %{"block-id" => "blk_email_step"})
        assert slot_drop(html, "blk_wizard", "body") == "ok"

        html = canvas(view) |> render_hook("dragend", %{})
        assert slot_drop(html, "blk_wizard", "body") == nil
      end
    end

    describe "drop" do
      # Sabotage: building `{:insert, ...}` instead of `{:move, ...}` in the
      # "drop" handler - the block ends up in both slots and the first
      # assertion fails.
      test "one command, one round-trip, and the block is where it was dropped", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        canvas(view) |> render_hook("dragstart", %{"block-id" => "blk_email_step"})

        canvas(view)
        |> render_hook("drop", %{
          "block-id" => "blk_email_step",
          "parent-id" => "blk_variant",
          "slot" => "otherwise",
          "index" => "0"
        })

        document = latest_document()

        assert slot_ids(document, "blk_variant", "otherwise") == [
                 "blk_email_step",
                 "blk_control_pause"
               ]

        assert slot_ids(document, "blk_wizard", "body") == ["blk_variant", "blk_track_conversion"]
      end

      # Sabotage: `Edit.apply/2`'s move arm reading the target index against the
      # slot *before* the removal (ADR-0005 decision 4's rejected reading) - the
      # order comes back reversed.
      test "a move within one slot reads the index with the block removed (d4)", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        canvas(view) |> render_hook("dragstart", %{"block-id" => "blk_email_step"})

        canvas(view)
        |> render_hook("drop", %{
          "block-id" => "blk_email_step",
          "parent-id" => "blk_wizard",
          "slot" => "body",
          "index" => "2"
        })

        assert slot_ids(latest_document(), "blk_wizard", "body") == [
                 "blk_variant",
                 "blk_track_conversion",
                 "blk_email_step"
               ]
      end

      # Sabotage: `Editor.to_index/1` returning the raw binary instead of an
      # integer - `Edit.apply/2` then refuses the command and the document
      # never changes.
      test "the index arrives from the DOM as a string and is still an index", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        canvas(view) |> render_hook("dragstart", %{"block-id" => "blk_control_pause"})

        canvas(view)
        |> render_hook("drop", %{
          "block-id" => "blk_control_pause",
          "parent-id" => "blk_wizard",
          "slot" => "body",
          "index" => "1"
        })

        assert slot_ids(latest_document(), "blk_wizard", "body") == [
                 "blk_email_step",
                 "blk_control_pause",
                 "blk_variant",
                 "blk_track_conversion"
               ]
      end

      # Sabotage: `Editor.commit/2` assigning the new document on the `:error`
      # arm too - a refused drop would then mutate the tree and this goes red.
      test "a drop the algebra refuses leaves the document alone", %{conn: conn} do
        {:ok, view, html} = mount_editor(conn)

        assert html =~ ~s(data-root="true"), "the root renders"

        refute has_element?(
                 view,
                 ~s([data-block-id="blk_wizard"] > .sb-node__chrome > .sb-node__remove)
               ),
               "the root is not deletable, so the affordance is absent"

        canvas(view) |> render_hook("dragstart", %{"block-id" => "blk_wizard"})

        canvas(view)
        |> render_hook("drop", %{
          "block-id" => "blk_wizard",
          "parent-id" => "blk_variant",
          "slot" => "otherwise",
          "index" => "0"
        })

        refute latest_document(), "the root cannot be moved, so the host is never notified"
      end
    end

    describe "palette drag-to-insert (sb-4nep)" do
      # The gesture the "+" path could not offer: a type dragged out of the
      # palette onto a gap. It reuses the pick's `:insert`, so what is asserted
      # here is that the session is built against a probe of the dragged TYPE
      # and that the drop lands the same command the pick lands.

      # Sabotage: `Editor.insert_drag_session/2` returning `session([], ...)`
      # unconditionally - nothing is stamped "ok" and the first two assertions
      # go red together.
      test "stamps the slots that accept the dragged type", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        html = canvas(view) |> render_hook("insert-dragstart", %{"type" => "core.wait"})

        assert slot_drop(html, "blk_wizard", "body") == "ok"
        assert slot_drop(html, "blk_variant", "otherwise") == "ok"

        assert slot_drop(html, "blk_track_conversion", "after") == "no",
               "an unresolvable parent has no slots/1, so it takes nothing (d5 rule 1)"
      end

      # Sabotage: asking for a probe of a fixed type rather than the dragged one
      # (`new_block(palette, "core.on_event")`) - `core.on_event` fits nowhere
      # in this document and the second half goes red.
      test "the stamped set is the probe block's own answer", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)
        document = EditorFixtures.signup_wizard()
        palette = EditorFixtures.palette()

        html = canvas(view) |> render_hook("insert-dragstart", %{"type" => "core.wait"})

        probe = Block.new("core.wait", config: %{"duration" => nil})
        expected = MapSet.new(Targets.droppable_slots_for(document, palette, probe))

        stamped =
          ~r/data-slot-name="([^"]+)" data-parent-id="([^"]+)"[^>]*data-drop="ok"/
          |> Regex.scan(html)
          |> MapSet.new(fn [_all, slot, parent] -> {parent, slot} end)

        assert stamped == expected

        # And a different type gets a different answer, which is what makes the
        # set above the *dragged* type's rather than any type's: `core.on_event`
        # is an attached handler, so nothing in this document takes one.
        html = canvas(view) |> render_hook("insert-dragstart", %{"type" => "core.on_event"})

        refute html =~ ~s(data-drop="ok")
      end

      # Sabotage: the "insert-drop" handler taking its position from
      # `palette_position` instead of from the params - nothing is armed here,
      # so the insert lands nowhere and the slot keeps its three children.
      test "a drop inserts a block of that type at the gap it landed on", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        canvas(view) |> render_hook("insert-dragstart", %{"type" => "core.wait"})

        canvas(view)
        |> render_hook("insert-drop", %{
          "type" => "core.wait",
          "parent-id" => "blk_wizard",
          "slot" => "body",
          "index" => "1"
        })

        document = latest_document()

        assert slot_types(document, "blk_wizard", "body") == [
                 "core.wait",
                 "core.wait",
                 "core.branch",
                 EditorFixtures.unknown_type()
               ]

        assert slot_ids(document, "blk_variant", "otherwise") == ["blk_control_pause"],
               "the insert is a copy of a type, not a move of anything"
      end

      # Sabotage: dropping the `assign(:drag, nil)` from the "insert-drop"
      # handler - the stamps survive a finished drag and the first assertion
      # finds data-drop still on the slot.
      test "the drop ends the session and clears any armed gap", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        armed =
          ~s(.sb-gap[data-parent-id="blk_variant"][data-slot="otherwise"][data-index="0"] ) <>
            ".sb-gap__add"

        assert render_click(element(view, armed)) =~ ~s(data-armed="true"),
               "the click arms a gap, which is the mode the drop has to clear"

        canvas(view) |> render_hook("insert-dragstart", %{"type" => "core.wait"})

        html =
          canvas(view)
          |> render_hook("insert-drop", %{
            "type" => "core.wait",
            "parent-id" => "blk_wizard",
            "slot" => "body",
            "index" => "0"
          })

        assert slot_drop(html, "blk_wizard", "body") == nil
        assert html =~ ~s(data-armed="false")

        refute html =~ ~s(data-armed="true"),
               "the gesture that landed said where, so the mode ends"
      end

      # Sabotage: `insert_drag_session/2`'s `:error` arm falling through to
      # `slot_verdicts/3` with no probe - it raises instead of refusing, and
      # the refusal this asserts never gets a chance to be wrong.
      test "a type the palette cannot resolve refuses everywhere and inserts nothing", %{
        conn: conn
      } do
        {:ok, view, _html} = mount_editor(conn)

        html =
          canvas(view)
          |> render_hook("insert-dragstart", %{"type" => EditorFixtures.unknown_type()})

        refute html =~ ~s(data-drop="ok"), "a type with no module accepts nowhere"
        assert slot_drop(html, "blk_wizard", "body") == "no"

        canvas(view)
        |> render_hook("insert-drop", %{
          "type" => EditorFixtures.unknown_type(),
          "parent-id" => "blk_wizard",
          "slot" => "body",
          "index" => "0"
        })

        refute latest_document(), "no block was minted, so the host is never notified"
      end

      # Sabotage: dropping `draggable="true"` from the palette entry - the row
      # is a click target again and the browser starts no drag at all, which is
      # precisely the defect sb-4nep is about.
      test "a palette entry is a drag source carrying its type name", %{conn: conn} do
        {:ok, _view, html} = mount_editor(conn)

        # A bare `draggable="true"` would prove nothing: the cards on the
        # canvas carry one too, and they are the gesture that already worked.
        assert Regex.match?(
                 ~r/class="sb-palette__pick"[^>]*draggable="true"[^>]*data-sb-drag-type="core.wait"/,
                 html
               ),
               "the entry names the type the drop will insert"
      end
    end

    defp slot_types(document, parent_id, slot) do
      document
      |> Document.blocks()
      |> Enum.find(&(&1.id == parent_id))
      |> Map.fetch!(:slots)
      |> Map.get(slot, [])
      |> Enum.map(& &1.type)
    end

    defp slot_ids(document, parent_id, slot) do
      document
      |> Document.blocks()
      |> Enum.find(&(&1.id == parent_id))
      |> Map.fetch!(:slots)
      |> Map.get(slot, [])
      |> Enum.map(& &1.id)
    end
  end
end
