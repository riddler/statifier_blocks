# ADR-0005 decision 1: with `phoenix_live_view` absent the editor does not
# compile, so neither can a test that drives it. The `:liveview` tag on
# `StatifierBlocks.EditorLiveCase` excludes these from a headless *run*; this
# guard is what keeps them out of a headless *compile*.
if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.InsertProbeTest do
    @moduledoc """
    The insert probe carries the palette entry's `default_config`, so a read
    declared on a config field is asked at insert time (sb-1c7g).

    Both insert paths mint a probe block of the candidate type and ask
    `StatifierBlocks.Edit.Targets` about it - the drag from the palette, and
    the "+" that filters the palette browser to what the armed slot takes.
    Neither can ask about a read whose path the probe does not carry, and a
    `{:path, _}` field defaulting to `""` carries none. What is asserted
    here is that the entry's declaration reaches both probes and nothing
    else: the pure verdict the probes ask for is
    `StatifierBlocks.Edit.TargetsReasonTest`'s subject and not this file's.
    """

    use StatifierBlocks.EditorLiveCase

    alias StatifierBlocks.{Assignability, InsertProbeFixtures}
    alias StatifierBlocks.Edit.Targets

    defp canvas(view), do: element(view, "#sb-canvas")

    defp mount_reproduction(conn) do
      mount_editor(conn,
        document: InsertProbeFixtures.document(),
        palette: InsertProbeFixtures.palette(),
        datamodel: InsertProbeFixtures.datamodel()
      )
    end

    defp slot_drop(html, parent_id, slot) do
      case Regex.run(
             ~r/data-slot-name="#{slot}" data-parent-id="#{parent_id}"[^>]*data-drop="(\w+)"/,
             html
           ) do
        [_all, state] -> state
        nil -> nil
      end
    end

    describe "the finding the probe is standing in for" do
      # Sabotage: pointing the fixture's `expects:` at `Settleable`, which
      # `cards.credit_txn` does satisfy - this goes red, and with it the
      # premise every assertion below rests on.
      test "a configured block of this type is refused from the slot, with a type_mismatch" do
        document = InsertProbeFixtures.document()
        palette = InsertProbeFixtures.palette()
        ctx = %{datamodel: InsertProbeFixtures.datamodel()}

        configured =
          Block.new("cards.settle_final",
            id: "blk_FIN",
            config: %{"subject" => "cards.current_txn"}
          )

        assert {:error, findings} =
                 Assignability.check(palette, document, {"blk_GRP", "body", 0}, configured, ctx)

        assert Enum.any?(
                 findings,
                 &match?(
                   {:type_mismatch, "blk_FIN", _ref, _held, _expected, "cards.current_txn"},
                   &1
                 )
               )
      end
    end

    describe "the drag path" do
      # Sabotage: `insert_drag_session/2` calling `new_block/2` again instead
      # of `probe/2` - this goes red on the first assertion, which is the
      # defect sb-1c7g reports: the probe declares no read and the slot lights.
      test "greys a slot whose subject type does not satisfy the dragged block's read", %{
        conn: conn
      } do
        {:ok, view, _html} = mount_reproduction(conn)

        html = canvas(view) |> render_hook("insert-dragstart", %{"type" => "cards.settle_final"})

        assert slot_drop(html, "blk_GRP", "body") == "no"
      end

      # Sabotage: `probe/2` merging `default_config` *under* the schema
      # defaults instead of over them - the `""` wins, the read goes silent
      # again, and the stamped set stops matching the configured probe's.
      test "the stamped set is the probe-with-default-config's own answer", %{conn: conn} do
        {:ok, view, _html} = mount_reproduction(conn)

        html = canvas(view) |> render_hook("insert-dragstart", %{"type" => "cards.settle_final"})

        expected =
          InsertProbeFixtures.document()
          |> Targets.droppable_slots_for(
            InsertProbeFixtures.palette(),
            Block.new("cards.settle_final", config: %{"subject" => "cards.current_txn"}),
            %{datamodel: InsertProbeFixtures.datamodel()}
          )
          |> MapSet.new()

        stamped =
          ~r/data-slot-name="([^"]+)" data-parent-id="([^"]+)"[^>]*data-drop="ok"/
          |> Regex.scan(html)
          |> MapSet.new(fn [_all, slot, parent] -> {parent, slot} end)

        assert stamped == expected
        assert expected != MapSet.new()
      end

      # Sabotage: `probe/2` merging the entry's `default_config` into every
      # type's probe rather than its own - `core.wait` declares no reads at
      # all, so a slot that darkened for it would be darkening for someone
      # else's declaration.
      test "a block with no config-dependent read is unaffected", %{conn: conn} do
        {:ok, view, _html} = mount_reproduction(conn)

        html = canvas(view) |> render_hook("insert-dragstart", %{"type" => "core.wait"})

        assert slot_drop(html, "blk_GRP", "body") == "ok"
      end
    end

    describe "the click-to-insert path" do
      # Sabotage: `accepted_types/3` calling `new_block/2` again - this goes
      # red on the first assertion, which is the same defect through the "+"
      # rather than through the drag.
      test "filters the type out of the palette the armed slot offers", %{conn: conn} do
        {:ok, view, _html} = mount_reproduction(conn)

        html =
          canvas(view)
          |> render_hook("palette-open", %{
            "parent-id" => "blk_GRP",
            "slot" => "body",
            "index" => "0"
          })

        refute html =~ ~s(data-type="cards.settle_final"),
               "the slot refuses a configured block of this type, so the palette does not offer it"

        assert html =~ ~s(data-type="core.wait"),
               "and it still offers everything the slot does take"
      end
    end
  end
end
