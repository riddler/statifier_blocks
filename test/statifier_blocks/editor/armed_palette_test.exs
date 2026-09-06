# ADR-0005 decision 1: with `phoenix_live_view` absent the editor does not
# compile, so neither can a test that drives it. The `:liveview` tag on
# `StatifierBlocks.EditorLiveCase` excludes these from a headless *run*; this
# guard is what keeps them out of a headless *compile*.
if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.ArmedPaletteTest do
    @moduledoc """
    What an armed palette offers, and the line that counts it (sb-ym2w).

    One subject, in two kinds. A palette opened from a "+" is narrowed by the
    slot rather than by anything the author typed, and the promise the
    narrowing makes is that every row left on screen will land at that
    position. Both halves of the palette have to keep it:

      * a **type** is filtered by `Edit.Targets.droppable_slots_for/3` against
        the insert probe, which since sb-1c7g carries the entry's
        `default_config` - so a type refused for a READ rather than for its
        kind is filtered too, and the count line above the rows says so;
      * a **recipe** is filtered by its own question (ADR-0005 clause 3C):
        `insert/2` at the armed position, and `Recipe.within_reach?/2` over
        the commands it answers with. The pick's two checks, run before the
        row is drawn rather than after it is clicked.

    The count line is asserted against the rows it counts rather than against
    a written-down number, so a core type registered tomorrow does not fail a
    test about arithmetic. What is written down is the denominator, because a
    scan that silently matched nothing would make the comparison vacuous.
    """

    use StatifierBlocks.EditorLiveCase

    alias StatifierBlocks.InsertProbeFixtures

    defp canvas(view), do: element(view, "#sb-canvas")

    defp arm(view, parent_id, slot, index) do
      render_hook(canvas(view), "palette-open", %{
        "parent-id" => parent_id,
        "slot" => slot,
        "index" => to_string(index)
      })
    end

    # The count line's rendered text, with the markup around it taken off, so
    # an assertion is about what an author reads.
    defp count_text(html) do
      [_whole, text] = Regex.run(~r{<p class="sb-palette__count"[^>]*>(.*?)</p>}s, html)
      String.trim(text)
    end

    defp type_rows(html) do
      ~r/<li data-type="([^"]+)"/
      |> Regex.scan(html)
      |> Enum.map(&List.last/1)
    end

    defp types_in(document, block_id, slot) do
      document
      |> Document.blocks()
      |> Enum.find(&(&1.id == block_id))
      |> Map.fetch!(:slots)
      |> Map.get(slot, [])
      |> Enum.map(& &1.type)
    end

    # The deadline recipe's two positions, as `DeadlinePickTest` documents
    # them: a group with an interrupts rail, and a sequence with none.
    #
    #   blk_root (core.sequence)
    #     body: [blk_group, blk_plain]
    defp recipe_document do
      group = Block.new("core.group", id: "blk_group", slots: %{"body" => []})
      plain = Block.new("core.sequence", id: "blk_plain")

      Document.new(
        Block.new("core.sequence", id: "blk_root", slots: %{"body" => [group, plain]}),
        id: "bdoc_armed_palette"
      )
    end

    defp mount_probe(conn) do
      mount_editor(conn,
        document: InsertProbeFixtures.document(),
        palette: InsertProbeFixtures.palette(),
        datamodel: InsertProbeFixtures.datamodel()
      )
    end

    describe "the fit line" do
      # The line and the rows are two readings of one acceptance set, and the
      # defect this pins is the pair disagreeing: rows filtered on the probe's
      # full verdict under a numerator counted some other way. `settle_final`
      # is the case that tells the two apart - it fits the slot structurally
      # and fails the read, so a numerator computed from anything but the set
      # the rows came from counts it.
      #
      # Sabotage: `count_line/3` computing `shown_types` from `groups` rather
      # than from `visible` - the numerator reads 19 over a shorter list.
      test "counts the types that will land, reads included", %{conn: conn} do
        {:ok, view, html} = mount_probe(conn)

        assert count_text(html) == "19 block types", "the scan saw the whole palette"

        armed = arm(view, "blk_GRP", "body", 0)
        rows = type_rows(armed)

        refute "cards.settle_final" in rows,
               "the slot refuses a configured block of this type, so it is not offered"

        assert "core.wait" in rows, "and everything the slot does take is still offered"
        assert length(rows) < 19
        assert count_text(armed) == "#{length(rows)} of 19 block types fit here"
      end
    end

    describe "a recipe at an armed target" do
      # Clause 3C's refusal was reachable only by clicking: the row was on
      # screen at every position, and picking it wrote nothing and said
      # nothing. Filtering it is the same answer given before the click.
      #
      # Sabotage: `accepted?/3` passing every recipe again - the row survives
      # the armed palette and this goes red.
      test "an arrangement that cannot land here is not offered", %{conn: conn} do
        {:ok, view, html} =
          mount_editor(conn, document: recipe_document(), palette: Palette.core())

        assert html =~ ~s(data-recipe="deadline"), "unarmed, the whole palette is on screen"

        armed = arm(view, "blk_plain", "body", 0)

        refute armed =~ ~s(data-recipe="deadline"),
               "a sequence has no interrupts rail, so `insert/2` refuses this position"

        refute count_text(armed) =~ "recipe",
               "and the line does not go on naming a row that is not there"
      end

      # The other half of the same filter, and the one that says it filters on
      # the recipe's own answer rather than on the kind: a recipe row at a
      # position that takes it is still a row, and still a pick.
      #
      # Sabotage: `recipe_lands?/4` answering `false` for everything - the row
      # is gone from both positions and the first assertion here goes red.
      test "one that can land is offered, and inserts", %{conn: conn} do
        {:ok, view, _html} =
          mount_editor(conn, document: recipe_document(), palette: Palette.core())

        armed = arm(view, "blk_group", "body", 0)

        assert armed =~ ~s(data-recipe="deadline")
        assert count_text(armed) =~ "1 recipe"

        view |> with_target("#editor") |> render_click("palette-pick", %{"recipe" => "deadline"})

        assert %Document{} = changed = latest_document()
        assert types_in(changed, "blk_group", "body") == ["core.send"]
        assert types_in(changed, "blk_group", "interrupts") == ["core.on_event"]
      end
    end
  end
end
