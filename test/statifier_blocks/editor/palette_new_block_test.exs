# ADR-0005 decision 1: with `phoenix_live_view` absent the editor does not
# compile, so neither can a test that drives it. The `:liveview` tag on
# `StatifierBlocks.EditorLiveCase` excludes these from a headless *run*; this
# guard is what keeps them out of a headless *compile*.
if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.PaletteNewBlockTest do
    @moduledoc """
    The editor's insert delegates to `StatifierBlocks.Palette.new_block/2`
    (sb-zjyv), and the block an author gets is the one that function returns.

    The helper used to be private to the editor. This is the oracle that the
    move changed nothing an author can see: what a palette pick puts in the
    document is `new_block/2`'s block, id apart - an id is minted per gesture
    (decision 2), so it is the one field two calls may not share.

    Both insert paths reach `insert_from_palette/3` - the pick here, and the
    drop, which routes through it - so this covers the one delegation site
    the two of them share. The probe's own delegation is
    `StatifierBlocks.Editor.InsertProbeTest`'s subject.
    """

    use StatifierBlocks.EditorLiveCase

    alias StatifierBlocks.Palette

    defp document do
      Document.new(Block.new("core.sequence", id: "blk_root"), id: "bdoc_new_block")
    end

    defp add_button(parent_id, slot, index) do
      ~s([data-parent-id="#{parent_id}"][data-slot="#{slot}"][data-index="#{index}"] .sb-gap__add)
    end

    defp inserted(document, block_id, slot) do
      document
      |> Document.blocks()
      |> Enum.find(&(&1.id == block_id))
      |> Map.fetch!(:slots)
      |> Map.get(slot, [])
      |> List.first()
    end

    describe "a pick from the palette" do
      # Sabotage: `insert_from_palette/3` building its own block (schema
      # defaults dropped, or `type_version` left at Block.new's default)
      # instead of calling `Palette.new_block/2` - this goes red.
      test "puts down exactly the block Palette.new_block/2 returns", %{conn: conn} do
        palette = Palette.core()
        {:ok, view, _html} = mount_editor(conn, document: document(), palette: palette)

        view |> element(add_button("blk_root", "body", 0)) |> render_click()

        view
        |> with_target("#editor")
        |> render_click("palette-pick", %{"type" => "core.send"})

        assert %Document{} = changed = latest_document()
        assert %Block{} = block = inserted(changed, "blk_root", "body")

        assert {:ok, expected} = Palette.new_block(palette, "core.send")
        assert %{block | id: expected.id} == expected
      end

      # Sabotage: `Palette.new_block/2` answering `{:ok, _}` for a name no
      # entry carries - the editor's unknown-type arm stops firing and the
      # document changes, so this goes red.
      test "a type the palette does not carry inserts nothing", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, document: document(), palette: Palette.core())

        view |> element(add_button("blk_root", "body", 0)) |> render_click()

        view
        |> with_target("#editor")
        |> render_click("palette-pick", %{"type" => "no.such.type"})

        assert inserted(latest_document() || document(), "blk_root", "body") == nil
      end
    end
  end
end
